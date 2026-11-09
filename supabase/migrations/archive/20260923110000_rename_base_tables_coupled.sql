-- =============================================================================
-- Tier 1, part 2: the 18 base tables other repos reference
-- =============================================================================
-- XRFF-497, part of XRFF-494. Companion commits land in digital-twin-dashboard
-- (XRFF-498), silva-connector (XRFF-499), aquarius-connector (XRFF-500) and
-- open-data-connector (XRFF-501) alongside this.
--
-- These are the tables the first rename migration deliberately left alone
-- because they are read -- and in silva-connector's case written -- from outside
-- this repo. dt.unr is unaffected either way: it runs its own database volume and
-- its own checkouts, and picks up nothing until those repos are pulled.
--
-- The five auditlog_* junction tables move here rather than with the uncoupled
-- set, because renaming them while shared.auditlog kept its squashed name would
-- leave the schema in a state that is neither shape.
--
-- 18 tables, 10 sequences, 3 indexes, 76 constraints, 16 function bodies. The
-- function list is longer than the last migration's because sensor.sensorreadings
-- is the most-referenced table in the database: bulk_insert_readings,
-- aggregate_readings, get_latest_reading, check_sensor_health,
-- refresh_soil_aggregates and ue_sensor_state_at all name it, and Postgres
-- rewrites none of them.
--
-- Mirrored to init 49-rename-base-tables-coupled.sql.
-- =============================================================================

-- 1. Tables.
ALTER TABLE sensor.sensorreadings RENAME TO sensor_readings;
ALTER TABLE sensor.sensortypes RENAME TO sensor_types;
ALTER TABLE shared.auditlog RENAME TO audit_log;
ALTER TABLE shared.auditlog_environments RENAME TO audit_log_environments;
ALTER TABLE shared.auditlog_phenologyobservations RENAME TO audit_log_phenology_observations;
ALTER TABLE shared.auditlog_pointclouds RENAME TO audit_log_point_clouds;
ALTER TABLE shared.auditlog_stems RENAME TO audit_log_stems;
ALTER TABLE shared.auditlog_trees RENAME TO audit_log_trees;
ALTER TABLE shared.climatepathways RENAME TO climate_pathways;
ALTER TABLE shared.climatezones RENAME TO climate_zones;
ALTER TABLE shared.managementregimes RENAME TO management_regimes;
ALTER TABLE shared.processingjobs RENAME TO processing_jobs;
ALTER TABLE shared.soiltypes RENAME TO soil_types;
ALTER TABLE shared.varianttypes RENAME TO variant_types;
ALTER TABLE trees.datasourcetypes RENAME TO data_source_types;
ALTER TABLE trees.growthsimulations RENAME TO growth_simulations;
ALTER TABLE trees.simulationruns RENAME TO simulation_runs;
ALTER TABLE trees.treestatus RENAME TO tree_status;

-- 2. Sequences.
ALTER SEQUENCE sensor.sensorreadings_sensor_reading_id_seq RENAME TO sensor_readings_sensor_reading_id_seq;
ALTER SEQUENCE sensor.sensortypes_sensor_type_id_seq RENAME TO sensor_types_sensor_type_id_seq;
ALTER SEQUENCE shared.auditlog_audit_id_seq RENAME TO audit_log_audit_id_seq;
ALTER SEQUENCE shared.climatezones_climate_zone_id_seq RENAME TO climate_zones_climate_zone_id_seq;
ALTER SEQUENCE shared.processingjobs_processing_job_id_seq RENAME TO processing_jobs_processing_job_id_seq;
ALTER SEQUENCE shared.soiltypes_soil_type_id_seq RENAME TO soil_types_soil_type_id_seq;
ALTER SEQUENCE shared.varianttypes_variant_type_id_seq RENAME TO variant_types_variant_type_id_seq;
ALTER SEQUENCE trees.datasourcetypes_data_source_type_id_seq RENAME TO data_source_types_data_source_type_id_seq;
ALTER SEQUENCE trees.growthsimulations_growth_simulation_id_seq RENAME TO growth_simulations_growth_simulation_id_seq;
ALTER SEQUENCE trees.treestatus_tree_status_id_seq RENAME TO tree_status_tree_status_id_seq;

-- 3. Indexes.
ALTER INDEX trees.idx_simulationruns_created_at RENAME TO idx_simulation_runs_created_at;
ALTER INDEX trees.idx_simulationruns_location_scenario RENAME TO idx_simulation_runs_location_scenario;
ALTER INDEX trees.idx_simulationruns_simulator RENAME TO idx_simulation_runs_simulator;

