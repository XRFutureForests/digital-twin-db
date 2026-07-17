--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

-- Baked into the base supabase/postgres image via its own bootstrap; restated here
-- with IF NOT EXISTS so this baseline is self-contained and replay-safe.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA extensions CASCADE;
CREATE EXTENSION IF NOT EXISTS postgis_topology SCHEMA extensions CASCADE;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA extensions TO anon, authenticated, service_role;
ALTER DATABASE postgres SET search_path TO "$user", public, extensions;

--
-- Name: environments; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS environments;


--
-- Name: imagery; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS imagery;


--
-- Name: pointclouds; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS pointclouds;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: sensor; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS sensor;


--
-- Name: shared; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS shared;


--
-- Name: trees; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS trees;


--
-- Name: calculate_duration_days(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: environments; Owner: -
--

CREATE FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF start_date IS NULL OR end_date IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN EXTRACT(DAY FROM (end_date - start_date))::INTEGER;
END;
$$;


--
-- Name: FUNCTION calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone); Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) IS 'Calculates duration in days between start and end dates';


--
-- Name: create_from_sensor_data(integer, timestamp with time zone, timestamp with time zone, character varying); Type: FUNCTION; Schema: environments; Owner: -
--

CREATE FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying DEFAULT NULL::character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
        (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'sensor_derived'),
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
    FROM sensor.SensorReadings sr
    JOIN sensor.Sensors s ON sr.sensor_id = s.sensor_id
    JOIN sensor.SensorTypes st ON s.sensor_type_id = st.sensor_type_id
    WHERE s.location_id = location_id_param
        AND sr.Timestamp >= start_time
        AND sr.Timestamp <= end_time
        AND sr.Quality IN ('good', 'suspect')
    HAVING COUNT(*) > 0
    RETURNING environment_id INTO new_variant_id;

    RETURN new_variant_id;
END;
$$;


--
-- Name: FUNCTION create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying); Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) IS 'Creates environment variant by aggregating sensor readings';


--
-- Name: is_active(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: environments; Owner: -
--

CREATE FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW());
END;
$$;


--
-- Name: FUNCTION is_active(start_date timestamp with time zone, end_date timestamp with time zone); Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) IS 'Checks if environment variant is currently active';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: environments; Owner: -
--

CREATE FUNCTION environments.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: imagery; Owner: -
--

CREATE FUNCTION imagery.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: get_s3_bucket(text); Type: FUNCTION; Schema: pointclouds; Owner: -
--

