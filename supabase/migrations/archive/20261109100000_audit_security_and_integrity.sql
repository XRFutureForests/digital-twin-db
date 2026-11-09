-- =============================================================================
-- Audit 2026-11-09: function privileges, audit log, child-row ownership,
-- variant integrity, licence in ue_trees, duplicate indexes, JWT secret, height classes (XRFF-661)
-- =============================================================================
-- PostgREST serves the base schemas too (PGRST_DB_SCHEMAS lists shared, trees,
-- sensor, ...; the portal and open-data-connector use them through a profile
-- header). PostgreSQL lets PUBLIC execute every new function, so every
-- SECURITY DEFINER function in those schemas was callable anonymously as
-- POST /rest/v1/rpc/<name> with Content-Profile: shared -- refresh_lookup
-- reloaded lookups from CSV, create_audit_log wrote audit rows, and
-- get_audit_history read the audit log past row-level security.
--
-- Mirrored to init 87-audit-security-and-integrity.sql.
-- =============================================================================

SET search_path TO public, shared, trees, sensor, extensions;

-- -----------------------------------------------------------------------------
-- 1. Functions in the base schemas: closed by default, opened by name
-- -----------------------------------------------------------------------------
-- service_role (connectors, the job runner through postgres, which is a member)
-- keeps everything. anon and authenticated get back the SECURITY INVOKER
-- functions, which run with the caller's own rights and are what the public
-- views and policies call, plus the named DEFINER helpers the row-level
-- security policies call. Trigger functions need no EXECUTE grant to fire.
DO $$
DECLARE
    s text;
    f regprocedure;
BEGIN
    FOREACH s IN ARRAY ARRAY['shared', 'trees', 'sensor', 'point_clouds',
                             'environments', 'imagery', 'forest_floor'] LOOP
        EXECUTE format('REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA %I FROM PUBLIC, anon, authenticated', s);
        EXECUTE format('GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA %I TO service_role', s);
        EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA %I GRANT EXECUTE ON FUNCTIONS TO service_role', s);
    END LOOP;

    -- PUBLIC's EXECUTE on a new function is a global default; a per-schema
    -- ALTER DEFAULT PRIVILEGES cannot take it away, only a global one can.
    -- Functions in public keep their explicit defaults for the API roles.
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

    FOR f IN
        SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname IN ('shared', 'trees', 'sensor', 'point_clouds', 'environments', 'imagery', 'forest_floor')
           AND p.prokind = 'f' AND NOT p.prosecdef AND p.prorettype <> 'trigger'::regtype
    LOOP
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', f);
    END LOOP;
END $$;

-- The policy helpers. Each returns only what the caller's own token entitles
-- it to; DEFINER so the policies can read campaigns and team membership.
GRANT EXECUTE ON FUNCTION
    shared.has_restricted_campaigns(),
    shared.hidden_observation_ids(),
    shared.hidden_point_cloud_ids(),
    shared.hidden_qsm_ids(),
    shared.hidden_sensor_ids(),
    shared.hidden_tree_ids(),
    shared.is_admin(),
    shared.is_contributor(),
    shared.is_curator(),
    shared.my_curated_team_ids(),
    shared.my_team_ids(),
    shared.readable_campaign_ids(),
    shared.writable_campaign_ids(),
    shared.writable_observation_ids()