-- 4. Constraints.
ALTER TABLE sensor.sensor_readings RENAME CONSTRAINT sensorreadings_pkey TO sensor_readings_pkey;
ALTER TABLE sensor.sensor_readings RENAME CONSTRAINT sensorreadings_quality_check TO sensor_readings_quality_check;
ALTER TABLE sensor.sensor_readings RENAME CONSTRAINT sensorreadings_scenario_id_fkey TO sensor_readings_scenario_id_fkey;
ALTER TABLE sensor.sensor_readings RENAME CONSTRAINT sensorreadings_sensor_id_fkey TO sensor_readings_sensor_id_fkey;
ALTER TABLE sensor.sensor_readings RENAME CONSTRAINT sensorreadings_sensor_id_timestamp_unique TO sensor_readings_sensor_id_timestamp_unique;
ALTER TABLE sensor.sensor_types RENAME CONSTRAINT sensortypes_pkey TO sensor_types_pkey;
ALTER TABLE sensor.sensor_types RENAME CONSTRAINT sensortypes_sensor_type_name_key TO sensor_types_sensor_type_name_key;
ALTER TABLE shared.audit_log RENAME CONSTRAINT auditlog_change_type_check TO audit_log_change_type_check;
ALTER TABLE shared.audit_log RENAME CONSTRAINT auditlog_pkey TO audit_log_pkey;
ALTER TABLE shared.audit_log_environments RENAME CONSTRAINT auditlog_environments_audit_id_fkey TO audit_log_environments_audit_id_fkey;
ALTER TABLE shared.audit_log_environments RENAME CONSTRAINT auditlog_environments_environment_id_fkey TO audit_log_environments_environment_id_fkey;
ALTER TABLE shared.audit_log_environments RENAME CONSTRAINT auditlog_environments_pkey TO audit_log_environments_pkey;
ALTER TABLE shared.audit_log_phenology_observations RENAME CONSTRAINT auditlog_phenologyobservations_audit_id_fkey TO audit_log_phenology_observations_audit_id_fkey;
ALTER TABLE shared.audit_log_phenology_observations RENAME CONSTRAINT auditlog_phenologyobservations_phenology_observation_id_fkey TO audit_log_phenology_observations_phenology_observation_id_fkey;
ALTER TABLE shared.audit_log_phenology_observations RENAME CONSTRAINT auditlog_phenologyobservations_pkey TO audit_log_phenology_observations_pkey;
ALTER TABLE shared.audit_log_point_clouds RENAME CONSTRAINT auditlog_pointclouds_audit_id_fkey TO audit_log_point_clouds_audit_id_fkey;
ALTER TABLE shared.audit_log_point_clouds RENAME CONSTRAINT auditlog_pointclouds_pkey TO audit_log_point_clouds_pkey;
ALTER TABLE shared.audit_log_point_clouds RENAME CONSTRAINT auditlog_pointclouds_point_cloud_id_fkey TO audit_log_point_clouds_point_cloud_id_fkey;
ALTER TABLE shared.audit_log_stems RENAME CONSTRAINT auditlog_stems_audit_id_fkey TO audit_log_stems_audit_id_fkey;
ALTER TABLE shared.audit_log_stems RENAME CONSTRAINT auditlog_stems_pkey TO audit_log_stems_pkey;
ALTER TABLE shared.audit_log_stems RENAME CONSTRAINT auditlog_stems_stem_id_fkey TO audit_log_stems_stem_id_fkey;
ALTER TABLE shared.audit_log_trees RENAME CONSTRAINT auditlog_trees_audit_id_fkey TO audit_log_trees_audit_id_fkey;
ALTER TABLE shared.audit_log_trees RENAME CONSTRAINT auditlog_trees_pkey TO audit_log_trees_pkey;
ALTER TABLE shared.audit_log_trees RENAME CONSTRAINT auditlog_trees_tree_id_fkey TO audit_log_trees_tree_id_fkey;
ALTER TABLE shared.climate_pathways RENAME CONSTRAINT climatepathways_pathway_id_check TO climate_pathways_pathway_id_check;
ALTER TABLE shared.climate_pathways RENAME CONSTRAINT climatepathways_pathway_name_check TO climate_pathways_pathway_name_check;
ALTER TABLE shared.climate_pathways RENAME CONSTRAINT climatepathways_pathway_name_key TO climate_pathways_pathway_name_key;
ALTER TABLE shared.climate_pathways RENAME CONSTRAINT climatepathways_pkey TO climate_pathways_pkey;
ALTER TABLE shared.climate_zones RENAME CONSTRAINT climatezones_climate_zone_name_key TO climate_zones_climate_zone_name_key;
ALTER TABLE shared.climate_zones RENAME CONSTRAINT climatezones_pkey TO climate_zones_pkey;
ALTER TABLE shared.management_regimes RENAME CONSTRAINT managementregimes_pkey TO management_regimes_pkey;
ALTER TABLE shared.management_regimes RENAME CONSTRAINT managementregimes_regime_id_check TO management_regimes_regime_id_check;
ALTER TABLE shared.management_regimes RENAME CONSTRAINT managementregimes_regime_name_check TO management_regimes_regime_name_check;
ALTER TABLE shared.management_regimes RENAME CONSTRAINT managementregimes_regime_name_key TO management_regimes_regime_name_key;
ALTER TABLE shared.processing_jobs RENAME CONSTRAINT processingjobs_external_job_id_key TO processing_jobs_external_job_id_key;
ALTER TABLE shared.processing_jobs RENAME CONSTRAINT processingjobs_pkey TO processing_jobs_pkey;
ALTER TABLE shared.processing_jobs RENAME CONSTRAINT processingjobs_status_check TO processing_jobs_status_check;
ALTER TABLE shared.soil_types RENAME CONSTRAINT soiltypes_pkey TO soil_types_pkey;
ALTER TABLE shared.soil_types RENAME CONSTRAINT soiltypes_soil_type_name_key TO soil_types_soil_type_name_key;
ALTER TABLE shared.variant_types RENAME CONSTRAINT varianttypes_pkey TO variant_types_pkey;
ALTER TABLE shared.variant_types RENAME CONSTRAINT varianttypes_variant_type_name_key TO variant_types_variant_type_name_key;
ALTER TABLE trees.data_source_types RENAME CONSTRAINT datasourcetypes_data_source_type_name_key TO data_source_types_data_source_type_name_key;
ALTER TABLE trees.data_source_types RENAME CONSTRAINT datasourcetypes_pkey TO data_source_types_pkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_basal_area_m2_check TO growth_simulations_basal_area_m2_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_base_tree_id_fkey TO growth_simulations_base_tree_id_fkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_biomass_kg_check TO growth_simulations_biomass_kg_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_carbon_content_kg_check TO growth_simulations_carbon_content_kg_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_crown_base_height_m_check TO growth_simulations_crown_base_height_m_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_crown_width_m_check TO growth_simulations_crown_width_m_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_dbh_cm_check TO growth_simulations_dbh_cm_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_health_score_check TO growth_simulations_health_score_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_height_m_check TO growth_simulations_height_m_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_location_id_fkey TO growth_simulations_location_id_fkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_pkey TO growth_simulations_pkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_plot_id_fkey TO growth_simulations_plot_id_fkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_projection_year_check TO growth_simulations_projection_year_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_run_id_fkey TO growth_simulations_run_id_fkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_scenario_id_fkey TO growth_simulations_scenario_id_fkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_simulator_name_check TO growth_simulations_simulator_name_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_species_id_fkey TO growth_simulations_species_id_fkey;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_stand_basal_area_m2ha_check TO growth_simulations_stand_basal_area_m2ha_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_stand_biomass_tha_check TO growth_simulations_stand_biomass_tha_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_stand_stem_count_ha_check TO growth_simulations_stand_stem_count_ha_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_stand_volume_m3ha_check TO growth_simulations_stand_volume_m3ha_check;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growthsimulations_volume_m3_check TO growth_simulations_volume_m3_check;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_base_variant_id_fkey TO simulation_runs_base_variant_id_fkey;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_base_year_check TO simulation_runs_base_year_check;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_horizon_years_check TO simulation_runs_horizon_years_check;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_location_id_fkey TO simulation_runs_location_id_fkey;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_pkey TO simulation_runs_pkey;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_process_id_fkey TO simulation_runs_process_id_fkey;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_run_params_is_object TO simulation_runs_run_params_is_object;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_scenario_id_fkey TO simulation_runs_scenario_id_fkey;
ALTER TABLE trees.simulation_runs RENAME CONSTRAINT simulationruns_simulator_name_check TO simulation_runs_simulator_name_check;
ALTER TABLE trees.tree_status RENAME CONSTRAINT treestatus_pkey TO tree_status_pkey;
ALTER TABLE trees.tree_status RENAME CONSTRAINT treestatus_tree_status_name_key TO tree_status_tree_status_name_key;

