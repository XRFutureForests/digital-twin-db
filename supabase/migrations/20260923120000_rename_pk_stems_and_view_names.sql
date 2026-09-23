-- =============================================================================
-- Tiers 4 and 5: primary-key stems, then the public view names
-- =============================================================================
-- XRFF-497 / XRFF-486, part of XRFF-494. Planned as two migrations (M4 then M5)
-- and merged into one for a reason worth recording.
--
-- A COLUMN rename does not behave like a TABLE rename. Renaming a table updates
-- every dependent view definition automatically, output column names and all --
-- verified on dev. Renaming a *column* updates the stored view definition text
-- but leaves the view's OUTPUT column under its original name, so
-- public.simulation_runs would have gone on publishing `run_id` over a base
-- column called `simulation_run_id`: exactly the alias drift tier 3 exists to
-- remove. Nine views expose a column this migration renames, and the view names
-- were due to change anyway, so doing the two separately meant rebuilding the
-- same views twice.
--
-- Everything here is ALTER ... RENAME. ALTER VIEW ... RENAME COLUMN renames an
-- output column in place and keeps the view's triggers, grants, owner and
-- security_invoker setting -- checked before relying on it, because the
-- DROP+CREATE route silently loses all four and did so twice yesterday.
--
-- 1-2. Eight primary keys whose stem did not match their table, and the seven
--      foreign-key columns that carry them. shared.Scenarios needs no change:
--      its columns are already climate_pathway_id and management_regime_id, so
--      renaming the parent PKs makes them match and removes two of the ten
--      role-qualified FK exceptions rather than adding any.
--
-- 5.   Twenty-six public view names follow their base tables. Twenty-seven do
--      not change: they are single words (campaigns, deadwood, trees) or were
--      already snake_case. Of the seven ue_* views only ue_sensorreadings moves
--      -- the rest are one word after the prefix -- so the Unreal side has one
--      Blueprint URL to change, not three.
--
-- 6.   The INSTEAD OF trigger functions and triggers are named after the views
--      they serve, so they follow too. A trigger references its function by OID,
--      not by name, so ALTER ... RENAME keeps every binding intact.
--
-- 7.   Seven function bodies name a renamed column. shared.get_audit_history is
--      dropped and recreated rather than replaced: audit_id is an OUT parameter,
--      so renaming it changes the row type and CREATE OR REPLACE is refused.
--
-- Mirrored to init 50-rename-pk-stems-and-view-names.sql.
-- =============================================================================

-- 1. Primary keys whose stem did not match their table.
ALTER TABLE shared.audit_log RENAME COLUMN audit_id TO audit_log_id;
ALTER TABLE shared.climate_pathways RENAME COLUMN pathway_id TO climate_pathway_id;
ALTER TABLE shared.management_regimes RENAME COLUMN regime_id TO management_regime_id;
ALTER TABLE trees.simulation_runs RENAME COLUMN run_id TO simulation_run_id;
ALTER TABLE trees.crown_foliage_profiles RENAME COLUMN profile_id TO crown_foliage_profile_id;
ALTER TABLE trees.qsm_cylinders RENAME COLUMN cylinder_id TO qsm_cylinder_id;
ALTER TABLE trees.tree_graph_edges RENAME COLUMN edge_id TO tree_graph_edge_id;
ALTER TABLE trees.geometric_crown_solids RENAME COLUMN geometric_solid_id TO geometric_crown_solid_id;

-- 2. Foreign keys, so each keeps carrying its parent PK name.
ALTER TABLE shared.audit_log_environments RENAME COLUMN audit_id TO audit_log_id;
ALTER TABLE shared.audit_log_phenology_observations RENAME COLUMN audit_id TO audit_log_id;
ALTER TABLE shared.audit_log_point_clouds RENAME COLUMN audit_id TO audit_log_id;
ALTER TABLE shared.audit_log_stems RENAME COLUMN audit_id TO audit_log_id;
ALTER TABLE shared.audit_log_trees RENAME COLUMN audit_id TO audit_log_id;
ALTER TABLE trees.growth_simulations RENAME COLUMN run_id TO simulation_run_id;
ALTER TABLE trees.trees RENAME COLUMN geometric_solid_id TO geometric_crown_solid_id;

-- 3. Sequences and constraints that embed the old column name.
ALTER SEQUENCE shared.audit_log_audit_id_seq RENAME TO audit_log_audit_log_id_seq;
ALTER SEQUENCE trees.crown_foliage_profiles_profile_id_seq RENAME TO crown_foliage_profiles_crown_foliage_profile_id_seq;
ALTER SEQUENCE trees.geometric_crown_solids_geometric_solid_id_seq RENAME TO geometric_crown_solids_geometric_crown_solid_id_seq;
ALTER SEQUENCE trees.qsm_cylinders_cylinder_id_seq RENAME TO qsm_cylinders_qsm_cylinder_id_seq;
ALTER SEQUENCE trees.tree_graph_edges_edge_id_seq RENAME TO tree_graph_edges_tree_graph_edge_id_seq;
ALTER TABLE shared.audit_log_environments RENAME CONSTRAINT audit_log_environments_audit_id_fkey TO audit_log_environments_audit_log_id_fkey;
ALTER TABLE shared.audit_log_phenology_observations RENAME CONSTRAINT audit_log_phenology_observations_audit_id_fkey TO audit_log_phenology_observations_audit_log_id_fkey;
ALTER TABLE shared.audit_log_point_clouds RENAME CONSTRAINT audit_log_point_clouds_audit_id_fkey TO audit_log_point_clouds_audit_log_id_fkey;
ALTER TABLE shared.audit_log_stems RENAME CONSTRAINT audit_log_stems_audit_id_fkey TO audit_log_stems_audit_log_id_fkey;
ALTER TABLE shared.audit_log_trees RENAME CONSTRAINT audit_log_trees_audit_id_fkey TO audit_log_trees_audit_log_id_fkey;
ALTER TABLE shared.climate_pathways RENAME CONSTRAINT climate_pathways_pathway_id_check TO climate_pathways_climate_pathway_id_check;
ALTER TABLE shared.management_regimes RENAME CONSTRAINT management_regimes_regime_id_check TO management_regimes_management_regime_id_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growth_simulations_run_id_fkey TO growth_simulations_simulation_run_id_fkey;
ALTER TABLE trees.trees RENAME CONSTRAINT trees_geometric_solid_id_fkey TO trees_geometric_crown_solid_id_fkey;