TO anon, authenticated;
GRANT EXECUTE ON FUNCTION shared.may_manage_role(text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. Audit log: curators read it all, everyone else only their own changes
-- -----------------------------------------------------------------------------
-- The old policy also showed rows with user_id IS NULL -- which was every row,
-- since scripts write without a token -- to any signed-in account, including
-- the values of datasets that account may not read.
DROP POLICY IF EXISTS "Users can view their own audit logs" ON shared.audit_log;
CREATE POLICY "Curators read all, others their own changes" ON shared.audit_log
    FOR SELECT TO authenticated
    USING (shared.is_curator() OR user_id = (SELECT auth.uid())::text);

-- Who made the change: the account when there is one, otherwise the API role
-- (service_role) or the database role a script connected as.
CREATE OR REPLACE FUNCTION shared.create_audit_log(
    table_name_param character varying, variant_id_param integer,
    field_name_param character varying, old_value_param text, new_value_param text,
    change_reason_param text DEFAULT NULL::text,
    change_type_param character varying DEFAULT 'field_update'::character varying)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_audit_id BIGINT;
BEGIN
    INSERT INTO shared.audit_log (
        field_name, old_value, new_value, change_reason,
        user_id, change_type, ip_address
    ) VALUES (
        field_name_param, old_value_param, new_value_param, change_reason_param,
        coalesce(auth.uid()::text, nullif(auth.jwt() ->> 'role', ''), session_user::text),
        change_type_param, inet_client_addr()
    )
    RETURNING audit_log_id INTO v_audit_id;
    CASE table_name_param
        WHEN 'point_clouds' THEN
            INSERT INTO shared.audit_log_point_clouds (audit_log_id, point_cloud_id) VALUES (v_audit_id, variant_id_param);
        WHEN 'trees' THEN
            INSERT INTO shared.audit_log_trees (audit_log_id, tree_id) VALUES (v_audit_id, variant_id_param);
        WHEN 'environments' THEN
            INSERT INTO shared.audit_log_environments (audit_log_id, environment_id) VALUES (v_audit_id, variant_id_param);
        WHEN 'stems' THEN
            INSERT INTO shared.audit_log_stems (audit_log_id, stem_id) VALUES (v_audit_id, variant_id_param);
        WHEN 'phenology_observations' THEN
            INSERT INTO shared.audit_log_phenology_observations (audit_log_id, phenology_observation_id) VALUES (v_audit_id, variant_id_param);
    END CASE;
    RETURN v_audit_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION shared.create_audit_log(character varying, integer, character varying, text, text, text, character varying) FROM PUBLIC, anon, authenticated;

-- revert_field_change wrote an audit row saying "revert" and returned TRUE
-- without changing the value. Nothing calls it; a correction is an UPDATE
-- with app.change_reason set, which the audit trigger records.
DROP FUNCTION IF EXISTS shared.revert_field_change(bigint, text);

-- -----------------------------------------------------------------------------
-- 3. Child rows: a contributor may add them only to a dataset it may write
-- -----------------------------------------------------------------------------
-- trees and sensors already carry a restrictive "Dataset owner: insert"
-- policy; their child tables only checked is_contributor(), so a contributor
-- could add a stem to another team's tree and change that team's stand
-- summaries. The helpers return nothing when no campaign belongs to a team or
-- the caller is a curator, so the check costs nothing until teams exist.
CREATE OR REPLACE FUNCTION shared.unwritable_tree_ids()
RETURNS SETOF integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
    SELECT t.tree_id FROM trees.trees t
     WHERE NOT shared.is_curator()
       AND EXISTS (SELECT 1 FROM shared.campaigns c WHERE c.owner_team_id IS NOT NULL)
       AND t.campaign_id IS NOT NULL
       AND t.campaign_id NOT IN (SELECT shared.writable_campaign_ids());
$$;

CREATE OR REPLACE FUNCTION shared.unwritable_sensor_ids()
RETURNS SETOF integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
    SELECT s.sensor_id FROM sensor.sensors s
     WHERE NOT shared.is_curator()
       AND EXISTS (SELECT 1 FROM shared.campaigns c WHERE c.owner_team_id IS NOT NULL)
       AND s.campaign_id IS NOT NULL
       AND s.campaign_id NOT IN (SELECT shared.writable_campaign_ids());
$$;

CREATE OR REPLACE FUNCTION shared.unwritable_point_cloud_ids()
RETURNS SETOF integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
    SELECT pc.point_cloud_id FROM point_clouds.point_clouds pc
     WHERE NOT shared.is_curator()
       AND EXISTS (SELECT 1 FROM shared.campaigns c WHERE c.owner_team_id IS NOT NULL)
       AND pc.campaign_id IS NOT NULL
       AND pc.campaign_id NOT IN (SELECT shared.writable_campaign_ids());
$$;

CREATE OR REPLACE FUNCTION shared.unwritable_qsm_ids()
RETURNS SETOF bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
    SELECT q.qsm_id FROM trees.qsms q
     WHERE q.tree_id IN (SELECT shared.unwritable_tree_ids())
        OR q.point_cloud_id IN (SELECT shared.unwritable_point_cloud_ids());
$$;

REVOKE EXECUTE ON FUNCTION shared.unwritable_tree_ids(), shared.unwritable_sensor_ids(),
    shared.unwritable_point_cloud_ids(), shared.unwritable_qsm_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION shared.unwritable_tree_ids(), shared.unwritable_sensor_ids(),
    shared.unwritable_point_cloud_ids(), shared.unwritable_qsm_ids() TO authenticated, service_role;

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('trees',  'stems',                  'tree_id NOT IN (SELECT shared.unwritable_tree_ids())'),
        ('trees',  'roots',                  'tree_id NOT IN (SELECT shared.unwritable_tree_ids())'),
        ('trees',  'crown_foliage_profiles', 'tree_id NOT IN (SELECT shared.unwritable_tree_ids())'),
        ('trees',  'phenology_observations', 'tree_id NOT IN (SELECT shared.unwritable_tree_ids())'),
        ('trees',  'qsms',                   '(tree_id IS NULL OR tree_id NOT IN (SELECT shared.unwritable_tree_ids())) AND (point_cloud_id IS NULL OR point_cloud_id NOT IN (SELECT shared.unwritable_point_cloud_ids()))'),
        ('trees',  'qsm_cylinders',          'qsm_id NOT IN (SELECT shared.unwritable_qsm_ids())'),
        ('trees',  'tree_graph_edges',       'qsm_id NOT IN (SELECT shared.unwritable_qsm_ids())'),
        ('sensor', 'sensor_readings',        'sensor_id NOT IN (SELECT shared.unwritable_sensor_ids())')
    ) AS v(s, t, chk)
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Dataset owner: insert" ON %I.%I', r.s, r.t);
        EXECUTE format('CREATE POLICY "Dataset owner: insert" ON %I.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (%s)',
                       r.s, r.t, r.chk);
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 4. A tree row's location, scenario and type are its variant's
-- -----------------------------------------------------------------------------
-- trees.location_id, scenario_id and variant_type_id all follow from
-- variant_id, and variants.location_id from scenario_id. They stay (clients
-- filter on them), but composite foreign keys now make a disagreeing row
-- impossible and carry changes along. variant_id becomes required: a tree
-- without one was invisible to every ?variant_id= query, and deleting a
-- variant used to leave its trees behind with a NULL variant.
ALTER TABLE shared.scenarios
    ADD CONSTRAINT scenarios_scenario_location_key UNIQUE (scenario_id, location_id);