CREATE FUNCTION pointclouds.get_s3_bucket(file_path text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN substring(file_path FROM 's3://([^/]+)/');
END;
$$;


--
-- Name: FUNCTION get_s3_bucket(file_path text); Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON FUNCTION pointclouds.get_s3_bucket(file_path text) IS 'Extracts S3 bucket name from file_path';


--
-- Name: get_s3_key(text); Type: FUNCTION; Schema: pointclouds; Owner: -
--

CREATE FUNCTION pointclouds.get_s3_key(file_path text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN substring(file_path FROM 's3://[^/]+/(.+)');
END;
$$;


--
-- Name: FUNCTION get_s3_key(file_path text); Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON FUNCTION pointclouds.get_s3_key(file_path text) IS 'Extracts S3 object key (path) from file_path';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: pointclouds; Owner: -
--

CREATE FUNCTION pointclouds.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: validate_s3_uri(text); Type: FUNCTION; Schema: pointclouds; Owner: -
--

CREATE FUNCTION pointclouds.validate_s3_uri(file_path text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    RETURN file_path ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$';
END;
$_$;


--
-- Name: FUNCTION validate_s3_uri(file_path text); Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON FUNCTION pointclouds.validate_s3_uri(file_path text) IS 'Validates S3 URI format for point cloud files';


--
-- Name: bulk_insert_readings(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bulk_insert_readings(readings jsonb) RETURNS TABLE(out_inserted_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'sensor'
    AS $$
DECLARE
    inserted_count integer;
BEGIN
    INSERT INTO sensor.sensorreadings (sensor_id, timestamp, value, quality)
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
$$;


--
-- Name: FUNCTION bulk_insert_readings(readings jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.bulk_insert_readings(readings jsonb) IS 'Bulk inserts readings from JSON array, skips duplicates';


--
-- Name: bulk_upsert_sensors(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) RETURNS TABLE(out_externalid character varying, out_sensorid integer)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    sensor_rec JSONB;
    v_position extensions.geometry;
BEGIN
    FOR sensor_rec IN SELECT * FROM jsonb_array_elements(p_sensors)
    LOOP
        -- Parse position WKT if provided
        IF sensor_rec->>'position' IS NOT NULL THEN
            v_position := extensions.ST_GeomFromText(sensor_rec->>'position', 4326);
        ELSE
            v_position := NULL;
        END IF;

        INSERT INTO sensor.sensors (
            location_id, plot_id, source, sensor_type_id, sensor_model, serial_number,
            position, sampling_interval_seconds, unit, external_id,
            external_metadata, is_active, created_by
        )
        VALUES (
            (sensor_rec->>'location_id')::INT,
            (sensor_rec->>'plot_id')::INT,
            sensor_rec->>'source',
            (sensor_rec->>'sensor_type_id')::INT,
            sensor_rec->>'sensor_model',
            sensor_rec->>'serial_number',
            v_position,
            (sensor_rec->>'sampling_interval_seconds')::INT,
            sensor_rec->>'unit',
            sensor_rec->>'external_id',
            (sensor_rec->'external_metadata')::JSONB,
            (sensor_rec->>'is_active')::BOOLEAN,
            sensor_rec->>'created_by'
        )
        ON CONFLICT (external_id) DO UPDATE SET
            location_id = EXCLUDED.location_id,
            plot_id = EXCLUDED.plot_id,
            source = EXCLUDED.source,
            sensor_type_id = EXCLUDED.sensor_type_id,
            sensor_model = EXCLUDED.sensor_model,
            serial_number = EXCLUDED.serial_number,
            position = EXCLUDED.position,
            sampling_interval_seconds = EXCLUDED.sampling_interval_seconds,
            unit = EXCLUDED.unit,
            external_metadata = EXCLUDED.external_metadata,
            is_active = EXCLUDED.is_active,
            updated_by = EXCLUDED.created_by,
            updated_at = NOW();
        
        RETURN QUERY SELECT 
            (sensor_rec->>'external_id')::VARCHAR AS out_externalid, 
            (SELECT s.sensor_id FROM sensor.sensors s WHERE s.external_id = sensor_rec->>'external_id') AS out_sensorid;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION bulk_upsert_sensors(p_sensors jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) IS 'Bulk upserts sensors from JSON array, returns external IDs and sensor IDs';


--
-- Name: campaigns_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.campaigns_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM shared.campaigns WHERE campaign_id = OLD.campaign_id;
    RETURN OLD;
END;
$$;


--
-- Name: FUNCTION campaigns_delete(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.campaigns_delete() IS 'INSTEAD OF DELETE trigger function for public.campaigns view';


--
-- Name: campaigns_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.campaigns_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.campaigns (
        campaign_name, campaign_type, location_id, start_date, end_date,
        description, methodology, equipment, personnel,
        created_by, updated_by
    ) VALUES (
        NEW.campaign_name, NEW.campaign_type, NEW.location_id, NEW.start_date, NEW.end_date,
        NEW.description, NEW.methodology, NEW.equipment, NEW.personnel,
        NEW.created_by, NEW.updated_by
    ) RETURNING campaign_id INTO NEW.campaign_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION campaigns_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.campaigns_insert() IS 'INSTEAD OF INSERT trigger function for public.campaigns view';


--
-- Name: campaigns_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.campaigns_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE shared.campaigns SET
        campaign_name = NEW.campaign_name,
        campaign_type = NEW.campaign_type,
        location_id = NEW.location_id,
        start_date = NEW.start_date,
        end_date = NEW.end_date,
        description = NEW.description,
        methodology = NEW.methodology,
        equipment = NEW.equipment,
        personnel = NEW.personnel,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE campaign_id = OLD.campaign_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION campaigns_update(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.campaigns_update() IS 'INSTEAD OF UPDATE trigger function for public.campaigns view';


--
-- Name: deadwood_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deadwood_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.deadwood (
        location_id, plot_id, tree_id, species_id,
        wood_type, length_m, diameter_cm, decay_class,
        volume_m3, position, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.tree_id, NEW.species_id,
        NEW.wood_type, NEW.length_m, NEW.diameter_cm, NEW.decay_class,
        NEW.volume_m3, NEW.position, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING deadwood_id INTO NEW.deadwood_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION deadwood_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deadwood_insert() IS 'INSTEAD OF INSERT trigger function for public.deadwood view';


--
-- Name: disturbanceevents_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.disturbanceevents_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.disturbanceevents (
        location_id, plot_id, disturbance_type, event_date, end_date,
        severity, affected_area_m2, description, notes,
        created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.disturbance_type, NEW.event_date, NEW.end_date,
        NEW.severity, NEW.affected_area_m2, NEW.description, NEW.notes,
        NEW.created_by, NEW.updated_by
    ) RETURNING disturbance_event_id INTO NEW.disturbance_event_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION disturbanceevents_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.disturbanceevents_insert() IS 'INSTEAD OF INSERT trigger function for public.disturbanceevents view';


--
-- Name: environments_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.environments_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO environments.environments SELECT NEW.*;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION environments_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.environments_insert() IS 'INSTEAD OF INSERT trigger function for public.environments view';


--
-- Name: groundvegetation_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.groundvegetation_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.groundvegetation (
        location_id, plot_id, species_name, cover_percent,
        height_cm, layer, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.species_name, NEW.cover_percent,
        NEW.height_cm, NEW.layer, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING ground_vegetation_id INTO NEW.ground_vegetation_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION groundvegetation_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.groundvegetation_insert() IS 'INSTEAD OF INSERT trigger function for public.groundvegetation view';


--
-- Name: images_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.images_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO imagery.images (
        location_id, plot_id, campaign_id, capture_date,
        file_path, file_format, resolution_px, camera_model,
        position, altitude_m, heading_deg, pitch_deg, roll_deg,
        ground_sample_distance_cm, description, created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.campaign_id, NEW.capture_date,
        NEW.file_path, NEW.file_format, NEW.resolution_px, NEW.camera_model,
        NEW.position, NEW.altitude_m, NEW.heading_deg, NEW.pitch_deg, NEW.roll_deg,
        NEW.ground_sample_distance_cm, NEW.description, NEW.created_by, NEW.updated_by
    ) RETURNING image_id INTO NEW.image_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION images_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.images_insert() IS 'INSTEAD OF INSERT trigger function for public.images view';


--
-- Name: managementevents_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.managementevents_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.managementevents (
        location_id, plot_id, event_type, event_date, end_date,
        description, affected_area_m2, performed_by, notes,
        created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.event_type, NEW.event_date, NEW.end_date,
        NEW.description, NEW.affected_area_m2, NEW.performed_by, NEW.notes,
        NEW.created_by, NEW.updated_by
    ) RETURNING management_event_id INTO NEW.management_event_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION managementevents_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.managementevents_insert() IS 'INSTEAD OF INSERT trigger function for public.managementevents view';


--
-- Name: phenologyobservations_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.phenologyobservations_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.phenologyobservations (
        tree_id, observation_date, phenophase_type,
        phenophase_status, intensity_percent, observer, notes, created_by
    ) VALUES (
        NEW.tree_id, NEW.observation_date, NEW.phenophase_type,
        NEW.phenophase_status, NEW.intensity_percent, NEW.observer, NEW.notes, NEW.created_by
    ) RETURNING phenology_observation_id INTO NEW.phenology_observation_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION phenologyobservations_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.phenologyobservations_insert() IS 'INSTEAD OF INSERT trigger function for public.phenologyobservations view';


--
-- Name: plots_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.plots_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.plots (
        location_id, plot_name, plot_number, area_m2,
        boundary, center_point, description,
        created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_name, NEW.plot_number, NEW.area_m2,
        NEW.boundary, NEW.center_point, NEW.description,
        NEW.created_by, NEW.updated_by
    ) RETURNING plot_id INTO NEW.plot_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION plots_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.plots_insert() IS 'INSTEAD OF INSERT trigger function for public.plots view';


--
-- Name: pointclouds_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pointclouds_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO pointclouds.pointclouds SELECT NEW.*;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION pointclouds_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.pointclouds_insert() IS 'INSTEAD OF INSERT trigger function for public.pointclouds view';


--
-- Name: sensor_tree_links_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensor_tree_links_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO sensor.sensor_tree_links (sensor_id, tree_id, description, start_date, end_date)
    VALUES (NEW.sensor_id, NEW.tree_id, NEW.description, NEW.start_date, NEW.end_date)
    ON CONFLICT (sensor_id, tree_id) DO NOTHING;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION sensor_tree_links_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sensor_tree_links_insert() IS 'INSTEAD OF INSERT trigger for public.sensor_tree_links view';


--
-- Name: sensorreadings_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensorreadings_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO sensor.sensorreadings (sensor_id, timestamp, value, quality, scenario_id, battery_voltage, signal_strength, notes)
    VALUES (NEW.sensor_id, NEW.timestamp, NEW.value, NEW.quality, NEW.scenario_id, NEW.battery_voltage, NEW.signal_strength, NEW.notes);
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION sensorreadings_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sensorreadings_insert() IS 'INSTEAD OF INSERT trigger function for public.sensorreadings view';


--
-- Name: sensors_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensors_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM sensor.sensors WHERE sensor_id = OLD.sensor_id;
    RETURN OLD;
END;
$$;


--
-- Name: sensors_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensors_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO sensor.sensors SELECT NEW.*;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION sensors_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sensors_insert() IS 'INSTEAD OF INSERT trigger function for public.sensors view';


--
-- Name: sensors_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sensors_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE sensor.sensors SET
        location_id = NEW.location_id,
        sensor_type_id = NEW.sensor_type_id,
        campaign_id = NEW.campaign_id,
        sensor_model = NEW.sensor_model,
        serial_number = NEW.serial_number,
        position = NEW.position,
        position_original = NEW.position_original,
        source_crs = NEW.source_crs,
        installation_date = NEW.installation_date,
        installation_height_m = NEW.installation_height_m,
        decommission_date = NEW.decommission_date,
        calibration_date = NEW.calibration_date,
        next_calibration_date = NEW.next_calibration_date,
        sampling_interval_seconds = NEW.sampling_interval_seconds,
        reading_type = NEW.reading_type,
        unit = NEW.unit,
        min_value = NEW.min_value,
        max_value = NEW.max_value,
        accuracy = NEW.accuracy,
        battery_level_percent = NEW.battery_level_percent,
        is_active = NEW.is_active,
        maintenance_notes = NEW.maintenance_notes,
        external_id = NEW.external_id,
        external_metadata = NEW.external_metadata,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE sensor_id = OLD.sensor_id;
    RETURN NEW;
END;
$$;


--
-- Name: stems_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stems_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.stems SELECT NEW.*;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION stems_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.stems_insert() IS 'INSTEAD OF INSERT trigger function for public.stems view';


--
-- Name: trees_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trees_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM trees.trees WHERE tree_id = OLD.tree_id;
    RETURN OLD;
END;
$$;


--
-- Name: FUNCTION trees_delete(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trees_delete() IS 'INSTEAD OF DELETE trigger function for public.trees view';


--
-- Name: trees_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trees_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.trees (
        tree_entity_id, variant_id, parent_tree_id, point_cloud_id, campaign_id,
        location_id, plot_id, scenario_id, variant_type_id, process_id,
        species_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
        measurement_date, data_source_type_id,
        height_m, crown_width_m, crown_base_height_m, crown_boundary,
        crown_offset_x_m, crown_offset_y_m, volume_m3,
        position, position_original, source_crs,
        lean_angle_deg, lean_direction_azimuth, time_delta_yrs, age_years,
        health_score, biomass_kg, carbon_content_kg,
        species_confidence, position_confidence, height_confidence,
        crown_class_id, damage_agent_id, defoliation_percent, discolouration_percent, crown_transparency_percent,
        status_change_date, field_notes, created_by, updated_by
    ) VALUES (
        COALESCE(NEW.tree_entity_id, gen_random_uuid()), NEW.variant_id, NEW.parent_tree_id, NEW.point_cloud_id, NEW.campaign_id,
        NEW.location_id, NEW.plot_id, NEW.scenario_id, NEW.variant_type_id, NEW.process_id,
        NEW.species_id, NEW.tree_status_id, NEW.branching_pattern_id, NEW.bark_characteristic_id,
        NEW.measurement_date, NEW.data_source_type_id,
        NEW.height_m, NEW.crown_width_m, NEW.crown_base_height_m, NEW.crown_boundary,
        NEW.crown_offset_x_m, NEW.crown_offset_y_m, NEW.volume_m3,
        NEW.position, NEW.position_original, NEW.source_crs,
        NEW.lean_angle_deg, NEW.lean_direction_azimuth, NEW.time_delta_yrs, NEW.age_years,
        NEW.health_score, NEW.biomass_kg, NEW.carbon_content_kg,
        NEW.species_confidence, NEW.position_confidence, NEW.height_confidence,
        NEW.crown_class_id, NEW.damage_agent_id, NEW.defoliation_percent, NEW.discolouration_percent, NEW.crown_transparency_percent,
        NEW.status_change_date, NEW.field_notes, NEW.created_by, NEW.updated_by
    ) RETURNING tree_id INTO NEW.tree_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION trees_insert(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trees_insert() IS 'INSTEAD OF INSERT trigger function for public.trees view';


--
-- Name: trees_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trees_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE trees.trees SET
        tree_entity_id = NEW.tree_entity_id,
        variant_id = NEW.variant_id,
        parent_tree_id = NEW.parent_tree_id,
        point_cloud_id = NEW.point_cloud_id,
        campaign_id = NEW.campaign_id,
        location_id = NEW.location_id,
        plot_id = NEW.plot_id,
        scenario_id = NEW.scenario_id,
        variant_type_id = NEW.variant_type_id,
        process_id = NEW.process_id,
        species_id = NEW.species_id,
        tree_status_id = NEW.tree_status_id,
        branching_pattern_id = NEW.branching_pattern_id,
        bark_characteristic_id = NEW.bark_characteristic_id,
        measurement_date = NEW.measurement_date,
        data_source_type_id = NEW.data_source_type_id,
        height_m = NEW.height_m,
        crown_width_m = NEW.crown_width_m,
        crown_base_height_m = NEW.crown_base_height_m,
        crown_boundary = NEW.crown_boundary,
        crown_offset_x_m = NEW.crown_offset_x_m,
        crown_offset_y_m = NEW.crown_offset_y_m,
        volume_m3 = NEW.volume_m3,
        position = NEW.position,
        position_original = NEW.position_original,
        source_crs = NEW.source_crs,
        lean_angle_deg = NEW.lean_angle_deg,
        lean_direction_azimuth = NEW.lean_direction_azimuth,
        time_delta_yrs = NEW.time_delta_yrs,
        age_years = NEW.age_years,
        health_score = NEW.health_score,
        biomass_kg = NEW.biomass_kg,
        carbon_content_kg = NEW.carbon_content_kg,
        species_confidence = NEW.species_confidence,
        position_confidence = NEW.position_confidence,
        height_confidence = NEW.height_confidence,
        crown_class_id = NEW.crown_class_id,
        damage_agent_id = NEW.damage_agent_id,
        defoliation_percent = NEW.defoliation_percent,
        discolouration_percent = NEW.discolouration_percent,
        crown_transparency_percent = NEW.crown_transparency_percent,
        status_change_date = NEW.status_change_date,
        field_notes = NEW.field_notes,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE tree_id = OLD.tree_id;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION trees_update(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trees_update() IS 'INSTEAD OF UPDATE trigger function for public.trees view';


--
-- Name: aggregate_readings(integer, timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: sensor; Owner: -
--

CREATE FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer DEFAULT 60) RETURNS TABLE(time_bucket timestamp with time zone, avg_value numeric, min_value numeric, max_value numeric, reading_count bigint)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        date_trunc('hour', sr."Timestamp") +
            ((EXTRACT(MINUTE FROM sr."Timestamp")::INTEGER / interval_minutes) * interval_minutes || ' minutes')::INTERVAL AS time_bucket,
        AVG(sr.Value) AS avg_value,
        MIN(sr.Value) AS min_value,
        MAX(sr.Value) AS max_value,
        COUNT(*) AS reading_count
    FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = sensor_id_param
        AND sr."Timestamp" >= start_time
        AND sr."Timestamp" <= end_time
        AND sr.Quality IN ('good', 'suspect')
    GROUP BY time_bucket
    ORDER BY time_bucket;
END;
$$;


--
-- Name: FUNCTION aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer); Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) IS 'Aggregates sensor readings into time intervals';


--
-- Name: check_sensor_health(integer, integer); Type: FUNCTION; Schema: sensor; Owner: -
--

CREATE FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer DEFAULT 24) RETURNS TABLE(sensor_id integer, ishealthy boolean, lastreading timestamp with time zone, readingscount bigint, goodqualitypercent numeric, issues text)
    LANGUAGE plpgsql STABLE
    AS $$
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
    LEFT JOIN sensor.SensorReadings sr ON s.sensor_id = sr.sensor_id
    WHERE s.sensor_id = sensor_id_param
    ORDER BY sr.Timestamp DESC
    LIMIT 1;

    -- Calculate expected readings
    expected_readings := (hours_back * 3600) / sampling_interval;

    -- Count actual readings
    SELECT COUNT(*), COUNT(*) FILTER (WHERE Quality = 'good')
    INTO actual_readings, good_readings
    FROM sensor.SensorReadings sr
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
$$;


--
-- Name: FUNCTION check_sensor_health(sensor_id_param integer, hours_back integer); Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) IS 'Checks sensor health based on recent reading patterns';


--
-- Name: get_latest_reading(integer); Type: FUNCTION; Schema: sensor; Owner: -
--

CREATE FUNCTION sensor.get_latest_reading(sensor_id_param integer) RETURNS TABLE(sensor_reading_id bigint, reading_timestamp timestamp with time zone, value numeric, quality character varying)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        sr.sensor_reading_id,
        sr."Timestamp",
        sr.Value,
        sr.Quality
    FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = sensor_id_param
    ORDER BY sr."Timestamp" DESC
    LIMIT 1;
END;
$$;


--
-- Name: FUNCTION get_latest_reading(sensor_id_param integer); Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) IS 'Returns the most recent reading for a sensor';


--
-- Name: link_sensors_to_trees_by_pattern(); Type: FUNCTION; Schema: sensor; Owner: -
--

CREATE FUNCTION sensor.link_sensors_to_trees_by_pattern() RETURNS TABLE(sensor_id integer, sensor_name text, tree_id integer, tree_info text, link_created boolean)
    LANGUAGE plpgsql
    AS $_$
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
        JOIN sensor.sensortypes st ON s.sensor_type_id = st.sensor_type_id
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
$_$;


--
-- Name: FUNCTION link_sensors_to_trees_by_pattern(); Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON FUNCTION sensor.link_sensors_to_trees_by_pattern() IS 'DEPRECATED - unreliable (see 32-ecosense-sensor-tree-map.sql). Use scripts/import/link_sensors_to_trees.py, which links via trees.sensor_ref.';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: sensor; Owner: -
--

CREATE FUNCTION sensor.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: audit_update_trigger(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.audit_update_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    column_name TEXT;
    old_value TEXT;
    new_value TEXT;
    audit_id BIGINT;
    record_id INTEGER;
    table_name VARCHAR;
BEGIN
    -- Determine table and record ID
    table_name := TG_TABLE_NAME;
    CASE TG_TABLE_NAME
        WHEN 'pointclouds' THEN
            record_id := NEW.point_cloud_id;
        WHEN 'trees' THEN
            record_id := NEW.tree_id;
        WHEN 'environments' THEN
            record_id := NEW.environment_id;
        WHEN 'stems' THEN
            record_id := NEW.stem_id;
        ELSE
            record_id := NULL;
    END CASE;

    -- Only audit if we have a valid record ID
    IF record_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Audit specific critical fields (add more as needed)
    CASE TG_TABLE_NAME
        WHEN 'trees' THEN
            -- Audit tree measurements
            IF OLD.Height_m IS DISTINCT FROM NEW.Height_m THEN
                PERFORM shared.create_audit_log(
                    'Trees', record_id, 'Height_m',
                    OLD.Height_m::TEXT, NEW.Height_m::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.crown_width_m IS DISTINCT FROM NEW.crown_width_m THEN
                PERFORM shared.create_audit_log(
                    'Trees', record_id, 'crown_width_m',
                    OLD.crown_width_m::TEXT, NEW.crown_width_m::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.health_score IS DISTINCT FROM NEW.health_score THEN
                PERFORM shared.create_audit_log(
                    'Trees', record_id, 'health_score',
                    OLD.health_score::TEXT, NEW.health_score::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.tree_status_id IS DISTINCT FROM NEW.tree_status_id THEN
                PERFORM shared.create_audit_log(
                    'Trees', record_id, 'tree_status_id',
                    OLD.tree_status_id::TEXT, NEW.tree_status_id::TEXT,
                    NULL, 'field_update'
                );
            END IF;

        WHEN 'stems' THEN
            -- Audit stem measurements
            IF OLD.DBH_cm IS DISTINCT FROM NEW.DBH_cm THEN
                PERFORM shared.create_audit_log(
                    'Stems', record_id, 'DBH_cm',
                    OLD.DBH_cm::TEXT, NEW.DBH_cm::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.stem_height_m IS DISTINCT FROM NEW.stem_height_m THEN
                PERFORM shared.create_audit_log(
                    'Stems', record_id, 'stem_height_m',
                    OLD.stem_height_m::TEXT, NEW.stem_height_m::TEXT,
                    NULL, 'field_update'
                );
            END IF;

        WHEN 'environments' THEN
            -- Audit environmental parameters
            IF OLD.avg_temperature_c IS DISTINCT FROM NEW.avg_temperature_c THEN
                PERFORM shared.create_audit_log(
                    'Environments', record_id, 'avg_temperature_c',
                    OLD.avg_temperature_c::TEXT, NEW.avg_temperature_c::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.stress_factor IS DISTINCT FROM NEW.stress_factor THEN
                PERFORM shared.create_audit_log(
                    'Environments', record_id, 'stress_factor',
                    OLD.stress_factor::TEXT, NEW.stress_factor::TEXT,
                    NULL, 'field_update'
                );
            END IF;

        WHEN 'pointclouds' THEN
            -- Audit processing status changes
            IF OLD.processing_status IS DISTINCT FROM NEW.processing_status THEN
                PERFORM shared.create_audit_log(
                    'PointClouds', record_id, 'processing_status',
                    OLD.processing_status::TEXT, NEW.processing_status::TEXT,
                    NULL, 'field_update'
                );
            END IF;
    END CASE;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION audit_update_trigger(); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.audit_update_trigger() IS 'Automatically creates audit log entries for critical field updates';


--
-- Name: create_audit_log(character varying, integer, character varying, text, text, text, character varying); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text DEFAULT NULL::text, change_type_param character varying DEFAULT 'field_update'::character varying) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_audit_id BIGINT;
BEGIN
    INSERT INTO shared.AuditLog (
        field_name,
        old_value,
        new_value,
        change_reason,
        user_id,
        change_type,
        ip_address
    ) VALUES (
        field_name_param,
        old_value_param,
        new_value_param,
        change_reason_param,
        auth.uid()::TEXT,
        change_type_param,
        inet_client_addr()
    )
    RETURNING audit_id INTO v_audit_id;

    -- Create junction table entry based on table name
    CASE table_name_param
        WHEN 'PointClouds' THEN
            INSERT INTO shared.AuditLog_PointClouds (audit_id, point_cloud_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Trees' THEN
            INSERT INTO shared.AuditLog_Trees (audit_id, tree_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Environments' THEN
            INSERT INTO shared.AuditLog_Environments (audit_id, environment_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'Stems' THEN
            INSERT INTO shared.AuditLog_Stems (audit_id, stem_id)
            VALUES (v_audit_id, variant_id_param);
    END CASE;

    RETURN v_audit_id;
END;
$$;


--
-- Name: FUNCTION create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying) IS 'Creates audit log entry with junction table link';


--
-- Name: current_user_id(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.current_user_id() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN auth.uid()::TEXT;
END;
$$;


--
-- Name: FUNCTION current_user_id(); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.current_user_id() IS 'Returns current authenticated user ID';


--
-- Name: get_audit_history(character varying, integer, integer); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer DEFAULT 100) RETURNS TABLE(audit_id bigint, field_name character varying, old_value text, new_value text, change_reason text, user_id character varying, "Timestamp" timestamp with time zone, change_type character varying)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
    IF table_name_param = 'PointClouds' THEN
        RETURN QUERY
            SELECT
                al.audit_id,
                al.field_name,
                al.old_value,
                al.new_value,
                al.change_reason,
                al.user_id,
                al.Timestamp,
                al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_PointClouds alpc ON al.audit_id = alpc.audit_id
            WHERE alpc.point_cloud_id = variant_id_param
            ORDER BY al.Timestamp DESC
            LIMIT limit_param;
    ELSIF table_name_param = 'Trees' THEN
        RETURN QUERY
            SELECT
                al.audit_id,
                al.field_name,
                al.old_value,
                al.new_value,
                al.change_reason,
                al.user_id,
                al.Timestamp,
                al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Trees alt ON al.audit_id = alt.audit_id
            WHERE alt.tree_id = variant_id_param
            ORDER BY al.Timestamp DESC
            LIMIT limit_param;
    ELSIF table_name_param = 'Environments' THEN
        RETURN QUERY
            SELECT
                al.audit_id,
                al.field_name,
                al.old_value,
                al.new_value,
                al.change_reason,
                al.user_id,
                al.Timestamp,
                al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Environments ale ON al.audit_id = ale.audit_id
            WHERE ale.environment_id = variant_id_param
            ORDER BY al.Timestamp DESC
            LIMIT limit_param;
    ELSIF table_name_param = 'Stems' THEN
        RETURN QUERY
            SELECT
                al.audit_id,
                al.field_name,
                al.old_value,
                al.new_value,
                al.change_reason,
                al.user_id,
                al.Timestamp,
                al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Stems als ON al.audit_id = als.audit_id
            WHERE als.stem_id = variant_id_param
            ORDER BY al.Timestamp DESC
            LIMIT limit_param;
    END IF;
    RETURN;
END;
$$;


--
-- Name: FUNCTION get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer) IS 'Retrieves audit history for a specific variant or record';


--
-- Name: is_admin(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.is_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
END;
$$;


--
-- Name: FUNCTION is_admin(); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.is_admin() IS 'RDA tier: Administrator - full user/role management, implies Curator rights';


--
-- Name: is_contributor(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.is_contributor() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'curator', 'contributor'), false);
END;
$$;


--
-- Name: FUNCTION is_contributor(); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.is_contributor() IS 'RDA tier: Contributor - can insert new field-data records, no alter/delete';


--
-- Name: is_curator(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.is_curator() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'curator'), false);
END;
$$;


--
-- Name: FUNCTION is_curator(); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.is_curator() IS 'RDA tier: Curator - can alter/delete field-data records';


--
-- Name: refresh_all_lookups(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.refresh_all_lookups() RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Refresh in dependency order
    RETURN QUERY SELECT * FROM shared.refresh_lookup('soil_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('climate_zones');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('variant_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('scenarios');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('species');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('locations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('sensor_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('tree_status');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('taper_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('straightness_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branching_patterns');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('bark_characteristics');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('datasource_types');
    -- Tree Morphology tables (from tree_anatomy.pdf)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('height_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_architectures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branch_elongation_habits');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_orientations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('shoot_elongation_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_shapes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('geometric_crown_solids');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('axis_structures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_forms');
    -- Tree Condition tables (FIA/NEON/ICP Forests-aligned)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('damage_agents');
END;
$$;


--
-- Name: FUNCTION refresh_all_lookups(); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.refresh_all_lookups() IS 'Reload all lookup tables from CSV files without full database rebuild';


--
-- Name: refresh_lookup(text); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.refresh_lookup(p_table_name text) RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
                climate_zone_name VARCHAR(10)
            ) ON COMMIT DROP;
            TRUNCATE _temp_locations;
            
            EXECUTE format('COPY _temp_locations FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'locations.csv');
            
            INSERT INTO shared.Locations (location_name, Description, center_point, Elevation_m, Slope_deg, Aspect, soil_type_id, climate_zone_id)
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
                (SELECT soil_type_id FROM shared.SoilTypes WHERE soil_type_name = t.soil_type_name),
                (SELECT climate_zone_id FROM shared.ClimateZones WHERE climate_zone_name = t.climate_zone_name)
            FROM _temp_locations t
            ON CONFLICT (location_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                center_point = EXCLUDED.center_point,
                Elevation_m = EXCLUDED.Elevation_m,
                Slope_deg = EXCLUDED.Slope_deg,
                Aspect = EXCLUDED.Aspect,
                soil_type_id = EXCLUDED.soil_type_id,
                climate_zone_id = EXCLUDED.climate_zone_id;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.locations;
            
        WHEN 'sensor_types', 'sensortypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM sensor.sensortypes;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_sensor_types (
                sensor_type_name VARCHAR(100),
                Description TEXT,
                typical_unit VARCHAR(50),
                typical_range_min NUMERIC(12, 4),
                typical_range_max NUMERIC(12, 4)
            ) ON COMMIT DROP;
            TRUNCATE _temp_sensor_types;
            
            EXECUTE format('COPY _temp_sensor_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'sensor_types.csv');
            
            INSERT INTO sensor.SensorTypes (sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max)
            SELECT sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max 
            FROM _temp_sensor_types
            ON CONFLICT (sensor_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_unit = EXCLUDED.typical_unit,
                typical_range_min = EXCLUDED.typical_range_min,
                typical_range_max = EXCLUDED.typical_range_max;
            
            SELECT COUNT(*) INTO v_rows_after FROM sensor.sensortypes;
            p_table_name := 'sensor_types';
            
        WHEN 'tree_status', 'treestatus' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.treestatus;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_tree_status (
                tree_status_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_tree_status;
            
            EXECUTE format('COPY _temp_tree_status FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'tree_status.csv');
            
            INSERT INTO trees.TreeStatus (tree_status_name, Description)
            SELECT tree_status_name, Description FROM _temp_tree_status
            ON CONFLICT (tree_status_name) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM trees.treestatus;
            p_table_name := 'tree_status';
            
        WHEN 'soil_types', 'soiltypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.soiltypes;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_soil_types (
                soil_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_soil_types;
            
            EXECUTE format('COPY _temp_soil_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'soil_types.csv');
            
            INSERT INTO shared.SoilTypes (soil_type_name, Description)
            SELECT soil_type_name, Description FROM _temp_soil_types
            ON CONFLICT (soil_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.soiltypes;
            p_table_name := 'soil_types';
            
        WHEN 'climate_zones', 'climatezones' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.climatezones;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_climate_zones (
                climate_zone_name VARCHAR(10),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_climate_zones;
            
            EXECUTE format('COPY _temp_climate_zones FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'climate_zones.csv');
            
            INSERT INTO shared.ClimateZones (climate_zone_name, Description)
            SELECT climate_zone_name, Description FROM _temp_climate_zones
            ON CONFLICT (climate_zone_name) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.climatezones;
            p_table_name := 'climate_zones';
            
        WHEN 'variant_types', 'varianttypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.varianttypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_variant_types (
                variant_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_variant_types;

            EXECUTE format('COPY _temp_variant_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'variant_types.csv');

            INSERT INTO shared.VariantTypes (variant_type_name, Description)
            SELECT variant_type_name, Description FROM _temp_variant_types
            ON CONFLICT (variant_type_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM shared.varianttypes;
            p_table_name := 'variant_types';

        WHEN 'scenarios' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.scenarios;

            CREATE TEMP TABLE IF NOT EXISTS _temp_scenarios (
                scenario_name VARCHAR(200),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_scenarios;

            EXECUTE format('COPY _temp_scenarios FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'scenarios.csv');

            INSERT INTO shared.Scenarios (scenario_name, Description)
            SELECT scenario_name, Description FROM _temp_scenarios
            ON CONFLICT (scenario_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM shared.scenarios;

        WHEN 'taper_types', 'tapertypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.tapertypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_taper_types (
                taper_type_name VARCHAR(100),
                Description TEXT,
                typical_taper_ratio_min NUMERIC(4, 3),
                typical_taper_ratio_max NUMERIC(4, 3)
            ) ON COMMIT DROP;
            TRUNCATE _temp_taper_types;

            EXECUTE format('COPY _temp_taper_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'taper_types.csv');

            INSERT INTO trees.TaperTypes (taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max)
            SELECT taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max FROM _temp_taper_types
            ON CONFLICT (taper_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_taper_ratio_min = EXCLUDED.typical_taper_ratio_min,
                typical_taper_ratio_max = EXCLUDED.typical_taper_ratio_max;

            SELECT COUNT(*) INTO v_rows_after FROM trees.tapertypes;
            p_table_name := 'taper_types';

        WHEN 'straightness_types', 'straightnesstypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.straightnesstypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_straightness_types (
                straightness_name VARCHAR(100),
                Description TEXT,
                deviation_angle_min NUMERIC(5, 2),
                deviation_angle_max NUMERIC(5, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_straightness_types;

            EXECUTE format('COPY _temp_straightness_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'straightness_types.csv');

            INSERT INTO trees.StraightnessTypes (straightness_name, Description, deviation_angle_min, deviation_angle_max)
            SELECT straightness_name, Description, deviation_angle_min, deviation_angle_max FROM _temp_straightness_types
            ON CONFLICT (straightness_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                deviation_angle_min = EXCLUDED.deviation_angle_min,
                deviation_angle_max = EXCLUDED.deviation_angle_max;

            SELECT COUNT(*) INTO v_rows_after FROM trees.straightnesstypes;
            p_table_name := 'straightness_types';

        WHEN 'branching_patterns', 'branchingpatterns' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branchingpatterns;

            CREATE TEMP TABLE IF NOT EXISTS _temp_branching_patterns (
                branching_pattern_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_branching_patterns;

            EXECUTE format('COPY _temp_branching_patterns FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branching_patterns.csv');

            INSERT INTO trees.BranchingPatterns (branching_pattern_name, Description)
            SELECT branching_pattern_name, Description FROM _temp_branching_patterns
            ON CONFLICT (branching_pattern_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.branchingpatterns;
            p_table_name := 'branching_patterns';

        WHEN 'bark_characteristics', 'barkcharacteristics' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.barkcharacteristics;

            CREATE TEMP TABLE IF NOT EXISTS _temp_bark_characteristics (
                bark_characteristic_name VARCHAR(100),
                Description TEXT,
                typical_species TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_bark_characteristics;

            EXECUTE format('COPY _temp_bark_characteristics FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'bark_characteristics.csv');

            INSERT INTO trees.BarkCharacteristics (bark_characteristic_name, Description, typical_species)
            SELECT bark_characteristic_name, Description, typical_species FROM _temp_bark_characteristics
            ON CONFLICT (bark_characteristic_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_species = EXCLUDED.typical_species;

            SELECT COUNT(*) INTO v_rows_after FROM trees.barkcharacteristics;
            p_table_name := 'bark_characteristics';

        WHEN 'datasource_types', 'datasourcetypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.datasourcetypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_datasource_types (
                data_source_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_datasource_types;

            EXECUTE format('COPY _temp_datasource_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'datasource_types.csv');

            INSERT INTO trees.DataSourceTypes (data_source_type_name, Description)
            SELECT data_source_type_name, Description FROM _temp_datasource_types
            ON CONFLICT (data_source_type_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.datasourcetypes;
            p_table_name := 'datasource_types';

        -- =====================================================================
        -- TREE MORPHOLOGY TABLES (from tree_anatomy.pdf)
        -- =====================================================================

        WHEN 'height_classes', 'phanerophyte_height_classes', 'phanerophyteheightclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.phanerophyteheightclasses;

            CREATE TEMP TABLE IF NOT EXISTS _temp_height_classes (
                height_class_name VARCHAR(50),
                Description TEXT,
                min_height_m NUMERIC(6, 2),
                max_height_m NUMERIC(6, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_height_classes;

            EXECUTE format('COPY _temp_height_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'phanerophyte_height_classes.csv');

            INSERT INTO trees.PhanerophyteHeightClasses (height_class_name, Description, min_height_m, max_height_m)
            SELECT height_class_name, Description, min_height_m, max_height_m FROM _temp_height_classes
            ON CONFLICT (height_class_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                min_height_m = EXCLUDED.min_height_m,
                max_height_m = EXCLUDED.max_height_m;

            SELECT COUNT(*) INTO v_rows_after FROM trees.phanerophyteheightclasses;
            p_table_name := 'height_classes';

        WHEN 'crown_architectures', 'crownarchitectures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownarchitectures;

            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_arch (
                crown_architecture_name VARCHAR(50),
                Description TEXT,
                typical_examples TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_arch;

            EXECUTE format('COPY _temp_crown_arch FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_architectures.csv');

            INSERT INTO trees.CrownArchitectures (crown_architecture_name, Description, typical_examples)
            SELECT crown_architecture_name, Description, typical_examples FROM _temp_crown_arch
            ON CONFLICT (crown_architecture_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_examples = EXCLUDED.typical_examples;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownarchitectures;
            p_table_name := 'crown_architectures';

        WHEN 'branch_elongation_habits', 'branchelongationhabits', 'elongation_habits' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branchelongationhabits;

            CREATE TEMP TABLE IF NOT EXISTS _temp_elongation (
                elongation_habit_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_elongation;

            EXECUTE format('COPY _temp_elongation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branch_elongation_habits.csv');

            INSERT INTO trees.BranchElongationHabits (elongation_habit_name, Description)
            SELECT elongation_habit_name, Description FROM _temp_elongation
            ON CONFLICT (elongation_habit_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.branchelongationhabits;
            p_table_name := 'branch_elongation_habits';

        WHEN 'growth_orientations', 'growthorientations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growthorientations;

            CREATE TEMP TABLE IF NOT EXISTS _temp_orientation (
                growth_orientation_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_orientation;

            EXECUTE format('COPY _temp_orientation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_orientations.csv');

            INSERT INTO trees.GrowthOrientations (growth_orientation_name, Description)
            SELECT growth_orientation_name, Description FROM _temp_orientation
            ON CONFLICT (growth_orientation_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.growthorientations;
            p_table_name := 'growth_orientations';

        WHEN 'shoot_elongation_types', 'shootelongationtypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.shootelongationtypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_shoot (
                shoot_elongation_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shoot;

            EXECUTE format('COPY _temp_shoot FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'shoot_elongation_types.csv');

            INSERT INTO trees.ShootElongationTypes (shoot_elongation_type_name, Description)
            SELECT shoot_elongation_type_name, Description FROM _temp_shoot
            ON CONFLICT (shoot_elongation_type_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.shootelongationtypes;
            p_table_name := 'shoot_elongation_types';

        WHEN 'crown_shapes', 'crownshapes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownshapes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_shapes (
                crown_shape_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shapes;

            EXECUTE format('COPY _temp_shapes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_shapes.csv');

            INSERT INTO trees.CrownShapes (crown_shape_name, Description)
            SELECT crown_shape_name, Description FROM _temp_shapes
            ON CONFLICT (crown_shape_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownshapes;
            p_table_name := 'crown_shapes';

        WHEN 'geometric_crown_solids', 'geometriccrownsolids', 'geometric_solids' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.geometriccrownsolids;

            CREATE TEMP TABLE IF NOT EXISTS _temp_solids (
                geometric_solid_name VARCHAR(50),
                Description TEXT,
                relative_lateral_area NUMERIC(4, 2),
                relative_volume NUMERIC(4, 2),
                relative_drag NUMERIC(4, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_solids;

            EXECUTE format('COPY _temp_solids FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'geometric_crown_solids.csv');

            INSERT INTO trees.GeometricCrownSolids (geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag)
            SELECT geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag FROM _temp_solids
            ON CONFLICT (geometric_solid_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                relative_lateral_area = EXCLUDED.relative_lateral_area,
                relative_volume = EXCLUDED.relative_volume,
                relative_drag = EXCLUDED.relative_drag;

            SELECT COUNT(*) INTO v_rows_after FROM trees.geometriccrownsolids;
            p_table_name := 'geometric_crown_solids';

        WHEN 'axis_structures', 'axisstructures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.axisstructures;

            CREATE TEMP TABLE IF NOT EXISTS _temp_axis (
                axis_structure_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_axis;

            EXECUTE format('COPY _temp_axis FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'axis_structures.csv');

            INSERT INTO trees.AxisStructures (axis_structure_name, Description)
            SELECT axis_structure_name, Description FROM _temp_axis
            ON CONFLICT (axis_structure_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.axisstructures;
            p_table_name := 'axis_structures';

        WHEN 'growth_forms', 'growthforms' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growthforms;

            CREATE TEMP TABLE IF NOT EXISTS _temp_forms (
                growth_form_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_forms;

            EXECUTE format('COPY _temp_forms FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_forms.csv');

            INSERT INTO trees.GrowthForms (growth_form_name, Description)
            SELECT growth_form_name, Description FROM _temp_forms
            ON CONFLICT (growth_form_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.growthforms;
            p_table_name := 'growth_forms';

        -- =====================================================================
        -- TREE CONDITION TABLES (FIA/NEON/ICP Forests-aligned)
        -- =====================================================================

        WHEN 'crown_classes', 'crownclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownclasses;

            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_classes (
                crown_class_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_classes;

            EXECUTE format('COPY _temp_crown_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_classes.csv');

            INSERT INTO trees.CrownClasses (crown_class_name, Description)
            SELECT crown_class_name, Description FROM _temp_crown_classes
            ON CONFLICT (crown_class_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownclasses;
            p_table_name := 'crown_classes';

        WHEN 'damage_agents', 'damageagents' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.damageagents;

            CREATE TEMP TABLE IF NOT EXISTS _temp_damage_agents (
                damage_agent_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_damage_agents;

            EXECUTE format('COPY _temp_damage_agents FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'damage_agents.csv');

            INSERT INTO trees.DamageAgents (damage_agent_name, Description)
            SELECT damage_agent_name, Description FROM _temp_damage_agents
            ON CONFLICT (damage_agent_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.damageagents;
            p_table_name := 'damage_agents';

        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0, 'ERROR: Unknown table. Use: species, locations, sensor_types, tree_status, soil_types, climate_zones, variant_types, scenarios, taper_types, straightness_types, branching_patterns, bark_characteristics, datasource_types, height_classes, crown_architectures, branch_elongation_habits, growth_orientations, shoot_elongation_types, crown_shapes, geometric_crown_solids, axis_structures, growth_forms, crown_classes, damage_agents';
            RETURN;
    END CASE;
    
    RETURN QUERY SELECT p_table_name, v_rows_before, v_rows_after, 'OK';
END;
$$;


--
-- Name: FUNCTION refresh_lookup(p_table_name text); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.refresh_lookup(p_table_name text) IS 'Reload a specific lookup table from its CSV file without full database rebuild';


--
-- Name: revert_field_change(bigint, text); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.revert_field_change(audit_id_param bigint, change_reason_param text DEFAULT 'Reverted change'::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    audit_record RECORD;
    table_name VARCHAR;
    variant_id INTEGER;
    field_name VARCHAR;
    old_value TEXT;
    new_audit_id BIGINT;
BEGIN
    -- Get audit record
    SELECT * INTO audit_record
    FROM shared.AuditLog
    WHERE audit_id = audit_id_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Audit record % not found', audit_id_param;
    END IF;

    -- Determine table and variant from junction tables
    IF EXISTS (SELECT 1 FROM shared.AuditLog_PointClouds WHERE audit_id = audit_id_param) THEN
        table_name := 'PointClouds';
        SELECT point_cloud_id INTO variant_id FROM shared.AuditLog_PointClouds WHERE audit_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.AuditLog_Trees WHERE audit_id = audit_id_param) THEN
        table_name := 'Trees';
        SELECT tree_id INTO variant_id FROM shared.AuditLog_Trees WHERE audit_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.AuditLog_Environments WHERE audit_id = audit_id_param) THEN
        table_name := 'Environments';
        SELECT environment_id INTO variant_id FROM shared.AuditLog_Environments WHERE audit_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.AuditLog_Stems WHERE audit_id = audit_id_param) THEN
        table_name := 'Stems';
        SELECT stem_id INTO variant_id FROM shared.AuditLog_Stems WHERE audit_id = audit_id_param;
    ELSE
        RAISE EXCEPTION 'Could not determine table for audit record %', audit_id_param;
    END IF;

    field_name := audit_record.field_name;
    old_value := audit_record.old_value;

    -- Create revert audit log
    SELECT shared.create_audit_log(
        table_name,
        variant_id,
        field_name,
        audit_record.new_value,  -- Current value becomes old value
        old_value,              -- Old value becomes new value
        change_reason_param,
        'revert'
    ) INTO new_audit_id;

    -- Execute the revert (this would need dynamic SQL for actual field update)
    -- For now, we just log the revert - actual update should be done via API

    RETURN TRUE;
END;
$$;


--
-- Name: FUNCTION revert_field_change(audit_id_param bigint, change_reason_param text); Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON FUNCTION shared.revert_field_change(audit_id_param bigint, change_reason_param text) IS 'Creates audit log entry for reverting a field change';


--
-- Name: set_created_by(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.set_created_by() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Try to set created_by if it exists and is NULL
    -- Use exception handling to gracefully skip if column doesn't exist in NEW record
    BEGIN
        IF (to_jsonb(NEW)->>'created_by') IS NULL THEN
            NEW.created_by := COALESCE(auth.uid()::TEXT, 'system');
        END IF;
    EXCEPTION
        WHEN undefined_column THEN
            -- Column doesn't exist in this table, skip silently
            NULL;
    END;
    RETURN NEW;
END;
$$;


--
-- Name: set_updated_by(); Type: FUNCTION; Schema: shared; Owner: -
--

CREATE FUNCTION shared.set_updated_by() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    NEW.updated_by := auth.uid()::TEXT;
    RETURN NEW;
END;
$$;


--
-- Name: assign_height_class(); Type: FUNCTION; Schema: trees; Owner: -
--

CREATE FUNCTION trees.assign_height_class() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.Height_m IS NOT NULL AND NEW.height_class_id IS NULL THEN
        SELECT phanerophyte_height_class_id INTO NEW.height_class_id
        FROM trees.PhanerophyteHeightClasses
        WHERE (min_height_m IS NULL OR NEW.Height_m >= min_height_m)
          AND (max_height_m IS NULL OR NEW.Height_m < max_height_m)
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION assign_height_class(); Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON FUNCTION trees.assign_height_class() IS 'Auto-assigns phanerophyte height class based on tree height';


--
-- Name: calculate_basal_area(numeric); Type: FUNCTION; Schema: trees; Owner: -
--

CREATE FUNCTION trees.calculate_basal_area(dbh_cm numeric) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    -- Basal area = π * (DBH/2)^2, convert cm to m
    RETURN PI() * POWER(dbh_cm / 200.0, 2);
END;
$$;


--
-- Name: FUNCTION calculate_basal_area(dbh_cm numeric); Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) IS 'Calculates basal area in m² from DBH in cm';


--
-- Name: calculate_crown_volume(numeric, numeric); Type: FUNCTION; Schema: trees; Owner: -
--

CREATE FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    -- Volume of ellipsoid: (4/3) * π * a * b * c
    -- Assuming circular crown: a = b = crown_width/2, c = crown_height/2
    RETURN (4.0/3.0) * PI() * POWER(crown_width_m / 2.0, 2) * (crown_height_m / 2.0);
END;
$$;


--
-- Name: FUNCTION calculate_crown_volume(crown_width_m numeric, crown_height_m numeric); Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) IS 'Calculates crown volume in m³ assuming ellipsoid shape';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: trees; Owner: -
--

CREATE FUNCTION trees.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: environments; Type: TABLE; Schema: environments; Owner: -
--

CREATE TABLE environments.environments (
    environment_id integer NOT NULL,
    parent_environment_id integer,
    location_id integer NOT NULL,
    scenario_id integer,
    variant_type_id integer NOT NULL,
    process_id integer,
    variant_name character varying(300) NOT NULL,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    avg_temperature_c numeric(6,2),
    avg_humidity_percent numeric(5,2),
    total_precipitation_mm numeric(8,2),
    avg_global_radiation_w_m2 numeric(8,2),
    avg_co2_ppm numeric(7,2),
    avg_wind_speed_ms numeric(6,2),
    dominant_wind_direction_deg numeric(5,2),
    avg_soil_moisture_percent numeric(5,2),
    avg_soil_temperature_c numeric(6,2),
    soil_ph numeric(4,2),
    nutrient_nitrogen_mg_kg numeric(8,2),
    nutrient_phosphorus_mg_kg numeric(8,2),
    nutrient_potassium_mg_kg numeric(8,2),
    stress_factor numeric(3,2),
    description text,
    research_notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT chk_date_range CHECK (((end_date IS NULL) OR (start_date IS NULL) OR (end_date >= start_date))),
    CONSTRAINT environments_avg_co2_ppm_check CHECK (((avg_co2_ppm >= (200)::numeric) AND (avg_co2_ppm <= (2000)::numeric))),
    CONSTRAINT environments_avg_global_radiation_w_m2_check CHECK ((avg_global_radiation_w_m2 >= (0)::numeric)),
    CONSTRAINT environments_avg_humidity_percent_check CHECK (((avg_humidity_percent >= (0)::numeric) AND (avg_humidity_percent <= (100)::numeric))),
    CONSTRAINT environments_avg_soil_moisture_percent_check CHECK (((avg_soil_moisture_percent >= (0)::numeric) AND (avg_soil_moisture_percent <= (100)::numeric))),
    CONSTRAINT environments_avg_soil_temperature_c_check CHECK (((avg_soil_temperature_c >= ('-20'::integer)::numeric) AND (avg_soil_temperature_c <= (40)::numeric))),
    CONSTRAINT environments_avg_temperature_c_check CHECK (((avg_temperature_c >= ('-50'::integer)::numeric) AND (avg_temperature_c <= (60)::numeric))),
    CONSTRAINT environments_avg_wind_speed_ms_check CHECK (((avg_wind_speed_ms >= (0)::numeric) AND (avg_wind_speed_ms <= (100)::numeric))),
    CONSTRAINT environments_dominant_wind_direction_deg_check CHECK (((dominant_wind_direction_deg >= (0)::numeric) AND (dominant_wind_direction_deg < (360)::numeric))),
    CONSTRAINT environments_nutrient_nitrogen_mg_kg_check CHECK ((nutrient_nitrogen_mg_kg >= (0)::numeric)),
    CONSTRAINT environments_nutrient_phosphorus_mg_kg_check CHECK ((nutrient_phosphorus_mg_kg >= (0)::numeric)),
    CONSTRAINT environments_nutrient_potassium_mg_kg_check CHECK ((nutrient_potassium_mg_kg >= (0)::numeric)),
    CONSTRAINT environments_soil_ph_check CHECK (((soil_ph >= (3)::numeric) AND (soil_ph <= (10)::numeric))),
    CONSTRAINT environments_stress_factor_check CHECK (((stress_factor >= (0)::numeric) AND (stress_factor <= (1)::numeric))),
    CONSTRAINT environments_total_precipitation_mm_check CHECK ((total_precipitation_mm >= (0)::numeric))
);


--
-- Name: TABLE environments; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON TABLE environments.environments IS 'Environmental condition variants derived from sensors, models, or user input';


--
-- Name: COLUMN environments.environment_id; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON COLUMN environments.environments.environment_id IS 'Unique identifier for this environment record';


--
-- Name: COLUMN environments.parent_environment_id; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON COLUMN environments.environments.parent_environment_id IS 'Parent environment for tracking environmental modifications';


--
-- Name: COLUMN environments.start_date; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON COLUMN environments.environments.start_date IS 'Start of environmental measurement period';


--
-- Name: COLUMN environments.end_date; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON COLUMN environments.environments.end_date IS 'End of environmental measurement period (NULL for ongoing)';


--
-- Name: COLUMN environments.avg_global_radiation_w_m2; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON COLUMN environments.environments.avg_global_radiation_w_m2 IS 'Average global radiation in W/m²';


--
-- Name: COLUMN environments.stress_factor; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON COLUMN environments.environments.stress_factor IS 'Environmental stress index (0=optimal, 1=severe stress)';


--
-- Name: locations; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.locations (
    location_id integer NOT NULL,
    location_name character varying(200) NOT NULL,
    boundary extensions.geometry(Polygon,4326),
    center_point extensions.geometry(Point,4326),
    description text,
    elevation_m numeric(8,2),
    slope_deg numeric(5,2),
    aspect character varying(3),
    soil_type_id integer,
    climate_zone_id integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT locations_aspect_check CHECK (((aspect)::text = ANY ((ARRAY['N'::character varying, 'NE'::character varying, 'E'::character varying, 'SE'::character varying, 'S'::character varying, 'SW'::character varying, 'W'::character varying, 'NW'::character varying])::text[]))),
    CONSTRAINT locations_slope_deg_check CHECK (((slope_deg >= (0)::numeric) AND (slope_deg <= (90)::numeric)))
);


--
-- Name: TABLE locations; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.locations IS 'Forest plot locations with spatial boundaries and environmental context';


--
-- Name: COLUMN locations.boundary; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.locations.boundary IS 'PostGIS polygon defining plot boundaries in WGS84';


--
-- Name: COLUMN locations.center_point; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.locations.center_point IS 'PostGIS point for plot center in WGS84';


--
-- Name: scenarios; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.scenarios (
    scenario_id integer NOT NULL,
    scenario_name character varying(200) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    location_id integer NOT NULL
);


--
-- Name: TABLE scenarios; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.scenarios IS 'Management regimes, one set per location (Location -> Scenario -> Variant). Each scenario owns its baseline initial conditions; its variants are the successive states (growth cycles, interventions) developing from that baseline.';


--
-- Name: COLUMN scenarios.location_id; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.scenarios.location_id IS 'The site this management regime belongs to — top of the Location -> Scenario -> Variant hierarchy.';


--
-- Name: varianttypes; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.varianttypes (
    variant_type_id integer NOT NULL,
    variant_type_name character varying(100) NOT NULL,
    description text,
    CONSTRAINT chk_variant_type_name CHECK (((variant_type_name)::text = ANY ((ARRAY['original'::character varying, 'processed'::character varying, 'manual'::character varying, 'simulated_growth'::character varying, 'user_input'::character varying, 'sensor_derived'::character varying, 'model_output'::character varying, 'repeat_measurement'::character varying])::text[])))
);


--
-- Name: TABLE varianttypes; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.varianttypes IS 'Types of data variants (original, processed, simulated, etc.)';


--
-- Name: active_environments; Type: VIEW; Schema: environments; Owner: -
--

CREATE VIEW environments.active_environments AS
 SELECT e.environment_id,
    e.parent_environment_id,
    e.location_id,
    e.scenario_id,
    e.variant_type_id,
    e.process_id,
    e.variant_name,
    e.start_date,
    e.end_date,
    e.avg_temperature_c,
    e.avg_humidity_percent,
    e.total_precipitation_mm,
    e.avg_global_radiation_w_m2,
    e.avg_co2_ppm,
    e.avg_wind_speed_ms,
    e.dominant_wind_direction_deg,
    e.avg_soil_moisture_percent,
    e.avg_soil_temperature_c,
    e.soil_ph,
    e.nutrient_nitrogen_mg_kg,
    e.nutrient_phosphorus_mg_kg,
    e.nutrient_potassium_mg_kg,
    e.stress_factor,
    e.description,
    e.research_notes,
    e.created_at,
    e.updated_at,
    e.created_by,
    e.updated_by,
    environments.calculate_duration_days(e.start_date, e.end_date) AS duration_days,
    environments.is_active(e.start_date, e.end_date) AS is_active,
    l.location_name,
    s.scenario_name,
    vt.variant_type_name
   FROM (((environments.environments e
     LEFT JOIN shared.locations l ON ((e.location_id = l.location_id)))
     LEFT JOIN shared.scenarios s ON ((e.scenario_id = s.scenario_id)))
     LEFT JOIN shared.varianttypes vt ON ((e.variant_type_id = vt.variant_type_id)))
  WHERE (environments.is_active(e.start_date, e.end_date) = true);


--
-- Name: VIEW active_environments; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON VIEW environments.active_environments IS 'Currently active environment variants with location and scenario context';


--
-- Name: environments_environment_id_seq; Type: SEQUENCE; Schema: environments; Owner: -
--

CREATE SEQUENCE environments.environments_environment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: environments_environment_id_seq; Type: SEQUENCE OWNED BY; Schema: environments; Owner: -
--

ALTER SEQUENCE environments.environments_environment_id_seq OWNED BY environments.environments.environment_id;


--
-- Name: location_environment_summary; Type: VIEW; Schema: environments; Owner: -
--

CREATE VIEW environments.location_environment_summary AS
 SELECT l.location_id,
    l.location_name,
    count(e.environment_id) AS environment_count,
    avg(e.avg_temperature_c) AS avg_temperature,
    avg(e.avg_humidity_percent) AS avg_humidity,
    avg(e.avg_co2_ppm) AS avg_co2,
    avg(e.stress_factor) AS avg_stress_factor,
    min(e.start_date) AS earliest_measurement,
    max(e.end_date) AS latest_measurement
   FROM (shared.locations l
     LEFT JOIN environments.environments e ON ((l.location_id = e.location_id)))
  GROUP BY l.location_id, l.location_name;


--
-- Name: VIEW location_environment_summary; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON VIEW environments.location_environment_summary IS 'Summary statistics of environmental conditions by location';


--
-- Name: images; Type: TABLE; Schema: imagery; Owner: -
--

CREATE TABLE imagery.images (
    image_id integer NOT NULL,
    location_id integer NOT NULL,
    plot_id integer,
    campaign_id integer,
    capture_date timestamp with time zone,
    file_path text NOT NULL,
    file_format character varying(20),
    resolution_px character varying(50),
    camera_model character varying(200),
    "position" extensions.geometry(Point,4326),
    altitude_m numeric(8,2),
    heading_deg numeric(5,2),
    pitch_deg numeric(5,2),
    roll_deg numeric(5,2),
    ground_sample_distance_cm numeric(8,4),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT images_file_format_check CHECK (((file_format)::text = ANY ((ARRAY['jpg'::character varying, 'png'::character varying, 'tiff'::character varying, 'raw'::character varying, 'geotiff'::character varying])::text[]))),
    CONSTRAINT images_ground_sample_distance_cm_check CHECK ((ground_sample_distance_cm > (0)::numeric)),
    CONSTRAINT images_heading_deg_check CHECK (((heading_deg >= (0)::numeric) AND (heading_deg < (360)::numeric))),
    CONSTRAINT images_pitch_deg_check CHECK (((pitch_deg >= ('-90'::integer)::numeric) AND (pitch_deg <= (90)::numeric))),
    CONSTRAINT images_roll_deg_check CHECK (((roll_deg >= ('-180'::integer)::numeric) AND (roll_deg <= (180)::numeric)))
);


--
-- Name: TABLE images; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON TABLE imagery.images IS 'Aerial and ground-based imagery with spatial metadata and camera parameters';


--
-- Name: COLUMN images.file_path; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.file_path IS 'Path or URI to image file';


--
-- Name: COLUMN images.file_format; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.file_format IS 'Image file format (jpg, png, tiff, raw, geotiff)';


--
-- Name: COLUMN images.resolution_px; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.resolution_px IS 'Image resolution in pixels (e.g., 4000x3000)';


--
-- Name: COLUMN images."position"; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images."position" IS 'Camera position in WGS84 (EPSG:4326)';


--
-- Name: COLUMN images.altitude_m; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.altitude_m IS 'Camera altitude above ground in meters';


--
-- Name: COLUMN images.heading_deg; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.heading_deg IS 'Camera heading in degrees (0=North, clockwise)';


--
-- Name: COLUMN images.pitch_deg; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.pitch_deg IS 'Camera pitch angle (-90 to 90 degrees)';


--
-- Name: COLUMN images.roll_deg; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.roll_deg IS 'Camera roll angle (-180 to 180 degrees)';


--
-- Name: COLUMN images.ground_sample_distance_cm; Type: COMMENT; Schema: imagery; Owner: -
--

COMMENT ON COLUMN imagery.images.ground_sample_distance_cm IS 'Ground sample distance in centimeters per pixel';


--
-- Name: images_image_id_seq; Type: SEQUENCE; Schema: imagery; Owner: -
--

CREATE SEQUENCE imagery.images_image_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: images_image_id_seq; Type: SEQUENCE OWNED BY; Schema: imagery; Owner: -
--

ALTER SEQUENCE imagery.images_image_id_seq OWNED BY imagery.images.image_id;


--
-- Name: pointclouds; Type: TABLE; Schema: pointclouds; Owner: -
--

CREATE TABLE pointclouds.pointclouds (
    point_cloud_id integer NOT NULL,
    parent_point_cloud_id integer,
    location_id integer NOT NULL,
    scenario_id integer,
    variant_type_id integer NOT NULL,
    process_id integer,
    campaign_id integer,
    scanner_id integer,
    variant_name character varying(300) NOT NULL,
    scan_date timestamp with time zone,
    sensor_model character varying(200),
    source_crs integer,
    platform_type character varying(50),
    scan_bounds extensions.geometry(Polygon,4326),
    file_path text NOT NULL,
    flight_altitude_m numeric(8,2),
    flight_speed_ms numeric(6,2),
    scan_angle_deg numeric(5,2),
    overlap_percent numeric(5,2),
    point_count bigint,
    point_density_per_m2 numeric(10,2),
    file_size_mb numeric(12,2),
    processing_status character varying(50),
    processing_progress numeric(5,2),
    error_message text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT chk_s3_filepath CHECK ((file_path ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$'::text)),
    CONSTRAINT pointclouds_file_size_mb_check CHECK ((file_size_mb >= (0)::numeric)),
    CONSTRAINT pointclouds_flight_altitude_m_check CHECK ((flight_altitude_m > (0)::numeric)),
    CONSTRAINT pointclouds_flight_speed_ms_check CHECK ((flight_speed_ms >= (0)::numeric)),
    CONSTRAINT pointclouds_overlap_percent_check CHECK (((overlap_percent >= (0)::numeric) AND (overlap_percent <= (100)::numeric))),
    CONSTRAINT pointclouds_platform_type_check CHECK (((platform_type)::text = ANY ((ARRAY['terrestrial'::character varying, 'aerial'::character varying, 'mobile'::character varying, 'UAV'::character varying])::text[]))),
    CONSTRAINT pointclouds_point_count_check CHECK ((point_count >= 0)),
    CONSTRAINT pointclouds_point_density_per_m2_check CHECK ((point_density_per_m2 >= (0)::numeric)),
    CONSTRAINT pointclouds_processing_progress_check CHECK (((processing_progress >= (0)::numeric) AND (processing_progress <= (100)::numeric))),
    CONSTRAINT pointclouds_processing_status_check CHECK (((processing_status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT pointclouds_scan_angle_deg_check CHECK (((scan_angle_deg >= (0)::numeric) AND (scan_angle_deg <= (360)::numeric)))
);


--
-- Name: TABLE pointclouds; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON TABLE pointclouds.pointclouds IS 'LiDAR point cloud variants - original scans and processed results';


--
-- Name: COLUMN pointclouds.point_cloud_id; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.point_cloud_id IS 'Unique identifier for this point cloud record';


--
-- Name: COLUMN pointclouds.parent_point_cloud_id; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.parent_point_cloud_id IS 'Parent point cloud for processing lineage tracking';


--
-- Name: COLUMN pointclouds.campaign_id; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.campaign_id IS 'Data collection campaign this scan belongs to';


--
-- Name: COLUMN pointclouds.scanner_id; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.scanner_id IS 'Physical scanner hardware used for this scan';


--
-- Name: COLUMN pointclouds.source_crs; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.source_crs IS 'EPSG code of original coordinate reference system';


--
-- Name: COLUMN pointclouds.platform_type; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.platform_type IS 'Scanning platform: terrestrial, aerial, mobile, UAV';


--
-- Name: COLUMN pointclouds.scan_bounds; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.scan_bounds IS 'PostGIS polygon defining point cloud coverage area in WGS84';


--
-- Name: COLUMN pointclouds.file_path; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.file_path IS 'S3 URI to point cloud file (e.g., s3://bucket-name/path/file.las)';


--
-- Name: COLUMN pointclouds.flight_altitude_m; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.flight_altitude_m IS 'Flight altitude above ground in meters (for aerial/UAV)';


--
-- Name: COLUMN pointclouds.flight_speed_ms; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.flight_speed_ms IS 'Platform speed during scanning in m/s';


--
-- Name: COLUMN pointclouds.scan_angle_deg; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.scan_angle_deg IS 'Scanner field of view angle in degrees';


--
-- Name: COLUMN pointclouds.overlap_percent; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.overlap_percent IS 'Swath overlap percentage (for aerial scans)';


--
-- Name: COLUMN pointclouds.point_density_per_m2; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.point_density_per_m2 IS 'Average point density in points per square meter';


--
-- Name: COLUMN pointclouds.processing_status; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.processing_status IS 'NULL for original scans, status for processed variants';


--
-- Name: COLUMN pointclouds.processing_progress; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.pointclouds.processing_progress IS 'Processing completion percentage (0-100)';


--
-- Name: pointclouds_point_cloud_id_seq; Type: SEQUENCE; Schema: pointclouds; Owner: -
--

CREATE SEQUENCE pointclouds.pointclouds_point_cloud_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pointclouds_point_cloud_id_seq; Type: SEQUENCE OWNED BY; Schema: pointclouds; Owner: -
--

ALTER SEQUENCE pointclouds.pointclouds_point_cloud_id_seq OWNED BY pointclouds.pointclouds.point_cloud_id;


--
-- Name: processing_lineage; Type: VIEW; Schema: pointclouds; Owner: -
--

CREATE VIEW pointclouds.processing_lineage AS
 WITH RECURSIVE lineage AS (
         SELECT pointclouds.point_cloud_id,
            pointclouds.parent_point_cloud_id,
            pointclouds.variant_name,
            pointclouds.process_id,
            pointclouds.processing_status,
            1 AS depth,
            ARRAY[pointclouds.point_cloud_id] AS lineage_path
           FROM pointclouds.pointclouds
          WHERE (pointclouds.parent_point_cloud_id IS NULL)
        UNION ALL
         SELECT pc.point_cloud_id,
            pc.parent_point_cloud_id,
            pc.variant_name,
            pc.process_id,
            pc.processing_status,
            (l.depth + 1),
            (l.lineage_path || pc.point_cloud_id)
           FROM (pointclouds.pointclouds pc
             JOIN lineage l ON ((pc.parent_point_cloud_id = l.point_cloud_id)))
        )
 SELECT lineage.point_cloud_id,
    lineage.parent_point_cloud_id,
    lineage.variant_name,
    lineage.process_id,
    lineage.processing_status,
    lineage.depth,
    lineage.lineage_path
   FROM lineage;


--
-- Name: VIEW processing_lineage; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON VIEW pointclouds.processing_lineage IS 'Recursive view showing point cloud processing lineage and depth';


--
-- Name: scanners; Type: TABLE; Schema: pointclouds; Owner: -
--

CREATE TABLE pointclouds.scanners (
    scanner_id integer NOT NULL,
    scanner_type_id integer NOT NULL,
    serial_number character varying(100),
    acquisition_date date,
    calibration_date date,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);


--
-- Name: TABLE scanners; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON TABLE pointclouds.scanners IS 'Individual LiDAR scanner hardware instances';


--
-- Name: COLUMN scanners.serial_number; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.scanners.serial_number IS 'Unique hardware serial number';


--
-- Name: COLUMN scanners.acquisition_date; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.scanners.acquisition_date IS 'Date scanner was acquired';


--
-- Name: COLUMN scanners.calibration_date; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.scanners.calibration_date IS 'Last calibration date';


--
-- Name: scanners_scanner_id_seq; Type: SEQUENCE; Schema: pointclouds; Owner: -
--

CREATE SEQUENCE pointclouds.scanners_scanner_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scanners_scanner_id_seq; Type: SEQUENCE OWNED BY; Schema: pointclouds; Owner: -
--

ALTER SEQUENCE pointclouds.scanners_scanner_id_seq OWNED BY pointclouds.scanners.scanner_id;


--
-- Name: scannertypes; Type: TABLE; Schema: pointclouds; Owner: -
--

CREATE TABLE pointclouds.scannertypes (
    scanner_type_id integer NOT NULL,
    scanner_type_name character varying(100) NOT NULL,
    manufacturer character varying(200),
    description text
);


--
-- Name: TABLE scannertypes; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON TABLE pointclouds.scannertypes IS 'LiDAR scanner type classifications and manufacturers';


--
-- Name: COLUMN scannertypes.scanner_type_name; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON COLUMN pointclouds.scannertypes.scanner_type_name IS 'Scanner type name (e.g., Terrestrial_TLS, Aerial_ALS, Mobile_MLS, UAV_ULS)';


--
-- Name: scannertypes_scanner_type_id_seq; Type: SEQUENCE; Schema: pointclouds; Owner: -
--

CREATE SEQUENCE pointclouds.scannertypes_scanner_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scannertypes_scanner_type_id_seq; Type: SEQUENCE OWNED BY; Schema: pointclouds; Owner: -
--

ALTER SEQUENCE pointclouds.scannertypes_scanner_type_id_seq OWNED BY pointclouds.scannertypes.scanner_type_id;


--
-- Name: axisstructures; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.axisstructures (
    axis_structure_id integer NOT NULL,
    axis_structure_name character varying(50) NOT NULL,
    description text
);


--
-- Name: TABLE axisstructures; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.axisstructures IS 'Main axis configuration (single leader vs polycormic)';


--
-- Name: axisstructures; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.axisstructures AS
 SELECT axisstructures.axis_structure_id,
    axisstructures.axis_structure_name,
    axisstructures.description
   FROM trees.axisstructures;


--
-- Name: VIEW axisstructures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.axisstructures IS 'Public API view for axis structures lookup table';


--
-- Name: branchelongationhabits; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.branchelongationhabits (
    branch_elongation_habit_id integer NOT NULL,
    elongation_habit_name character varying(50) NOT NULL,
    description text
);


--
-- Name: TABLE branchelongationhabits; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.branchelongationhabits IS 'Branch elongation patterns determining crown shape (acrotony, mesotony, basitony)';


--
-- Name: branchelongationhabits; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.branchelongationhabits AS
 SELECT branchelongationhabits.branch_elongation_habit_id,
    branchelongationhabits.elongation_habit_name,
    branchelongationhabits.description
   FROM trees.branchelongationhabits;


--
-- Name: VIEW branchelongationhabits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.branchelongationhabits IS 'Public API view for branch elongation habits lookup table';


--
-- Name: campaigns; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.campaigns (
    campaign_id integer NOT NULL,
    campaign_name character varying(200) NOT NULL,
    campaign_type character varying(50) NOT NULL,
    location_id integer,
    start_date date NOT NULL,
    end_date date,
    description text,
    methodology text,
    equipment text,
    personnel text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT campaigns_campaign_type_check CHECK (((campaign_type)::text = ANY ((ARRAY['lidar_flight'::character varying, 'field_inventory'::character varying, 'sensor_deployment'::character varying, 'drone_survey'::character varying, 'manual_update'::character varying])::text[]))),
    CONSTRAINT chk_campaign_dates CHECK (((end_date IS NULL) OR (end_date >= start_date)))
);


--
-- Name: TABLE campaigns; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.campaigns IS 'Data collection campaigns (LiDAR flights, field inventories, sensor deployments)';


--
-- Name: COLUMN campaigns.campaign_type; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.campaigns.campaign_type IS 'Type of data collection campaign';


--
-- Name: COLUMN campaigns.methodology; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.campaigns.methodology IS 'Description of data collection methodology used';


--
-- Name: COLUMN campaigns.equipment; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.campaigns.equipment IS 'Equipment used (e.g., scanner model, measurement tools)';


--
-- Name: campaigns; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.campaigns WITH (security_invoker='on') AS
 SELECT campaigns.campaign_id,
    campaigns.campaign_name,
    campaigns.campaign_type,
    campaigns.location_id,
    campaigns.start_date,
    campaigns.end_date,
    campaigns.description,
    campaigns.methodology,
    campaigns.equipment,
    campaigns.personnel,
    campaigns.created_at,
    campaigns.updated_at,
    campaigns.created_by,
    campaigns.updated_by
   FROM shared.campaigns;


--
-- Name: VIEW campaigns; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.campaigns IS 'Public API view for data collection campaigns';


--
-- Name: crownarchitectures; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.crownarchitectures (
    crown_architecture_id integer NOT NULL,
    crown_architecture_name character varying(50) NOT NULL,
    description text,
    typical_examples text
);


--
-- Name: TABLE crownarchitectures; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.crownarchitectures IS 'Crown architecture classification (excurrent, decurrent, etc.)';


--
-- Name: COLUMN crownarchitectures.typical_examples; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.crownarchitectures.typical_examples IS 'Example tree types with this architecture';


--
-- Name: crownarchitectures; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.crownarchitectures AS
 SELECT crownarchitectures.crown_architecture_id,
    crownarchitectures.crown_architecture_name,
    crownarchitectures.description,
    crownarchitectures.typical_examples
   FROM trees.crownarchitectures;


--
-- Name: VIEW crownarchitectures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.crownarchitectures IS 'Public API view for crown architectures lookup table';


--
-- Name: crownclasses; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.crownclasses (
    crown_class_id integer NOT NULL,
    crown_class_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_crown_class_name CHECK (((crown_class_name)::text = ANY ((ARRAY['dominant'::character varying, 'co_dominant'::character varying, 'intermediate'::character varying, 'overtopped'::character varying, 'open_grown'::character varying])::text[])))
);


--
-- Name: TABLE crownclasses; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.crownclasses IS 'Crown social/competitive position classification (FIA CCLCD / NEON canopyPosition analog)';


--
-- Name: crownclasses; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.crownclasses AS
 SELECT crownclasses.crown_class_id,
    crownclasses.crown_class_name,
    crownclasses.description
   FROM trees.crownclasses;


--
-- Name: VIEW crownclasses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.crownclasses IS 'Public API view for crown classes (competitive/social position) lookup table';


--
-- Name: crownshapes; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.crownshapes (
    crown_shape_id integer NOT NULL,
    crown_shape_name character varying(50) NOT NULL,
    description text
);


--
-- Name: TABLE crownshapes; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.crownshapes IS 'Common crown shape descriptions (pyramidal, conical, globose, etc.)';


--
-- Name: crownshapes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.crownshapes AS
 SELECT crownshapes.crown_shape_id,
    crownshapes.crown_shape_name,
    crownshapes.description
   FROM trees.crownshapes;


--
-- Name: VIEW crownshapes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.crownshapes IS 'Public API view for crown shapes lookup table';


--
-- Name: damageagents; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.damageagents (
    damage_agent_id integer NOT NULL,
    damage_agent_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_damage_agent_name CHECK (((damage_agent_name)::text = ANY ((ARRAY['none'::character varying, 'insect'::character varying, 'disease'::character varying, 'fire'::character varying, 'wind'::character varying, 'snow_ice'::character varying, 'drought'::character varying, 'mechanical'::character varying, 'animal'::character varying, 'human_activity'::character varying, 'competition'::character varying, 'unknown'::character varying])::text[])))
);


--
-- Name: TABLE damageagents; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.damageagents IS 'Cause of tree damage, decline, or mortality (FIA AGENTCD analog)';


--
-- Name: damageagents; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.damageagents AS
 SELECT damageagents.damage_agent_id,
    damageagents.damage_agent_name,
    damageagents.description
   FROM trees.damageagents;


--
-- Name: VIEW damageagents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.damageagents IS 'Public API view for damage agents lookup table';


--
-- Name: datasourcetypes; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.datasourcetypes (
    data_source_type_id integer NOT NULL,
    data_source_type_name character varying(50) NOT NULL,
    description text
);


--
-- Name: TABLE datasourcetypes; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.datasourcetypes IS 'How tree measurement data was collected or generated';


--
-- Name: datasourcetypes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.datasourcetypes AS
 SELECT datasourcetypes.data_source_type_id,
    datasourcetypes.data_source_type_name,
    datasourcetypes.description
   FROM trees.datasourcetypes;


--
-- Name: VIEW datasourcetypes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.datasourcetypes IS 'Data source type classifications (field, lidar, photogrammetry, estimated, simulated)';


--
-- Name: deadwood; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.deadwood (
    deadwood_id integer NOT NULL,
    location_id integer NOT NULL,
    plot_id integer,
    tree_id integer,
    species_id integer,
    wood_type character varying(50) NOT NULL,
    length_m numeric(6,2),
    diameter_cm numeric(6,2),
    decay_class integer,
    volume_m3 numeric(10,3),
    "position" extensions.geometry(Point,4326),
    measurement_date date,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT deadwood_decay_class_check CHECK (((decay_class >= 1) AND (decay_class <= 5))),
    CONSTRAINT deadwood_diameter_cm_check CHECK ((diameter_cm > (0)::numeric)),
    CONSTRAINT deadwood_length_m_check CHECK ((length_m > (0)::numeric)),
    CONSTRAINT deadwood_volume_m3_check CHECK ((volume_m3 >= (0)::numeric)),
    CONSTRAINT deadwood_wood_type_check CHECK (((wood_type)::text = ANY ((ARRAY['standing'::character varying, 'fallen'::character varying, 'stump'::character varying, 'branch'::character varying])::text[])))
);


--
-- Name: TABLE deadwood; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.deadwood IS 'Dead wood inventory including standing dead, fallen logs, stumps, and branches';


--
-- Name: COLUMN deadwood.tree_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.deadwood.tree_id IS 'Optional link to known dead tree record';


--
-- Name: COLUMN deadwood.wood_type; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.deadwood.wood_type IS 'Type of dead wood: standing, fallen, stump, or branch';


--
-- Name: COLUMN deadwood.decay_class; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.deadwood.decay_class IS 'Decay stage from 1 (fresh) to 5 (fully decomposed)';


--
-- Name: deadwood; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.deadwood WITH (security_invoker='on') AS
 SELECT deadwood.deadwood_id,
    deadwood.location_id,
    deadwood.plot_id,
    deadwood.tree_id,
    deadwood.species_id,
    deadwood.wood_type,
    deadwood.length_m,
    deadwood.diameter_cm,
    deadwood.decay_class,
    deadwood.volume_m3,
    deadwood."position",
    deadwood.measurement_date,
    deadwood.notes,
    deadwood.created_at,
    deadwood.created_by
   FROM trees.deadwood;


--
-- Name: VIEW deadwood; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.deadwood IS 'Public API view for dead wood inventory';


--
-- Name: disturbanceevents; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.disturbanceevents (
    disturbance_event_id integer NOT NULL,
    location_id integer NOT NULL,
    plot_id integer,
    disturbance_type character varying(50) NOT NULL,
    event_date date NOT NULL,
    end_date date,
    severity character varying(20),
    affected_area_m2 numeric(12,2),
    description text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT chk_dist_event_dates CHECK (((end_date IS NULL) OR (end_date >= event_date))),
    CONSTRAINT disturbanceevents_affected_area_m2_check CHECK ((affected_area_m2 > (0)::numeric)),
    CONSTRAINT disturbanceevents_disturbance_type_check CHECK (((disturbance_type)::text = ANY ((ARRAY['storm'::character varying, 'fire'::character varying, 'insect'::character varying, 'drought'::character varying, 'disease'::character varying, 'flood'::character varying, 'frost'::character varying, 'snow_damage'::character varying, 'landslide'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT disturbanceevents_severity_check CHECK (((severity)::text = ANY ((ARRAY['low'::character varying, 'moderate'::character varying, 'high'::character varying, 'severe'::character varying])::text[])))
);


--
-- Name: TABLE disturbanceevents; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.disturbanceevents IS 'Natural disturbance events affecting forest areas (storms, fire, insects, etc.)';


--
-- Name: COLUMN disturbanceevents.disturbance_type; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.disturbanceevents.disturbance_type IS 'Type of natural disturbance';


--
-- Name: COLUMN disturbanceevents.severity; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.disturbanceevents.severity IS 'Disturbance severity level';


--
-- Name: COLUMN disturbanceevents.affected_area_m2; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.disturbanceevents.affected_area_m2 IS 'Estimated area affected in m²';


--
-- Name: disturbanceevents; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.disturbanceevents WITH (security_invoker='on') AS
 SELECT disturbanceevents.disturbance_event_id,
    disturbanceevents.location_id,
    disturbanceevents.plot_id,
    disturbanceevents.disturbance_type,
    disturbanceevents.event_date,
    disturbanceevents.end_date,
    disturbanceevents.severity,
    disturbanceevents.affected_area_m2,
    disturbanceevents.description,
    disturbanceevents.notes,
    disturbanceevents.created_at,
    disturbanceevents.updated_at,
    disturbanceevents.created_by,
    disturbanceevents.updated_by
   FROM shared.disturbanceevents;


--
-- Name: VIEW disturbanceevents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.disturbanceevents IS 'Public API view for natural disturbance events';


--
-- Name: environments; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.environments WITH (security_invoker='on') AS
 SELECT environments.environment_id,
    environments.parent_environment_id,
    environments.location_id,
    environments.scenario_id,
    environments.variant_type_id,
    environments.process_id,
    environments.variant_name,
    environments.start_date,
    environments.end_date,
    environments.avg_temperature_c,
    environments.avg_humidity_percent,
    environments.total_precipitation_mm,
    environments.avg_global_radiation_w_m2,
    environments.avg_co2_ppm,
    environments.avg_wind_speed_ms,
    environments.dominant_wind_direction_deg,
    environments.avg_soil_moisture_percent,
    environments.avg_soil_temperature_c,
    environments.soil_ph,
    environments.nutrient_nitrogen_mg_kg,
    environments.nutrient_phosphorus_mg_kg,
    environments.nutrient_potassium_mg_kg,
    environments.stress_factor,
    environments.description,
    environments.research_notes,
    environments.created_at,
    environments.updated_at,
    environments.created_by,
    environments.updated_by
   FROM environments.environments;


--
-- Name: VIEW environments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.environments IS 'Public API view for environments table';


--
-- Name: geometriccrownsolids; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.geometriccrownsolids (
    geometric_solid_id integer NOT NULL,
    geometric_solid_name character varying(50) NOT NULL,
    description text,
    relative_lateral_area numeric(4,2),
    relative_volume numeric(4,2),
    relative_drag numeric(4,2),
    CONSTRAINT geometriccrownsolids_relative_drag_check CHECK (((relative_drag >= (0)::numeric) AND (relative_drag <= (1)::numeric))),
    CONSTRAINT geometriccrownsolids_relative_lateral_area_check CHECK (((relative_lateral_area >= (0)::numeric) AND (relative_lateral_area <= (1)::numeric))),
    CONSTRAINT geometriccrownsolids_relative_volume_check CHECK (((relative_volume >= (0)::numeric) AND (relative_volume <= (1)::numeric)))
);


--
-- Name: TABLE geometriccrownsolids; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.geometriccrownsolids IS 'Geometric crown shape models for simulation (area, volume, drag calculations)';


--
-- Name: COLUMN geometriccrownsolids.relative_lateral_area; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.geometriccrownsolids.relative_lateral_area IS 'Relative frontal/lateral area (1.0 = cylinder baseline)';


--
-- Name: COLUMN geometriccrownsolids.relative_volume; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.geometriccrownsolids.relative_volume IS 'Relative crown volume (1.0 = cylinder baseline)';


--
-- Name: COLUMN geometriccrownsolids.relative_drag; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.geometriccrownsolids.relative_drag IS 'Relative wind drag coefficient (1.0 = cylinder baseline)';


--
-- Name: geometriccrownsolids; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.geometriccrownsolids AS
 SELECT geometriccrownsolids.geometric_solid_id,
    geometriccrownsolids.geometric_solid_name,
    geometriccrownsolids.description,
    geometriccrownsolids.relative_lateral_area,
    geometriccrownsolids.relative_volume,
    geometriccrownsolids.relative_drag
   FROM trees.geometriccrownsolids;


--
-- Name: VIEW geometriccrownsolids; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.geometriccrownsolids IS 'Public API view for geometric crown solids lookup table';


--
-- Name: groundvegetation; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.groundvegetation (
    ground_vegetation_id integer NOT NULL,
    location_id integer NOT NULL,
    plot_id integer,
    species_name character varying(200),
    cover_percent numeric(5,2),
    height_cm numeric(6,2),
    layer character varying(50),
    measurement_date date,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT groundvegetation_cover_percent_check CHECK (((cover_percent >= (0)::numeric) AND (cover_percent <= (100)::numeric))),
    CONSTRAINT groundvegetation_height_cm_check CHECK ((height_cm >= (0)::numeric)),
    CONSTRAINT groundvegetation_layer_check CHECK (((layer)::text = ANY ((ARRAY['herb'::character varying, 'shrub'::character varying, 'moss'::character varying, 'litter'::character varying, 'fern'::character varying, 'grass'::character varying])::text[])))
);


--
-- Name: TABLE groundvegetation; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.groundvegetation IS 'Ground vegetation survey records by plot and layer';


--
-- Name: COLUMN groundvegetation.cover_percent; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.groundvegetation.cover_percent IS 'Estimated cover percentage (0-100)';


--
-- Name: COLUMN groundvegetation.layer; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.groundvegetation.layer IS 'Vegetation layer: herb, shrub, moss, litter, fern, grass';


--
-- Name: groundvegetation; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.groundvegetation WITH (security_invoker='on') AS
 SELECT groundvegetation.ground_vegetation_id,
    groundvegetation.location_id,
    groundvegetation.plot_id,
    groundvegetation.species_name,
    groundvegetation.cover_percent,
    groundvegetation.height_cm,
    groundvegetation.layer,
    groundvegetation.measurement_date,
    groundvegetation.notes,
    groundvegetation.created_at,
    groundvegetation.created_by
   FROM trees.groundvegetation;


--
-- Name: VIEW groundvegetation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.groundvegetation IS 'Public API view for ground vegetation surveys';


--
-- Name: species; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.species (
    species_id integer NOT NULL,
    common_name character varying(200),
    scientific_name character varying(200) NOT NULL,
    max_height_m numeric(6,2),
    max_dbh_cm numeric(6,2),
    typical_lifespan_years integer,
    growth_rate character varying(20),
    shade_tolerance character varying(20),
    is_deciduous boolean,
    gbif_key integer,
    gbif_accepted_name character varying(200),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT species_growth_rate_check CHECK (((growth_rate)::text = ANY ((ARRAY['very_slow'::character varying, 'slow'::character varying, 'moderate'::character varying, 'fast'::character varying, 'very_fast'::character varying])::text[]))),
    CONSTRAINT species_shade_tolerance_check CHECK (((shade_tolerance)::text = ANY ((ARRAY['very_low'::character varying, 'low'::character varying, 'moderate'::character varying, 'high'::character varying, 'very_high'::character varying])::text[])))
);


--
-- Name: TABLE species; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.species IS 'Tree species reference with growth characteristics';


--
-- Name: COLUMN species.max_height_m; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.species.max_height_m IS 'Maximum typical height in meters';


--
-- Name: COLUMN species.max_dbh_cm; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.species.max_dbh_cm IS 'Maximum typical diameter at breast height in centimeters';


--
-- Name: COLUMN species.typical_lifespan_years; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.species.typical_lifespan_years IS 'Typical lifespan in years';


--
-- Name: COLUMN species.growth_rate; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.species.growth_rate IS 'Relative growth rate (very_slow, slow, moderate, fast, very_fast)';


--
-- Name: COLUMN species.shade_tolerance; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.species.shade_tolerance IS 'Shade tolerance level (very_low, low, moderate, high, very_high)';


--
-- Name: COLUMN species.is_deciduous; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.species.is_deciduous IS 'Whether species is deciduous (true) or evergreen (false), NULL if unknown';


--
-- Name: growthsimulations; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.growthsimulations (
    growth_simulation_id bigint NOT NULL,
    run_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tree_entity_id uuid NOT NULL,
    base_tree_id integer,
    location_id integer,
    plot_id integer,
    scenario_id integer,
    species_id integer,
    simulator_name character varying(100) NOT NULL,
    simulator_version character varying(50),
    projection_year integer NOT NULL,
    time_delta_yrs numeric(8,2),
    height_m numeric(6,2),
    dbh_cm numeric(6,2),
    basal_area_m2 numeric(8,4),
    crown_width_m numeric(6,2),
    crown_base_height_m numeric(6,2),
    volume_m3 numeric(10,3),
    biomass_kg numeric(12,2),
    carbon_content_kg numeric(12,2),
    health_score numeric(3,2),
    mortality boolean DEFAULT false NOT NULL,
    stand_basal_area_m2ha numeric(8,4),
    stand_volume_m3ha numeric(10,3),
    stand_biomass_tha numeric(10,3),
    stand_stem_count_ha integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(200),
    CONSTRAINT chk_crown_base_le_height CHECK (((crown_base_height_m IS NULL) OR (height_m IS NULL) OR (crown_base_height_m <= height_m))),
    CONSTRAINT growthsimulations_basal_area_m2_check CHECK (((basal_area_m2 IS NULL) OR (basal_area_m2 >= (0)::numeric))),
    CONSTRAINT growthsimulations_biomass_kg_check CHECK (((biomass_kg IS NULL) OR (biomass_kg >= (0)::numeric))),
    CONSTRAINT growthsimulations_carbon_content_kg_check CHECK (((carbon_content_kg IS NULL) OR (carbon_content_kg >= (0)::numeric))),
    CONSTRAINT growthsimulations_crown_base_height_m_check CHECK (((crown_base_height_m IS NULL) OR (crown_base_height_m >= (0)::numeric))),
    CONSTRAINT growthsimulations_crown_width_m_check CHECK (((crown_width_m IS NULL) OR (crown_width_m >= (0)::numeric))),
    CONSTRAINT growthsimulations_dbh_cm_check CHECK (((dbh_cm IS NULL) OR (dbh_cm > (0)::numeric))),
    CONSTRAINT growthsimulations_health_score_check CHECK (((health_score IS NULL) OR ((health_score >= (0)::numeric) AND (health_score <= (1)::numeric)))),
    CONSTRAINT growthsimulations_height_m_check CHECK (((height_m IS NULL) OR (height_m > (0)::numeric))),
    CONSTRAINT growthsimulations_projection_year_check CHECK (((projection_year >= 1900) AND (projection_year <= 2300))),
    CONSTRAINT growthsimulations_simulator_name_check CHECK (((simulator_name)::text = ANY ((ARRAY['SILVA'::character varying, 'FVS'::character varying, 'iLand'::character varying, 'manual'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT growthsimulations_stand_basal_area_m2ha_check CHECK (((stand_basal_area_m2ha IS NULL) OR (stand_basal_area_m2ha >= (0)::numeric))),
    CONSTRAINT growthsimulations_stand_biomass_tha_check CHECK (((stand_biomass_tha IS NULL) OR (stand_biomass_tha >= (0)::numeric))),
    CONSTRAINT growthsimulations_stand_stem_count_ha_check CHECK (((stand_stem_count_ha IS NULL) OR (stand_stem_count_ha >= 0))),
    CONSTRAINT growthsimulations_stand_volume_m3ha_check CHECK (((stand_volume_m3ha IS NULL) OR (stand_volume_m3ha >= (0)::numeric))),
    CONSTRAINT growthsimulations_volume_m3_check CHECK (((volume_m3 IS NULL) OR (volume_m3 >= (0)::numeric)))
);


--
-- Name: TABLE growthsimulations; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.growthsimulations IS 'Per-tree forest growth projections from SILVA, FVS, iLand, or manual estimation. One row per (run_id, tree_entity_id, projection_year). run_id groups all rows produced by a single simulation run.';


--
-- Name: COLUMN growthsimulations.run_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.growthsimulations.run_id IS 'UUID identifying a single simulation run. All rows with the same run_id belong to one simulator execution and can be compared as a complete forest state.';


--
-- Name: COLUMN growthsimulations.tree_entity_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.growthsimulations.tree_entity_id IS 'Stable UUID of the physical tree (cross-variant identity from trees.Trees.tree_entity_id).';


--
-- Name: COLUMN growthsimulations.base_tree_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.growthsimulations.base_tree_id IS 'trees.Trees row (tree_id) used as the simulation input (baseline measurement).';


--
-- Name: COLUMN growthsimulations.projection_year; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.growthsimulations.projection_year IS 'Calendar year this projection describes.';


--
-- Name: COLUMN growthsimulations.mortality; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.growthsimulations.mortality IS 'True if this tree dies in this projection time step.';


--
-- Name: COLUMN growthsimulations.stand_basal_area_m2ha; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.growthsimulations.stand_basal_area_m2ha IS 'Stand-level basal area (m²/ha) — same value repeated for all trees in this run_id+Year.';


--
-- Name: growth_simulations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.growth_simulations AS
 SELECT gs.growth_simulation_id,
    gs.run_id,
    gs.tree_entity_id,
    gs.base_tree_id,
    gs.location_id,
    gs.plot_id,
    gs.scenario_id,
    s.scenario_name,
    sp.common_name AS species_name,
    sp.scientific_name,
    gs.simulator_name,
    gs.simulator_version,
    gs.projection_year,
    gs.time_delta_yrs,
    gs.height_m,
    gs.dbh_cm,
    gs.basal_area_m2,
    gs.crown_width_m,
    gs.crown_base_height_m,
    gs.volume_m3,
    gs.biomass_kg,
    gs.carbon_content_kg,
    gs.health_score,
    gs.mortality,
    gs.stand_basal_area_m2ha,
    gs.stand_volume_m3ha,
    gs.stand_biomass_tha AS standbio_tha,
    gs.stand_stem_count_ha,
    gs.created_at,
    gs.created_by
   FROM ((trees.growthsimulations gs
     LEFT JOIN shared.scenarios s ON ((gs.scenario_id = s.scenario_id)))
     LEFT JOIN shared.species sp ON ((gs.species_id = sp.species_id)));


--
-- Name: VIEW growth_simulations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.growth_simulations IS 'Flat view of growth simulation projections with scenario and species names resolved. Filter by scenario_name + projection_year to get a full forest state for UE Time Machine.';


--
-- Name: growthforms; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.growthforms (
    growth_form_id integer NOT NULL,
    growth_form_name character varying(50) NOT NULL,
    description text
);


--
-- Name: TABLE growthforms; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.growthforms IS 'General growth form classification (dendroid, arborescent, etc.)';


--
-- Name: growthforms; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.growthforms AS
 SELECT growthforms.growth_form_id,
    growthforms.growth_form_name,
    growthforms.description
   FROM trees.growthforms;


--
-- Name: VIEW growthforms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.growthforms IS 'Public API view for growth forms lookup table';


--
-- Name: growthorientations; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.growthorientations (
    growth_orientation_id integer NOT NULL,
    growth_orientation_name character varying(50) NOT NULL,
    description text
);


--
-- Name: TABLE growthorientations; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.growthorientations IS 'Shoot growth orientation (orthotropic=vertical, plagiotrophic=horizontal)';


--
-- Name: growthorientations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.growthorientations AS
 SELECT growthorientations.growth_orientation_id,
    growthorientations.growth_orientation_name,
    growthorientations.description
   FROM trees.growthorientations;


--
-- Name: VIEW growthorientations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.growthorientations IS 'Public API view for growth orientations lookup table';


--
-- Name: images; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.images WITH (security_invoker='on') AS
 SELECT images.image_id,
    images.location_id,
    images.plot_id,
    images.campaign_id,
    images.capture_date,
    images.file_path,
    images.file_format,
    images.resolution_px,
    images.camera_model,
    images."position",
    images.altitude_m,
    images.heading_deg,
    images.pitch_deg,
    images.roll_deg,
    images.ground_sample_distance_cm,
    images.description,
    images.created_at,
    images.updated_at,
    images.created_by,
    images.updated_by
   FROM imagery.images;


--
-- Name: VIEW images; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.images IS 'Public API view for imagery table';


--
-- Name: locations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.locations WITH (security_invoker='on') AS
 SELECT locations.location_id,
    locations.location_name,
    locations.boundary,
    locations.center_point,
    locations.description,
    locations.elevation_m,
    locations.slope_deg,
    locations.aspect,
    locations.soil_type_id,
    locations.climate_zone_id,
    locations.created_at,
    locations.updated_at,
    locations.created_by,
    locations.updated_by
   FROM shared.locations;


--
-- Name: VIEW locations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.locations IS 'Public API view for locations reference table';


--
-- Name: managementevents; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.managementevents (
    management_event_id integer NOT NULL,
    location_id integer NOT NULL,
    plot_id integer,
    event_type character varying(50) NOT NULL,
    event_date date NOT NULL,
    end_date date,
    description text,
    affected_area_m2 numeric(12,2),
    performed_by character varying(200),
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT chk_mgmt_event_dates CHECK (((end_date IS NULL) OR (end_date >= event_date))),
    CONSTRAINT managementevents_affected_area_m2_check CHECK ((affected_area_m2 > (0)::numeric)),
    CONSTRAINT managementevents_event_type_check CHECK (((event_type)::text = ANY ((ARRAY['thinning'::character varying, 'planting'::character varying, 'harvesting'::character varying, 'pruning'::character varying, 'fertilization'::character varying, 'prescribed_burn'::character varying, 'salvage_logging'::character varying, 'site_preparation'::character varying, 'other'::character varying])::text[])))
);


--
-- Name: TABLE managementevents; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.managementevents IS 'Forest management activities (thinning, planting, harvesting, etc.)';


--
-- Name: COLUMN managementevents.event_type; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.managementevents.event_type IS 'Type of management activity';


--
-- Name: COLUMN managementevents.affected_area_m2; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.managementevents.affected_area_m2 IS 'Area affected by the management activity in m²';


--
-- Name: managementevents; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.managementevents WITH (security_invoker='on') AS
 SELECT managementevents.management_event_id,
    managementevents.location_id,
    managementevents.plot_id,
    managementevents.event_type,
    managementevents.event_date,
    managementevents.end_date,
    managementevents.description,
    managementevents.affected_area_m2,
    managementevents.performed_by,
    managementevents.notes,
    managementevents.created_at,
    managementevents.updated_at,
    managementevents.created_by,
    managementevents.updated_by
   FROM shared.managementevents;


--
-- Name: VIEW managementevents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.managementevents IS 'Public API view for forest management events';


--
-- Name: phanerophyteheightclasses; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.phanerophyteheightclasses (
    phanerophyte_height_class_id integer NOT NULL,
    height_class_name character varying(50) NOT NULL,
    description text,
    min_height_m numeric(6,2),
    max_height_m numeric(6,2),
    CONSTRAINT chk_height_class_order CHECK (((min_height_m IS NULL) OR (max_height_m IS NULL) OR (min_height_m < max_height_m))),
    CONSTRAINT phanerophyteheightclasses_max_height_m_check CHECK ((max_height_m > (0)::numeric)),
    CONSTRAINT phanerophyteheightclasses_min_height_m_check CHECK ((min_height_m >= (0)::numeric))
);


--
-- Name: TABLE phanerophyteheightclasses; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.phanerophyteheightclasses IS 'Tree height classification (mega/meso/micro-phanerophyte)';


--
-- Name: COLUMN phanerophyteheightclasses.min_height_m; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.phanerophyteheightclasses.min_height_m IS 'Minimum height for this class (NULL = no lower bound)';


--
-- Name: COLUMN phanerophyteheightclasses.max_height_m; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.phanerophyteheightclasses.max_height_m IS 'Maximum height for this class (NULL = no upper bound)';


--
-- Name: phanerophyteheightclasses; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.phanerophyteheightclasses AS
 SELECT phanerophyteheightclasses.phanerophyte_height_class_id,
    phanerophyteheightclasses.height_class_name,
    phanerophyteheightclasses.description,
    phanerophyteheightclasses.min_height_m,
    phanerophyteheightclasses.max_height_m
   FROM trees.phanerophyteheightclasses;


--
-- Name: VIEW phanerophyteheightclasses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.phanerophyteheightclasses IS 'Public API view for phanerophyte height classes lookup table';


--
-- Name: phenologyobservations; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.phenologyobservations (
    phenology_observation_id integer NOT NULL,
    tree_id integer NOT NULL,
    observation_date date NOT NULL,
    phenophase_type character varying(50) NOT NULL,
    phenophase_status character varying(50),
    intensity_percent numeric(5,2),
    observer character varying(200),
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT phenologyobservations_intensity_percent_check CHECK (((intensity_percent >= (0)::numeric) AND (intensity_percent <= (100)::numeric))),
    CONSTRAINT phenologyobservations_phenophase_status_check CHECK (((phenophase_status)::text = ANY ((ARRAY['not_started'::character varying, 'beginning'::character varying, 'intermediate'::character varying, 'peak'::character varying, 'ending'::character varying, 'completed'::character varying])::text[]))),
    CONSTRAINT phenologyobservations_phenophase_type_check CHECK (((phenophase_type)::text = ANY ((ARRAY['bud_break'::character varying, 'leaf_out'::character varying, 'flowering'::character varying, 'fruit_set'::character varying, 'leaf_color'::character varying, 'leaf_fall'::character varying, 'dormancy'::character varying])::text[])))
);


--
-- Name: TABLE phenologyobservations; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.phenologyobservations IS 'Tree phenology observations tracking seasonal development phases';


--
-- Name: COLUMN phenologyobservations.phenophase_type; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.phenologyobservations.phenophase_type IS 'Type of phenological phase being observed';


--
-- Name: COLUMN phenologyobservations.phenophase_status; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.phenologyobservations.phenophase_status IS 'Current status of the phenophase';


--
-- Name: COLUMN phenologyobservations.intensity_percent; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.phenologyobservations.intensity_percent IS 'Intensity of the phenophase (0-100%)';


--
-- Name: phenologyobservations; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.phenologyobservations WITH (security_invoker='on') AS
 SELECT phenologyobservations.phenology_observation_id,
    phenologyobservations.tree_id,
    phenologyobservations.observation_date,
    phenologyobservations.phenophase_type,
    phenologyobservations.phenophase_status,
    phenologyobservations.intensity_percent,
    phenologyobservations.observer,
    phenologyobservations.notes,
    phenologyobservations.created_at,
    phenologyobservations.created_by
   FROM trees.phenologyobservations;


--
-- Name: VIEW phenologyobservations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.phenologyobservations IS 'Public API view for tree phenology observations';


--
-- Name: plots; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.plots (
    plot_id integer NOT NULL,
    location_id integer NOT NULL,
    plot_name character varying(200) NOT NULL,
    plot_number integer,
    area_m2 numeric(12,2),
    boundary extensions.geometry(Polygon,4326),
    center_point extensions.geometry(Point,4326),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT plots_area_m2_check CHECK ((area_m2 > (0)::numeric))
);


--
-- Name: TABLE plots; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.plots IS 'Sub-plot divisions within locations for detailed research grids';


--
-- Name: COLUMN plots.plot_name; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.plots.plot_name IS 'Plot identifier, unique within a location';


--
-- Name: COLUMN plots.plot_number; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.plots.plot_number IS 'Numeric plot identifier for ordering';


--
-- Name: COLUMN plots.area_m2; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.plots.area_m2 IS 'Plot area in square meters';


--
-- Name: COLUMN plots.boundary; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.plots.boundary IS 'PostGIS polygon defining plot boundaries in WGS84';


--
-- Name: plots; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.plots WITH (security_invoker='on') AS
 SELECT plots.plot_id,
    plots.location_id,
    plots.plot_name,
    plots.plot_number,
    plots.area_m2,
    plots.boundary,
    plots.center_point,
    plots.description,
    plots.created_at,
    plots.updated_at,
    plots.created_by,
    plots.updated_by
   FROM shared.plots;


--
-- Name: VIEW plots; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.plots IS 'Public API view for sub-plot divisions within locations';


--
-- Name: pointclouds; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.pointclouds WITH (security_invoker='on') AS
 SELECT pointclouds.point_cloud_id,
    pointclouds.parent_point_cloud_id,
    pointclouds.location_id,
    pointclouds.scenario_id,
    pointclouds.variant_type_id,
    pointclouds.process_id,
    pointclouds.campaign_id,
    pointclouds.scanner_id,
    pointclouds.variant_name,
    pointclouds.scan_date,
    pointclouds.sensor_model,
    pointclouds.source_crs,
    pointclouds.platform_type,
    pointclouds.scan_bounds,
    pointclouds.file_path,
    pointclouds.flight_altitude_m,
    pointclouds.flight_speed_ms,
    pointclouds.scan_angle_deg,
    pointclouds.overlap_percent,
    pointclouds.point_count,
    pointclouds.point_density_per_m2,
    pointclouds.file_size_mb,
    pointclouds.processing_status,
    pointclouds.processing_progress,
    pointclouds.error_message,
    pointclouds.created_at,
    pointclouds.updated_at,
    pointclouds.created_by,
    pointclouds.updated_by
   FROM pointclouds.pointclouds;


--
-- Name: VIEW pointclouds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.pointclouds IS 'Public API view for point clouds table';


--
-- Name: scenarios; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.scenarios AS
 SELECT scenarios.scenario_id,
    scenarios.scenario_name,
    scenarios.description,
    scenarios.created_at,
    scenarios.updated_at,
    scenarios.location_id
   FROM shared.scenarios;


--
-- Name: VIEW scenarios; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.scenarios IS 'Public API view: location-scoped management regimes (Location -> Scenario -> Variant).';


--
-- Name: sensor_tree_links; Type: TABLE; Schema: sensor; Owner: -
--

CREATE TABLE sensor.sensor_tree_links (
    sensortreelinkid integer NOT NULL,
    sensor_id integer NOT NULL,
    tree_id integer NOT NULL,
    description text,
    start_date date,
    end_date date,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE sensor_tree_links; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON TABLE sensor.sensor_tree_links IS 'Links sensors to specific tree records';


--
-- Name: sensor_tree_links; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sensor_tree_links WITH (security_invoker='on') AS
 SELECT sensor_tree_links.sensortreelinkid,
    sensor_tree_links.sensor_id,
    sensor_tree_links.tree_id,
    sensor_tree_links.description,
    sensor_tree_links.start_date,
    sensor_tree_links.end_date,
    sensor_tree_links.created_at
   FROM sensor.sensor_tree_links;


--
-- Name: VIEW sensor_tree_links; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.sensor_tree_links IS 'Public API view for sensor-tree link table';


--
-- Name: sensorreadings; Type: TABLE; Schema: sensor; Owner: -
--

CREATE TABLE sensor.sensorreadings (
    sensor_reading_id bigint NOT NULL,
    sensor_id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    value numeric(12,4) NOT NULL,
    quality character varying(50),
    scenario_id integer,
    battery_voltage numeric(4,2),
    signal_strength numeric(6,2),
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT sensorreadings_quality_check CHECK (((quality)::text = ANY ((ARRAY['good'::character varying, 'suspect'::character varying, 'bad'::character varying, 'missing'::character varying, 'calibration'::character varying])::text[])))
);


--
-- Name: TABLE sensorreadings; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON TABLE sensor.sensorreadings IS 'Time-series environmental sensor measurements';


--
-- Name: COLUMN sensorreadings.quality; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensorreadings.quality IS 'Data quality flag (good, suspect, bad, missing, calibration)';


--
-- Name: COLUMN sensorreadings.scenario_id; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensorreadings.scenario_id IS 'NULL for real readings, references scenario for simulated data';


--
-- Name: COLUMN sensorreadings.signal_strength; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensorreadings.signal_strength IS 'Wireless signal strength in dBm';


--
-- Name: sensorreadings; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sensorreadings WITH (security_invoker='on') AS
 SELECT sensorreadings.sensor_reading_id,
    sensorreadings.sensor_id,
    sensorreadings."timestamp",
    sensorreadings.value,
    sensorreadings.quality,
    sensorreadings.scenario_id,
    sensorreadings.battery_voltage,
    sensorreadings.signal_strength,
    sensorreadings.notes,
    sensorreadings.created_at
   FROM sensor.sensorreadings;


--
-- Name: VIEW sensorreadings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.sensorreadings IS 'Public API view for sensor readings table';


--
-- Name: sensors; Type: TABLE; Schema: sensor; Owner: -
--

CREATE TABLE sensor.sensors (
    sensor_id integer NOT NULL,
    location_id integer NOT NULL,
    sensor_type_id integer NOT NULL,
    campaign_id integer,
    plot_id integer,
    sensor_model character varying(200) NOT NULL,
    serial_number character varying(100),
    "position" extensions.geometry(Point,4326) NOT NULL,
    position_original extensions.geometry,
    source_crs integer,
    installation_date timestamp with time zone DEFAULT now() NOT NULL,
    installation_height_m numeric(5,2),
    decommission_date timestamp with time zone,
    calibration_date timestamp with time zone,
    next_calibration_date timestamp with time zone,
    sampling_interval_seconds integer NOT NULL,
    reading_type character varying(100),
    unit character varying(50),
    min_value numeric(12,4),
    max_value numeric(12,4),
    accuracy numeric(8,4),
    battery_level_percent numeric(5,2),
    is_active boolean DEFAULT true,
    maintenance_notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    source character varying(50),
    external_id character varying(200),
    external_metadata jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT chk_decommission_date CHECK (((decommission_date IS NULL) OR (decommission_date >= installation_date))),
    CONSTRAINT chk_value_range CHECK (((min_value IS NULL) OR (max_value IS NULL) OR (min_value <= max_value))),
    CONSTRAINT sensors_battery_level_percent_check CHECK (((battery_level_percent >= (0)::numeric) AND (battery_level_percent <= (100)::numeric))),
    CONSTRAINT sensors_installation_height_m_check CHECK ((installation_height_m >= (0)::numeric)),
    CONSTRAINT sensors_sampling_interval_seconds_check CHECK ((sampling_interval_seconds > 0))
);


--
-- Name: TABLE sensors; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON TABLE sensor.sensors IS 'Physical sensor installations with metadata and configuration';


--
-- Name: COLUMN sensors.campaign_id; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.campaign_id IS 'Deployment campaign this sensor was installed during';


--
-- Name: COLUMN sensors.plot_id; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.plot_id IS 'Named monitoring sub-area (plot) within the location, e.g. douglas_fir_plot. Populated from the location identifier of the external sensor sync; the site is location_id.';


--
-- Name: COLUMN sensors."position"; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors."position" IS 'PostGIS point for sensor location in WGS84';


--
-- Name: COLUMN sensors.position_original; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.position_original IS 'Original coordinates in source CRS before WGS84 transformation';


--
-- Name: COLUMN sensors.source_crs; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.source_crs IS 'EPSG code of original coordinate reference system for position_original';


--
-- Name: COLUMN sensors.installation_height_m; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.installation_height_m IS 'Height of sensor installation above ground in meters';


--
-- Name: COLUMN sensors.sampling_interval_seconds; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.sampling_interval_seconds IS 'Frequency of sensor measurements in seconds';


--
-- Name: COLUMN sensors.is_active; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.is_active IS 'Whether sensor is currently collecting data';


--
-- Name: COLUMN sensors.source; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.source IS 'External system this sensor''s data comes from (e.g. ''aquarius''). One of many possible providers.';


--
-- Name: COLUMN sensors.external_id; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.external_id IS 'Unique identifier for this sensor within its source system (see source).';


--
-- Name: COLUMN sensors.external_metadata; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON COLUMN sensor.sensors.external_metadata IS 'Additional source-specific metadata (raw payload from the provider).';


--
-- Name: sensors; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sensors WITH (security_invoker='on') AS
 SELECT sensors.sensor_id,
    sensors.location_id,
    sensors.sensor_type_id,
    sensors.campaign_id,
    sensors.plot_id,
    sensors.sensor_model,
    sensors.serial_number,
    sensors."position",
    sensors.position_original,
    sensors.source_crs,
    sensors.installation_date,
    sensors.installation_height_m,
    sensors.decommission_date,
    sensors.calibration_date,
    sensors.next_calibration_date,
    sensors.sampling_interval_seconds,
    sensors.reading_type,
    sensors.unit,
    sensors.min_value,
    sensors.max_value,
    sensors.accuracy,
    sensors.battery_level_percent,
    sensors.is_active,
    sensors.maintenance_notes,
    sensors.created_at,
    sensors.updated_at,
    sensors.created_by,
    sensors.updated_by,
    sensors.source,
    sensors.external_id,
    sensors.external_metadata
   FROM sensor.sensors;


--
-- Name: VIEW sensors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.sensors IS 'Public API view for sensors table';


--
-- Name: sensortypes; Type: TABLE; Schema: sensor; Owner: -
--

CREATE TABLE sensor.sensortypes (
    sensor_type_id integer NOT NULL,
    sensor_type_name character varying(100) NOT NULL,
    description text,
    typical_unit character varying(50),
    typical_range_min numeric(12,4),
    typical_range_max numeric(12,4),
    CONSTRAINT chk_typical_range CHECK (((typical_range_min IS NULL) OR (typical_range_max IS NULL) OR (typical_range_min <= typical_range_max)))
);


--
-- Name: TABLE sensortypes; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON TABLE sensor.sensortypes IS 'Environmental sensor type classifications';


--
-- Name: sensortypes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.sensortypes WITH (security_invoker='on') AS
 SELECT sensortypes.sensor_type_id,
    sensortypes.sensor_type_name,
    sensortypes.description,
    sensortypes.typical_unit,
    sensortypes.typical_range_min,
    sensortypes.typical_range_max
   FROM sensor.sensortypes;


--
-- Name: VIEW sensortypes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.sensortypes IS 'Public API view for sensor types reference table';


--
-- Name: shootelongationtypes; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.shootelongationtypes (
    shoot_elongation_type_id integer NOT NULL,
    shoot_elongation_type_name character varying(50) NOT NULL,
    description text
);


--
-- Name: TABLE shootelongationtypes; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.shootelongationtypes IS 'Shoot elongation classification (long, short, spur shoots)';


--
-- Name: shootelongationtypes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.shootelongationtypes AS
 SELECT shootelongationtypes.shoot_elongation_type_id,
    shootelongationtypes.shoot_elongation_type_name,
    shootelongationtypes.description
   FROM trees.shootelongationtypes;


--
-- Name: VIEW shootelongationtypes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.shootelongationtypes IS 'Public API view for shoot elongation types lookup table';


--
-- Name: stems; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.stems (
    stem_id integer NOT NULL,
    tree_id integer NOT NULL,
    stem_number integer NOT NULL,
    taper_type_id integer,
    straightness_type_id integer,
    dbh_cm numeric(6,2),
    taper_ratio numeric(4,3),
    sweep_cm_per_m numeric(5,2),
    stem_height_m numeric(6,2),
    stem_volume_m3 numeric(10,3),
    bark_thickness_mm numeric(5,2),
    wood_density_kg_m3 numeric(6,2),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT stems_bark_thickness_mm_check CHECK (((bark_thickness_mm >= (0)::numeric) AND (bark_thickness_mm <= (200)::numeric))),
    CONSTRAINT stems_dbh_cm_check CHECK (((dbh_cm > (0)::numeric) AND (dbh_cm <= (1000)::numeric))),
    CONSTRAINT stems_stem_height_m_check CHECK (((stem_height_m > (0)::numeric) AND (stem_height_m <= (200)::numeric))),
    CONSTRAINT stems_stem_number_check CHECK ((stem_number >= 1)),
    CONSTRAINT stems_stem_volume_m3_check CHECK ((stem_volume_m3 >= (0)::numeric)),
    CONSTRAINT stems_sweep_cm_per_m_check CHECK ((sweep_cm_per_m >= (0)::numeric)),
    CONSTRAINT stems_taper_ratio_check CHECK (((taper_ratio >= (0)::numeric) AND (taper_ratio <= (1)::numeric))),
    CONSTRAINT stems_wood_density_kg_m3_check CHECK (((wood_density_kg_m3 >= (100)::numeric) AND (wood_density_kg_m3 <= (2000)::numeric)))
);


--
-- Name: TABLE stems; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.stems IS 'Individual stem measurements for multi-stem trees';


--
-- Name: COLUMN stems.stem_number; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.stems.stem_number IS 'Stem number (1=main stem, 2+=secondary stems)';


--
-- Name: COLUMN stems.dbh_cm; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.stems.dbh_cm IS 'Diameter at breast height (1.3m) in centimeters';


--
-- Name: COLUMN stems.taper_ratio; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.stems.taper_ratio IS 'Ratio of top diameter to bottom diameter';


--
-- Name: COLUMN stems.sweep_cm_per_m; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.stems.sweep_cm_per_m IS 'Maximum horizontal deviation per meter of height';


--
-- Name: trees; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.trees (
    tree_id integer NOT NULL,
    tree_entity_id uuid DEFAULT gen_random_uuid(),
    variant_id integer,
    parent_tree_id integer,
    point_cloud_id integer,
    campaign_id integer,
    location_id integer NOT NULL,
    plot_id integer,
    scenario_id integer,
    variant_type_id integer NOT NULL,
    process_id integer,
    species_id integer,
    tree_status_id integer,
    branching_pattern_id integer,
    bark_characteristic_id integer,
    measurement_date date,
    data_source_type_id integer,
    height_m numeric(6,2),
    height_source character varying(50) DEFAULT 'measured'::character varying,
    crown_width_m numeric(6,2),
    crown_base_height_m numeric(6,2),
    crown_boundary extensions.geometry(Polygon,4326),
    crown_offset_x_m numeric(5,2),
    crown_offset_y_m numeric(5,2),
    volume_m3 numeric(10,3),
    "position" extensions.geometry(Point,4326) NOT NULL,
    position_original extensions.geometry,
    source_crs integer,
    lean_angle_deg numeric(5,2),
    lean_direction_azimuth integer,
    time_delta_yrs numeric(8,2),
    age_years integer,
    health_score numeric(3,2),
    biomass_kg numeric(12,2),
    carbon_content_kg numeric(12,2),
    species_confidence numeric(3,2),
    position_confidence numeric(3,2),
    height_confidence numeric(3,2),
    status_change_date date,
    tree_number integer,
    field_notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    created_by character varying(200),
    updated_by character varying(200),
    height_class_id integer,
    crown_architecture_id integer,
    elongation_habit_id integer,
    growth_orientation_id integer,
    shoot_elongation_type_id integer,
    crown_shape_id integer,
    geometric_solid_id integer,
    axis_structure_id integer,
    growth_form_id integer,
    live_crown_ratio numeric(4,3) GENERATED ALWAYS AS (
CASE
    WHEN ((height_m IS NOT NULL) AND (height_m > (0)::numeric) AND (crown_base_height_m IS NOT NULL)) THEN ((height_m - crown_base_height_m) / height_m)
    ELSE NULL::numeric
END) STORED,
    crown_class_id integer,
    damage_agent_id integer,
    defoliation_percent numeric(5,2),
    discolouration_percent numeric(5,2),
    crown_transparency_percent numeric(5,2),
    sensor_ref character varying(100),
    CONSTRAINT chk_crown_base_height CHECK (((crown_base_height_m IS NULL) OR (crown_base_height_m <= height_m))),
    CONSTRAINT trees_age_years_check CHECK (((age_years >= 0) AND (age_years <= 5000))),
    CONSTRAINT trees_biomass_kg_check CHECK ((biomass_kg >= (0)::numeric)),
    CONSTRAINT trees_carbon_content_kg_check CHECK ((carbon_content_kg >= (0)::numeric)),
    CONSTRAINT trees_crown_base_height_m_check CHECK ((crown_base_height_m >= (0)::numeric)),
    CONSTRAINT trees_crown_transparency_percent_check CHECK (((crown_transparency_percent >= (0)::numeric) AND (crown_transparency_percent <= (100)::numeric))),
    CONSTRAINT trees_crown_width_m_check CHECK (((crown_width_m >= (0)::numeric) AND (crown_width_m <= (100)::numeric))),
    CONSTRAINT trees_defoliation_percent_check CHECK (((defoliation_percent >= (0)::numeric) AND (defoliation_percent <= (100)::numeric))),
    CONSTRAINT trees_discolouration_percent_check CHECK (((discolouration_percent >= (0)::numeric) AND (discolouration_percent <= (100)::numeric))),
    CONSTRAINT trees_health_score_check CHECK (((health_score >= (0)::numeric) AND (health_score <= (1)::numeric))),
    CONSTRAINT trees_height_confidence_check CHECK (((height_confidence >= (0)::numeric) AND (height_confidence <= (1)::numeric))),
    CONSTRAINT trees_height_m_check CHECK (((height_m > (0)::numeric) AND (height_m <= (200)::numeric))),
    CONSTRAINT trees_lean_angle_deg_check CHECK (((lean_angle_deg >= (0)::numeric) AND (lean_angle_deg <= (90)::numeric))),
    CONSTRAINT trees_lean_direction_azimuth_check CHECK (((lean_direction_azimuth >= 0) AND (lean_direction_azimuth < 360))),
    CONSTRAINT trees_position_confidence_check CHECK (((position_confidence >= (0)::numeric) AND (position_confidence <= (1)::numeric))),
    CONSTRAINT trees_species_confidence_check CHECK (((species_confidence >= (0)::numeric) AND (species_confidence <= (1)::numeric))),
    CONSTRAINT trees_volume_m3_check CHECK ((volume_m3 >= (0)::numeric))
);


--
-- Name: TABLE trees; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.trees IS 'Tree measurement and simulation records with spatial positions';


--
-- Name: COLUMN trees.tree_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.tree_id IS 'Unique row identifier for this tree record';


--
-- Name: COLUMN trees.tree_entity_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.tree_entity_id IS 'Persistent UUID identifying the physical tree across all variants';


--
-- Name: COLUMN trees.variant_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.variant_id IS 'Forest state group — all trees sharing this variant_id belong to the same time step within a scenario. Use for UE time-travel switching.';


--
-- Name: COLUMN trees.parent_tree_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.parent_tree_id IS 'Parent tree record for tracking growth or modifications';


--
-- Name: COLUMN trees.point_cloud_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.point_cloud_id IS 'Source point cloud if tree was detected from LiDAR';


--
-- Name: COLUMN trees.campaign_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.campaign_id IS 'Data collection campaign this measurement belongs to';


--
-- Name: COLUMN trees.plot_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.plot_id IS 'Sub-plot within the location where tree is located';


--
-- Name: COLUMN trees.measurement_date; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.measurement_date IS 'Actual date of field measurement (may differ from created_at)';


--
-- Name: COLUMN trees.data_source_type_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.data_source_type_id IS 'FK to trees.DataSourceTypes — how the data was collected or generated';


--
-- Name: COLUMN trees.crown_boundary; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.crown_boundary IS 'PostGIS polygon defining crown extent';


--
-- Name: COLUMN trees.crown_offset_x_m; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.crown_offset_x_m IS 'Crown center offset from trunk position (X/East-West in meters)';


--
-- Name: COLUMN trees.crown_offset_y_m; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.crown_offset_y_m IS 'Crown center offset from trunk position (Y/North-South in meters)';


--
-- Name: COLUMN trees."position"; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees."position" IS 'PostGIS point for tree location in WGS84';


--
-- Name: COLUMN trees.position_original; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.position_original IS 'Original coordinates in source CRS before WGS84 transformation';


--
-- Name: COLUMN trees.source_crs; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.source_crs IS 'EPSG code of original coordinate reference system for position_original';


--
-- Name: COLUMN trees.time_delta_yrs; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.time_delta_yrs IS 'Time elapsed since parent variant (for growth simulations)';


--
-- Name: COLUMN trees.health_score; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.health_score IS 'Tree health assessment score (0=dead, 1=optimal)';


--
-- Name: COLUMN trees.species_confidence; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.species_confidence IS 'Confidence in species identification (0-1)';


--
-- Name: COLUMN trees.position_confidence; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.position_confidence IS 'Confidence in position accuracy (0-1)';


--
-- Name: COLUMN trees.height_confidence; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.height_confidence IS 'Confidence in height measurement (0-1)';


--
-- Name: COLUMN trees.status_change_date; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.status_change_date IS 'Date when tree status changed (e.g., mortality date)';


--
-- Name: COLUMN trees.tree_number; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.tree_number IS 'Local tree identifier within the location/plot (e.g., 62 in ecosense plot 4, or 367 in mathisle)';


--
-- Name: COLUMN trees.height_class_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.height_class_id IS 'Phanerophyte height classification';


--
-- Name: COLUMN trees.crown_architecture_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.crown_architecture_id IS 'Crown architecture type (excurrent, decurrent, etc.)';


--
-- Name: COLUMN trees.elongation_habit_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.elongation_habit_id IS 'Branch elongation pattern (acrotony, mesotony, basitony)';


--
-- Name: COLUMN trees.growth_orientation_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.growth_orientation_id IS 'Predominant growth orientation (orthotropic/plagiotrophic)';


--
-- Name: COLUMN trees.shoot_elongation_type_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.shoot_elongation_type_id IS 'Typical shoot elongation type';


--
-- Name: COLUMN trees.crown_shape_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.crown_shape_id IS 'Observed crown shape';


--
-- Name: COLUMN trees.geometric_solid_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.geometric_solid_id IS 'Geometric model for crown volume/drag calculations';


--
-- Name: COLUMN trees.axis_structure_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.axis_structure_id IS 'Main axis structure (single leader/polycormic)';


--
-- Name: COLUMN trees.growth_form_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.growth_form_id IS 'General growth form classification';


--
-- Name: COLUMN trees.live_crown_ratio; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.live_crown_ratio IS 'Computed ratio of live crown height to total tree height';


--
-- Name: COLUMN trees.crown_class_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.crown_class_id IS 'Crown competitive/social position (dominant/co_dominant/intermediate/overtopped/open_grown)';


--
-- Name: COLUMN trees.damage_agent_id; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.damage_agent_id IS 'Primary agent responsible for observed damage or decline, if any';


--
-- Name: COLUMN trees.defoliation_percent; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.defoliation_percent IS 'ICP Forests-style defoliation assessment (0-100%, in 5% steps by convention)';


--
-- Name: COLUMN trees.discolouration_percent; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.discolouration_percent IS 'ICP Forests-style foliage discolouration assessment (0-100%)';


--
-- Name: COLUMN trees.crown_transparency_percent; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.crown_transparency_percent IS 'ICP Forests-style crown transparency assessment (0-100%)';


--
-- Name: COLUMN trees.sensor_ref; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.trees.sensor_ref IS 'Source-agnostic reference identifying the sensor cluster installed on this tree. Matches the prefix of sensor.sensors.serial_number, so all of a tree''s sensors resolve from it. For the current Ecosense data this value is the external provider''s name prefix (e.g. Beech_Mixed_8), but the column carries no provider semantics. NULL for non-instrumented trees.';


--
-- Name: silva_input; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.silva_input AS
 SELECT t.location_id AS bid,
    COALESCE(t.plot_id, t.location_id) AS bid2,
    COALESCE(t.tree_number, t.tree_id) AS nr,
        CASE sp.scientific_name
            WHEN 'Picea abies'::text THEN 1
            WHEN 'Abies alba'::text THEN 2
            WHEN 'Pinus sylvestris'::text THEN 3
            WHEN 'Pseudotsuga menziesii'::text THEN 4
            WHEN 'Larix decidua'::text THEN 5
            WHEN 'Fagus sylvatica'::text THEN 11
            WHEN 'Quercus robur'::text THEN 15
            WHEN 'Quercus petraea'::text THEN 16
            WHEN 'Betula pendula'::text THEN 20
            WHEN 'Betula pubescens'::text THEN 21
            WHEN 'Fraxinus excelsior'::text THEN 22
            WHEN 'Acer pseudoplatanus'::text THEN 24
            WHEN 'Acer platanoides'::text THEN 24
            WHEN 'Tilia cordata'::text THEN 25
            WHEN 'Prunus avium'::text THEN 30
            WHEN 'Torminalis glaberrima'::text THEN 33
            ELSE NULL::integer
        END AS ba,
    round(((extensions.st_x(extensions.st_transform(t."position", 32632)) - extensions.st_x(extensions.st_transform(l.center_point, 32632))))::numeric, 2) AS x,
    round(((extensions.st_y(extensions.st_transform(t."position", 32632)) - extensions.st_y(extensions.st_transform(l.center_point, 32632))))::numeric, 2) AS y,
    t.height_m AS h,
    st.dbh_cm AS d,
    t.crown_base_height_m AS hkb,
    t.crown_width_m AS kb,
    t.age_years AS age,
    (EXTRACT(year FROM t.measurement_date))::integer AS base_year,
    l.elevation_m,
    l.slope_deg,
    l.aspect,
    t.tree_entity_id,
    t.tree_id AS base_tree_id,
    t.scenario_id,
    sc.scenario_name,
    t.location_id,
    t.plot_id,
    t.species_id,
    sp.common_name AS species_common,
    sp.scientific_name AS species_sci,
    t.health_score
   FROM (((((trees.trees t
     LEFT JOIN shared.locations l ON ((t.location_id = l.location_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)))
     LEFT JOIN shared.scenarios sc ON ((t.scenario_id = sc.scenario_id)))
     LEFT JOIN trees.stems st ON (((st.tree_id = t.tree_id) AND (st.stem_number = 1))))
     LEFT JOIN trees.datasourcetypes dst ON ((t.data_source_type_id = dst.data_source_type_id)))
  WHERE (((dst.data_source_type_name)::text = ANY ((ARRAY['field'::character varying, 'lidar'::character varying, 'photogrammetry'::character varying])::text[])) AND (t.height_m IS NOT NULL) AND (l.center_point IS NOT NULL) AND (NOT (t.variant_type_id IN ( SELECT varianttypes.variant_type_id
           FROM shared.varianttypes
          WHERE ((varianttypes.variant_type_name)::text = ANY ((ARRAY['simulated_growth'::character varying, 'model_output'::character varying, 'sensor_derived'::character varying])::text[]))))));


--
-- Name: VIEW silva_input; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.silva_input IS 'DRAFT: SILVA 4.5 single-tree input view. Filter by scenario_name + location_name before passing to R. Positions are in metres relative to location center_point (UTM 32N). Verify ba codes and column names against the Freiburg R implementation (XRFF-244).';


--
-- Name: simulation_runs; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.simulation_runs AS
 SELECT gs.run_id,
    gs.simulator_name,
    gs.simulator_version,
    s.scenario_name,
    l.location_name,
    min(gs.projection_year) AS first_year,
    max(gs.projection_year) AS last_year,
    count(DISTINCT gs.projection_year) AS year_steps,
    count(DISTINCT gs.tree_entity_id) AS tree_count,
    max(gs.created_at) AS created_at,
    max((gs.created_by)::text) AS created_by
   FROM ((trees.growthsimulations gs
     LEFT JOIN shared.scenarios s ON ((gs.scenario_id = s.scenario_id)))
     LEFT JOIN shared.locations l ON ((gs.location_id = l.location_id)))
  GROUP BY gs.run_id, gs.simulator_name, gs.simulator_version, s.scenario_name, l.location_name;


--
-- Name: VIEW simulation_runs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.simulation_runs IS 'Summary of each simulation run: simulator, scenario, year range, tree count. Use to populate a run selector UI before querying growth_simulations.';


--
-- Name: species; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.species WITH (security_invoker='on') AS
 SELECT species.species_id,
    species.common_name,
    species.scientific_name,
    species.max_height_m,
    species.max_dbh_cm,
    species.typical_lifespan_years,
    species.growth_rate,
    species.shade_tolerance,
    species.is_deciduous,
    species.gbif_key,
    species.gbif_accepted_name,
    species.created_at,
    species.updated_at
   FROM shared.species;


--
-- Name: VIEW species; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.species IS 'Public API view for tree species reference table';


--
-- Name: stems; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.stems WITH (security_invoker='on') AS
 SELECT stems.stem_id,
    stems.tree_id,
    stems.stem_number,
    stems.taper_type_id,
    stems.straightness_type_id,
    stems.dbh_cm,
    stems.taper_ratio,
    stems.sweep_cm_per_m,
    stems.stem_height_m,
    stems.stem_volume_m3,
    stems.bark_thickness_mm,
    stems.wood_density_kg_m3,
    stems.created_at,
    stems.updated_at
   FROM trees.stems;


--
-- Name: VIEW stems; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.stems IS 'Public API view for tree stems table';


--
-- Name: trees; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trees WITH (security_invoker='on') AS
 SELECT trees.tree_id,
    trees.tree_entity_id,
    trees.variant_id,
    trees.parent_tree_id,
    trees.point_cloud_id,
    trees.campaign_id,
    trees.location_id,
    trees.plot_id,
    trees.scenario_id,
    trees.variant_type_id,
    trees.process_id,
    trees.species_id,
    trees.tree_status_id,
    trees.branching_pattern_id,
    trees.bark_characteristic_id,
    trees.measurement_date,
    trees.data_source_type_id,
    trees.height_m,
    trees.height_source,
    trees.crown_width_m,
    trees.crown_base_height_m,
    trees.crown_boundary,
    trees.crown_offset_x_m,
    trees.crown_offset_y_m,
    trees.volume_m3,
    trees."position",
    trees.position_original,
    trees.source_crs,
    trees.lean_angle_deg,
    trees.lean_direction_azimuth,
    trees.time_delta_yrs,
    trees.age_years,
    trees.health_score,
    trees.biomass_kg,
    trees.carbon_content_kg,
    trees.species_confidence,
    trees.position_confidence,
    trees.height_confidence,
    trees.status_change_date,
    trees.tree_number,
    trees.field_notes,
    trees.created_at,
    trees.updated_at,
    trees.created_by,
    trees.updated_by,
    trees.height_class_id,
    trees.crown_architecture_id,
    trees.elongation_habit_id,
    trees.growth_orientation_id,
    trees.shoot_elongation_type_id,
    trees.crown_shape_id,
    trees.geometric_solid_id,
    trees.axis_structure_id,
    trees.growth_form_id,
    trees.live_crown_ratio,
    trees.crown_class_id,
    trees.damage_agent_id,
    trees.defoliation_percent,
    trees.discolouration_percent,
    trees.crown_transparency_percent
   FROM trees.trees;


--
-- Name: VIEW trees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.trees IS 'Public API view for trees table';


--
-- Name: ue_sensorreadings; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ue_sensorreadings WITH (security_invoker='on') AS
 SELECT sr.sensor_reading_id,
    sr.sensor_id,
    st.sensor_type_name AS sensor_type,
    s.unit,
    sr."timestamp",
    sr.value,
    sr.quality
   FROM ((sensor.sensorreadings sr
     JOIN sensor.sensors s ON ((sr.sensor_id = s.sensor_id)))
     JOIN sensor.sensortypes st ON ((s.sensor_type_id = st.sensor_type_id)));


--
-- Name: VIEW ue_sensorreadings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.ue_sensorreadings IS 'Enriched sensor time-series for UE Blueprint. Includes sensor type and unit, keyed by sensor_id. Look up the linked tree once via ue_sensors, not per reading. GET /ue_sensorreadings?sensor_id=eq.<id>&order=timestamp.desc&limit=96';


--
-- Name: ue_sensors; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ue_sensors WITH (security_invoker='on') AS
 SELECT s.sensor_id,
    s.source,
    s.external_id,
    s.serial_number AS sensor_label,
    (s.external_metadata ->> 'Parameter'::text) AS parameter,
    st.sensor_type_id,
    st.sensor_type_name AS sensor_type,
    s.unit,
    s.sensor_model,
    (s.external_metadata ->> 'DataOwner'::text) AS data_owner,
    s.is_active,
    s.installation_height_m,
    s.sampling_interval_seconds,
    s.installation_date,
    l.location_id,
    l.location_name,
    s.plot_id,
    p.plot_name,
    lr."timestamp" AS latest_timestamp,
    lr.value AS latest_value,
    lr.quality AS latest_quality,
    t.tree_id AS linked_tree_id,
    t.tree_entity_id AS linked_tree_entity_id,
    sp.common_name AS linked_tree_species,
    sp.scientific_name AS linked_tree_scientificname,
    t.height_m AS linked_tree_height_m,
    extensions.st_y(s."position") AS latitude,
    extensions.st_x(s."position") AS longitude
   FROM (((((((sensor.sensors s
     JOIN sensor.sensortypes st ON ((s.sensor_type_id = st.sensor_type_id)))
     JOIN shared.locations l ON ((s.location_id = l.location_id)))
     LEFT JOIN shared.plots p ON ((s.plot_id = p.plot_id)))
     LEFT JOIN LATERAL ( SELECT sr."timestamp",
            sr.value,
            sr.quality
           FROM sensor.sensorreadings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) lr ON (true))
     LEFT JOIN sensor.sensor_tree_links stl ON ((stl.sensor_id = s.sensor_id)))
     LEFT JOIN trees.trees t ON ((stl.tree_id = t.tree_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)));


--
-- Name: VIEW ue_sensors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.ue_sensors IS 'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model (enriched instrument), data owner, location, latest reading, and linked tree info (populated after sensor_tree_links is filled). GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>';


--
-- Name: variants; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.variants (
    variant_id integer NOT NULL,
    location_id integer NOT NULL,
    scenario_id integer NOT NULL,
    variant_type_id integer NOT NULL,
    variant_name character varying(200) NOT NULL,
    simulation_year integer,
    time_delta_yrs numeric(8,2),
    sort_order integer DEFAULT 0 NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now(),
    parent_variant_id integer,
    CONSTRAINT variants_simulation_year_check CHECK (((simulation_year >= 1900) AND (simulation_year <= 2300))),
    CONSTRAINT variants_time_delta_yrs_check CHECK ((time_delta_yrs >= (0)::numeric))
);


--
-- Name: TABLE variants; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.variants IS 'Forest state snapshots — each row is one time step at one location within one scenario. variant_id groups all trees at that state. Use for UE time-travel switching.';


--
-- Name: COLUMN variants.location_id; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.variants.location_id IS 'The forest site this variant belongs to — top level of the Location → Scenario → Variant hierarchy';


--
-- Name: COLUMN variants.scenario_id; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.variants.scenario_id IS 'The scenario (set of assumptions) this variant belongs to';


--
-- Name: COLUMN variants.variant_type_id; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.variants.variant_type_id IS 'Type of data in this variant (original field measurement, simulated growth, etc.)';


--
-- Name: COLUMN variants.simulation_year; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.variants.simulation_year IS 'Calendar year this forest state represents';


--
-- Name: COLUMN variants.time_delta_yrs; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.variants.time_delta_yrs IS 'Years elapsed from the scenario baseline';


--
-- Name: COLUMN variants.sort_order; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.variants.sort_order IS 'Display order for time-slider UI in UE (0=earliest)';


--
-- Name: COLUMN variants.parent_variant_id; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.variants.parent_variant_id IS 'The variant this state developed from (baseline has none). Encodes the timeline/intervention lineage within a scenario.';


--
-- Name: ue_trees; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ue_trees AS
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
    COALESCE(((t.crown_base_height_m / NULLIF(t.height_m, (0)::numeric)) > 0.6), false) AS competition,
    t.sensor_ref,
    (EXISTS ( SELECT 1
           FROM sensor.sensor_tree_links stl
          WHERE (stl.tree_id = t.tree_id))) AS has_sensors,
    extensions.st_x(t.position_original) AS original_x,
    extensions.st_y(t.position_original) AS original_y,
    t.source_crs,
    extensions.st_y(t."position") AS latitude,
    extensions.st_x(t."position") AS longitude
   FROM ((((((trees.trees t
     LEFT JOIN shared.locations l ON ((t.location_id = l.location_id)))
     LEFT JOIN shared.variants v ON ((t.variant_id = v.variant_id)))
     LEFT JOIN shared.scenarios s ON ((v.scenario_id = s.scenario_id)))
     LEFT JOIN shared.varianttypes vt ON ((v.variant_type_id = vt.variant_type_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)))
     LEFT JOIN trees.stems st ON (((st.tree_id = t.tree_id) AND (st.stem_number = 1))));


--
-- Name: VIEW ue_trees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.ue_trees IS 'Flat tree catalogue for UE Blueprint import. One row per tree with the location/scenario/variant hierarchy (id + name at each level), species, main-stem DBH, competition flag, sensor cross-reference (sensor_ref + has_sensors), projected source coordinates (original_x/original_y in source_crs, EPSG:32632/UTM 32N — preferred for UE placement) and flattened latitude/longitude. Filter by variant_id to load one time step. For a tree''s sensors: GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>.';


--
-- Name: variants; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.variants AS
 SELECT v.variant_id,
    v.location_id,
    v.scenario_id,
    v.variant_type_id,
    v.variant_name,
    v.simulation_year,
    v.time_delta_yrs,
    v.sort_order,
    v.description,
    v.created_at,
    v.parent_variant_id,
    l.location_name,
    s.scenario_name,
    vt.variant_type_name
   FROM (((shared.variants v
     LEFT JOIN shared.locations l ON ((v.location_id = l.location_id)))
     LEFT JOIN shared.scenarios s ON ((v.scenario_id = s.scenario_id)))
     LEFT JOIN shared.varianttypes vt ON ((v.variant_type_id = vt.variant_type_id)));


--
-- Name: VIEW variants; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.variants IS 'Forest-state variants with location/scenario/type names and parent_variant_id lineage joined. Filter by location_id+scenario_id for a site+scenario timeline.';


--
-- Name: varianttypes; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.varianttypes AS
 SELECT varianttypes.variant_type_id,
    varianttypes.variant_type_name,
    varianttypes.description
   FROM shared.varianttypes;


--
-- Name: VIEW varianttypes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.varianttypes IS 'Public API view for data variant type classifications';


--
-- Name: active_sensors_status; Type: VIEW; Schema: sensor; Owner: -
--

CREATE VIEW sensor.active_sensors_status AS
 SELECT s.sensor_id,
    s.location_id,
    st.sensor_type_name,
    s.sensor_model,
    s.is_active,
    s.battery_level_percent,
    ( SELECT sr."timestamp"
           FROM sensor.sensorreadings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) AS last_reading_time,
    ( SELECT sr.value
           FROM sensor.sensorreadings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) AS last_reading_value,
    ( SELECT sr.quality
           FROM sensor.sensorreadings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) AS last_reading_quality
   FROM (sensor.sensors s
     JOIN sensor.sensortypes st ON ((s.sensor_type_id = st.sensor_type_id)))
  WHERE (s.is_active = true);


--
-- Name: VIEW active_sensors_status; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON VIEW sensor.active_sensors_status IS 'Active sensors with their latest reading information';


--
-- Name: sensor_tree_links_sensortreelinkid_seq; Type: SEQUENCE; Schema: sensor; Owner: -
--

CREATE SEQUENCE sensor.sensor_tree_links_sensortreelinkid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensor_tree_links_sensortreelinkid_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: -
--

ALTER SEQUENCE sensor.sensor_tree_links_sensortreelinkid_seq OWNED BY sensor.sensor_tree_links.sensortreelinkid;


--
-- Name: sensor_tree_view; Type: VIEW; Schema: sensor; Owner: -
--

CREATE VIEW sensor.sensor_tree_view AS
 SELECT s.sensor_id,
    s.serial_number AS sensor_name,
    st.sensor_type_name AS sensor_type,
    s.unit AS sensor_unit,
    s.is_active AS sensor_active,
    stl.description AS link_description,
    stl.created_at AS link_created_at,
    t.tree_id,
    sp.common_name AS tree_species,
    t.height_m AS tree_height_m,
    "substring"(t.field_notes, 'tree_id: [^|]+'::text) AS tree_identifier,
    "substring"(t.field_notes, 'FID: [0-9]+'::text) AS tree_fid,
    l.location_name AS tree_location,
    extensions.st_x(t."position") AS tree_longitude,
    extensions.st_y(t."position") AS tree_latitude
   FROM (((((sensor.sensor_tree_links stl
     JOIN sensor.sensors s ON ((stl.sensor_id = s.sensor_id)))
     JOIN sensor.sensortypes st ON ((s.sensor_type_id = st.sensor_type_id)))
     LEFT JOIN trees.trees t ON ((stl.tree_id = t.tree_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)))
     LEFT JOIN shared.locations l ON ((t.location_id = l.location_id)));


--
-- Name: VIEW sensor_tree_view; Type: COMMENT; Schema: sensor; Owner: -
--

COMMENT ON VIEW sensor.sensor_tree_view IS 'View showing relationships between sensors and trees with detailed information';


--
-- Name: sensorreadings_sensor_reading_id_seq; Type: SEQUENCE; Schema: sensor; Owner: -
--

CREATE SEQUENCE sensor.sensorreadings_sensor_reading_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensorreadings_sensor_reading_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: -
--

ALTER SEQUENCE sensor.sensorreadings_sensor_reading_id_seq OWNED BY sensor.sensorreadings.sensor_reading_id;


--
-- Name: sensors_sensor_id_seq; Type: SEQUENCE; Schema: sensor; Owner: -
--

CREATE SEQUENCE sensor.sensors_sensor_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensors_sensor_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: -
--

ALTER SEQUENCE sensor.sensors_sensor_id_seq OWNED BY sensor.sensors.sensor_id;


--
-- Name: sensortypes_sensor_type_id_seq; Type: SEQUENCE; Schema: sensor; Owner: -
--

CREATE SEQUENCE sensor.sensortypes_sensor_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sensortypes_sensor_type_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: -
--

ALTER SEQUENCE sensor.sensortypes_sensor_type_id_seq OWNED BY sensor.sensortypes.sensor_type_id;


--
-- Name: auditlog; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.auditlog (
    audit_id bigint NOT NULL,
    field_name character varying(200) NOT NULL,
    old_value text,
    new_value text,
    change_reason text,
    user_id character varying(200),
    "timestamp" timestamp with time zone DEFAULT now(),
    change_type character varying(50),
    ip_address inet,
    user_agent text,
    CONSTRAINT auditlog_change_type_check CHECK (((change_type)::text = ANY ((ARRAY['field_update'::character varying, 'bulk_update'::character varying, 'revert'::character varying, 'insert'::character varying, 'delete'::character varying])::text[])))
);


--
-- Name: TABLE auditlog; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.auditlog IS 'Field-level change tracking with user attribution (linked via junction tables)';


--
-- Name: COLUMN auditlog.field_name; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.auditlog.field_name IS 'Name of the field that was changed';


--
-- Name: COLUMN auditlog.old_value; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.auditlog.old_value IS 'Previous value (stored as JSON text)';


--
-- Name: COLUMN auditlog.new_value; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.auditlog.new_value IS 'New value (stored as JSON text)';


--
-- Name: auditlog_audit_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.auditlog_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditlog_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.auditlog_audit_id_seq OWNED BY shared.auditlog.audit_id;


--
-- Name: auditlog_environments; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.auditlog_environments (
    audit_id bigint NOT NULL,
    environment_id integer NOT NULL
);


--
-- Name: TABLE auditlog_environments; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.auditlog_environments IS 'Links audit log entries to environment records';


--
-- Name: auditlog_pointclouds; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.auditlog_pointclouds (
    audit_id bigint NOT NULL,
    point_cloud_id integer NOT NULL
);


--
-- Name: TABLE auditlog_pointclouds; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.auditlog_pointclouds IS 'Links audit log entries to point cloud records';


--
-- Name: auditlog_stems; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.auditlog_stems (
    audit_id bigint NOT NULL,
    stem_id integer NOT NULL
);


--
-- Name: TABLE auditlog_stems; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.auditlog_stems IS 'Links audit log entries to individual stems';


--
-- Name: auditlog_trees; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.auditlog_trees (
    audit_id bigint NOT NULL,
    tree_id integer NOT NULL
);


--
-- Name: TABLE auditlog_trees; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.auditlog_trees IS 'Links audit log entries to tree records';


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.campaigns_campaign_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.campaigns_campaign_id_seq OWNED BY shared.campaigns.campaign_id;


--
-- Name: climatezones; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.climatezones (
    climate_zone_id integer NOT NULL,
    climate_zone_name character varying(10) NOT NULL,
    description text,
    CONSTRAINT chk_climate_zone_format CHECK (((climate_zone_name)::text ~ '^[A-Z][A-Za-z]{0,3}$'::text))
);


--
-- Name: TABLE climatezones; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.climatezones IS 'Köppen climate classification zones';


--
-- Name: COLUMN climatezones.climate_zone_name; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.climatezones.climate_zone_name IS 'Köppen climate classification code (e.g., Cfb, Dfb, ET, EF, BWh)';


--
-- Name: climatezones_climate_zone_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.climatezones_climate_zone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: climatezones_climate_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.climatezones_climate_zone_id_seq OWNED BY shared.climatezones.climate_zone_id;


--
-- Name: disturbanceevents_disturbance_event_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.disturbanceevents_disturbance_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: disturbanceevents_disturbance_event_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.disturbanceevents_disturbance_event_id_seq OWNED BY shared.disturbanceevents.disturbance_event_id;


--
-- Name: disturbanceevents_trees; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.disturbanceevents_trees (
    disturbance_event_id integer NOT NULL,
    tree_id integer NOT NULL,
    damage_level character varying(50),
    notes text,
    CONSTRAINT disturbanceevents_trees_damage_level_check CHECK (((damage_level)::text = ANY ((ARRAY['none'::character varying, 'light'::character varying, 'moderate'::character varying, 'severe'::character varying, 'destroyed'::character varying])::text[])))
);


--
-- Name: TABLE disturbanceevents_trees; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.disturbanceevents_trees IS 'Links disturbance events to affected individual trees with damage assessment';


--
-- Name: COLUMN disturbanceevents_trees.damage_level; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.disturbanceevents_trees.damage_level IS 'Level of damage to individual tree';


--
-- Name: locations_location_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.locations_location_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: locations_location_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.locations_location_id_seq OWNED BY shared.locations.location_id;


--
-- Name: managementevents_management_event_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.managementevents_management_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: managementevents_management_event_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.managementevents_management_event_id_seq OWNED BY shared.managementevents.management_event_id;


--
-- Name: plots_plot_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.plots_plot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plots_plot_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.plots_plot_id_seq OWNED BY shared.plots.plot_id;


--
-- Name: processes; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processes (
    process_id integer NOT NULL,
    process_name character varying(200) NOT NULL,
    algorithm_name character varying(200),
    version character varying(50),
    description text,
    author character varying(200),
    publication_date date,
    citation text,
    category character varying(100),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT processes_category_check CHECK (((category)::text = ANY ((ARRAY['detection'::character varying, 'classification'::character varying, 'simulation'::character varying, 'analysis'::character varying, 'aggregation'::character varying])::text[])))
);


--
-- Name: TABLE processes; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processes IS 'Processing algorithms and methods with versioning and academic attribution';


--
-- Name: COLUMN processes.process_name; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.processes.process_name IS 'Process name (e.g., LiDAR_Segmentation, Tree_Detection, Growth_Simulation)';


--
-- Name: COLUMN processes.algorithm_name; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.processes.algorithm_name IS 'Algorithm used (e.g., RandomForest, DeepLearning, RulesBased)';


--
-- Name: processes_process_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.processes_process_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: processes_process_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.processes_process_id_seq OWNED BY shared.processes.process_id;


--
-- Name: processingjobs; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processingjobs (
    processing_job_id integer NOT NULL,
    external_job_id character varying(200),
    workflow_name character varying(200) NOT NULL,
    workflow_version character varying(50),
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    submitted_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    input_data jsonb,
    output_data jsonb,
    error_message text,
    submitted_by character varying(200),
    CONSTRAINT chk_completed_date CHECK (((completed_at IS NULL) OR (completed_at >= submitted_at))),
    CONSTRAINT processingjobs_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: TABLE processingjobs; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processingjobs IS 'Tracks external processing jobs and compute workflows';


--
-- Name: COLUMN processingjobs.external_job_id; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.processingjobs.external_job_id IS 'Unique identifier from external processing system';


--
-- Name: COLUMN processingjobs.status; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.processingjobs.status IS 'Job status: pending, running, completed, failed';


--
-- Name: COLUMN processingjobs.input_data; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.processingjobs.input_data IS 'JSON representation of input parameters and data references';


--
-- Name: COLUMN processingjobs.output_data; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.processingjobs.output_data IS 'JSON representation of output data references and results';


--
-- Name: processingjobs_processing_job_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.processingjobs_processing_job_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: processingjobs_processing_job_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.processingjobs_processing_job_id_seq OWNED BY shared.processingjobs.processing_job_id;


--
-- Name: processmetrics; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processmetrics (
    process_metric_id integer NOT NULL,
    process_id integer NOT NULL,
    metric_name character varying(200) NOT NULL,
    metric_value numeric(10,6),
    source text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT chk_metric_name CHECK (((metric_name)::text = ANY ((ARRAY['accuracy'::character varying, 'precision'::character varying, 'recall'::character varying, 'f1_score'::character varying, 'rmse'::character varying, 'mae'::character varying, 'r_squared'::character varying])::text[])))
);


--
-- Name: TABLE processmetrics; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processmetrics IS 'Published performance metrics for processes';


--
-- Name: processmetrics_process_metric_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.processmetrics_process_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: processmetrics_process_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.processmetrics_process_metric_id_seq OWNED BY shared.processmetrics.process_metric_id;


--
-- Name: processparameters; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processparameters (
    process_parameter_id integer NOT NULL,
    parameter_name character varying(200) NOT NULL,
    parameter_value text NOT NULL,
    data_type character varying(50),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT processparameters_data_type_check CHECK (((data_type)::text = ANY ((ARRAY['float'::character varying, 'int'::character varying, 'string'::character varying, 'boolean'::character varying, 'json'::character varying])::text[])))
);


--
-- Name: TABLE processparameters; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processparameters IS 'Process parameters used for variants (linked via junction tables)';


--
-- Name: COLUMN processparameters.parameter_value; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.processparameters.parameter_value IS 'Parameter value as text (cast based on data_type)';


--
-- Name: processparameters_environments; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processparameters_environments (
    process_parameter_id integer NOT NULL,
    environment_id integer NOT NULL
);


--
-- Name: TABLE processparameters_environments; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processparameters_environments IS 'Links process parameters to environment records';


--
-- Name: processparameters_pointclouds; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processparameters_pointclouds (
    process_parameter_id integer NOT NULL,
    point_cloud_id integer NOT NULL
);


--
-- Name: TABLE processparameters_pointclouds; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processparameters_pointclouds IS 'Links process parameters to point cloud records';


--
-- Name: processparameters_process_parameter_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.processparameters_process_parameter_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: processparameters_process_parameter_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.processparameters_process_parameter_id_seq OWNED BY shared.processparameters.process_parameter_id;


--
-- Name: processparameters_stems; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processparameters_stems (
    process_parameter_id integer NOT NULL,
    stem_id integer NOT NULL
);


--
-- Name: TABLE processparameters_stems; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processparameters_stems IS 'Links process parameters to individual stems';


--
-- Name: processparameters_trees; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.processparameters_trees (
    process_parameter_id integer NOT NULL,
    tree_id integer NOT NULL
);


--
-- Name: TABLE processparameters_trees; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.processparameters_trees IS 'Links process parameters to tree records';


--
-- Name: recent_changes; Type: VIEW; Schema: shared; Owner: -
--

CREATE VIEW shared.recent_changes AS
 SELECT al.audit_id,
    COALESCE(
        CASE
            WHEN (alpc.point_cloud_id IS NOT NULL) THEN 'PointClouds'::text
            WHEN (alt.tree_id IS NOT NULL) THEN 'Trees'::text
            WHEN (ale.environment_id IS NOT NULL) THEN 'Environments'::text
            WHEN (als.stem_id IS NOT NULL) THEN 'Stems'::text
            ELSE NULL::text
        END) AS table_name,
    COALESCE(alpc.point_cloud_id, alt.tree_id, ale.environment_id, als.stem_id) AS record_id,
    al.field_name,
    al.old_value,
    al.new_value,
    al.change_type,
    al.user_id,
    al."timestamp",
    al.change_reason
   FROM ((((shared.auditlog al
     LEFT JOIN shared.auditlog_pointclouds alpc ON ((al.audit_id = alpc.audit_id)))
     LEFT JOIN shared.auditlog_trees alt ON ((al.audit_id = alt.audit_id)))
     LEFT JOIN shared.auditlog_environments ale ON ((al.audit_id = ale.audit_id)))
     LEFT JOIN shared.auditlog_stems als ON ((al.audit_id = als.audit_id)))
  ORDER BY al."timestamp" DESC;


--
-- Name: VIEW recent_changes; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON VIEW shared.recent_changes IS 'Unified view of recent changes across all audited tables';


--
-- Name: scenarios_scenario_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.scenarios_scenario_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scenarios_scenario_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.scenarios_scenario_id_seq OWNED BY shared.scenarios.scenario_id;


--
-- Name: soiltypes; Type: TABLE; Schema: shared; Owner: -
--

CREATE TABLE shared.soiltypes (
    soil_type_id integer NOT NULL,
    soil_type_name character varying(100) NOT NULL,
    description text,
    CONSTRAINT chk_soil_type_name CHECK (((soil_type_name)::text = ANY ((ARRAY['Alfisol'::character varying, 'Andisol'::character varying, 'Aridisol'::character varying, 'Entisol'::character varying, 'Gelisol'::character varying, 'Histosol'::character varying, 'Inceptisol'::character varying, 'Mollisol'::character varying, 'Oxisol'::character varying, 'Spodosol'::character varying, 'Ultisol'::character varying, 'Vertisol'::character varying])::text[])))
);


--
-- Name: TABLE soiltypes; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON TABLE shared.soiltypes IS 'USDA soil classification reference table';


--
-- Name: COLUMN soiltypes.soil_type_name; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON COLUMN shared.soiltypes.soil_type_name IS 'USDA soil classification type';


--
-- Name: soiltypes_soil_type_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.soiltypes_soil_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: soiltypes_soil_type_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.soiltypes_soil_type_id_seq OWNED BY shared.soiltypes.soil_type_id;


--
-- Name: species_species_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.species_species_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: species_species_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.species_species_id_seq OWNED BY shared.species.species_id;


--
-- Name: user_activity_summary; Type: VIEW; Schema: shared; Owner: -
--

CREATE VIEW shared.user_activity_summary AS
 SELECT auditlog.user_id,
    count(*) AS total_changes,
    count(DISTINCT date(auditlog."timestamp")) AS active_days,
    min(auditlog."timestamp") AS first_change,
    max(auditlog."timestamp") AS last_change,
    count(*) FILTER (WHERE ((auditlog.change_type)::text = 'field_update'::text)) AS field_updates,
    count(*) FILTER (WHERE ((auditlog.change_type)::text = 'bulk_update'::text)) AS bulk_updates,
    count(*) FILTER (WHERE ((auditlog.change_type)::text = 'revert'::text)) AS reverts
   FROM shared.auditlog
  GROUP BY auditlog.user_id;


--
-- Name: VIEW user_activity_summary; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON VIEW shared.user_activity_summary IS 'Summary of user activity and change patterns';


--
-- Name: variants_variant_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.variants_variant_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: variants_variant_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.variants_variant_id_seq OWNED BY shared.variants.variant_id;


--
-- Name: varianttypes_variant_type_id_seq; Type: SEQUENCE; Schema: shared; Owner: -
--

CREATE SEQUENCE shared.varianttypes_variant_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: varianttypes_variant_type_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: -
--

ALTER SEQUENCE shared.varianttypes_variant_type_id_seq OWNED BY shared.varianttypes.variant_type_id;


--
-- Name: axisstructures_axis_structure_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.axisstructures_axis_structure_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: axisstructures_axis_structure_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.axisstructures_axis_structure_id_seq OWNED BY trees.axisstructures.axis_structure_id;


--
-- Name: barkcharacteristics; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.barkcharacteristics (
    bark_characteristic_id integer NOT NULL,
    bark_characteristic_name character varying(100) NOT NULL,
    description text,
    typical_species text
);


--
-- Name: TABLE barkcharacteristics; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.barkcharacteristics IS 'Bark texture and appearance classifications';


--
-- Name: barkcharacteristics_bark_characteristic_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.barkcharacteristics_bark_characteristic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: barkcharacteristics_bark_characteristic_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.barkcharacteristics_bark_characteristic_id_seq OWNED BY trees.barkcharacteristics.bark_characteristic_id;


--
-- Name: branchelongationhabits_branch_elongation_habit_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.branchelongationhabits_branch_elongation_habit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: branchelongationhabits_branch_elongation_habit_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.branchelongationhabits_branch_elongation_habit_id_seq OWNED BY trees.branchelongationhabits.branch_elongation_habit_id;


--
-- Name: branchingpatterns; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.branchingpatterns (
    branching_pattern_id integer NOT NULL,
    branching_pattern_name character varying(100) NOT NULL,
    description text
);


--
-- Name: TABLE branchingpatterns; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.branchingpatterns IS 'Branch arrangement patterns on stems';


--
-- Name: branchingpatterns_branching_pattern_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.branchingpatterns_branching_pattern_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: branchingpatterns_branching_pattern_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.branchingpatterns_branching_pattern_id_seq OWNED BY trees.branchingpatterns.branching_pattern_id;


--
-- Name: crownarchitectures_crown_architecture_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.crownarchitectures_crown_architecture_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: crownarchitectures_crown_architecture_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.crownarchitectures_crown_architecture_id_seq OWNED BY trees.crownarchitectures.crown_architecture_id;


--
-- Name: crownclasses_crown_class_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.crownclasses_crown_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: crownclasses_crown_class_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.crownclasses_crown_class_id_seq OWNED BY trees.crownclasses.crown_class_id;


--
-- Name: crownshapes_crown_shape_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.crownshapes_crown_shape_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: crownshapes_crown_shape_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.crownshapes_crown_shape_id_seq OWNED BY trees.crownshapes.crown_shape_id;


--
-- Name: damageagents_damage_agent_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.damageagents_damage_agent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: damageagents_damage_agent_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.damageagents_damage_agent_id_seq OWNED BY trees.damageagents.damage_agent_id;


--
-- Name: datasourcetypes_data_source_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.datasourcetypes_data_source_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: datasourcetypes_data_source_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.datasourcetypes_data_source_type_id_seq OWNED BY trees.datasourcetypes.data_source_type_id;


--
-- Name: deadwood_deadwood_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.deadwood_deadwood_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deadwood_deadwood_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.deadwood_deadwood_id_seq OWNED BY trees.deadwood.deadwood_id;


--
-- Name: geometriccrownsolids_geometric_solid_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.geometriccrownsolids_geometric_solid_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geometriccrownsolids_geometric_solid_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.geometriccrownsolids_geometric_solid_id_seq OWNED BY trees.geometriccrownsolids.geometric_solid_id;


--
-- Name: groundvegetation_ground_vegetation_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.groundvegetation_ground_vegetation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: groundvegetation_ground_vegetation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.groundvegetation_ground_vegetation_id_seq OWNED BY trees.groundvegetation.ground_vegetation_id;


--
-- Name: growthforms_growth_form_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.growthforms_growth_form_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: growthforms_growth_form_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.growthforms_growth_form_id_seq OWNED BY trees.growthforms.growth_form_id;


--
-- Name: growthorientations_growth_orientation_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.growthorientations_growth_orientation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: growthorientations_growth_orientation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.growthorientations_growth_orientation_id_seq OWNED BY trees.growthorientations.growth_orientation_id;


--
-- Name: growthsimulations_growth_simulation_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.growthsimulations_growth_simulation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: growthsimulations_growth_simulation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.growthsimulations_growth_simulation_id_seq OWNED BY trees.growthsimulations.growth_simulation_id;


--
-- Name: phanerophyteheightclasses_phanerophyte_height_class_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.phanerophyteheightclasses_phanerophyte_height_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: phanerophyteheightclasses_phanerophyte_height_class_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.phanerophyteheightclasses_phanerophyte_height_class_id_seq OWNED BY trees.phanerophyteheightclasses.phanerophyte_height_class_id;


--
-- Name: phenologyobservations_phenology_observation_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.phenologyobservations_phenology_observation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: phenologyobservations_phenology_observation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.phenologyobservations_phenology_observation_id_seq OWNED BY trees.phenologyobservations.phenology_observation_id;


--
-- Name: shootelongationtypes_shoot_elongation_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.shootelongationtypes_shoot_elongation_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: shootelongationtypes_shoot_elongation_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.shootelongationtypes_shoot_elongation_type_id_seq OWNED BY trees.shootelongationtypes.shoot_elongation_type_id;


--
-- Name: stems_stem_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.stems_stem_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stems_stem_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.stems_stem_id_seq OWNED BY trees.stems.stem_id;


--
-- Name: straightnesstypes; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.straightnesstypes (
    straightness_type_id integer NOT NULL,
    straightness_name character varying(100) NOT NULL,
    description text,
    deviation_angle_min numeric(5,2),
    deviation_angle_max numeric(5,2),
    CONSTRAINT chk_deviation_order CHECK ((deviation_angle_min <= deviation_angle_max)),
    CONSTRAINT straightnesstypes_deviation_angle_max_check CHECK (((deviation_angle_max >= (0)::numeric) AND (deviation_angle_max <= (90)::numeric))),
    CONSTRAINT straightnesstypes_deviation_angle_min_check CHECK (((deviation_angle_min >= (0)::numeric) AND (deviation_angle_min <= (90)::numeric)))
);


--
-- Name: TABLE straightnesstypes; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.straightnesstypes IS 'Stem straightness classifications';


--
-- Name: straightnesstypes_straightness_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.straightnesstypes_straightness_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: straightnesstypes_straightness_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.straightnesstypes_straightness_type_id_seq OWNED BY trees.straightnesstypes.straightness_type_id;


--
-- Name: tapertypes; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.tapertypes (
    taper_type_id integer NOT NULL,
    taper_type_name character varying(100) NOT NULL,
    description text,
    typical_taper_ratio_min numeric(4,3),
    typical_taper_ratio_max numeric(4,3),
    CONSTRAINT chk_taper_ratio_order CHECK ((typical_taper_ratio_min <= typical_taper_ratio_max)),
    CONSTRAINT tapertypes_typical_taper_ratio_max_check CHECK (((typical_taper_ratio_max >= (0)::numeric) AND (typical_taper_ratio_max <= (1)::numeric))),
    CONSTRAINT tapertypes_typical_taper_ratio_min_check CHECK (((typical_taper_ratio_min >= (0)::numeric) AND (typical_taper_ratio_min <= (1)::numeric)))
);


--
-- Name: TABLE tapertypes; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.tapertypes IS 'Stem taper form classifications';


--
-- Name: COLUMN tapertypes.typical_taper_ratio_min; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON COLUMN trees.tapertypes.typical_taper_ratio_min IS 'Minimum typical taper ratio (diameter at top / diameter at bottom)';


--
-- Name: tapertypes_taper_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.tapertypes_taper_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tapertypes_taper_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.tapertypes_taper_type_id_seq OWNED BY trees.tapertypes.taper_type_id;


--
-- Name: trees_tree_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.trees_tree_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trees_tree_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.trees_tree_id_seq OWNED BY trees.trees.tree_id;


--
-- Name: trees_with_metrics; Type: VIEW; Schema: trees; Owner: -
--

CREATE VIEW trees.trees_with_metrics AS
SELECT
    NULL::integer AS tree_id,
    NULL::uuid AS tree_entity_id,
    NULL::integer AS variant_id,
    NULL::integer AS parent_tree_id,
    NULL::integer AS point_cloud_id,
    NULL::integer AS campaign_id,
    NULL::integer AS location_id,
    NULL::integer AS plot_id,
    NULL::integer AS scenario_id,
    NULL::integer AS variant_type_id,
    NULL::integer AS process_id,
    NULL::integer AS species_id,
    NULL::integer AS tree_status_id,
    NULL::integer AS branching_pattern_id,
    NULL::integer AS bark_characteristic_id,
    NULL::date AS measurement_date,
    NULL::integer AS data_source_type_id,
    NULL::numeric(6,2) AS height_m,
    NULL::character varying(50) AS height_source,
    NULL::numeric(6,2) AS crown_width_m,
    NULL::numeric(6,2) AS crown_base_height_m,
    NULL::extensions.geometry(Polygon,4326) AS crown_boundary,
    NULL::numeric(5,2) AS crown_offset_x_m,
    NULL::numeric(5,2) AS crown_offset_y_m,
    NULL::numeric(10,3) AS volume_m3,
    NULL::extensions.geometry(Point,4326) AS "position",
    NULL::extensions.geometry AS position_original,
    NULL::integer AS source_crs,
    NULL::numeric(5,2) AS lean_angle_deg,
    NULL::integer AS lean_direction_azimuth,
    NULL::numeric(8,2) AS time_delta_yrs,
    NULL::integer AS age_years,
    NULL::numeric(3,2) AS health_score,
    NULL::numeric(12,2) AS biomass_kg,
    NULL::numeric(12,2) AS carbon_content_kg,
    NULL::numeric(3,2) AS species_confidence,
    NULL::numeric(3,2) AS position_confidence,
    NULL::numeric(3,2) AS height_confidence,
    NULL::date AS status_change_date,
    NULL::integer AS tree_number,
    NULL::text AS field_notes,
    NULL::timestamp with time zone AS created_at,
    NULL::timestamp with time zone AS updated_at,
    NULL::character varying(200) AS created_by,
    NULL::character varying(200) AS updated_by,
    NULL::character varying(200) AS scientific_name,
    NULL::character varying(200) AS common_name,
    NULL::bigint AS stem_count,
    NULL::numeric AS total_basal_area_m2,
    NULL::numeric AS crown_volume_m3;


--
-- Name: VIEW trees_with_metrics; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON VIEW trees.trees_with_metrics IS 'Trees with computed metrics (basal area, crown volume, stem count)';


--
-- Name: treestatus; Type: TABLE; Schema: trees; Owner: -
--

CREATE TABLE trees.treestatus (
    tree_status_id integer NOT NULL,
    tree_status_name character varying(100) NOT NULL,
    description text,
    CONSTRAINT chk_tree_status_name CHECK (((tree_status_name)::text = ANY ((ARRAY['healthy'::character varying, 'stressed'::character varying, 'declining'::character varying, 'dead'::character varying, 'harvested'::character varying, 'missing'::character varying, 'downed'::character varying, 'broken'::character varying])::text[])))
);


--
-- Name: TABLE treestatus; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON TABLE trees.treestatus IS 'Tree health and status classification';


--
-- Name: treestatus_tree_status_id_seq; Type: SEQUENCE; Schema: trees; Owner: -
--

CREATE SEQUENCE trees.treestatus_tree_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: treestatus_tree_status_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: -
--

ALTER SEQUENCE trees.treestatus_tree_status_id_seq OWNED BY trees.treestatus.tree_status_id;


--
-- Name: environments environment_id; Type: DEFAULT; Schema: environments; Owner: -
--

ALTER TABLE ONLY environments.environments ALTER COLUMN environment_id SET DEFAULT nextval('environments.environments_environment_id_seq'::regclass);


--
-- Name: images image_id; Type: DEFAULT; Schema: imagery; Owner: -
--

ALTER TABLE ONLY imagery.images ALTER COLUMN image_id SET DEFAULT nextval('imagery.images_image_id_seq'::regclass);


--
-- Name: pointclouds point_cloud_id; Type: DEFAULT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds ALTER COLUMN point_cloud_id SET DEFAULT nextval('pointclouds.pointclouds_point_cloud_id_seq'::regclass);


--
-- Name: scanners scanner_id; Type: DEFAULT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.scanners ALTER COLUMN scanner_id SET DEFAULT nextval('pointclouds.scanners_scanner_id_seq'::regclass);


--
-- Name: scannertypes scanner_type_id; Type: DEFAULT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.scannertypes ALTER COLUMN scanner_type_id SET DEFAULT nextval('pointclouds.scannertypes_scanner_type_id_seq'::regclass);


--
-- Name: sensor_tree_links sensortreelinkid; Type: DEFAULT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensor_tree_links ALTER COLUMN sensortreelinkid SET DEFAULT nextval('sensor.sensor_tree_links_sensortreelinkid_seq'::regclass);


--
-- Name: sensorreadings sensor_reading_id; Type: DEFAULT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensorreadings ALTER COLUMN sensor_reading_id SET DEFAULT nextval('sensor.sensorreadings_sensor_reading_id_seq'::regclass);


--
-- Name: sensors sensor_id; Type: DEFAULT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensors ALTER COLUMN sensor_id SET DEFAULT nextval('sensor.sensors_sensor_id_seq'::regclass);


--
-- Name: sensortypes sensor_type_id; Type: DEFAULT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensortypes ALTER COLUMN sensor_type_id SET DEFAULT nextval('sensor.sensortypes_sensor_type_id_seq'::regclass);


--
-- Name: auditlog audit_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog ALTER COLUMN audit_id SET DEFAULT nextval('shared.auditlog_audit_id_seq'::regclass);


--
-- Name: campaigns campaign_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.campaigns ALTER COLUMN campaign_id SET DEFAULT nextval('shared.campaigns_campaign_id_seq'::regclass);


--
-- Name: climatezones climate_zone_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.climatezones ALTER COLUMN climate_zone_id SET DEFAULT nextval('shared.climatezones_climate_zone_id_seq'::regclass);


--
-- Name: disturbanceevents disturbance_event_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.disturbanceevents ALTER COLUMN disturbance_event_id SET DEFAULT nextval('shared.disturbanceevents_disturbance_event_id_seq'::regclass);


--
-- Name: locations location_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.locations ALTER COLUMN location_id SET DEFAULT nextval('shared.locations_location_id_seq'::regclass);


--
-- Name: managementevents management_event_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.managementevents ALTER COLUMN management_event_id SET DEFAULT nextval('shared.managementevents_management_event_id_seq'::regclass);


--
-- Name: plots plot_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.plots ALTER COLUMN plot_id SET DEFAULT nextval('shared.plots_plot_id_seq'::regclass);


--
-- Name: processes process_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processes ALTER COLUMN process_id SET DEFAULT nextval('shared.processes_process_id_seq'::regclass);


--
-- Name: processingjobs processing_job_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processingjobs ALTER COLUMN processing_job_id SET DEFAULT nextval('shared.processingjobs_processing_job_id_seq'::regclass);


--
-- Name: processmetrics process_metric_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processmetrics ALTER COLUMN process_metric_id SET DEFAULT nextval('shared.processmetrics_process_metric_id_seq'::regclass);


--
-- Name: processparameters process_parameter_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters ALTER COLUMN process_parameter_id SET DEFAULT nextval('shared.processparameters_process_parameter_id_seq'::regclass);


--
-- Name: scenarios scenario_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.scenarios ALTER COLUMN scenario_id SET DEFAULT nextval('shared.scenarios_scenario_id_seq'::regclass);


--
-- Name: soiltypes soil_type_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.soiltypes ALTER COLUMN soil_type_id SET DEFAULT nextval('shared.soiltypes_soil_type_id_seq'::regclass);


--
-- Name: species species_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.species ALTER COLUMN species_id SET DEFAULT nextval('shared.species_species_id_seq'::regclass);


--
-- Name: variants variant_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.variants ALTER COLUMN variant_id SET DEFAULT nextval('shared.variants_variant_id_seq'::regclass);


--
-- Name: varianttypes variant_type_id; Type: DEFAULT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.varianttypes ALTER COLUMN variant_type_id SET DEFAULT nextval('shared.varianttypes_variant_type_id_seq'::regclass);


--
-- Name: axisstructures axis_structure_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.axisstructures ALTER COLUMN axis_structure_id SET DEFAULT nextval('trees.axisstructures_axis_structure_id_seq'::regclass);


--
-- Name: barkcharacteristics bark_characteristic_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.barkcharacteristics ALTER COLUMN bark_characteristic_id SET DEFAULT nextval('trees.barkcharacteristics_bark_characteristic_id_seq'::regclass);


--
-- Name: branchelongationhabits branch_elongation_habit_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.branchelongationhabits ALTER COLUMN branch_elongation_habit_id SET DEFAULT nextval('trees.branchelongationhabits_branch_elongation_habit_id_seq'::regclass);


--
-- Name: branchingpatterns branching_pattern_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.branchingpatterns ALTER COLUMN branching_pattern_id SET DEFAULT nextval('trees.branchingpatterns_branching_pattern_id_seq'::regclass);


--
-- Name: crownarchitectures crown_architecture_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownarchitectures ALTER COLUMN crown_architecture_id SET DEFAULT nextval('trees.crownarchitectures_crown_architecture_id_seq'::regclass);


--
-- Name: crownclasses crown_class_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownclasses ALTER COLUMN crown_class_id SET DEFAULT nextval('trees.crownclasses_crown_class_id_seq'::regclass);


--
-- Name: crownshapes crown_shape_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownshapes ALTER COLUMN crown_shape_id SET DEFAULT nextval('trees.crownshapes_crown_shape_id_seq'::regclass);


--
-- Name: damageagents damage_agent_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.damageagents ALTER COLUMN damage_agent_id SET DEFAULT nextval('trees.damageagents_damage_agent_id_seq'::regclass);


--
-- Name: datasourcetypes data_source_type_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.datasourcetypes ALTER COLUMN data_source_type_id SET DEFAULT nextval('trees.datasourcetypes_data_source_type_id_seq'::regclass);


--
-- Name: deadwood deadwood_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.deadwood ALTER COLUMN deadwood_id SET DEFAULT nextval('trees.deadwood_deadwood_id_seq'::regclass);


--
-- Name: geometriccrownsolids geometric_solid_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.geometriccrownsolids ALTER COLUMN geometric_solid_id SET DEFAULT nextval('trees.geometriccrownsolids_geometric_solid_id_seq'::regclass);


--
-- Name: groundvegetation ground_vegetation_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.groundvegetation ALTER COLUMN ground_vegetation_id SET DEFAULT nextval('trees.groundvegetation_ground_vegetation_id_seq'::regclass);


--
-- Name: growthforms growth_form_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthforms ALTER COLUMN growth_form_id SET DEFAULT nextval('trees.growthforms_growth_form_id_seq'::regclass);


--
-- Name: growthorientations growth_orientation_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthorientations ALTER COLUMN growth_orientation_id SET DEFAULT nextval('trees.growthorientations_growth_orientation_id_seq'::regclass);


--
-- Name: growthsimulations growth_simulation_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthsimulations ALTER COLUMN growth_simulation_id SET DEFAULT nextval('trees.growthsimulations_growth_simulation_id_seq'::regclass);


--
-- Name: phanerophyteheightclasses phanerophyte_height_class_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.phanerophyteheightclasses ALTER COLUMN phanerophyte_height_class_id SET DEFAULT nextval('trees.phanerophyteheightclasses_phanerophyte_height_class_id_seq'::regclass);


--
-- Name: phenologyobservations phenology_observation_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.phenologyobservations ALTER COLUMN phenology_observation_id SET DEFAULT nextval('trees.phenologyobservations_phenology_observation_id_seq'::regclass);


--
-- Name: shootelongationtypes shoot_elongation_type_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.shootelongationtypes ALTER COLUMN shoot_elongation_type_id SET DEFAULT nextval('trees.shootelongationtypes_shoot_elongation_type_id_seq'::regclass);


--
-- Name: stems stem_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.stems ALTER COLUMN stem_id SET DEFAULT nextval('trees.stems_stem_id_seq'::regclass);


--
-- Name: straightnesstypes straightness_type_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.straightnesstypes ALTER COLUMN straightness_type_id SET DEFAULT nextval('trees.straightnesstypes_straightness_type_id_seq'::regclass);


--
-- Name: tapertypes taper_type_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.tapertypes ALTER COLUMN taper_type_id SET DEFAULT nextval('trees.tapertypes_taper_type_id_seq'::regclass);


--
-- Name: trees tree_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees ALTER COLUMN tree_id SET DEFAULT nextval('trees.trees_tree_id_seq'::regclass);


--
-- Name: treestatus tree_status_id; Type: DEFAULT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.treestatus ALTER COLUMN tree_status_id SET DEFAULT nextval('trees.treestatus_tree_status_id_seq'::regclass);


--
-- Name: environments environments_pkey; Type: CONSTRAINT; Schema: environments; Owner: -
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_pkey PRIMARY KEY (environment_id);


--
-- Name: images images_pkey; Type: CONSTRAINT; Schema: imagery; Owner: -
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_pkey PRIMARY KEY (image_id);


--
-- Name: pointclouds pointclouds_pkey; Type: CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_pkey PRIMARY KEY (point_cloud_id);


--
-- Name: scanners scanners_pkey; Type: CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.scanners
    ADD CONSTRAINT scanners_pkey PRIMARY KEY (scanner_id);


--
-- Name: scanners scanners_serial_number_key; Type: CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.scanners
    ADD CONSTRAINT scanners_serial_number_key UNIQUE (serial_number);


--
-- Name: scannertypes scannertypes_pkey; Type: CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.scannertypes
    ADD CONSTRAINT scannertypes_pkey PRIMARY KEY (scanner_type_id);


--
-- Name: scannertypes scannertypes_scanner_type_name_key; Type: CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.scannertypes
    ADD CONSTRAINT scannertypes_scanner_type_name_key UNIQUE (scanner_type_name);


--
-- Name: sensor_tree_links sensor_tree_links_pkey; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_pkey PRIMARY KEY (sensortreelinkid);


--
-- Name: sensor_tree_links sensor_tree_links_sensor_id_tree_id_key; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_sensor_id_tree_id_key UNIQUE (sensor_id, tree_id);


--
-- Name: sensorreadings sensorreadings_pkey; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensorreadings
    ADD CONSTRAINT sensorreadings_pkey PRIMARY KEY (sensor_reading_id);


--
-- Name: sensorreadings sensorreadings_sensorid_timestamp_unique; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensorreadings
    ADD CONSTRAINT sensorreadings_sensorid_timestamp_unique UNIQUE (sensor_id, "timestamp");


--
-- Name: sensors sensors_external_id_key; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_external_id_key UNIQUE (external_id);


--
-- Name: sensors sensors_pkey; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_pkey PRIMARY KEY (sensor_id);


--
-- Name: sensortypes sensortypes_pkey; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensortypes
    ADD CONSTRAINT sensortypes_pkey PRIMARY KEY (sensor_type_id);


--
-- Name: sensortypes sensortypes_sensor_type_name_key; Type: CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensortypes
    ADD CONSTRAINT sensortypes_sensor_type_name_key UNIQUE (sensor_type_name);


--
-- Name: auditlog_environments auditlog_environments_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_environments
    ADD CONSTRAINT auditlog_environments_pkey PRIMARY KEY (audit_id, environment_id);


--
-- Name: auditlog auditlog_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog
    ADD CONSTRAINT auditlog_pkey PRIMARY KEY (audit_id);


--
-- Name: auditlog_pointclouds auditlog_pointclouds_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_pointclouds
    ADD CONSTRAINT auditlog_pointclouds_pkey PRIMARY KEY (audit_id, point_cloud_id);


--
-- Name: auditlog_stems auditlog_stems_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_stems
    ADD CONSTRAINT auditlog_stems_pkey PRIMARY KEY (audit_id, stem_id);


--
-- Name: auditlog_trees auditlog_trees_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_trees
    ADD CONSTRAINT auditlog_trees_pkey PRIMARY KEY (audit_id, tree_id);


--
-- Name: campaigns campaigns_campaign_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.campaigns
    ADD CONSTRAINT campaigns_campaign_name_key UNIQUE (campaign_name);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (campaign_id);


--
-- Name: climatezones climatezones_climate_zone_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.climatezones
    ADD CONSTRAINT climatezones_climate_zone_name_key UNIQUE (climate_zone_name);


--
-- Name: climatezones climatezones_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.climatezones
    ADD CONSTRAINT climatezones_pkey PRIMARY KEY (climate_zone_id);


--
-- Name: disturbanceevents disturbanceevents_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.disturbanceevents
    ADD CONSTRAINT disturbanceevents_pkey PRIMARY KEY (disturbance_event_id);


--
-- Name: disturbanceevents_trees disturbanceevents_trees_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.disturbanceevents_trees
    ADD CONSTRAINT disturbanceevents_trees_pkey PRIMARY KEY (disturbance_event_id, tree_id);


--
-- Name: locations locations_location_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_location_name_key UNIQUE (location_name);


--
-- Name: locations locations_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (location_id);


--
-- Name: managementevents managementevents_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.managementevents
    ADD CONSTRAINT managementevents_pkey PRIMARY KEY (management_event_id);


--
-- Name: plots plots_location_id_plot_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_location_id_plot_name_key UNIQUE (location_id, plot_name);


--
-- Name: plots plots_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_pkey PRIMARY KEY (plot_id);


--
-- Name: processes processes_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processes
    ADD CONSTRAINT processes_pkey PRIMARY KEY (process_id);


--
-- Name: processes processes_process_name_version_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processes
    ADD CONSTRAINT processes_process_name_version_key UNIQUE (process_name, version);


--
-- Name: processingjobs processingjobs_external_job_id_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processingjobs
    ADD CONSTRAINT processingjobs_external_job_id_key UNIQUE (external_job_id);


--
-- Name: processingjobs processingjobs_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processingjobs
    ADD CONSTRAINT processingjobs_pkey PRIMARY KEY (processing_job_id);


--
-- Name: processmetrics processmetrics_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processmetrics
    ADD CONSTRAINT processmetrics_pkey PRIMARY KEY (process_metric_id);


--
-- Name: processparameters_environments processparameters_environments_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_environments
    ADD CONSTRAINT processparameters_environments_pkey PRIMARY KEY (process_parameter_id, environment_id);


--
-- Name: processparameters processparameters_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters
    ADD CONSTRAINT processparameters_pkey PRIMARY KEY (process_parameter_id);


--
-- Name: processparameters_pointclouds processparameters_pointclouds_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_pointclouds
    ADD CONSTRAINT processparameters_pointclouds_pkey PRIMARY KEY (process_parameter_id, point_cloud_id);


--
-- Name: processparameters_stems processparameters_stems_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_stems
    ADD CONSTRAINT processparameters_stems_pkey PRIMARY KEY (process_parameter_id, stem_id);


--
-- Name: processparameters_trees processparameters_trees_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_trees
    ADD CONSTRAINT processparameters_trees_pkey PRIMARY KEY (process_parameter_id, tree_id);


--
-- Name: scenarios scenarios_location_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_location_name_key UNIQUE (location_id, scenario_name);


--
-- Name: scenarios scenarios_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_pkey PRIMARY KEY (scenario_id);


--
-- Name: soiltypes soiltypes_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.soiltypes
    ADD CONSTRAINT soiltypes_pkey PRIMARY KEY (soil_type_id);


--
-- Name: soiltypes soiltypes_soil_type_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.soiltypes
    ADD CONSTRAINT soiltypes_soil_type_name_key UNIQUE (soil_type_name);


--
-- Name: species species_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.species
    ADD CONSTRAINT species_pkey PRIMARY KEY (species_id);


--
-- Name: species species_scientific_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.species
    ADD CONSTRAINT species_scientific_name_key UNIQUE (scientific_name);


--
-- Name: variants variants_location_id_scenario_id_variant_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_location_id_scenario_id_variant_name_key UNIQUE (location_id, scenario_id, variant_name);


--
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (variant_id);


--
-- Name: varianttypes varianttypes_pkey; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.varianttypes
    ADD CONSTRAINT varianttypes_pkey PRIMARY KEY (variant_type_id);


--
-- Name: varianttypes varianttypes_variant_type_name_key; Type: CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.varianttypes
    ADD CONSTRAINT varianttypes_variant_type_name_key UNIQUE (variant_type_name);


--
-- Name: axisstructures axisstructures_axis_structure_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.axisstructures
    ADD CONSTRAINT axisstructures_axis_structure_name_key UNIQUE (axis_structure_name);


--
-- Name: axisstructures axisstructures_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.axisstructures
    ADD CONSTRAINT axisstructures_pkey PRIMARY KEY (axis_structure_id);


--
-- Name: barkcharacteristics barkcharacteristics_bark_characteristic_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.barkcharacteristics
    ADD CONSTRAINT barkcharacteristics_bark_characteristic_name_key UNIQUE (bark_characteristic_name);


--
-- Name: barkcharacteristics barkcharacteristics_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.barkcharacteristics
    ADD CONSTRAINT barkcharacteristics_pkey PRIMARY KEY (bark_characteristic_id);


--
-- Name: branchelongationhabits branchelongationhabits_elongation_habit_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.branchelongationhabits
    ADD CONSTRAINT branchelongationhabits_elongation_habit_name_key UNIQUE (elongation_habit_name);


--
-- Name: branchelongationhabits branchelongationhabits_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.branchelongationhabits
    ADD CONSTRAINT branchelongationhabits_pkey PRIMARY KEY (branch_elongation_habit_id);


--
-- Name: branchingpatterns branchingpatterns_branching_pattern_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.branchingpatterns
    ADD CONSTRAINT branchingpatterns_branching_pattern_name_key UNIQUE (branching_pattern_name);


--
-- Name: branchingpatterns branchingpatterns_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.branchingpatterns
    ADD CONSTRAINT branchingpatterns_pkey PRIMARY KEY (branching_pattern_id);


--
-- Name: crownarchitectures crownarchitectures_crown_architecture_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownarchitectures
    ADD CONSTRAINT crownarchitectures_crown_architecture_name_key UNIQUE (crown_architecture_name);


--
-- Name: crownarchitectures crownarchitectures_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownarchitectures
    ADD CONSTRAINT crownarchitectures_pkey PRIMARY KEY (crown_architecture_id);


--
-- Name: crownclasses crownclasses_crown_class_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownclasses
    ADD CONSTRAINT crownclasses_crown_class_name_key UNIQUE (crown_class_name);


--
-- Name: crownclasses crownclasses_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownclasses
    ADD CONSTRAINT crownclasses_pkey PRIMARY KEY (crown_class_id);


--
-- Name: crownshapes crownshapes_crown_shape_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownshapes
    ADD CONSTRAINT crownshapes_crown_shape_name_key UNIQUE (crown_shape_name);


--
-- Name: crownshapes crownshapes_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.crownshapes
    ADD CONSTRAINT crownshapes_pkey PRIMARY KEY (crown_shape_id);


--
-- Name: damageagents damageagents_damage_agent_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.damageagents
    ADD CONSTRAINT damageagents_damage_agent_name_key UNIQUE (damage_agent_name);


--
-- Name: damageagents damageagents_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.damageagents
    ADD CONSTRAINT damageagents_pkey PRIMARY KEY (damage_agent_id);


--
-- Name: datasourcetypes datasourcetypes_data_source_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.datasourcetypes
    ADD CONSTRAINT datasourcetypes_data_source_type_name_key UNIQUE (data_source_type_name);


--
-- Name: datasourcetypes datasourcetypes_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.datasourcetypes
    ADD CONSTRAINT datasourcetypes_pkey PRIMARY KEY (data_source_type_id);


--
-- Name: deadwood deadwood_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.deadwood
    ADD CONSTRAINT deadwood_pkey PRIMARY KEY (deadwood_id);


--
-- Name: geometriccrownsolids geometriccrownsolids_geometric_solid_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.geometriccrownsolids
    ADD CONSTRAINT geometriccrownsolids_geometric_solid_name_key UNIQUE (geometric_solid_name);


--
-- Name: geometriccrownsolids geometriccrownsolids_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.geometriccrownsolids
    ADD CONSTRAINT geometriccrownsolids_pkey PRIMARY KEY (geometric_solid_id);


--
-- Name: groundvegetation groundvegetation_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.groundvegetation
    ADD CONSTRAINT groundvegetation_pkey PRIMARY KEY (ground_vegetation_id);


--
-- Name: growthforms growthforms_growth_form_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthforms
    ADD CONSTRAINT growthforms_growth_form_name_key UNIQUE (growth_form_name);


--
-- Name: growthforms growthforms_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthforms
    ADD CONSTRAINT growthforms_pkey PRIMARY KEY (growth_form_id);


--
-- Name: growthorientations growthorientations_growth_orientation_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthorientations
    ADD CONSTRAINT growthorientations_growth_orientation_name_key UNIQUE (growth_orientation_name);


--
-- Name: growthorientations growthorientations_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthorientations
    ADD CONSTRAINT growthorientations_pkey PRIMARY KEY (growth_orientation_id);


--
-- Name: growthsimulations growthsimulations_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthsimulations
    ADD CONSTRAINT growthsimulations_pkey PRIMARY KEY (growth_simulation_id);


--
-- Name: phanerophyteheightclasses phanerophyteheightclasses_height_class_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.phanerophyteheightclasses
    ADD CONSTRAINT phanerophyteheightclasses_height_class_name_key UNIQUE (height_class_name);


--
-- Name: phanerophyteheightclasses phanerophyteheightclasses_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.phanerophyteheightclasses
    ADD CONSTRAINT phanerophyteheightclasses_pkey PRIMARY KEY (phanerophyte_height_class_id);


--
-- Name: phenologyobservations phenologyobservations_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.phenologyobservations
    ADD CONSTRAINT phenologyobservations_pkey PRIMARY KEY (phenology_observation_id);


--
-- Name: shootelongationtypes shootelongationtypes_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.shootelongationtypes
    ADD CONSTRAINT shootelongationtypes_pkey PRIMARY KEY (shoot_elongation_type_id);


--
-- Name: shootelongationtypes shootelongationtypes_shoot_elongation_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.shootelongationtypes
    ADD CONSTRAINT shootelongationtypes_shoot_elongation_type_name_key UNIQUE (shoot_elongation_type_name);


--
-- Name: stems stems_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_pkey PRIMARY KEY (stem_id);


--
-- Name: stems stems_tree_id_stem_number_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_tree_id_stem_number_key UNIQUE (tree_id, stem_number);


--
-- Name: straightnesstypes straightnesstypes_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.straightnesstypes
    ADD CONSTRAINT straightnesstypes_pkey PRIMARY KEY (straightness_type_id);


--
-- Name: straightnesstypes straightnesstypes_straightness_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.straightnesstypes
    ADD CONSTRAINT straightnesstypes_straightness_name_key UNIQUE (straightness_name);


--
-- Name: tapertypes tapertypes_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.tapertypes
    ADD CONSTRAINT tapertypes_pkey PRIMARY KEY (taper_type_id);


--
-- Name: tapertypes tapertypes_taper_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.tapertypes
    ADD CONSTRAINT tapertypes_taper_type_name_key UNIQUE (taper_type_name);


--
-- Name: trees trees_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_pkey PRIMARY KEY (tree_id);


--
-- Name: treestatus treestatus_pkey; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.treestatus
    ADD CONSTRAINT treestatus_pkey PRIMARY KEY (tree_status_id);


--
-- Name: treestatus treestatus_tree_status_name_key; Type: CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.treestatus
    ADD CONSTRAINT treestatus_tree_status_name_key UNIQUE (tree_status_name);


--
-- Name: idx_environments_created_at; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_created_at ON environments.environments USING btree (created_at DESC);


--
-- Name: idx_environments_created_by; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_created_by ON environments.environments USING btree (created_by);


--
-- Name: idx_environments_end_date; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_end_date ON environments.environments USING btree (end_date DESC NULLS LAST);


--
-- Name: idx_environments_location; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_location ON environments.environments USING btree (location_id);


--
-- Name: idx_environments_parent; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_parent ON environments.environments USING btree (parent_environment_id);


--
-- Name: idx_environments_process; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_process ON environments.environments USING btree (process_id);


--
-- Name: idx_environments_scenario; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_scenario ON environments.environments USING btree (scenario_id);


--
-- Name: idx_environments_start_date; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_start_date ON environments.environments USING btree (start_date DESC);


--
-- Name: idx_environments_variant_type; Type: INDEX; Schema: environments; Owner: -
--

CREATE INDEX idx_environments_variant_type ON environments.environments USING btree (variant_type_id);


--
-- Name: idx_images_campaign; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_campaign ON imagery.images USING btree (campaign_id);


--
-- Name: idx_images_capture_date; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_capture_date ON imagery.images USING btree (capture_date DESC);


--
-- Name: idx_images_created_at; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_created_at ON imagery.images USING btree (created_at DESC);


--
-- Name: idx_images_created_by; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_created_by ON imagery.images USING btree (created_by);


--
-- Name: idx_images_format; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_format ON imagery.images USING btree (file_format);


--
-- Name: idx_images_location; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_location ON imagery.images USING btree (location_id);


--
-- Name: idx_images_plot; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_plot ON imagery.images USING btree (plot_id);


--
-- Name: idx_images_position; Type: INDEX; Schema: imagery; Owner: -
--

CREATE INDEX idx_images_position ON imagery.images USING gist ("position");


--
-- Name: idx_pointclouds_campaign; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_campaign ON pointclouds.pointclouds USING btree (campaign_id);


--
-- Name: idx_pointclouds_created_at; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_created_at ON pointclouds.pointclouds USING btree (created_at DESC);


--
-- Name: idx_pointclouds_created_by; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_created_by ON pointclouds.pointclouds USING btree (created_by);


--
-- Name: idx_pointclouds_location; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_location ON pointclouds.pointclouds USING btree (location_id);


--
-- Name: idx_pointclouds_parent; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_parent ON pointclouds.pointclouds USING btree (parent_point_cloud_id);


--
-- Name: idx_pointclouds_platform_type; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_platform_type ON pointclouds.pointclouds USING btree (platform_type);


--
-- Name: idx_pointclouds_process; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_process ON pointclouds.pointclouds USING btree (process_id);


--
-- Name: idx_pointclouds_processing_status; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_processing_status ON pointclouds.pointclouds USING btree (processing_status);


--
-- Name: idx_pointclouds_scan_bounds; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_scan_bounds ON pointclouds.pointclouds USING gist (scan_bounds);


--
-- Name: idx_pointclouds_scan_date; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_scan_date ON pointclouds.pointclouds USING btree (scan_date DESC);


--
-- Name: idx_pointclouds_scanner; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_scanner ON pointclouds.pointclouds USING btree (scanner_id);


--
-- Name: idx_pointclouds_scenario; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_scenario ON pointclouds.pointclouds USING btree (scenario_id);


--
-- Name: idx_pointclouds_variant_type; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_pointclouds_variant_type ON pointclouds.pointclouds USING btree (variant_type_id);


--
-- Name: idx_scanner_types_name; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_scanner_types_name ON pointclouds.scannertypes USING btree (scanner_type_name);


--
-- Name: idx_scanners_serial; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_scanners_serial ON pointclouds.scanners USING btree (serial_number);


--
-- Name: idx_scanners_type; Type: INDEX; Schema: pointclouds; Owner: -
--

CREATE INDEX idx_scanners_type ON pointclouds.scanners USING btree (scanner_type_id);


--
-- Name: idx_sensor_readings_quality; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensor_readings_quality ON sensor.sensorreadings USING btree (quality);


--
-- Name: idx_sensor_readings_scenario; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensor_readings_scenario ON sensor.sensorreadings USING btree (scenario_id);


--
-- Name: idx_sensor_readings_sensor_id; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensor_readings_sensor_id ON sensor.sensorreadings USING btree (sensor_id);


--
-- Name: idx_sensor_readings_sensor_timestamp; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensor_readings_sensor_timestamp ON sensor.sensorreadings USING btree (sensor_id, "timestamp" DESC);


--
-- Name: idx_sensor_readings_timestamp; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensor_readings_timestamp ON sensor.sensorreadings USING btree ("timestamp" DESC);


--
-- Name: idx_sensor_tree_links_tree; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensor_tree_links_tree ON sensor.sensor_tree_links USING btree (tree_id);


--
-- Name: idx_sensor_types_name; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensor_types_name ON sensor.sensortypes USING btree (sensor_type_name);


--
-- Name: idx_sensors_campaign; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_campaign ON sensor.sensors USING btree (campaign_id);


--
-- Name: idx_sensors_created_by; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_created_by ON sensor.sensors USING btree (created_by);


--
-- Name: idx_sensors_external_id; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_external_id ON sensor.sensors USING btree (external_id);


--
-- Name: idx_sensors_installation_date; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_installation_date ON sensor.sensors USING btree (installation_date DESC);


--
-- Name: idx_sensors_is_active; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_is_active ON sensor.sensors USING btree (is_active);


--
-- Name: idx_sensors_location; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_location ON sensor.sensors USING btree (location_id);


--
-- Name: idx_sensors_plot; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_plot ON sensor.sensors USING btree (plot_id);


--
-- Name: idx_sensors_position; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_position ON sensor.sensors USING gist ("position");


--
-- Name: idx_sensors_sensor_type; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_sensor_type ON sensor.sensors USING btree (sensor_type_id);


--
-- Name: idx_sensors_serial_number; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_serial_number ON sensor.sensors USING btree (serial_number);


--
-- Name: idx_sensors_source; Type: INDEX; Schema: sensor; Owner: -
--

CREATE INDEX idx_sensors_source ON sensor.sensors USING btree (source);


--
-- Name: idx_audit_environments_audit; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_environments_audit ON shared.auditlog_environments USING btree (audit_id);


--
-- Name: idx_audit_environments_environment; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_environments_environment ON shared.auditlog_environments USING btree (environment_id);


--
-- Name: idx_audit_log_change_type; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_log_change_type ON shared.auditlog USING btree (change_type);


--
-- Name: idx_audit_log_field_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_log_field_name ON shared.auditlog USING btree (field_name);


--
-- Name: idx_audit_log_timestamp; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_log_timestamp ON shared.auditlog USING btree ("timestamp" DESC);


--
-- Name: idx_audit_log_user_id; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_log_user_id ON shared.auditlog USING btree (user_id);


--
-- Name: idx_audit_pointclouds_audit; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_pointclouds_audit ON shared.auditlog_pointclouds USING btree (audit_id);


--
-- Name: idx_audit_pointclouds_pointcloud; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_pointclouds_pointcloud ON shared.auditlog_pointclouds USING btree (point_cloud_id);


--
-- Name: idx_audit_stems_audit; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_stems_audit ON shared.auditlog_stems USING btree (audit_id);


--
-- Name: idx_audit_stems_stem; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_stems_stem ON shared.auditlog_stems USING btree (stem_id);


--
-- Name: idx_audit_trees_audit; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_trees_audit ON shared.auditlog_trees USING btree (audit_id);


--
-- Name: idx_audit_trees_tree; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_audit_trees_tree ON shared.auditlog_trees USING btree (tree_id);


--
-- Name: idx_campaigns_location; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_campaigns_location ON shared.campaigns USING btree (location_id);


--
-- Name: idx_campaigns_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_campaigns_name ON shared.campaigns USING btree (campaign_name);


--
-- Name: idx_campaigns_start_date; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_campaigns_start_date ON shared.campaigns USING btree (start_date DESC);


--
-- Name: idx_campaigns_type; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_campaigns_type ON shared.campaigns USING btree (campaign_type);


--
-- Name: idx_dist_events_date; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_dist_events_date ON shared.disturbanceevents USING btree (event_date DESC);


--
-- Name: idx_dist_events_location; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_dist_events_location ON shared.disturbanceevents USING btree (location_id);


--
-- Name: idx_dist_events_plot; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_dist_events_plot ON shared.disturbanceevents USING btree (plot_id);


--
-- Name: idx_dist_events_severity; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_dist_events_severity ON shared.disturbanceevents USING btree (severity);


--
-- Name: idx_dist_events_type; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_dist_events_type ON shared.disturbanceevents USING btree (disturbance_type);


--
-- Name: idx_dist_trees_event; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_dist_trees_event ON shared.disturbanceevents_trees USING btree (disturbance_event_id);


--
-- Name: idx_dist_trees_tree; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_dist_trees_tree ON shared.disturbanceevents_trees USING btree (tree_id);


--
-- Name: idx_locations_boundary; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_locations_boundary ON shared.locations USING gist (boundary);


--
-- Name: idx_locations_centerpoint; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_locations_centerpoint ON shared.locations USING gist (center_point);


--
-- Name: idx_locations_climate_zone; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_locations_climate_zone ON shared.locations USING btree (climate_zone_id);


--
-- Name: idx_locations_soil_type; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_locations_soil_type ON shared.locations USING btree (soil_type_id);


--
-- Name: idx_mgmt_events_date; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_mgmt_events_date ON shared.managementevents USING btree (event_date DESC);


--
-- Name: idx_mgmt_events_location; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_mgmt_events_location ON shared.managementevents USING btree (location_id);


--
-- Name: idx_mgmt_events_plot; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_mgmt_events_plot ON shared.managementevents USING btree (plot_id);


--
-- Name: idx_mgmt_events_type; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_mgmt_events_type ON shared.managementevents USING btree (event_type);


--
-- Name: idx_plots_boundary; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_plots_boundary ON shared.plots USING gist (boundary);


--
-- Name: idx_plots_centerpoint; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_plots_centerpoint ON shared.plots USING gist (center_point);


--
-- Name: idx_plots_location; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_plots_location ON shared.plots USING btree (location_id);


--
-- Name: idx_pp_environments_environment; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_environments_environment ON shared.processparameters_environments USING btree (environment_id);


--
-- Name: idx_pp_environments_parameter; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_environments_parameter ON shared.processparameters_environments USING btree (process_parameter_id);


--
-- Name: idx_pp_pointclouds_parameter; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_pointclouds_parameter ON shared.processparameters_pointclouds USING btree (process_parameter_id);


--
-- Name: idx_pp_pointclouds_pointcloud; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_pointclouds_pointcloud ON shared.processparameters_pointclouds USING btree (point_cloud_id);


--
-- Name: idx_pp_stems_parameter; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_stems_parameter ON shared.processparameters_stems USING btree (process_parameter_id);


--
-- Name: idx_pp_stems_stem; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_stems_stem ON shared.processparameters_stems USING btree (stem_id);


--
-- Name: idx_pp_trees_parameter; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_trees_parameter ON shared.processparameters_trees USING btree (process_parameter_id);


--
-- Name: idx_pp_trees_tree; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_pp_trees_tree ON shared.processparameters_trees USING btree (tree_id);


--
-- Name: idx_process_metrics_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_process_metrics_name ON shared.processmetrics USING btree (metric_name);


--
-- Name: idx_process_metrics_process_id; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_process_metrics_process_id ON shared.processmetrics USING btree (process_id);


--
-- Name: idx_process_parameters_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_process_parameters_name ON shared.processparameters USING btree (parameter_name);


--
-- Name: idx_processes_category; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_processes_category ON shared.processes USING btree (category);


--
-- Name: idx_processes_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_processes_name ON shared.processes USING btree (process_name);


--
-- Name: idx_processing_jobs_external_id; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_processing_jobs_external_id ON shared.processingjobs USING btree (external_job_id);


--
-- Name: idx_processing_jobs_status; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_processing_jobs_status ON shared.processingjobs USING btree (status);


--
-- Name: idx_processing_jobs_submitted_at; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_processing_jobs_submitted_at ON shared.processingjobs USING btree (submitted_at DESC);


--
-- Name: idx_processing_jobs_submitted_by; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_processing_jobs_submitted_by ON shared.processingjobs USING btree (submitted_by);


--
-- Name: idx_processing_jobs_workflow; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_processing_jobs_workflow ON shared.processingjobs USING btree (workflow_name);


--
-- Name: idx_scenarios_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_scenarios_name ON shared.scenarios USING btree (scenario_name);


--
-- Name: idx_species_common_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_species_common_name ON shared.species USING btree (common_name);


--
-- Name: idx_species_growth_rate; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_species_growth_rate ON shared.species USING btree (growth_rate);


--
-- Name: idx_species_scientific_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_species_scientific_name ON shared.species USING btree (scientific_name);


--
-- Name: idx_species_shade_tolerance; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_species_shade_tolerance ON shared.species USING btree (shade_tolerance);


--
-- Name: idx_variant_types_name; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_variant_types_name ON shared.varianttypes USING btree (variant_type_name);


--
-- Name: idx_variants_location; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_variants_location ON shared.variants USING btree (location_id);


--
-- Name: idx_variants_location_scenario; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_variants_location_scenario ON shared.variants USING btree (location_id, scenario_id);


--
-- Name: idx_variants_scenario; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_variants_scenario ON shared.variants USING btree (scenario_id);


--
-- Name: idx_variants_sort; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_variants_sort ON shared.variants USING btree (location_id, scenario_id, sort_order);


--
-- Name: idx_variants_type; Type: INDEX; Schema: shared; Owner: -
--

CREATE INDEX idx_variants_type ON shared.variants USING btree (variant_type_id);


--
-- Name: idx_axis_structures_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_axis_structures_name ON trees.axisstructures USING btree (axis_structure_name);


--
-- Name: idx_bark_characteristics_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_bark_characteristics_name ON trees.barkcharacteristics USING btree (bark_characteristic_name);


--
-- Name: idx_branching_patterns_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_branching_patterns_name ON trees.branchingpatterns USING btree (branching_pattern_name);


--
-- Name: idx_crown_architectures_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_crown_architectures_name ON trees.crownarchitectures USING btree (crown_architecture_name);


--
-- Name: idx_crown_classes_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_crown_classes_name ON trees.crownclasses USING btree (crown_class_name);


--
-- Name: idx_crown_shapes_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_crown_shapes_name ON trees.crownshapes USING btree (crown_shape_name);


--
-- Name: idx_damage_agents_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_damage_agents_name ON trees.damageagents USING btree (damage_agent_name);


--
-- Name: idx_deadwood_location; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_deadwood_location ON trees.deadwood USING btree (location_id);


--
-- Name: idx_deadwood_plot; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_deadwood_plot ON trees.deadwood USING btree (plot_id);


--
-- Name: idx_deadwood_position; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_deadwood_position ON trees.deadwood USING gist ("position");


--
-- Name: idx_deadwood_species; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_deadwood_species ON trees.deadwood USING btree (species_id);


--
-- Name: idx_deadwood_tree; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_deadwood_tree ON trees.deadwood USING btree (tree_id);


--
-- Name: idx_deadwood_type; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_deadwood_type ON trees.deadwood USING btree (wood_type);


--
-- Name: idx_elongation_habits_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_elongation_habits_name ON trees.branchelongationhabits USING btree (elongation_habit_name);


--
-- Name: idx_geometric_solids_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_geometric_solids_name ON trees.geometriccrownsolids USING btree (geometric_solid_name);


--
-- Name: idx_groundveg_date; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_groundveg_date ON trees.groundvegetation USING btree (measurement_date DESC);


--
-- Name: idx_groundveg_layer; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_groundveg_layer ON trees.groundvegetation USING btree (layer);


--
-- Name: idx_groundveg_location; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_groundveg_location ON trees.groundvegetation USING btree (location_id);


--
-- Name: idx_groundveg_plot; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_groundveg_plot ON trees.groundvegetation USING btree (plot_id);


--
-- Name: idx_growth_forms_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_growth_forms_name ON trees.growthforms USING btree (growth_form_name);


--
-- Name: idx_growth_orientations_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_growth_orientations_name ON trees.growthorientations USING btree (growth_orientation_name);


--
-- Name: idx_growthsim_entity_run; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_growthsim_entity_run ON trees.growthsimulations USING btree (tree_entity_id, run_id);


--
-- Name: idx_growthsim_location_year; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_growthsim_location_year ON trees.growthsimulations USING btree (location_id, projection_year);


--
-- Name: idx_growthsim_run_year; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_growthsim_run_year ON trees.growthsimulations USING btree (run_id, projection_year);


--
-- Name: idx_growthsim_scenario_year; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_growthsim_scenario_year ON trees.growthsimulations USING btree (scenario_id, projection_year);


--
-- Name: idx_growthsim_simulator; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_growthsim_simulator ON trees.growthsimulations USING btree (simulator_name, scenario_id);


--
-- Name: idx_height_classes_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_height_classes_name ON trees.phanerophyteheightclasses USING btree (height_class_name);


--
-- Name: idx_phenology_date; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_phenology_date ON trees.phenologyobservations USING btree (observation_date DESC);


--
-- Name: idx_phenology_tree; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_phenology_tree ON trees.phenologyobservations USING btree (tree_id);


--
-- Name: idx_phenology_type; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_phenology_type ON trees.phenologyobservations USING btree (phenophase_type);


--
-- Name: idx_shoot_elongation_types_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_shoot_elongation_types_name ON trees.shootelongationtypes USING btree (shoot_elongation_type_name);


--
-- Name: idx_stems_dbh; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_stems_dbh ON trees.stems USING btree (dbh_cm);


--
-- Name: idx_stems_stem_number; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_stems_stem_number ON trees.stems USING btree (stem_number);


--
-- Name: idx_stems_straightness_type; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_stems_straightness_type ON trees.stems USING btree (straightness_type_id);


--
-- Name: idx_stems_taper_type; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_stems_taper_type ON trees.stems USING btree (taper_type_id);


--
-- Name: idx_stems_tree; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_stems_tree ON trees.stems USING btree (tree_id);


--
-- Name: idx_straightness_types_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_straightness_types_name ON trees.straightnesstypes USING btree (straightness_name);


--
-- Name: idx_taper_types_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_taper_types_name ON trees.tapertypes USING btree (taper_type_name);


--
-- Name: idx_tree_status_name; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_tree_status_name ON trees.treestatus USING btree (tree_status_name);


--
-- Name: idx_trees_axis_structure; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_axis_structure ON trees.trees USING btree (axis_structure_id);


--
-- Name: idx_trees_campaign; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_campaign ON trees.trees USING btree (campaign_id);


--
-- Name: idx_trees_created_at; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_created_at ON trees.trees USING btree (created_at DESC);


--
-- Name: idx_trees_created_by; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_created_by ON trees.trees USING btree (created_by);


--
-- Name: idx_trees_crown_architecture; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_crown_architecture ON trees.trees USING btree (crown_architecture_id);


--
-- Name: idx_trees_crown_boundary; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_crown_boundary ON trees.trees USING gist (crown_boundary);


--
-- Name: idx_trees_crown_class; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_crown_class ON trees.trees USING btree (crown_class_id);


--
-- Name: idx_trees_crown_shape; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_crown_shape ON trees.trees USING btree (crown_shape_id);


--
-- Name: idx_trees_damage_agent; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_damage_agent ON trees.trees USING btree (damage_agent_id);


--
-- Name: idx_trees_datasource_type; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_datasource_type ON trees.trees USING btree (data_source_type_id);


--
-- Name: idx_trees_elongation_habit; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_elongation_habit ON trees.trees USING btree (elongation_habit_id);


--
-- Name: idx_trees_geometric_solid; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_geometric_solid ON trees.trees USING btree (geometric_solid_id);


--
-- Name: idx_trees_growth_form; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_growth_form ON trees.trees USING btree (growth_form_id);


--
-- Name: idx_trees_growth_orientation; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_growth_orientation ON trees.trees USING btree (growth_orientation_id);


--
-- Name: idx_trees_height; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_height ON trees.trees USING btree (height_m);


--
-- Name: idx_trees_height_class; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_height_class ON trees.trees USING btree (height_class_id);


--
-- Name: idx_trees_live_crown_ratio; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_live_crown_ratio ON trees.trees USING btree (live_crown_ratio);


--
-- Name: idx_trees_location; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_location ON trees.trees USING btree (location_id);


--
-- Name: idx_trees_location_scenario; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_location_scenario ON trees.trees USING btree (location_id, scenario_id);


--
-- Name: idx_trees_measurement_date; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_measurement_date ON trees.trees USING btree (measurement_date DESC);


--
-- Name: idx_trees_parent; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_parent ON trees.trees USING btree (parent_tree_id);


--
-- Name: idx_trees_plot; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_plot ON trees.trees USING btree (plot_id);


--
-- Name: idx_trees_pointcloud; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_pointcloud ON trees.trees USING btree (point_cloud_id);


--
-- Name: idx_trees_position; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_position ON trees.trees USING gist ("position");


--
-- Name: idx_trees_process; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_process ON trees.trees USING btree (process_id);


--
-- Name: idx_trees_scenario; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_scenario ON trees.trees USING btree (scenario_id);


--
-- Name: idx_trees_scenario_id; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_scenario_id ON trees.trees USING btree (scenario_id);


--
-- Name: idx_trees_sensor_ref; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_sensor_ref ON trees.trees USING btree (sensor_ref);


--
-- Name: idx_trees_shoot_elongation; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_shoot_elongation ON trees.trees USING btree (shoot_elongation_type_id);


--
-- Name: idx_trees_species; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_species ON trees.trees USING btree (species_id);


--
-- Name: idx_trees_tree_entity; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_tree_entity ON trees.trees USING btree (tree_entity_id);


--
-- Name: idx_trees_tree_number; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_tree_number ON trees.trees USING btree (tree_number);


--
-- Name: idx_trees_tree_status; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_tree_status ON trees.trees USING btree (tree_status_id);


--
-- Name: idx_trees_variant; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_variant ON trees.trees USING btree (variant_id);


--
-- Name: idx_trees_variant_type; Type: INDEX; Schema: trees; Owner: -
--

CREATE INDEX idx_trees_variant_type ON trees.trees USING btree (variant_type_id);


--
-- Name: trees_with_metrics _RETURN; Type: RULE; Schema: trees; Owner: -
--

CREATE OR REPLACE VIEW trees.trees_with_metrics AS
 SELECT t.tree_id,
    t.tree_entity_id,
    t.variant_id,
    t.parent_tree_id,
    t.point_cloud_id,
    t.campaign_id,
    t.location_id,
    t.plot_id,
    t.scenario_id,
    t.variant_type_id,
    t.process_id,
    t.species_id,
    t.tree_status_id,
    t.branching_pattern_id,
    t.bark_characteristic_id,
    t.measurement_date,
    t.data_source_type_id,
    t.height_m,
    t.height_source,
    t.crown_width_m,
    t.crown_base_height_m,
    t.crown_boundary,
    t.crown_offset_x_m,
    t.crown_offset_y_m,
    t.volume_m3,
    t."position",
    t.position_original,
    t.source_crs,
    t.lean_angle_deg,
    t.lean_direction_azimuth,
    t.time_delta_yrs,
    t.age_years,
    t.health_score,
    t.biomass_kg,
    t.carbon_content_kg,
    t.species_confidence,
    t.position_confidence,
    t.height_confidence,
    t.status_change_date,
    t.tree_number,
    t.field_notes,
    t.created_at,
    t.updated_at,
    t.created_by,
    t.updated_by,
    s.scientific_name,
    s.common_name,
    count(st.stem_id) AS stem_count,
    sum(trees.calculate_basal_area(st.dbh_cm)) AS total_basal_area_m2,
    trees.calculate_crown_volume(t.crown_width_m, (t.height_m - t.crown_base_height_m)) AS crown_volume_m3
   FROM ((trees.trees t
     LEFT JOIN shared.species s ON ((t.species_id = s.species_id)))
     LEFT JOIN trees.stems st ON ((t.tree_id = st.tree_id)))
  GROUP BY t.tree_id, s.species_id;


--
-- Name: environments trigger_environments_audit; Type: TRIGGER; Schema: environments; Owner: -
--

CREATE TRIGGER trigger_environments_audit AFTER UPDATE ON environments.environments FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: environments trigger_environments_created_by; Type: TRIGGER; Schema: environments; Owner: -
--

CREATE TRIGGER trigger_environments_created_by BEFORE INSERT ON environments.environments FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: environments trigger_environments_updated_at; Type: TRIGGER; Schema: environments; Owner: -
--

CREATE TRIGGER trigger_environments_updated_at BEFORE UPDATE ON environments.environments FOR EACH ROW EXECUTE FUNCTION environments.update_updated_at_column();


--
-- Name: environments trigger_environments_updated_by; Type: TRIGGER; Schema: environments; Owner: -
--

CREATE TRIGGER trigger_environments_updated_by BEFORE UPDATE ON environments.environments FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: images trigger_images_created_by; Type: TRIGGER; Schema: imagery; Owner: -
--

CREATE TRIGGER trigger_images_created_by BEFORE INSERT ON imagery.images FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: images trigger_images_updated_at; Type: TRIGGER; Schema: imagery; Owner: -
--

CREATE TRIGGER trigger_images_updated_at BEFORE UPDATE ON imagery.images FOR EACH ROW EXECUTE FUNCTION imagery.update_updated_at_column();


--
-- Name: images trigger_images_updated_by; Type: TRIGGER; Schema: imagery; Owner: -
--

CREATE TRIGGER trigger_images_updated_by BEFORE UPDATE ON imagery.images FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: pointclouds trigger_pointclouds_audit; Type: TRIGGER; Schema: pointclouds; Owner: -
--

CREATE TRIGGER trigger_pointclouds_audit AFTER UPDATE ON pointclouds.pointclouds FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: pointclouds trigger_pointclouds_created_by; Type: TRIGGER; Schema: pointclouds; Owner: -
--

CREATE TRIGGER trigger_pointclouds_created_by BEFORE INSERT ON pointclouds.pointclouds FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: pointclouds trigger_pointclouds_updated_at; Type: TRIGGER; Schema: pointclouds; Owner: -
--

CREATE TRIGGER trigger_pointclouds_updated_at BEFORE UPDATE ON pointclouds.pointclouds FOR EACH ROW EXECUTE FUNCTION pointclouds.update_updated_at_column();


--
-- Name: pointclouds trigger_pointclouds_updated_by; Type: TRIGGER; Schema: pointclouds; Owner: -
--

CREATE TRIGGER trigger_pointclouds_updated_by BEFORE UPDATE ON pointclouds.pointclouds FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: campaigns campaigns_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER campaigns_delete_trigger INSTEAD OF DELETE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.campaigns_delete();


--
-- Name: campaigns campaigns_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER campaigns_insert_trigger INSTEAD OF INSERT ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.campaigns_insert();


--
-- Name: campaigns campaigns_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER campaigns_update_trigger INSTEAD OF UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.campaigns_update();


--
-- Name: deadwood deadwood_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deadwood_insert_trigger INSTEAD OF INSERT ON public.deadwood FOR EACH ROW EXECUTE FUNCTION public.deadwood_insert();


--
-- Name: disturbanceevents disturbanceevents_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER disturbanceevents_insert_trigger INSTEAD OF INSERT ON public.disturbanceevents FOR EACH ROW EXECUTE FUNCTION public.disturbanceevents_insert();


--
-- Name: environments environments_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER environments_insert_trigger INSTEAD OF INSERT ON public.environments FOR EACH ROW EXECUTE FUNCTION public.environments_insert();


--
-- Name: groundvegetation groundvegetation_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER groundvegetation_insert_trigger INSTEAD OF INSERT ON public.groundvegetation FOR EACH ROW EXECUTE FUNCTION public.groundvegetation_insert();


--
-- Name: images images_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER images_insert_trigger INSTEAD OF INSERT ON public.images FOR EACH ROW EXECUTE FUNCTION public.images_insert();


--
-- Name: managementevents managementevents_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER managementevents_insert_trigger INSTEAD OF INSERT ON public.managementevents FOR EACH ROW EXECUTE FUNCTION public.managementevents_insert();


--
-- Name: phenologyobservations phenologyobservations_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER phenologyobservations_insert_trigger INSTEAD OF INSERT ON public.phenologyobservations FOR EACH ROW EXECUTE FUNCTION public.phenologyobservations_insert();


--
-- Name: plots plots_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER plots_insert_trigger INSTEAD OF INSERT ON public.plots FOR EACH ROW EXECUTE FUNCTION public.plots_insert();


--
-- Name: pointclouds pointclouds_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pointclouds_insert_trigger INSTEAD OF INSERT ON public.pointclouds FOR EACH ROW EXECUTE FUNCTION public.pointclouds_insert();


--
-- Name: sensor_tree_links sensor_tree_links_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sensor_tree_links_insert_trigger INSTEAD OF INSERT ON public.sensor_tree_links FOR EACH ROW EXECUTE FUNCTION public.sensor_tree_links_insert();


--
-- Name: sensorreadings sensorreadings_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sensorreadings_insert_trigger INSTEAD OF INSERT ON public.sensorreadings FOR EACH ROW EXECUTE FUNCTION public.sensorreadings_insert();


--
-- Name: sensors sensors_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sensors_delete_trigger INSTEAD OF DELETE ON public.sensors FOR EACH ROW EXECUTE FUNCTION public.sensors_delete();


--
-- Name: sensors sensors_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sensors_insert_trigger INSTEAD OF INSERT ON public.sensors FOR EACH ROW EXECUTE FUNCTION public.sensors_insert();


--
-- Name: sensors sensors_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sensors_update_trigger INSTEAD OF UPDATE ON public.sensors FOR EACH ROW EXECUTE FUNCTION public.sensors_update();


--
-- Name: stems stems_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stems_insert_trigger INSTEAD OF INSERT ON public.stems FOR EACH ROW EXECUTE FUNCTION public.stems_insert();


--
-- Name: trees trees_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trees_delete_trigger INSTEAD OF DELETE ON public.trees FOR EACH ROW EXECUTE FUNCTION public.trees_delete();


--
-- Name: trees trees_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trees_insert_trigger INSTEAD OF INSERT ON public.trees FOR EACH ROW EXECUTE FUNCTION public.trees_insert();


--
-- Name: trees trees_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trees_update_trigger INSTEAD OF UPDATE ON public.trees FOR EACH ROW EXECUTE FUNCTION public.trees_update();


--
-- Name: sensors trigger_sensors_created_by; Type: TRIGGER; Schema: sensor; Owner: -
--

CREATE TRIGGER trigger_sensors_created_by BEFORE INSERT ON sensor.sensors FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: sensors trigger_sensors_updated_at; Type: TRIGGER; Schema: sensor; Owner: -
--

CREATE TRIGGER trigger_sensors_updated_at BEFORE UPDATE ON sensor.sensors FOR EACH ROW EXECUTE FUNCTION sensor.update_updated_at_column();


--
-- Name: sensors trigger_sensors_updated_by; Type: TRIGGER; Schema: sensor; Owner: -
--

CREATE TRIGGER trigger_sensors_updated_by BEFORE UPDATE ON sensor.sensors FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: campaigns trigger_campaigns_created_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_campaigns_created_by BEFORE INSERT ON shared.campaigns FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: campaigns trigger_campaigns_updated_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_campaigns_updated_by BEFORE UPDATE ON shared.campaigns FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: disturbanceevents trigger_dist_events_created_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_dist_events_created_by BEFORE INSERT ON shared.disturbanceevents FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: disturbanceevents trigger_dist_events_updated_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_dist_events_updated_by BEFORE UPDATE ON shared.disturbanceevents FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: locations trigger_locations_created_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_locations_created_by BEFORE INSERT ON shared.locations FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: locations trigger_locations_updated_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_locations_updated_by BEFORE UPDATE ON shared.locations FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: managementevents trigger_mgmt_events_created_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_mgmt_events_created_by BEFORE INSERT ON shared.managementevents FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: managementevents trigger_mgmt_events_updated_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_mgmt_events_updated_by BEFORE UPDATE ON shared.managementevents FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: plots trigger_plots_created_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_plots_created_by BEFORE INSERT ON shared.plots FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: plots trigger_plots_updated_by; Type: TRIGGER; Schema: shared; Owner: -
--

CREATE TRIGGER trigger_plots_updated_by BEFORE UPDATE ON shared.plots FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: trees trg_trees_assign_height_class; Type: TRIGGER; Schema: trees; Owner: -
--

CREATE TRIGGER trg_trees_assign_height_class BEFORE INSERT OR UPDATE OF height_m ON trees.trees FOR EACH ROW EXECUTE FUNCTION trees.assign_height_class();


--
-- Name: stems trigger_stems_audit; Type: TRIGGER; Schema: trees; Owner: -
--

CREATE TRIGGER trigger_stems_audit AFTER UPDATE ON trees.stems FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: stems trigger_stems_updated_at; Type: TRIGGER; Schema: trees; Owner: -
--

CREATE TRIGGER trigger_stems_updated_at BEFORE UPDATE ON trees.stems FOR EACH ROW EXECUTE FUNCTION trees.update_updated_at_column();


--
-- Name: trees trigger_trees_audit; Type: TRIGGER; Schema: trees; Owner: -
--

CREATE TRIGGER trigger_trees_audit AFTER UPDATE ON trees.trees FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: trees trigger_trees_created_by; Type: TRIGGER; Schema: trees; Owner: -
--

CREATE TRIGGER trigger_trees_created_by BEFORE INSERT ON trees.trees FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: trees trigger_trees_updated_at; Type: TRIGGER; Schema: trees; Owner: -
--

CREATE TRIGGER trigger_trees_updated_at BEFORE UPDATE ON trees.trees FOR EACH ROW EXECUTE FUNCTION trees.update_updated_at_column();


--
-- Name: trees trigger_trees_updated_by; Type: TRIGGER; Schema: trees; Owner: -
--

CREATE TRIGGER trigger_trees_updated_by BEFORE UPDATE ON trees.trees FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: environments environments_location_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: -
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: environments environments_parent_environment_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: -
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_parent_environment_id_fkey FOREIGN KEY (parent_environment_id) REFERENCES environments.environments(environment_id) ON DELETE SET NULL;


--
-- Name: environments environments_process_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: -
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: environments environments_scenario_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: -
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: environments environments_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: -
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.varianttypes(variant_type_id);


--
-- Name: images images_campaign_id_fkey; Type: FK CONSTRAINT; Schema: imagery; Owner: -
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: images images_location_id_fkey; Type: FK CONSTRAINT; Schema: imagery; Owner: -
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: images images_plot_id_fkey; Type: FK CONSTRAINT; Schema: imagery; Owner: -
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: pointclouds pointclouds_campaign_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: pointclouds pointclouds_location_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: pointclouds pointclouds_parent_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_parent_point_cloud_id_fkey FOREIGN KEY (parent_point_cloud_id) REFERENCES pointclouds.pointclouds(point_cloud_id) ON DELETE SET NULL;


--
-- Name: pointclouds pointclouds_process_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: pointclouds pointclouds_scanner_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_scanner_id_fkey FOREIGN KEY (scanner_id) REFERENCES pointclouds.scanners(scanner_id) ON DELETE SET NULL;


--
-- Name: pointclouds pointclouds_scenario_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: pointclouds pointclouds_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.pointclouds
    ADD CONSTRAINT pointclouds_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.varianttypes(variant_type_id);


--
-- Name: scanners scanners_scanner_type_id_fkey; Type: FK CONSTRAINT; Schema: pointclouds; Owner: -
--

ALTER TABLE ONLY pointclouds.scanners
    ADD CONSTRAINT scanners_scanner_type_id_fkey FOREIGN KEY (scanner_type_id) REFERENCES pointclouds.scannertypes(scanner_type_id);


--
-- Name: sensor_tree_links sensor_tree_links_sensor_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_sensor_id_fkey FOREIGN KEY (sensor_id) REFERENCES sensor.sensors(sensor_id) ON DELETE CASCADE;


--
-- Name: sensor_tree_links sensor_tree_links_tree_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: sensorreadings sensorreadings_scenario_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensorreadings
    ADD CONSTRAINT sensorreadings_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: sensorreadings sensorreadings_sensor_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensorreadings
    ADD CONSTRAINT sensorreadings_sensor_id_fkey FOREIGN KEY (sensor_id) REFERENCES sensor.sensors(sensor_id) ON DELETE CASCADE;


--
-- Name: sensors sensors_campaign_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: sensors sensors_location_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: sensors sensors_plot_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: sensors sensors_sensor_type_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: -
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_sensor_type_id_fkey FOREIGN KEY (sensor_type_id) REFERENCES sensor.sensortypes(sensor_type_id);


--
-- Name: auditlog_environments auditlog_environments_audit_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_environments
    ADD CONSTRAINT auditlog_environments_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES shared.auditlog(audit_id) ON DELETE CASCADE;


--
-- Name: auditlog_environments auditlog_environments_environment_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_environments
    ADD CONSTRAINT auditlog_environments_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES environments.environments(environment_id) ON DELETE CASCADE;


--
-- Name: auditlog_pointclouds auditlog_pointclouds_audit_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_pointclouds
    ADD CONSTRAINT auditlog_pointclouds_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES shared.auditlog(audit_id) ON DELETE CASCADE;


--
-- Name: auditlog_pointclouds auditlog_pointclouds_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_pointclouds
    ADD CONSTRAINT auditlog_pointclouds_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES pointclouds.pointclouds(point_cloud_id) ON DELETE CASCADE;


--
-- Name: auditlog_stems auditlog_stems_audit_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_stems
    ADD CONSTRAINT auditlog_stems_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES shared.auditlog(audit_id) ON DELETE CASCADE;


--
-- Name: auditlog_stems auditlog_stems_stem_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_stems
    ADD CONSTRAINT auditlog_stems_stem_id_fkey FOREIGN KEY (stem_id) REFERENCES trees.stems(stem_id) ON DELETE CASCADE;


--
-- Name: auditlog_trees auditlog_trees_audit_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_trees
    ADD CONSTRAINT auditlog_trees_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES shared.auditlog(audit_id) ON DELETE CASCADE;


--
-- Name: auditlog_trees auditlog_trees_tree_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.auditlog_trees
    ADD CONSTRAINT auditlog_trees_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: campaigns campaigns_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.campaigns
    ADD CONSTRAINT campaigns_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE SET NULL;


--
-- Name: disturbanceevents disturbanceevents_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.disturbanceevents
    ADD CONSTRAINT disturbanceevents_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: disturbanceevents disturbanceevents_plot_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.disturbanceevents
    ADD CONSTRAINT disturbanceevents_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: disturbanceevents_trees disturbanceevents_trees_disturbance_event_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.disturbanceevents_trees
    ADD CONSTRAINT disturbanceevents_trees_disturbance_event_id_fkey FOREIGN KEY (disturbance_event_id) REFERENCES shared.disturbanceevents(disturbance_event_id) ON DELETE CASCADE;


--
-- Name: disturbanceevents_trees disturbanceevents_trees_tree_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.disturbanceevents_trees
    ADD CONSTRAINT disturbanceevents_trees_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: locations locations_climate_zone_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_climate_zone_id_fkey FOREIGN KEY (climate_zone_id) REFERENCES shared.climatezones(climate_zone_id);


--
-- Name: locations locations_soil_type_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_soil_type_id_fkey FOREIGN KEY (soil_type_id) REFERENCES shared.soiltypes(soil_type_id);


--
-- Name: managementevents managementevents_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.managementevents
    ADD CONSTRAINT managementevents_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: managementevents managementevents_plot_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.managementevents
    ADD CONSTRAINT managementevents_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: plots plots_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: processmetrics processmetrics_process_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processmetrics
    ADD CONSTRAINT processmetrics_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE CASCADE;


--
-- Name: processparameters_environments processparameters_environments_environment_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_environments
    ADD CONSTRAINT processparameters_environments_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES environments.environments(environment_id) ON DELETE CASCADE;


--
-- Name: processparameters_environments processparameters_environments_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_environments
    ADD CONSTRAINT processparameters_environments_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.processparameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: processparameters_pointclouds processparameters_pointclouds_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_pointclouds
    ADD CONSTRAINT processparameters_pointclouds_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES pointclouds.pointclouds(point_cloud_id) ON DELETE CASCADE;


--
-- Name: processparameters_pointclouds processparameters_pointclouds_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_pointclouds
    ADD CONSTRAINT processparameters_pointclouds_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.processparameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: processparameters_stems processparameters_stems_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_stems
    ADD CONSTRAINT processparameters_stems_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.processparameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: processparameters_stems processparameters_stems_stem_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_stems
    ADD CONSTRAINT processparameters_stems_stem_id_fkey FOREIGN KEY (stem_id) REFERENCES trees.stems(stem_id) ON DELETE CASCADE;


--
-- Name: processparameters_trees processparameters_trees_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_trees
    ADD CONSTRAINT processparameters_trees_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.processparameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: processparameters_trees processparameters_trees_tree_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.processparameters_trees
    ADD CONSTRAINT processparameters_trees_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: scenarios scenarios_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: variants variants_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: variants variants_parent_variant_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_parent_variant_id_fkey FOREIGN KEY (parent_variant_id) REFERENCES shared.variants(variant_id) ON DELETE SET NULL;


--
-- Name: variants variants_scenario_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE CASCADE;


--
-- Name: variants variants_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: -
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.varianttypes(variant_type_id);


--
-- Name: deadwood deadwood_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.deadwood
    ADD CONSTRAINT deadwood_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: deadwood deadwood_plot_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.deadwood
    ADD CONSTRAINT deadwood_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: deadwood deadwood_species_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.deadwood
    ADD CONSTRAINT deadwood_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: deadwood deadwood_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.deadwood
    ADD CONSTRAINT deadwood_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE SET NULL;


--
-- Name: groundvegetation groundvegetation_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.groundvegetation
    ADD CONSTRAINT groundvegetation_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: groundvegetation groundvegetation_plot_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.groundvegetation
    ADD CONSTRAINT groundvegetation_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: growthsimulations growthsimulations_base_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthsimulations
    ADD CONSTRAINT growthsimulations_base_tree_id_fkey FOREIGN KEY (base_tree_id) REFERENCES trees.trees(tree_id) ON DELETE SET NULL;


--
-- Name: growthsimulations growthsimulations_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthsimulations
    ADD CONSTRAINT growthsimulations_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: growthsimulations growthsimulations_plot_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthsimulations
    ADD CONSTRAINT growthsimulations_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: growthsimulations growthsimulations_scenario_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthsimulations
    ADD CONSTRAINT growthsimulations_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: growthsimulations growthsimulations_species_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.growthsimulations
    ADD CONSTRAINT growthsimulations_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: phenologyobservations phenologyobservations_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.phenologyobservations
    ADD CONSTRAINT phenologyobservations_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: stems stems_straightness_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_straightness_type_id_fkey FOREIGN KEY (straightness_type_id) REFERENCES trees.straightnesstypes(straightness_type_id);


--
-- Name: stems stems_taper_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_taper_type_id_fkey FOREIGN KEY (taper_type_id) REFERENCES trees.tapertypes(taper_type_id);


--
-- Name: stems stems_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: trees trees_axis_structure_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_axis_structure_id_fkey FOREIGN KEY (axis_structure_id) REFERENCES trees.axisstructures(axis_structure_id);


--
-- Name: trees trees_bark_characteristic_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_bark_characteristic_id_fkey FOREIGN KEY (bark_characteristic_id) REFERENCES trees.barkcharacteristics(bark_characteristic_id);


--
-- Name: trees trees_branching_pattern_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_branching_pattern_id_fkey FOREIGN KEY (branching_pattern_id) REFERENCES trees.branchingpatterns(branching_pattern_id);


--
-- Name: trees trees_campaign_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: trees trees_crown_architecture_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_crown_architecture_id_fkey FOREIGN KEY (crown_architecture_id) REFERENCES trees.crownarchitectures(crown_architecture_id);


--
-- Name: trees trees_crown_class_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_crown_class_id_fkey FOREIGN KEY (crown_class_id) REFERENCES trees.crownclasses(crown_class_id);


--
-- Name: trees trees_crown_shape_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_crown_shape_id_fkey FOREIGN KEY (crown_shape_id) REFERENCES trees.crownshapes(crown_shape_id);


--
-- Name: trees trees_damage_agent_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_damage_agent_id_fkey FOREIGN KEY (damage_agent_id) REFERENCES trees.damageagents(damage_agent_id);


--
-- Name: trees trees_data_source_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_data_source_type_id_fkey FOREIGN KEY (data_source_type_id) REFERENCES trees.datasourcetypes(data_source_type_id) ON DELETE SET NULL;


--
-- Name: trees trees_elongation_habit_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_elongation_habit_id_fkey FOREIGN KEY (elongation_habit_id) REFERENCES trees.branchelongationhabits(branch_elongation_habit_id);


--
-- Name: trees trees_geometric_solid_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_geometric_solid_id_fkey FOREIGN KEY (geometric_solid_id) REFERENCES trees.geometriccrownsolids(geometric_solid_id);


--
-- Name: trees trees_growth_form_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_growth_form_id_fkey FOREIGN KEY (growth_form_id) REFERENCES trees.growthforms(growth_form_id);


--
-- Name: trees trees_growth_orientation_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_growth_orientation_id_fkey FOREIGN KEY (growth_orientation_id) REFERENCES trees.growthorientations(growth_orientation_id);


--
-- Name: trees trees_height_class_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_height_class_id_fkey FOREIGN KEY (height_class_id) REFERENCES trees.phanerophyteheightclasses(phanerophyte_height_class_id);


--
-- Name: trees trees_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: trees trees_parent_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_parent_tree_id_fkey FOREIGN KEY (parent_tree_id) REFERENCES trees.trees(tree_id) ON DELETE SET NULL;


--
-- Name: trees trees_plot_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: trees trees_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES pointclouds.pointclouds(point_cloud_id) ON DELETE SET NULL;


--
-- Name: trees trees_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: trees trees_scenario_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: trees trees_shoot_elongation_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_shoot_elongation_type_id_fkey FOREIGN KEY (shoot_elongation_type_id) REFERENCES trees.shootelongationtypes(shoot_elongation_type_id);


--
-- Name: trees trees_species_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: trees trees_tree_status_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_tree_status_id_fkey FOREIGN KEY (tree_status_id) REFERENCES trees.treestatus(tree_status_id);


--
-- Name: trees trees_variant_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES shared.variants(variant_id) ON DELETE SET NULL;


--
-- Name: trees trees_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: -
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.varianttypes(variant_type_id);


--
-- Name: environments Contributors can create environments; Type: POLICY; Schema: environments; Owner: -
--

CREATE POLICY "Contributors can create environments" ON environments.environments FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: environments Curators can delete environments; Type: POLICY; Schema: environments; Owner: -
--

CREATE POLICY "Curators can delete environments" ON environments.environments FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: environments Curators can update environments; Type: POLICY; Schema: environments; Owner: -
--

CREATE POLICY "Curators can update environments" ON environments.environments FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: environments Environments are viewable by everyone; Type: POLICY; Schema: environments; Owner: -
--

CREATE POLICY "Environments are viewable by everyone" ON environments.environments FOR SELECT USING (true);


--
-- Name: POLICY "Environments are viewable by everyone" ON environments; Type: COMMENT; Schema: environments; Owner: -
--

COMMENT ON POLICY "Environments are viewable by everyone" ON environments.environments IS 'Public read access to environmental conditions';


--
-- Name: environments Service role can manage all environments; Type: POLICY; Schema: environments; Owner: -
--

CREATE POLICY "Service role can manage all environments" ON environments.environments TO service_role USING (true) WITH CHECK (true);


--
-- Name: environments; Type: ROW SECURITY; Schema: environments; Owner: -
--

ALTER TABLE environments.environments ENABLE ROW LEVEL SECURITY;

--
-- Name: images Contributors can create images; Type: POLICY; Schema: imagery; Owner: -
--

CREATE POLICY "Contributors can create images" ON imagery.images FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: images Curators can delete images; Type: POLICY; Schema: imagery; Owner: -
--

CREATE POLICY "Curators can delete images" ON imagery.images FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: images Curators can update images; Type: POLICY; Schema: imagery; Owner: -
--

CREATE POLICY "Curators can update images" ON imagery.images FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: images Images are viewable by everyone; Type: POLICY; Schema: imagery; Owner: -
--

CREATE POLICY "Images are viewable by everyone" ON imagery.images FOR SELECT USING (true);


--
-- Name: images Service role can manage all images; Type: POLICY; Schema: imagery; Owner: -
--

CREATE POLICY "Service role can manage all images" ON imagery.images TO service_role USING (true) WITH CHECK (true);


--
-- Name: images; Type: ROW SECURITY; Schema: imagery; Owner: -
--

ALTER TABLE imagery.images ENABLE ROW LEVEL SECURITY;

--
-- Name: scanners Authenticated users can manage scanners; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Authenticated users can manage scanners" ON pointclouds.scanners TO authenticated USING (true) WITH CHECK (true);


--
-- Name: pointclouds Contributors can create point clouds; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Contributors can create point clouds" ON pointclouds.pointclouds FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: pointclouds Curators can delete point clouds; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Curators can delete point clouds" ON pointclouds.pointclouds FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: pointclouds Curators can update point clouds; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Curators can update point clouds" ON pointclouds.pointclouds FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: pointclouds Point clouds are viewable by everyone; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Point clouds are viewable by everyone" ON pointclouds.pointclouds FOR SELECT USING (true);


--
-- Name: POLICY "Point clouds are viewable by everyone" ON pointclouds; Type: COMMENT; Schema: pointclouds; Owner: -
--

COMMENT ON POLICY "Point clouds are viewable by everyone" ON pointclouds.pointclouds IS 'Public read access to point cloud metadata';


--
-- Name: scannertypes Scanner types are viewable by everyone; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Scanner types are viewable by everyone" ON pointclouds.scannertypes FOR SELECT USING (true);


--
-- Name: scanners Scanners are viewable by everyone; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Scanners are viewable by everyone" ON pointclouds.scanners FOR SELECT USING (true);


--
-- Name: pointclouds Service role can manage all point clouds; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Service role can manage all point clouds" ON pointclouds.pointclouds TO service_role USING (true) WITH CHECK (true);


--
-- Name: scanners Service role can manage all scanners; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Service role can manage all scanners" ON pointclouds.scanners TO service_role USING (true) WITH CHECK (true);


--
-- Name: scannertypes Service role can manage scanner types; Type: POLICY; Schema: pointclouds; Owner: -
--

CREATE POLICY "Service role can manage scanner types" ON pointclouds.scannertypes TO service_role USING (true) WITH CHECK (true);


--
-- Name: pointclouds; Type: ROW SECURITY; Schema: pointclouds; Owner: -
--

ALTER TABLE pointclouds.pointclouds ENABLE ROW LEVEL SECURITY;

--
-- Name: scanners; Type: ROW SECURITY; Schema: pointclouds; Owner: -
--

ALTER TABLE pointclouds.scanners ENABLE ROW LEVEL SECURITY;

--
-- Name: scannertypes; Type: ROW SECURITY; Schema: pointclouds; Owner: -
--

ALTER TABLE pointclouds.scannertypes ENABLE ROW LEVEL SECURITY;

--
-- Name: sensors Authenticated users can manage sensors; Type: POLICY; Schema: sensor; Owner: -
--

CREATE POLICY "Authenticated users can manage sensors" ON sensor.sensors TO authenticated USING (true) WITH CHECK (true);


--
-- Name: sensorreadings Contributors can insert sensor readings; Type: POLICY; Schema: sensor; Owner: -
--

CREATE POLICY "Contributors can insert sensor readings" ON sensor.sensorreadings FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: sensorreadings Sensor readings are viewable by everyone; Type: POLICY; Schema: sensor; Owner: -
--

CREATE POLICY "Sensor readings are viewable by everyone" ON sensor.sensorreadings FOR SELECT USING (true);


--
-- Name: sensortypes Sensor types are viewable by everyone; Type: POLICY; Schema: sensor; Owner: -
--

CREATE POLICY "Sensor types are viewable by everyone" ON sensor.sensortypes FOR SELECT USING (true);


--
-- Name: sensors Sensors are viewable by everyone; Type: POLICY; Schema: sensor; Owner: -
--

CREATE POLICY "Sensors are viewable by everyone" ON sensor.sensors FOR SELECT USING (true);


--
-- Name: sensorreadings Service role can manage all sensor readings; Type: POLICY; Schema: sensor; Owner: -
--

CREATE POLICY "Service role can manage all sensor readings" ON sensor.sensorreadings TO service_role USING (true) WITH CHECK (true);


--
-- Name: sensorreadings; Type: ROW SECURITY; Schema: sensor; Owner: -
--

ALTER TABLE sensor.sensorreadings ENABLE ROW LEVEL SECURITY;

--
-- Name: sensors; Type: ROW SECURITY; Schema: sensor; Owner: -
--

ALTER TABLE sensor.sensors ENABLE ROW LEVEL SECURITY;

--
-- Name: sensortypes; Type: ROW SECURITY; Schema: sensor; Owner: -
--

ALTER TABLE sensor.sensortypes ENABLE ROW LEVEL SECURITY;

--
-- Name: auditlog_environments Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.auditlog_environments FOR SELECT TO authenticated USING (true);


--
-- Name: auditlog_pointclouds Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.auditlog_pointclouds FOR SELECT TO authenticated USING (true);


--
-- Name: auditlog_stems Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.auditlog_stems FOR SELECT TO authenticated USING (true);


--
-- Name: auditlog_trees Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.auditlog_trees FOR SELECT TO authenticated USING (true);


--
-- Name: locations Authenticated users can insert locations; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can insert locations" ON shared.locations FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: campaigns Authenticated users can manage campaigns; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage campaigns" ON shared.campaigns TO authenticated USING (true) WITH CHECK (true);


--
-- Name: disturbanceevents Authenticated users can manage disturbance events; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage disturbance events" ON shared.disturbanceevents TO authenticated USING (true) WITH CHECK (true);


--
-- Name: disturbanceevents_trees Authenticated users can manage disturbance tree links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage disturbance tree links" ON shared.disturbanceevents_trees TO authenticated USING (true) WITH CHECK (true);


--
-- Name: managementevents Authenticated users can manage management events; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage management events" ON shared.managementevents TO authenticated USING (true) WITH CHECK (true);


--
-- Name: plots Authenticated users can manage plots; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage plots" ON shared.plots TO authenticated USING (true) WITH CHECK (true);


--
-- Name: processmetrics Authenticated users can manage process metrics; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage process metrics" ON shared.processmetrics TO authenticated USING (true) WITH CHECK (true);


--
-- Name: processparameters_environments Authenticated users can manage process parameter links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage process parameter links" ON shared.processparameters_environments TO authenticated USING (true) WITH CHECK (true);


--
-- Name: processparameters_pointclouds Authenticated users can manage process parameter links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage process parameter links" ON shared.processparameters_pointclouds TO authenticated USING (true) WITH CHECK (true);


--
-- Name: processparameters_stems Authenticated users can manage process parameter links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage process parameter links" ON shared.processparameters_stems TO authenticated USING (true) WITH CHECK (true);


--
-- Name: processparameters_trees Authenticated users can manage process parameter links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage process parameter links" ON shared.processparameters_trees TO authenticated USING (true) WITH CHECK (true);


--
-- Name: processparameters Authenticated users can manage process parameters; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage process parameters" ON shared.processparameters TO authenticated USING (true) WITH CHECK (true);


--
-- Name: processes Authenticated users can manage processes; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage processes" ON shared.processes TO authenticated USING (true) WITH CHECK (true);


--
-- Name: scenarios Authenticated users can manage scenarios; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage scenarios" ON shared.scenarios TO authenticated USING (true) WITH CHECK (true);


--
-- Name: species Authenticated users can manage species; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can manage species" ON shared.species TO authenticated USING (true) WITH CHECK (true);


--
-- Name: locations Authenticated users can update locations; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Authenticated users can update locations" ON shared.locations FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: campaigns Campaigns are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Campaigns are viewable by everyone" ON shared.campaigns FOR SELECT USING (true);


--
-- Name: disturbanceevents Disturbance events are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Disturbance events are viewable by everyone" ON shared.disturbanceevents FOR SELECT USING (true);


--
-- Name: disturbanceevents_trees Disturbance tree links are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Disturbance tree links are viewable by everyone" ON shared.disturbanceevents_trees FOR SELECT USING (true);


--
-- Name: processingjobs Enable all for service_role; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Enable all for service_role" ON shared.processingjobs TO service_role USING (true) WITH CHECK (true);


--
-- Name: processingjobs Enable read for authenticated users; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Enable read for authenticated users" ON shared.processingjobs FOR SELECT TO authenticated USING (true);


--
-- Name: locations Locations are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Locations are viewable by everyone" ON shared.locations FOR SELECT USING (true);


--
-- Name: POLICY "Locations are viewable by everyone" ON locations; Type: COMMENT; Schema: shared; Owner: -
--

COMMENT ON POLICY "Locations are viewable by everyone" ON shared.locations IS 'Public read access to location data';


--
-- Name: managementevents Management events are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Management events are viewable by everyone" ON shared.managementevents FOR SELECT USING (true);


--
-- Name: plots Plots are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Plots are viewable by everyone" ON shared.plots FOR SELECT USING (true);


--
-- Name: processmetrics Process metrics are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Process metrics are viewable by everyone" ON shared.processmetrics FOR SELECT USING (true);


--
-- Name: processparameters_environments Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.processparameters_environments FOR SELECT USING (true);


--
-- Name: processparameters_pointclouds Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.processparameters_pointclouds FOR SELECT USING (true);


--
-- Name: processparameters_stems Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.processparameters_stems FOR SELECT USING (true);


--
-- Name: processparameters_trees Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.processparameters_trees FOR SELECT USING (true);


--
-- Name: processparameters Process parameters are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Process parameters are viewable by everyone" ON shared.processparameters FOR SELECT USING (true);


--
-- Name: processes Processes are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Processes are viewable by everyone" ON shared.processes FOR SELECT USING (true);


--
-- Name: climatezones Reference tables are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Reference tables are viewable by everyone" ON shared.climatezones FOR SELECT USING (true);


--
-- Name: soiltypes Reference tables are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Reference tables are viewable by everyone" ON shared.soiltypes FOR SELECT USING (true);


--
-- Name: varianttypes Reference tables are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Reference tables are viewable by everyone" ON shared.varianttypes FOR SELECT USING (true);


--
-- Name: scenarios Scenarios are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Scenarios are viewable by everyone" ON shared.scenarios FOR SELECT USING (true);


--
-- Name: campaigns Service role can manage all campaigns; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage all campaigns" ON shared.campaigns TO service_role USING (true) WITH CHECK (true);


--
-- Name: disturbanceevents Service role can manage all disturbance events; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage all disturbance events" ON shared.disturbanceevents TO service_role USING (true) WITH CHECK (true);


--
-- Name: disturbanceevents_trees Service role can manage all disturbance tree links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage all disturbance tree links" ON shared.disturbanceevents_trees TO service_role USING (true) WITH CHECK (true);


--
-- Name: managementevents Service role can manage all management events; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage all management events" ON shared.managementevents TO service_role USING (true) WITH CHECK (true);


--
-- Name: plots Service role can manage all plots; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage all plots" ON shared.plots TO service_role USING (true) WITH CHECK (true);


--
-- Name: auditlog_environments Service role can manage audit links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage audit links" ON shared.auditlog_environments TO service_role USING (true) WITH CHECK (true);


--
-- Name: auditlog_pointclouds Service role can manage audit links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage audit links" ON shared.auditlog_pointclouds TO service_role USING (true) WITH CHECK (true);


--
-- Name: auditlog_stems Service role can manage audit links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage audit links" ON shared.auditlog_stems TO service_role USING (true) WITH CHECK (true);


--
-- Name: auditlog_trees Service role can manage audit links; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage audit links" ON shared.auditlog_trees TO service_role USING (true) WITH CHECK (true);


--
-- Name: auditlog Service role can manage audit logs; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Service role can manage audit logs" ON shared.auditlog TO service_role USING (true) WITH CHECK (true);


--
-- Name: species Species are viewable by everyone; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Species are viewable by everyone" ON shared.species FOR SELECT USING (true);


--
-- Name: auditlog Users can view their own audit logs; Type: POLICY; Schema: shared; Owner: -
--

CREATE POLICY "Users can view their own audit logs" ON shared.auditlog FOR SELECT TO authenticated USING ((((user_id)::text = (auth.uid())::text) OR (user_id IS NULL)));


--
-- Name: auditlog; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.auditlog ENABLE ROW LEVEL SECURITY;

--
-- Name: auditlog_environments; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.auditlog_environments ENABLE ROW LEVEL SECURITY;

--
-- Name: auditlog_pointclouds; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.auditlog_pointclouds ENABLE ROW LEVEL SECURITY;

--
-- Name: auditlog_stems; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.auditlog_stems ENABLE ROW LEVEL SECURITY;

--
-- Name: auditlog_trees; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.auditlog_trees ENABLE ROW LEVEL SECURITY;

--
-- Name: campaigns; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.campaigns ENABLE ROW LEVEL SECURITY;

--
-- Name: climatezones; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.climatezones ENABLE ROW LEVEL SECURITY;

--
-- Name: disturbanceevents; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.disturbanceevents ENABLE ROW LEVEL SECURITY;

--
-- Name: disturbanceevents_trees; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.disturbanceevents_trees ENABLE ROW LEVEL SECURITY;

--
-- Name: locations; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.locations ENABLE ROW LEVEL SECURITY;

--
-- Name: managementevents; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.managementevents ENABLE ROW LEVEL SECURITY;

--
-- Name: plots; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.plots ENABLE ROW LEVEL SECURITY;

--
-- Name: processes; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processes ENABLE ROW LEVEL SECURITY;

--
-- Name: processingjobs; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processingjobs ENABLE ROW LEVEL SECURITY;

--
-- Name: processmetrics; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processmetrics ENABLE ROW LEVEL SECURITY;

--
-- Name: processparameters; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processparameters ENABLE ROW LEVEL SECURITY;

--
-- Name: processparameters_environments; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processparameters_environments ENABLE ROW LEVEL SECURITY;

--
-- Name: processparameters_pointclouds; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processparameters_pointclouds ENABLE ROW LEVEL SECURITY;

--
-- Name: processparameters_stems; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processparameters_stems ENABLE ROW LEVEL SECURITY;

--
-- Name: processparameters_trees; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.processparameters_trees ENABLE ROW LEVEL SECURITY;

--
-- Name: scenarios; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.scenarios ENABLE ROW LEVEL SECURITY;

--
-- Name: soiltypes; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.soiltypes ENABLE ROW LEVEL SECURITY;

--
-- Name: species; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.species ENABLE ROW LEVEL SECURITY;

--
-- Name: varianttypes; Type: ROW SECURITY; Schema: shared; Owner: -
--

ALTER TABLE shared.varianttypes ENABLE ROW LEVEL SECURITY;

--
-- Name: deadwood Contributors can create deadwood records; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Contributors can create deadwood records" ON trees.deadwood FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: groundvegetation Contributors can create ground vegetation records; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Contributors can create ground vegetation records" ON trees.groundvegetation FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: phenologyobservations Contributors can create phenology observations; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Contributors can create phenology observations" ON trees.phenologyobservations FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: stems Contributors can create stems; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Contributors can create stems" ON trees.stems FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: trees Contributors can create trees; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Contributors can create trees" ON trees.trees FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: deadwood Curators can delete deadwood records; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can delete deadwood records" ON trees.deadwood FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: groundvegetation Curators can delete ground vegetation records; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can delete ground vegetation records" ON trees.groundvegetation FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: phenologyobservations Curators can delete phenology observations; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can delete phenology observations" ON trees.phenologyobservations FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: stems Curators can delete stems; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can delete stems" ON trees.stems FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: trees Curators can delete trees; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can delete trees" ON trees.trees FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: deadwood Curators can update deadwood records; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can update deadwood records" ON trees.deadwood FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: groundvegetation Curators can update ground vegetation records; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can update ground vegetation records" ON trees.groundvegetation FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: phenologyobservations Curators can update phenology observations; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can update phenology observations" ON trees.phenologyobservations FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: stems Curators can update stems; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can update stems" ON trees.stems FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: trees Curators can update trees; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Curators can update trees" ON trees.trees FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: deadwood Deadwood records are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Deadwood records are viewable by everyone" ON trees.deadwood FOR SELECT USING (true);


--
-- Name: groundvegetation Ground vegetation records are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Ground vegetation records are viewable by everyone" ON trees.groundvegetation FOR SELECT USING (true);


--
-- Name: phenologyobservations Phenology observations are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Phenology observations are viewable by everyone" ON trees.phenologyobservations FOR SELECT USING (true);


--
-- Name: deadwood Service role can manage all deadwood records; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Service role can manage all deadwood records" ON trees.deadwood TO service_role USING (true) WITH CHECK (true);


--
-- Name: groundvegetation Service role can manage all ground vegetation; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Service role can manage all ground vegetation" ON trees.groundvegetation TO service_role USING (true) WITH CHECK (true);


--
-- Name: phenologyobservations Service role can manage all phenology observations; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Service role can manage all phenology observations" ON trees.phenologyobservations TO service_role USING (true) WITH CHECK (true);


--
-- Name: stems Service role can manage all stems; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Service role can manage all stems" ON trees.stems TO service_role USING (true) WITH CHECK (true);


--
-- Name: trees Service role can manage all trees; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Service role can manage all trees" ON trees.trees TO service_role USING (true) WITH CHECK (true);


--
-- Name: stems Stems are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Stems are viewable by everyone" ON trees.stems FOR SELECT USING (true);


--
-- Name: axisstructures Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.axisstructures FOR SELECT USING (true);


--
-- Name: barkcharacteristics Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.barkcharacteristics FOR SELECT USING (true);


--
-- Name: branchelongationhabits Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.branchelongationhabits FOR SELECT USING (true);


--
-- Name: branchingpatterns Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.branchingpatterns FOR SELECT USING (true);


--
-- Name: crownarchitectures Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.crownarchitectures FOR SELECT USING (true);


--
-- Name: crownclasses Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.crownclasses FOR SELECT USING (true);


--
-- Name: crownshapes Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.crownshapes FOR SELECT USING (true);


--
-- Name: damageagents Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.damageagents FOR SELECT USING (true);


--
-- Name: geometriccrownsolids Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.geometriccrownsolids FOR SELECT USING (true);


--
-- Name: growthforms Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.growthforms FOR SELECT USING (true);


--
-- Name: growthorientations Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.growthorientations FOR SELECT USING (true);


--
-- Name: phanerophyteheightclasses Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.phanerophyteheightclasses FOR SELECT USING (true);


--
-- Name: shootelongationtypes Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.shootelongationtypes FOR SELECT USING (true);


--
-- Name: straightnesstypes Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.straightnesstypes FOR SELECT USING (true);


--
-- Name: tapertypes Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.tapertypes FOR SELECT USING (true);


--
-- Name: treestatus Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.treestatus FOR SELECT USING (true);


--
-- Name: trees Trees are viewable by everyone; Type: POLICY; Schema: trees; Owner: -
--

CREATE POLICY "Trees are viewable by everyone" ON trees.trees FOR SELECT USING (true);


--
-- Name: POLICY "Trees are viewable by everyone" ON trees; Type: COMMENT; Schema: trees; Owner: -
--

COMMENT ON POLICY "Trees are viewable by everyone" ON trees.trees IS 'Public read access to tree measurement data';


--
-- Name: axisstructures; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.axisstructures ENABLE ROW LEVEL SECURITY;

--
-- Name: barkcharacteristics; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.barkcharacteristics ENABLE ROW LEVEL SECURITY;

--
-- Name: branchelongationhabits; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.branchelongationhabits ENABLE ROW LEVEL SECURITY;

--
-- Name: branchingpatterns; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.branchingpatterns ENABLE ROW LEVEL SECURITY;

--
-- Name: crownarchitectures; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.crownarchitectures ENABLE ROW LEVEL SECURITY;

--
-- Name: crownclasses; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.crownclasses ENABLE ROW LEVEL SECURITY;

--
-- Name: crownshapes; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.crownshapes ENABLE ROW LEVEL SECURITY;

--
-- Name: damageagents; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.damageagents ENABLE ROW LEVEL SECURITY;

--
-- Name: deadwood; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.deadwood ENABLE ROW LEVEL SECURITY;

--
-- Name: geometriccrownsolids; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.geometriccrownsolids ENABLE ROW LEVEL SECURITY;

--
-- Name: groundvegetation; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.groundvegetation ENABLE ROW LEVEL SECURITY;

--
-- Name: growthforms; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.growthforms ENABLE ROW LEVEL SECURITY;

--
-- Name: growthorientations; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.growthorientations ENABLE ROW LEVEL SECURITY;

--
-- Name: phanerophyteheightclasses; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.phanerophyteheightclasses ENABLE ROW LEVEL SECURITY;

--
-- Name: phenologyobservations; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.phenologyobservations ENABLE ROW LEVEL SECURITY;

--
-- Name: shootelongationtypes; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.shootelongationtypes ENABLE ROW LEVEL SECURITY;

--
-- Name: stems; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.stems ENABLE ROW LEVEL SECURITY;

--
-- Name: straightnesstypes; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.straightnesstypes ENABLE ROW LEVEL SECURITY;

--
-- Name: tapertypes; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.tapertypes ENABLE ROW LEVEL SECURITY;

--
-- Name: trees; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.trees ENABLE ROW LEVEL SECURITY;

--
-- Name: treestatus; Type: ROW SECURITY; Schema: trees; Owner: -
--

ALTER TABLE trees.treestatus ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA environments; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA environments TO anon;
GRANT USAGE ON SCHEMA environments TO authenticated;
GRANT USAGE ON SCHEMA environments TO service_role;


--
-- Name: SCHEMA imagery; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA imagery TO anon;
GRANT USAGE ON SCHEMA imagery TO authenticated;
GRANT USAGE ON SCHEMA imagery TO service_role;


--
-- Name: SCHEMA pointclouds; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA pointclouds TO anon;
GRANT USAGE ON SCHEMA pointclouds TO authenticated;
GRANT USAGE ON SCHEMA pointclouds TO service_role;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA sensor; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA sensor TO anon;
GRANT USAGE ON SCHEMA sensor TO authenticated;
GRANT USAGE ON SCHEMA sensor TO service_role;


--
-- Name: SCHEMA shared; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA shared TO anon;
GRANT USAGE ON SCHEMA shared TO authenticated;
GRANT USAGE ON SCHEMA shared TO service_role;


--
-- Name: SCHEMA trees; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA trees TO anon;
GRANT USAGE ON SCHEMA trees TO authenticated;
GRANT USAGE ON SCHEMA trees TO service_role;


--
-- Name: FUNCTION calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone); Type: ACL; Schema: environments; Owner: -
--

GRANT ALL ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) TO service_role;


--
-- Name: FUNCTION create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying); Type: ACL; Schema: environments; Owner: -
--

GRANT ALL ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) TO anon;
GRANT ALL ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) TO authenticated;
GRANT ALL ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) TO service_role;


--
-- Name: FUNCTION is_active(start_date timestamp with time zone, end_date timestamp with time zone); Type: ACL; Schema: environments; Owner: -
--

GRANT ALL ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: environments; Owner: -
--

GRANT ALL ON FUNCTION environments.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION environments.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION environments.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: imagery; Owner: -
--

GRANT ALL ON FUNCTION imagery.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION imagery.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION imagery.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION get_s3_bucket(file_path text); Type: ACL; Schema: pointclouds; Owner: -
--

GRANT ALL ON FUNCTION pointclouds.get_s3_bucket(file_path text) TO anon;
GRANT ALL ON FUNCTION pointclouds.get_s3_bucket(file_path text) TO authenticated;
GRANT ALL ON FUNCTION pointclouds.get_s3_bucket(file_path text) TO service_role;


--
-- Name: FUNCTION get_s3_key(file_path text); Type: ACL; Schema: pointclouds; Owner: -
--

GRANT ALL ON FUNCTION pointclouds.get_s3_key(file_path text) TO anon;
GRANT ALL ON FUNCTION pointclouds.get_s3_key(file_path text) TO authenticated;
GRANT ALL ON FUNCTION pointclouds.get_s3_key(file_path text) TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: pointclouds; Owner: -
--

GRANT ALL ON FUNCTION pointclouds.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION pointclouds.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION pointclouds.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION validate_s3_uri(file_path text); Type: ACL; Schema: pointclouds; Owner: -
--

GRANT ALL ON FUNCTION pointclouds.validate_s3_uri(file_path text) TO anon;
GRANT ALL ON FUNCTION pointclouds.validate_s3_uri(file_path text) TO authenticated;
GRANT ALL ON FUNCTION pointclouds.validate_s3_uri(file_path text) TO service_role;


--
-- Name: FUNCTION bulk_insert_readings(readings jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.bulk_insert_readings(readings jsonb) TO postgres;
GRANT ALL ON FUNCTION public.bulk_insert_readings(readings jsonb) TO anon;
GRANT ALL ON FUNCTION public.bulk_insert_readings(readings jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.bulk_insert_readings(readings jsonb) TO service_role;


--
-- Name: FUNCTION bulk_upsert_sensors(p_sensors jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) TO postgres;
GRANT ALL ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) TO anon;
GRANT ALL ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) TO service_role;


--
-- Name: FUNCTION campaigns_delete(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.campaigns_delete() TO postgres;
GRANT ALL ON FUNCTION public.campaigns_delete() TO anon;
GRANT ALL ON FUNCTION public.campaigns_delete() TO authenticated;
GRANT ALL ON FUNCTION public.campaigns_delete() TO service_role;


--
-- Name: FUNCTION campaigns_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.campaigns_insert() TO postgres;
GRANT ALL ON FUNCTION public.campaigns_insert() TO anon;
GRANT ALL ON FUNCTION public.campaigns_insert() TO authenticated;
GRANT ALL ON FUNCTION public.campaigns_insert() TO service_role;


--
-- Name: FUNCTION campaigns_update(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.campaigns_update() TO postgres;
GRANT ALL ON FUNCTION public.campaigns_update() TO anon;
GRANT ALL ON FUNCTION public.campaigns_update() TO authenticated;
GRANT ALL ON FUNCTION public.campaigns_update() TO service_role;


--
-- Name: FUNCTION deadwood_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.deadwood_insert() TO postgres;
GRANT ALL ON FUNCTION public.deadwood_insert() TO anon;
GRANT ALL ON FUNCTION public.deadwood_insert() TO authenticated;
GRANT ALL ON FUNCTION public.deadwood_insert() TO service_role;


--
-- Name: FUNCTION disturbanceevents_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.disturbanceevents_insert() TO postgres;
GRANT ALL ON FUNCTION public.disturbanceevents_insert() TO anon;
GRANT ALL ON FUNCTION public.disturbanceevents_insert() TO authenticated;
GRANT ALL ON FUNCTION public.disturbanceevents_insert() TO service_role;


--
-- Name: FUNCTION environments_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.environments_insert() TO postgres;
GRANT ALL ON FUNCTION public.environments_insert() TO anon;
GRANT ALL ON FUNCTION public.environments_insert() TO authenticated;
GRANT ALL ON FUNCTION public.environments_insert() TO service_role;


--
-- Name: FUNCTION groundvegetation_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.groundvegetation_insert() TO postgres;
GRANT ALL ON FUNCTION public.groundvegetation_insert() TO anon;
GRANT ALL ON FUNCTION public.groundvegetation_insert() TO authenticated;
GRANT ALL ON FUNCTION public.groundvegetation_insert() TO service_role;


--
-- Name: FUNCTION images_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.images_insert() TO postgres;
GRANT ALL ON FUNCTION public.images_insert() TO anon;
GRANT ALL ON FUNCTION public.images_insert() TO authenticated;
GRANT ALL ON FUNCTION public.images_insert() TO service_role;


--
-- Name: FUNCTION managementevents_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.managementevents_insert() TO postgres;
GRANT ALL ON FUNCTION public.managementevents_insert() TO anon;
GRANT ALL ON FUNCTION public.managementevents_insert() TO authenticated;
GRANT ALL ON FUNCTION public.managementevents_insert() TO service_role;


--
-- Name: FUNCTION phenologyobservations_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.phenologyobservations_insert() TO postgres;
GRANT ALL ON FUNCTION public.phenologyobservations_insert() TO anon;
GRANT ALL ON FUNCTION public.phenologyobservations_insert() TO authenticated;
GRANT ALL ON FUNCTION public.phenologyobservations_insert() TO service_role;


--
-- Name: FUNCTION plots_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.plots_insert() TO postgres;
GRANT ALL ON FUNCTION public.plots_insert() TO anon;
GRANT ALL ON FUNCTION public.plots_insert() TO authenticated;
GRANT ALL ON FUNCTION public.plots_insert() TO service_role;


--
-- Name: FUNCTION pointclouds_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.pointclouds_insert() TO postgres;
GRANT ALL ON FUNCTION public.pointclouds_insert() TO anon;
GRANT ALL ON FUNCTION public.pointclouds_insert() TO authenticated;
GRANT ALL ON FUNCTION public.pointclouds_insert() TO service_role;


--
-- Name: FUNCTION sensor_tree_links_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO postgres;
GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO anon;
GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO authenticated;
GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO service_role;


--
-- Name: FUNCTION sensorreadings_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensorreadings_insert() TO postgres;
GRANT ALL ON FUNCTION public.sensorreadings_insert() TO anon;
GRANT ALL ON FUNCTION public.sensorreadings_insert() TO authenticated;
GRANT ALL ON FUNCTION public.sensorreadings_insert() TO service_role;


--
-- Name: FUNCTION sensors_delete(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensors_delete() TO postgres;
GRANT ALL ON FUNCTION public.sensors_delete() TO anon;
GRANT ALL ON FUNCTION public.sensors_delete() TO authenticated;
GRANT ALL ON FUNCTION public.sensors_delete() TO service_role;


--
-- Name: FUNCTION sensors_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensors_insert() TO postgres;
GRANT ALL ON FUNCTION public.sensors_insert() TO anon;
GRANT ALL ON FUNCTION public.sensors_insert() TO authenticated;
GRANT ALL ON FUNCTION public.sensors_insert() TO service_role;


--
-- Name: FUNCTION sensors_update(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.sensors_update() TO postgres;
GRANT ALL ON FUNCTION public.sensors_update() TO anon;
GRANT ALL ON FUNCTION public.sensors_update() TO authenticated;
GRANT ALL ON FUNCTION public.sensors_update() TO service_role;


--
-- Name: FUNCTION stems_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.stems_insert() TO postgres;
GRANT ALL ON FUNCTION public.stems_insert() TO anon;
GRANT ALL ON FUNCTION public.stems_insert() TO authenticated;
GRANT ALL ON FUNCTION public.stems_insert() TO service_role;


--
-- Name: FUNCTION trees_delete(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trees_delete() TO postgres;
GRANT ALL ON FUNCTION public.trees_delete() TO anon;
GRANT ALL ON FUNCTION public.trees_delete() TO authenticated;
GRANT ALL ON FUNCTION public.trees_delete() TO service_role;


--
-- Name: FUNCTION trees_insert(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trees_insert() TO postgres;
GRANT ALL ON FUNCTION public.trees_insert() TO anon;
GRANT ALL ON FUNCTION public.trees_insert() TO authenticated;
GRANT ALL ON FUNCTION public.trees_insert() TO service_role;


--
-- Name: FUNCTION trees_update(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.trees_update() TO postgres;
GRANT ALL ON FUNCTION public.trees_update() TO anon;
GRANT ALL ON FUNCTION public.trees_update() TO authenticated;
GRANT ALL ON FUNCTION public.trees_update() TO service_role;


--
-- Name: FUNCTION aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer); Type: ACL; Schema: sensor; Owner: -
--

GRANT ALL ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) TO anon;
GRANT ALL ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) TO authenticated;
GRANT ALL ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) TO service_role;


--
-- Name: FUNCTION check_sensor_health(sensor_id_param integer, hours_back integer); Type: ACL; Schema: sensor; Owner: -
--

GRANT ALL ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) TO anon;
GRANT ALL ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) TO authenticated;
GRANT ALL ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) TO service_role;


--
-- Name: FUNCTION get_latest_reading(sensor_id_param integer); Type: ACL; Schema: sensor; Owner: -
--

GRANT ALL ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) TO anon;
GRANT ALL ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) TO authenticated;
GRANT ALL ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) TO service_role;


--
-- Name: FUNCTION link_sensors_to_trees_by_pattern(); Type: ACL; Schema: sensor; Owner: -
--

GRANT ALL ON FUNCTION sensor.link_sensors_to_trees_by_pattern() TO service_role;
GRANT ALL ON FUNCTION sensor.link_sensors_to_trees_by_pattern() TO authenticated;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: sensor; Owner: -
--

GRANT ALL ON FUNCTION sensor.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION sensor.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION sensor.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying) TO authenticated;
GRANT ALL ON FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying) TO service_role;


--
-- Name: FUNCTION current_user_id(); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.current_user_id() TO authenticated;
GRANT ALL ON FUNCTION shared.current_user_id() TO service_role;


--
-- Name: FUNCTION get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer) TO authenticated;
GRANT ALL ON FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer) TO service_role;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.is_admin() TO anon;
GRANT ALL ON FUNCTION shared.is_admin() TO authenticated;
GRANT ALL ON FUNCTION shared.is_admin() TO service_role;


--
-- Name: FUNCTION is_contributor(); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.is_contributor() TO anon;
GRANT ALL ON FUNCTION shared.is_contributor() TO authenticated;
GRANT ALL ON FUNCTION shared.is_contributor() TO service_role;


--
-- Name: FUNCTION is_curator(); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.is_curator() TO anon;
GRANT ALL ON FUNCTION shared.is_curator() TO authenticated;
GRANT ALL ON FUNCTION shared.is_curator() TO service_role;


--
-- Name: FUNCTION refresh_all_lookups(); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.refresh_all_lookups() TO service_role;


--
-- Name: FUNCTION refresh_lookup(p_table_name text); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.refresh_lookup(p_table_name text) TO service_role;


--
-- Name: FUNCTION revert_field_change(audit_id_param bigint, change_reason_param text); Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON FUNCTION shared.revert_field_change(audit_id_param bigint, change_reason_param text) TO authenticated;
GRANT ALL ON FUNCTION shared.revert_field_change(audit_id_param bigint, change_reason_param text) TO service_role;


--
-- Name: FUNCTION calculate_basal_area(dbh_cm numeric); Type: ACL; Schema: trees; Owner: -
--

GRANT ALL ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) TO anon;
GRANT ALL ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) TO authenticated;
GRANT ALL ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) TO service_role;


--
-- Name: FUNCTION calculate_crown_volume(crown_width_m numeric, crown_height_m numeric); Type: ACL; Schema: trees; Owner: -
--

GRANT ALL ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) TO anon;
GRANT ALL ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) TO authenticated;
GRANT ALL ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: trees; Owner: -
--

GRANT ALL ON FUNCTION trees.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION trees.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION trees.update_updated_at_column() TO service_role;


--
-- Name: TABLE environments; Type: ACL; Schema: environments; Owner: -
--

GRANT SELECT ON TABLE environments.environments TO anon;
GRANT SELECT ON TABLE environments.environments TO authenticated;
GRANT ALL ON TABLE environments.environments TO service_role;


--
-- Name: TABLE locations; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.locations TO anon;
GRANT SELECT ON TABLE shared.locations TO authenticated;
GRANT ALL ON TABLE shared.locations TO service_role;


--
-- Name: TABLE scenarios; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.scenarios TO anon;
GRANT SELECT ON TABLE shared.scenarios TO authenticated;
GRANT ALL ON TABLE shared.scenarios TO service_role;


--
-- Name: TABLE varianttypes; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.varianttypes TO anon;
GRANT SELECT ON TABLE shared.varianttypes TO authenticated;
GRANT ALL ON TABLE shared.varianttypes TO service_role;


--
-- Name: TABLE active_environments; Type: ACL; Schema: environments; Owner: -
--

GRANT SELECT ON TABLE environments.active_environments TO anon;
GRANT SELECT ON TABLE environments.active_environments TO authenticated;
GRANT ALL ON TABLE environments.active_environments TO service_role;


--
-- Name: SEQUENCE environments_environment_id_seq; Type: ACL; Schema: environments; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE environments.environments_environment_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE environments.environments_environment_id_seq TO service_role;


--
-- Name: TABLE location_environment_summary; Type: ACL; Schema: environments; Owner: -
--

GRANT SELECT ON TABLE environments.location_environment_summary TO anon;
GRANT SELECT ON TABLE environments.location_environment_summary TO authenticated;
GRANT ALL ON TABLE environments.location_environment_summary TO service_role;


--
-- Name: TABLE images; Type: ACL; Schema: imagery; Owner: -
--

GRANT SELECT ON TABLE imagery.images TO anon;
GRANT SELECT ON TABLE imagery.images TO authenticated;
GRANT ALL ON TABLE imagery.images TO service_role;


--
-- Name: SEQUENCE images_image_id_seq; Type: ACL; Schema: imagery; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE imagery.images_image_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE imagery.images_image_id_seq TO service_role;


--
-- Name: TABLE pointclouds; Type: ACL; Schema: pointclouds; Owner: -
--

GRANT SELECT ON TABLE pointclouds.pointclouds TO anon;
GRANT SELECT ON TABLE pointclouds.pointclouds TO authenticated;
GRANT ALL ON TABLE pointclouds.pointclouds TO service_role;


--
-- Name: SEQUENCE pointclouds_point_cloud_id_seq; Type: ACL; Schema: pointclouds; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE pointclouds.pointclouds_point_cloud_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE pointclouds.pointclouds_point_cloud_id_seq TO service_role;


--
-- Name: TABLE processing_lineage; Type: ACL; Schema: pointclouds; Owner: -
--

GRANT SELECT ON TABLE pointclouds.processing_lineage TO anon;
GRANT SELECT ON TABLE pointclouds.processing_lineage TO authenticated;
GRANT ALL ON TABLE pointclouds.processing_lineage TO service_role;


--
-- Name: TABLE scanners; Type: ACL; Schema: pointclouds; Owner: -
--

GRANT SELECT ON TABLE pointclouds.scanners TO anon;
GRANT SELECT ON TABLE pointclouds.scanners TO authenticated;
GRANT ALL ON TABLE pointclouds.scanners TO service_role;


--
-- Name: SEQUENCE scanners_scanner_id_seq; Type: ACL; Schema: pointclouds; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE pointclouds.scanners_scanner_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE pointclouds.scanners_scanner_id_seq TO service_role;


--
-- Name: TABLE scannertypes; Type: ACL; Schema: pointclouds; Owner: -
--

GRANT SELECT ON TABLE pointclouds.scannertypes TO anon;
GRANT SELECT ON TABLE pointclouds.scannertypes TO authenticated;
GRANT ALL ON TABLE pointclouds.scannertypes TO service_role;


--
-- Name: SEQUENCE scannertypes_scanner_type_id_seq; Type: ACL; Schema: pointclouds; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE pointclouds.scannertypes_scanner_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE pointclouds.scannertypes_scanner_type_id_seq TO service_role;


--
-- Name: TABLE axisstructures; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.axisstructures TO postgres;
GRANT ALL ON TABLE public.axisstructures TO anon;
GRANT ALL ON TABLE public.axisstructures TO authenticated;
GRANT ALL ON TABLE public.axisstructures TO service_role;


--
-- Name: TABLE branchelongationhabits; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.branchelongationhabits TO postgres;
GRANT ALL ON TABLE public.branchelongationhabits TO anon;
GRANT ALL ON TABLE public.branchelongationhabits TO authenticated;
GRANT ALL ON TABLE public.branchelongationhabits TO service_role;


--
-- Name: TABLE campaigns; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.campaigns TO anon;
GRANT SELECT ON TABLE shared.campaigns TO authenticated;
GRANT ALL ON TABLE shared.campaigns TO service_role;


--
-- Name: TABLE campaigns; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.campaigns TO postgres;
GRANT ALL ON TABLE public.campaigns TO anon;
GRANT ALL ON TABLE public.campaigns TO authenticated;
GRANT ALL ON TABLE public.campaigns TO service_role;


--
-- Name: TABLE crownarchitectures; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.crownarchitectures TO postgres;
GRANT ALL ON TABLE public.crownarchitectures TO anon;
GRANT ALL ON TABLE public.crownarchitectures TO authenticated;
GRANT ALL ON TABLE public.crownarchitectures TO service_role;


--
-- Name: TABLE crownclasses; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.crownclasses TO postgres;
GRANT ALL ON TABLE public.crownclasses TO anon;
GRANT ALL ON TABLE public.crownclasses TO authenticated;
GRANT ALL ON TABLE public.crownclasses TO service_role;


--
-- Name: TABLE crownshapes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.crownshapes TO postgres;
GRANT ALL ON TABLE public.crownshapes TO anon;
GRANT ALL ON TABLE public.crownshapes TO authenticated;
GRANT ALL ON TABLE public.crownshapes TO service_role;


--
-- Name: TABLE damageagents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.damageagents TO postgres;
GRANT ALL ON TABLE public.damageagents TO anon;
GRANT ALL ON TABLE public.damageagents TO authenticated;
GRANT ALL ON TABLE public.damageagents TO service_role;


--
-- Name: TABLE datasourcetypes; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.datasourcetypes TO anon;
GRANT SELECT ON TABLE trees.datasourcetypes TO authenticated;
GRANT ALL ON TABLE trees.datasourcetypes TO service_role;


--
-- Name: TABLE datasourcetypes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.datasourcetypes TO postgres;
GRANT ALL ON TABLE public.datasourcetypes TO anon;
GRANT ALL ON TABLE public.datasourcetypes TO authenticated;
GRANT ALL ON TABLE public.datasourcetypes TO service_role;


--
-- Name: TABLE deadwood; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.deadwood TO anon;
GRANT SELECT ON TABLE trees.deadwood TO authenticated;
GRANT ALL ON TABLE trees.deadwood TO service_role;


--
-- Name: TABLE deadwood; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.deadwood TO postgres;
GRANT ALL ON TABLE public.deadwood TO anon;
GRANT ALL ON TABLE public.deadwood TO authenticated;
GRANT ALL ON TABLE public.deadwood TO service_role;


--
-- Name: TABLE disturbanceevents; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.disturbanceevents TO anon;
GRANT SELECT ON TABLE shared.disturbanceevents TO authenticated;
GRANT ALL ON TABLE shared.disturbanceevents TO service_role;


--
-- Name: TABLE disturbanceevents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.disturbanceevents TO postgres;
GRANT ALL ON TABLE public.disturbanceevents TO anon;
GRANT ALL ON TABLE public.disturbanceevents TO authenticated;
GRANT ALL ON TABLE public.disturbanceevents TO service_role;


--
-- Name: TABLE environments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.environments TO postgres;
GRANT ALL ON TABLE public.environments TO anon;
GRANT ALL ON TABLE public.environments TO authenticated;
GRANT ALL ON TABLE public.environments TO service_role;


--
-- Name: TABLE geometriccrownsolids; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.geometriccrownsolids TO postgres;
GRANT ALL ON TABLE public.geometriccrownsolids TO anon;
GRANT ALL ON TABLE public.geometriccrownsolids TO authenticated;
GRANT ALL ON TABLE public.geometriccrownsolids TO service_role;


--
-- Name: TABLE groundvegetation; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.groundvegetation TO anon;
GRANT SELECT ON TABLE trees.groundvegetation TO authenticated;
GRANT ALL ON TABLE trees.groundvegetation TO service_role;


--
-- Name: TABLE groundvegetation; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.groundvegetation TO postgres;
GRANT ALL ON TABLE public.groundvegetation TO anon;
GRANT ALL ON TABLE public.groundvegetation TO authenticated;
GRANT ALL ON TABLE public.groundvegetation TO service_role;


--
-- Name: TABLE species; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.species TO anon;
GRANT SELECT ON TABLE shared.species TO authenticated;
GRANT ALL ON TABLE shared.species TO service_role;


--
-- Name: TABLE growthsimulations; Type: ACL; Schema: trees; Owner: -
--

GRANT INSERT,UPDATE ON TABLE trees.growthsimulations TO authenticated;


--
-- Name: TABLE growth_simulations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.growth_simulations TO postgres;
GRANT ALL ON TABLE public.growth_simulations TO anon;
GRANT ALL ON TABLE public.growth_simulations TO authenticated;
GRANT ALL ON TABLE public.growth_simulations TO service_role;


--
-- Name: TABLE growthforms; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.growthforms TO postgres;
GRANT ALL ON TABLE public.growthforms TO anon;
GRANT ALL ON TABLE public.growthforms TO authenticated;
GRANT ALL ON TABLE public.growthforms TO service_role;


--
-- Name: TABLE growthorientations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.growthorientations TO postgres;
GRANT ALL ON TABLE public.growthorientations TO anon;
GRANT ALL ON TABLE public.growthorientations TO authenticated;
GRANT ALL ON TABLE public.growthorientations TO service_role;


--
-- Name: TABLE images; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.images TO postgres;
GRANT ALL ON TABLE public.images TO anon;
GRANT ALL ON TABLE public.images TO authenticated;
GRANT ALL ON TABLE public.images TO service_role;


--
-- Name: TABLE locations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.locations TO postgres;
GRANT ALL ON TABLE public.locations TO anon;
GRANT ALL ON TABLE public.locations TO authenticated;
GRANT ALL ON TABLE public.locations TO service_role;


--
-- Name: TABLE managementevents; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.managementevents TO anon;
GRANT SELECT ON TABLE shared.managementevents TO authenticated;
GRANT ALL ON TABLE shared.managementevents TO service_role;


--
-- Name: TABLE managementevents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.managementevents TO postgres;
GRANT ALL ON TABLE public.managementevents TO anon;
GRANT ALL ON TABLE public.managementevents TO authenticated;
GRANT ALL ON TABLE public.managementevents TO service_role;


--
-- Name: TABLE phanerophyteheightclasses; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.phanerophyteheightclasses TO postgres;
GRANT ALL ON TABLE public.phanerophyteheightclasses TO anon;
GRANT ALL ON TABLE public.phanerophyteheightclasses TO authenticated;
GRANT ALL ON TABLE public.phanerophyteheightclasses TO service_role;


--
-- Name: TABLE phenologyobservations; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.phenologyobservations TO anon;
GRANT SELECT ON TABLE trees.phenologyobservations TO authenticated;
GRANT ALL ON TABLE trees.phenologyobservations TO service_role;


--
-- Name: TABLE phenologyobservations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.phenologyobservations TO postgres;
GRANT ALL ON TABLE public.phenologyobservations TO anon;
GRANT ALL ON TABLE public.phenologyobservations TO authenticated;
GRANT ALL ON TABLE public.phenologyobservations TO service_role;


--
-- Name: TABLE plots; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.plots TO anon;
GRANT SELECT ON TABLE shared.plots TO authenticated;
GRANT ALL ON TABLE shared.plots TO service_role;


--
-- Name: TABLE plots; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.plots TO postgres;
GRANT ALL ON TABLE public.plots TO anon;
GRANT ALL ON TABLE public.plots TO authenticated;
GRANT ALL ON TABLE public.plots TO service_role;


--
-- Name: TABLE pointclouds; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pointclouds TO postgres;
GRANT ALL ON TABLE public.pointclouds TO anon;
GRANT ALL ON TABLE public.pointclouds TO authenticated;
GRANT ALL ON TABLE public.pointclouds TO service_role;


--
-- Name: TABLE scenarios; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.scenarios TO postgres;
GRANT ALL ON TABLE public.scenarios TO anon;
GRANT ALL ON TABLE public.scenarios TO authenticated;
GRANT ALL ON TABLE public.scenarios TO service_role;


--
-- Name: TABLE sensor_tree_links; Type: ACL; Schema: sensor; Owner: -
--

GRANT ALL ON TABLE sensor.sensor_tree_links TO service_role;
GRANT SELECT ON TABLE sensor.sensor_tree_links TO authenticated;
GRANT SELECT ON TABLE sensor.sensor_tree_links TO anon;


--
-- Name: TABLE sensor_tree_links; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sensor_tree_links TO postgres;
GRANT ALL ON TABLE public.sensor_tree_links TO anon;
GRANT ALL ON TABLE public.sensor_tree_links TO authenticated;
GRANT ALL ON TABLE public.sensor_tree_links TO service_role;


--
-- Name: TABLE sensorreadings; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT ON TABLE sensor.sensorreadings TO anon;
GRANT SELECT,INSERT ON TABLE sensor.sensorreadings TO authenticated;
GRANT ALL ON TABLE sensor.sensorreadings TO service_role;


--
-- Name: TABLE sensorreadings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sensorreadings TO postgres;
GRANT ALL ON TABLE public.sensorreadings TO anon;
GRANT ALL ON TABLE public.sensorreadings TO authenticated;
GRANT ALL ON TABLE public.sensorreadings TO service_role;


--
-- Name: TABLE sensors; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT ON TABLE sensor.sensors TO anon;
GRANT SELECT ON TABLE sensor.sensors TO authenticated;
GRANT ALL ON TABLE sensor.sensors TO service_role;


--
-- Name: TABLE sensors; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sensors TO postgres;
GRANT ALL ON TABLE public.sensors TO anon;
GRANT ALL ON TABLE public.sensors TO authenticated;
GRANT ALL ON TABLE public.sensors TO service_role;


--
-- Name: TABLE sensortypes; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT ON TABLE sensor.sensortypes TO anon;
GRANT SELECT ON TABLE sensor.sensortypes TO authenticated;
GRANT ALL ON TABLE sensor.sensortypes TO service_role;


--
-- Name: TABLE sensortypes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.sensortypes TO postgres;
GRANT ALL ON TABLE public.sensortypes TO anon;
GRANT ALL ON TABLE public.sensortypes TO authenticated;
GRANT ALL ON TABLE public.sensortypes TO service_role;


--
-- Name: TABLE shootelongationtypes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.shootelongationtypes TO postgres;
GRANT ALL ON TABLE public.shootelongationtypes TO anon;
GRANT ALL ON TABLE public.shootelongationtypes TO authenticated;
GRANT ALL ON TABLE public.shootelongationtypes TO service_role;


--
-- Name: TABLE stems; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.stems TO anon;
GRANT SELECT ON TABLE trees.stems TO authenticated;
GRANT ALL ON TABLE trees.stems TO service_role;


--
-- Name: TABLE trees; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.trees TO anon;
GRANT SELECT ON TABLE trees.trees TO authenticated;
GRANT ALL ON TABLE trees.trees TO service_role;


--
-- Name: TABLE silva_input; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.silva_input TO postgres;
GRANT ALL ON TABLE public.silva_input TO anon;
GRANT ALL ON TABLE public.silva_input TO authenticated;
GRANT ALL ON TABLE public.silva_input TO service_role;


--
-- Name: TABLE simulation_runs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.simulation_runs TO postgres;
GRANT ALL ON TABLE public.simulation_runs TO anon;
GRANT ALL ON TABLE public.simulation_runs TO authenticated;
GRANT ALL ON TABLE public.simulation_runs TO service_role;


--
-- Name: TABLE species; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.species TO postgres;
GRANT ALL ON TABLE public.species TO anon;
GRANT ALL ON TABLE public.species TO authenticated;
GRANT ALL ON TABLE public.species TO service_role;


--
-- Name: TABLE stems; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stems TO postgres;
GRANT ALL ON TABLE public.stems TO anon;
GRANT ALL ON TABLE public.stems TO authenticated;
GRANT ALL ON TABLE public.stems TO service_role;


--
-- Name: TABLE trees; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.trees TO postgres;
GRANT ALL ON TABLE public.trees TO anon;
GRANT ALL ON TABLE public.trees TO authenticated;
GRANT ALL ON TABLE public.trees TO service_role;


--
-- Name: TABLE ue_sensorreadings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ue_sensorreadings TO postgres;
GRANT ALL ON TABLE public.ue_sensorreadings TO anon;
GRANT ALL ON TABLE public.ue_sensorreadings TO authenticated;
GRANT ALL ON TABLE public.ue_sensorreadings TO service_role;


--
-- Name: TABLE ue_sensors; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ue_sensors TO postgres;
GRANT ALL ON TABLE public.ue_sensors TO anon;
GRANT ALL ON TABLE public.ue_sensors TO authenticated;
GRANT ALL ON TABLE public.ue_sensors TO service_role;


--
-- Name: TABLE variants; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.variants TO anon;
GRANT SELECT ON TABLE shared.variants TO authenticated;
GRANT ALL ON TABLE shared.variants TO service_role;


--
-- Name: TABLE ue_trees; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ue_trees TO postgres;
GRANT ALL ON TABLE public.ue_trees TO anon;
GRANT ALL ON TABLE public.ue_trees TO authenticated;
GRANT ALL ON TABLE public.ue_trees TO service_role;


--
-- Name: TABLE variants; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.variants TO postgres;
GRANT ALL ON TABLE public.variants TO anon;
GRANT ALL ON TABLE public.variants TO authenticated;
GRANT ALL ON TABLE public.variants TO service_role;


--
-- Name: TABLE varianttypes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.varianttypes TO postgres;
GRANT ALL ON TABLE public.varianttypes TO anon;
GRANT ALL ON TABLE public.varianttypes TO authenticated;
GRANT ALL ON TABLE public.varianttypes TO service_role;


--
-- Name: TABLE active_sensors_status; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT ON TABLE sensor.active_sensors_status TO anon;
GRANT SELECT ON TABLE sensor.active_sensors_status TO authenticated;
GRANT ALL ON TABLE sensor.active_sensors_status TO service_role;


--
-- Name: SEQUENCE sensor_tree_links_sensortreelinkid_seq; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_tree_links_sensortreelinkid_seq TO service_role;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_tree_links_sensortreelinkid_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_tree_links_sensortreelinkid_seq TO anon;


--
-- Name: TABLE sensor_tree_view; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT ON TABLE sensor.sensor_tree_view TO authenticated;
GRANT SELECT ON TABLE sensor.sensor_tree_view TO anon;


--
-- Name: SEQUENCE sensorreadings_sensor_reading_id_seq; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensorreadings_sensor_reading_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensorreadings_sensor_reading_id_seq TO service_role;


--
-- Name: SEQUENCE sensors_sensor_id_seq; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensors_sensor_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensors_sensor_id_seq TO service_role;


--
-- Name: SEQUENCE sensortypes_sensor_type_id_seq; Type: ACL; Schema: sensor; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensortypes_sensor_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensortypes_sensor_type_id_seq TO service_role;


--
-- Name: TABLE auditlog; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.auditlog TO anon;
GRANT SELECT ON TABLE shared.auditlog TO authenticated;
GRANT ALL ON TABLE shared.auditlog TO service_role;


--
-- Name: SEQUENCE auditlog_audit_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.auditlog_audit_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.auditlog_audit_id_seq TO service_role;


--
-- Name: SEQUENCE campaigns_campaign_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.campaigns_campaign_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.campaigns_campaign_id_seq TO service_role;


--
-- Name: TABLE climatezones; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.climatezones TO anon;
GRANT SELECT ON TABLE shared.climatezones TO authenticated;
GRANT ALL ON TABLE shared.climatezones TO service_role;


--
-- Name: SEQUENCE climatezones_climate_zone_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.climatezones_climate_zone_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.climatezones_climate_zone_id_seq TO service_role;


--
-- Name: SEQUENCE disturbanceevents_disturbance_event_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.disturbanceevents_disturbance_event_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.disturbanceevents_disturbance_event_id_seq TO service_role;


--
-- Name: SEQUENCE locations_location_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.locations_location_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.locations_location_id_seq TO service_role;


--
-- Name: SEQUENCE managementevents_management_event_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.managementevents_management_event_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.managementevents_management_event_id_seq TO service_role;


--
-- Name: SEQUENCE plots_plot_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.plots_plot_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.plots_plot_id_seq TO service_role;


--
-- Name: TABLE processes; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.processes TO anon;
GRANT SELECT ON TABLE shared.processes TO authenticated;
GRANT ALL ON TABLE shared.processes TO service_role;


--
-- Name: SEQUENCE processes_process_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.processes_process_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.processes_process_id_seq TO service_role;


--
-- Name: TABLE processingjobs; Type: ACL; Schema: shared; Owner: -
--

GRANT ALL ON TABLE shared.processingjobs TO service_role;
GRANT SELECT ON TABLE shared.processingjobs TO authenticated;
GRANT SELECT ON TABLE shared.processingjobs TO anon;


--
-- Name: SEQUENCE processingjobs_processing_job_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.processingjobs_processing_job_id_seq TO service_role;
GRANT SELECT,USAGE ON SEQUENCE shared.processingjobs_processing_job_id_seq TO authenticated;


--
-- Name: TABLE processmetrics; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.processmetrics TO anon;
GRANT SELECT ON TABLE shared.processmetrics TO authenticated;
GRANT ALL ON TABLE shared.processmetrics TO service_role;


--
-- Name: SEQUENCE processmetrics_process_metric_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.processmetrics_process_metric_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.processmetrics_process_metric_id_seq TO service_role;


--
-- Name: TABLE processparameters; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.processparameters TO anon;
GRANT SELECT ON TABLE shared.processparameters TO authenticated;
GRANT ALL ON TABLE shared.processparameters TO service_role;


--
-- Name: SEQUENCE processparameters_process_parameter_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.processparameters_process_parameter_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.processparameters_process_parameter_id_seq TO service_role;


--
-- Name: SEQUENCE scenarios_scenario_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.scenarios_scenario_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.scenarios_scenario_id_seq TO service_role;


--
-- Name: TABLE soiltypes; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT ON TABLE shared.soiltypes TO anon;
GRANT SELECT ON TABLE shared.soiltypes TO authenticated;
GRANT ALL ON TABLE shared.soiltypes TO service_role;


--
-- Name: SEQUENCE soiltypes_soil_type_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.soiltypes_soil_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.soiltypes_soil_type_id_seq TO service_role;


--
-- Name: SEQUENCE species_species_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.species_species_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.species_species_id_seq TO service_role;


--
-- Name: SEQUENCE variants_variant_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.variants_variant_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.variants_variant_id_seq TO service_role;


--
-- Name: SEQUENCE varianttypes_variant_type_id_seq; Type: ACL; Schema: shared; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE shared.varianttypes_variant_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.varianttypes_variant_type_id_seq TO service_role;


--
-- Name: TABLE barkcharacteristics; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.barkcharacteristics TO anon;
GRANT SELECT ON TABLE trees.barkcharacteristics TO authenticated;
GRANT ALL ON TABLE trees.barkcharacteristics TO service_role;


--
-- Name: SEQUENCE barkcharacteristics_bark_characteristic_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.barkcharacteristics_bark_characteristic_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.barkcharacteristics_bark_characteristic_id_seq TO service_role;


--
-- Name: TABLE branchingpatterns; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.branchingpatterns TO anon;
GRANT SELECT ON TABLE trees.branchingpatterns TO authenticated;
GRANT ALL ON TABLE trees.branchingpatterns TO service_role;


--
-- Name: SEQUENCE branchingpatterns_branching_pattern_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.branchingpatterns_branching_pattern_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.branchingpatterns_branching_pattern_id_seq TO service_role;


--
-- Name: SEQUENCE datasourcetypes_data_source_type_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.datasourcetypes_data_source_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.datasourcetypes_data_source_type_id_seq TO service_role;


--
-- Name: SEQUENCE deadwood_deadwood_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.deadwood_deadwood_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.deadwood_deadwood_id_seq TO service_role;


--
-- Name: SEQUENCE groundvegetation_ground_vegetation_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.groundvegetation_ground_vegetation_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.groundvegetation_ground_vegetation_id_seq TO service_role;


--
-- Name: SEQUENCE growthsimulations_growth_simulation_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.growthsimulations_growth_simulation_id_seq TO authenticated;


--
-- Name: SEQUENCE phenologyobservations_phenology_observation_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.phenologyobservations_phenology_observation_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.phenologyobservations_phenology_observation_id_seq TO service_role;


--
-- Name: SEQUENCE stems_stem_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.stems_stem_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.stems_stem_id_seq TO service_role;


--
-- Name: TABLE straightnesstypes; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.straightnesstypes TO anon;
GRANT SELECT ON TABLE trees.straightnesstypes TO authenticated;
GRANT ALL ON TABLE trees.straightnesstypes TO service_role;


--
-- Name: SEQUENCE straightnesstypes_straightness_type_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.straightnesstypes_straightness_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.straightnesstypes_straightness_type_id_seq TO service_role;


--
-- Name: TABLE tapertypes; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.tapertypes TO anon;
GRANT SELECT ON TABLE trees.tapertypes TO authenticated;
GRANT ALL ON TABLE trees.tapertypes TO service_role;


--
-- Name: SEQUENCE tapertypes_taper_type_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.tapertypes_taper_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.tapertypes_taper_type_id_seq TO service_role;


--
-- Name: SEQUENCE trees_tree_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.trees_tree_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.trees_tree_id_seq TO service_role;


--
-- Name: TABLE trees_with_metrics; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.trees_with_metrics TO anon;
GRANT SELECT ON TABLE trees.trees_with_metrics TO authenticated;
GRANT ALL ON TABLE trees.trees_with_metrics TO service_role;


--
-- Name: TABLE treestatus; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT ON TABLE trees.treestatus TO anon;
GRANT SELECT ON TABLE trees.treestatus TO authenticated;
GRANT ALL ON TABLE trees.treestatus TO service_role;


--
-- Name: SEQUENCE treestatus_tree_status_id_seq; Type: ACL; Schema: trees; Owner: -
--

GRANT SELECT,USAGE ON SEQUENCE trees.treestatus_tree_status_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.treestatus_tree_status_id_seq TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- PostgreSQL database dump complete
--