-- 4. View output columns. A COLUMN rename does not propagate to a
--    view the way a TABLE rename does: the stored definition updates
--    but the output column keeps its original name, so each has to be
--    renamed in place. ALTER VIEW ... RENAME COLUMN keeps the view's
--    triggers, grants, owner and security_invoker -- no DROP/CREATE.
ALTER VIEW public.climate_pathways RENAME COLUMN pathway_id TO climate_pathway_id;
ALTER VIEW public.crownfoliageprofiles RENAME COLUMN profile_id TO crown_foliage_profile_id;
ALTER VIEW public.geometriccrownsolids RENAME COLUMN geometric_solid_id TO geometric_crown_solid_id;
ALTER VIEW public.growth_simulations RENAME COLUMN run_id TO simulation_run_id;
ALTER VIEW public.management_regimes RENAME COLUMN regime_id TO management_regime_id;
ALTER VIEW public.simulation_runs RENAME COLUMN run_id TO simulation_run_id;
ALTER VIEW public.treegraphedges RENAME COLUMN edge_id TO tree_graph_edge_id;
ALTER VIEW public.trees RENAME COLUMN geometric_solid_id TO geometric_crown_solid_id;
ALTER VIEW shared.recent_changes RENAME COLUMN audit_id TO audit_log_id;

-- 5. Public view names follow their base tables.
ALTER VIEW public.attributeprovenance RENAME TO attribute_provenance;
ALTER VIEW public.axisstructures RENAME TO axis_structures;
ALTER VIEW public.branchelongationhabits RENAME TO branch_elongation_habits;
ALTER VIEW public.crownarchitectures RENAME TO crown_architectures;
ALTER VIEW public.crownclasses RENAME TO crown_classes;
ALTER VIEW public.crownfoliageprofiles RENAME TO crown_foliage_profiles;
ALTER VIEW public.crownshapes RENAME TO crown_shapes;
ALTER VIEW public.damageagents RENAME TO damage_agents;
ALTER VIEW public.datasourcetypes RENAME TO data_source_types;
ALTER VIEW public.disturbanceevents RENAME TO disturbance_events;
ALTER VIEW public.geometriccrownsolids RENAME TO geometric_crown_solids;
ALTER VIEW public.groundvegetation RENAME TO ground_vegetation;
ALTER VIEW public.growthforms RENAME TO growth_forms;
ALTER VIEW public.growthorientations RENAME TO growth_orientations;
ALTER VIEW public.managementevents RENAME TO management_events;
ALTER VIEW public.phanerophyteheightclasses RENAME TO phanerophyte_height_classes;
ALTER VIEW public.phenologyobservations RENAME TO phenology_observations;
ALTER VIEW public.pointclouds RENAME TO point_clouds;
ALTER VIEW public.rootsystemtypes RENAME TO root_system_types;
ALTER VIEW public.sensorreadings RENAME TO sensor_readings;
ALTER VIEW public.sensortypes RENAME TO sensor_types;
ALTER VIEW public.shootelongationtypes RENAME TO shoot_elongation_types;
ALTER VIEW public.treegraphedges RENAME TO tree_graph_edges;
ALTER VIEW public.treeparttypes RENAME TO tree_part_types;
ALTER VIEW public.ue_sensorreadings RENAME TO ue_sensor_readings;
ALTER VIEW public.varianttypes RENAME TO variant_types;

-- 6. The INSTEAD OF trigger functions and triggers are named after the views
--    they serve, so they follow. ALTER ... RENAME keeps every binding: a
--    trigger references its function by OID, not by name.
ALTER FUNCTION public.crownfoliageprofiles_insert() RENAME TO crown_foliage_profiles_insert;
ALTER FUNCTION public.disturbanceevents_insert() RENAME TO disturbance_events_insert;
ALTER FUNCTION public.groundvegetation_insert() RENAME TO ground_vegetation_insert;
ALTER FUNCTION public.managementevents_insert() RENAME TO management_events_insert;
ALTER FUNCTION public.phenologyobservations_insert() RENAME TO phenology_observations_insert;
ALTER FUNCTION public.pointclouds_insert() RENAME TO point_clouds_insert;
ALTER FUNCTION public.sensorreadings_insert() RENAME TO sensor_readings_insert;
ALTER FUNCTION public.treegraphedges_insert() RENAME TO tree_graph_edges_insert;
ALTER TRIGGER crownfoliageprofiles_insert_trigger ON public.crown_foliage_profiles RENAME TO crown_foliage_profiles_insert_trigger;
ALTER TRIGGER disturbanceevents_insert_trigger ON public.disturbance_events RENAME TO disturbance_events_insert_trigger;
ALTER TRIGGER groundvegetation_insert_trigger ON public.ground_vegetation RENAME TO ground_vegetation_insert_trigger;
ALTER TRIGGER managementevents_insert_trigger ON public.management_events RENAME TO management_events_insert_trigger;
ALTER TRIGGER phenologyobservations_insert_trigger ON public.phenology_observations RENAME TO phenology_observations_insert_trigger;
ALTER TRIGGER pointclouds_insert_trigger ON public.point_clouds RENAME TO point_clouds_insert_trigger;
ALTER TRIGGER sensorreadings_insert_trigger ON public.sensor_readings RENAME TO sensor_readings_insert_trigger;
ALTER TRIGGER treegraphedges_insert_trigger ON public.tree_graph_edges RENAME TO tree_graph_edges_insert_trigger;
-- get_audit_history returns audit_id as an OUT parameter, so renaming it
-- changes the row type and CREATE OR REPLACE is refused. It is a query
-- helper, not a trigger function, so nothing depends on it by OID.
DROP FUNCTION IF EXISTS shared.get_audit_history(character varying, integer, integer);