-- 5. The one constraint whose generated name runs out of room.
--    Postgres names an FK constraint <table>_<column>_fkey. Here the junction
--    table already carries the referenced entity, so the default repeats it:
--    audit_log_phenology_observations_phenology_observation_id_fkey is 62 bytes
--    against a 63-byte limit that Postgres enforces by silently truncating in
--    the middle. It was already 60 before this migration. Named explicitly and
--    shorter rather than left one byte from the cliff.
ALTER TABLE shared.audit_log_phenology_observations
    RENAME CONSTRAINT audit_log_phenology_observations_phenology_observation_id_fkey
    TO audit_log_phenology_observations_observation_fkey;
CREATE OR REPLACE FUNCTION public.sensorreadings_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO sensor.sensor_readings (sensor_id, timestamp, value, quality, scenario_id, battery_voltage, signal_strength, notes)
    VALUES (NEW.sensor_id, NEW.timestamp, NEW.value, NEW.quality, NEW.scenario_id, NEW.battery_voltage, NEW.signal_strength, NEW.notes);
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer DEFAULT 60)
 RETURNS TABLE(time_bucket timestamp with time zone, avg_value numeric, min_value numeric, max_value numeric, reading_count bigint)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        date_trunc('hour', sr."Timestamp") +
            ((EXTRACT(MINUTE FROM sr."Timestamp")::INTEGER / interval_minutes) * interval_minutes || ' minutes')::INTERVAL AS time_bucket,
        AVG(sr.Value) AS avg_value,
        MIN(sr.Value) AS min_value,
        MAX(sr.Value) AS max_value,
        COUNT(*) AS reading_count
    FROM sensor.sensor_readings sr
    WHERE sr.sensor_id = sensor_id_param
        AND sr."Timestamp" >= start_time
        AND sr."Timestamp" <= end_time
        AND sr.Quality IN ('good', 'suspect')
    GROUP BY time_bucket
    ORDER BY time_bucket;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer DEFAULT 100)
 RETURNS TABLE(audit_id bigint, field_name character varying, old_value text, new_value text, change_reason text, user_id character varying, "Timestamp" timestamp with time zone, change_type character varying)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    IF table_name_param = 'PointClouds' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_point_clouds alpc ON al.audit_id = alpc.audit_id
            WHERE alpc.point_cloud_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Trees' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_trees alt ON al.audit_id = alt.audit_id
            WHERE alt.tree_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Environments' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_environments ale ON al.audit_id = ale.audit_id
            WHERE ale.environment_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Stems' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_stems als ON al.audit_id = als.audit_id
            WHERE als.stem_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'PhenologyObservations' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_phenology_observations alp ON al.audit_id = alp.audit_id
            WHERE alp.phenology_observation_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    END IF;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying DEFAULT NULL::character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    new_variant_id INTEGER;
    calculated_variant_name VARCHAR;
