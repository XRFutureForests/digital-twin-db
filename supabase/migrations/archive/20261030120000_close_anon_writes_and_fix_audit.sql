-- =============================================================================
-- Close three writes the role model never meant to allow, and revive two audits
-- =============================================================================
-- Found 2026-10-30 by the documentation audit, checked against pg_proc /
-- has_*_privilege before writing this.
--
-- 1. Five connector RPCs were writable with the public anon key.
--    bulk_insert_readings, bulk_upsert_sensors, set_location_attributes,
--    upsert_environment and refresh_soil_aggregates are SECURITY DEFINER, so
--    they write as their owner whoever calls them, and none checks the
--    caller's role. EXECUTE was granted to anon and authenticated. The anon
--    key is public by design -- Unreal ships with it, the portal shows it --
--    so anyone could insert readings, upsert sensors, overwrite site
--    attributes and environments. Every caller (aquarius-connector,
--    open-data-connector, scripts/import/ingest_sensor_data.py) sends the
--    service_role key, so EXECUTE now goes to service_role only. A user-facing
--    write path, if one is ever wanted, gets its own role check -- not a grant.
--
-- 2. trees.growth_simulations was writable by any signed-in account.
--    RLS is off on it (reads go through the SECURITY DEFINER public view), and
--    authenticated held INSERT and UPDATE -- so since the 2026-10-30 decision
--    "no role = read-only" an account with no role could still write SILVA
--    trajectories with `Content-Profile: trees`. The only writer is
--    silva-connector, over libpq as postgres -- and postgres (not a superuser
--    here) held that INSERT/UPDATE only through its membership in
--    authenticated. So the grants move: off anon and authenticated, onto
--    postgres directly, which is the access silva-connector had before.
--
-- 3. Point-cloud and phenology updates were never audited.
--    shared.audit_update_trigger() dispatches on TG_TABLE_NAME, and two of its
--    WHEN labels still carried the pre-2026-09-23 names ('pointclouds',
--    'phenologyobservations'). Since the rename the trigger found no record id
--    for those tables and returned without logging; both junction tables held
--    0 rows. The labels are rewritten in the function's own definition
--    (pg_get_functiondef, so SECURITY DEFINER and search_path stay as they
--    are), with a check that each old label occurs exactly twice -- once in the
--    record-id CASE, once in the field CASE.
--
-- 4. 22 table/column COMMENTs still used pre-rename names; they feed the
--    generated data dictionary, so they are rewritten (section 4 below).
--
-- Mirrored to init 70-close-anon-writes-and-fix-audit.sql.
-- =============================================================================

-- 1 ---------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.bulk_insert_readings(jsonb)                                                    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bulk_upsert_sensors(jsonb)                                                     FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.refresh_soil_aggregates(integer, integer, integer, boolean)                     FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone)
                                                                                                                  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text)
                                                                                                                  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.bulk_insert_readings(jsonb)                                                     TO service_role;
GRANT EXECUTE ON FUNCTION public.bulk_upsert_sensors(jsonb)                                                      TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_soil_aggregates(integer, integer, integer, boolean)                      TO service_role;
GRANT EXECUTE ON FUNCTION public.set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone)
                                                                                                                  TO service_role;
GRANT EXECUTE ON FUNCTION public.upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text)
                                                                                                                  TO service_role;

-- 2 ---------------------------------------------------------------------------

REVOKE INSERT, UPDATE, DELETE ON trees.growth_simulations FROM anon, authenticated;
GRANT INSERT, UPDATE ON trees.growth_simulations TO postgres;
GRANT USAGE, SELECT ON SEQUENCE trees.growth_simulations_growth_simulation_id_seq TO postgres;

-- 3 ---------------------------------------------------------------------------

DO $$
DECLARE
    v_def  text := pg_get_functiondef('shared.audit_update_trigger()'::regprocedure);
    v_hits int;
BEGIN
    -- Already applied on a re-run.
    IF v_def LIKE '%WHEN ''point_clouds'' THEN%' THEN
        RETURN;
    END IF;

    v_hits := (length(v_def) - length(replace(v_def, 'WHEN ''pointclouds'' THEN', ''))) / length('WHEN ''pointclouds'' THEN');
    IF v_hits <> 2 THEN
        RAISE EXCEPTION 'audit_update_trigger: % WHEN ''pointclouds'' labels, expected 2 -- body changed, patch by hand', v_hits;
    END IF;
    v_hits := (length(v_def) - length(replace(v_def, 'WHEN ''phenologyobservations'' THEN', ''))) / length('WHEN ''phenologyobservations'' THEN');
    IF v_hits <> 2 THEN
        RAISE EXCEPTION 'audit_update_trigger: % WHEN ''phenologyobservations'' labels, expected 2 -- body changed, patch by hand', v_hits;
    END IF;

    v_def := replace(v_def, 'WHEN ''pointclouds'' THEN', 'WHEN ''point_clouds'' THEN');
    v_def := replace(v_def, 'WHEN ''phenologyobservations'' THEN', 'WHEN ''phenology_observations'' THEN');
    EXECUTE v_def;
END;
$$;

-- 4 ---------------------------------------------------------------------------
-- Table and column COMMENTs still named 22 relations the pre-2026-09-23 way
-- (trees.SimulationRuns, shared.Locations, sensor.SensorTypes, trees.QSMs,
-- ...). docs/database-dictionary.md is generated from these comments, so they
-- are the documentation now. Each schema-qualified CamelCase name is turned
-- into snake_case and replaced only when a relation of that name exists, so a
-- word that merely looks like a name is left alone. Idempotent: a re-run finds
-- nothing to match.

DO $$
DECLARE
    d       record;
    m       text[];
    v_new   text;
    v_snake text;
BEGIN
    FOR d IN
        SELECT c.oid, c.relkind, ds.objsubid, ds.description, a.attname
          FROM pg_description ds
          JOIN pg_class c ON c.oid = ds.objoid AND ds.classoid = 'pg_class'::regclass
          JOIN pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ds.objsubid AND ds.objsubid > 0
         WHERE n.nspname IN ('shared', 'trees', 'sensor', 'environments', 'pointclouds', 'imagery', 'forest_floor', 'public')
           AND ds.description ~ '(shared|trees|sensor|environments|pointclouds|imagery)\.[A-Z][A-Za-z]+'
    LOOP
        v_new := d.description;
        FOR m IN SELECT regexp_matches(d.description, '(shared|trees|sensor|environments|pointclouds|imagery)\.([A-Z][A-Za-z]+)', 'g')
        LOOP
            v_snake := lower(regexp_replace(m[2], '([a-z])([A-Z])', '\1_\2', 'g'));
            IF to_regclass(m[1] || '.' || v_snake) IS NOT NULL THEN
                v_new := replace(v_new, m[1] || '.' || m[2], m[1] || '.' || v_snake);
            END IF;
        END LOOP;
        CONTINUE WHEN v_new = d.description;

        IF d.objsubid = 0 THEN
            EXECUTE format('COMMENT ON %s %s IS %L',
                           CASE d.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END,
                           d.oid::regclass, v_new);
        ELSE
            EXECUTE format('COMMENT ON COLUMN %s.%I IS %L', d.oid::regclass, d.attname, v_new);
        END IF;
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