CREATE OR REPLACE FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer DEFAULT 100)
 RETURNS TABLE(audit_log_id bigint, field_name character varying, old_value text, new_value text, change_reason text, user_id character varying, "Timestamp" timestamp with time zone, change_type character varying)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    IF table_name_param = 'PointClouds' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_point_clouds alpc ON al.audit_log_id = alpc.audit_log_id
            WHERE alpc.point_cloud_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Trees' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_trees alt ON al.audit_log_id = alt.audit_log_id
            WHERE alt.tree_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Environments' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_environments ale ON al.audit_log_id = ale.audit_log_id
            WHERE ale.environment_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Stems' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_stems als ON al.audit_log_id = als.audit_log_id
            WHERE als.stem_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'PhenologyObservations' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_phenology_observations alp ON al.audit_log_id = alp.audit_log_id
            WHERE alp.phenology_observation_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    END IF;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.revert_field_change(audit_id_param bigint, change_reason_param text DEFAULT 'Reverted change'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    audit_record RECORD;
    table_name VARCHAR;
    variant_id INTEGER;
    field_name VARCHAR;
    old_value TEXT;
    new_audit_id BIGINT;
BEGIN
    SELECT * INTO audit_record FROM shared.audit_log WHERE audit_log_id = audit_id_param;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Audit record % not found', audit_id_param;
    END IF;
    IF EXISTS (SELECT 1 FROM shared.audit_log_point_clouds WHERE audit_log_id = audit_id_param) THEN
        table_name := 'PointClouds';
        SELECT point_cloud_id INTO variant_id FROM shared.audit_log_point_clouds WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_trees WHERE audit_log_id = audit_id_param) THEN
        table_name := 'Trees';
        SELECT tree_id INTO variant_id FROM shared.audit_log_trees WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_environments WHERE audit_log_id = audit_id_param) THEN
        table_name := 'Environments';
        SELECT environment_id INTO variant_id FROM shared.audit_log_environments WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_stems WHERE audit_log_id = audit_id_param) THEN
        table_name := 'Stems';
        SELECT stem_id INTO variant_id FROM shared.audit_log_stems WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_phenology_observations WHERE audit_log_id = audit_id_param) THEN
        table_name := 'PhenologyObservations';
        SELECT phenology_observation_id INTO variant_id FROM shared.audit_log_phenology_observations WHERE audit_log_id = audit_id_param;
    ELSE
        RAISE EXCEPTION 'Could not determine table for audit record %', audit_id_param;
    END IF;
    field_name := audit_record.field_name;
    old_value := audit_record.old_value;
    SELECT shared.create_audit_log(
        table_name, variant_id, field_name,
        audit_record.new_value, old_value,
        change_reason_param, 'revert'
    ) INTO new_audit_id;
    RETURN TRUE;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text DEFAULT NULL::text, change_type_param character varying DEFAULT 'field_update'::character varying)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_audit_id BIGINT;