ALTER TABLE shared.variants
    DROP CONSTRAINT variants_scenario_id_fkey,
    ADD CONSTRAINT variants_scenario_location_fkey FOREIGN KEY (scenario_id, location_id)
        REFERENCES shared.scenarios (scenario_id, location_id) ON UPDATE CASCADE ON DELETE CASCADE,
    ADD CONSTRAINT variants_identity_key UNIQUE (variant_id, scenario_id, location_id, variant_type_id);

-- Writers need to give only variant_id; the copies are filled from it.
CREATE OR REPLACE FUNCTION trees.fill_from_variant()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $$
BEGIN
    SELECT coalesce(NEW.location_id, v.location_id),
           coalesce(NEW.scenario_id, v.scenario_id),
           coalesce(NEW.variant_type_id, v.variant_type_id)
      INTO NEW.location_id, NEW.scenario_id, NEW.variant_type_id
      FROM shared.variants v
     WHERE v.variant_id = NEW.variant_id;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION trees.fill_from_variant() IS
    'Fills a new tree row''s location_id, scenario_id and variant_type_id from its variant when the writer leaves them out. A value the writer gives must still match the variant (trees_variant_fkey).';
CREATE TRIGGER trg_trees_fill_from_variant
    BEFORE INSERT ON trees.trees
    FOR EACH ROW EXECUTE FUNCTION trees.fill_from_variant();

ALTER TABLE trees.trees
    ALTER COLUMN variant_id SET NOT NULL,
    ALTER COLUMN scenario_id SET NOT NULL,
    DROP CONSTRAINT trees_variant_id_fkey,
    DROP CONSTRAINT trees_scenario_id_fkey,
    ADD CONSTRAINT trees_variant_fkey FOREIGN KEY (variant_id, scenario_id, location_id, variant_type_id)
        REFERENCES shared.variants (variant_id, scenario_id, location_id, variant_type_id)
        ON UPDATE CASCADE ON DELETE CASCADE;