BEGIN
    -- Generate variant name if not provided
    IF variant_name_param IS NULL THEN
        calculated_variant_name := 'Sensor_Aggregation_' ||
            location_id_param || '_' ||
            TO_CHAR(start_time, 'YYYY-MM-DD') || '_to_' ||
            TO_CHAR(end_time, 'YYYY-MM-DD');
    ELSE
        calculated_variant_name := variant_name_param;
    END IF;
    -- Insert aggregated environment variant
    INSERT INTO environments.Environments (
        location_id,
        variant_type_id,
        process_id,
        variant_name,
        start_date,
        end_date,
        avg_temperature_c,
        avg_humidity_percent,
        total_precipitation_mm,
        avg_co2_ppm,
        avg_wind_speed_ms,
        avg_soil_moisture_percent,
        avg_soil_temperature_c
    )
    SELECT
        location_id_param,
        (SELECT variant_type_id FROM shared.variant_types WHERE variant_type_name = 'sensor_derived'),
        (SELECT process_id FROM shared.Processes WHERE process_name = 'Sensor_Data_Aggregation' LIMIT 1),
        calculated_variant_name,
        start_time,
        end_time,
        AVG(CASE WHEN st.sensor_type_name = 'Temperature' THEN sr.Value END) AS avg_temperature_c,
        AVG(CASE WHEN st.sensor_type_name = 'Humidity' THEN sr.Value END) AS avg_humidity_percent,
        SUM(CASE WHEN st.sensor_type_name = 'Precipitation' THEN sr.Value END) AS total_precipitation_mm,
        AVG(CASE WHEN st.sensor_type_name = 'CO2' THEN sr.Value END) AS avg_co2_ppm,
        AVG(CASE WHEN st.sensor_type_name = 'Wind_Speed' THEN sr.Value END) AS avg_wind_speed_ms,
        AVG(CASE WHEN st.sensor_type_name = 'Soil_Moisture' THEN sr.Value END) AS avg_soil_moisture_percent,
        AVG(CASE WHEN st.sensor_type_name = 'Soil_Temperature' THEN sr.Value END) AS avg_soil_temperature_c
    FROM sensor.sensor_readings sr
    JOIN sensor.Sensors s ON sr.sensor_id = s.sensor_id
    JOIN sensor.sensor_types st ON s.sensor_type_id = st.sensor_type_id
    WHERE s.location_id = location_id_param
        AND sr.Timestamp >= start_time
        AND sr.Timestamp <= end_time
        AND sr.Quality IN ('good', 'suspect')
    HAVING COUNT(*) > 0
    RETURNING environment_id INTO new_variant_id;
    RETURN new_variant_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_readings(readings jsonb)
 RETURNS TABLE(out_inserted_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'sensor'
AS $function$
DECLARE
    inserted_count integer;
BEGIN
    INSERT INTO sensor.sensor_readings (sensor_id, timestamp, value, quality)
    SELECT 
        (r->>'sensor_id')::integer,
        (r->>'timestamp')::timestamptz,
        (r->>'value')::numeric,
        COALESCE(r->>'quality', 'good')
    FROM jsonb_array_elements(readings) AS r
    ON CONFLICT (sensor_id, timestamp) DO NOTHING;
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    RETURN QUERY SELECT inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION sensor.get_latest_reading(sensor_id_param integer)
 RETURNS TABLE(sensor_reading_id bigint, reading_timestamp timestamp with time zone, value numeric, quality character varying)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        sr.sensor_reading_id,
        sr."Timestamp",
        sr.Value,
        sr.Quality
    FROM sensor.sensor_readings sr
    WHERE sr.sensor_id = sensor_id_param
    ORDER BY sr."Timestamp" DESC
    LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer DEFAULT 24)
 RETURNS TABLE(sensor_id integer, ishealthy boolean, lastreading timestamp with time zone, readingscount bigint, goodqualitypercent numeric, issues text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    expected_readings INTEGER;
    actual_readings BIGINT;
    good_readings BIGINT;
    last_reading TIMESTAMPTZ;
    sampling_interval INTEGER;
    health_issues TEXT := '';
BEGIN
    -- Get sensor sampling interval
    SELECT s.sampling_interval_seconds, sr.Timestamp
    INTO sampling_interval, last_reading
    FROM sensor.Sensors s
    LEFT JOIN sensor.sensor_readings sr ON s.sensor_id = sr.sensor_id
    WHERE s.sensor_id = sensor_id_param
    ORDER BY sr.Timestamp DESC
    LIMIT 1;
    -- Calculate expected readings
    expected_readings := (hours_back * 3600) / sampling_interval;
    -- Count actual readings
    SELECT COUNT(*), COUNT(*) FILTER (WHERE Quality = 'good')
    INTO actual_readings, good_readings
    FROM sensor.sensor_readings sr
    WHERE sr.sensor_id = sensor_id_param
        AND sr.Timestamp > NOW() - (hours_back || ' hours')::INTERVAL;
    -- Check for issues
    IF last_reading < NOW() - (hours_back || ' hours')::INTERVAL THEN
        health_issues := health_issues || 'No recent readings; ';
    END IF;
    IF actual_readings < (expected_readings * 0.8) THEN
        health_issues := health_issues || 'Missing readings; ';
    END IF;
    IF actual_readings > 0 AND (good_readings::NUMERIC / actual_readings) < 0.9 THEN
        health_issues := health_issues || 'Low quality readings; ';
    END IF;
    RETURN QUERY SELECT
        sensor_id_param,
        (health_issues = '') AS IsHealthy,
        last_reading,
        actual_readings,
        CASE WHEN actual_readings > 0
            THEN ROUND((good_readings::NUMERIC / actual_readings * 100), 2)
            ELSE 0
        END AS GoodQualityPercent,
        NULLIF(TRIM(health_issues), '') AS Issues;
END;
$function$;

CREATE OR REPLACE FUNCTION sensor.link_sensors_to_trees_by_pattern()
 RETURNS TABLE(sensor_id integer, sensor_name text, tree_id integer, tree_info text, link_created boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
    sensor_rec RECORD;
    tree_rec RECORD;
    tree_number TEXT;
    links_created INTEGER := 0;
BEGIN
    -- Loop through all dendrometer and sap flow sensors
    FOR sensor_rec IN
        SELECT
            s.sensor_id,
            s.serial_number,
            s.external_metadata->>'LocationIdentifier' as location,
            st.sensor_type_name
        FROM sensor.sensors s
        JOIN sensor.sensor_types st ON s.sensor_type_id = st.sensor_type_id
        WHERE s.external_id IS NOT NULL
        AND st.sensor_type_name IN ('Stem_Radial_Variation', 'Sap_Flow')
        ORDER BY s.serial_number
    LOOP
        tree_number := NULL;
        -- Extract tree number from sensor name patterns
        IF sensor_rec.serial_number ~* '.*_([0-9]+)_(Dendrometer|SapFlow)$' THEN
            tree_number := substring(sensor_rec.serial_number from '.*_([0-9]+)_(Dendrometer|SapFlow)$');
        ELSIF sensor_rec.serial_number ~* '.*_([0-9]+)_(Drought|Control)$' THEN
            tree_number := substring(sensor_rec.serial_number from '.*_([0-9]+)_(Drought|Control)$');
        END IF;
        IF tree_number IS NOT NULL THEN
            SELECT t.tree_id, t.field_notes
            INTO tree_rec
            FROM trees.trees t
            WHERE t.field_notes IS NOT NULL
            AND (
                t.field_notes ~* ('tree_id: [0-9_]*' || tree_number || '[^0-9]')
                OR t.field_notes ~* ('FID: ' || tree_number || ' ')
            )
            LIMIT 1;
            IF tree_rec.tree_id IS NOT NULL THEN
                BEGIN
                    INSERT INTO sensor.sensor_tree_links (sensor_id, tree_id, description)
                    VALUES (
                        sensor_rec.sensor_id,
                        tree_rec.tree_id,
                        'Auto-linked based on sensor name: ' || sensor_rec.serial_number
                    )
                    ON CONFLICT (sensor_id, tree_id) DO NOTHING;
                    links_created := links_created + 1;
                    sensor_id := sensor_rec.sensor_id;
                    sensor_name := sensor_rec.serial_number;
                    tree_id := tree_rec.tree_id;
                    tree_info := tree_rec.field_notes;
                    link_created := TRUE;
                    RETURN NEXT;
                EXCEPTION WHEN OTHERS THEN
                    CONTINUE;
                END;
            END IF;
        END IF;
    END LOOP;
    RAISE NOTICE 'Created % sensor-tree links', links_created;
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
    SELECT * INTO audit_record FROM shared.audit_log WHERE audit_id = audit_id_param;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Audit record % not found', audit_id_param;
    END IF;
    IF EXISTS (SELECT 1 FROM shared.audit_log_point_clouds WHERE audit_id = audit_id_param) THEN
        table_name := 'PointClouds';
        SELECT point_cloud_id INTO variant_id FROM shared.audit_log_point_clouds WHERE audit_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_trees WHERE audit_id = audit_id_param) THEN
        table_name := 'Trees';
        SELECT tree_id INTO variant_id FROM shared.audit_log_trees WHERE audit_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_environments WHERE audit_id = audit_id_param) THEN
        table_name := 'Environments';
        SELECT environment_id INTO variant_id FROM shared.audit_log_environments WHERE audit_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_stems WHERE audit_id = audit_id_param) THEN
        table_name := 'Stems';
        SELECT stem_id INTO variant_id FROM shared.audit_log_stems WHERE audit_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_phenology_observations WHERE audit_id = audit_id_param) THEN
        table_name := 'PhenologyObservations';
        SELECT phenology_observation_id INTO variant_id FROM shared.audit_log_phenology_observations WHERE audit_id = audit_id_param;
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
    RETURNING audit_id INTO v_audit_id;
    CASE table_name_param
        WHEN 'PointClouds' THEN
            INSERT INTO shared.audit_log_point_clouds (audit_id, point_cloud_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Trees' THEN
            INSERT INTO shared.audit_log_trees (audit_id, tree_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Environments' THEN
            INSERT INTO shared.audit_log_environments (audit_id, environment_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Stems' THEN
            INSERT INTO shared.audit_log_stems (audit_id, stem_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'PhenologyObservations' THEN
            INSERT INTO shared.audit_log_phenology_observations (audit_id, phenology_observation_id)
            VALUES (v_audit_id, variant_id_param);
    END CASE;
    RETURN v_audit_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.request_job(workflow text, params jsonb DEFAULT '{}'::jsonb, external_job_id text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    proc   record;
    job_id integer;
BEGIN
    IF NOT shared.is_contributor() THEN
        RAISE EXCEPTION 'requesting a job requires the contributor role'
            USING ERRCODE = '42501',
                  HINT = 'The caller needs an app_metadata.role of contributor, '
                         'curator or admin -- see data-access-guide.md, '
                         '"Assigning a role tier". Note that the Studio SQL '
                         'Editor connects as supabase_admin with no JWT, so it '
                         'can never satisfy this check however privileged the '
                         'person at the keyboard is.';
    END IF;
    SELECT p.workflow_key, p.version, p.param_schema
      INTO proc
      FROM shared.Processes p
     WHERE p.workflow_key = request_job.workflow;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown workflow "%"', request_job.workflow
            USING ERRCODE = '22023',
                  HINT = 'select workflow_key, description from public.workflows;';
    END IF;
    PERFORM shared.validate_against_param_schema(
        proc.param_schema, coalesce(request_job.params, '{}'::jsonb));
    IF request_job.external_job_id IS NOT NULL THEN
        SELECT j.processing_job_id INTO job_id
          FROM shared.processing_jobs j
         WHERE j.external_job_id = request_job.external_job_id;
        IF FOUND THEN
            RETURN job_id;
        END IF;
    END IF;
    INSERT INTO shared.processing_jobs
        (external_job_id, workflow_name, workflow_version, status, input_data, submitted_by)
    VALUES (request_job.external_job_id, proc.workflow_key, proc.version, 'pending',
            coalesce(request_job.params, '{}'::jsonb), auth.uid()::text)
    ON CONFLICT ON CONSTRAINT processingjobs_external_job_id_key DO NOTHING
    RETURNING processing_job_id INTO job_id;
    IF job_id IS NULL THEN
        SELECT j.processing_job_id INTO job_id
          FROM shared.processing_jobs j
         WHERE j.external_job_id = request_job.external_job_id;
    END IF;
    RETURN job_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_soil_aggregates(p_location_id integer DEFAULT NULL::integer, p_year integer DEFAULT NULL::integer, p_min_days_per_quarter integer DEFAULT 7, p_dry_run boolean DEFAULT false)
 RETURNS TABLE(out_location_id integer, out_year integer, out_start_date date, out_end_date date, out_avg_soil_moisture_percent numeric, out_avg_soil_temperature_c numeric, out_environment_id integer, out_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared', 'sensor', 'environments'
AS $function$
DECLARE
    v_process_id integer;
    v_row record;
    v_values jsonb;
    v_environment_id integer;
    v_description text;
    v_written text[];
    v_refused text[];
    v_first date;
    v_last date;
BEGIN
    SELECT process_id INTO v_process_id
      FROM shared.Processes
     WHERE process_name = 'Soil Aggregates from Sensor Readings'
       AND version = '1.0';
    IF v_process_id IS NULL THEN
        RAISE EXCEPTION 'the Soil Aggregates process row is missing -- '
                        'migration 20260903130000 did not fully apply';
    END IF;
    FOR v_row IN
        WITH reading AS (
            -- One row per accepted reading, carrying everything the nesting
            -- needs. The range filter is the sensor type's own declaration.
            SELECT s.location_id,
                   st.sensor_type_name                       AS quantity,
                   s.unit                                    AS unit,
                   r.sensor_id,
                   (r.timestamp AT TIME ZONE 'UTC')::date    AS day,
                   EXTRACT(YEAR    FROM r.timestamp AT TIME ZONE 'UTC')::integer AS yr,
                   EXTRACT(QUARTER FROM r.timestamp AT TIME ZONE 'UTC')::integer AS qtr,
                   r.value
              FROM sensor.sensor_readings r
              JOIN sensor.Sensors        s  USING (sensor_id)
              JOIN sensor.sensor_types    st USING (sensor_type_id)
             WHERE st.sensor_type_name IN ('soil_moisture', 'soil_temperature')
               AND r.value BETWEEN st.typical_range_min AND st.typical_range_max
               AND (p_location_id IS NULL OR s.location_id = p_location_id)
               AND (p_year IS NULL
                    OR EXTRACT(YEAR FROM r.timestamp AT TIME ZONE 'UTC')::integer = p_year)
        ),
        -- Level 1: a sensor's own day.
        sensor_day AS (
            SELECT location_id, quantity, yr, qtr, day, sensor_id, avg(value) AS v
              FROM reading GROUP BY 1, 2, 3, 4, 5, 6
        ),
        -- Level 2: the day across sensors.
        day_mean AS (
            SELECT location_id, quantity, yr, qtr, day, avg(v) AS v
              FROM sensor_day GROUP BY 1, 2, 3, 4, 5
        ),
        -- Level 3: the quarter across its measured days.
        quarter_mean AS (
            SELECT location_id, quantity, yr, qtr, avg(v) AS v, count(*) AS days
              FROM day_mean GROUP BY 1, 2, 3, 4
        ),
        -- Level 4: the year across its qualifying quarters, plus the count
        -- needed to judge whether the year may be written at all.
        year_mean AS (
            SELECT location_id, quantity, yr,
                   avg(v)  FILTER (WHERE days >= p_min_days_per_quarter) AS v,
                   count(*) FILTER (WHERE days >= p_min_days_per_quarter) AS quarters
              FROM quarter_mean GROUP BY 1, 2, 3
        ),
        -- Units are checked over every reading of the quantity, not only the
        -- qualifying quarters: a second unit anywhere in the year means the
        -- series is not one series.
        units AS (
            SELECT location_id, quantity, yr, count(DISTINCT unit) AS units,
                   min(day) AS first_day, max(day) AS last_day
              FROM reading GROUP BY 1, 2, 3
        ),
        per_quantity AS (
            SELECT y.location_id, y.quantity, y.yr, y.v, y.quarters,
                   u.units, u.first_day, u.last_day
              FROM year_mean y JOIN units u USING (location_id, quantity, yr)
        )
        SELECT location_id,
               yr,
               max(v)         FILTER (WHERE quantity = 'soil_moisture')    AS moisture,
               max(quarters)  FILTER (WHERE quantity = 'soil_moisture')    AS moisture_quarters,
               max(units)     FILTER (WHERE quantity = 'soil_moisture')    AS moisture_units,
               min(first_day) FILTER (WHERE quantity = 'soil_moisture')    AS moisture_first,
               max(last_day)  FILTER (WHERE quantity = 'soil_moisture')    AS moisture_last,
               max(v)         FILTER (WHERE quantity = 'soil_temperature') AS temperature,
               max(quarters)  FILTER (WHERE quantity = 'soil_temperature') AS temperature_quarters,
               max(units)     FILTER (WHERE quantity = 'soil_temperature') AS temperature_units,
               min(first_day) FILTER (WHERE quantity = 'soil_temperature') AS temperature_first,
               max(last_day)  FILTER (WHERE quantity = 'soil_temperature') AS temperature_last
          FROM per_quantity
         GROUP BY 1, 2
         ORDER BY 1, 2
    LOOP
        out_location_id := v_row.location_id;
        out_year        := v_row.yr;
        out_environment_id := NULL;
        out_avg_soil_moisture_percent := NULL;
        out_avg_soil_temperature_c    := NULL;
        v_written := ARRAY[]::text[];
        v_refused := ARRAY[]::text[];
        v_values  := '{}'::jsonb;
        v_first   := NULL;
        v_last    := NULL;
        -- soil moisture
        IF v_row.moisture_units IS NULL THEN
            NULL;  -- the quantity is simply not measured here
        ELSIF v_row.moisture_units > 1 THEN
            v_refused := v_refused || format(
                'soil moisture: sensors report %s different units, so a mean would '
                'mix scales', v_row.moisture_units);
        ELSIF v_row.moisture_quarters < 4 THEN
            v_refused := v_refused || format(
                'soil moisture: only %s of 4 quarters have %s or more measured days, '
                'so an annual mean would be a seasonal one',
                v_row.moisture_quarters, p_min_days_per_quarter);
        ELSE
            out_avg_soil_moisture_percent := round(v_row.moisture::numeric, 3);
            v_values := v_values || jsonb_build_object(
                'avg_soil_moisture_percent', out_avg_soil_moisture_percent);
            v_written := v_written || 'soil moisture'::text;
            v_first := least(v_first, v_row.moisture_first);
            v_last  := greatest(v_last, v_row.moisture_last);
        END IF;
        -- soil temperature
        IF v_row.temperature_units IS NULL THEN
            NULL;
        ELSIF v_row.temperature_units > 1 THEN
            v_refused := v_refused || format(
                'soil temperature: sensors report %s different units, so a mean would '
                'mix scales', v_row.temperature_units);
        ELSIF v_row.temperature_quarters < 4 THEN
            v_refused := v_refused || format(
                'soil temperature: only %s of 4 quarters have %s or more measured days, '
                'so an annual mean would be a seasonal one',
                v_row.temperature_quarters, p_min_days_per_quarter);
        ELSE
            out_avg_soil_temperature_c := round(v_row.temperature::numeric, 3);
            v_values := v_values || jsonb_build_object(
                'avg_soil_temperature_c', out_avg_soil_temperature_c);
            v_written := v_written || 'soil temperature'::text;
            v_first := least(v_first, v_row.temperature_first);
            v_last  := greatest(v_last, v_row.temperature_last);
        END IF;
        IF v_values = '{}'::jsonb THEN
            out_status := 'skipped -- ' || array_to_string(v_refused, '; ');
            RETURN NEXT;
            CONTINUE;
        END IF;
        -- The window is the one the written quantities were measured over, not
        -- the calendar year they fall in and not a refused quantity's span.
        out_start_date := v_first;
        out_end_date   := v_last;
        v_description := format(
            'Measured %s at this location, %s to %s. Quarter-balanced nested mean: '
            'each sensor weighted equally within a day, each day within its quarter, '
            'each of the 4 quarters within the year, so the value is not weighted by '
            'sampling density. Readings outside the range sensor.sensor_types declares '
            'for the quantity are excluded. Sensor depth is not recorded in the twin, '
            'so this is a mean across the depths the network sits at, not a profile.',
            array_to_string(v_written, ' and '), v_first, v_last);
        IF p_dry_run THEN
            out_status := 'dry run: ' || v_description;
            IF array_length(v_refused, 1) IS NOT NULL THEN
                out_status := out_status || ' Refused -- ' || array_to_string(v_refused, '; ');
            END IF;
            RETURN NEXT;
            CONTINUE;
        END IF;
        SELECT e.out_environment_id INTO v_environment_id
          FROM public.upsert_environment(
                   p_location_id      => v_row.location_id,
                   -- 6 = sensor_derived, "Aggregated or derived from sensor
                   -- readings". Not 7/model_output: nothing was modelled.
                   p_variant_type_id  => 6,
                   p_variant_name     => 'twin-sensors',
                   p_process_id       => v_process_id,
                   p_values           => v_values,
                   -- No scenario. This is what was measured, not a projection,
                   -- and a scenario_id would assert a pathway it does not have.
                   p_scenario_id      => NULL,
                   p_start_date       => v_first::timestamptz,
                   p_end_date         => (v_last + 1)::timestamptz - interval '1 second',
                   p_description      => v_description
               ) AS e;
        IF v_environment_id IS NULL THEN
            RAISE EXCEPTION 'upsert_environment returned no environment_id for '
                            'location % year %', v_row.location_id, v_row.yr;
        END IF;
        out_environment_id := v_environment_id;
        out_status := 'written: ' || array_to_string(v_written, ' and ');
        IF array_length(v_refused, 1) IS NOT NULL THEN
            out_status := out_status || '; refused -- ' || array_to_string(v_refused, '; ');
        END IF;
        RETURN NEXT;
    END LOOP;
    RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.scenario_axes_from_name(p_name text)
 RETURNS TABLE(management_regime_id smallint, climate_pathway_id smallint)
 LANGUAGE sql
 STABLE
AS $function$
    -- <pathway> alone: a climate-data bucket, regime none.
    SELECT 0::smallint, cp.pathway_id
    FROM shared.climate_pathways cp
    WHERE cp.pathway_name = p_name
    UNION ALL
    -- <regime> alone: that regime under the historical climate.
    SELECT mr.regime_id, 0::smallint
    FROM shared.management_regimes mr
    WHERE mr.regime_name = p_name AND mr.regime_id <> 0
    UNION ALL
    -- <regime>_<pathway>.
    SELECT mr.regime_id, cp.pathway_id
    FROM shared.management_regimes mr
    JOIN shared.climate_pathways cp ON p_name = mr.regime_name || '_' || cp.pathway_name
    WHERE mr.regime_id <> 0 AND cp.pathway_id <> 0
    LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION shared.scenarios_derive_axes()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    a record;
BEGIN
    IF NEW.management_regime_id IS NULL OR NEW.climate_pathway_id IS NULL THEN
        SELECT * INTO a FROM shared.scenario_axes_from_name(NEW.scenario_name);
        IF NOT FOUND THEN
            RAISE EXCEPTION 'scenario name ''%'' does not fit <pathway> | <regime> | <regime>_<pathway> (see shared.management_regimes / shared.climate_pathways); pass management_regime_id and climate_pathway_id explicitly or use a conforming name',
                NEW.scenario_name USING ERRCODE = '22023';
        END IF;
        NEW.management_regime_id := coalesce(NEW.management_regime_id, a.management_regime_id);
        NEW.climate_pathway_id   := coalesce(NEW.climate_pathway_id,   a.climate_pathway_id);
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval DEFAULT NULL::interval)
 RETURNS TABLE(sensor_id integer, source character varying, sensor_type character varying, unit character varying, "timestamp" timestamp with time zone, value numeric, quality character varying, linked_tree_id integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.sensor_id,
           s.source,
           st.sensor_type_name AS sensor_type,
           s.unit,
           r."timestamp",
           r.value,
           r.quality,
           stl.tree_id AS linked_tree_id
      FROM sensor.sensors s
      JOIN sensor.sensor_types st
        ON st.sensor_type_id = s.sensor_type_id
      LEFT JOIN sensor.sensor_tree_links stl
        ON stl.sensor_id = s.sensor_id
     CROSS JOIN LATERAL (
            -- One index seek per sensor. Both bounds are needed: the upper one
            -- is the question being asked, the lower one is what keeps this an
            -- index range scan instead of a walk back through every reading the
            -- sensor has ever produced. Its width is the caller's, or four of
            -- this sensor's stored sampling intervals.
            SELECT sr."timestamp", sr.value, sr.quality
              FROM sensor.sensor_readings sr
             WHERE sr.sensor_id = s.sensor_id
               AND sr."timestamp" <= p_timestamp
               AND sr."timestamp" >  p_timestamp
                                     - coalesce(p_lookback,
                                                (4 * s.sampling_interval_seconds) * interval '1 second')
             ORDER BY sr."timestamp" DESC
             LIMIT 1
     ) r;
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
                geometric_solid_name VARCHAR(50),
                Description TEXT,
                relative_lateral_area NUMERIC(4, 2),
                relative_volume NUMERIC(4, 2),
                relative_drag NUMERIC(4, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_solids;
            EXECUTE format('COPY _temp_solids FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'geometric_crown_solids.csv');
            INSERT INTO trees.geometric_crown_solids (geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag)
            SELECT geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag FROM _temp_solids
            ON CONFLICT (geometric_solid_name) DO UPDATE SET
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