BEGIN
    INSERT INTO shared.audit_log (
        field_name, old_value, new_value, change_reason,
        user_id, change_type, ip_address
    ) VALUES (
        field_name_param, old_value_param, new_value_param, change_reason_param,
        auth.uid()::TEXT, change_type_param, inet_client_addr()
    )
    RETURNING audit_log_id INTO v_audit_id;
    CASE table_name_param
        WHEN 'PointClouds' THEN
            INSERT INTO shared.audit_log_point_clouds (audit_log_id, point_cloud_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Trees' THEN
            INSERT INTO shared.audit_log_trees (audit_log_id, tree_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Environments' THEN
            INSERT INTO shared.audit_log_environments (audit_log_id, environment_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Stems' THEN
            INSERT INTO shared.audit_log_stems (audit_log_id, stem_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'PhenologyObservations' THEN
            INSERT INTO shared.audit_log_phenology_observations (audit_log_id, phenology_observation_id)
            VALUES (v_audit_id, variant_id_param);
    END CASE;
    RETURN v_audit_id;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.audit_update_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    audit_log_id BIGINT;
    record_id INTEGER;
    v_reason TEXT;
BEGIN
    -- NULL unless the caller set it for this transaction.
    v_reason := NULLIF(current_setting('app.change_reason', true), '');

    CASE TG_TABLE_NAME
        WHEN 'pointclouds' THEN
            record_id := NEW.point_cloud_id;
        WHEN 'trees' THEN
            record_id := NEW.tree_id;
        WHEN 'environments' THEN
            record_id := NEW.environment_id;
        WHEN 'stems' THEN
            record_id := NEW.stem_id;
        WHEN 'phenologyobservations' THEN
            record_id := NEW.phenology_observation_id;
        ELSE
            record_id := NULL;
    END CASE;

    IF record_id IS NULL THEN
        RETURN NEW;
    END IF;

    CASE TG_TABLE_NAME
        WHEN 'trees' THEN
            IF OLD.Height_m IS DISTINCT FROM NEW.Height_m THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'Height_m', OLD.Height_m::TEXT, NEW.Height_m::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.crown_width_m IS DISTINCT FROM NEW.crown_width_m THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'crown_width_m', OLD.crown_width_m::TEXT, NEW.crown_width_m::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31: derived attributes filled by allometry.
            IF OLD.crown_base_height_m IS DISTINCT FROM NEW.crown_base_height_m THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'crown_base_height_m', OLD.crown_base_height_m::TEXT, NEW.crown_base_height_m::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.volume_m3 IS DISTINCT FROM NEW.volume_m3 THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'volume_m3', OLD.volume_m3::TEXT, NEW.volume_m3::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31 (follow-up): age is derived from height by
            -- allometric inversion, so it needs a trail like the rest.
            IF OLD.age_years IS DISTINCT FROM NEW.age_years THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'age_years', OLD.age_years::TEXT, NEW.age_years::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31 (follow-up): biomass and carbon are derived from
            -- DBH and height by allometry, so they need a trail like the rest.
            IF OLD.biomass_kg IS DISTINCT FROM NEW.biomass_kg THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'biomass_kg', OLD.biomass_kg::TEXT, NEW.biomass_kg::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.carbon_content_kg IS DISTINCT FROM NEW.carbon_content_kg THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'carbon_content_kg', OLD.carbon_content_kg::TEXT, NEW.carbon_content_kg::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.health_score IS DISTINCT FROM NEW.health_score THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'health_score', OLD.health_score::TEXT, NEW.health_score::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.tree_status_id IS DISTINCT FROM NEW.tree_status_id THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'tree_status_id', OLD.tree_status_id::TEXT, NEW.tree_status_id::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'stems' THEN
            IF OLD.DBH_cm IS DISTINCT FROM NEW.DBH_cm THEN
                PERFORM shared.create_audit_log('Stems', record_id, 'DBH_cm', OLD.DBH_cm::TEXT, NEW.DBH_cm::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.stem_height_m IS DISTINCT FROM NEW.stem_height_m THEN
                PERFORM shared.create_audit_log('Stems', record_id, 'stem_height_m', OLD.stem_height_m::TEXT, NEW.stem_height_m::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31.
            IF OLD.stem_volume_m3 IS DISTINCT FROM NEW.stem_volume_m3 THEN
                PERFORM shared.create_audit_log('Stems', record_id, 'stem_volume_m3', OLD.stem_volume_m3::TEXT, NEW.stem_volume_m3::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'environments' THEN
            IF OLD.avg_temperature_c IS DISTINCT FROM NEW.avg_temperature_c THEN
                PERFORM shared.create_audit_log('Environments', record_id, 'avg_temperature_c', OLD.avg_temperature_c::TEXT, NEW.avg_temperature_c::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.stress_factor IS DISTINCT FROM NEW.stress_factor THEN
                PERFORM shared.create_audit_log('Environments', record_id, 'stress_factor', OLD.stress_factor::TEXT, NEW.stress_factor::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'pointclouds' THEN
            IF OLD.processing_status IS DISTINCT FROM NEW.processing_status THEN
                PERFORM shared.create_audit_log('PointClouds', record_id, 'processing_status', OLD.processing_status::TEXT, NEW.processing_status::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'phenologyobservations' THEN
            IF OLD.phenophase_status IS DISTINCT FROM NEW.phenophase_status THEN
                PERFORM shared.create_audit_log('PhenologyObservations', record_id, 'phenophase_status', OLD.phenophase_status::TEXT, NEW.phenophase_status::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.intensity_percent IS DISTINCT FROM NEW.intensity_percent THEN
                PERFORM shared.create_audit_log('PhenologyObservations', record_id, 'intensity_percent', OLD.intensity_percent::TEXT, NEW.intensity_percent::TEXT, v_reason, 'field_update');
            END IF;
    END CASE;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.crownfoliageprofiles_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO trees.crown_foliage_profiles (
        tree_id, process_id, distribution_type, vertical_params,
        horizontal_params, total_leaf_area_m2, source, created_by
    ) VALUES (
        NEW.tree_id, NEW.process_id, NEW.distribution_type, NEW.vertical_params,
        NEW.horizontal_params, NEW.total_leaf_area_m2, NEW.source, NEW.created_by
    ) RETURNING crown_foliage_profile_id INTO NEW.crown_foliage_profile_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.treegraphedges_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO trees.tree_graph_edges (
        qsm_id, from_cylinder_index, to_cylinder_index, edge_type
    ) VALUES (
        NEW.qsm_id, NEW.from_cylinder_index, NEW.to_cylinder_index, NEW.edge_type
    ) RETURNING tree_graph_edge_id INTO NEW.tree_graph_edge_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.scenario_axes_from_name(p_name text)
 RETURNS TABLE(management_regime_id smallint, climate_pathway_id smallint)
 LANGUAGE sql
 STABLE
AS $function$
    -- <pathway> alone: a climate-data bucket, regime none.
    SELECT 0::smallint, cp.climate_pathway_id
    FROM shared.climate_pathways cp
    WHERE cp.pathway_name = p_name
    UNION ALL
    -- <regime> alone: that regime under the historical climate.
    SELECT mr.management_regime_id, 0::smallint
    FROM shared.management_regimes mr
    WHERE mr.regime_name = p_name AND mr.management_regime_id <> 0
    UNION ALL
    -- <regime>_<pathway>.
    SELECT mr.management_regime_id, cp.climate_pathway_id
    FROM shared.management_regimes mr
    JOIN shared.climate_pathways cp ON p_name = mr.regime_name || '_' || cp.pathway_name
    WHERE mr.management_regime_id <> 0 AND cp.climate_pathway_id <> 0
    LIMIT 1;
$function$;

-- 8. Label columns follow their primary keys. Renaming the PK in section 1 left
--    these three lookups with a label whose stem no longer matched -- caught by
--    check_naming.py immediately after applying sections 1-7, which is the rule
--    that every lookup's <stem>_id and <stem>_name agree.
ALTER TABLE shared.climate_pathways RENAME COLUMN pathway_name TO climate_pathway_name;
ALTER TABLE shared.management_regimes RENAME COLUMN regime_name TO management_regime_name;
ALTER TABLE trees.geometric_crown_solids RENAME COLUMN geometric_solid_name TO geometric_crown_solid_name;

ALTER VIEW public.climate_pathways RENAME COLUMN pathway_name TO climate_pathway_name;
ALTER VIEW public.management_regimes RENAME COLUMN regime_name TO management_regime_name;
ALTER VIEW public.geometric_crown_solids RENAME COLUMN geometric_solid_name TO geometric_crown_solid_name;

ALTER TABLE shared.climate_pathways RENAME CONSTRAINT climate_pathways_pathway_name_check TO climate_pathways_climate_pathway_name_check;
ALTER TABLE shared.climate_pathways RENAME CONSTRAINT climate_pathways_pathway_name_key TO climate_pathways_climate_pathway_name_key;
ALTER TABLE shared.management_regimes RENAME CONSTRAINT management_regimes_regime_name_check TO management_regimes_management_regime_name_check;
ALTER TABLE shared.management_regimes RENAME CONSTRAINT management_regimes_regime_name_key TO management_regimes_management_regime_name_key;
ALTER TABLE trees.geometric_crown_solids RENAME CONSTRAINT geometric_crown_solids_geometric_solid_name_key TO geometric_crown_solids_geometric_crown_solid_name_key;
CREATE OR REPLACE FUNCTION shared.scenario_axes_from_name(p_name text)
 RETURNS TABLE(management_regime_id smallint, climate_pathway_id smallint)
 LANGUAGE sql
 STABLE
AS $function$
    -- <pathway> alone: a climate-data bucket, regime none.
    SELECT 0::smallint, cp.climate_pathway_id
    FROM shared.climate_pathways cp
    WHERE cp.climate_pathway_name = p_name
    UNION ALL
    -- <regime> alone: that regime under the historical climate.
    SELECT mr.management_regime_id, 0::smallint
    FROM shared.management_regimes mr
    WHERE mr.management_regime_name = p_name AND mr.management_regime_id <> 0
    UNION ALL
    -- <regime>_<pathway>.
    SELECT mr.management_regime_id, cp.climate_pathway_id
    FROM shared.management_regimes mr
    JOIN shared.climate_pathways cp ON p_name = mr.management_regime_name || '_' || cp.climate_pathway_name
    WHERE mr.management_regime_id <> 0 AND cp.climate_pathway_id <> 0
    LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION shared.refresh_lookup(p_table_name text)
 RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_rows_before INT;
    v_rows_after INT;
    v_csv_path TEXT;
BEGIN
    -- Normalize table name
    p_table_name := lower(trim(p_table_name));
    -- Map table names to CSV files
    v_csv_path := '/var/lib/postgresql/lookups/';
    CASE p_table_name
        WHEN 'species' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.species;
            CREATE TEMP TABLE IF NOT EXISTS _temp_species (
                common_name VARCHAR(200),
                scientific_name VARCHAR(200),
                max_height_m NUMERIC(6, 2),
                max_dbh_cm NUMERIC(6, 2),
                typical_lifespan_years INTEGER,
                growth_rate VARCHAR(20),
                shade_tolerance VARCHAR(20),
                is_deciduous BOOLEAN,
                gbif_key INTEGER,
                gbif_accepted_name VARCHAR(200)
            ) ON COMMIT DROP;
            TRUNCATE _temp_species;
            EXECUTE format('COPY _temp_species FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'species.csv');
            INSERT INTO shared.Species (common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name)
            SELECT common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name
            FROM _temp_species
            ON CONFLICT (scientific_name) DO UPDATE SET
                common_name = EXCLUDED.common_name,
                max_height_m = EXCLUDED.max_height_m,
                max_dbh_cm = EXCLUDED.max_dbh_cm,
                typical_lifespan_years = EXCLUDED.typical_lifespan_years,
                growth_rate = EXCLUDED.growth_rate,
                shade_tolerance = EXCLUDED.shade_tolerance,
                is_deciduous = EXCLUDED.is_deciduous,
                gbif_key = EXCLUDED.gbif_key,
                gbif_accepted_name = EXCLUDED.gbif_accepted_name;
            SELECT COUNT(*) INTO v_rows_after FROM shared.species;
        WHEN 'locations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.locations;
            CREATE TEMP TABLE IF NOT EXISTS _temp_locations (
                location_name VARCHAR(200),
                Description TEXT,
                CenterLongitude NUMERIC(10, 6),
                CenterLatitude NUMERIC(10, 6),
                Elevation_m NUMERIC(8, 2),
                Slope_deg NUMERIC(5, 2),
                Aspect VARCHAR(3),
                soil_type_name VARCHAR(100),
                climate_zone_name VARCHAR(10),
                ForestGrowthRegion VARCHAR(16),
                SoilMoistness SMALLINT,
                SoilNutrientSupply SMALLINT,
                CrsEpsg INTEGER
            ) ON COMMIT DROP;
            TRUNCATE _temp_locations;
            EXECUTE format('COPY _temp_locations FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'locations.csv');
            INSERT INTO shared.Locations (location_name, Description, center_point, Elevation_m, Slope_deg, Aspect, soil_type_id, climate_zone_id, forest_growth_region, soil_moistness, soil_nutrient_supply, crs_epsg)
            SELECT 
                t.location_name,
                t.Description,
                CASE WHEN t.CenterLongitude IS NOT NULL AND t.CenterLatitude IS NOT NULL 
                     THEN extensions.ST_SetSRID(extensions.ST_MakePoint(t.CenterLongitude, t.CenterLatitude), 4326)
                     ELSE NULL 
                END,
                t.Elevation_m,
                t.Slope_deg,
                t.Aspect,
                (SELECT soil_type_id FROM shared.soil_types WHERE soil_type_name = t.soil_type_name),
                (SELECT climate_zone_id FROM shared.climate_zones WHERE climate_zone_name = t.climate_zone_name),
                t.ForestGrowthRegion,
                t.SoilMoistness,
                t.SoilNutrientSupply,
                t.CrsEpsg
            FROM _temp_locations t
            -- The eight site-attribute columns keep their value once an
            -- acquisition process has written one, so a refresh cannot revert it
            -- and leave its provenance row claiming a source the column no
            -- longer holds (XRFF-391). Description, center_point and crs_epsg are
            -- always reseeded: the CSV owns all three.
            ON CONFLICT (location_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                center_point = EXCLUDED.center_point,
                crs_epsg = EXCLUDED.crs_epsg,
                Elevation_m = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'elevation_m')
                                   THEN Locations.Elevation_m ELSE EXCLUDED.Elevation_m END,
                Slope_deg = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'slope_deg')
                                 THEN Locations.Slope_deg ELSE EXCLUDED.Slope_deg END,
                Aspect = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'aspect')
                              THEN Locations.Aspect ELSE EXCLUDED.Aspect END,
                soil_type_id = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_type_id')
                                    THEN Locations.soil_type_id ELSE EXCLUDED.soil_type_id END,
                climate_zone_id = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'climate_zone_id')
                                       THEN Locations.climate_zone_id ELSE EXCLUDED.climate_zone_id END,
                forest_growth_region = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'forest_growth_region')
                                            THEN Locations.forest_growth_region ELSE EXCLUDED.forest_growth_region END,
                soil_moistness = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_moistness')
                                      THEN Locations.soil_moistness ELSE EXCLUDED.soil_moistness END,
                soil_nutrient_supply = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_nutrient_supply')
                                            THEN Locations.soil_nutrient_supply ELSE EXCLUDED.soil_nutrient_supply END;
            SELECT COUNT(*) INTO v_rows_after FROM shared.locations;
        WHEN 'sensor_types', 'sensortypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM sensor.sensor_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_sensor_types (
                sensor_type_name VARCHAR(100),
                Description TEXT,
                typical_unit VARCHAR(50),
                typical_range_min NUMERIC(12, 4),
                typical_range_max NUMERIC(12, 4)
            ) ON COMMIT DROP;
            TRUNCATE _temp_sensor_types;
            EXECUTE format('COPY _temp_sensor_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'sensor_types.csv');
            INSERT INTO sensor.sensor_types (sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max)
            SELECT sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max 
            FROM _temp_sensor_types
            ON CONFLICT (sensor_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_unit = EXCLUDED.typical_unit,
                typical_range_min = EXCLUDED.typical_range_min,
                typical_range_max = EXCLUDED.typical_range_max;
            SELECT COUNT(*) INTO v_rows_after FROM sensor.sensor_types;
            p_table_name := 'sensor_types';
        WHEN 'tree_status', 'treestatus' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.tree_status;
            CREATE TEMP TABLE IF NOT EXISTS _temp_tree_status (
                tree_status_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_tree_status;
            EXECUTE format('COPY _temp_tree_status FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'tree_status.csv');
            INSERT INTO trees.tree_status (tree_status_name, Description)
            SELECT tree_status_name, Description FROM _temp_tree_status
            ON CONFLICT (tree_status_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.tree_status;
            p_table_name := 'tree_status';
        WHEN 'soil_types', 'soiltypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.soil_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_soil_types (
                soil_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_soil_types;
            EXECUTE format('COPY _temp_soil_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'soil_types.csv');
            INSERT INTO shared.soil_types (soil_type_name, Description)
            SELECT soil_type_name, Description FROM _temp_soil_types
            ON CONFLICT (soil_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM shared.soil_types;
            p_table_name := 'soil_types';
        WHEN 'climate_zones', 'climatezones' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.climate_zones;
            CREATE TEMP TABLE IF NOT EXISTS _temp_climate_zones (
                climate_zone_name VARCHAR(10),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_climate_zones;
            EXECUTE format('COPY _temp_climate_zones FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'climate_zones.csv');
            INSERT INTO shared.climate_zones (climate_zone_name, Description)
            SELECT climate_zone_name, Description FROM _temp_climate_zones
            ON CONFLICT (climate_zone_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM shared.climate_zones;
            p_table_name := 'climate_zones';
        WHEN 'variant_types', 'varianttypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.variant_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_variant_types (
                variant_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_variant_types;
            EXECUTE format('COPY _temp_variant_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'variant_types.csv');
            INSERT INTO shared.variant_types (variant_type_name, Description)
            SELECT variant_type_name, Description FROM _temp_variant_types
            ON CONFLICT (variant_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM shared.variant_types;
            p_table_name := 'variant_types';
        WHEN 'scenarios' THEN
            -- Scenarios are location-scoped (Scenarios.location_id NOT NULL,
            -- UNIQUE(location_id, scenario_name)) and are created per site by the
            -- growth-variant seed scripts — not a refreshable global lookup CSV.
            SELECT COUNT(*) INTO v_rows_before FROM shared.scenarios;
            RAISE NOTICE 'scenarios are location-scoped; not refreshed from a global CSV (skipped)';
            v_rows_after := v_rows_before;
        WHEN 'taper_types', 'tapertypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.taper_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_taper_types (
                taper_type_name VARCHAR(100),
                Description TEXT,
                typical_taper_ratio_min NUMERIC(4, 3),
                typical_taper_ratio_max NUMERIC(4, 3)
            ) ON COMMIT DROP;
            TRUNCATE _temp_taper_types;
            EXECUTE format('COPY _temp_taper_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'taper_types.csv');
            INSERT INTO trees.taper_types (taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max)
            SELECT taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max FROM _temp_taper_types
            ON CONFLICT (taper_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_taper_ratio_min = EXCLUDED.typical_taper_ratio_min,
                typical_taper_ratio_max = EXCLUDED.typical_taper_ratio_max;
            SELECT COUNT(*) INTO v_rows_after FROM trees.taper_types;
            p_table_name := 'taper_types';
        WHEN 'straightness_types', 'straightnesstypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.straightness_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_straightness_types (
                straightness_type_name VARCHAR(100),
                Description TEXT,
                deviation_angle_min_deg NUMERIC(5, 2),
                deviation_angle_max_deg NUMERIC(5, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_straightness_types;
            EXECUTE format('COPY _temp_straightness_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'straightness_types.csv');
            INSERT INTO trees.straightness_types (straightness_type_name, Description, deviation_angle_min_deg, deviation_angle_max_deg)
            SELECT straightness_type_name, Description, deviation_angle_min_deg, deviation_angle_max_deg FROM _temp_straightness_types
            ON CONFLICT (straightness_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                deviation_angle_min_deg = EXCLUDED.deviation_angle_min_deg,
                deviation_angle_max_deg = EXCLUDED.deviation_angle_max_deg;
            SELECT COUNT(*) INTO v_rows_after FROM trees.straightness_types;
            p_table_name := 'straightness_types';
        WHEN 'branching_patterns', 'branchingpatterns' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branching_patterns;
            CREATE TEMP TABLE IF NOT EXISTS _temp_branching_patterns (
                branching_pattern_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_branching_patterns;
            EXECUTE format('COPY _temp_branching_patterns FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branching_patterns.csv');
            INSERT INTO trees.branching_patterns (branching_pattern_name, Description)
            SELECT branching_pattern_name, Description FROM _temp_branching_patterns
            ON CONFLICT (branching_pattern_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.branching_patterns;
            p_table_name := 'branching_patterns';
        WHEN 'bark_characteristics', 'barkcharacteristics' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.bark_characteristics;
            CREATE TEMP TABLE IF NOT EXISTS _temp_bark_characteristics (
                bark_characteristic_name VARCHAR(100),
                Description TEXT,
                typical_species TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_bark_characteristics;
            EXECUTE format('COPY _temp_bark_characteristics FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'bark_characteristics.csv');
            INSERT INTO trees.bark_characteristics (bark_characteristic_name, Description, typical_species)
            SELECT bark_characteristic_name, Description, typical_species FROM _temp_bark_characteristics
            ON CONFLICT (bark_characteristic_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_species = EXCLUDED.typical_species;
            SELECT COUNT(*) INTO v_rows_after FROM trees.bark_characteristics;
            p_table_name := 'bark_characteristics';
        WHEN 'datasource_types', 'datasourcetypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.data_source_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_datasource_types (
                data_source_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_datasource_types;
            EXECUTE format('COPY _temp_datasource_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'datasource_types.csv');
            INSERT INTO trees.data_source_types (data_source_type_name, Description)
            SELECT data_source_type_name, Description FROM _temp_datasource_types
            ON CONFLICT (data_source_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.data_source_types;
            p_table_name := 'datasource_types';
        -- =====================================================================
        -- TREE MORPHOLOGY TABLES (from tree_anatomy.pdf)
        -- =====================================================================
        WHEN 'height_classes', 'phanerophyte_height_classes', 'phanerophyteheightclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.phanerophyte_height_classes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_height_classes (
                height_class_name VARCHAR(50),
                Description TEXT,
                min_height_m NUMERIC(6, 2),
                max_height_m NUMERIC(6, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_height_classes;
            EXECUTE format('COPY _temp_height_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'phanerophyte_height_classes.csv');
            INSERT INTO trees.phanerophyte_height_classes (height_class_name, Description, min_height_m, max_height_m)
            SELECT height_class_name, Description, min_height_m, max_height_m FROM _temp_height_classes
            ON CONFLICT (height_class_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                min_height_m = EXCLUDED.min_height_m,
                max_height_m = EXCLUDED.max_height_m;
            SELECT COUNT(*) INTO v_rows_after FROM trees.phanerophyte_height_classes;
            p_table_name := 'height_classes';
        WHEN 'crown_architectures', 'crownarchitectures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crown_architectures;
            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_arch (
                crown_architecture_name VARCHAR(50),
                Description TEXT,
                typical_examples TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_arch;
            EXECUTE format('COPY _temp_crown_arch FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_architectures.csv');
            INSERT INTO trees.crown_architectures (crown_architecture_name, Description, typical_examples)
            SELECT crown_architecture_name, Description, typical_examples FROM _temp_crown_arch
            ON CONFLICT (crown_architecture_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_examples = EXCLUDED.typical_examples;
            SELECT COUNT(*) INTO v_rows_after FROM trees.crown_architectures;
            p_table_name := 'crown_architectures';
        WHEN 'branch_elongation_habits', 'branchelongationhabits', 'elongation_habits' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branch_elongation_habits;
            CREATE TEMP TABLE IF NOT EXISTS _temp_elongation (
                elongation_habit_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_elongation;
            EXECUTE format('COPY _temp_elongation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branch_elongation_habits.csv');
            INSERT INTO trees.branch_elongation_habits (elongation_habit_name, Description)
            SELECT elongation_habit_name, Description FROM _temp_elongation
            ON CONFLICT (elongation_habit_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.branch_elongation_habits;
            p_table_name := 'branch_elongation_habits';
        WHEN 'growth_orientations', 'growthorientations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growth_orientations;
            CREATE TEMP TABLE IF NOT EXISTS _temp_orientation (
                growth_orientation_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_orientation;
            EXECUTE format('COPY _temp_orientation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_orientations.csv');
            INSERT INTO trees.growth_orientations (growth_orientation_name, Description)
            SELECT growth_orientation_name, Description FROM _temp_orientation
            ON CONFLICT (growth_orientation_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.growth_orientations;
            p_table_name := 'growth_orientations';
        WHEN 'shoot_elongation_types', 'shootelongationtypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.shoot_elongation_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_shoot (
                shoot_elongation_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shoot;
            EXECUTE format('COPY _temp_shoot FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'shoot_elongation_types.csv');
            INSERT INTO trees.shoot_elongation_types (shoot_elongation_type_name, Description)
            SELECT shoot_elongation_type_name, Description FROM _temp_shoot
            ON CONFLICT (shoot_elongation_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.shoot_elongation_types;
            p_table_name := 'shoot_elongation_types';
        WHEN 'crown_shapes', 'crownshapes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crown_shapes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_shapes (
                crown_shape_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shapes;
            EXECUTE format('COPY _temp_shapes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_shapes.csv');
            INSERT INTO trees.crown_shapes (crown_shape_name, Description)
            SELECT crown_shape_name, Description FROM _temp_shapes
            ON CONFLICT (crown_shape_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.crown_shapes;
            p_table_name := 'crown_shapes';
        WHEN 'geometric_crown_solids', 'geometriccrownsolids', 'geometric_solids' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.geometric_crown_solids;
            CREATE TEMP TABLE IF NOT EXISTS _temp_solids (
                geometric_crown_solid_name VARCHAR(50),
                Description TEXT,
                relative_lateral_area NUMERIC(4, 2),
                relative_volume NUMERIC(4, 2),
                relative_drag NUMERIC(4, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_solids;
            EXECUTE format('COPY _temp_solids FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'geometric_crown_solids.csv');
            INSERT INTO trees.geometric_crown_solids (geometric_crown_solid_name, Description, relative_lateral_area, relative_volume, relative_drag)
            SELECT geometric_crown_solid_name, Description, relative_lateral_area, relative_volume, relative_drag FROM _temp_solids
            ON CONFLICT (geometric_crown_solid_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                relative_lateral_area = EXCLUDED.relative_lateral_area,
                relative_volume = EXCLUDED.relative_volume,
                relative_drag = EXCLUDED.relative_drag;
            SELECT COUNT(*) INTO v_rows_after FROM trees.geometric_crown_solids;
            p_table_name := 'geometric_crown_solids';
        WHEN 'axis_structures', 'axisstructures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.axis_structures;
            CREATE TEMP TABLE IF NOT EXISTS _temp_axis (
                axis_structure_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_axis;
            EXECUTE format('COPY _temp_axis FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'axis_structures.csv');
            INSERT INTO trees.axis_structures (axis_structure_name, Description)
            SELECT axis_structure_name, Description FROM _temp_axis
            ON CONFLICT (axis_structure_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.axis_structures;
            p_table_name := 'axis_structures';
        WHEN 'growth_forms', 'growthforms' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growth_forms;
            CREATE TEMP TABLE IF NOT EXISTS _temp_forms (
                growth_form_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_forms;
            EXECUTE format('COPY _temp_forms FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_forms.csv');
            INSERT INTO trees.growth_forms (growth_form_name, Description)
            SELECT growth_form_name, Description FROM _temp_forms
            ON CONFLICT (growth_form_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.growth_forms;
            p_table_name := 'growth_forms';
        -- =====================================================================
        -- TREE CONDITION TABLES (FIA/NEON/ICP Forests-aligned)
        -- =====================================================================
        WHEN 'crown_classes', 'crownclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crown_classes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_classes (
                crown_class_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_classes;
            EXECUTE format('COPY _temp_crown_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_classes.csv');
            INSERT INTO trees.crown_classes (crown_class_name, Description)
            SELECT crown_class_name, Description FROM _temp_crown_classes
            ON CONFLICT (crown_class_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.crown_classes;
            p_table_name := 'crown_classes';
        WHEN 'damage_agents', 'damageagents' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.damage_agents;
            CREATE TEMP TABLE IF NOT EXISTS _temp_damage_agents (
                damage_agent_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_damage_agents;
            EXECUTE format('COPY _temp_damage_agents FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'damage_agents.csv');
            INSERT INTO trees.damage_agents (damage_agent_name, Description)
            SELECT damage_agent_name, Description FROM _temp_damage_agents
            ON CONFLICT (damage_agent_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.damage_agents;
            p_table_name := 'damage_agents';
        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0, 'ERROR: Unknown table. Use: species, locations, sensor_types, tree_status, soil_types, climate_zones, variant_types, scenarios, taper_types, straightness_types, branching_patterns, bark_characteristics, datasource_types, height_classes, crown_architectures, branch_elongation_habits, growth_orientations, shoot_elongation_types, crown_shapes, geometric_crown_solids, axis_structures, growth_forms, crown_classes, damage_agents';
            RETURN;
    END CASE;
    RETURN QUERY SELECT p_table_name, v_rows_before, v_rows_after, 'OK';
END;
$function$;