-- -----------------------------------------------------------------------------
-- 5. ue_trees carries each tree's licence and citation
-- -----------------------------------------------------------------------------
-- A measured tree takes them from its campaign; a projected tree (no campaign)
-- from the campaign of the most recent measurement of the same physical tree
-- (tree_entity_id). Appended at the end so existing struct parsers keep working.
CREATE OR REPLACE VIEW public.ue_trees WITH (security_invoker = on) AS
 SELECT t.tree_id,
    t.tree_entity_id,
    t.location_id,
    l.location_name,
    s.scenario_id,
    s.scenario_name,
    t.variant_id,
    v.variant_name,
    v.simulation_year,
    vt.variant_type_name,
    sp.common_name AS species_name,
    sp.scientific_name,
    t.height_m,
    t.crown_width_m,
    t.crown_base_height_m,
    st.dbh_cm,
    t.age_years,
    t.health_score,
    COALESCE((t.crown_base_height_m / NULLIF(t.height_m, 0::numeric)) > 0.6, false) AS has_competition,
    t.sensor_ref,
    (EXISTS ( SELECT 1
           FROM sensor.sensor_tree_links stl
          WHERE stl.tree_id = t.tree_id)) AS has_sensors,
    st_x(COALESCE(t.position_original, st_transform(t."position", l.crs_epsg))) AS original_x,
    st_y(COALESCE(t.position_original, st_transform(t."position", l.crs_epsg))) AS original_y,
    COALESCE(t.source_crs,
        CASE
            WHEN t.position_original IS NULL AND t."position" IS NOT NULL THEN l.crs_epsg
            ELSE NULL::integer
        END) AS source_crs,
    st_y(t."position") AS latitude,
    st_x(t."position") AS longitude,
    v.sort_order,
    v.time_delta_yrs,
    v.variant_type_id,
    s.scenario_code,
    s.management_regime_id,
    mr.management_regime_name,
    s.climate_pathway_id,
    cp.climate_pathway_name,
    t.tree_status_id,
    ts.tree_status_name,
    sp.leaf_type,
    c.campaign_id,
    c.licence,
    c.citation,
    c.doi
   FROM trees.trees t
     LEFT JOIN shared.locations l ON t.location_id = l.location_id
     LEFT JOIN shared.variants v ON t.variant_id = v.variant_id
     LEFT JOIN shared.scenarios s ON v.scenario_id = s.scenario_id
     LEFT JOIN shared.variant_types vt ON v.variant_type_id = vt.variant_type_id
     LEFT JOIN shared.species sp ON t.species_id = sp.species_id
     LEFT JOIN trees.stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
     LEFT JOIN shared.management_regimes mr ON mr.management_regime_id = s.management_regime_id
     LEFT JOIN shared.climate_pathways cp ON cp.climate_pathway_id = s.climate_pathway_id
     LEFT JOIN trees.tree_status ts ON ts.tree_status_id = t.tree_status_id
     LEFT JOIN LATERAL ( SELECT m.campaign_id
           FROM trees.trees m
          WHERE t.campaign_id IS NULL AND m.tree_entity_id = t.tree_entity_id AND m.campaign_id IS NOT NULL
          ORDER BY m.measurement_date DESC NULLS LAST, m.tree_id DESC
         LIMIT 1) src ON true
     LEFT JOIN shared.campaigns c ON c.campaign_id = COALESCE(t.campaign_id, src.campaign_id);

COMMENT ON COLUMN public.ue_trees.licence IS
    'Licence of the data behind this row: the tree''s campaign, or for a projection the campaign of the latest measurement of the same tree. NULL when neither exists.';

-- -----------------------------------------------------------------------------
-- 6. Duplicate indexes on trees.trees
-- -----------------------------------------------------------------------------
-- idx_trees_scenario_id repeats idx_trees_scenario; idx_trees_location is the
-- leading column of idx_trees_location_scenario; idx_trees_variant the leading
-- column of trees_variant_entity_key.
DROP INDEX IF EXISTS trees.idx_trees_scenario_id;
DROP INDEX IF EXISTS trees.idx_trees_location;
DROP INDEX IF EXISTS trees.idx_trees_variant;

-- -----------------------------------------------------------------------------
-- 7. The JWT signing secret is no longer a database setting
-- -----------------------------------------------------------------------------
-- The Supabase template's jwt.sql stored it with ALTER DATABASE ... SET
-- app.settings.jwt_secret, which every role that can connect may read with
-- current_setting() -- dashboard_reader included -- and then sign a
-- service_role token. Nothing in the database or the workspace reads it;
-- PostgREST and GoTrue take the secret from their environment.
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I RESET "app.settings.jwt_secret"', current_database());
    EXECUTE format('ALTER DATABASE %I RESET "app.settings.jwt_exp"', current_database());
END $$;

-- -----------------------------------------------------------------------------
-- 8. A tree's height class follows its height
-- -----------------------------------------------------------------------------
-- assign_height_class() filled the class only while it was NULL, so every
-- writer that changed height_m without clearing the class (fill_missing_heights,
-- the canopy height fix, the Pathfinder upsert) left the old class behind:
-- 229 trees on dev on 2026-11-09. The class is a function of the height, so it
-- is now recomputed whenever there is a height; without one, a class given by
-- the writer (a field estimate) stays.
CREATE OR REPLACE FUNCTION trees.assign_height_class()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $function$
BEGIN
    IF NEW.height_m IS NOT NULL THEN
        SELECT c.height_class_id INTO NEW.height_class_id
          FROM trees.phanerophyte_height_classes c
         WHERE (c.min_height_m IS NULL OR NEW.height_m >= c.min_height_m)
           AND (c.max_height_m IS NULL OR NEW.height_m < c.max_height_m)
         LIMIT 1;
    END IF;
    RETURN NEW;
END;
$function$;

UPDATE trees.trees t
   SET height_class_id = c.height_class_id
  FROM trees.phanerophyte_height_classes c
 WHERE t.height_m IS NOT NULL
   AND (c.min_height_m IS NULL OR t.height_m >= c.min_height_m)
   AND (c.max_height_m IS NULL OR t.height_m < c.max_height_m)
   AND t.height_class_id IS DISTINCT FROM c.height_class_id;

NOTIFY pgrst, 'reload schema';
