-- =============================================================================
-- BASELINE SNAPSHOT 2026-11-09 (XRFF-661)
-- =============================================================================
-- The whole application schema as a fresh init produced it on 2026-11-09:
-- schema-only pg_dump of shared, trees, sensor, point_clouds, environments,
-- imagery, forest_floor and public, taken from a database initialised from the
-- previous chain (10-baseline-schema.sql plus 76 numbered files, through
-- migration 20261109100000). It replaces that chain: the history is in
-- supabase/migrations/archive/ and in git.
--
-- Checked before adoption: a database initialised from this snapshot and
-- 20261109120001_reference_data.sql matches the chain-built one in a full
-- schema-only pg_dump, the role list and every reference table's rows.
--
-- New schema changes: a new timestamped file in supabase/migrations/. The db
-- image runs that directory in name order after the platform's own migrations.
-- =============================================================================

-- PostGIS and the extension grants are in 10000000000001_extensions.sql,
-- which runs before the platform's own migrations, as the old baseline did.

-- The dashboards' read-only role (migration 20261102180000). No login here:
-- each host sets one, see RUNBOOK.md section 9.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dashboard_reader') THEN
        CREATE ROLE dashboard_reader NOLOGIN NOINHERIT;
    END IF;
END $$;
ALTER ROLE dashboard_reader INHERIT;
GRANT anon TO dashboard_reader;
ALTER ROLE dashboard_reader SET statement_timeout = '30s';
ALTER ROLE dashboard_reader SET search_path = shared, trees, sensor, environments, extensions, public;
COMMENT ON ROLE dashboard_reader IS 'Read-only role for digital-twin-dashboard: a member of anon, so it reads what an anonymous API caller may read and row-level security applies. No login here; each host sets a password (RUNBOOK §9).';

-- supabase_admin's default privileges in public would grant anon and
-- authenticated everything on each object created below. The dump states each
-- object's exact privileges, so those defaults are off while it loads; the
-- dump's own ALTER DEFAULT PRIVILEGES near the end puts them back.
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE ALL ON TABLES FROM postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE ALL ON SEQUENCES FROM postgres, anon, authenticated, service_role;

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

--
-- Name: environments; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA IF NOT EXISTS environments;


ALTER SCHEMA environments OWNER TO supabase_admin;

--
-- Name: forest_floor; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA IF NOT EXISTS forest_floor;


ALTER SCHEMA forest_floor OWNER TO supabase_admin;

--
-- Name: SCHEMA forest_floor; Type: COMMENT; Schema: -; Owner: supabase_admin
--

COMMENT ON SCHEMA forest_floor IS 'Plot/site-level forest floor surveys (deadwood, ground vegetation) -- not tied to a single tree';


--
-- Name: imagery; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA IF NOT EXISTS imagery;


ALTER SCHEMA imagery OWNER TO supabase_admin;

--
-- Name: point_clouds; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA IF NOT EXISTS point_clouds;


ALTER SCHEMA point_clouds OWNER TO supabase_admin;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA IF NOT EXISTS public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: sensor; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA IF NOT EXISTS sensor;


ALTER SCHEMA sensor OWNER TO supabase_admin;

--
-- Name: shared; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA IF NOT EXISTS shared;


ALTER SCHEMA shared OWNER TO supabase_admin;

--
-- Name: trees; Type: SCHEMA; Schema: -; Owner: supabase_admin
--

CREATE SCHEMA IF NOT EXISTS trees;


ALTER SCHEMA trees OWNER TO supabase_admin;

--
-- Name: calculate_duration_days(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: environments; Owner: supabase_admin
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


ALTER FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) OWNER TO supabase_admin;

--
-- Name: FUNCTION calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone); Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) IS 'Calculates duration in days between start and end dates';


--
-- Name: create_from_sensor_data(integer, timestamp with time zone, timestamp with time zone, character varying); Type: FUNCTION; Schema: environments; Owner: supabase_admin
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
$$;


ALTER FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) OWNER TO supabase_admin;

--
-- Name: FUNCTION create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying); Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) IS 'Creates environment variant by aggregating sensor readings';


--
-- Name: is_active(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: environments; Owner: supabase_admin
--

CREATE FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW());
END;
$$;


ALTER FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) OWNER TO supabase_admin;

--
-- Name: FUNCTION is_active(start_date timestamp with time zone, end_date timestamp with time zone); Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) IS 'Checks if environment variant is currently active';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: environments; Owner: supabase_admin
--

CREATE FUNCTION environments.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION environments.update_updated_at_column() OWNER TO supabase_admin;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: imagery; Owner: supabase_admin
--

CREATE FUNCTION imagery.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION imagery.update_updated_at_column() OWNER TO supabase_admin;

--
-- Name: get_s3_bucket(text); Type: FUNCTION; Schema: point_clouds; Owner: supabase_admin
--

CREATE FUNCTION point_clouds.get_s3_bucket(file_path text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN substring(file_path FROM 's3://([^/]+)/');
END;
$$;


ALTER FUNCTION point_clouds.get_s3_bucket(file_path text) OWNER TO supabase_admin;

--
-- Name: FUNCTION get_s3_bucket(file_path text); Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON FUNCTION point_clouds.get_s3_bucket(file_path text) IS 'Extracts S3 bucket name from file_path';


--
-- Name: get_s3_key(text); Type: FUNCTION; Schema: point_clouds; Owner: supabase_admin
--

CREATE FUNCTION point_clouds.get_s3_key(file_path text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN substring(file_path FROM 's3://[^/]+/(.+)');
END;
$$;


ALTER FUNCTION point_clouds.get_s3_key(file_path text) OWNER TO supabase_admin;

--
-- Name: FUNCTION get_s3_key(file_path text); Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON FUNCTION point_clouds.get_s3_key(file_path text) IS 'Extracts S3 object key (path) from file_path';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: point_clouds; Owner: supabase_admin
--

CREATE FUNCTION point_clouds.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION point_clouds.update_updated_at_column() OWNER TO supabase_admin;

--
-- Name: validate_s3_uri(text); Type: FUNCTION; Schema: point_clouds; Owner: supabase_admin
--

CREATE FUNCTION point_clouds.validate_s3_uri(file_path text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
BEGIN
    RETURN file_path ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$';
END;
$_$;


ALTER FUNCTION point_clouds.validate_s3_uri(file_path text) OWNER TO supabase_admin;

--
-- Name: FUNCTION validate_s3_uri(file_path text); Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON FUNCTION point_clouds.validate_s3_uri(file_path text) IS 'Validates S3 URI format for point cloud files';


--
-- Name: add_team_member(integer, text, boolean); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.add_team_member(p_team_id integer, p_email text, p_is_team_curator boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_user  uuid;
    v_actor text := (SELECT u.email FROM auth.users u WHERE u.id = auth.uid());
BEGIN
    IF NOT (shared.is_curator()
            OR (p_team_id IN (SELECT shared.my_curated_team_ids()) AND NOT p_is_team_curator)) THEN
        RAISE EXCEPTION 'Only curators, or curators of this team adding a plain member, may add team members'
            USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.teams t WHERE t.team_id = p_team_id) THEN
        RAISE EXCEPTION 'No team %', p_team_id USING ERRCODE = 'P0002';
    END IF;
    SELECT u.id INTO v_user FROM auth.users u WHERE lower(u.email) = lower(trim(p_email));
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'No account with e-mail %', p_email USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO shared.team_members (team_id, user_id, is_team_curator, created_by)
    VALUES (p_team_id, v_user, p_is_team_curator, v_actor)
    ON CONFLICT (team_id, user_id) DO UPDATE SET is_team_curator = EXCLUDED.is_team_curator;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, new_role, team_id)
    VALUES (auth.uid(), v_actor, lower(trim(p_email)), 'team_add',
            CASE WHEN p_is_team_curator THEN 'team_curator' ELSE 'team_member' END, p_team_id);
END;
$$;


ALTER FUNCTION public.add_team_member(p_team_id integer, p_email text, p_is_team_curator boolean) OWNER TO supabase_admin;

--
-- Name: bulk_insert_readings(jsonb); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.bulk_insert_readings(readings jsonb) RETURNS TABLE(out_inserted_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'sensor'
    AS $$
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
$$;


ALTER FUNCTION public.bulk_insert_readings(readings jsonb) OWNER TO supabase_admin;

--
-- Name: FUNCTION bulk_insert_readings(readings jsonb); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.bulk_insert_readings(readings jsonb) IS 'Bulk inserts readings from JSON array, skips duplicates';


--
-- Name: bulk_upsert_sensors(jsonb); Type: FUNCTION; Schema: public; Owner: supabase_admin
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


ALTER FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) OWNER TO supabase_admin;

--
-- Name: FUNCTION bulk_upsert_sensors(p_sensors jsonb); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) IS 'Bulk upserts sensors from JSON array, returns external IDs and sensor IDs';


--
-- Name: campaigns_delete(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.campaigns_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM shared.campaigns WHERE campaign_id = OLD.campaign_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.campaigns_delete() OWNER TO supabase_admin;

--
-- Name: FUNCTION campaigns_delete(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.campaigns_delete() IS 'INSTEAD OF DELETE trigger function for public.campaigns view';


--
-- Name: campaigns_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.campaigns_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.campaigns (
        campaign_name, campaign_type, location_id, start_date, end_date,
        description, methodology, equipment, personnel,
        created_by, updated_by,
        owner_team_id, licence, access_level, embargo_until, citation, doi
    ) VALUES (
        NEW.campaign_name, NEW.campaign_type, NEW.location_id, NEW.start_date, NEW.end_date,
        NEW.description, NEW.methodology, NEW.equipment, NEW.personnel,
        NEW.created_by, NEW.updated_by,
        NEW.owner_team_id, NEW.licence, coalesce(NEW.access_level, 'public'), NEW.embargo_until,
        NEW.citation, NEW.doi
    ) RETURNING campaign_id INTO NEW.campaign_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.campaigns_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION campaigns_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.campaigns_insert() IS 'INSTEAD OF INSERT trigger function for public.campaigns view';


--
-- Name: campaigns_update(); Type: FUNCTION; Schema: public; Owner: supabase_admin
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
        owner_team_id = NEW.owner_team_id,
        licence = NEW.licence,
        access_level = NEW.access_level,
        embargo_until = NEW.embargo_until,
        citation = NEW.citation,
        doi = NEW.doi,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE campaign_id = OLD.campaign_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.campaigns_update() OWNER TO supabase_admin;

--
-- Name: FUNCTION campaigns_update(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.campaigns_update() IS 'INSTEAD OF UPDATE trigger function for public.campaigns view';


--
-- Name: create_account(text, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.create_account(p_email text, p_role text DEFAULT NULL::text) RETURNS TABLE(email text, role text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
DECLARE
    v_email    text := lower(btrim(p_email));
    v_role     text := NULLIF(btrim(p_role), '');
    v_id       uuid := gen_random_uuid();
    v_password text;
    v_now      timestamptz := now();
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can create accounts'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
        RAISE EXCEPTION 'Not an email address: %', COALESCE(p_email, '(empty)')
            USING ERRCODE = '22023';
    END IF;

    IF v_role IS NOT NULL AND v_role NOT IN ('contributor', 'curator', 'admin') THEN
        RAISE EXCEPTION 'Unknown role: %', v_role
            USING ERRCODE = '22023',
                  HINT = 'Use contributor, curator or admin -- or leave it empty for a read-only account.';
    END IF;

    IF NOT shared.may_manage_role(v_role) THEN
        RAISE EXCEPTION 'You cannot create a % account', v_role
            USING ERRCODE = '42501',
                  HINT = 'Curators create read-only and contributor accounts; only admins grant curator or admin.';
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users u WHERE lower(u.email) = v_email AND u.deleted_at IS NULL) THEN
        RAISE EXCEPTION 'An account for % already exists', v_email
            USING ERRCODE = '23505',
                  HINT = 'Change its role or reset its password instead.';
    END IF;

    v_password := shared.new_account_password();

    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
        v_email, extensions.crypt(v_password, extensions.gen_salt('bf')),
        v_now,
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'))
            || CASE WHEN v_role IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('role', v_role) END,
        jsonb_build_object('must_change_password', true),
        v_now, v_now,
        '', '', '', ''
    );

    INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    VALUES (
        v_id::text, v_id,
        jsonb_build_object('sub', v_id::text, 'email', v_email,
                           'email_verified', false, 'phone_verified', false),
        'email', v_now, v_now
    );

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, new_role)
    VALUES (auth.uid(), auth.jwt() ->> 'email', v_email, 'create', v_role);

    RETURN QUERY SELECT v_email, v_role, v_password;
END;
$_$;


ALTER FUNCTION public.create_account(p_email text, p_role text) OWNER TO supabase_admin;

--
-- Name: FUNCTION create_account(p_email text, p_role text); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.create_account(p_email text, p_role text) IS 'Create a confirmed email/password account and return its one-time password. Curators: read-only (NULL) or contributor; admins: any tier. Logged to shared.account_events.';


--
-- Name: crown_foliage_profiles_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.crown_foliage_profiles_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.crown_foliage_profiles (
        tree_id, process_id, distribution_type, vertical_params,
        horizontal_params, total_leaf_area_m2, source, created_by
    ) VALUES (
        NEW.tree_id, NEW.process_id, NEW.distribution_type, NEW.vertical_params,
        NEW.horizontal_params, NEW.total_leaf_area_m2, NEW.source, NEW.created_by
    ) RETURNING profile_id INTO NEW.profile_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.crown_foliage_profiles_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION crown_foliage_profiles_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.crown_foliage_profiles_insert() IS 'INSTEAD OF INSERT trigger function for public.crownfoliageprofiles view';


--
-- Name: crownfoliageprofiles_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.crownfoliageprofiles_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.crownfoliageprofiles_insert() OWNER TO supabase_admin;

--
-- Name: deadwood_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.deadwood_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO forest_floor.deadwood (
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


ALTER FUNCTION public.deadwood_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION deadwood_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.deadwood_insert() IS 'INSTEAD OF INSERT trigger function for public.deadwood view';


--
-- Name: disturbance_events_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.disturbance_events_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.disturbance_events (
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


ALTER FUNCTION public.disturbance_events_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION disturbance_events_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.disturbance_events_insert() IS 'INSTEAD OF INSERT trigger function for public.disturbanceevents view';


--
-- Name: environments_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.environments_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO environments.environments SELECT NEW.*;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.environments_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION environments_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.environments_insert() IS 'INSTEAD OF INSERT trigger function for public.environments view';


--
-- Name: estimate_stand(integer, integer, boolean, numeric); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean DEFAULT false, p_confidence numeric DEFAULT 0.95) RETURNS TABLE(sampling_design_id integer, variant_id integer, by_species boolean, species_id integer, variable text, unit text, estimate numeric, standard_error numeric, relative_standard_error_pct numeric, margin_of_error numeric, sampling_error_pct numeric, ci_low numeric, ci_high numeric, confidence numeric, n_units integer, area_ha numeric, total numeric, total_standard_error numeric, method text)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
    SELECT * FROM shared.estimate_stand(p_sampling_design_id, p_variant_id, p_by_species, p_confidence);
$$;


ALTER FUNCTION public.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) OWNER TO supabase_admin;

--
-- Name: FUNCTION estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) IS 'REST entry point for shared.estimate_stand: POST /rest/v1/rpc/estimate_stand {"p_sampling_design_id":..,"p_variant_id":..,"p_by_species":false,"p_confidence":0.95}.';


--
-- Name: ground_vegetation_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.ground_vegetation_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO forest_floor.ground_vegetation (
        location_id, plot_id, species_name, cover_percent,
        height_cm, layer, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.species_name, NEW.cover_percent,
        NEW.height_cm, NEW.layer, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING ground_vegetation_id INTO NEW.ground_vegetation_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.ground_vegetation_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION ground_vegetation_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.ground_vegetation_insert() IS 'INSTEAD OF INSERT trigger function for public.groundvegetation view';


--
-- Name: images_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
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


ALTER FUNCTION public.images_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION images_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.images_insert() IS 'INSTEAD OF INSERT trigger function for public.images view';


--
-- Name: list_accounts(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.list_accounts() RETURNS TABLE(email text, role text, created_at timestamp with time zone, last_sign_in_at timestamp with time zone, must_change_password boolean, manageable boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can list accounts'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    RETURN QUERY
    SELECT u.email::text,
           u.raw_app_meta_data ->> 'role',
           u.created_at,
           u.last_sign_in_at,
           COALESCE((u.raw_user_meta_data ->> 'must_change_password')::boolean, false),
           shared.may_manage_role(u.raw_app_meta_data ->> 'role') AND u.id <> auth.uid()
      FROM auth.users u
     WHERE u.deleted_at IS NULL
       AND NOT u.is_anonymous
     ORDER BY u.email;
END;
$$;


ALTER FUNCTION public.list_accounts() OWNER TO supabase_admin;

--
-- Name: FUNCTION list_accounts(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.list_accounts() IS 'Every account with its role tier and last sign-in; `manageable` says whether the caller may change it. Curators and admins only.';


--
-- Name: list_team_members(integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.list_team_members(p_team_id integer) RETURNS TABLE(email text, is_team_curator boolean, added_at timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NOT (shared.is_curator() OR p_team_id IN (SELECT shared.my_team_ids())) THEN
        RAISE EXCEPTION 'Only curators and members of the team may list its members' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT u.email::text, tm.is_team_curator, tm.created_at
      FROM shared.team_members tm
      JOIN auth.users u ON u.id = tm.user_id
     WHERE tm.team_id = p_team_id
     ORDER BY tm.is_team_curator DESC, u.email;
END;
$$;


ALTER FUNCTION public.list_team_members(p_team_id integer) OWNER TO supabase_admin;

--
-- Name: management_events_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.management_events_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.management_events (
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


ALTER FUNCTION public.management_events_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION management_events_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.management_events_insert() IS 'INSTEAD OF INSERT trigger function for public.managementevents view';


--
-- Name: my_access(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.my_access() RETURNS TABLE(network text, signed_in boolean, app_role text, team_ids integer[])
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
-- plpgsql, not sql: auth.jwt() does not exist yet when a fresh database runs
-- its init files, and a sql function body is checked at creation.
BEGIN
    RETURN QUERY
    SELECT shared.request_network(),
           auth.uid() IS NOT NULL,
           auth.jwt() -> 'app_metadata' ->> 'role',
           ARRAY(SELECT shared.my_team_ids());
END;
$$;


ALTER FUNCTION public.my_access() OWNER TO supabase_admin;

--
-- Name: FUNCTION my_access(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.my_access() IS 'What the database knows about the caller: network (campus or internet), signed in or not, app role, team ids. POST /rest/v1/rpc/my_access.';


--
-- Name: phenology_observations_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.phenology_observations_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.phenology_observations (
        tree_id, observation_date, phenophase_type,
        phenophase_status, intensity_percent, observer, notes, created_by
    ) VALUES (
        NEW.tree_id, NEW.observation_date, NEW.phenophase_type,
        NEW.phenophase_status, NEW.intensity_percent, NEW.observer, NEW.notes, NEW.created_by
    ) RETURNING phenology_observation_id INTO NEW.phenology_observation_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.phenology_observations_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION phenology_observations_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.phenology_observations_insert() IS 'INSTEAD OF INSERT trigger function for public.phenologyobservations view';


--
-- Name: plots_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.plots_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO shared.plots (
        location_id, plot_name, plot_number, area_m2,
        boundary, center_point, description,
        created_by, updated_by,
        sampling_design_id, stratum_id, parent_plot_id, sampling_weight, area_source
    ) VALUES (
        NEW.location_id, NEW.plot_name, NEW.plot_number, NEW.area_m2,
        NEW.boundary, NEW.center_point, NEW.description,
        NEW.created_by, NEW.updated_by,
        NEW.sampling_design_id, NEW.stratum_id, NEW.parent_plot_id,
        coalesce(NEW.sampling_weight, 1), NEW.area_source
    ) RETURNING plot_id INTO NEW.plot_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.plots_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION plots_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.plots_insert() IS 'INSTEAD OF INSERT trigger function for public.plots view';


--
-- Name: point_clouds_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.point_clouds_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO point_clouds.point_clouds SELECT NEW.*;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.point_clouds_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION point_clouds_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.point_clouds_insert() IS 'INSTEAD OF INSERT trigger function for public.pointclouds view';


--
-- Name: qsms_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.qsms_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.qsms (
        tree_entity_id, tree_id, point_cloud_id, process_id,
        lod, local_crs, origin_position, cylinder_count,
        total_volume_m3, trunk_volume_m3, branch_volume_m3,
        dbh_qsm_cm, height_qsm_m, crown_area_qsm_m2,
        is_corrected, created_by
    ) VALUES (
        COALESCE(NEW.tree_entity_id, gen_random_uuid()), NEW.tree_id, NEW.point_cloud_id, NEW.process_id,
        NEW.lod, NEW.local_crs, NEW.origin_position, NEW.cylinder_count,
        NEW.total_volume_m3, NEW.trunk_volume_m3, NEW.branch_volume_m3,
        NEW.dbh_qsm_cm, NEW.height_qsm_m, NEW.crown_area_qsm_m2,
        COALESCE(NEW.is_corrected, false), NEW.created_by
    ) RETURNING qsm_id INTO NEW.qsm_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.qsms_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION qsms_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.qsms_insert() IS 'INSTEAD OF INSERT trigger function for public.qsms view';


--
-- Name: refresh_soil_aggregates(integer, integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.refresh_soil_aggregates(p_location_id integer DEFAULT NULL::integer, p_year integer DEFAULT NULL::integer, p_min_days_per_quarter integer DEFAULT 7, p_dry_run boolean DEFAULT false) RETURNS TABLE(out_location_id integer, out_year integer, out_start_date date, out_end_date date, out_avg_soil_moisture_percent numeric, out_avg_soil_temperature_c numeric, out_environment_id integer, out_status text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'shared', 'sensor', 'environments'
    AS $$
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
$$;


ALTER FUNCTION public.refresh_soil_aggregates(p_location_id integer, p_year integer, p_min_days_per_quarter integer, p_dry_run boolean) OWNER TO supabase_admin;

--
-- Name: FUNCTION refresh_soil_aggregates(p_location_id integer, p_year integer, p_min_days_per_quarter integer, p_dry_run boolean); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.refresh_soil_aggregates(p_location_id integer, p_year integer, p_min_days_per_quarter integer, p_dry_run boolean) IS 'Derive avg_soil_moisture_percent and avg_soil_temperature_c for each location and year from the twin own sensor readings, and write them to environments.Environments under variant_name ''twin-sensors''. The value is a quarter-balanced nested mean -- equal weight per sensor within a day, per day within a quarter, per quarter within the year -- because the readings arrive in four month-long windows whose volumes differ tenfold, and a flat mean would be weighted by sampling density rather than by time. The two quantities are judged separately, so a site can contribute the column it supports. Returns one row per location-year considered, including what it refused: a quantity without four quarters of at least p_min_days_per_quarter measured days, or whose sensors disagree on the unit, is skipped with a reason rather than averaged. Idempotent.';


--
-- Name: remove_team_member(integer, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.remove_team_member(p_team_id integer, p_email text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_user       uuid;
    v_is_curator boolean;
    v_actor      text := (SELECT u.email FROM auth.users u WHERE u.id = auth.uid());
BEGIN
    SELECT u.id INTO v_user FROM auth.users u WHERE lower(u.email) = lower(trim(p_email));
    SELECT tm.is_team_curator INTO v_is_curator
      FROM shared.team_members tm WHERE tm.team_id = p_team_id AND tm.user_id = v_user;
    IF NOT FOUND THEN
        RAISE EXCEPTION '% is not a member of team %', p_email, p_team_id USING ERRCODE = 'P0002';
    END IF;
    IF NOT (shared.is_curator()
            OR (p_team_id IN (SELECT shared.my_curated_team_ids()) AND NOT v_is_curator)) THEN
        RAISE EXCEPTION 'Only curators, or curators of this team removing a plain member, may remove team members'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM shared.team_members tm WHERE tm.team_id = p_team_id AND tm.user_id = v_user;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, old_role, team_id)
    VALUES (auth.uid(), v_actor, lower(trim(p_email)), 'team_remove',
            CASE WHEN v_is_curator THEN 'team_curator' ELSE 'team_member' END, p_team_id);
END;
$$;


ALTER FUNCTION public.remove_team_member(p_team_id integer, p_email text) OWNER TO supabase_admin;

--
-- Name: request_job(text, jsonb, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.request_job(workflow text, params jsonb DEFAULT '{}'::jsonb, external_job_id text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
    ON CONFLICT ON CONSTRAINT processing_jobs_external_job_id_key DO NOTHING
    RETURNING processing_job_id INTO job_id;
    IF job_id IS NULL THEN
        SELECT j.processing_job_id INTO job_id
          FROM shared.processing_jobs j
         WHERE j.external_job_id = request_job.external_job_id;
    END IF;
    RETURN job_id;
END;
$$;


ALTER FUNCTION public.request_job(workflow text, params jsonb, external_job_id text) OWNER TO supabase_admin;

--
-- Name: FUNCTION request_job(workflow text, params jsonb, external_job_id text); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.request_job(workflow text, params jsonb, external_job_id text) IS 'Ask for a workflow run. Validates the workflow against public.workflows and the params against its param_schema, then queues a pending job and returns its id. Pass external_job_id to make the request idempotent -- a repeat with the same key returns the first job instead of queueing a second. SECURITY DEFINER because RLS makes shared.ProcessingJobs read-only to authenticated callers; this function is its only write path. Nothing here says how a workflow runs: the runner resolves workflow_key against its own private config and refuses anything absent from it.';


--
-- Name: reset_account_password(text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.reset_account_password(p_email text) RETURNS TABLE(email text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_email    text := lower(btrim(p_email));
    v_id       uuid;
    v_role     text;
    v_password text;
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can reset passwords'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    SELECT u.id, u.raw_app_meta_data ->> 'role' INTO v_id, v_role
      FROM auth.users u
     WHERE lower(u.email) = v_email AND u.deleted_at IS NULL;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'No account for %', COALESCE(p_email, '(empty)')
            USING ERRCODE = 'P0002';
    END IF;

    IF v_id = auth.uid() THEN
        RAISE EXCEPTION 'Change your own password on the account page instead'
            USING ERRCODE = '42501';
    END IF;

    IF NOT shared.may_manage_role(v_role) THEN
        RAISE EXCEPTION 'You cannot reset the password of a % account', v_role
            USING ERRCODE = '42501',
                  HINT = 'Ask an admin.';
    END IF;

    v_password := shared.new_account_password();

    UPDATE auth.users u
       SET encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
           raw_user_meta_data = COALESCE(u.raw_user_meta_data, '{}'::jsonb)
                                || jsonb_build_object('must_change_password', true),
           updated_at = now()
     WHERE u.id = v_id;

    -- A reset is usually "lost it" or "someone else had it": end every session,
    -- so an old refresh token cannot outlive the password it came with.
    DELETE FROM auth.sessions s WHERE s.user_id = v_id;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, old_role, new_role)
    VALUES (auth.uid(), auth.jwt() ->> 'email', v_email, 'reset_password', v_role, v_role);

    RETURN QUERY SELECT v_email, v_password;
END;
$$;


ALTER FUNCTION public.reset_account_password(p_email text) OWNER TO supabase_admin;

--
-- Name: FUNCTION reset_account_password(p_email text); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.reset_account_password(p_email text) IS 'Give an account a new one-time password and end its sessions. Curators: read-only and contributor accounts; admins: any; never your own. Logged to shared.account_events.';


--
-- Name: roots_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.roots_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.roots (
        tree_entity_id, tree_id, root_system_type_id, lod, geometry_class,
        root_depth_m, root_spread_radius_m, process_id, source, created_by
    ) VALUES (
        COALESCE(NEW.tree_entity_id, gen_random_uuid()), NEW.tree_id, NEW.root_system_type_id, NEW.lod, NEW.geometry_class,
        NEW.root_depth_m, NEW.root_spread_radius_m, NEW.process_id, NEW.source, NEW.created_by
    ) RETURNING root_id INTO NEW.root_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.roots_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION roots_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.roots_insert() IS 'INSTEAD OF INSERT trigger function for public.roots view';


--
-- Name: sensor_readings_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.sensor_readings_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO sensor.sensor_readings (sensor_id, timestamp, value, quality, scenario_id, battery_voltage_v, signal_strength, notes)
    VALUES (NEW.sensor_id, NEW.timestamp, NEW.value, NEW.quality, NEW.scenario_id, NEW.battery_voltage_v, NEW.signal_strength, NEW.notes);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.sensor_readings_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION sensor_readings_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.sensor_readings_insert() IS 'INSTEAD OF INSERT trigger function for public.sensorreadings view';


--
-- Name: sensor_tree_links_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
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


ALTER FUNCTION public.sensor_tree_links_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION sensor_tree_links_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.sensor_tree_links_insert() IS 'INSTEAD OF INSERT trigger for public.sensor_tree_links view';


--
-- Name: sensors_delete(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.sensors_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM sensor.sensors WHERE sensor_id = OLD.sensor_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.sensors_delete() OWNER TO supabase_admin;

--
-- Name: sensors_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.sensors_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO sensor.sensors SELECT NEW.*;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.sensors_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION sensors_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.sensors_insert() IS 'INSTEAD OF INSERT trigger function for public.sensors view';


--
-- Name: sensors_update(); Type: FUNCTION; Schema: public; Owner: supabase_admin
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
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.sensors_update() OWNER TO supabase_admin;

--
-- Name: set_account_role(text, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.set_account_role(p_email text, p_role text DEFAULT NULL::text) RETURNS TABLE(email text, role text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_email text := lower(btrim(p_email));
    v_role  text := NULLIF(btrim(p_role), '');
    v_id    uuid;
    v_old   text;
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can change roles'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    IF v_role IS NOT NULL AND v_role NOT IN ('contributor', 'curator', 'admin') THEN
        RAISE EXCEPTION 'Unknown role: %', v_role
            USING ERRCODE = '22023',
                  HINT = 'Use contributor, curator or admin -- or leave it empty for read-only.';
    END IF;

    SELECT u.id, u.raw_app_meta_data ->> 'role' INTO v_id, v_old
      FROM auth.users u
     WHERE lower(u.email) = v_email AND u.deleted_at IS NULL;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'No account for %', COALESCE(p_email, '(empty)')
            USING ERRCODE = 'P0002';
    END IF;

    -- Nobody changes their own tier: a curator cannot promote themselves, and
    -- an admin cannot lock the lab out by demoting the last admin by accident.
    IF v_id = auth.uid() THEN
        RAISE EXCEPTION 'You cannot change your own role'
            USING ERRCODE = '42501',
                  HINT = 'Ask another admin.';
    END IF;

    IF NOT (shared.may_manage_role(v_old) AND shared.may_manage_role(v_role)) THEN
        RAISE EXCEPTION 'You cannot change a % account to %',
                COALESCE(v_old, 'read-only'), COALESCE(v_role, 'read-only')
            USING ERRCODE = '42501',
                  HINT = 'Curators manage read-only and contributor accounts; only admins grant or revoke curator and admin.';
    END IF;

    UPDATE auth.users u
       SET raw_app_meta_data = CASE WHEN v_role IS NULL
                                    THEN COALESCE(u.raw_app_meta_data, '{}'::jsonb) - 'role'
                                    ELSE COALESCE(u.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', v_role)
                               END,
           updated_at = now()
     WHERE u.id = v_id;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, old_role, new_role)
    VALUES (auth.uid(), auth.jwt() ->> 'email', v_email, 'set_role', v_old, v_role);

    RETURN QUERY SELECT v_email, v_role;
END;
$$;


ALTER FUNCTION public.set_account_role(p_email text, p_role text) OWNER TO supabase_admin;

--
-- Name: FUNCTION set_account_role(p_email text, p_role text); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.set_account_role(p_email text, p_role text) IS 'Set or clear (NULL = read-only) an account''s role tier. Takes effect at its next sign-in or token refresh (at most JWT_EXPIRY later). Curators: between read-only and contributor; admins: any tier; never your own. Logged to shared.account_events.';


--
-- Name: set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text DEFAULT NULL::text, p_license character varying DEFAULT NULL::character varying, p_fetched_at timestamp with time zone DEFAULT now()) RETURNS TABLE(out_written_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'shared'
    AS $_$
DECLARE
    c_settable CONSTANT text[] := ARRAY[
        'elevation_m', 'slope_deg', 'aspect',
        'soil_type_id', 'climate_zone_id',
        'forest_growth_region', 'soil_moistness', 'soil_nutrient_supply'
    ];
    v_rejected text[];
    v_column   text;
    v_type     text;
    v_count    integer := 0;
BEGIN
    IF p_attributes IS NULL OR jsonb_typeof(p_attributes) <> 'object' THEN
        RAISE EXCEPTION 'p_attributes must be a JSON object, got %',
            COALESCE(jsonb_typeof(p_attributes), 'null');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.locations WHERE location_id = p_location_id) THEN
        RAISE EXCEPTION 'no such location: %', p_location_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.processes WHERE process_id = p_process_id) THEN
        RAISE EXCEPTION 'no such process: % -- register the source in shared.Processes first',
            p_process_id;
    END IF;
    SELECT array_agg(k ORDER BY k) INTO v_rejected
      FROM jsonb_object_keys(p_attributes) AS k
     WHERE k <> ALL (c_settable);
    IF v_rejected IS NOT NULL THEN
        RAISE EXCEPTION 'not settable through set_location_attributes: % (settable: %)',
            array_to_string(v_rejected, ', '), array_to_string(c_settable, ', ');
    END IF;
    FOR v_column IN SELECT k FROM jsonb_object_keys(p_attributes) AS k ORDER BY k
    LOOP
        SELECT format_type(a.atttypid, a.atttypmod) INTO v_type
          FROM pg_attribute a
         WHERE a.attrelid = 'shared.locations'::regclass
           AND a.attname  = v_column
           AND a.attnum > 0 AND NOT a.attisdropped;
        -- The cast is to the column's own declared type, so a bad value fails
        -- here rather than being coerced into something plausible.
        EXECUTE format('UPDATE shared.locations SET %I = $1::%s WHERE location_id = $2',
                       v_column, v_type)
          USING p_attributes ->> v_column, p_location_id;
        INSERT INTO shared.attribute_provenance
            (location_id, column_name, process_id, fetched_at, source_uri, license)
        VALUES (p_location_id, v_column, p_process_id, p_fetched_at, p_source_uri, p_license)
        ON CONFLICT (location_id, column_name) DO UPDATE SET
            process_id = EXCLUDED.process_id,
            fetched_at = EXCLUDED.fetched_at,
            source_uri = EXCLUDED.source_uri,
            license    = EXCLUDED.license;
        v_count := v_count + 1;
    END LOOP;
    RETURN QUERY SELECT v_count;
END;
$_$;


ALTER FUNCTION public.set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text, p_license character varying, p_fetched_at timestamp with time zone) OWNER TO supabase_admin;

--
-- Name: FUNCTION set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text, p_license character varying, p_fetched_at timestamp with time zone); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text, p_license character varying, p_fetched_at timestamp with time zone) IS 'Sets site attributes on one shared.Locations row from an open-data source and records where each came from, atomically. p_attributes is a JSON object of column name to value, restricted to elevation_m, slope_deg, aspect, soil_type_id, climate_zone_id, forest_growth_region, soil_moistness and soil_nutrient_supply; any other key raises. Idempotent: re-running with the same input leaves one provenance row per column. Returns the number of columns written.';


--
-- Name: stems_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.stems_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.stems SELECT NEW.*;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.stems_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION stems_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.stems_insert() IS 'INSTEAD OF INSERT trigger function for public.stems view';


--
-- Name: tree_graph_edges_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.tree_graph_edges_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.tree_graph_edges (
        qsm_id, from_cylinder_index, to_cylinder_index, edge_type
    ) VALUES (
        NEW.qsm_id, NEW.from_cylinder_index, NEW.to_cylinder_index, NEW.edge_type
    ) RETURNING edge_id INTO NEW.edge_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.tree_graph_edges_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION tree_graph_edges_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.tree_graph_edges_insert() IS 'INSTEAD OF INSERT trigger function for public.treegraphedges view';


--
-- Name: treegraphedges_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.treegraphedges_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.tree_graph_edges (
        qsm_id, from_cylinder_index, to_cylinder_index, edge_type
    ) VALUES (
        NEW.qsm_id, NEW.from_cylinder_index, NEW.to_cylinder_index, NEW.edge_type
    ) RETURNING tree_graph_edge_id INTO NEW.tree_graph_edge_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.treegraphedges_insert() OWNER TO supabase_admin;

--
-- Name: trees_delete(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.trees_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM trees.trees WHERE tree_id = OLD.tree_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.trees_delete() OWNER TO supabase_admin;

--
-- Name: FUNCTION trees_delete(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.trees_delete() IS 'INSTEAD OF DELETE trigger function for public.trees view';


--
-- Name: trees_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
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
        height_m, height_source, crown_width_m, crown_base_height_m, crown_boundary,
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
        NEW.height_m, NEW.height_source, NEW.crown_width_m, NEW.crown_base_height_m, NEW.crown_boundary,
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


ALTER FUNCTION public.trees_insert() OWNER TO supabase_admin;

--
-- Name: FUNCTION trees_insert(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.trees_insert() IS 'INSTEAD OF INSERT trigger function for public.trees view';


--
-- Name: trees_update(); Type: FUNCTION; Schema: public; Owner: supabase_admin
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
        height_source = NEW.height_source,
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
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trees_update() OWNER TO supabase_admin;

--
-- Name: FUNCTION trees_update(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.trees_update() IS 'INSTEAD OF UPDATE trigger function for public.trees view';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: sensor_readings; Type: TABLE; Schema: sensor; Owner: supabase_admin
--

CREATE TABLE sensor.sensor_readings (
    sensor_reading_id bigint NOT NULL,
    sensor_id integer NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    value numeric(12,4) NOT NULL,
    quality character varying(50),
    scenario_id integer,
    battery_voltage_v numeric(4,2),
    signal_strength numeric(6,2),
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT sensor_readings_quality_check CHECK (((quality)::text = ANY (ARRAY[('good'::character varying)::text, ('suspect'::character varying)::text, ('bad'::character varying)::text, ('missing'::character varying)::text, ('calibration'::character varying)::text])))
);


ALTER TABLE sensor.sensor_readings OWNER TO supabase_admin;

--
-- Name: TABLE sensor_readings; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON TABLE sensor.sensor_readings IS 'Time-series environmental sensor measurements';


--
-- Name: COLUMN sensor_readings.quality; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensor_readings.quality IS 'Data quality flag (good, suspect, bad, missing, calibration)';


--
-- Name: COLUMN sensor_readings.scenario_id; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensor_readings.scenario_id IS 'NULL for real readings, references scenario for simulated data';


--
-- Name: COLUMN sensor_readings.signal_strength; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensor_readings.signal_strength IS 'Wireless signal strength in dBm';


--
-- Name: sensor_types; Type: TABLE; Schema: sensor; Owner: supabase_admin
--

CREATE TABLE sensor.sensor_types (
    sensor_type_id integer NOT NULL,
    sensor_type_name character varying(100) NOT NULL,
    description text,
    typical_unit character varying(50),
    typical_range_min numeric(12,4),
    typical_range_max numeric(12,4),
    CONSTRAINT chk_typical_range CHECK (((typical_range_min IS NULL) OR (typical_range_max IS NULL) OR (typical_range_min <= typical_range_max)))
);


ALTER TABLE sensor.sensor_types OWNER TO supabase_admin;

--
-- Name: TABLE sensor_types; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON TABLE sensor.sensor_types IS 'Environmental sensor type classifications';


--
-- Name: COLUMN sensor_types.typical_unit; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensor_types.typical_unit IS 'Default unit for this sensor type, from sensor.units. NULL where the type has no single natural unit.';


--
-- Name: sensors; Type: TABLE; Schema: sensor; Owner: supabase_admin
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
    source text,
    external_id character varying(200),
    external_metadata jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT chk_decommission_date CHECK (((decommission_date IS NULL) OR (decommission_date >= installation_date))),
    CONSTRAINT chk_value_range CHECK (((min_value IS NULL) OR (max_value IS NULL) OR (min_value <= max_value))),
    CONSTRAINT sensors_battery_level_percent_check CHECK (((battery_level_percent >= (0)::numeric) AND (battery_level_percent <= (100)::numeric))),
    CONSTRAINT sensors_installation_height_m_check CHECK ((installation_height_m >= (0)::numeric)),
    CONSTRAINT sensors_sampling_interval_seconds_check CHECK ((sampling_interval_seconds > 0))
);


ALTER TABLE sensor.sensors OWNER TO supabase_admin;

--
-- Name: TABLE sensors; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON TABLE sensor.sensors IS 'Sensors and the series they produce, physical or modelled. Most rows are physical installations with an instrument, a serial number and a position. Rows whose `source` names a model or reanalysis (e.g. ''open-meteo'') are virtual: one series per location and quantity, no hardware, `serial_number` NULL and no entry in sensor.sensor_tree_links. Discriminate on `source`, never on `sensor_type_id` -- the types are quantities, shared by both kinds.';


--
-- Name: COLUMN sensors.campaign_id; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.campaign_id IS 'Deployment campaign this sensor was installed during';


--
-- Name: COLUMN sensors.plot_id; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.plot_id IS 'Named monitoring sub-area (plot) within the location, e.g. douglas_fir_plot. Populated from the location identifier of the external sensor sync; the site is location_id.';


--
-- Name: COLUMN sensors."position"; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors."position" IS 'PostGIS point for sensor location in WGS84';


--
-- Name: COLUMN sensors.position_original; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.position_original IS 'Original coordinates in source CRS before WGS84 transformation';


--
-- Name: COLUMN sensors.source_crs; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.source_crs IS 'EPSG code of original coordinate reference system for position_original';


--
-- Name: COLUMN sensors.installation_height_m; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.installation_height_m IS 'Height of sensor installation above ground in meters';


--
-- Name: COLUMN sensors.sampling_interval_seconds; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.sampling_interval_seconds IS 'Frequency of sensor measurements in seconds';


--
-- Name: COLUMN sensors.unit; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.unit IS 'Canonical unit of this sensor''s readings, from sensor.units. ASCII with _ as the divisor; render sensor.units.unit_display instead of this value.';


--
-- Name: COLUMN sensors.is_active; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.is_active IS 'Whether sensor is currently collecting data';


--
-- Name: COLUMN sensors.source; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.source IS 'External system this sensor''s data comes from (e.g. ''aquarius''). One of many possible providers.';


--
-- Name: COLUMN sensors.external_id; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.external_id IS 'Unique identifier for this sensor within its source system (see source).';


--
-- Name: COLUMN sensors.external_metadata; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensors.external_metadata IS 'Additional source-specific metadata (raw payload from the provider).';


--
-- Name: ue_sensor_readings; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_sensor_readings WITH (security_invoker='on') AS
 SELECT sr.sensor_reading_id,
    sr.sensor_id,
    st.sensor_type_name,
    s.unit,
    sr."timestamp",
    sr.value,
    sr.quality,
    (EXTRACT(epoch FROM sr."timestamp"))::bigint AS timestamp_unix,
    s.location_id
   FROM ((sensor.sensor_readings sr
     JOIN sensor.sensors s ON ((sr.sensor_id = s.sensor_id)))
     JOIN sensor.sensor_types st ON ((s.sensor_type_id = st.sensor_type_id)));


ALTER TABLE public.ue_sensor_readings OWNER TO supabase_admin;

--
-- Name: VIEW ue_sensor_readings; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_sensor_readings IS 'Enriched sensor time-series for UE Blueprint. Includes sensor type, unit, timestamp_unix (epoch seconds) and the sensor''s location_id, keyed by sensor_id. Look up the linked tree once via ue_sensors, not per reading. GET /ue_sensor_readings?location_id=eq.<site>&order=timestamp.desc&limit=100000 (one site), or ?sensor_id=eq.<id>&order=timestamp.desc&limit=96 (one sensor).';


--
-- Name: ue_sensor_readings_latest(integer, integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.ue_sensor_readings_latest(p_limit integer DEFAULT 100000, p_location_id integer DEFAULT NULL::integer) RETURNS SETOF public.ue_sensor_readings
    LANGUAGE sql STABLE
    AS $$
    SELECT newest.*
      FROM (SELECT r.*
              FROM public.ue_sensor_readings r
             WHERE p_location_id IS NULL OR r.location_id = p_location_id
             ORDER BY r."timestamp" DESC
             LIMIT p_limit) newest
     ORDER BY newest.sensor_id, newest.timestamp_unix;
$$;


ALTER FUNCTION public.ue_sensor_readings_latest(p_limit integer, p_location_id integer) OWNER TO supabase_admin;

--
-- Name: FUNCTION ue_sensor_readings_latest(p_limit integer, p_location_id integer); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.ue_sensor_readings_latest(p_limit integer, p_location_id integer) IS 'The newest p_limit rows of ue_sensor_readings (optionally of one site, p_location_id), returned sorted by sensor_id, then timestamp_unix -- the order Unreal''s DT_SensorReadings wants. Filter by site with p_location_id, not with a PostgREST filter (that applies after the limit). GET /rest/v1/rpc/ue_sensor_readings_latest?p_limit=100000';


--
-- Name: ue_sensor_state_at(timestamp with time zone, interval); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval DEFAULT NULL::interval) RETURNS TABLE(sensor_id integer, source character varying, sensor_type_name character varying, unit character varying, "timestamp" timestamp with time zone, value numeric, quality character varying, tree_id integer)
    LANGUAGE sql STABLE
    AS $$
    SELECT s.sensor_id,
           s.source,
           st.sensor_type_name,
           s.unit,
           r."timestamp",
           r.value,
           r.quality,
           stl.tree_id
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
$$;


ALTER FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval) OWNER TO supabase_admin;

--
-- Name: FUNCTION ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval) IS 'Latest reading per sensor at or before p_timestamp, within p_lookback (default: 4 x the sensor''s sampling_interval_seconds -- one hour for the 15-min network, four hours for hourly series). The scene-wide counterpart to ue_sensor_readings, for driving a VR time slider from one request. Sensors with no reading in the window are absent from the result -- that is deliberate, a gap in the record must not be papered over with a stale value. `source` names the provider: an instrument network such as ''aquarius'', or a model such as ''open-meteo'' whose readings are computed rather than measured. Filter on it before showing a value as an observation. POST /rest/v1/rpc/ue_sensor_state_at  {"p_timestamp":"2025-07-15T12:00:00Z"}';


--
-- Name: upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb DEFAULT '{}'::jsonb, p_scenario_id integer DEFAULT NULL::integer, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_description text DEFAULT NULL::text) RETURNS TABLE(out_environment_id integer, out_inserted boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'shared', 'environments'
    AS $$
DECLARE
    c_settable CONSTANT text[] := ARRAY[
        'avg_temperature_c', 'avg_humidity_percent', 'total_precipitation_mm',
        'avg_global_radiation_w_m2', 'avg_co2_ppm', 'avg_wind_speed_ms',
        'dominant_wind_direction_deg', 'avg_soil_moisture_percent',
        'avg_soil_temperature_c', 'soil_ph', 'nutrient_nitrogen_mg_kg',
        'nutrient_phosphorus_mg_kg', 'nutrient_potassium_mg_kg', 'stress_factor'
    ];
    v_rejected text[];
BEGIN
    IF p_values IS NULL OR jsonb_typeof(p_values) <> 'object' THEN
        RAISE EXCEPTION 'p_values must be a JSON object, got %',
            COALESCE(jsonb_typeof(p_values), 'null');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM shared.processes WHERE process_id = p_process_id) THEN
        RAISE EXCEPTION 'no such process: % -- register the source in shared.Processes first',
            p_process_id;
    END IF;

    SELECT array_agg(k ORDER BY k) INTO v_rejected
      FROM jsonb_object_keys(p_values) AS k
     WHERE k <> ALL (c_settable);

    IF v_rejected IS NOT NULL THEN
        RAISE EXCEPTION 'not settable through upsert_environment: % (settable: %)',
            array_to_string(v_rejected, ', '), array_to_string(c_settable, ', ');
    END IF;

    RETURN QUERY
    INSERT INTO environments.environments AS e (
        location_id, scenario_id, variant_type_id, variant_name,
        start_date, end_date, process_id, description,
        avg_temperature_c, avg_humidity_percent, total_precipitation_mm,
        avg_global_radiation_w_m2, avg_co2_ppm, avg_wind_speed_ms,
        dominant_wind_direction_deg, avg_soil_moisture_percent,
        avg_soil_temperature_c, soil_ph, nutrient_nitrogen_mg_kg,
        nutrient_phosphorus_mg_kg, nutrient_potassium_mg_kg, stress_factor
    )
    SELECT p_location_id, p_scenario_id, p_variant_type_id, p_variant_name,
           p_start_date, p_end_date, p_process_id, p_description,
           v.avg_temperature_c, v.avg_humidity_percent, v.total_precipitation_mm,
           v.avg_global_radiation_w_m2, v.avg_co2_ppm, v.avg_wind_speed_ms,
           v.dominant_wind_direction_deg, v.avg_soil_moisture_percent,
           v.avg_soil_temperature_c, v.soil_ph, v.nutrient_nitrogen_mg_kg,
           v.nutrient_phosphorus_mg_kg, v.nutrient_potassium_mg_kg, v.stress_factor
      FROM jsonb_populate_record(NULL::environments.environments, p_values) AS v
    ON CONFLICT (location_id, scenario_id, variant_type_id, variant_name, start_date, end_date)
    DO UPDATE SET
        process_id                  = EXCLUDED.process_id,
        description                 = COALESCE(EXCLUDED.description,                 e.description),
        avg_temperature_c           = COALESCE(EXCLUDED.avg_temperature_c,           e.avg_temperature_c),
        avg_humidity_percent        = COALESCE(EXCLUDED.avg_humidity_percent,        e.avg_humidity_percent),
        total_precipitation_mm      = COALESCE(EXCLUDED.total_precipitation_mm,      e.total_precipitation_mm),
        avg_global_radiation_w_m2   = COALESCE(EXCLUDED.avg_global_radiation_w_m2,   e.avg_global_radiation_w_m2),
        avg_co2_ppm                 = COALESCE(EXCLUDED.avg_co2_ppm,                 e.avg_co2_ppm),
        avg_wind_speed_ms           = COALESCE(EXCLUDED.avg_wind_speed_ms,           e.avg_wind_speed_ms),
        dominant_wind_direction_deg = COALESCE(EXCLUDED.dominant_wind_direction_deg, e.dominant_wind_direction_deg),
        avg_soil_moisture_percent   = COALESCE(EXCLUDED.avg_soil_moisture_percent,   e.avg_soil_moisture_percent),
        avg_soil_temperature_c      = COALESCE(EXCLUDED.avg_soil_temperature_c,      e.avg_soil_temperature_c),
        soil_ph                     = COALESCE(EXCLUDED.soil_ph,                     e.soil_ph),
        nutrient_nitrogen_mg_kg     = COALESCE(EXCLUDED.nutrient_nitrogen_mg_kg,     e.nutrient_nitrogen_mg_kg),
        nutrient_phosphorus_mg_kg   = COALESCE(EXCLUDED.nutrient_phosphorus_mg_kg,   e.nutrient_phosphorus_mg_kg),
        nutrient_potassium_mg_kg    = COALESCE(EXCLUDED.nutrient_potassium_mg_kg,    e.nutrient_potassium_mg_kg),
        stress_factor               = COALESCE(EXCLUDED.stress_factor,               e.stress_factor)
    RETURNING e.environment_id, (e.xmax = 0);
END;
$$;


ALTER FUNCTION public.upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb, p_scenario_id integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text) OWNER TO supabase_admin;

--
-- Name: FUNCTION upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb, p_scenario_id integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb, p_scenario_id integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text) IS 'Creates or refreshes the one environments.Environments row for a (location, scenario, variant type, variant name, period) and records the producing process. p_values is a JSON object of measurement column to value; any other key raises. Absent keys leave the stored value alone, so two sources can fill different columns of the same period. Idempotent: calling twice with identical input leaves exactly one row. Returns the environment_id and whether the row was newly inserted.';


--
-- Name: aggregate_readings(integer, timestamp with time zone, timestamp with time zone, integer); Type: FUNCTION; Schema: sensor; Owner: supabase_admin
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
    FROM sensor.sensor_readings sr
    WHERE sr.sensor_id = sensor_id_param
        AND sr."Timestamp" >= start_time
        AND sr."Timestamp" <= end_time
        AND sr.Quality IN ('good', 'suspect')
    GROUP BY time_bucket
    ORDER BY time_bucket;
END;
$$;


ALTER FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) OWNER TO supabase_admin;

--
-- Name: FUNCTION aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer); Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) IS 'Aggregates sensor readings into time intervals';


--
-- Name: check_sensor_health(integer, integer); Type: FUNCTION; Schema: sensor; Owner: supabase_admin
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
$$;


ALTER FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) OWNER TO supabase_admin;

--
-- Name: FUNCTION check_sensor_health(sensor_id_param integer, hours_back integer); Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) IS 'Checks sensor health based on recent reading patterns';


--
-- Name: get_latest_reading(integer); Type: FUNCTION; Schema: sensor; Owner: supabase_admin
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
    FROM sensor.sensor_readings sr
    WHERE sr.sensor_id = sensor_id_param
    ORDER BY sr."Timestamp" DESC
    LIMIT 1;
END;
$$;


ALTER FUNCTION sensor.get_latest_reading(sensor_id_param integer) OWNER TO supabase_admin;

--
-- Name: FUNCTION get_latest_reading(sensor_id_param integer); Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) IS 'Returns the most recent reading for a sensor';


--
-- Name: link_sensors_to_trees_by_pattern(); Type: FUNCTION; Schema: sensor; Owner: supabase_admin
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
$_$;


ALTER FUNCTION sensor.link_sensors_to_trees_by_pattern() OWNER TO supabase_admin;

--
-- Name: FUNCTION link_sensors_to_trees_by_pattern(); Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON FUNCTION sensor.link_sensors_to_trees_by_pattern() IS 'DEPRECATED - unreliable (see 32-ecosense-sensor-tree-map.sql). Use scripts/import/link_sensors_to_trees.py, which links via trees.sensor_ref.';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: sensor; Owner: supabase_admin
--

CREATE FUNCTION sensor.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION sensor.update_updated_at_column() OWNER TO supabase_admin;

--
-- Name: attribute_is_acquired(integer, text); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM shared.attribute_provenance
        WHERE location_id = p_location_id
          AND column_name = p_column_name
    );
$$;


ALTER FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) OWNER TO supabase_admin;

--
-- Name: FUNCTION attribute_is_acquired(p_location_id integer, p_column_name text); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) IS 'True when a shared.Locations column was written by an acquisition process and therefore must not be reseeded from data/lookups/locations.csv (XRFF-391).';


--
-- Name: audit_update_trigger(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.audit_update_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    audit_log_id BIGINT;
    record_id INTEGER;
    v_reason TEXT;
BEGIN
    -- NULL unless the caller set it for this transaction.
    v_reason := NULLIF(current_setting('app.change_reason', true), '');

    CASE TG_TABLE_NAME
        WHEN 'point_clouds' THEN
            record_id := NEW.point_cloud_id;
        WHEN 'trees' THEN
            record_id := NEW.tree_id;
        WHEN 'environments' THEN
            record_id := NEW.environment_id;
        WHEN 'stems' THEN
            record_id := NEW.stem_id;
        WHEN 'phenology_observations' THEN
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
                PERFORM shared.create_audit_log('trees', record_id, 'Height_m', OLD.Height_m::TEXT, NEW.Height_m::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.crown_width_m IS DISTINCT FROM NEW.crown_width_m THEN
                PERFORM shared.create_audit_log('trees', record_id, 'crown_width_m', OLD.crown_width_m::TEXT, NEW.crown_width_m::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31: derived attributes filled by allometry.
            IF OLD.crown_base_height_m IS DISTINCT FROM NEW.crown_base_height_m THEN
                PERFORM shared.create_audit_log('trees', record_id, 'crown_base_height_m', OLD.crown_base_height_m::TEXT, NEW.crown_base_height_m::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.volume_m3 IS DISTINCT FROM NEW.volume_m3 THEN
                PERFORM shared.create_audit_log('trees', record_id, 'volume_m3', OLD.volume_m3::TEXT, NEW.volume_m3::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31 (follow-up): age is derived from height by
            -- allometric inversion, so it needs a trail like the rest.
            IF OLD.age_years IS DISTINCT FROM NEW.age_years THEN
                PERFORM shared.create_audit_log('trees', record_id, 'age_years', OLD.age_years::TEXT, NEW.age_years::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31 (follow-up): biomass and carbon are derived from
            -- DBH and height by allometry, so they need a trail like the rest.
            IF OLD.biomass_kg IS DISTINCT FROM NEW.biomass_kg THEN
                PERFORM shared.create_audit_log('trees', record_id, 'biomass_kg', OLD.biomass_kg::TEXT, NEW.biomass_kg::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.carbon_content_kg IS DISTINCT FROM NEW.carbon_content_kg THEN
                PERFORM shared.create_audit_log('trees', record_id, 'carbon_content_kg', OLD.carbon_content_kg::TEXT, NEW.carbon_content_kg::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.health_score IS DISTINCT FROM NEW.health_score THEN
                PERFORM shared.create_audit_log('trees', record_id, 'health_score', OLD.health_score::TEXT, NEW.health_score::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.tree_status_id IS DISTINCT FROM NEW.tree_status_id THEN
                PERFORM shared.create_audit_log('trees', record_id, 'tree_status_id', OLD.tree_status_id::TEXT, NEW.tree_status_id::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'stems' THEN
            IF OLD.DBH_cm IS DISTINCT FROM NEW.DBH_cm THEN
                PERFORM shared.create_audit_log('stems', record_id, 'DBH_cm', OLD.DBH_cm::TEXT, NEW.DBH_cm::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.stem_height_m IS DISTINCT FROM NEW.stem_height_m THEN
                PERFORM shared.create_audit_log('stems', record_id, 'stem_height_m', OLD.stem_height_m::TEXT, NEW.stem_height_m::TEXT, v_reason, 'field_update');
            END IF;
            -- Added 2026-08-31.
            IF OLD.stem_volume_m3 IS DISTINCT FROM NEW.stem_volume_m3 THEN
                PERFORM shared.create_audit_log('stems', record_id, 'stem_volume_m3', OLD.stem_volume_m3::TEXT, NEW.stem_volume_m3::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'environments' THEN
            IF OLD.avg_temperature_c IS DISTINCT FROM NEW.avg_temperature_c THEN
                PERFORM shared.create_audit_log('environments', record_id, 'avg_temperature_c', OLD.avg_temperature_c::TEXT, NEW.avg_temperature_c::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.stress_factor IS DISTINCT FROM NEW.stress_factor THEN
                PERFORM shared.create_audit_log('environments', record_id, 'stress_factor', OLD.stress_factor::TEXT, NEW.stress_factor::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'point_clouds' THEN
            IF OLD.processing_status IS DISTINCT FROM NEW.processing_status THEN
                PERFORM shared.create_audit_log('point_clouds', record_id, 'processing_status', OLD.processing_status::TEXT, NEW.processing_status::TEXT, v_reason, 'field_update');
            END IF;

        WHEN 'phenology_observations' THEN
            IF OLD.phenophase_status IS DISTINCT FROM NEW.phenophase_status THEN
                PERFORM shared.create_audit_log('phenology_observations', record_id, 'phenophase_status', OLD.phenophase_status::TEXT, NEW.phenophase_status::TEXT, v_reason, 'field_update');
            END IF;
            IF OLD.intensity_percent IS DISTINCT FROM NEW.intensity_percent THEN
                PERFORM shared.create_audit_log('phenology_observations', record_id, 'intensity_percent', OLD.intensity_percent::TEXT, NEW.intensity_percent::TEXT, v_reason, 'field_update');
            END IF;
    END CASE;

    RETURN NEW;
END;
$$;


ALTER FUNCTION shared.audit_update_trigger() OWNER TO supabase_admin;

--
-- Name: FUNCTION audit_update_trigger(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.audit_update_trigger() IS 'Records column-level changes into shared.AuditLog. Set app.change_reason (SET LOCAL) before an UPDATE to record why a value changed; leave it unset for ordinary edits.';


--
-- Name: check_inclusion_rule_overlap(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.check_inclusion_rule_overlap() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM shared.inclusion_rules r
         WHERE r.sampling_design_id = NEW.sampling_design_id
           AND r.inclusion_rule_id <> NEW.inclusion_rule_id
           AND numrange(r.min_dbh_cm, r.max_dbh_cm, '[)') && numrange(NEW.min_dbh_cm, NEW.max_dbh_cm, '[)')
    ) THEN
        RAISE EXCEPTION 'Inclusion rule DBH range [%, %) overlaps another rule of sampling design %',
            NEW.min_dbh_cm, coalesce(NEW.max_dbh_cm::text, 'inf'), NEW.sampling_design_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION shared.check_inclusion_rule_overlap() OWNER TO supabase_admin;

--
-- Name: create_audit_log(character varying, integer, character varying, text, text, text, character varying); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text DEFAULT NULL::text, change_type_param character varying DEFAULT 'field_update'::character varying) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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
$$;


ALTER FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying) OWNER TO supabase_admin;

--
-- Name: FUNCTION create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying) IS 'Creates audit log entry with junction table link';


--
-- Name: current_user_id(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.current_user_id() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    RETURN auth.uid()::TEXT;
END;
$$;


ALTER FUNCTION shared.current_user_id() OWNER TO supabase_admin;

--
-- Name: FUNCTION current_user_id(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.current_user_id() IS 'Returns current authenticated user ID';


--
-- Name: ef_value(boolean, text, numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT (CASE
        WHEN p_min_dbh_cm IS NOT NULL AND (p_dbh_cm IS NULL OR p_dbh_cm < p_min_dbh_cm) THEN NULL
        WHEN p_has_rules THEN CASE p_rule_type
            WHEN 'fixed_radius' THEN 10000 / (pg_catalog.pi() * p_radius_m ^ 2)
            WHEN 'angle_count'  THEN p_basal_area_factor_m2ha / (pg_catalog.pi() * (p_dbh_cm / 200.0) ^ 2)
        END
        WHEN p_area_m2 > 0 THEN 10000 / p_area_m2
    END)::numeric;
$$;


ALTER FUNCTION shared.ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric) OWNER TO supabase_admin;

--
-- Name: FUNCTION ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric) IS 'The expansion-factor formula, given an already resolved design (has rules?), the inclusion rule matching the DBH (NULL when none), the inclusion area and the minimum DBH: fixed radius 10000/(pi r²), angle count BAF/basal area, otherwise 10000/area. Inlinable: no SET clause, only pg_catalog calls. Used by shared.expansion_factor_ha and the summary views.';


--
-- Name: estimate_stand(integer, integer, boolean, numeric); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean DEFAULT false, p_confidence numeric DEFAULT 0.95) RETURNS TABLE(sampling_design_id integer, variant_id integer, by_species boolean, species_id integer, variable text, unit text, estimate numeric, standard_error numeric, relative_standard_error_pct numeric, margin_of_error numeric, sampling_error_pct numeric, ci_low numeric, ci_high numeric, confidence numeric, n_units integer, area_ha numeric, total numeric, total_standard_error numeric, method text)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
    SELECT * FROM shared.estimate_stand_domains(p_sampling_design_id, p_variant_id,
                                                NOT p_by_species, p_by_species, p_confidence);
$$;


ALTER FUNCTION shared.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) OWNER TO supabase_admin;

--
-- Name: FUNCTION estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) IS 'Design-based estimate per variable (stems, basal area, volume, biomass, carbon per hectare) for one sampling design and variant: mean, standard error, confidence interval (0.90/0.95/0.99), number of units, area and total. Census, simple random, systematic (as simple random) and stratified designs; two_phase returns NULLs. With-replacement variance, no finite population correction. `method` states which estimator was used.';


--
-- Name: estimate_stand_domains(integer, integer, boolean, boolean, numeric); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric) RETURNS TABLE(sampling_design_id integer, variant_id integer, by_species boolean, species_id integer, variable text, unit text, estimate numeric, standard_error numeric, relative_standard_error_pct numeric, margin_of_error numeric, sampling_error_pct numeric, ci_low numeric, ci_high numeric, confidence numeric, n_units integer, area_ha numeric, total numeric, total_standard_error numeric, method text)
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
DECLARE
    v_strategy   text;
    v_reporting  numeric;
    v_has_rules  boolean;
    v_location   integer;
    v_stratified boolean;
    v_method     text;
BEGIN
    IF p_confidence IS NULL OR p_confidence NOT IN (0.90, 0.95, 0.99) THEN
        RAISE EXCEPTION 'confidence must be 0.90, 0.95 or 0.99, got %', p_confidence;
    END IF;

    SELECT d.strategy, d.reporting_area_ha,
           EXISTS (SELECT 1 FROM shared.inclusion_rules r WHERE r.sampling_design_id = d.sampling_design_id)
      INTO v_strategy, v_reporting, v_has_rules
      FROM shared.sampling_designs d
     WHERE d.sampling_design_id = p_sampling_design_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT v.location_id INTO v_location FROM shared.variants v WHERE v.variant_id = p_variant_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    v_stratified := v_strategy IN ('stratified_random', 'stratified_systematic');
    v_method := CASE v_strategy
        WHEN 'census'                THEN 'census: area-weighted mean of the census units, no sampling error'
        WHEN 'simple_random'         THEN 'simple random: weighted mean, with-replacement variance, no finite population correction'
        WHEN 'systematic'            THEN 'systematic, estimated as simple random (usually overstates the error): weighted mean, with-replacement variance, no finite population correction'
        WHEN 'stratified_random'     THEN 'stratified: per-stratum weighted mean combined by stratum area, with-replacement variance, no finite population correction'
        WHEN 'stratified_systematic' THEN 'stratified systematic, estimated as stratified random: per-stratum weighted mean combined by stratum area, with-replacement variance, no finite population correction'
        ELSE 'not supported: ' || v_strategy
    END;

    RETURN QUERY
    WITH units AS (
        -- Sample units of the design at the variant's site. Rule designs: every
        -- plot of the design without child plots of the design. Area designs:
        -- every plot of the design with an area.
        SELECT p.plot_id, p.stratum_id, p.sampling_weight AS w, p.area_m2
          FROM shared.plots p
         WHERE p.sampling_design_id = p_sampling_design_id
           AND p.location_id = v_location
           AND CASE WHEN v_has_rules
                    THEN NOT EXISTS (SELECT 1 FROM shared.plots c
                                      WHERE c.parent_plot_id = p.plot_id
                                        AND c.sampling_design_id = p_sampling_design_id)
                    ELSE p.area_m2 > 0
               END
    ),
    ps AS (
        SELECT s.*
          FROM public.plot_summaries s
         WHERE s.variant_id = p_variant_id
           AND s.plot_id IN (SELECT u.plot_id FROM units u)
    ),
    domains AS (
        SELECT DISTINCT ps.species_id, true AS by_sp FROM ps WHERE p_per_species
        UNION ALL
        SELECT NULL::integer, false WHERE p_all_species
    ),
    vars (variable, unit, ord) AS (
        VALUES ('stems_ha', '1/ha', 1), ('basal_area_m2ha', 'm2/ha', 2), ('volume_m3ha', 'm3/ha', 3),
               ('biomass_tha', 't/ha', 4), ('carbon_tha', 't/ha', 5)
    ),
    y AS (
        -- one value per unit, domain and variable; a unit without trees in the
        -- domain is a zero, a unit with an incomplete value is NULL
        SELECT u.plot_id, u.stratum_id, u.w, u.area_m2, dm.species_id, dm.by_sp,
               vr.variable, vr.unit, vr.ord,
               CASE WHEN count(ps.plot_id) = 0 THEN 0
                    WHEN bool_and(CASE vr.variable
                                      WHEN 'stems_ha'        THEN ps.stems_ha
                                      WHEN 'basal_area_m2ha' THEN ps.basal_area_m2ha
                                      WHEN 'volume_m3ha'     THEN ps.volume_m3ha
                                      WHEN 'biomass_tha'     THEN ps.biomass_tha
                                      WHEN 'carbon_tha'      THEN ps.carbon_tha
                                  END IS NOT NULL)
                    THEN sum(CASE vr.variable
                                 WHEN 'stems_ha'        THEN ps.stems_ha
                                 WHEN 'basal_area_m2ha' THEN ps.basal_area_m2ha
                                 WHEN 'volume_m3ha'     THEN ps.volume_m3ha
                                 WHEN 'biomass_tha'     THEN ps.biomass_tha
                                 WHEN 'carbon_tha'      THEN ps.carbon_tha
                             END)
               END AS y
          FROM units u
         CROSS JOIN domains dm
         CROSS JOIN vars vr
          LEFT JOIN ps ON ps.plot_id = u.plot_id
                      AND (NOT dm.by_sp OR ps.species_id IS NOT DISTINCT FROM dm.species_id)
         GROUP BY u.plot_id, u.stratum_id, u.w, u.area_m2, dm.species_id, dm.by_sp,
                  vr.variable, vr.unit, vr.ord
    ),
    per_stratum AS (
        SELECT y.species_id, y.by_sp, y.variable, y.unit, y.ord,
               CASE WHEN v_stratified THEN y.stratum_id ELSE 0 END AS h,
               count(*)                     AS n_h,
               bool_and(y.y IS NOT NULL)    AS complete,
               sum(y.w)                     AS w_h,
               sum(y.w * y.y) / sum(y.w)    AS ybar_h,
               sum(y.area_m2 * y.y) / nullif(sum(y.area_m2), 0) AS area_mean_h,
               sum(y.area_m2)               AS area_m2_h
          FROM y
         GROUP BY 1, 2, 3, 4, 5, 6
    ),
    with_var AS (
        SELECT s.*,
               CASE WHEN s.n_h >= 2
                    THEN s.n_h::numeric / (s.n_h - 1)
                         * (SELECT sum((y.w * (y.y - s.ybar_h)) ^ 2)
                              FROM y
                             WHERE y.species_id IS NOT DISTINCT FROM s.species_id
                               AND y.by_sp = s.by_sp
                               AND y.variable = s.variable
                               AND (CASE WHEN v_stratified THEN y.stratum_id ELSE 0 END)
                                   IS NOT DISTINCT FROM s.h)
                         / s.w_h ^ 2
               END AS var_h,
               st.area_ha AS stratum_area_ha
          FROM per_stratum s
          LEFT JOIN shared.strata st ON v_stratified AND st.stratum_id = s.h
    ),
    combined AS (
        SELECT c.species_id, c.by_sp, c.variable, c.unit, c.ord,
               sum(c.n_h)::integer                          AS n,
               count(*)                                     AS n_strata,
               bool_and(c.complete)                         AS complete,
               bool_and(c.h IS NOT NULL AND (NOT v_stratified OR c.stratum_area_ha IS NOT NULL))
                                                            AS weights_ok,
               bool_and(c.var_h IS NOT NULL)                AS var_ok,
               sum(c.stratum_area_ha)                       AS strata_area_ha,
               sum(c.area_m2_h) / 10000                     AS census_area_ha,
               CASE WHEN v_strategy = 'census'
                    THEN sum(c.area_mean_h * c.area_m2_h) / nullif(sum(c.area_m2_h), 0)
                    WHEN v_stratified
                    THEN sum(c.stratum_area_ha * c.ybar_h) / nullif(sum(c.stratum_area_ha), 0)
                    ELSE sum(c.ybar_h)
               END                                          AS est,
               CASE WHEN v_stratified
                    THEN sum((c.stratum_area_ha / nullif((SELECT sum(c2.stratum_area_ha) FROM with_var c2
                                                          WHERE c2.species_id IS NOT DISTINCT FROM c.species_id
                                                            AND c2.by_sp = c.by_sp AND c2.variable = c.variable), 0)) ^ 2
                             * c.var_h)
                    ELSE sum(c.var_h)
               END                                          AS var
          FROM with_var c
         GROUP BY 1, 2, 3, 4, 5
    ),
    final AS (
        SELECT c.*,
               CASE WHEN v_strategy NOT IN ('census', 'simple_random', 'systematic',
                                            'stratified_random', 'stratified_systematic')
                         OR NOT c.complete OR NOT c.weights_ok
                    THEN NULL ELSE c.est END AS est_ok,
               CASE WHEN v_strategy IN ('simple_random', 'systematic',
                                        'stratified_random', 'stratified_systematic')
                         AND c.complete AND c.weights_ok AND c.var_ok
                    THEN sqrt(c.var) END AS se,
               shared.t_quantile(p_confidence, (c.n - c.n_strata)::integer) AS tq,
               CASE WHEN v_strategy = 'census' THEN c.census_area_ha
                    WHEN v_stratified THEN c.strata_area_ha END AS area
          FROM combined c
    )
    SELECT p_sampling_design_id,
           p_variant_id,
           f.by_sp,
           f.species_id,
           f.variable,
           f.unit,
           round(f.est_ok, 4),
           round(f.se, 4),
           round(100 * f.se / nullif(f.est_ok, 0), 2),
           round(f.tq * f.se, 4),
           round(100 * f.tq * f.se / nullif(f.est_ok, 0), 2),
           round(f.est_ok - f.tq * f.se, 4),
           round(f.est_ok + f.tq * f.se, 4),
           p_confidence,
           f.n,
           round(f.area, 4),
           round(f.est_ok * coalesce(v_reporting, f.area), 2),
           round(f.se * coalesce(v_reporting, f.area), 2),
           v_method
      FROM final f
     ORDER BY f.by_sp, f.species_id NULLS FIRST, f.ord;
END;
$$;


ALTER FUNCTION shared.estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric) OWNER TO supabase_admin;

--
-- Name: FUNCTION estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric) IS 'The design-based estimator behind shared.estimate_stand, returning the all-species rows (by_species false), the per-species rows, or both from one pass over the trees. See shared.estimate_stand for the method.';


--
-- Name: expansion_factor_ha(integer, numeric); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
    WITH RECURSIVE up AS (
        SELECT p.parent_plot_id, p.sampling_design_id, p.area_m2, 0 AS depth
          FROM shared.plots p
         WHERE p.plot_id = p_plot_id
        UNION ALL
        SELECT q.parent_plot_id, q.sampling_design_id, q.area_m2, up.depth + 1
          FROM shared.plots q
          JOIN up ON q.plot_id = up.parent_plot_id
         WHERE up.depth < 10
    ),
    resolved AS (
        SELECT EXISTS (SELECT 1 FROM up) AS plot_exists,
               (SELECT u.sampling_design_id FROM up u WHERE u.sampling_design_id IS NOT NULL
                 ORDER BY u.depth LIMIT 1) AS design_id,
               (SELECT u.area_m2 FROM up u WHERE u.area_m2 > 0
                 ORDER BY u.depth LIMIT 1) AS area_m2
    )
    SELECT CASE WHEN res.plot_exists THEN
               shared.ef_value(
                   EXISTS (SELECT 1 FROM shared.inclusion_rules r WHERE r.sampling_design_id = res.design_id),
                   ir.rule_type, ir.radius_m, ir.basal_area_factor_m2ha,
                   res.area_m2, d.min_dbh_cm, p_dbh_cm)
           END
      FROM resolved res
      LEFT JOIN shared.sampling_designs d ON d.sampling_design_id = res.design_id
      LEFT JOIN shared.inclusion_rules ir
             ON ir.sampling_design_id = res.design_id
            AND p_dbh_cm >= ir.min_dbh_cm
            AND (ir.max_dbh_cm IS NULL OR p_dbh_cm < ir.max_dbh_cm)
            AND p_dbh_cm > 0;
$$;


ALTER FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric) OWNER TO supabase_admin;

--
-- Name: FUNCTION expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric) IS 'Trees per hectare that one tree of the given DBH on the given plot stands for, from the sampling design: fixed radius 10000/(pi r²), angle count BAF/basal area, otherwise 10000/area_m2. Design and area come from the plot or, where it has none, its nearest enclosing plot (a fully mapped site: one census plot with the area, the plots inside it as labels). NULL when unknown. Excludes the sampling weight.';


--
-- Name: get_audit_history(character varying, integer, integer); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer DEFAULT 100) RETURNS TABLE(audit_log_id bigint, field_name character varying, old_value text, new_value text, change_reason text, user_id character varying, "Timestamp" timestamp with time zone, change_type character varying)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    AS $$
BEGIN
    IF table_name_param = 'point_clouds' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_point_clouds alpc ON al.audit_log_id = alpc.audit_log_id
            WHERE alpc.point_cloud_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'trees' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_trees alt ON al.audit_log_id = alt.audit_log_id
            WHERE alt.tree_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'environments' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_environments ale ON al.audit_log_id = ale.audit_log_id
            WHERE ale.environment_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'stems' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_stems als ON al.audit_log_id = als.audit_log_id
            WHERE als.stem_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'phenology_observations' THEN
        RETURN QUERY
            SELECT al.audit_log_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.audit_log al
            JOIN shared.audit_log_phenology_observations alp ON al.audit_log_id = alp.audit_log_id
            WHERE alp.phenology_observation_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSE
        RAISE EXCEPTION 'Unknown table name %: use point_clouds, trees, environments, stems or phenology_observations', table_name_param;
    END IF;
    RETURN;
END;
$$;


ALTER FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer) OWNER TO supabase_admin;

--
-- Name: has_restricted_campaigns(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.has_restricted_campaigns() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT EXISTS (SELECT 1 FROM shared.campaigns c
                    WHERE c.access_level <> 'public' OR c.embargo_until > current_date);
$$;


ALTER FUNCTION shared.has_restricted_campaigns() OWNER TO supabase_admin;

--
-- Name: FUNCTION has_restricted_campaigns(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.has_restricted_campaigns() IS 'True when any campaign is not public or is under embargo. Child-table policies use it to skip their parent check while everything is public.';


--
-- Name: hidden_observation_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.hidden_observation_ids() RETURNS SETOF bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT o.observation_id FROM trees.observations o
     WHERE o.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$$;


ALTER FUNCTION shared.hidden_observation_ids() OWNER TO supabase_admin;

--
-- Name: hidden_point_cloud_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.hidden_point_cloud_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT pc.point_cloud_id FROM point_clouds.point_clouds pc
     WHERE pc.campaign_id IS NOT NULL
       AND pc.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$$;


ALTER FUNCTION shared.hidden_point_cloud_ids() OWNER TO supabase_admin;

--
-- Name: hidden_qsm_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.hidden_qsm_ids() RETURNS SETOF bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT q.qsm_id FROM trees.qsms q
     WHERE q.tree_id IN (SELECT shared.hidden_tree_ids())
        OR q.point_cloud_id IN (SELECT shared.hidden_point_cloud_ids());
$$;


ALTER FUNCTION shared.hidden_qsm_ids() OWNER TO supabase_admin;

--
-- Name: hidden_sensor_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.hidden_sensor_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT s.sensor_id FROM sensor.sensors s
     WHERE s.campaign_id IS NOT NULL
       AND s.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$$;


ALTER FUNCTION shared.hidden_sensor_ids() OWNER TO supabase_admin;

--
-- Name: hidden_tree_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.hidden_tree_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT t.tree_id FROM trees.trees t
     WHERE t.campaign_id IS NOT NULL
       AND t.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$$;


ALTER FUNCTION shared.hidden_tree_ids() OWNER TO supabase_admin;

--
-- Name: is_admin(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.is_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
END;
$$;


ALTER FUNCTION shared.is_admin() OWNER TO supabase_admin;

--
-- Name: FUNCTION is_admin(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.is_admin() IS 'RDA tier: Administrator - full user/role management, implies Curator rights';


--
-- Name: is_contributor(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.is_contributor() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'curator', 'contributor'), false);
END;
$$;


ALTER FUNCTION shared.is_contributor() OWNER TO supabase_admin;

--
-- Name: FUNCTION is_contributor(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.is_contributor() IS 'RDA tier: Contributor - can insert new field-data records, no alter/delete';


--
-- Name: is_curator(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.is_curator() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    RETURN COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'curator'), false);
END;
$$;


ALTER FUNCTION shared.is_curator() OWNER TO supabase_admin;

--
-- Name: FUNCTION is_curator(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.is_curator() IS 'RDA tier: Curator - can alter/delete field-data records';


--
-- Name: may_manage_role(text); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.may_manage_role(p_role text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT CASE
        WHEN shared.is_admin()   THEN p_role IS NULL OR p_role IN ('contributor', 'curator', 'admin')
        WHEN shared.is_curator() THEN p_role IS NULL OR p_role = 'contributor'
        ELSE false
    END;
$$;


ALTER FUNCTION shared.may_manage_role(p_role text) OWNER TO supabase_admin;

--
-- Name: FUNCTION may_manage_role(p_role text); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.may_manage_role(p_role text) IS 'True when the caller may grant, revoke or reset an account at this role tier (NULL = no role). Admins: every tier. Curators: no role and contributor only.';


--
-- Name: my_curated_team_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.my_curated_team_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT tm.team_id FROM shared.team_members tm WHERE tm.user_id = auth.uid() AND tm.is_team_curator;
$$;


ALTER FUNCTION shared.my_curated_team_ids() OWNER TO supabase_admin;

--
-- Name: my_team_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.my_team_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT tm.team_id FROM shared.team_members tm WHERE tm.user_id = auth.uid();
$$;


ALTER FUNCTION shared.my_team_ids() OWNER TO supabase_admin;

--
-- Name: new_account_password(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.new_account_password() RETURNS text
    LANGUAGE sql
    SET search_path TO ''
    AS $$
    -- 15 random bytes -> 20 URL-safe characters, no padding, no look-alike
    -- trouble from '+' and '/' when it is read out over the phone.
    SELECT translate(encode(extensions.gen_random_bytes(15), 'base64'), '+/', '-_');
$$;


ALTER FUNCTION shared.new_account_password() OWNER TO supabase_admin;

--
-- Name: readable_campaign_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.readable_campaign_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT c.campaign_id
      FROM shared.campaigns c
     WHERE shared.is_curator()
        OR c.owner_team_id IN (SELECT shared.my_team_ids())
        OR ((c.embargo_until IS NULL OR c.embargo_until <= current_date)
            AND (c.access_level = 'public'
                 OR (c.access_level = 'campus'
                     AND (shared.request_network() = 'campus' OR auth.uid() IS NOT NULL))
                 OR (c.access_level = 'registered' AND auth.uid() IS NOT NULL)));
$$;


ALTER FUNCTION shared.readable_campaign_ids() OWNER TO supabase_admin;

--
-- Name: FUNCTION readable_campaign_ids(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.readable_campaign_ids() IS 'Campaigns the caller may read: all for curators and admins; their teams'' campaigns for team members; otherwise, outside an embargo, public ones, campus ones from the university network or with an account, registered ones with an account.';


--
-- Name: refresh_all_lookups(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
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


ALTER FUNCTION shared.refresh_all_lookups() OWNER TO supabase_admin;

--
-- Name: FUNCTION refresh_all_lookups(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.refresh_all_lookups() IS 'Reload all lookup tables from CSV files without full database rebuild';


--
-- Name: refresh_lookup(text); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.refresh_lookup(p_table_name text) RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    v_rows_before INT;
    v_rows_after  INT;
    v_csv_path    TEXT := '/var/lib/postgresql/lookups/';
    v_key         TEXT;
BEGIN
    p_table_name := lower(trim(p_table_name));

    -- Resolve an alias to its registry key: callers have historically passed
    -- both the logical key and the (then squashed) table name.
    -- Aliased: lookup_registry.table_name would otherwise be ambiguous against
    -- this function's OUT parameter of the same name.
    SELECT lr.logical_key INTO v_key FROM shared.lookup_registry lr
     WHERE lr.logical_key = p_table_name
        OR replace(lr.table_name, '_', '') = replace(p_table_name, '_', '')
        OR lr.table_name = p_table_name
     LIMIT 1;

    IF v_key IS NOT NULL THEN
        RETURN QUERY SELECT * FROM shared.refresh_lookup_generic(v_key);
        RETURN;
    END IF;

    -- Everything else keeps a bespoke branch, because its CSV columns are
    -- constructed (a PostGIS point from lat/long) or resolved (a name to an FK)
    -- rather than stored, and locations additionally preserves acquired site
    -- attributes (XRFF-391).
    CASE p_table_name
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
        WHEN 'scenarios' THEN
            -- Scenarios are location-scoped (Scenarios.location_id NOT NULL,
            -- UNIQUE(location_id, scenario_name)) and are created per site by the
            -- growth-variant seed scripts — not a refreshable global lookup CSV.
            SELECT COUNT(*) INTO v_rows_before FROM shared.scenarios;
            RAISE NOTICE 'scenarios are location-scoped; not refreshed from a global CSV (skipped)';
            v_rows_after := v_rows_before;
        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0,
                ('ERROR: unknown lookup. Registry keys: ' ||
                 (SELECT string_agg(logical_key, ', ' ORDER BY logical_key)
                    FROM shared.lookup_registry) ||
                 ', plus locations, scenarios')::TEXT;
            RETURN;
    END CASE;

    -- The bespoke branches above set the counters and fall through to here,
    -- which is where the original function returned its row. Dropping this tail
    -- made locations and scenarios return no row at all while still reporting
    -- success in the logs.
    RETURN QUERY SELECT p_table_name, v_rows_before, v_rows_after, 'OK'::TEXT;
END;
$$;


ALTER FUNCTION shared.refresh_lookup(p_table_name text) OWNER TO supabase_admin;

--
-- Name: FUNCTION refresh_lookup(p_table_name text); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.refresh_lookup(p_table_name text) IS 'Reload a specific lookup table from its CSV file without full database rebuild';


--
-- Name: refresh_lookup_generic(text); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.refresh_lookup_generic(p_key text) RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    r            shared.lookup_registry%ROWTYPE;
    v_before     INT;
    v_after      INT;
    v_qualified  TEXT;
    v_tempcols   TEXT;
    v_collist    TEXT;
    v_selectlist TEXT;
    v_updates    TEXT;
    v_col        TEXT;
    v_type       TEXT;
BEGIN
    SELECT * INTO r FROM shared.lookup_registry WHERE logical_key = lower(trim(p_key));
    IF NOT FOUND THEN
        RETURN QUERY SELECT p_key, 0, 0, 'ERROR: not in shared.lookup_registry'::TEXT;
        RETURN;
    END IF;

    v_qualified := format('%I.%I', r.schema_name, r.table_name);
    EXECUTE format('SELECT count(*) FROM %s', v_qualified) INTO v_before;

    -- Every temp column is text; the cast happens on the way in, using the
    -- target's declared type. A CSV that disagrees with the schema fails the
    -- cast loudly instead of storing something surprising.
    SELECT string_agg(format('%I TEXT', c), ', ' ORDER BY ord)
      INTO v_tempcols FROM unnest(r.csv_columns) WITH ORDINALITY AS t(c, ord);
    SELECT string_agg(format('%I', c), ', ' ORDER BY ord)
      INTO v_collist FROM unnest(r.csv_columns) WITH ORDINALITY AS t(c, ord);

    v_selectlist := '';
    FOREACH v_col IN ARRAY r.csv_columns LOOP
        -- Aliased: information_schema.columns.table_name would otherwise be
        -- ambiguous against this function's OUT parameter of the same name.
        SELECT c.data_type INTO v_type FROM information_schema.columns c
         WHERE c.table_schema = r.schema_name AND c.table_name = r.table_name
           AND c.column_name = v_col;
        IF v_type IS NULL THEN
            RETURN QUERY SELECT r.table_name, v_before, v_before,
                format('ERROR: registry names column %s, which %s does not have',
                       v_col, v_qualified)::TEXT;
            RETURN;
        END IF;
        v_selectlist := v_selectlist ||
            CASE WHEN v_selectlist = '' THEN '' ELSE ', ' END ||
            format('NULLIF(%I, '''')::%s', v_col, v_type);
    END LOOP;

    -- Refresh every non-key column from the file; the natural key is the match.
    SELECT string_agg(format('%I = EXCLUDED.%I', c, c), ', ' ORDER BY ord)
      INTO v_updates FROM unnest(r.csv_columns) WITH ORDINALITY AS t(c, ord)
     WHERE c <> r.natural_key;

    DROP TABLE IF EXISTS _lookup_stage;
    EXECUTE format('CREATE TEMP TABLE _lookup_stage (%s) ON COMMIT DROP', v_tempcols);
    EXECUTE format('COPY _lookup_stage FROM %L WITH (FORMAT csv, HEADER true)',
                   '/var/lib/postgresql/lookups/' || r.csv_file);

    IF v_updates IS NULL THEN
        EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM _lookup_stage '
                       'ON CONFLICT (%I) DO NOTHING',
                       v_qualified, v_collist, v_selectlist, r.natural_key);
    ELSE
        EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM _lookup_stage '
                       'ON CONFLICT (%I) DO UPDATE SET %s',
                       v_qualified, v_collist, v_selectlist, r.natural_key, v_updates);
    END IF;

    EXECUTE format('SELECT count(*) FROM %s', v_qualified) INTO v_after;
    RETURN QUERY SELECT r.table_name, v_before, v_after, 'OK'::TEXT;
END;
$$;


ALTER FUNCTION shared.refresh_lookup_generic(p_key text) OWNER TO supabase_admin;

--
-- Name: FUNCTION refresh_lookup_generic(p_key text); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.refresh_lookup_generic(p_key text) IS 'Registry-driven lookup loader. Called by shared.refresh_lookup for every key in shared.lookup_registry; the remaining keys (locations, scenarios) keep bespoke branches because their CSV columns are constructed or resolved rather than stored.';


--
-- Name: request_network(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.request_network() RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
    SELECT CASE
        WHEN (nullif(current_setting('request.headers', true), '')::json ->> 'x-dt-network') = 'campus'
        THEN 'campus' ELSE 'internet'
    END;
$$;


ALTER FUNCTION shared.request_network() OWNER TO supabase_admin;

--
-- Name: FUNCTION request_network(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.request_network() IS 'campus when the request came through the dashboard''s nginx from the university network (header X-DT-Network, set by nginx and never taken from the client), internet otherwise, including direct database connections.';


--
-- Name: sample_unit_id(integer); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.sample_unit_id(p_plot_id integer) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
    WITH RECURSIVE up AS (
        SELECT p.plot_id, p.parent_plot_id, p.sampling_design_id, p.area_m2, 0 AS depth
          FROM shared.plots p
         WHERE p.plot_id = p_plot_id
        UNION ALL
        SELECT q.plot_id, q.parent_plot_id, q.sampling_design_id, q.area_m2, up.depth + 1
          FROM shared.plots q
          JOIN up ON q.plot_id = up.parent_plot_id
         WHERE up.depth < 10
    ),
    design AS (
        SELECT u.sampling_design_id
          FROM up u
         WHERE u.sampling_design_id IS NOT NULL
         ORDER BY u.depth
         LIMIT 1
    )
    SELECT CASE
        WHEN EXISTS (SELECT 1 FROM shared.inclusion_rules r
                      WHERE r.sampling_design_id = (SELECT sampling_design_id FROM design))
            THEN (SELECT u.plot_id FROM up u WHERE u.depth = 0)
        ELSE (SELECT u.plot_id FROM up u WHERE u.area_m2 > 0 ORDER BY u.depth LIMIT 1)
    END;
$$;


ALTER FUNCTION shared.sample_unit_id(p_plot_id integer) OWNER TO supabase_admin;

--
-- Name: FUNCTION sample_unit_id(p_plot_id integer); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.sample_unit_id(p_plot_id integer) IS 'Sample unit a plot''s trees belong to: the plot itself when its design has inclusion rules, otherwise the nearest plot up the parent chain with an area (on a fully mapped site, the census plot). NULL when there is none.';


--
-- Name: scenario_axes_from_name(text); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.scenario_axes_from_name(p_name text) RETURNS TABLE(management_regime_id smallint, climate_pathway_id smallint)
    LANGUAGE sql STABLE
    AS $$
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
$$;


ALTER FUNCTION shared.scenario_axes_from_name(p_name text) OWNER TO supabase_admin;

--
-- Name: FUNCTION scenario_axes_from_name(p_name text); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.scenario_axes_from_name(p_name text) IS 'The scenario naming grammar: <pathway> | <regime> | <regime>_<pathway>. Returns the two axis ids, or no row when the name fits none of the forms.';


--
-- Name: scenarios_derive_axes(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.scenarios_derive_axes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION shared.scenarios_derive_axes() OWNER TO supabase_admin;

--
-- Name: set_created_by(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
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


ALTER FUNCTION shared.set_created_by() OWNER TO supabase_admin;

--
-- Name: set_updated_by(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.set_updated_by() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    NEW.updated_by := auth.uid()::TEXT;
    RETURN NEW;
END;
$$;


ALTER FUNCTION shared.set_updated_by() OWNER TO supabase_admin;

--
-- Name: t_quantile(numeric, integer); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.t_quantile(p_confidence numeric, p_df integer) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
    SELECT CASE p_confidence WHEN 0.90 THEN t.q90 WHEN 0.95 THEN t.q95 WHEN 0.99 THEN t.q99 END
      FROM (VALUES
        (1, 6.314, 12.706, 63.657), (2, 2.920, 4.303, 9.925), (3, 2.353, 3.182, 5.841),
        (4, 2.132, 2.776, 4.604),   (5, 2.015, 2.571, 4.032), (6, 1.943, 2.447, 3.707),
        (7, 1.895, 2.365, 3.499),   (8, 1.860, 2.306, 3.355), (9, 1.833, 2.262, 3.250),
        (10, 1.812, 2.228, 3.169),  (11, 1.796, 2.201, 3.106), (12, 1.782, 2.179, 3.055),
        (13, 1.771, 2.160, 3.012),  (14, 1.761, 2.145, 2.977), (15, 1.753, 2.131, 2.947),
        (16, 1.746, 2.120, 2.921),  (17, 1.740, 2.110, 2.898), (18, 1.734, 2.101, 2.878),
        (19, 1.729, 2.093, 2.861),  (20, 1.725, 2.086, 2.845), (21, 1.721, 2.080, 2.831),
        (22, 1.717, 2.074, 2.819),  (23, 1.714, 2.069, 2.807), (24, 1.711, 2.064, 2.797),
        (25, 1.708, 2.060, 2.787),  (26, 1.706, 2.056, 2.779), (27, 1.703, 2.052, 2.771),
        (28, 1.701, 2.048, 2.763),  (29, 1.699, 2.045, 2.756), (30, 1.697, 2.042, 2.750),
        (40, 1.684, 2.021, 2.704),  (60, 1.671, 2.000, 2.660), (120, 1.658, 1.980, 2.617),
        (2147483647, 1.645, 1.960, 2.576)
      ) AS t(df, q90, q95, q99)
     WHERE p_df >= 1 AND t.df <= p_df
     ORDER BY t.df DESC
     LIMIT 1;
$$;


ALTER FUNCTION shared.t_quantile(p_confidence numeric, p_df integer) OWNER TO supabase_admin;

--
-- Name: FUNCTION t_quantile(p_confidence numeric, p_df integer); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.t_quantile(p_confidence numeric, p_df integer) IS 'Two-sided Student t quantile for confidence 0.90, 0.95 or 0.99 and df >= 1, from a table (df 1-30, 40, 60, 120, infinity; between rows the next lower df, i.e. slightly wider). NULL otherwise.';


--
-- Name: unwritable_point_cloud_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.unwritable_point_cloud_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT pc.point_cloud_id FROM point_clouds.point_clouds pc
     WHERE NOT shared.is_curator()
       AND EXISTS (SELECT 1 FROM shared.campaigns c WHERE c.owner_team_id IS NOT NULL)
       AND pc.campaign_id IS NOT NULL
       AND pc.campaign_id NOT IN (SELECT shared.writable_campaign_ids());
$$;


ALTER FUNCTION shared.unwritable_point_cloud_ids() OWNER TO supabase_admin;

--
-- Name: unwritable_qsm_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.unwritable_qsm_ids() RETURNS SETOF bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT q.qsm_id FROM trees.qsms q
     WHERE q.tree_id IN (SELECT shared.unwritable_tree_ids())
        OR q.point_cloud_id IN (SELECT shared.unwritable_point_cloud_ids());
$$;


ALTER FUNCTION shared.unwritable_qsm_ids() OWNER TO supabase_admin;

--
-- Name: unwritable_sensor_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.unwritable_sensor_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT s.sensor_id FROM sensor.sensors s
     WHERE NOT shared.is_curator()
       AND EXISTS (SELECT 1 FROM shared.campaigns c WHERE c.owner_team_id IS NOT NULL)
       AND s.campaign_id IS NOT NULL
       AND s.campaign_id NOT IN (SELECT shared.writable_campaign_ids());
$$;


ALTER FUNCTION shared.unwritable_sensor_ids() OWNER TO supabase_admin;

--
-- Name: unwritable_tree_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.unwritable_tree_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT t.tree_id FROM trees.trees t
     WHERE NOT shared.is_curator()
       AND EXISTS (SELECT 1 FROM shared.campaigns c WHERE c.owner_team_id IS NOT NULL)
       AND t.campaign_id IS NOT NULL
       AND t.campaign_id NOT IN (SELECT shared.writable_campaign_ids());
$$;


ALTER FUNCTION shared.unwritable_tree_ids() OWNER TO supabase_admin;

--
-- Name: validate_against_param_schema(jsonb, jsonb); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb) RETURNS void
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
DECLARE
    key       text;
    dep       text;
    spec      jsonb;
    val       jsonb;
    want_type text;
    num       numeric;
BEGIN
    IF params IS NULL OR jsonb_typeof(params) <> 'object' THEN
        RAISE EXCEPTION 'params must be a JSON object, got %',
            coalesce(jsonb_typeof(params), 'null')
            USING ERRCODE = '22023';
    END IF;

    -- A readOnly property is recorded BY the run, not offered to the caller.
    -- Checked ahead of the unknown-parameter branch below, because the key is
    -- in `properties` and would otherwise be accepted silently: declaring
    -- silva's three resolved parameters (20260923170000) so the RO-Crate could
    -- record them had the side effect of making request_job() take them as
    -- input and ignore them.
    FOR key IN SELECT jsonb_object_keys(params) LOOP
        IF coalesce((schema->'properties'->key->>'readOnly')::boolean, false) THEN
            RAISE EXCEPTION
                'parameter "%" is readOnly: it is recorded by the run, not set by the caller',
                key USING ERRCODE = '22023';
        END IF;
    END LOOP;

    IF NOT coalesce((schema->>'additionalProperties')::boolean, false) THEN
        FOR key IN SELECT jsonb_object_keys(params) LOOP
            IF NOT (coalesce(schema->'properties', '{}'::jsonb) ? key) THEN
                RAISE EXCEPTION 'unknown parameter "%"; accepted: %', key,
                    coalesce((SELECT string_agg(k, ', ' ORDER BY k)
                                FROM jsonb_object_keys(coalesce(schema->'properties',
                                                                '{}'::jsonb)) k
                               WHERE NOT coalesce(
                                   (schema->'properties'->k->>'readOnly')::boolean, false)),
                             '(none)')
                    USING ERRCODE = '22023';
            END IF;
        END LOOP;
    END IF;

    FOR key IN SELECT jsonb_array_elements_text(coalesce(schema->'required', '[]'::jsonb)) LOOP
        IF NOT (params ? key) THEN
            RAISE EXCEPTION 'missing required parameter "%"', key USING ERRCODE = '22023';
        END IF;
    END LOOP;

    FOR key IN SELECT jsonb_object_keys(coalesce(schema->'dependentRequired', '{}'::jsonb)) LOOP
        IF params ? key THEN
            FOR dep IN SELECT jsonb_array_elements_text(schema->'dependentRequired'->key) LOOP
                IF NOT (params ? dep) THEN
                    RAISE EXCEPTION 'parameter "%" must be given together with "%"', key, dep
                        USING ERRCODE = '22023';
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    FOR key, val IN SELECT * FROM jsonb_each(params) LOOP
        spec := coalesce(schema->'properties', '{}'::jsonb) -> key;
        CONTINUE WHEN spec IS NULL;

        want_type := spec->>'type';
        IF want_type = 'integer' THEN
            IF jsonb_typeof(val) <> 'number' OR (val#>>'{}') !~ '^-?[0-9]+$' THEN
                RAISE EXCEPTION 'parameter "%" must be an integer, got %', key, val
                    USING ERRCODE = '22023';
            END IF;
        ELSIF want_type IN ('number', 'boolean', 'string') THEN
            IF jsonb_typeof(val) <> want_type THEN
                RAISE EXCEPTION 'parameter "%" must be %, got %', key, want_type, jsonb_typeof(val)
                    USING ERRCODE = '22023';
            END IF;
        END IF;

        IF spec ? 'enum' AND NOT (spec->'enum' @> jsonb_build_array(val)) THEN
            RAISE EXCEPTION 'parameter "%" must be one of %, got %',
                key, spec->>'enum', val USING ERRCODE = '22023';
        END IF;

        IF jsonb_typeof(val) = 'number' THEN
            num := (val#>>'{}')::numeric;
            IF spec ? 'minimum' AND num < (spec->>'minimum')::numeric THEN
                RAISE EXCEPTION 'parameter "%" must be at least %, got %',
                    key, spec->>'minimum', num USING ERRCODE = '22023';
            END IF;
            IF spec ? 'maximum' AND num > (spec->>'maximum')::numeric THEN
                RAISE EXCEPTION 'parameter "%" must be at most %, got %',
                    key, spec->>'maximum', num USING ERRCODE = '22023';
            END IF;
            IF spec ? 'multipleOf' AND num % (spec->>'multipleOf')::numeric <> 0 THEN
                RAISE EXCEPTION 'parameter "%" must be a multiple of %, got %',
                    key, spec->>'multipleOf', num USING ERRCODE = '22023';
            END IF;
        END IF;

        IF spec ? 'pattern' AND jsonb_typeof(val) = 'string'
           AND (val#>>'{}') !~ (spec->>'pattern') THEN
            RAISE EXCEPTION 'parameter "%" does not match %', key, spec->>'pattern'
                USING ERRCODE = '22023';
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb) OWNER TO supabase_admin;

--
-- Name: FUNCTION validate_against_param_schema(schema jsonb, params jsonb); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb) IS 'Check a params object against a shared.Processes.param_schema. Implements the JSON Schema draft-07 subset that column documents -- additionalProperties, required, dependentRequired, type, enum, minimum, maximum, multipleOf, pattern -- and nothing wider. Returns silently or raises 22023 with a message meant for the person who sent the request.';


--
-- Name: writable_campaign_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.writable_campaign_ids() RETURNS SETOF integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT c.campaign_id
      FROM shared.campaigns c
     WHERE shared.is_curator()
        OR c.owner_team_id IS NULL
        OR c.owner_team_id IN (SELECT shared.my_team_ids());
$$;


ALTER FUNCTION shared.writable_campaign_ids() OWNER TO supabase_admin;

--
-- Name: FUNCTION writable_campaign_ids(); Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON FUNCTION shared.writable_campaign_ids() IS 'Campaigns the caller may add rows to or change rows of (row-level policies still decide the role): those without an owner team, their own teams'', all for curators and admins.';


--
-- Name: writable_observation_ids(); Type: FUNCTION; Schema: shared; Owner: supabase_admin
--

CREATE FUNCTION shared.writable_observation_ids() RETURNS SETOF bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT o.observation_id FROM trees.observations o
     WHERE o.campaign_id IN (SELECT shared.writable_campaign_ids());
$$;


ALTER FUNCTION shared.writable_observation_ids() OWNER TO supabase_admin;

--
-- Name: assign_height_class(); Type: FUNCTION; Schema: trees; Owner: supabase_admin
--

CREATE FUNCTION trees.assign_height_class() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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
$$;


ALTER FUNCTION trees.assign_height_class() OWNER TO supabase_admin;

--
-- Name: FUNCTION assign_height_class(); Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON FUNCTION trees.assign_height_class() IS 'Auto-assigns phanerophyte height class based on tree height';


--
-- Name: calculate_basal_area(numeric); Type: FUNCTION; Schema: trees; Owner: supabase_admin
--

CREATE FUNCTION trees.calculate_basal_area(dbh_cm numeric) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    -- Basal area = π * (DBH/2)^2, convert cm to m
    RETURN PI() * POWER(dbh_cm / 200.0, 2);
END;
$$;


ALTER FUNCTION trees.calculate_basal_area(dbh_cm numeric) OWNER TO supabase_admin;

--
-- Name: FUNCTION calculate_basal_area(dbh_cm numeric); Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) IS 'Calculates basal area in m² from DBH in cm';


--
-- Name: calculate_crown_volume(numeric, numeric); Type: FUNCTION; Schema: trees; Owner: supabase_admin
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


ALTER FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) OWNER TO supabase_admin;

--
-- Name: FUNCTION calculate_crown_volume(crown_width_m numeric, crown_height_m numeric); Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) IS 'Calculates crown volume in m³ assuming ellipsoid shape';


--
-- Name: fill_from_variant(); Type: FUNCTION; Schema: trees; Owner: supabase_admin
--

CREATE FUNCTION trees.fill_from_variant() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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


ALTER FUNCTION trees.fill_from_variant() OWNER TO supabase_admin;

--
-- Name: FUNCTION fill_from_variant(); Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON FUNCTION trees.fill_from_variant() IS 'Fills a new tree row''s location_id, scenario_id and variant_type_id from its variant when the writer leaves them out. A value the writer gives must still match the variant (trees_variant_fkey).';


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: trees; Owner: supabase_admin
--

CREATE FUNCTION trees.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION trees.update_updated_at_column() OWNER TO supabase_admin;

--
-- Name: environments; Type: TABLE; Schema: environments; Owner: supabase_admin
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


ALTER TABLE environments.environments OWNER TO supabase_admin;

--
-- Name: TABLE environments; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON TABLE environments.environments IS 'Environmental condition variants derived from sensors, models, or user input';


--
-- Name: COLUMN environments.environment_id; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON COLUMN environments.environments.environment_id IS 'Unique identifier for this environment record';


--
-- Name: COLUMN environments.parent_environment_id; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON COLUMN environments.environments.parent_environment_id IS 'Parent environment for tracking environmental modifications';


--
-- Name: COLUMN environments.start_date; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON COLUMN environments.environments.start_date IS 'Start of environmental measurement period';


--
-- Name: COLUMN environments.end_date; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON COLUMN environments.environments.end_date IS 'End of environmental measurement period (NULL for ongoing)';


--
-- Name: COLUMN environments.avg_global_radiation_w_m2; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON COLUMN environments.environments.avg_global_radiation_w_m2 IS 'Average global radiation in W/m²';


--
-- Name: COLUMN environments.stress_factor; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON COLUMN environments.environments.stress_factor IS 'Environmental stress index (0=optimal, 1=severe stress)';


--
-- Name: locations; Type: TABLE; Schema: shared; Owner: supabase_admin
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
    forest_growth_region character varying(16),
    soil_moistness smallint,
    soil_nutrient_supply smallint,
    crs_epsg integer,
    CONSTRAINT locations_aspect_check CHECK (((aspect)::text = ANY (ARRAY[('N'::character varying)::text, ('NE'::character varying)::text, ('E'::character varying)::text, ('SE'::character varying)::text, ('S'::character varying)::text, ('SW'::character varying)::text, ('W'::character varying)::text, ('NW'::character varying)::text]))),
    CONSTRAINT locations_crs_epsg_check CHECK (((crs_epsg IS NULL) OR ((crs_epsg >= 1024) AND (crs_epsg <= 32767)))),
    CONSTRAINT locations_slope_deg_check CHECK (((slope_deg >= (0)::numeric) AND (slope_deg <= (90)::numeric))),
    CONSTRAINT locations_soil_moistness_check CHECK (((soil_moistness IS NULL) OR ((soil_moistness >= 1) AND (soil_moistness <= 9)))),
    CONSTRAINT locations_soil_nutrient_supply_check CHECK (((soil_nutrient_supply IS NULL) OR ((soil_nutrient_supply >= 1) AND (soil_nutrient_supply <= 5))))
);


ALTER TABLE shared.locations OWNER TO supabase_admin;

--
-- Name: TABLE locations; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.locations IS 'Forest plot locations with spatial boundaries and environmental context';


--
-- Name: COLUMN locations.boundary; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.locations.boundary IS 'PostGIS polygon defining plot boundaries in WGS84';


--
-- Name: COLUMN locations.center_point; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.locations.center_point IS 'PostGIS point for plot center in WGS84';


--
-- Name: COLUMN locations.forest_growth_region; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.locations.forest_growth_region IS 'German forest growth region code (Wuchsgebiet.Wuchsbezirk), e.g. ''99.73.11''. Keys SILVA/silvaR''s internal climate table, which supplies temperature, precipitation and vegetation-period length for the site. Derived once by point-in-polygon against the Thuenen Wuchsbezirke 2020 layer; see silva-connector/docs/site-conditions.md for provenance.';


--
-- Name: COLUMN locations.soil_moistness; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.locations.soil_moistness IS 'SILVA soil moisture class, 1-9 (1 = very dry, 5 = fresh, 9 = very wet). Not derivable from soil_type_id: shared.soil_types holds USDA soil orders (Alfisol, Spodosol, ...), which describe pedogenesis rather than water supply. Requires a site survey value.';


--
-- Name: COLUMN locations.soil_nutrient_supply; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.locations.soil_nutrient_supply IS 'SILVA soil nutrient supply class, 1-5 (1 = very low, 5 = very high). Like soil_moistness, independent of the USDA order in soil_type_id and requires a site survey value.';


--
-- Name: COLUMN locations.crs_epsg; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.locations.crs_epsg IS 'Declared internal projected CRS of the site as an EPSG code (e.g. 32632 = WGS 84 / UTM zone 32N). The one frame in which per-site planimetric work (engine placement, terrain, distances) is done; every input in another frame is transformed on ingestion and its source frame retained on the record (trees.trees.source_crs / position_original). Geometry columns stay EPSG:4326. Seeded from data/lookups/locations.csv.';


--
-- Name: scenarios; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.scenarios (
    scenario_id integer NOT NULL,
    scenario_name character varying(200) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    location_id integer NOT NULL,
    management_regime_id smallint NOT NULL,
    climate_pathway_id smallint NOT NULL,
    scenario_code integer GENERATED ALWAYS AS (((management_regime_id * 10) + climate_pathway_id)) STORED
);


ALTER TABLE shared.scenarios OWNER TO supabase_admin;

--
-- Name: TABLE scenarios; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.scenarios IS 'One scenario per (location, management regime, climate pathway). scenario_code = regime*10 + pathway is the numeric key, scenario_name the text one; the name follows <pathway> | <regime> | <regime>_<pathway> and the axes are derived from it on insert when not given. Regime 0 scenarios hold acquired data only; the rest own a baseline and a variant timeline (Location -> Scenario -> Variant).';


--
-- Name: COLUMN scenarios.location_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.scenarios.location_id IS 'The site this management regime belongs to — top of the Location -> Scenario -> Variant hierarchy.';


--
-- Name: COLUMN scenarios.management_regime_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.scenarios.management_regime_id IS 'Management axis -> shared.management_regimes. Filled from scenario_name by trigger when omitted (grammar: <pathway> | <regime> | <regime>_<pathway>).';


--
-- Name: COLUMN scenarios.climate_pathway_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.scenarios.climate_pathway_id IS 'Climate axis -> shared.climate_pathways. 0 = historical. Filled from scenario_name by trigger when omitted.';


--
-- Name: COLUMN scenarios.scenario_code; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.scenarios.scenario_code IS 'management_regime_id * 10 + climate_pathway_id, generated. The sort key Unreal uses: tens digit = regime, units digit = pathway. natural_growth = 10, crop_tree_thinning_ssp585 = 23, a bare ssp370 climate bucket = 2.';


--
-- Name: variant_types; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.variant_types (
    variant_type_id integer NOT NULL,
    variant_type_name character varying(100) NOT NULL,
    description text,
    CONSTRAINT chk_variant_type_name CHECK (((variant_type_name)::text = ANY (ARRAY[('original'::character varying)::text, ('processed'::character varying)::text, ('manual'::character varying)::text, ('simulated_growth'::character varying)::text, ('user_input'::character varying)::text, ('sensor_derived'::character varying)::text, ('model_output'::character varying)::text, ('repeat_measurement'::character varying)::text])))
);


ALTER TABLE shared.variant_types OWNER TO supabase_admin;

--
-- Name: TABLE variant_types; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.variant_types IS 'Types of data variants (original, processed, simulated, etc.)';


--
-- Name: active_environments; Type: VIEW; Schema: environments; Owner: supabase_admin
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
     LEFT JOIN shared.variant_types vt ON ((e.variant_type_id = vt.variant_type_id)))
  WHERE (environments.is_active(e.start_date, e.end_date) = true);


ALTER TABLE environments.active_environments OWNER TO supabase_admin;

--
-- Name: VIEW active_environments; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON VIEW environments.active_environments IS 'Currently active environment variants with location and scenario context';


--
-- Name: environments_environment_id_seq; Type: SEQUENCE; Schema: environments; Owner: supabase_admin
--

CREATE SEQUENCE environments.environments_environment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE environments.environments_environment_id_seq OWNER TO supabase_admin;

--
-- Name: environments_environment_id_seq; Type: SEQUENCE OWNED BY; Schema: environments; Owner: supabase_admin
--

ALTER SEQUENCE environments.environments_environment_id_seq OWNED BY environments.environments.environment_id;


--
-- Name: location_environment_summary; Type: VIEW; Schema: environments; Owner: supabase_admin
--

CREATE VIEW environments.location_environment_summary AS
 SELECT l.location_id,
    l.location_name,
    count(e.environment_id) AS environment_count,
    avg(e.avg_temperature_c) AS avg_temperature_c,
    avg(e.avg_humidity_percent) AS avg_humidity_percent,
    avg(e.avg_co2_ppm) AS avg_co2_ppm,
    avg(e.stress_factor) AS avg_stress_factor,
    min(e.start_date) AS earliest_measurement,
    max(e.end_date) AS latest_measurement
   FROM (shared.locations l
     LEFT JOIN environments.environments e ON ((l.location_id = e.location_id)))
  GROUP BY l.location_id, l.location_name;


ALTER TABLE environments.location_environment_summary OWNER TO supabase_admin;

--
-- Name: VIEW location_environment_summary; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON VIEW environments.location_environment_summary IS 'Summary statistics of environmental conditions by location';


--
-- Name: deadwood; Type: TABLE; Schema: forest_floor; Owner: supabase_admin
--

CREATE TABLE forest_floor.deadwood (
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
    campaign_id integer,
    geom extensions.geometry(Geometry,4326),
    diameter_top_cm numeric(6,2),
    void_diameter_cm numeric(6,2),
    source_deadwood_id text,
    source_attributes jsonb,
    CONSTRAINT deadwood_decay_class_check CHECK (((decay_class >= 1) AND (decay_class <= 5))),
    CONSTRAINT deadwood_diameter_cm_check CHECK ((diameter_cm > (0)::numeric)),
    CONSTRAINT deadwood_diameter_top_cm_check CHECK ((diameter_top_cm > (0)::numeric)),
    CONSTRAINT deadwood_length_m_check CHECK ((length_m > (0)::numeric)),
    CONSTRAINT deadwood_source_attributes_object_check CHECK (((source_attributes IS NULL) OR (jsonb_typeof(source_attributes) = 'object'::text))),
    CONSTRAINT deadwood_source_id_needs_campaign_check CHECK (((source_deadwood_id IS NULL) OR (campaign_id IS NOT NULL))),
    CONSTRAINT deadwood_void_diameter_cm_check CHECK ((void_diameter_cm >= (0)::numeric)),
    CONSTRAINT deadwood_volume_m3_check CHECK ((volume_m3 >= (0)::numeric)),
    CONSTRAINT deadwood_wood_type_check CHECK (((wood_type)::text = ANY (ARRAY[('standing'::character varying)::text, ('fallen'::character varying)::text, ('stump'::character varying)::text, ('branch'::character varying)::text])))
);


ALTER TABLE forest_floor.deadwood OWNER TO supabase_admin;

--
-- Name: TABLE deadwood; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON TABLE forest_floor.deadwood IS 'Dead wood inventory including standing dead, fallen logs, stumps, and branches';


--
-- Name: COLUMN deadwood.tree_id; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.tree_id IS 'Optional link to known dead tree record';


--
-- Name: COLUMN deadwood.wood_type; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.wood_type IS 'Type of dead wood: standing, fallen, stump, or branch';


--
-- Name: COLUMN deadwood.diameter_cm; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.diameter_cm IS 'Diameter in centimetres: at the base (thick end) for lying pieces and stumps, at breast height for standing dead trees.';


--
-- Name: COLUMN deadwood.decay_class; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.decay_class IS 'Decay stage from 1 (fresh) to 5 (fully decomposed)';


--
-- Name: COLUMN deadwood.campaign_id; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.campaign_id IS 'Data collection campaign (dataset) this record belongs to; decides who may read it (access levels).';


--
-- Name: COLUMN deadwood.geom; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.geom IS 'The piece as measured, any geometry in WGS84: a line for a lying piece, a point for a stump. position stays the representative point.';


--
-- Name: COLUMN deadwood.diameter_top_cm; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.diameter_top_cm IS 'Diameter at the thin end of a lying piece, in centimetres.';


--
-- Name: COLUMN deadwood.void_diameter_cm; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.void_diameter_cm IS 'Diameter of the hollow core, in centimetres (NSW coarseWoodyDebrisVoidSpace). 0 = solid.';


--
-- Name: COLUMN deadwood.source_deadwood_id; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.source_deadwood_id IS 'The producer''s own identifier of this piece. Unique per campaign; requires campaign_id.';


--
-- Name: COLUMN deadwood.source_attributes; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.deadwood.source_attributes IS 'Protocol codes without a column of their own, as a JSON object keyed by the source''s column names (e.g. the raw typology).';


--
-- Name: deadwood_deadwood_id_seq; Type: SEQUENCE; Schema: forest_floor; Owner: supabase_admin
--

CREATE SEQUENCE forest_floor.deadwood_deadwood_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE forest_floor.deadwood_deadwood_id_seq OWNER TO supabase_admin;

--
-- Name: deadwood_deadwood_id_seq; Type: SEQUENCE OWNED BY; Schema: forest_floor; Owner: supabase_admin
--

ALTER SEQUENCE forest_floor.deadwood_deadwood_id_seq OWNED BY forest_floor.deadwood.deadwood_id;


--
-- Name: ground_vegetation; Type: TABLE; Schema: forest_floor; Owner: supabase_admin
--

CREATE TABLE forest_floor.ground_vegetation (
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
    campaign_id integer,
    CONSTRAINT ground_vegetation_cover_percent_check CHECK (((cover_percent >= (0)::numeric) AND (cover_percent <= (100)::numeric))),
    CONSTRAINT ground_vegetation_height_cm_check CHECK ((height_cm >= (0)::numeric)),
    CONSTRAINT ground_vegetation_layer_check CHECK (((layer)::text = ANY (ARRAY[('herb'::character varying)::text, ('shrub'::character varying)::text, ('moss'::character varying)::text, ('litter'::character varying)::text, ('fern'::character varying)::text, ('grass'::character varying)::text])))
);


ALTER TABLE forest_floor.ground_vegetation OWNER TO supabase_admin;

--
-- Name: TABLE ground_vegetation; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON TABLE forest_floor.ground_vegetation IS 'Ground vegetation survey records by plot and layer';


--
-- Name: COLUMN ground_vegetation.cover_percent; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.ground_vegetation.cover_percent IS 'Estimated cover percentage (0-100)';


--
-- Name: COLUMN ground_vegetation.layer; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.ground_vegetation.layer IS 'Vegetation layer: herb, shrub, moss, litter, fern, grass';


--
-- Name: COLUMN ground_vegetation.campaign_id; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.ground_vegetation.campaign_id IS 'Data collection campaign (dataset) this record belongs to; decides who may read it (access levels).';


--
-- Name: ground_vegetation_ground_vegetation_id_seq; Type: SEQUENCE; Schema: forest_floor; Owner: supabase_admin
--

CREATE SEQUENCE forest_floor.ground_vegetation_ground_vegetation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE forest_floor.ground_vegetation_ground_vegetation_id_seq OWNER TO supabase_admin;

--
-- Name: ground_vegetation_ground_vegetation_id_seq; Type: SEQUENCE OWNED BY; Schema: forest_floor; Owner: supabase_admin
--

ALTER SEQUENCE forest_floor.ground_vegetation_ground_vegetation_id_seq OWNED BY forest_floor.ground_vegetation.ground_vegetation_id;


--
-- Name: regeneration; Type: TABLE; Schema: forest_floor; Owner: supabase_admin
--

CREATE TABLE forest_floor.regeneration (
    regeneration_id integer NOT NULL,
    location_id integer NOT NULL,
    plot_id integer,
    campaign_id integer,
    species_id integer,
    size_class character varying(20) NOT NULL,
    live_count integer DEFAULT 0 NOT NULL,
    dead_count integer DEFAULT 0 NOT NULL,
    mean_height_m numeric(5,2),
    "position" extensions.geometry(Point,4326),
    measurement_date date,
    source_regeneration_id text,
    source_attributes jsonb,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    updated_by character varying(200),
    survey_area_m2 numeric(10,2),
    CONSTRAINT regeneration_dead_count_check CHECK ((dead_count >= 0)),
    CONSTRAINT regeneration_live_count_check CHECK ((live_count >= 0)),
    CONSTRAINT regeneration_mean_height_m_check CHECK ((mean_height_m >= (0)::numeric)),
    CONSTRAINT regeneration_size_class_check CHECK (((size_class)::text = ANY ((ARRAY['seedling'::character varying, 'sapling'::character varying])::text[]))),
    CONSTRAINT regeneration_source_attributes_object_check CHECK (((source_attributes IS NULL) OR (jsonb_typeof(source_attributes) = 'object'::text))),
    CONSTRAINT regeneration_source_id_needs_campaign_check CHECK (((source_regeneration_id IS NULL) OR (campaign_id IS NOT NULL))),
    CONSTRAINT regeneration_survey_area_m2_check CHECK ((survey_area_m2 > (0)::numeric))
);


ALTER TABLE forest_floor.regeneration OWNER TO supabase_admin;

--
-- Name: TABLE regeneration; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON TABLE forest_floor.regeneration IS 'Regeneration tallies: live and dead counts per species and size class on a survey area within a plot (survey_area_m2, else the plot''s area). See public.regeneration_per_ha. Size classes follow the protocol of the plot''s sampling design.';


--
-- Name: COLUMN regeneration.plot_id; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.plot_id IS 'The plot the tally was made in. The survey area is survey_area_m2, else the plot''s area_m2 (or the nearest enclosing plot''s).';


--
-- Name: COLUMN regeneration.size_class; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.size_class IS 'seedling | sapling, as the protocol defines them (e.g. Pathfinder: seedlings on 12 x 12 m, saplings on 0.01 ha).';


--
-- Name: COLUMN regeneration.live_count; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.live_count IS 'Live individuals counted.';


--
-- Name: COLUMN regeneration.dead_count; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.dead_count IS 'Dead individuals counted.';


--
-- Name: COLUMN regeneration.mean_height_m; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.mean_height_m IS 'Mean height of the counted individuals, when recorded.';


--
-- Name: COLUMN regeneration."position"; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration."position" IS 'Where the tally was made, when recorded (subplot centre or measured point).';


--
-- Name: COLUMN regeneration.source_regeneration_id; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.source_regeneration_id IS 'The producer''s own identifier of this tally. Unique per campaign; requires campaign_id.';


--
-- Name: COLUMN regeneration.source_attributes; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.source_attributes IS 'Protocol codes without a column of their own, as a JSON object keyed by the source''s column names (e.g. the raw species name).';


--
-- Name: COLUMN regeneration.survey_area_m2; Type: COMMENT; Schema: forest_floor; Owner: supabase_admin
--

COMMENT ON COLUMN forest_floor.regeneration.survey_area_m2 IS 'Area the tally was counted on, in m2 (e.g. Pathfinder saplings: 100 m2 within the 0.25 ha plot). NULL = the whole plot''s resolved area. Not a plot of its own: a plot with its own area would count as a tree sample unit.';


--
-- Name: regeneration_regeneration_id_seq; Type: SEQUENCE; Schema: forest_floor; Owner: supabase_admin
--

CREATE SEQUENCE forest_floor.regeneration_regeneration_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE forest_floor.regeneration_regeneration_id_seq OWNER TO supabase_admin;

--
-- Name: regeneration_regeneration_id_seq; Type: SEQUENCE OWNED BY; Schema: forest_floor; Owner: supabase_admin
--

ALTER SEQUENCE forest_floor.regeneration_regeneration_id_seq OWNED BY forest_floor.regeneration.regeneration_id;


--
-- Name: images; Type: TABLE; Schema: imagery; Owner: supabase_admin
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
    CONSTRAINT images_file_format_check CHECK (((file_format)::text = ANY (ARRAY[('jpg'::character varying)::text, ('png'::character varying)::text, ('tiff'::character varying)::text, ('raw'::character varying)::text, ('geotiff'::character varying)::text]))),
    CONSTRAINT images_ground_sample_distance_cm_check CHECK ((ground_sample_distance_cm > (0)::numeric)),
    CONSTRAINT images_heading_deg_check CHECK (((heading_deg >= (0)::numeric) AND (heading_deg < (360)::numeric))),
    CONSTRAINT images_pitch_deg_check CHECK (((pitch_deg >= ('-90'::integer)::numeric) AND (pitch_deg <= (90)::numeric))),
    CONSTRAINT images_roll_deg_check CHECK (((roll_deg >= ('-180'::integer)::numeric) AND (roll_deg <= (180)::numeric)))
);


ALTER TABLE imagery.images OWNER TO supabase_admin;

--
-- Name: TABLE images; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON TABLE imagery.images IS 'Aerial and ground-based imagery with spatial metadata and camera parameters';


--
-- Name: COLUMN images.file_path; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.file_path IS 'Path or URI to image file';


--
-- Name: COLUMN images.file_format; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.file_format IS 'Image file format (jpg, png, tiff, raw, geotiff)';


--
-- Name: COLUMN images.resolution_px; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.resolution_px IS 'Image resolution in pixels (e.g., 4000x3000)';


--
-- Name: COLUMN images."position"; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images."position" IS 'Camera position in WGS84 (EPSG:4326)';


--
-- Name: COLUMN images.altitude_m; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.altitude_m IS 'Camera altitude above ground in meters';


--
-- Name: COLUMN images.heading_deg; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.heading_deg IS 'Camera heading in degrees (0=North, clockwise)';


--
-- Name: COLUMN images.pitch_deg; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.pitch_deg IS 'Camera pitch angle (-90 to 90 degrees)';


--
-- Name: COLUMN images.roll_deg; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.roll_deg IS 'Camera roll angle (-180 to 180 degrees)';


--
-- Name: COLUMN images.ground_sample_distance_cm; Type: COMMENT; Schema: imagery; Owner: supabase_admin
--

COMMENT ON COLUMN imagery.images.ground_sample_distance_cm IS 'Ground sample distance in centimeters per pixel';


--
-- Name: images_image_id_seq; Type: SEQUENCE; Schema: imagery; Owner: supabase_admin
--

CREATE SEQUENCE imagery.images_image_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE imagery.images_image_id_seq OWNER TO supabase_admin;

--
-- Name: images_image_id_seq; Type: SEQUENCE OWNED BY; Schema: imagery; Owner: supabase_admin
--

ALTER SEQUENCE imagery.images_image_id_seq OWNED BY imagery.images.image_id;


--
-- Name: point_clouds; Type: TABLE; Schema: point_clouds; Owner: supabase_admin
--

CREATE TABLE point_clouds.point_clouds (
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
    CONSTRAINT point_clouds_file_size_mb_check CHECK ((file_size_mb >= (0)::numeric)),
    CONSTRAINT point_clouds_flight_altitude_m_check CHECK ((flight_altitude_m > (0)::numeric)),
    CONSTRAINT point_clouds_flight_speed_ms_check CHECK ((flight_speed_ms >= (0)::numeric)),
    CONSTRAINT point_clouds_overlap_percent_check CHECK (((overlap_percent >= (0)::numeric) AND (overlap_percent <= (100)::numeric))),
    CONSTRAINT point_clouds_platform_type_check CHECK (((platform_type)::text = ANY (ARRAY[('terrestrial'::character varying)::text, ('aerial'::character varying)::text, ('mobile'::character varying)::text, ('UAV'::character varying)::text]))),
    CONSTRAINT point_clouds_point_count_check CHECK ((point_count >= 0)),
    CONSTRAINT point_clouds_point_density_per_m2_check CHECK ((point_density_per_m2 >= (0)::numeric)),
    CONSTRAINT point_clouds_processing_progress_check CHECK (((processing_progress >= (0)::numeric) AND (processing_progress <= (100)::numeric))),
    CONSTRAINT point_clouds_processing_status_check CHECK (((processing_status)::text = ANY (ARRAY[('pending'::character varying)::text, ('processing'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text, ('cancelled'::character varying)::text]))),
    CONSTRAINT point_clouds_scan_angle_deg_check CHECK (((scan_angle_deg >= (0)::numeric) AND (scan_angle_deg <= (360)::numeric)))
);


ALTER TABLE point_clouds.point_clouds OWNER TO supabase_admin;

--
-- Name: TABLE point_clouds; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON TABLE point_clouds.point_clouds IS 'LiDAR point cloud variants - original scans and processed results';


--
-- Name: COLUMN point_clouds.point_cloud_id; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.point_cloud_id IS 'Unique identifier for this point cloud record';


--
-- Name: COLUMN point_clouds.parent_point_cloud_id; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.parent_point_cloud_id IS 'Parent point cloud for processing lineage tracking';


--
-- Name: COLUMN point_clouds.campaign_id; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.campaign_id IS 'Data collection campaign this scan belongs to';


--
-- Name: COLUMN point_clouds.scanner_id; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.scanner_id IS 'Physical scanner hardware used for this scan';


--
-- Name: COLUMN point_clouds.source_crs; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.source_crs IS 'EPSG code of original coordinate reference system';


--
-- Name: COLUMN point_clouds.platform_type; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.platform_type IS 'Scanning platform: terrestrial, aerial, mobile, UAV';


--
-- Name: COLUMN point_clouds.scan_bounds; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.scan_bounds IS 'PostGIS polygon defining point cloud coverage area in WGS84';


--
-- Name: COLUMN point_clouds.file_path; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.file_path IS 'S3 URI to point cloud file (e.g., s3://bucket-name/path/file.las)';


--
-- Name: COLUMN point_clouds.flight_altitude_m; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.flight_altitude_m IS 'Flight altitude above ground in meters (for aerial/UAV)';


--
-- Name: COLUMN point_clouds.flight_speed_ms; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.flight_speed_ms IS 'Platform speed during scanning in m/s';


--
-- Name: COLUMN point_clouds.scan_angle_deg; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.scan_angle_deg IS 'Scanner field of view angle in degrees';


--
-- Name: COLUMN point_clouds.overlap_percent; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.overlap_percent IS 'Swath overlap percentage (for aerial scans)';


--
-- Name: COLUMN point_clouds.point_density_per_m2; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.point_density_per_m2 IS 'Average point density in points per square meter';


--
-- Name: COLUMN point_clouds.processing_status; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.processing_status IS 'NULL for original scans, status for processed variants';


--
-- Name: COLUMN point_clouds.processing_progress; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.point_clouds.processing_progress IS 'Processing completion percentage (0-100)';


--
-- Name: point_clouds_point_cloud_id_seq; Type: SEQUENCE; Schema: point_clouds; Owner: supabase_admin
--

CREATE SEQUENCE point_clouds.point_clouds_point_cloud_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE point_clouds.point_clouds_point_cloud_id_seq OWNER TO supabase_admin;

--
-- Name: point_clouds_point_cloud_id_seq; Type: SEQUENCE OWNED BY; Schema: point_clouds; Owner: supabase_admin
--

ALTER SEQUENCE point_clouds.point_clouds_point_cloud_id_seq OWNED BY point_clouds.point_clouds.point_cloud_id;


--
-- Name: processing_lineage; Type: VIEW; Schema: point_clouds; Owner: supabase_admin
--

CREATE VIEW point_clouds.processing_lineage AS
 WITH RECURSIVE lineage AS (
         SELECT point_clouds.point_cloud_id,
            point_clouds.parent_point_cloud_id,
            point_clouds.variant_name,
            point_clouds.process_id,
            point_clouds.processing_status,
            1 AS depth,
            ARRAY[point_clouds.point_cloud_id] AS lineage_path
           FROM point_clouds.point_clouds
          WHERE (point_clouds.parent_point_cloud_id IS NULL)
        UNION ALL
         SELECT pc.point_cloud_id,
            pc.parent_point_cloud_id,
            pc.variant_name,
            pc.process_id,
            pc.processing_status,
            (l.depth + 1),
            (l.lineage_path || pc.point_cloud_id)
           FROM (point_clouds.point_clouds pc
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


ALTER TABLE point_clouds.processing_lineage OWNER TO supabase_admin;

--
-- Name: VIEW processing_lineage; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON VIEW point_clouds.processing_lineage IS 'Recursive view showing point cloud processing lineage and depth';


--
-- Name: scanner_types; Type: TABLE; Schema: point_clouds; Owner: supabase_admin
--

CREATE TABLE point_clouds.scanner_types (
    scanner_type_id integer NOT NULL,
    scanner_type_name character varying(100) NOT NULL,
    manufacturer character varying(200),
    description text
);


ALTER TABLE point_clouds.scanner_types OWNER TO supabase_admin;

--
-- Name: TABLE scanner_types; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON TABLE point_clouds.scanner_types IS 'LiDAR scanner type classifications and manufacturers';


--
-- Name: COLUMN scanner_types.scanner_type_name; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.scanner_types.scanner_type_name IS 'Scanner type name (e.g., Terrestrial_TLS, Aerial_ALS, Mobile_MLS, UAV_ULS)';


--
-- Name: scanner_types_scanner_type_id_seq; Type: SEQUENCE; Schema: point_clouds; Owner: supabase_admin
--

CREATE SEQUENCE point_clouds.scanner_types_scanner_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE point_clouds.scanner_types_scanner_type_id_seq OWNER TO supabase_admin;

--
-- Name: scanner_types_scanner_type_id_seq; Type: SEQUENCE OWNED BY; Schema: point_clouds; Owner: supabase_admin
--

ALTER SEQUENCE point_clouds.scanner_types_scanner_type_id_seq OWNED BY point_clouds.scanner_types.scanner_type_id;


--
-- Name: scanners; Type: TABLE; Schema: point_clouds; Owner: supabase_admin
--

CREATE TABLE point_clouds.scanners (
    scanner_id integer NOT NULL,
    scanner_type_id integer NOT NULL,
    serial_number character varying(100),
    acquisition_date date,
    calibration_date date,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);


ALTER TABLE point_clouds.scanners OWNER TO supabase_admin;

--
-- Name: TABLE scanners; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON TABLE point_clouds.scanners IS 'Individual LiDAR scanner hardware instances';


--
-- Name: COLUMN scanners.serial_number; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.scanners.serial_number IS 'Unique hardware serial number';


--
-- Name: COLUMN scanners.acquisition_date; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.scanners.acquisition_date IS 'Date scanner was acquired';


--
-- Name: COLUMN scanners.calibration_date; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON COLUMN point_clouds.scanners.calibration_date IS 'Last calibration date';


--
-- Name: scanners_scanner_id_seq; Type: SEQUENCE; Schema: point_clouds; Owner: supabase_admin
--

CREATE SEQUENCE point_clouds.scanners_scanner_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE point_clouds.scanners_scanner_id_seq OWNER TO supabase_admin;

--
-- Name: scanners_scanner_id_seq; Type: SEQUENCE OWNED BY; Schema: point_clouds; Owner: supabase_admin
--

ALTER SEQUENCE point_clouds.scanners_scanner_id_seq OWNED BY point_clouds.scanners.scanner_id;


--
-- Name: attribute_provenance; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.attribute_provenance (
    attribute_provenance_id integer NOT NULL,
    location_id integer NOT NULL,
    column_name character varying(64) NOT NULL,
    process_id integer NOT NULL,
    fetched_at timestamp with time zone DEFAULT now() NOT NULL,
    source_uri text,
    license character varying(100)
);


ALTER TABLE shared.attribute_provenance OWNER TO supabase_admin;

--
-- Name: TABLE attribute_provenance; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.attribute_provenance IS 'Where each value in a shared.locations column came from: one row per (location, column), replaced when the value is refreshed. Written by public.set_location_attributes in the same transaction as the value itself, so an attribute cannot be updated without saying what produced it.';


--
-- Name: COLUMN attribute_provenance.column_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.attribute_provenance.column_name IS 'Name of the shared.locations column this row describes. Not FK-checkable; the allowed set is enforced by public.set_location_attributes, which is the only writer.';


--
-- Name: COLUMN attribute_provenance.process_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.attribute_provenance.process_id IS 'shared.processes row for the source -- its name, version, licence and citation. NOT NULL: an acquired value with no registered source is exactly what this table exists to prevent.';


--
-- Name: COLUMN attribute_provenance.fetched_at; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.attribute_provenance.fetched_at IS 'When the value was retrieved from the source, which is not the same as when the source published it (shared.processes.publication_date) nor when the row was written.';


--
-- Name: COLUMN attribute_provenance.source_uri; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.attribute_provenance.source_uri IS 'Direct reference to the fetched artefact -- API request URL, DOI, or file identifier -- so a value can be traced to one retrieval, not just to a dataset.';


--
-- Name: COLUMN attribute_provenance.license; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.attribute_provenance.license IS 'Licence of the source value, e.g. CC-BY-4.0, Copernicus. Carried per value because this database is published and the attribution requirements travel with the data.';


--
-- Name: processes; Type: TABLE; Schema: shared; Owner: supabase_admin
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
    param_schema jsonb,
    workflow_key character varying(50),
    CONSTRAINT processes_category_check CHECK (((category)::text = ANY (ARRAY['detection'::text, 'classification'::text, 'simulation'::text, 'analysis'::text, 'aggregation'::text, 'acquisition'::text]))),
    CONSTRAINT processes_param_schema_is_object CHECK (((param_schema IS NULL) OR (jsonb_typeof(param_schema) = 'object'::text))),
    CONSTRAINT processes_runnable_has_param_schema CHECK (((workflow_key IS NULL) OR (param_schema IS NOT NULL)))
);


ALTER TABLE shared.processes OWNER TO supabase_admin;

--
-- Name: TABLE processes; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.processes IS 'Processing algorithms and methods with versioning and academic attribution';


--
-- Name: COLUMN processes.process_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processes.process_name IS 'Process name (e.g., LiDAR_Segmentation, Tree_Detection, Growth_Simulation)';


--
-- Name: COLUMN processes.algorithm_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processes.algorithm_name IS 'Algorithm used (e.g., RandomForest, DeepLearning, RulesBased)';


--
-- Name: COLUMN processes.category; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processes.category IS 'What kind of step this is. `acquisition` (added 2026-09-02) is a fetch from an external system -- Aquarius, ERA5, SoilGrids -- as opposed to a computation over data already held.';


--
-- Name: COLUMN processes.param_schema; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processes.param_schema IS 'JSON Schema for the workflow''s run_params. Properties marked "readOnly": true are recorded by the run rather than offered by the job menu -- web/jobs skips them when building its form, and emit_ro_crate includes them in the reproducibility record. Every key a run writes into run_params must be declared here; tests/automated/e2e/provenance/test_ro_crate.py asserts it.';


--
-- Name: COLUMN processes.workflow_key; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processes.workflow_key IS 'Short machine name of a runnable workflow -- the string request_job() takes and the runner matches against its local workflows.toml. NULL means the row is provenance only: it records what produced some data and cannot be requested. UNIQUE, so exactly one row (one version) is runnable per workflow; on a version bump the key is moved to the new row, not copied.';


--
-- Name: attribute_provenance; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.attribute_provenance WITH (security_invoker='on') AS
 SELECT ap.attribute_provenance_id,
    ap.location_id,
    l.location_name,
    ap.column_name,
    ap.process_id,
    p.process_name,
    p.version AS process_version,
    p.citation,
    ap.fetched_at,
    ap.source_uri,
    ap.license
   FROM ((shared.attribute_provenance ap
     JOIN shared.locations l ON ((l.location_id = ap.location_id)))
     JOIN shared.processes p ON ((p.process_id = ap.process_id)));


ALTER TABLE public.attribute_provenance OWNER TO supabase_admin;

--
-- Name: VIEW attribute_provenance; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.attribute_provenance IS 'Where every acquired shared.locations value came from, with the name, version and citation of the source resolved from shared.processes.';


--
-- Name: axis_structures; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.axis_structures (
    axis_structure_id integer NOT NULL,
    axis_structure_name character varying(50) NOT NULL,
    description text
);


ALTER TABLE trees.axis_structures OWNER TO supabase_admin;

--
-- Name: TABLE axis_structures; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.axis_structures IS 'Main axis configuration (single leader vs polycormic)';


--
-- Name: axis_structures; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.axis_structures AS
 SELECT axis_structures.axis_structure_id,
    axis_structures.axis_structure_name,
    axis_structures.description
   FROM trees.axis_structures;


ALTER TABLE public.axis_structures OWNER TO supabase_admin;

--
-- Name: VIEW axis_structures; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.axis_structures IS 'Public API view for axis structures lookup table';


--
-- Name: branch_elongation_habits; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.branch_elongation_habits (
    elongation_habit_id integer NOT NULL,
    elongation_habit_name character varying(50) NOT NULL,
    description text
);


ALTER TABLE trees.branch_elongation_habits OWNER TO supabase_admin;

--
-- Name: TABLE branch_elongation_habits; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.branch_elongation_habits IS 'Branch elongation patterns determining crown shape (acrotony, mesotony, basitony)';


--
-- Name: branch_elongation_habits; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.branch_elongation_habits AS
 SELECT branch_elongation_habits.elongation_habit_id,
    branch_elongation_habits.elongation_habit_name,
    branch_elongation_habits.description
   FROM trees.branch_elongation_habits;


ALTER TABLE public.branch_elongation_habits OWNER TO supabase_admin;

--
-- Name: VIEW branch_elongation_habits; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.branch_elongation_habits IS 'Public API view for branch elongation habits lookup table';


--
-- Name: campaigns; Type: TABLE; Schema: shared; Owner: supabase_admin
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
    owner_team_id integer,
    licence character varying(100) NOT NULL,
    access_level character varying(20) DEFAULT 'public'::character varying NOT NULL,
    embargo_until date,
    citation text,
    doi character varying(255),
    CONSTRAINT campaigns_access_level_check CHECK (((access_level)::text = ANY ((ARRAY['public'::character varying, 'campus'::character varying, 'registered'::character varying, 'team'::character varying])::text[]))),
    CONSTRAINT campaigns_campaign_type_check CHECK (((campaign_type)::text = ANY (ARRAY['lidar_flight'::text, 'field_inventory'::text, 'sensor_deployment'::text, 'drone_survey'::text, 'manual_update'::text, 'laser_scan'::text]))),
    CONSTRAINT campaigns_licence_not_blank_check CHECK ((btrim((licence)::text) <> ''::text)),
    CONSTRAINT campaigns_team_level_needs_owner_check CHECK ((((access_level)::text <> 'team'::text) OR (owner_team_id IS NOT NULL))),
    CONSTRAINT chk_campaign_dates CHECK (((end_date IS NULL) OR (end_date >= start_date)))
);


ALTER TABLE shared.campaigns OWNER TO supabase_admin;

--
-- Name: TABLE campaigns; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.campaigns IS 'Data collection campaigns (LiDAR flights, field inventories, sensor deployments)';


--
-- Name: COLUMN campaigns.campaign_type; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.campaign_type IS 'Type of data collection campaign: field_inventory, lidar_flight (airborne laser scanning), drone_survey (UAV, incl. ULS), laser_scan (ground-based TLS or MLS), sensor_deployment, manual_update.';


--
-- Name: COLUMN campaigns.methodology; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.methodology IS 'Description of data collection methodology used';


--
-- Name: COLUMN campaigns.equipment; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.equipment IS 'Equipment used (e.g., scanner model, measurement tools)';


--
-- Name: COLUMN campaigns.owner_team_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.owner_team_id IS 'Team that owns the dataset. Its members see the campaign at every access level and during an embargo. Required for access_level team.';


--
-- Name: COLUMN campaigns.licence; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.licence IS 'Licence of the dataset, preferably an SPDX identifier (CC-BY-4.0, CC0-1.0, ...) or "all rights reserved". Required.';


--
-- Name: COLUMN campaigns.access_level; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.access_level IS 'Who may read the campaign''s rows: public (everyone), campus (university network incl. VPN, and any signed-in account), registered (any signed-in account), team (members of owner_team_id). Curators and admins see all.';


--
-- Name: COLUMN campaigns.embargo_until; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.embargo_until IS 'Until this date only the owning team, curators and admins see the campaign''s rows, whatever the access level. NULL = no embargo.';


--
-- Name: COLUMN campaigns.citation; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.citation IS 'How to cite the dataset.';


--
-- Name: COLUMN campaigns.doi; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.campaigns.doi IS 'DOI of the dataset, if published (e.g. 10.5281/zenodo.123).';


--
-- Name: campaigns; Type: VIEW; Schema: public; Owner: supabase_admin
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
    campaigns.updated_by,
    campaigns.owner_team_id,
    campaigns.licence,
    campaigns.access_level,
    campaigns.embargo_until,
    campaigns.citation,
    campaigns.doi
   FROM shared.campaigns;


ALTER TABLE public.campaigns OWNER TO supabase_admin;

--
-- Name: VIEW campaigns; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.campaigns IS 'Public API view for data collection campaigns';


--
-- Name: climate_pathways; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.climate_pathways (
    climate_pathway_id smallint NOT NULL,
    climate_pathway_name character varying(50) NOT NULL,
    label character varying(50),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT climate_pathways_climate_pathway_id_check CHECK (((climate_pathway_id >= 0) AND (climate_pathway_id <= 9))),
    CONSTRAINT climate_pathways_climate_pathway_name_check CHECK (((climate_pathway_name)::text ~ '^[a-z][a-z0-9]*$'::text))
);


ALTER TABLE shared.climate_pathways OWNER TO supabase_admin;

--
-- Name: TABLE climate_pathways; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.climate_pathways IS 'Climate axis of a scenario. Pathway 0 (historical) is the observed 1981-2010 climatology held constant; the others are the CMIP6 SSPs the open-data connector acquires (CHELSA temperature/precipitation, SSP CO2). Names are single tokens because they are the suffix of a scenario name.';


--
-- Name: climate_pathways; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.climate_pathways WITH (security_invoker='on') AS
 SELECT climate_pathways.climate_pathway_id,
    climate_pathways.climate_pathway_name,
    climate_pathways.label,
    climate_pathways.description,
    climate_pathways.created_at
   FROM shared.climate_pathways;


ALTER TABLE public.climate_pathways OWNER TO supabase_admin;

--
-- Name: VIEW climate_pathways; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.climate_pathways IS 'Climate axis of scenarios: id + name + label. 0 = historical (observed climatology held constant), 1..3 = CMIP6 SSPs.';


--
-- Name: crown_architectures; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.crown_architectures (
    crown_architecture_id integer NOT NULL,
    crown_architecture_name character varying(50) NOT NULL,
    description text,
    typical_examples text
);


ALTER TABLE trees.crown_architectures OWNER TO supabase_admin;

--
-- Name: TABLE crown_architectures; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.crown_architectures IS 'Crown architecture classification (excurrent, decurrent, etc.)';


--
-- Name: COLUMN crown_architectures.typical_examples; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.crown_architectures.typical_examples IS 'Example tree types with this architecture';


--
-- Name: crown_architectures; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.crown_architectures AS
 SELECT crown_architectures.crown_architecture_id,
    crown_architectures.crown_architecture_name,
    crown_architectures.description,
    crown_architectures.typical_examples
   FROM trees.crown_architectures;


ALTER TABLE public.crown_architectures OWNER TO supabase_admin;

--
-- Name: VIEW crown_architectures; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.crown_architectures IS 'Public API view for crown architectures lookup table';


--
-- Name: crown_classes; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.crown_classes (
    crown_class_id integer NOT NULL,
    crown_class_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_crown_class_name CHECK (((crown_class_name)::text = ANY (ARRAY[('dominant'::character varying)::text, ('co_dominant'::character varying)::text, ('intermediate'::character varying)::text, ('overtopped'::character varying)::text, ('open_grown'::character varying)::text])))
);


ALTER TABLE trees.crown_classes OWNER TO supabase_admin;

--
-- Name: TABLE crown_classes; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.crown_classes IS 'Crown social/competitive position classification (FIA CCLCD / NEON canopyPosition analog)';


--
-- Name: crown_classes; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.crown_classes AS
 SELECT crown_classes.crown_class_id,
    crown_classes.crown_class_name,
    crown_classes.description
   FROM trees.crown_classes;


ALTER TABLE public.crown_classes OWNER TO supabase_admin;

--
-- Name: VIEW crown_classes; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.crown_classes IS 'Public API view for crown classes (competitive/social position) lookup table';


--
-- Name: crown_foliage_profiles; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.crown_foliage_profiles (
    crown_foliage_profile_id bigint NOT NULL,
    tree_id integer NOT NULL,
    process_id integer,
    distribution_type text NOT NULL,
    vertical_params numeric[],
    horizontal_params numeric[],
    total_leaf_area_m2 numeric(10,2),
    source text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT crown_foliage_profiles_distribution_type_check CHECK ((distribution_type = ANY (ARRAY['beta'::text, 'johnson_sb'::text, 'uniform'::text]))),
    CONSTRAINT crown_foliage_profiles_source_check CHECK ((source = ANY (ARRAY['species_literature_default'::text, 'fitted'::text, 'measured'::text]))),
    CONSTRAINT crown_foliage_profiles_total_leaf_area_m2_check CHECK ((total_leaf_area_m2 >= (0)::numeric))
);


ALTER TABLE trees.crown_foliage_profiles OWNER TO supabase_admin;

--
-- Name: TABLE crown_foliage_profiles; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.crown_foliage_profiles IS 'Crown leaf area density/distribution (not per-leaf geometry -- QSM is wood-only) for growpy/PVE procedural leaf instancing';


--
-- Name: COLUMN crown_foliage_profiles.distribution_type; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.crown_foliage_profiles.distribution_type IS 'beta (Le Port et al. 2000) | johnson_sb (Jerez et al. 2005) | uniform (no species-specific shape known yet -- not a placeholder pretending to be fitted data)';


--
-- Name: COLUMN crown_foliage_profiles.vertical_params; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.crown_foliage_profiles.vertical_params IS 'Distribution shape parameters (e.g. Beta''s two shape params); NULL when distribution_type = uniform';


--
-- Name: COLUMN crown_foliage_profiles.source; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.crown_foliage_profiles.source IS 'species_literature_default = literature parameters for this species; fitted = fit to our own data; measured = destructive/allometric measurement';


--
-- Name: crown_foliage_profiles; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.crown_foliage_profiles WITH (security_invoker='on') AS
 SELECT crown_foliage_profiles.crown_foliage_profile_id,
    crown_foliage_profiles.tree_id,
    crown_foliage_profiles.process_id,
    crown_foliage_profiles.distribution_type,
    crown_foliage_profiles.vertical_params,
    crown_foliage_profiles.horizontal_params,
    crown_foliage_profiles.total_leaf_area_m2,
    crown_foliage_profiles.source,
    crown_foliage_profiles.created_at,
    crown_foliage_profiles.created_by
   FROM trees.crown_foliage_profiles;


ALTER TABLE public.crown_foliage_profiles OWNER TO supabase_admin;

--
-- Name: VIEW crown_foliage_profiles; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.crown_foliage_profiles IS 'Public API view for crown foliage density/distribution profiles';


--
-- Name: crown_shapes; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.crown_shapes (
    crown_shape_id integer NOT NULL,
    crown_shape_name character varying(50) NOT NULL,
    description text
);


ALTER TABLE trees.crown_shapes OWNER TO supabase_admin;

--
-- Name: TABLE crown_shapes; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.crown_shapes IS 'Common crown shape descriptions (pyramidal, conical, globose, etc.)';


--
-- Name: crown_shapes; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.crown_shapes AS
 SELECT crown_shapes.crown_shape_id,
    crown_shapes.crown_shape_name,
    crown_shapes.description
   FROM trees.crown_shapes;


ALTER TABLE public.crown_shapes OWNER TO supabase_admin;

--
-- Name: VIEW crown_shapes; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.crown_shapes IS 'Public API view for crown shapes lookup table';


--
-- Name: entity_matches; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.entity_matches (
    entity_match_id bigint NOT NULL,
    observation_id bigint NOT NULL,
    tree_entity_id uuid,
    decision character varying(20) NOT NULL,
    method character varying(100) NOT NULL,
    score numeric(4,3),
    reference_campaign_id integer,
    process_id integer,
    decided_by character varying(200) NOT NULL,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    supersedes_entity_match_id bigint,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT entity_matches_decision_check CHECK (((decision)::text = ANY ((ARRAY['matched'::character varying, 'new'::character varying, 'ambiguous'::character varying])::text[]))),
    CONSTRAINT entity_matches_entity_unless_ambiguous_check CHECK ((((decision)::text = 'ambiguous'::text) OR (tree_entity_id IS NOT NULL))),
    CONSTRAINT entity_matches_not_self_check CHECK ((supersedes_entity_match_id <> entity_match_id)),
    CONSTRAINT entity_matches_score_check CHECK (((score >= (0)::numeric) AND (score <= (1)::numeric)))
);


ALTER TABLE trees.entity_matches OWNER TO supabase_admin;

--
-- Name: TABLE entity_matches; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.entity_matches IS 'Re-identification decisions: which physical tree (tree_entity_id) an observation belongs to, how that was decided and by whom. Revisable: a new decision supersedes the previous one, which is kept. Per observation the decisions form one chain, so exactly one is current (public.current_entity_matches).';


--
-- Name: COLUMN entity_matches.tree_entity_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.tree_entity_id IS 'The physical tree the observation is assigned to: an existing entity for matched, a new UUID for new. NULL only for ambiguous. No foreign key: an entity is a UUID shared by tree rows, not a row of its own.';


--
-- Name: COLUMN entity_matches.decision; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.decision IS 'matched (an existing tree) | new (no counterpart; a new entity) | ambiguous (no safe decision; held for review).';


--
-- Name: COLUMN entity_matches.method; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.method IS 'How the decision was reached. Deliberately unconstrained so a new method needs no migration; values in use: first_campaign (the first campaign at its site: every observation it makes is new), single_campaign (the only campaign at its site), tag_number (field tag or tree number), spatial (position gate plus attribute check, e.g. mutual nearest partner within 1 m and a compatible DBH), manual (a person''s review).';


--
-- Name: COLUMN entity_matches.score; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.score IS 'Match confidence from 0 to 1, when the method gives one.';


--
-- Name: COLUMN entity_matches.reference_campaign_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.reference_campaign_id IS 'The campaign matched against (the other half of the campaign pair). NULL when there was none, e.g. a single-campaign site.';


--
-- Name: COLUMN entity_matches.process_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.process_id IS 'The matching process and version, when a process decided.';


--
-- Name: COLUMN entity_matches.decided_by; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.decided_by IS 'Who decided: a person''s e-mail or a process name.';


--
-- Name: COLUMN entity_matches.supersedes_entity_match_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.entity_matches.supersedes_entity_match_id IS 'The earlier decision on the same observation that this one replaces. Superseded decisions are kept, never deleted.';


--
-- Name: observations; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.observations (
    observation_id bigint NOT NULL,
    location_id integer NOT NULL,
    campaign_id integer NOT NULL,
    process_id integer,
    tree_id integer,
    point_cloud_id integer,
    instance_id text,
    observed_on date,
    "position" extensions.geometry(Point,4326),
    position_uncertainty_m numeric(6,3),
    species_id integer,
    dbh_cm numeric(6,2),
    height_m numeric(6,2),
    source_attributes jsonb,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT observations_dbh_cm_check CHECK ((dbh_cm > (0)::numeric)),
    CONSTRAINT observations_height_m_check CHECK (((height_m > (0)::numeric) AND (height_m <= (200)::numeric))),
    CONSTRAINT observations_instance_needs_cloud_check CHECK (((instance_id IS NULL) OR (point_cloud_id IS NOT NULL))),
    CONSTRAINT observations_locatable_check CHECK (((tree_id IS NOT NULL) OR ("position" IS NOT NULL))),
    CONSTRAINT observations_position_uncertainty_m_check CHECK ((position_uncertainty_m >= (0)::numeric)),
    CONSTRAINT observations_source_attributes_object_check CHECK (((source_attributes IS NULL) OR (jsonb_typeof(source_attributes) = 'object'::text)))
);


ALTER TABLE trees.observations OWNER TO supabase_admin;

--
-- Name: TABLE observations; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.observations IS 'One tree as detected or measured by one campaign: the input of re-identification. A field-inventory tree points at its tree row (tree_id) and needs no copied attributes; a detection from a point cloud carries its own position and attributes plus point_cloud_id and instance_id. The link to a physical tree is decided in trees.entity_matches, never here.';


--
-- Name: COLUMN observations.campaign_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.campaign_id IS 'The campaign (dataset) that made the observation; decides who may read it (access levels).';


--
-- Name: COLUMN observations.process_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.process_id IS 'The detection or measurement process (e.g. a segmentation pipeline and version).';


--
-- Name: COLUMN observations.tree_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.tree_id IS 'The tree row that carries this observation in its campaign''s variant, when there is one: the field tree itself, or the tree created for a detection decided as new. At most one observation per tree row.';


--
-- Name: COLUMN observations.point_cloud_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.point_cloud_id IS 'The point cloud the tree was detected in.';


--
-- Name: COLUMN observations.instance_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.instance_id IS 'The tree''s label within that point cloud (e.g. TreeID). Unique per point cloud; requires point_cloud_id.';


--
-- Name: COLUMN observations."position"; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations."position" IS 'Stem position as observed, WGS84. NULL when the observation is a tree row, which holds the position.';


--
-- Name: COLUMN observations.position_uncertainty_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.position_uncertainty_m IS 'Planimetric position uncertainty in metres, as the source states it.';


--
-- Name: COLUMN observations.dbh_cm; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.dbh_cm IS 'DBH as observed, centimetres. NULL when the observation is a tree row.';


--
-- Name: COLUMN observations.height_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.height_m IS 'Height as observed, metres. NULL when the observation is a tree row.';


--
-- Name: COLUMN observations.source_attributes; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.observations.source_attributes IS 'Source fields without a column of their own, as a JSON object keyed by the source''s names.';


--
-- Name: current_entity_matches; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.current_entity_matches WITH (security_invoker='on') AS
 SELECT m.entity_match_id,
    m.observation_id,
    o.location_id,
    o.campaign_id,
    o.tree_id,
    m.tree_entity_id,
    m.decision,
    m.method,
    m.score,
    m.reference_campaign_id,
    m.decided_by,
    m.decided_at
   FROM (trees.entity_matches m
     JOIN trees.observations o ON ((o.observation_id = m.observation_id)))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM trees.entity_matches s
          WHERE (s.supersedes_entity_match_id = m.entity_match_id))));


ALTER TABLE public.current_entity_matches OWNER TO supabase_admin;

--
-- Name: VIEW current_entity_matches; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.current_entity_matches IS 'The one current decision per observation, with the observation''s location, campaign and tree row.';


--
-- Name: damage_agents; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.damage_agents (
    damage_agent_id integer NOT NULL,
    damage_agent_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_damage_agent_name CHECK (((damage_agent_name)::text = ANY (ARRAY[('none'::character varying)::text, ('insect'::character varying)::text, ('disease'::character varying)::text, ('fire'::character varying)::text, ('wind'::character varying)::text, ('snow_ice'::character varying)::text, ('drought'::character varying)::text, ('mechanical'::character varying)::text, ('animal'::character varying)::text, ('human_activity'::character varying)::text, ('competition'::character varying)::text, ('unknown'::character varying)::text])))
);


ALTER TABLE trees.damage_agents OWNER TO supabase_admin;

--
-- Name: TABLE damage_agents; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.damage_agents IS 'Cause of tree damage, decline, or mortality (FIA AGENTCD analog)';


--
-- Name: damage_agents; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.damage_agents AS
 SELECT damage_agents.damage_agent_id,
    damage_agents.damage_agent_name,
    damage_agents.description
   FROM trees.damage_agents;


ALTER TABLE public.damage_agents OWNER TO supabase_admin;

--
-- Name: VIEW damage_agents; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.damage_agents IS 'Public API view for damage agents lookup table';


--
-- Name: data_source_types; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.data_source_types (
    data_source_type_id integer NOT NULL,
    data_source_type_name character varying(50) NOT NULL,
    description text
);


ALTER TABLE trees.data_source_types OWNER TO supabase_admin;

--
-- Name: TABLE data_source_types; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.data_source_types IS 'How tree measurement data was collected or generated';


--
-- Name: data_source_types; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.data_source_types AS
 SELECT data_source_types.data_source_type_id,
    data_source_types.data_source_type_name,
    data_source_types.description
   FROM trees.data_source_types;


ALTER TABLE public.data_source_types OWNER TO supabase_admin;

--
-- Name: VIEW data_source_types; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.data_source_types IS 'Data source type classifications (field, lidar, photogrammetry, estimated, simulated)';


--
-- Name: deadwood; Type: VIEW; Schema: public; Owner: supabase_admin
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
    deadwood.created_by,
    deadwood.campaign_id,
    deadwood.geom,
    deadwood.diameter_top_cm,
    deadwood.void_diameter_cm,
    deadwood.source_deadwood_id,
    deadwood.source_attributes
   FROM forest_floor.deadwood;


ALTER TABLE public.deadwood OWNER TO supabase_admin;

--
-- Name: VIEW deadwood; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.deadwood IS 'Public API view for dead wood inventory';


--
-- Name: disturbance_events; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.disturbance_events (
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
    CONSTRAINT disturbance_events_affected_area_m2_check CHECK ((affected_area_m2 > (0)::numeric)),
    CONSTRAINT disturbance_events_disturbance_type_check CHECK (((disturbance_type)::text = ANY (ARRAY[('storm'::character varying)::text, ('fire'::character varying)::text, ('insect'::character varying)::text, ('drought'::character varying)::text, ('disease'::character varying)::text, ('flood'::character varying)::text, ('frost'::character varying)::text, ('snow_damage'::character varying)::text, ('landslide'::character varying)::text, ('other'::character varying)::text]))),
    CONSTRAINT disturbance_events_severity_check CHECK (((severity)::text = ANY (ARRAY[('low'::character varying)::text, ('moderate'::character varying)::text, ('high'::character varying)::text, ('severe'::character varying)::text])))
);


ALTER TABLE shared.disturbance_events OWNER TO supabase_admin;

--
-- Name: TABLE disturbance_events; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.disturbance_events IS 'Natural disturbance events affecting forest areas (storms, fire, insects, etc.)';


--
-- Name: COLUMN disturbance_events.disturbance_type; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.disturbance_events.disturbance_type IS 'Type of natural disturbance';


--
-- Name: COLUMN disturbance_events.severity; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.disturbance_events.severity IS 'Disturbance severity level';


--
-- Name: COLUMN disturbance_events.affected_area_m2; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.disturbance_events.affected_area_m2 IS 'Estimated area affected in m²';


--
-- Name: disturbance_events; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.disturbance_events WITH (security_invoker='on') AS
 SELECT disturbance_events.disturbance_event_id,
    disturbance_events.location_id,
    disturbance_events.plot_id,
    disturbance_events.disturbance_type,
    disturbance_events.event_date,
    disturbance_events.end_date,
    disturbance_events.severity,
    disturbance_events.affected_area_m2,
    disturbance_events.description,
    disturbance_events.notes,
    disturbance_events.created_at,
    disturbance_events.updated_at,
    disturbance_events.created_by,
    disturbance_events.updated_by
   FROM shared.disturbance_events;


ALTER TABLE public.disturbance_events OWNER TO supabase_admin;

--
-- Name: VIEW disturbance_events; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.disturbance_events IS 'Public API view for natural disturbance events';


--
-- Name: entity_matches; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.entity_matches WITH (security_invoker='on') AS
 SELECT entity_matches.entity_match_id,
    entity_matches.observation_id,
    entity_matches.tree_entity_id,
    entity_matches.decision,
    entity_matches.method,
    entity_matches.score,
    entity_matches.reference_campaign_id,
    entity_matches.process_id,
    entity_matches.decided_by,
    entity_matches.decided_at,
    entity_matches.supersedes_entity_match_id,
    entity_matches.notes,
    entity_matches.created_at,
    entity_matches.created_by
   FROM trees.entity_matches;


ALTER TABLE public.entity_matches OWNER TO supabase_admin;

--
-- Name: VIEW entity_matches; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.entity_matches IS 'Every re-identification decision, superseded ones included. Writable by contributors; revise by inserting a decision that supersedes the current one.';


--
-- Name: environments; Type: VIEW; Schema: public; Owner: supabase_admin
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


ALTER TABLE public.environments OWNER TO supabase_admin;

--
-- Name: VIEW environments; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.environments IS 'Public API view for environments table';


--
-- Name: geometric_crown_solids; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.geometric_crown_solids (
    geometric_crown_solid_id integer NOT NULL,
    geometric_crown_solid_name character varying(50) NOT NULL,
    description text,
    relative_lateral_area numeric(4,2),
    relative_volume numeric(4,2),
    relative_drag numeric(4,2),
    CONSTRAINT geometric_crown_solids_relative_drag_check CHECK (((relative_drag >= (0)::numeric) AND (relative_drag <= (1)::numeric))),
    CONSTRAINT geometric_crown_solids_relative_lateral_area_check CHECK (((relative_lateral_area >= (0)::numeric) AND (relative_lateral_area <= (1)::numeric))),
    CONSTRAINT geometric_crown_solids_relative_volume_check CHECK (((relative_volume >= (0)::numeric) AND (relative_volume <= (1)::numeric)))
);


ALTER TABLE trees.geometric_crown_solids OWNER TO supabase_admin;

--
-- Name: TABLE geometric_crown_solids; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.geometric_crown_solids IS 'Geometric crown shape models for simulation (area, volume, drag calculations)';


--
-- Name: COLUMN geometric_crown_solids.relative_lateral_area; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.geometric_crown_solids.relative_lateral_area IS 'Relative frontal/lateral area (1.0 = cylinder baseline)';


--
-- Name: COLUMN geometric_crown_solids.relative_volume; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.geometric_crown_solids.relative_volume IS 'Relative crown volume (1.0 = cylinder baseline)';


--
-- Name: COLUMN geometric_crown_solids.relative_drag; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.geometric_crown_solids.relative_drag IS 'Relative wind drag coefficient (1.0 = cylinder baseline)';


--
-- Name: geometric_crown_solids; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.geometric_crown_solids AS
 SELECT geometric_crown_solids.geometric_crown_solid_id,
    geometric_crown_solids.geometric_crown_solid_name,
    geometric_crown_solids.description,
    geometric_crown_solids.relative_lateral_area,
    geometric_crown_solids.relative_volume,
    geometric_crown_solids.relative_drag
   FROM trees.geometric_crown_solids;


ALTER TABLE public.geometric_crown_solids OWNER TO supabase_admin;

--
-- Name: VIEW geometric_crown_solids; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.geometric_crown_solids IS 'Public API view for geometric crown solids lookup table';


--
-- Name: ground_vegetation; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ground_vegetation WITH (security_invoker='on') AS
 SELECT ground_vegetation.ground_vegetation_id,
    ground_vegetation.location_id,
    ground_vegetation.plot_id,
    ground_vegetation.species_name,
    ground_vegetation.cover_percent,
    ground_vegetation.height_cm,
    ground_vegetation.layer,
    ground_vegetation.measurement_date,
    ground_vegetation.notes,
    ground_vegetation.created_at,
    ground_vegetation.created_by,
    ground_vegetation.campaign_id
   FROM forest_floor.ground_vegetation;


ALTER TABLE public.ground_vegetation OWNER TO supabase_admin;

--
-- Name: VIEW ground_vegetation; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ground_vegetation IS 'Public API view for ground vegetation surveys';


--
-- Name: growth_forms; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.growth_forms (
    growth_form_id integer NOT NULL,
    growth_form_name character varying(50) NOT NULL,
    description text
);


ALTER TABLE trees.growth_forms OWNER TO supabase_admin;

--
-- Name: TABLE growth_forms; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.growth_forms IS 'General growth form classification (dendroid, arborescent, etc.)';


--
-- Name: growth_forms; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.growth_forms AS
 SELECT growth_forms.growth_form_id,
    growth_forms.growth_form_name,
    growth_forms.description
   FROM trees.growth_forms;


ALTER TABLE public.growth_forms OWNER TO supabase_admin;

--
-- Name: VIEW growth_forms; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.growth_forms IS 'Public API view for growth forms lookup table';


--
-- Name: growth_orientations; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.growth_orientations (
    growth_orientation_id integer NOT NULL,
    growth_orientation_name character varying(50) NOT NULL,
    description text
);


ALTER TABLE trees.growth_orientations OWNER TO supabase_admin;

--
-- Name: TABLE growth_orientations; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.growth_orientations IS 'Shoot growth orientation (orthotropic=vertical, plagiotrophic=horizontal)';


--
-- Name: growth_orientations; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.growth_orientations AS
 SELECT growth_orientations.growth_orientation_id,
    growth_orientations.growth_orientation_name,
    growth_orientations.description
   FROM trees.growth_orientations;


ALTER TABLE public.growth_orientations OWNER TO supabase_admin;

--
-- Name: VIEW growth_orientations; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.growth_orientations IS 'Public API view for growth orientations lookup table';


--
-- Name: species; Type: TABLE; Schema: shared; Owner: supabase_admin
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
    leaf_type character varying(20),
    CONSTRAINT species_growth_rate_check CHECK (((growth_rate)::text = ANY (ARRAY[('very_slow'::character varying)::text, ('slow'::character varying)::text, ('moderate'::character varying)::text, ('fast'::character varying)::text, ('very_fast'::character varying)::text]))),
    CONSTRAINT species_leaf_type_check CHECK (((leaf_type)::text = ANY ((ARRAY['needleleaf'::character varying, 'broadleaf'::character varying])::text[]))),
    CONSTRAINT species_shade_tolerance_check CHECK (((shade_tolerance)::text = ANY (ARRAY[('very_low'::character varying)::text, ('low'::character varying)::text, ('moderate'::character varying)::text, ('high'::character varying)::text, ('very_high'::character varying)::text])))
);


ALTER TABLE shared.species OWNER TO supabase_admin;

--
-- Name: TABLE species; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.species IS 'Tree species reference with growth characteristics';


--
-- Name: COLUMN species.max_height_m; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.species.max_height_m IS 'Maximum typical height in meters';


--
-- Name: COLUMN species.max_dbh_cm; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.species.max_dbh_cm IS 'Maximum typical diameter at breast height in centimeters';


--
-- Name: COLUMN species.typical_lifespan_years; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.species.typical_lifespan_years IS 'Typical lifespan in years';


--
-- Name: COLUMN species.growth_rate; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.species.growth_rate IS 'Relative growth rate (very_slow, slow, moderate, fast, very_fast)';


--
-- Name: COLUMN species.shade_tolerance; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.species.shade_tolerance IS 'Shade tolerance level (very_low, low, moderate, high, very_high)';


--
-- Name: COLUMN species.is_deciduous; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.species.is_deciduous IS 'Whether species is deciduous (true) or evergreen (false), NULL if unknown';


--
-- Name: COLUMN species.leaf_type; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.species.leaf_type IS 'Leaf habit: needleleaf (conifers, larch included) or broadleaf. Independent of is_deciduous. Matches the Copernicus Dominant Leaf Type classes.';


--
-- Name: growth_simulations; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.growth_simulations (
    growth_simulation_id bigint NOT NULL,
    simulation_run_id uuid NOT NULL,
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
    is_mortality boolean DEFAULT false NOT NULL,
    stand_basal_area_m2ha numeric(8,4),
    stand_volume_m3ha numeric(10,3),
    stand_biomass_tha numeric(10,3),
    stand_stem_count_ha integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(200),
    CONSTRAINT chk_crown_base_le_height CHECK (((crown_base_height_m IS NULL) OR (height_m IS NULL) OR (crown_base_height_m <= height_m))),
    CONSTRAINT growth_simulations_basal_area_m2_check CHECK (((basal_area_m2 IS NULL) OR (basal_area_m2 >= (0)::numeric))),
    CONSTRAINT growth_simulations_biomass_kg_check CHECK (((biomass_kg IS NULL) OR (biomass_kg >= (0)::numeric))),
    CONSTRAINT growth_simulations_carbon_content_kg_check CHECK (((carbon_content_kg IS NULL) OR (carbon_content_kg >= (0)::numeric))),
    CONSTRAINT growth_simulations_crown_base_height_m_check CHECK (((crown_base_height_m IS NULL) OR (crown_base_height_m >= (0)::numeric))),
    CONSTRAINT growth_simulations_crown_width_m_check CHECK (((crown_width_m IS NULL) OR (crown_width_m >= (0)::numeric))),
    CONSTRAINT growth_simulations_dbh_cm_check CHECK (((dbh_cm IS NULL) OR (dbh_cm > (0)::numeric))),
    CONSTRAINT growth_simulations_health_score_check CHECK (((health_score IS NULL) OR ((health_score >= (0)::numeric) AND (health_score <= (1)::numeric)))),
    CONSTRAINT growth_simulations_height_m_check CHECK (((height_m IS NULL) OR (height_m > (0)::numeric))),
    CONSTRAINT growth_simulations_projection_year_check CHECK (((projection_year >= 1900) AND (projection_year <= 2300))),
    CONSTRAINT growth_simulations_simulator_name_check CHECK (((simulator_name)::text = ANY (ARRAY[('SILVA'::character varying)::text, ('FVS'::character varying)::text, ('iLand'::character varying)::text, ('manual'::character varying)::text, ('other'::character varying)::text]))),
    CONSTRAINT growth_simulations_stand_basal_area_m2ha_check CHECK (((stand_basal_area_m2ha IS NULL) OR (stand_basal_area_m2ha >= (0)::numeric))),
    CONSTRAINT growth_simulations_stand_biomass_tha_check CHECK (((stand_biomass_tha IS NULL) OR (stand_biomass_tha >= (0)::numeric))),
    CONSTRAINT growth_simulations_stand_stem_count_ha_check CHECK (((stand_stem_count_ha IS NULL) OR (stand_stem_count_ha >= 0))),
    CONSTRAINT growth_simulations_stand_volume_m3ha_check CHECK (((stand_volume_m3ha IS NULL) OR (stand_volume_m3ha >= (0)::numeric))),
    CONSTRAINT growth_simulations_volume_m3_check CHECK (((volume_m3 IS NULL) OR (volume_m3 >= (0)::numeric)))
);


ALTER TABLE trees.growth_simulations OWNER TO supabase_admin;

--
-- Name: TABLE growth_simulations; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.growth_simulations IS 'Per-tree forest growth projections from SILVA, FVS, iLand, or manual estimation. One row per (run_id, tree_entity_id, projection_year). run_id groups all rows produced by a single simulation run.';


--
-- Name: COLUMN growth_simulations.simulation_run_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.growth_simulations.simulation_run_id IS 'UUID identifying a single simulation run. All rows with the same run_id belong to one simulator execution and can be compared as a complete forest state.';


--
-- Name: COLUMN growth_simulations.tree_entity_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.growth_simulations.tree_entity_id IS 'Stable UUID of the physical tree (cross-variant identity from trees.trees.tree_entity_id).';


--
-- Name: COLUMN growth_simulations.base_tree_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.growth_simulations.base_tree_id IS 'trees.trees row (tree_id) used as the simulation input (baseline measurement).';


--
-- Name: COLUMN growth_simulations.projection_year; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.growth_simulations.projection_year IS 'Calendar year this projection describes.';


--
-- Name: COLUMN growth_simulations.is_mortality; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.growth_simulations.is_mortality IS 'True if this tree dies in this projection time step.';


--
-- Name: COLUMN growth_simulations.stand_basal_area_m2ha; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.growth_simulations.stand_basal_area_m2ha IS 'Stand-level basal area (m²/ha) — same value repeated for all trees in this run_id+Year.';


--
-- Name: growth_simulations; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.growth_simulations WITH (security_invoker='on') AS
 SELECT gs.growth_simulation_id,
    gs.simulation_run_id,
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
    gs.is_mortality,
    gs.stand_basal_area_m2ha,
    gs.stand_volume_m3ha,
    gs.stand_biomass_tha,
    gs.stand_stem_count_ha,
    gs.created_at,
    gs.created_by
   FROM ((trees.growth_simulations gs
     LEFT JOIN shared.scenarios s ON ((gs.scenario_id = s.scenario_id)))
     LEFT JOIN shared.species sp ON ((gs.species_id = sp.species_id)));


ALTER TABLE public.growth_simulations OWNER TO supabase_admin;

--
-- Name: VIEW growth_simulations; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.growth_simulations IS 'Flat view of growth simulation projections with scenario and species names resolved. Filter by scenario_name + projection_year to get a full forest state for UE Time Machine.';


--
-- Name: images; Type: VIEW; Schema: public; Owner: supabase_admin
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


ALTER TABLE public.images OWNER TO supabase_admin;

--
-- Name: VIEW images; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.images IS 'Public API view for imagery table';


--
-- Name: inclusion_rules; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.inclusion_rules (
    inclusion_rule_id integer NOT NULL,
    sampling_design_id integer NOT NULL,
    min_dbh_cm numeric(6,2) DEFAULT 0 NOT NULL,
    max_dbh_cm numeric(6,2),
    rule_type character varying(20) NOT NULL,
    radius_m numeric(7,3),
    basal_area_factor_m2ha numeric(7,3),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT inclusion_rules_basal_area_factor_m2ha_check CHECK ((basal_area_factor_m2ha > (0)::numeric)),
    CONSTRAINT inclusion_rules_check CHECK (((max_dbh_cm IS NULL) OR (max_dbh_cm > min_dbh_cm))),
    CONSTRAINT inclusion_rules_check1 CHECK (((((rule_type)::text = 'fixed_radius'::text) AND (radius_m IS NOT NULL) AND (basal_area_factor_m2ha IS NULL)) OR (((rule_type)::text = 'angle_count'::text) AND (basal_area_factor_m2ha IS NOT NULL) AND (radius_m IS NULL)))),
    CONSTRAINT inclusion_rules_min_dbh_cm_check CHECK ((min_dbh_cm >= (0)::numeric)),
    CONSTRAINT inclusion_rules_radius_m_check CHECK ((radius_m > (0)::numeric)),
    CONSTRAINT inclusion_rules_rule_type_check CHECK (((rule_type)::text = ANY ((ARRAY['fixed_radius'::character varying, 'angle_count'::character varying])::text[])))
);


ALTER TABLE shared.inclusion_rules OWNER TO supabase_admin;

--
-- Name: TABLE inclusion_rules; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.inclusion_rules IS 'Which trees a plot of this design records, by DBH range: within a fixed radius (one rule = fixed-radius plot, several = nested circles) or by angle count with a basal-area factor. Ranges of one design must not overlap. A design without rules uses each plot''s own area (shared.plots.area_m2) as the inclusion area.';


--
-- Name: COLUMN inclusion_rules.min_dbh_cm; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.inclusion_rules.min_dbh_cm IS 'Lower DBH bound of the rule, inclusive.';


--
-- Name: COLUMN inclusion_rules.max_dbh_cm; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.inclusion_rules.max_dbh_cm IS 'Upper DBH bound of the rule, exclusive. NULL = no upper bound.';


--
-- Name: COLUMN inclusion_rules.radius_m; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.inclusion_rules.radius_m IS 'Horizontal plot radius for fixed_radius rules.';


--
-- Name: COLUMN inclusion_rules.basal_area_factor_m2ha; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.inclusion_rules.basal_area_factor_m2ha IS 'Basal-area factor (m²/ha per counted tree) for angle_count rules, e.g. 4 in the German national inventory.';


--
-- Name: inclusion_rules; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.inclusion_rules WITH (security_invoker='on') AS
 SELECT inclusion_rules.inclusion_rule_id,
    inclusion_rules.sampling_design_id,
    inclusion_rules.min_dbh_cm,
    inclusion_rules.max_dbh_cm,
    inclusion_rules.rule_type,
    inclusion_rules.radius_m,
    inclusion_rules.basal_area_factor_m2ha,
    inclusion_rules.description,
    inclusion_rules.created_at,
    inclusion_rules.updated_at,
    inclusion_rules.created_by,
    inclusion_rules.updated_by
   FROM shared.inclusion_rules;


ALTER TABLE public.inclusion_rules OWNER TO supabase_admin;

--
-- Name: VIEW inclusion_rules; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.inclusion_rules IS 'Inclusion rules per sampling design: fixed radius or angle count by DBH range.';


--
-- Name: processing_jobs; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.processing_jobs (
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
    started_at timestamp with time zone,
    claimed_by character varying(200),
    attempts integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 1 NOT NULL,
    next_attempt_at timestamp with time zone,
    CONSTRAINT chk_attempts_nonneg CHECK (((attempts >= 0) AND (max_attempts >= 1))),
    CONSTRAINT chk_completed_date CHECK (((completed_at IS NULL) OR (completed_at >= submitted_at))),
    CONSTRAINT chk_started_after_submitted CHECK (((started_at IS NULL) OR (started_at >= submitted_at))),
    CONSTRAINT processing_jobs_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('running'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text])))
);


ALTER TABLE shared.processing_jobs OWNER TO supabase_admin;

--
-- Name: TABLE processing_jobs; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.processing_jobs IS 'Tracks external processing jobs and compute workflows';


--
-- Name: COLUMN processing_jobs.external_job_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.external_job_id IS 'Idempotency key supplied by the caller. Already UNIQUE, and adopted as the deduplication key: enqueueing the same key twice yields one job, so a repeated request from VR or a double-clicked button cannot start the same run twice. NULL for jobs that do not need deduplication.';


--
-- Name: COLUMN processing_jobs.status; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.status IS 'Job status: pending, running, completed, failed';


--
-- Name: COLUMN processing_jobs.input_data; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.input_data IS 'JSON representation of input parameters and data references';


--
-- Name: COLUMN processing_jobs.output_data; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.output_data IS 'JSON representation of output data references and results';


--
-- Name: COLUMN processing_jobs.started_at; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.started_at IS 'When a runner claimed the job and began executing it. NULL while pending.';


--
-- Name: COLUMN processing_jobs.claimed_by; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.claimed_by IS 'Identity of the runner instance holding the job (host and process), so `runner reap` can tell a live claim from an abandoned one.';


--
-- Name: COLUMN processing_jobs.attempts; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.attempts IS 'How many times the job has been claimed. Incremented on claim, so an abandoned job that is reaped and re-queued is not retried forever.';


--
-- Name: COLUMN processing_jobs.max_attempts; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.max_attempts IS 'Claim budget. DEFAULT 1 = no automatic retry, which is the v1 policy: these workflows fail for parameter reasons far more often than transient ones.';


--
-- Name: COLUMN processing_jobs.next_attempt_at; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.processing_jobs.next_attempt_at IS 'Earliest time a runner may claim the job. NULL means immediately. Set by `runner reap` to hold a recovered job back.';


--
-- Name: job_status; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.job_status WITH (security_invoker='on') AS
 SELECT j.processing_job_id,
    j.external_job_id,
    j.workflow_name,
    j.workflow_version,
    j.status,
    j.submitted_by,
    j.submitted_at,
    j.started_at,
    j.completed_at,
        CASE
            WHEN (j.started_at IS NULL) THEN NULL::integer
            ELSE (EXTRACT(epoch FROM (COALESCE(j.completed_at, now()) - j.started_at)))::integer
        END AS duration_seconds,
    j.attempts,
    j.max_attempts,
    j.error_message,
    j.input_data,
    j.output_data
   FROM shared.processing_jobs j;


ALTER TABLE public.job_status OWNER TO supabase_admin;

--
-- Name: VIEW job_status; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.job_status IS 'Every job the caller is allowed to see -- their own, or all of them for a curator. Omits claimed_by and next_attempt_at, which are the runner''s bookkeeping rather than the submitter''s answer. An anon caller matches no policy and so reads an empty list.';


--
-- Name: locations; Type: VIEW; Schema: public; Owner: supabase_admin
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
    locations.updated_by,
    locations.forest_growth_region,
    locations.soil_moistness,
    locations.soil_nutrient_supply,
    locations.crs_epsg
   FROM shared.locations;


ALTER TABLE public.locations OWNER TO supabase_admin;

--
-- Name: VIEW locations; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.locations IS 'Public API view for locations reference table';


--
-- Name: management_events; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.management_events (
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
    CONSTRAINT management_events_affected_area_m2_check CHECK ((affected_area_m2 > (0)::numeric)),
    CONSTRAINT management_events_event_type_check CHECK (((event_type)::text = ANY (ARRAY[('thinning'::character varying)::text, ('planting'::character varying)::text, ('harvesting'::character varying)::text, ('pruning'::character varying)::text, ('fertilization'::character varying)::text, ('prescribed_burn'::character varying)::text, ('salvage_logging'::character varying)::text, ('site_preparation'::character varying)::text, ('other'::character varying)::text])))
);


ALTER TABLE shared.management_events OWNER TO supabase_admin;

--
-- Name: TABLE management_events; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.management_events IS 'Forest management activities (thinning, planting, harvesting, etc.)';


--
-- Name: COLUMN management_events.event_type; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.management_events.event_type IS 'Type of management activity';


--
-- Name: COLUMN management_events.affected_area_m2; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.management_events.affected_area_m2 IS 'Area affected by the management activity in m²';


--
-- Name: management_events; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.management_events WITH (security_invoker='on') AS
 SELECT management_events.management_event_id,
    management_events.location_id,
    management_events.plot_id,
    management_events.event_type,
    management_events.event_date,
    management_events.end_date,
    management_events.description,
    management_events.affected_area_m2,
    management_events.performed_by,
    management_events.notes,
    management_events.created_at,
    management_events.updated_at,
    management_events.created_by,
    management_events.updated_by
   FROM shared.management_events;


ALTER TABLE public.management_events OWNER TO supabase_admin;

--
-- Name: VIEW management_events; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.management_events IS 'Public API view for forest management events';


--
-- Name: management_regimes; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.management_regimes (
    management_regime_id smallint NOT NULL,
    management_regime_name character varying(100) NOT NULL,
    description text,
    silva_rules jsonb,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT management_regimes_management_regime_id_check CHECK (((management_regime_id >= 0) AND (management_regime_id <= 99))),
    CONSTRAINT management_regimes_management_regime_name_check CHECK (((management_regime_name)::text ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$'::text))
);


ALTER TABLE shared.management_regimes OWNER TO supabase_admin;

--
-- Name: TABLE management_regimes; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.management_regimes IS 'Management axis of a scenario. Small integer id + snake_case name, so Unreal can sort on the number and label with the text. Regime 0 (none) marks scenarios that hold acquired data only, never trees.';


--
-- Name: COLUMN management_regimes.silva_rules; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.management_regimes.silva_rules IS 'silvaR thinning preset: {"removal_method","max_removal_fraction","rules":[{species, thinning_type, guide_curve, metric, intervention, crop_trees_per_ha, n_competitors, target_dbh_cm, target_probability}]}. Species by scientific name or "all". NULL = no management. silva-connector turns this into silva_thinning_regime().';


--
-- Name: management_regimes; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.management_regimes WITH (security_invoker='on') AS
 SELECT management_regimes.management_regime_id,
    management_regimes.management_regime_name,
    management_regimes.description,
    management_regimes.silva_rules,
    management_regimes.created_at
   FROM shared.management_regimes;


ALTER TABLE public.management_regimes OWNER TO supabase_admin;

--
-- Name: VIEW management_regimes; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.management_regimes IS 'Management axis of scenarios: id + name + description + the silvaR thinning preset (silva_rules). Regime 0 holds no trees.';


--
-- Name: observations; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.observations WITH (security_invoker='on') AS
 SELECT observations.observation_id,
    observations.location_id,
    observations.campaign_id,
    observations.process_id,
    observations.tree_id,
    observations.point_cloud_id,
    observations.instance_id,
    observations.observed_on,
    observations."position",
    observations.position_uncertainty_m,
    observations.species_id,
    observations.dbh_cm,
    observations.height_m,
    observations.source_attributes,
    observations.created_at,
    observations.created_by
   FROM trees.observations;


ALTER TABLE public.observations OWNER TO supabase_admin;

--
-- Name: VIEW observations; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.observations IS 'Trees as detected or measured by one campaign, the input of re-identification. Writable by contributors.';


--
-- Name: phanerophyte_height_classes; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.phanerophyte_height_classes (
    height_class_id integer NOT NULL,
    height_class_name character varying(50) NOT NULL,
    description text,
    min_height_m numeric(6,2),
    max_height_m numeric(6,2),
    CONSTRAINT chk_height_class_order CHECK (((min_height_m IS NULL) OR (max_height_m IS NULL) OR (min_height_m < max_height_m))),
    CONSTRAINT phanerophyte_height_classes_max_height_m_check CHECK ((max_height_m > (0)::numeric)),
    CONSTRAINT phanerophyte_height_classes_min_height_m_check CHECK ((min_height_m >= (0)::numeric))
);


ALTER TABLE trees.phanerophyte_height_classes OWNER TO supabase_admin;

--
-- Name: TABLE phanerophyte_height_classes; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.phanerophyte_height_classes IS 'Tree height classification (mega/meso/micro-phanerophyte)';


--
-- Name: COLUMN phanerophyte_height_classes.min_height_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.phanerophyte_height_classes.min_height_m IS 'Minimum height for this class (NULL = no lower bound)';


--
-- Name: COLUMN phanerophyte_height_classes.max_height_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.phanerophyte_height_classes.max_height_m IS 'Maximum height for this class (NULL = no upper bound)';


--
-- Name: phanerophyte_height_classes; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.phanerophyte_height_classes AS
 SELECT phanerophyte_height_classes.height_class_id,
    phanerophyte_height_classes.height_class_name,
    phanerophyte_height_classes.description,
    phanerophyte_height_classes.min_height_m,
    phanerophyte_height_classes.max_height_m
   FROM trees.phanerophyte_height_classes;


ALTER TABLE public.phanerophyte_height_classes OWNER TO supabase_admin;

--
-- Name: VIEW phanerophyte_height_classes; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.phanerophyte_height_classes IS 'Public API view for phanerophyte height classes lookup table';


--
-- Name: phenology_observations; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.phenology_observations (
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
    CONSTRAINT phenology_observations_intensity_percent_check CHECK (((intensity_percent >= (0)::numeric) AND (intensity_percent <= (100)::numeric))),
    CONSTRAINT phenology_observations_phenophase_status_check CHECK (((phenophase_status)::text = ANY (ARRAY[('not_started'::character varying)::text, ('beginning'::character varying)::text, ('intermediate'::character varying)::text, ('peak'::character varying)::text, ('ending'::character varying)::text, ('completed'::character varying)::text]))),
    CONSTRAINT phenology_observations_phenophase_type_check CHECK (((phenophase_type)::text = ANY (ARRAY[('bud_break'::character varying)::text, ('leaf_out'::character varying)::text, ('flowering'::character varying)::text, ('fruit_set'::character varying)::text, ('leaf_color'::character varying)::text, ('leaf_fall'::character varying)::text, ('dormancy'::character varying)::text])))
);


ALTER TABLE trees.phenology_observations OWNER TO supabase_admin;

--
-- Name: TABLE phenology_observations; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.phenology_observations IS 'Tree phenology observations tracking seasonal development phases';


--
-- Name: COLUMN phenology_observations.phenophase_type; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.phenology_observations.phenophase_type IS 'Type of phenological phase being observed';


--
-- Name: COLUMN phenology_observations.phenophase_status; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.phenology_observations.phenophase_status IS 'Current status of the phenophase';


--
-- Name: COLUMN phenology_observations.intensity_percent; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.phenology_observations.intensity_percent IS 'Intensity of the phenophase (0-100%)';


--
-- Name: phenology_observations; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.phenology_observations WITH (security_invoker='on') AS
 SELECT phenology_observations.phenology_observation_id,
    phenology_observations.tree_id,
    phenology_observations.observation_date,
    phenology_observations.phenophase_type,
    phenology_observations.phenophase_status,
    phenology_observations.intensity_percent,
    phenology_observations.observer,
    phenology_observations.notes,
    phenology_observations.created_at,
    phenology_observations.created_by
   FROM trees.phenology_observations;


ALTER TABLE public.phenology_observations OWNER TO supabase_admin;

--
-- Name: VIEW phenology_observations; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.phenology_observations IS 'Public API view for tree phenology observations';


--
-- Name: plots; Type: TABLE; Schema: shared; Owner: supabase_admin
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
    sampling_design_id integer,
    stratum_id integer,
    parent_plot_id integer,
    sampling_weight numeric(12,6) DEFAULT 1 NOT NULL,
    area_source character varying(20),
    CONSTRAINT plots_area_m2_check CHECK ((area_m2 > (0)::numeric)),
    CONSTRAINT plots_area_source_check CHECK (((area_source)::text = ANY ((ARRAY['surveyed'::character varying, 'nominal'::character varying, 'convex_hull'::character varying])::text[]))),
    CONSTRAINT plots_not_own_parent_check CHECK (((parent_plot_id IS NULL) OR (parent_plot_id <> plot_id))),
    CONSTRAINT plots_sampling_weight_check CHECK ((sampling_weight > (0)::numeric))
);


ALTER TABLE shared.plots OWNER TO supabase_admin;

--
-- Name: TABLE plots; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.plots IS 'Sub-plot divisions within locations for detailed research grids';


--
-- Name: COLUMN plots.plot_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.plot_name IS 'Plot identifier, unique within a location';


--
-- Name: COLUMN plots.plot_number; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.plot_number IS 'Numeric plot identifier for ordering';


--
-- Name: COLUMN plots.area_m2; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.area_m2 IS 'Plot area in square metres: the inclusion area of every tree when the design has no inclusion rules (census or fixed-area plot). A plot without an area inherits the nearest enclosing plot''s (parent_plot_id). Horizontal area; area_source says where it comes from.';


--
-- Name: COLUMN plots.boundary; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.boundary IS 'PostGIS polygon defining plot boundaries in WGS84';


--
-- Name: COLUMN plots.sampling_design_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.sampling_design_id IS 'Sampling design (protocol) this plot was laid out and measured under. NULL = none recorded.';


--
-- Name: COLUMN plots.stratum_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.stratum_id IS 'Stratum of a stratified design; must belong to sampling_design_id.';


--
-- Name: COLUMN plots.parent_plot_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.parent_plot_id IS 'Enclosing sample unit: a plot''s cluster, or a subplot''s plot. NULL = top level.';


--
-- Name: COLUMN plots.sampling_weight; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.sampling_weight IS 'Sampling weight of this unit for the estimator (Open Foris Arena''s weight); 1 = equal weight. Not part of the expansion factor.';


--
-- Name: COLUMN plots.area_source; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.plots.area_source IS 'Where area_m2 comes from: surveyed (measured boundary) | nominal (protocol size) | convex_hull (hull of the stem positions, as silva-connector derives stand area).';


--
-- Name: sampling_designs; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.sampling_designs (
    sampling_design_id integer NOT NULL,
    design_name character varying(200) NOT NULL,
    strategy character varying(30) NOT NULL,
    protocol_name character varying(200),
    protocol_version character varying(50),
    dbh_measuring_height_m numeric(4,2) DEFAULT 1.3 NOT NULL,
    min_dbh_cm numeric(6,2),
    reporting_area_ha numeric(14,4),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT sampling_designs_dbh_measuring_height_m_check CHECK ((dbh_measuring_height_m > (0)::numeric)),
    CONSTRAINT sampling_designs_min_dbh_cm_check CHECK ((min_dbh_cm >= (0)::numeric)),
    CONSTRAINT sampling_designs_reporting_area_ha_check CHECK ((reporting_area_ha > (0)::numeric)),
    CONSTRAINT sampling_designs_strategy_check CHECK (((strategy)::text = ANY ((ARRAY['census'::character varying, 'simple_random'::character varying, 'systematic'::character varying, 'stratified_random'::character varying, 'stratified_systematic'::character varying, 'two_phase'::character varying])::text[])))
);


ALTER TABLE shared.sampling_designs OWNER TO supabase_admin;

--
-- Name: TABLE sampling_designs; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.sampling_designs IS 'One inventory protocol: how plots were chosen (strategy), which field manual and version, at which height DBH is measured and from which DBH trees are recorded. Plots point here; inclusion rules and strata hang off it. strategy = census means every tree of the plot area was recorded.';


--
-- Name: COLUMN sampling_designs.strategy; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.sampling_designs.strategy IS 'How the sample units were chosen: census | simple_random | systematic | stratified_random | stratified_systematic | two_phase (Open Foris Arena''s strategies plus census).';


--
-- Name: COLUMN sampling_designs.protocol_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.sampling_designs.protocol_name IS 'Field manual or inventory protocol the data was measured under, e.g. BWI 2022 Aufnahmeanweisung.';


--
-- Name: COLUMN sampling_designs.dbh_measuring_height_m; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.sampling_designs.dbh_measuring_height_m IS 'Height above ground at which DBH is measured under this protocol (1.3 m in Europe, 1.37 m in the US). trees.stems.dbh_measuring_height_m overrides it per stem.';


--
-- Name: COLUMN sampling_designs.min_dbh_cm; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.sampling_designs.min_dbh_cm IS 'Smallest DBH recorded under this protocol. Trees below it get no expansion factor. NULL = no threshold.';


--
-- Name: COLUMN sampling_designs.reporting_area_ha; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.sampling_designs.reporting_area_ha IS 'Area of the population the sample represents (the inventory area), for totals. NULL = per-hectare results only.';


--
-- Name: plot_inclusion; Type: VIEW; Schema: shared; Owner: supabase_admin
--

CREATE VIEW shared.plot_inclusion WITH (security_invoker='on') AS
 WITH RECURSIVE up AS (
         SELECT p.plot_id AS start_plot_id,
            p.plot_id,
            p.parent_plot_id,
            p.sampling_design_id,
            p.area_m2,
            0 AS depth
           FROM shared.plots p
        UNION ALL
         SELECT up.start_plot_id,
            q.plot_id,
            q.parent_plot_id,
            q.sampling_design_id,
            q.area_m2,
            (up.depth + 1)
           FROM (shared.plots q
             JOIN up ON ((q.plot_id = up.parent_plot_id)))
          WHERE (up.depth < 10)
        ), resolved AS (
         SELECT up.start_plot_id AS plot_id,
            (array_agg(up.sampling_design_id ORDER BY up.depth) FILTER (WHERE (up.sampling_design_id IS NOT NULL)))[1] AS sampling_design_id,
            (array_agg(up.area_m2 ORDER BY up.depth) FILTER (WHERE (up.area_m2 > (0)::numeric)))[1] AS area_m2,
            (array_agg(up.plot_id ORDER BY up.depth) FILTER (WHERE (up.area_m2 > (0)::numeric)))[1] AS area_plot_id
           FROM up
          GROUP BY up.start_plot_id
        )
 SELECT r.plot_id,
    r.sampling_design_id,
    r.area_m2,
    d.min_dbh_cm,
    hr.has_rules,
        CASE
            WHEN hr.has_rules THEN r.plot_id
            ELSE r.area_plot_id
        END AS sample_unit_id
   FROM ((resolved r
     LEFT JOIN shared.sampling_designs d ON ((d.sampling_design_id = r.sampling_design_id)))
     CROSS JOIN LATERAL ( SELECT (EXISTS ( SELECT 1
                   FROM shared.inclusion_rules ir
                  WHERE (ir.sampling_design_id = r.sampling_design_id))) AS has_rules) hr);


ALTER TABLE shared.plot_inclusion OWNER TO supabase_admin;

--
-- Name: VIEW plot_inclusion; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON VIEW shared.plot_inclusion IS 'Every plot with its resolved sampling design and inclusion area (its own, else the nearest enclosing plot''s), the design''s minimum DBH, whether the design has inclusion rules, and the sample unit its trees belong to. The set-based equivalent of shared.sample_unit_id() and the resolution in shared.expansion_factor_ha().';


--
-- Name: stems; Type: TABLE; Schema: trees; Owner: supabase_admin
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
    dbh_measuring_height_m numeric(4,2),
    CONSTRAINT stems_bark_thickness_mm_check CHECK (((bark_thickness_mm >= (0)::numeric) AND (bark_thickness_mm <= (200)::numeric))),
    CONSTRAINT stems_dbh_cm_check CHECK (((dbh_cm > (0)::numeric) AND (dbh_cm <= (1000)::numeric))),
    CONSTRAINT stems_dbh_measuring_height_check CHECK (((dbh_measuring_height_m IS NULL) OR (dbh_measuring_height_m > (0)::numeric))),
    CONSTRAINT stems_stem_height_m_check CHECK (((stem_height_m > (0)::numeric) AND (stem_height_m <= (200)::numeric))),
    CONSTRAINT stems_stem_number_check CHECK ((stem_number >= 1)),
    CONSTRAINT stems_stem_volume_m3_check CHECK ((stem_volume_m3 >= (0)::numeric)),
    CONSTRAINT stems_sweep_cm_per_m_check CHECK ((sweep_cm_per_m >= (0)::numeric)),
    CONSTRAINT stems_taper_ratio_check CHECK (((taper_ratio >= (0)::numeric) AND (taper_ratio <= (1)::numeric))),
    CONSTRAINT stems_wood_density_kg_m3_check CHECK (((wood_density_kg_m3 >= (100)::numeric) AND (wood_density_kg_m3 <= (2000)::numeric)))
);


ALTER TABLE trees.stems OWNER TO supabase_admin;

--
-- Name: TABLE stems; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.stems IS 'Individual stem measurements for multi-stem trees';


--
-- Name: COLUMN stems.stem_number; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.stems.stem_number IS 'Stem number (1=main stem, 2+=secondary stems)';


--
-- Name: COLUMN stems.dbh_cm; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.stems.dbh_cm IS 'Stem diameter in centimetres at the measuring height: dbh_measuring_height_m, else the sampling design''s, else 1.3 m.';


--
-- Name: COLUMN stems.taper_ratio; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.stems.taper_ratio IS 'Ratio of top diameter to bottom diameter';


--
-- Name: COLUMN stems.sweep_cm_per_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.stems.sweep_cm_per_m IS 'Maximum horizontal deviation per meter of height';


--
-- Name: COLUMN stems.dbh_measuring_height_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.stems.dbh_measuring_height_m IS 'Height at which dbh_cm was measured, when it differs from the design''s (e.g. raised above a buttress or a fork). NULL = the design''s height, 1.3 m without a design.';


--
-- Name: tree_status; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.tree_status (
    tree_status_id integer NOT NULL,
    tree_status_name character varying(100) NOT NULL,
    description text,
    CONSTRAINT chk_tree_status_name CHECK (((tree_status_name)::text = ANY (ARRAY[('healthy'::character varying)::text, ('stressed'::character varying)::text, ('declining'::character varying)::text, ('dead'::character varying)::text, ('harvested'::character varying)::text, ('missing'::character varying)::text, ('downed'::character varying)::text, ('broken'::character varying)::text])))
);


ALTER TABLE trees.tree_status OWNER TO supabase_admin;

--
-- Name: TABLE tree_status; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.tree_status IS 'Tree health and status classification';


--
-- Name: trees; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.trees (
    tree_id integer NOT NULL,
    tree_entity_id uuid DEFAULT gen_random_uuid(),
    variant_id integer NOT NULL,
    parent_tree_id integer,
    point_cloud_id integer,
    campaign_id integer,
    location_id integer NOT NULL,
    plot_id integer,
    scenario_id integer NOT NULL,
    variant_type_id integer NOT NULL,
    process_id integer,
    species_id integer,
    tree_status_id integer,
    branching_pattern_id integer,
    bark_characteristic_id integer,
    measurement_date date,
    data_source_type_id integer,
    height_m numeric(6,2),
    height_source character varying(50),
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
    geometric_crown_solid_id integer,
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
    source_tree_id text,
    source_attributes jsonb,
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
    CONSTRAINT trees_source_attributes_object_check CHECK (((source_attributes IS NULL) OR (jsonb_typeof(source_attributes) = 'object'::text))),
    CONSTRAINT trees_source_tree_id_needs_campaign_check CHECK (((source_tree_id IS NULL) OR (campaign_id IS NOT NULL))),
    CONSTRAINT trees_species_confidence_check CHECK (((species_confidence >= (0)::numeric) AND (species_confidence <= (1)::numeric))),
    CONSTRAINT trees_volume_m3_check CHECK ((volume_m3 >= (0)::numeric))
);


ALTER TABLE trees.trees OWNER TO supabase_admin;

--
-- Name: TABLE trees; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.trees IS 'Tree measurement and simulation records with spatial positions';


--
-- Name: COLUMN trees.tree_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.tree_id IS 'Unique row identifier for this tree record';


--
-- Name: COLUMN trees.tree_entity_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.tree_entity_id IS 'Persistent UUID identifying the physical tree across all variants. Unique within a variant (trees_variant_entity_key). How an entity was assigned across campaigns is recorded in trees.entity_matches.';


--
-- Name: COLUMN trees.variant_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.variant_id IS 'Forest state group — all trees sharing this variant_id belong to the same time step within a scenario. Use for UE time-travel switching.';


--
-- Name: COLUMN trees.parent_tree_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.parent_tree_id IS 'Parent tree record for tracking growth or modifications';


--
-- Name: COLUMN trees.point_cloud_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.point_cloud_id IS 'Source point cloud if tree was detected from LiDAR';


--
-- Name: COLUMN trees.campaign_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.campaign_id IS 'Data collection campaign this measurement belongs to';


--
-- Name: COLUMN trees.plot_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.plot_id IS 'Sub-plot within the location where tree is located';


--
-- Name: COLUMN trees.measurement_date; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.measurement_date IS 'Actual date of field measurement (may differ from created_at)';


--
-- Name: COLUMN trees.data_source_type_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.data_source_type_id IS 'FK to trees.data_source_types — how the data was collected or generated';


--
-- Name: COLUMN trees.height_source; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.height_source IS 'How height_m was arrived at. NULL means unrecorded -- it is not a claim that the height was measured. Values in use: ''measured'' (field instrument), ''measured_tls'' (terrestrial laser scan, scripts/import/import_tls_heights.py), ''allometric_fitted_species'' / ''allometric_fitted_leaf_type'' (Naslund H-D curve fitted to this database''s measured trees, per species or pooled per leaf type, see scripts/import/fill_missing_heights.py), ''allometric_yield_table'' (yield-table height, scripts/seed/ecosense_canopy_height_fix.sql), ''simulated_silva'' (SILVA projection, see silva-connector). Pair with data_source_type_id, which records how the tree record as a whole was produced, and process_id, which identifies the run.';


--
-- Name: COLUMN trees.crown_boundary; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.crown_boundary IS 'PostGIS polygon defining crown extent';


--
-- Name: COLUMN trees.crown_offset_x_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.crown_offset_x_m IS 'Crown center offset from trunk position (X/East-West in meters)';


--
-- Name: COLUMN trees.crown_offset_y_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.crown_offset_y_m IS 'Crown center offset from trunk position (Y/North-South in meters)';


--
-- Name: COLUMN trees."position"; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees."position" IS 'PostGIS point for tree location in WGS84';


--
-- Name: COLUMN trees.position_original; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.position_original IS 'Original coordinates in source CRS before WGS84 transformation';


--
-- Name: COLUMN trees.source_crs; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.source_crs IS 'EPSG code of original coordinate reference system for position_original';


--
-- Name: COLUMN trees.time_delta_yrs; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.time_delta_yrs IS 'Time elapsed since parent variant (for growth simulations)';


--
-- Name: COLUMN trees.health_score; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.health_score IS 'Tree health assessment score (0=dead, 1=optimal)';


--
-- Name: COLUMN trees.species_confidence; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.species_confidence IS 'Confidence in species identification (0-1)';


--
-- Name: COLUMN trees.position_confidence; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.position_confidence IS 'Confidence in position accuracy (0-1)';


--
-- Name: COLUMN trees.height_confidence; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.height_confidence IS 'Confidence in height measurement (0-1)';


--
-- Name: COLUMN trees.status_change_date; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.status_change_date IS 'Date when tree status changed (e.g., mortality date)';


--
-- Name: COLUMN trees.tree_number; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.tree_number IS 'Local tree identifier within the location/plot (e.g., 62 in ecosense plot 4, or 367 in mathisle)';


--
-- Name: COLUMN trees.height_class_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.height_class_id IS 'Phanerophyte height classification';


--
-- Name: COLUMN trees.crown_architecture_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.crown_architecture_id IS 'Crown architecture type (excurrent, decurrent, etc.)';


--
-- Name: COLUMN trees.elongation_habit_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.elongation_habit_id IS 'Branch elongation pattern (acrotony, mesotony, basitony)';


--
-- Name: COLUMN trees.growth_orientation_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.growth_orientation_id IS 'Predominant growth orientation (orthotropic/plagiotrophic)';


--
-- Name: COLUMN trees.shoot_elongation_type_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.shoot_elongation_type_id IS 'Typical shoot elongation type';


--
-- Name: COLUMN trees.crown_shape_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.crown_shape_id IS 'Observed crown shape';


--
-- Name: COLUMN trees.geometric_crown_solid_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.geometric_crown_solid_id IS 'Geometric model for crown volume/drag calculations';


--
-- Name: COLUMN trees.axis_structure_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.axis_structure_id IS 'Main axis structure (single leader/polycormic)';


--
-- Name: COLUMN trees.growth_form_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.growth_form_id IS 'General growth form classification';


--
-- Name: COLUMN trees.live_crown_ratio; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.live_crown_ratio IS 'Computed ratio of live crown height to total tree height';


--
-- Name: COLUMN trees.crown_class_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.crown_class_id IS 'Crown competitive/social position (dominant/co_dominant/intermediate/overtopped/open_grown)';


--
-- Name: COLUMN trees.damage_agent_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.damage_agent_id IS 'Primary agent responsible for observed damage or decline, if any';


--
-- Name: COLUMN trees.defoliation_percent; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.defoliation_percent IS 'ICP Forests-style defoliation assessment (0-100%, in 5% steps by convention)';


--
-- Name: COLUMN trees.discolouration_percent; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.discolouration_percent IS 'ICP Forests-style foliage discolouration assessment (0-100%)';


--
-- Name: COLUMN trees.crown_transparency_percent; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.crown_transparency_percent IS 'ICP Forests-style crown transparency assessment (0-100%)';


--
-- Name: COLUMN trees.sensor_ref; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.sensor_ref IS 'Source-agnostic reference identifying the sensor cluster installed on this tree. Matches the prefix of sensor.sensors.serial_number, so all of a tree''s sensors resolve from it. For the current Ecosense data this value is the external provider''s name prefix (e.g. Beech_Mixed_8), but the column carries no provider semantics. NULL for non-instrumented trees.';


--
-- Name: COLUMN trees.source_tree_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.source_tree_id IS 'The producer''s own identifier of this tree (e.g. Pathfinder tree_id, a 3Dtrees.earth instance id). Unique per campaign and variant, so re-importing or re-pushing the same inventory is idempotent. Requires campaign_id.';


--
-- Name: COLUMN trees.source_attributes; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.trees.source_attributes IS 'Protocol-specific codes without a column of their own, as a JSON object keyed by the source''s column names (e.g. {"canopy_layer": "1", "rs_visibility": "2", "species_raw": "Larix_europaea"}). The protocol is the plot''s sampling design. A code becomes a column once a second source shares it.';


--
-- Name: plot_summaries; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.plot_summaries WITH (security_invoker='on') AS
 WITH tree_rows AS (
         SELECT t.variant_id,
            t.location_id,
            t.species_id,
            pi.sample_unit_id AS plot_id,
            e.ef,
            e.ba_ha,
            e.vol_ha,
            e.bio_ha,
            e.c_ha,
            ba.basal_area_m2,
            t.volume_m3,
            t.biomass_kg,
            t.carbon_content_kg
           FROM ((((((trees.trees t
             JOIN shared.plot_inclusion pi ON ((pi.plot_id = t.plot_id)))
             LEFT JOIN trees.stems s1 ON (((s1.tree_id = t.tree_id) AND (s1.stem_number = 1))))
             LEFT JOIN shared.inclusion_rules ir ON (((ir.sampling_design_id = pi.sampling_design_id) AND (s1.dbh_cm >= ir.min_dbh_cm) AND ((ir.max_dbh_cm IS NULL) OR (s1.dbh_cm < ir.max_dbh_cm)) AND (s1.dbh_cm > (0)::numeric))))
             LEFT JOIN trees.tree_status ts ON ((ts.tree_status_id = t.tree_status_id)))
             LEFT JOIN LATERAL ( SELECT (sum((pi() * (((s.dbh_cm / 200.0) ^ (2)::numeric))::double precision)))::numeric AS basal_area_m2
                   FROM trees.stems s
                  WHERE (s.tree_id = t.tree_id)) ba ON (true))
             CROSS JOIN LATERAL ( SELECT x.ef,
                    (x.ef * ba.basal_area_m2) AS ba_ha,
                    (x.ef * t.volume_m3) AS vol_ha,
                    (x.ef * t.biomass_kg) AS bio_ha,
                    (x.ef * t.carbon_content_kg) AS c_ha
                   FROM ( SELECT shared.ef_value(pi.has_rules, (ir.rule_type)::text, ir.radius_m, ir.basal_area_factor_m2ha, pi.area_m2, pi.min_dbh_cm, s1.dbh_cm) AS ef
                         OFFSET 0) x) e)
          WHERE ((COALESCE(ts.tree_status_name, ''::character varying))::text <> ALL ((ARRAY['dead'::character varying, 'harvested'::character varying, 'missing'::character varying, 'downed'::character varying])::text[]))
        )
 SELECT r.plot_id,
    r.variant_id,
    r.location_id,
    p.sampling_design_id,
    p.stratum_id,
    p.sampling_weight,
    r.species_id,
    (count(r.ef))::integer AS trees_measured,
    ((count(*) - count(r.ef)))::integer AS trees_without_expansion_factor,
    round(COALESCE(sum(r.ef), (0)::numeric), 4) AS stems_ha,
        CASE
            WHEN (count(r.basal_area_m2) FILTER (WHERE (r.ef IS NOT NULL)) = count(r.ef)) THEN round(COALESCE(sum(r.ba_ha), (0)::numeric), 6)
            ELSE NULL::numeric
        END AS basal_area_m2ha,
        CASE
            WHEN (count(r.volume_m3) FILTER (WHERE (r.ef IS NOT NULL)) = count(r.ef)) THEN round(COALESCE(sum(r.vol_ha), (0)::numeric), 6)
            ELSE NULL::numeric
        END AS volume_m3ha,
        CASE
            WHEN (count(r.biomass_kg) FILTER (WHERE (r.ef IS NOT NULL)) = count(r.ef)) THEN round((COALESCE(sum(r.bio_ha), (0)::numeric) / (1000)::numeric), 6)
            ELSE NULL::numeric
        END AS biomass_tha,
        CASE
            WHEN (count(r.carbon_content_kg) FILTER (WHERE (r.ef IS NOT NULL)) = count(r.ef)) THEN round((COALESCE(sum(r.c_ha), (0)::numeric) / (1000)::numeric), 6)
            ELSE NULL::numeric
        END AS carbon_tha
   FROM (tree_rows r
     JOIN shared.plots p ON ((p.plot_id = r.plot_id)))
  GROUP BY r.plot_id, r.variant_id, r.location_id, p.sampling_design_id, p.stratum_id, p.sampling_weight, r.species_id;


ALTER TABLE public.plot_summaries OWNER TO supabase_admin;

--
-- Name: VIEW plot_summaries; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.plot_summaries IS 'Per sample unit (plot, or the census plot of a fully mapped site), variant and species: living trees per hectare and their basal area, volume, biomass and carbon per hectare, each tree weighted by its expansion factor. A value is NULL when a counted tree lacks it. Sum over species for the all-species value. Filter on variant_id.';


--
-- Name: plots; Type: VIEW; Schema: public; Owner: supabase_admin
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
    plots.updated_by,
    plots.sampling_design_id,
    plots.stratum_id,
    plots.parent_plot_id,
    plots.sampling_weight,
    plots.area_source
   FROM shared.plots;


ALTER TABLE public.plots OWNER TO supabase_admin;

--
-- Name: VIEW plots; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.plots IS 'Public API view for sub-plot divisions within locations';


--
-- Name: point_clouds; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.point_clouds WITH (security_invoker='on') AS
 SELECT point_clouds.point_cloud_id,
    point_clouds.parent_point_cloud_id,
    point_clouds.location_id,
    point_clouds.scenario_id,
    point_clouds.variant_type_id,
    point_clouds.process_id,
    point_clouds.campaign_id,
    point_clouds.scanner_id,
    point_clouds.variant_name,
    point_clouds.scan_date,
    point_clouds.sensor_model,
    point_clouds.source_crs,
    point_clouds.platform_type,
    point_clouds.scan_bounds,
    point_clouds.file_path,
    point_clouds.flight_altitude_m,
    point_clouds.flight_speed_ms,
    point_clouds.scan_angle_deg,
    point_clouds.overlap_percent,
    point_clouds.point_count,
    point_clouds.point_density_per_m2,
    point_clouds.file_size_mb,
    point_clouds.processing_status,
    point_clouds.processing_progress,
    point_clouds.error_message,
    point_clouds.created_at,
    point_clouds.updated_at,
    point_clouds.created_by,
    point_clouds.updated_by
   FROM point_clouds.point_clouds;


ALTER TABLE public.point_clouds OWNER TO supabase_admin;

--
-- Name: VIEW point_clouds; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.point_clouds IS 'Public API view for point clouds table';


--
-- Name: qsms; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.qsms (
    qsm_id bigint NOT NULL,
    tree_entity_id uuid NOT NULL,
    tree_id integer NOT NULL,
    point_cloud_id integer,
    process_id integer,
    lod smallint,
    local_crs text,
    origin_position extensions.geometry(PointZ,4326),
    cylinder_count integer,
    total_volume_m3 numeric(10,3),
    trunk_volume_m3 numeric(10,3),
    branch_volume_m3 numeric(10,3),
    dbh_qsm_cm numeric(6,2),
    height_qsm_m numeric(6,2),
    crown_area_qsm_m2 numeric(10,2),
    is_corrected boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT qsms_branch_volume_m3_check CHECK ((branch_volume_m3 >= (0)::numeric)),
    CONSTRAINT qsms_crown_area_qsm_m2_check CHECK ((crown_area_qsm_m2 >= (0)::numeric)),
    CONSTRAINT qsms_cylinder_count_check CHECK ((cylinder_count >= 0)),
    CONSTRAINT qsms_dbh_qsm_cm_check CHECK (((dbh_qsm_cm > (0)::numeric) AND (dbh_qsm_cm <= (1000)::numeric))),
    CONSTRAINT qsms_height_qsm_m_check CHECK (((height_qsm_m > (0)::numeric) AND (height_qsm_m <= (200)::numeric))),
    CONSTRAINT qsms_lod_check CHECK (((lod >= 0) AND (lod <= 4))),
    CONSTRAINT qsms_total_volume_m3_check CHECK ((total_volume_m3 >= (0)::numeric)),
    CONSTRAINT qsms_trunk_volume_m3_check CHECK ((trunk_volume_m3 >= (0)::numeric))
);


ALTER TABLE trees.qsms OWNER TO supabase_admin;

--
-- Name: TABLE qsms; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.qsms IS 'QSM (Quantitative Structure Model) reconstructions -- one row per reconstruction, several per physical tree possible';


--
-- Name: COLUMN qsms.tree_entity_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsms.tree_entity_id IS 'Stable physical-tree identity (trees.trees.tree_entity_id) -- groups QSMs of the same tree across scans/tools/parameter sets';


--
-- Name: COLUMN qsms.lod; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsms.lod IS 'CityGML representation level of detail, 0-4: 0 = 2D footprint, 1 = 2.5D height/root depth, 2 = crown + trunk as separable volumes, 3 = 3D morphological structure, 4 = internal detail plus structured semantics. This is the ONLY meaning of "LoD" in this database. It is not a rendering resolution and not a count of which parts exist -- for those see the render-resolution and structural-detail axes in docs/level-of-detail-vocabulary.md (XRFF-404).';


--
-- Name: COLUMN qsms.local_crs; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsms.local_crs IS 'CRS of the cylinder coordinates in trees.qsmcylinders, or the literal value ''local'' if none';


--
-- Name: COLUMN qsms.origin_position; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsms.origin_position IS 'Georeferences the local cylinder coordinate frame';


--
-- Name: COLUMN qsms.total_volume_m3; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsms.total_volume_m3 IS 'QSM-derived total volume -- kept separate from the allometric trees.trees.volume_m3';


--
-- Name: COLUMN qsms.dbh_qsm_cm; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsms.dbh_qsm_cm IS 'DBH as derived from the QSM -- kept separate from trees.stems.dbh_cm to allow validating one against the other';


--
-- Name: COLUMN qsms.is_corrected; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsms.is_corrected IS 'Raw TreeQSM (false) vs Real Twig radius-corrected (true)';


--
-- Name: qsms; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.qsms WITH (security_invoker='on') AS
 SELECT qsms.qsm_id,
    qsms.tree_entity_id,
    qsms.tree_id,
    qsms.point_cloud_id,
    qsms.process_id,
    qsms.lod,
    qsms.local_crs,
    qsms.origin_position,
    qsms.cylinder_count,
    qsms.total_volume_m3,
    qsms.trunk_volume_m3,
    qsms.branch_volume_m3,
    qsms.dbh_qsm_cm,
    qsms.height_qsm_m,
    qsms.crown_area_qsm_m2,
    qsms.is_corrected,
    qsms.created_at,
    qsms.created_by
   FROM trees.qsms;


ALTER TABLE public.qsms OWNER TO supabase_admin;

--
-- Name: VIEW qsms; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.qsms IS 'Public API view for QSM reconstructions';


--
-- Name: regeneration; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.regeneration WITH (security_invoker='on') AS
 SELECT regeneration.regeneration_id,
    regeneration.location_id,
    regeneration.plot_id,
    regeneration.campaign_id,
    regeneration.species_id,
    regeneration.size_class,
    regeneration.live_count,
    regeneration.dead_count,
    regeneration.mean_height_m,
    regeneration."position",
    regeneration.measurement_date,
    regeneration.source_regeneration_id,
    regeneration.source_attributes,
    regeneration.notes,
    regeneration.created_at,
    regeneration.updated_at,
    regeneration.created_by,
    regeneration.updated_by,
    regeneration.survey_area_m2
   FROM forest_floor.regeneration;


ALTER TABLE public.regeneration OWNER TO supabase_admin;

--
-- Name: VIEW regeneration; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.regeneration IS 'Regeneration tallies: live and dead counts per species and size class on a plot or subplot. Writable by contributors.';


--
-- Name: regeneration_per_ha; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.regeneration_per_ha WITH (security_invoker='on') AS
 SELECT r.regeneration_id,
    r.location_id,
    r.plot_id,
    r.campaign_id,
    r.species_id,
    sp.scientific_name,
    r.size_class,
    r.live_count,
    r.dead_count,
    r.mean_height_m,
    COALESCE(r.survey_area_m2, pi.area_m2) AS survey_area_m2,
    round((((r.live_count)::numeric * 10000.0) / COALESCE(r.survey_area_m2, pi.area_m2)), 2) AS live_per_ha,
    round((((r.dead_count)::numeric * 10000.0) / COALESCE(r.survey_area_m2, pi.area_m2)), 2) AS dead_per_ha,
    r.measurement_date
   FROM ((forest_floor.regeneration r
     LEFT JOIN shared.species sp ON ((sp.species_id = r.species_id)))
     LEFT JOIN shared.plot_inclusion pi ON ((pi.plot_id = r.plot_id)));


ALTER TABLE public.regeneration_per_ha OWNER TO supabase_admin;

--
-- Name: VIEW regeneration_per_ha; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.regeneration_per_ha IS 'Regeneration per hectare: each tally''s counts divided by its survey area (survey_area_m2, else the plot''s area_m2 or the nearest enclosing plot''s). NULL per-hectare values where no area is known.';


--
-- Name: root_system_types; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.root_system_types (
    root_system_type_id smallint NOT NULL,
    root_system_type_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_root_system_type_name CHECK (((root_system_type_name)::text = ANY (ARRAY[('tap_root'::character varying)::text, ('heart_root'::character varying)::text, ('lateral_root'::character varying)::text])))
);


ALTER TABLE trees.root_system_types OWNER TO supabase_admin;

--
-- Name: TABLE root_system_types; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.root_system_types IS 'Root system morphology lookup (Koestler et al. 1968 classification; Guerrero Inigez 2017 LoD-matched geometric models)';


--
-- Name: root_system_types; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.root_system_types WITH (security_invoker='on') AS
 SELECT root_system_types.root_system_type_id,
    root_system_types.root_system_type_name,
    root_system_types.description
   FROM trees.root_system_types;


ALTER TABLE public.root_system_types OWNER TO supabase_admin;

--
-- Name: VIEW root_system_types; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.root_system_types IS 'Public API view for root system types lookup table';


--
-- Name: roots; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.roots (
    root_id bigint NOT NULL,
    tree_entity_id uuid NOT NULL,
    tree_id integer NOT NULL,
    root_system_type_id smallint NOT NULL,
    lod smallint,
    geometry_class text,
    root_depth_m numeric(6,2),
    root_spread_radius_m numeric(6,2),
    process_id integer,
    source text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT roots_geometry_class_check CHECK (((geometry_class IS NULL) OR (geometry_class = ANY (ARRAY['implicit'::text, 'explicit'::text])))),
    CONSTRAINT roots_lod_check CHECK (((lod >= 0) AND (lod <= 4))),
    CONSTRAINT roots_root_depth_m_check CHECK ((root_depth_m >= (0)::numeric)),
    CONSTRAINT roots_root_spread_radius_m_check CHECK ((root_spread_radius_m >= (0)::numeric)),
    CONSTRAINT roots_source_check CHECK ((source = ANY (ARRAY['species_default'::text, 'field_observed'::text, 'measured'::text])))
);


ALTER TABLE trees.roots OWNER TO supabase_admin;

--
-- Name: TABLE roots; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.roots IS 'Root system classification/geometry (Guerrero Inigez 2017 LoD-matched models) -- classifiable from species now, geometrized later';


--
-- Name: COLUMN roots.tree_entity_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.roots.tree_entity_id IS 'Stable physical-tree identity (trees.trees.tree_entity_id)';


--
-- Name: COLUMN roots.lod; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.roots.lod IS 'CityGML representation level of detail, 0-4; same ladder as trees.qsms.lod. Read together with geometry_class: implicit = a prototype instanced with a transform (a generic asset placed on this tree), explicit = this tree''s own geometry. The number alone cannot tell those apart. See docs/level-of-detail-vocabulary.md (XRFF-404).';


--
-- Name: COLUMN roots.geometry_class; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.roots.geometry_class IS 'implicit = prototype instanced with a transform, so LoD2-LoD3 at best; explicit = this tree''s own measured geometry, which is what qualifies a row as LoD4. Always interpreted alongside lod, never on its own. See docs/citygml-qsm-mapping.md §5.';


--
-- Name: COLUMN roots.source; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.roots.source IS 'species_default = classified from silvics literature, no measurement; field_observed = seen but not measured; measured = geometry actually captured';


--
-- Name: roots; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.roots WITH (security_invoker='on') AS
 SELECT roots.root_id,
    roots.tree_entity_id,
    roots.tree_id,
    roots.root_system_type_id,
    roots.lod,
    roots.geometry_class,
    roots.root_depth_m,
    roots.root_spread_radius_m,
    roots.process_id,
    roots.source,
    roots.created_at,
    roots.created_by
   FROM trees.roots;


ALTER TABLE public.roots OWNER TO supabase_admin;

--
-- Name: VIEW roots; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.roots IS 'Public API view for root system classification/geometry';


--
-- Name: sampling_designs; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.sampling_designs WITH (security_invoker='on') AS
 SELECT sampling_designs.sampling_design_id,
    sampling_designs.design_name,
    sampling_designs.strategy,
    sampling_designs.protocol_name,
    sampling_designs.protocol_version,
    sampling_designs.dbh_measuring_height_m,
    sampling_designs.min_dbh_cm,
    sampling_designs.reporting_area_ha,
    sampling_designs.description,
    sampling_designs.created_at,
    sampling_designs.updated_at,
    sampling_designs.created_by,
    sampling_designs.updated_by
   FROM shared.sampling_designs;


ALTER TABLE public.sampling_designs OWNER TO supabase_admin;

--
-- Name: VIEW sampling_designs; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.sampling_designs IS 'Sampling designs (inventory protocols). Readable by everyone; contributors write.';


--
-- Name: scenarios; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.scenarios WITH (security_invoker='on') AS
 SELECT scenarios.scenario_id,
    scenarios.scenario_name,
    scenarios.description,
    scenarios.created_at,
    scenarios.updated_at,
    scenarios.location_id,
    scenarios.management_regime_id,
    scenarios.climate_pathway_id,
    scenarios.scenario_code
   FROM shared.scenarios;


ALTER TABLE public.scenarios OWNER TO supabase_admin;

--
-- Name: VIEW scenarios; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.scenarios IS 'Public API view: location-scoped scenarios (Location -> Scenario -> Variant), each a (management regime, climate pathway) pair with scenario_code = regime*10 + pathway. Insertable; omit the axis ids and they are derived from a conforming scenario_name. For names alongside ids use ue_scenarios.';


--
-- Name: sensor_readings; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.sensor_readings WITH (security_invoker='on') AS
 SELECT sensor_readings.sensor_reading_id,
    sensor_readings.sensor_id,
    sensor_readings."timestamp",
    sensor_readings.value,
    sensor_readings.quality,
    sensor_readings.scenario_id,
    sensor_readings.battery_voltage_v,
    sensor_readings.signal_strength,
    sensor_readings.notes,
    sensor_readings.created_at
   FROM sensor.sensor_readings;


ALTER TABLE public.sensor_readings OWNER TO supabase_admin;

--
-- Name: VIEW sensor_readings; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.sensor_readings IS 'Public API view for sensor readings table';


--
-- Name: sensor_tree_links; Type: TABLE; Schema: sensor; Owner: supabase_admin
--

CREATE TABLE sensor.sensor_tree_links (
    sensor_tree_link_id integer NOT NULL,
    sensor_id integer NOT NULL,
    tree_id integer NOT NULL,
    description text,
    start_date date,
    end_date date,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE sensor.sensor_tree_links OWNER TO supabase_admin;

--
-- Name: TABLE sensor_tree_links; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON TABLE sensor.sensor_tree_links IS 'Links sensors to specific tree records';


--
-- Name: COLUMN sensor_tree_links.sensor_tree_link_id; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON COLUMN sensor.sensor_tree_links.sensor_tree_link_id IS 'Surrogate key. Renamed from sensortreelinkid in XRFF-488 -- it was the only primary key in the database not spelled <stem>_id.';


--
-- Name: sensor_tree_links; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.sensor_tree_links WITH (security_invoker='on') AS
 SELECT sensor_tree_links.sensor_tree_link_id,
    sensor_tree_links.sensor_id,
    sensor_tree_links.tree_id,
    sensor_tree_links.description,
    sensor_tree_links.start_date,
    sensor_tree_links.end_date,
    sensor_tree_links.created_at
   FROM sensor.sensor_tree_links;


ALTER TABLE public.sensor_tree_links OWNER TO supabase_admin;

--
-- Name: VIEW sensor_tree_links; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.sensor_tree_links IS 'Public API view for sensor-tree link table';


--
-- Name: sensor_types; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.sensor_types WITH (security_invoker='on') AS
 SELECT sensor_types.sensor_type_id,
    sensor_types.sensor_type_name,
    sensor_types.description,
    sensor_types.typical_unit,
    sensor_types.typical_range_min,
    sensor_types.typical_range_max
   FROM sensor.sensor_types;


ALTER TABLE public.sensor_types OWNER TO supabase_admin;

--
-- Name: VIEW sensor_types; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.sensor_types IS 'Public API view for sensor types reference table';


--
-- Name: sensors; Type: VIEW; Schema: public; Owner: supabase_admin
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


ALTER TABLE public.sensors OWNER TO supabase_admin;

--
-- Name: VIEW sensors; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.sensors IS 'Public API view for sensors table';


--
-- Name: shoot_elongation_types; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.shoot_elongation_types (
    shoot_elongation_type_id integer NOT NULL,
    shoot_elongation_type_name character varying(50) NOT NULL,
    description text
);


ALTER TABLE trees.shoot_elongation_types OWNER TO supabase_admin;

--
-- Name: TABLE shoot_elongation_types; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.shoot_elongation_types IS 'Shoot elongation classification (long, short, spur shoots)';


--
-- Name: shoot_elongation_types; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.shoot_elongation_types AS
 SELECT shoot_elongation_types.shoot_elongation_type_id,
    shoot_elongation_types.shoot_elongation_type_name,
    shoot_elongation_types.description
   FROM trees.shoot_elongation_types;


ALTER TABLE public.shoot_elongation_types OWNER TO supabase_admin;

--
-- Name: VIEW shoot_elongation_types; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.shoot_elongation_types IS 'Public API view for shoot elongation types lookup table';


--
-- Name: variants; Type: TABLE; Schema: shared; Owner: supabase_admin
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


ALTER TABLE shared.variants OWNER TO supabase_admin;

--
-- Name: TABLE variants; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.variants IS 'Forest state snapshots — each row is one time step at one location within one scenario. variant_id groups all trees at that state. Use for UE time-travel switching.';


--
-- Name: COLUMN variants.location_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.variants.location_id IS 'The forest site this variant belongs to — top level of the Location → Scenario → Variant hierarchy';


--
-- Name: COLUMN variants.scenario_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.variants.scenario_id IS 'The scenario (set of assumptions) this variant belongs to';


--
-- Name: COLUMN variants.variant_type_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.variants.variant_type_id IS 'Type of data in this variant (original field measurement, simulated growth, etc.)';


--
-- Name: COLUMN variants.simulation_year; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.variants.simulation_year IS 'Calendar year this forest state represents';


--
-- Name: COLUMN variants.time_delta_yrs; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.variants.time_delta_yrs IS 'Years elapsed from the scenario baseline';


--
-- Name: COLUMN variants.sort_order; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.variants.sort_order IS 'Display order for time-slider UI in UE (0=earliest)';


--
-- Name: COLUMN variants.parent_variant_id; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.variants.parent_variant_id IS 'The variant this state developed from (baseline has none). Encodes the timeline/intervention lineage within a scenario.';


--
-- Name: simulation_runs; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.simulation_runs (
    simulation_run_id uuid NOT NULL,
    location_id integer NOT NULL,
    scenario_id integer,
    base_variant_id integer,
    base_year integer,
    simulator_name character varying(100) NOT NULL,
    simulator_version character varying(50),
    process_id integer,
    horizon_years integer,
    seed integer,
    is_mortality_enabled boolean,
    is_promoted boolean,
    run_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(200),
    CONSTRAINT simulation_runs_base_year_check CHECK (((base_year IS NULL) OR ((base_year >= 1900) AND (base_year <= 2300)))),
    CONSTRAINT simulation_runs_horizon_years_check CHECK (((horizon_years IS NULL) OR (horizon_years >= 0))),
    CONSTRAINT simulation_runs_run_params_is_object CHECK ((jsonb_typeof(run_params) = 'object'::text)),
    CONSTRAINT simulation_runs_simulator_name_check CHECK (((simulator_name)::text = ANY (ARRAY['SILVA'::text, 'FVS'::text, 'iLand'::text, 'manual'::text, 'other'::text])))
);


ALTER TABLE trees.simulation_runs OWNER TO supabase_admin;

--
-- Name: TABLE simulation_runs; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.simulation_runs IS 'One row per forest growth simulation run: what was simulated, by which simulator, and with which parameters. trees.growth_simulations holds the per-tree result rows of a run and references this table by run_id.';


--
-- Name: COLUMN simulation_runs.base_variant_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.base_variant_id IS 'shared.variants row the run was projected forward from. The reproducibility anchor: variant names are reused and deleted by --replace, so the reference is stored, not the name.';


--
-- Name: COLUMN simulation_runs.base_year; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.base_year IS 'Calendar year of the base variant (year zero). First projected year = base_year + one simulator period.';


--
-- Name: COLUMN simulation_runs.process_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.process_id IS 'shared.processes row the run registered itself under (algorithm, version, citation).';


--
-- Name: COLUMN simulation_runs.horizon_years; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.horizon_years IS 'Projection horizon in years, as requested (silva-connector: --years, a multiple of 5).';


--
-- Name: COLUMN simulation_runs.seed; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.seed IS 'Random seed. The one parameter that makes two otherwise identical runs differ, and the reason this table exists.';


--
-- Name: COLUMN simulation_runs.is_mortality_enabled; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.is_mortality_enabled IS 'True if the simulator was allowed to kill trees during the run.';


--
-- Name: COLUMN simulation_runs.is_promoted; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.is_promoted IS 'True if the run wrote the shared.variants chain UE reads when it ran. Never cleared: a later promoted run of the same location and scenario (--replace) takes the chain over, and public.simulation_runs.holds_variant_chain marks the one that holds it now. False for a comparison-only run (silva-connector --no-promote).';


--
-- Name: COLUMN simulation_runs.run_params; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.simulation_runs.run_params IS 'Simulator-specific parameters as named keys, e.g. {"competition": "sf_polygon", "variant_prefix": "silva", "replace": true}. Named parameters only -- never a command line. An absent key on a run predating 2026-09-02 means the value was not recorded, not that it was unset.';


--
-- Name: simulation_runs; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.simulation_runs WITH (security_invoker='on') AS
 SELECT r.simulation_run_id,
    r.simulator_name,
    r.simulator_version,
    s.scenario_name,
    l.location_name,
    agg.first_year,
    agg.last_year,
    agg.year_steps,
    agg.tree_count,
    r.created_at,
    (r.created_by)::text AS created_by,
    r.base_year,
    r.horizon_years,
    bv.variant_name AS base_variant_name,
    r.seed,
    r.is_mortality_enabled,
    r.is_promoted,
    r.run_params,
    (r.is_promoted AND (NOT (EXISTS ( SELECT 1
           FROM trees.simulation_runs newer
          WHERE (newer.is_promoted AND (newer.location_id = r.location_id) AND (newer.scenario_id = r.scenario_id) AND (newer.created_at > r.created_at)))))) AS holds_variant_chain
   FROM ((((trees.simulation_runs r
     LEFT JOIN shared.scenarios s ON ((s.scenario_id = r.scenario_id)))
     LEFT JOIN shared.locations l ON ((l.location_id = r.location_id)))
     LEFT JOIN shared.variants bv ON ((bv.variant_id = r.base_variant_id)))
     LEFT JOIN LATERAL ( SELECT min(gs.projection_year) AS first_year,
            max(gs.projection_year) AS last_year,
            count(DISTINCT gs.projection_year) AS year_steps,
            count(DISTINCT gs.tree_entity_id) AS tree_count
           FROM trees.growth_simulations gs
          WHERE (gs.simulation_run_id = r.simulation_run_id)) agg ON (true));


ALTER TABLE public.simulation_runs OWNER TO supabase_admin;

--
-- Name: VIEW simulation_runs; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.simulation_runs IS 'One row per growth simulation run: identity, configuration and the size of the trajectory it produced. Backed by trees.simulation_runs; counts aggregated from trees.growth_simulations.';


--
-- Name: species; Type: VIEW; Schema: public; Owner: supabase_admin
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


ALTER TABLE public.species OWNER TO supabase_admin;

--
-- Name: VIEW species; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.species IS 'Public API view for tree species reference table';


--
-- Name: stand_summaries; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.stand_summaries WITH (security_invoker='on') AS
 WITH pairs AS (
         SELECT DISTINCT p.sampling_design_id,
            v_1.variant_id
           FROM (shared.variants v_1
             JOIN shared.plots p ON ((p.location_id = v_1.location_id)))
          WHERE (p.sampling_design_id IS NOT NULL)
        )
 SELECT pr.variant_id,
    v.variant_name,
    v.simulation_year,
    v.location_id,
    l.location_name,
    v.scenario_id,
    sc.scenario_name,
    pr.sampling_design_id,
    d.design_name,
    d.strategy,
    e.by_species,
    e.species_id,
    sp.scientific_name AS species_name,
    e.variable,
    e.unit,
    e.estimate,
    e.standard_error,
    e.relative_standard_error_pct,
    e.margin_of_error,
    e.sampling_error_pct,
    e.ci_low,
    e.ci_high,
    e.confidence,
    e.n_units,
    e.area_ha,
    e.total,
    e.total_standard_error,
    e.method
   FROM ((((((pairs pr
     JOIN shared.variants v ON ((v.variant_id = pr.variant_id)))
     JOIN shared.locations l ON ((l.location_id = v.location_id)))
     LEFT JOIN shared.scenarios sc ON ((sc.scenario_id = v.scenario_id)))
     JOIN shared.sampling_designs d ON ((d.sampling_design_id = pr.sampling_design_id)))
     CROSS JOIN LATERAL shared.estimate_stand_domains(pr.sampling_design_id, pr.variant_id, true, true, 0.95) e(sampling_design_id, variant_id, by_species, species_id, variable, unit, estimate, standard_error, relative_standard_error_pct, margin_of_error, sampling_error_pct, ci_low, ci_high, confidence, n_units, area_ha, total, total_standard_error, method))
     LEFT JOIN shared.species sp ON ((sp.species_id = e.species_id)))
  WHERE (e.n_units > 0);


ALTER TABLE public.stand_summaries OWNER TO supabase_admin;

--
-- Name: VIEW stand_summaries; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.stand_summaries IS 'Per-hectare stand values of every variant for each sampling design of its site, all species (by_species false) and per species: estimate, standard error, relative standard error %, margin of error and sampling error % at 95 %, confidence interval, units, area and total. Census designs have no sampling error. Filter on variant_id; other confidence levels via /rpc/estimate_stand.';


--
-- Name: stems; Type: VIEW; Schema: public; Owner: supabase_admin
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
    stems.updated_at,
    stems.dbh_measuring_height_m
   FROM trees.stems;


ALTER TABLE public.stems OWNER TO supabase_admin;

--
-- Name: VIEW stems; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.stems IS 'Public API view for tree stems table';


--
-- Name: strata; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.strata (
    stratum_id integer NOT NULL,
    sampling_design_id integer NOT NULL,
    stratum_name character varying(200) NOT NULL,
    area_ha numeric(14,4),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    updated_by character varying(200),
    CONSTRAINT strata_area_ha_check CHECK ((area_ha > (0)::numeric))
);


ALTER TABLE shared.strata OWNER TO supabase_admin;

--
-- Name: TABLE strata; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.strata IS 'Strata of a stratified sampling design, with their area. A plot''s stratum must belong to the plot''s design.';


--
-- Name: COLUMN strata.area_ha; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.strata.area_ha IS 'Stratum area in hectares; stratified estimators weight by it.';


--
-- Name: strata; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.strata WITH (security_invoker='on') AS
 SELECT strata.stratum_id,
    strata.sampling_design_id,
    strata.stratum_name,
    strata.area_ha,
    strata.description,
    strata.created_at,
    strata.updated_at,
    strata.created_by,
    strata.updated_by
   FROM shared.strata;


ALTER TABLE public.strata OWNER TO supabase_admin;

--
-- Name: VIEW strata; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.strata IS 'Strata of stratified sampling designs, with area.';


--
-- Name: teams; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.teams (
    team_id integer NOT NULL,
    team_name character varying(200) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    updated_by character varying(200)
);


ALTER TABLE shared.teams OWNER TO supabase_admin;

--
-- Name: TABLE teams; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.teams IS 'A group that owns datasets (campaigns). Members see their team''s campaigns at every access level and during an embargo; team curators manage the membership.';


--
-- Name: teams; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.teams WITH (security_invoker='on') AS
 SELECT teams.team_id,
    teams.team_name,
    teams.description,
    teams.created_at,
    teams.updated_at,
    teams.created_by,
    teams.updated_by
   FROM shared.teams;


ALTER TABLE public.teams OWNER TO supabase_admin;

--
-- Name: VIEW teams; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.teams IS 'Teams that own datasets. Readable by everyone; curators create and change them.';


--
-- Name: tree_expansion_factors; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.tree_expansion_factors WITH (security_invoker='on') AS
 SELECT t.tree_id,
    t.tree_entity_id,
    t.variant_id,
    t.location_id,
    t.plot_id,
    p.sampling_design_id,
    p.stratum_id,
    p.sampling_weight,
    s.dbh_cm,
        CASE
            WHEN (pi.plot_id IS NOT NULL) THEN shared.ef_value(pi.has_rules, (ir.rule_type)::text, ir.radius_m, ir.basal_area_factor_m2ha, pi.area_m2, pi.min_dbh_cm, s.dbh_cm)
            ELSE NULL::numeric
        END AS expansion_factor_ha
   FROM ((((trees.trees t
     LEFT JOIN shared.plots p ON ((p.plot_id = t.plot_id)))
     LEFT JOIN shared.plot_inclusion pi ON ((pi.plot_id = t.plot_id)))
     LEFT JOIN trees.stems s ON (((s.tree_id = t.tree_id) AND (s.stem_number = 1))))
     LEFT JOIN shared.inclusion_rules ir ON (((ir.sampling_design_id = pi.sampling_design_id) AND (s.dbh_cm >= ir.min_dbh_cm) AND ((ir.max_dbh_cm IS NULL) OR (s.dbh_cm < ir.max_dbh_cm)) AND (s.dbh_cm > (0)::numeric))));


ALTER TABLE public.tree_expansion_factors OWNER TO supabase_admin;

--
-- Name: VIEW tree_expansion_factors; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.tree_expansion_factors IS 'Trees per hectare each tree stands for (shared.expansion_factor_ha on the main stem''s DBH), with the plot''s design, stratum and sampling weight. Filter on variant_id. NULL where the plot has no area or design.';


--
-- Name: tree_graph_edges; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.tree_graph_edges (
    tree_graph_edge_id bigint NOT NULL,
    qsm_id bigint NOT NULL,
    from_cylinder_index integer NOT NULL,
    to_cylinder_index integer NOT NULL,
    edge_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT tree_graph_edges_edge_type_check CHECK ((edge_type = ANY (ARRAY['observed'::text, 'synthetic'::text, 'derived'::text])))
);


ALTER TABLE trees.tree_graph_edges OWNER TO supabase_admin;

--
-- Name: TABLE tree_graph_edges; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.tree_graph_edges IS 'QSM topology edges whose type deviates from the trees.qsmcylinders parent-chain default (''observed''); see this migration''s header for the observed/synthetic/derived distinction';


--
-- Name: COLUMN tree_graph_edges.from_cylinder_index; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.tree_graph_edges.from_cylinder_index IS 'Parent cylinder_index -- the CityGML Edge''s first Node';


--
-- Name: COLUMN tree_graph_edges.to_cylinder_index; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.tree_graph_edges.to_cylinder_index IS 'Child cylinder_index -- the CityGML Edge''s second Node';


--
-- Name: COLUMN tree_graph_edges.edge_type; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.tree_graph_edges.edge_type IS 'observed = measured by the source; synthetic = the source itself flagged this as inferred; derived = we added/overrode it ourselves';


--
-- Name: tree_graph_edges; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.tree_graph_edges WITH (security_invoker='on') AS
 SELECT tree_graph_edges.tree_graph_edge_id,
    tree_graph_edges.qsm_id,
    tree_graph_edges.from_cylinder_index,
    tree_graph_edges.to_cylinder_index,
    tree_graph_edges.edge_type,
    tree_graph_edges.created_at
   FROM trees.tree_graph_edges;


ALTER TABLE public.tree_graph_edges OWNER TO supabase_admin;

--
-- Name: VIEW tree_graph_edges; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.tree_graph_edges IS 'Public API view for QSM topology edge overrides (observed/synthetic/derived)';


--
-- Name: tree_part_types; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.tree_part_types (
    part_type_id smallint NOT NULL,
    part_type_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_part_type_name CHECK (((part_type_name)::text = ANY (ARRAY[('root'::character varying)::text, ('trunk'::character varying)::text, ('branch'::character varying)::text, ('twig'::character varying)::text, ('leaf'::character varying)::text, ('crown'::character varying)::text])))
);


ALTER TABLE trees.tree_part_types OWNER TO supabase_admin;

--
-- Name: TABLE tree_part_types; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.tree_part_types IS 'CityGML tree feature-class lookup (Ambarwari et al. 2024) -- join point for a future CityGML ADE';


--
-- Name: tree_part_types; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.tree_part_types WITH (security_invoker='on') AS
 SELECT tree_part_types.part_type_id,
    tree_part_types.part_type_name,
    tree_part_types.description
   FROM trees.tree_part_types;


ALTER TABLE public.tree_part_types OWNER TO supabase_admin;

--
-- Name: VIEW tree_part_types; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.tree_part_types IS 'Public API view for tree part types (CityGML feature classes) lookup table';


--
-- Name: trees; Type: VIEW; Schema: public; Owner: supabase_admin
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
    trees.geometric_crown_solid_id,
    trees.axis_structure_id,
    trees.growth_form_id,
    trees.live_crown_ratio,
    trees.crown_class_id,
    trees.damage_agent_id,
    trees.defoliation_percent,
    trees.discolouration_percent,
    trees.crown_transparency_percent,
    trees.source_tree_id,
    trees.source_attributes
   FROM trees.trees;


ALTER TABLE public.trees OWNER TO supabase_admin;

--
-- Name: VIEW trees; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.trees IS 'Public API view for trees table';


--
-- Name: ue_climate; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_climate WITH (security_invoker='on') AS
 SELECT e.location_id,
    max((l.location_name)::text) AS location_name,
    e.scenario_id,
    max((s.scenario_name)::text) AS scenario_name,
    e.variant_type_id,
    max((vt.variant_type_name)::text) AS variant_type_name,
    e.start_date,
    e.end_date,
    (EXTRACT(year FROM e.start_date))::integer AS start_year,
    (EXTRACT(year FROM e.end_date))::integer AS end_year,
    max(e.avg_temperature_c) AS avg_temperature_c,
    max(e.avg_humidity_percent) AS avg_humidity_percent,
    max(e.total_precipitation_mm) AS total_precipitation_mm,
    max(e.avg_global_radiation_w_m2) AS avg_global_radiation_w_m2,
    max(e.avg_co2_ppm) AS avg_co2_ppm,
    max(e.avg_wind_speed_ms) AS avg_wind_speed_ms,
    max(e.dominant_wind_direction_deg) AS dominant_wind_direction_deg,
    max(e.avg_soil_moisture_percent) AS avg_soil_moisture_percent,
    max(e.avg_soil_temperature_c) AS avg_soil_temperature_c,
    max(e.soil_ph) AS soil_ph,
    max(e.nutrient_nitrogen_mg_kg) AS nutrient_nitrogen_mg_kg,
    max(e.nutrient_phosphorus_mg_kg) AS nutrient_phosphorus_mg_kg,
    max(e.nutrient_potassium_mg_kg) AS nutrient_potassium_mg_kg,
    max(e.stress_factor) AS stress_factor,
    array_agg(DISTINCT e.variant_name ORDER BY e.variant_name) AS variant_names,
    array_agg(DISTINCT p.process_name ORDER BY p.process_name) FILTER (WHERE (p.process_name IS NOT NULL)) AS process_names,
    (count(*))::integer AS row_count,
    array_remove(ARRAY[
        CASE
            WHEN (count(e.avg_temperature_c) > 1) THEN 'avg_temperature_c'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.avg_humidity_percent) > 1) THEN 'avg_humidity_percent'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.total_precipitation_mm) > 1) THEN 'total_precipitation_mm'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.avg_global_radiation_w_m2) > 1) THEN 'avg_global_radiation_w_m2'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.avg_co2_ppm) > 1) THEN 'avg_co2_ppm'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.avg_wind_speed_ms) > 1) THEN 'avg_wind_speed_ms'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.dominant_wind_direction_deg) > 1) THEN 'dominant_wind_direction_deg'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.avg_soil_moisture_percent) > 1) THEN 'avg_soil_moisture_percent'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.avg_soil_temperature_c) > 1) THEN 'avg_soil_temperature_c'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.soil_ph) > 1) THEN 'soil_ph'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.nutrient_nitrogen_mg_kg) > 1) THEN 'nutrient_nitrogen_mg_kg'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.nutrient_phosphorus_mg_kg) > 1) THEN 'nutrient_phosphorus_mg_kg'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.nutrient_potassium_mg_kg) > 1) THEN 'nutrient_potassium_mg_kg'::text
            ELSE NULL::text
        END,
        CASE
            WHEN (count(e.stress_factor) > 1) THEN 'stress_factor'::text
            ELSE NULL::text
        END], NULL::text) AS conflicting_columns
   FROM ((((environments.environments e
     JOIN shared.locations l ON ((l.location_id = e.location_id)))
     LEFT JOIN shared.scenarios s ON ((s.scenario_id = e.scenario_id)))
     LEFT JOIN shared.variant_types vt ON ((vt.variant_type_id = e.variant_type_id)))
     LEFT JOIN shared.processes p ON ((p.process_id = e.process_id)))
  GROUP BY e.location_id, e.scenario_id, e.variant_type_id, e.start_date, e.end_date;


ALTER TABLE public.ue_climate OWNER TO supabase_admin;

--
-- Name: VIEW ue_climate; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_climate IS 'environments.environments merged across variant_name: one row per location, scenario, variant type and period, with each measurement column taken from whichever dataset supplied it. This is the read a scene makes -- ue_environments returns one row per dataset, which since XRFF-395 means two half-empty rows per window where a scenario picker wants one full one. `variant_names` and `process_names` carry the provenance the merge folds away; `conflicting_columns` is empty unless two datasets supplied the same measurement for the same window, in which case the value shown is an arbitrary one of them. Despite the name it also returns the scenario-less rows -- soil chemistry (both years NULL) and the measured soil aggregate -- because the grouping is by period, not by topic. GET /rest/v1/ue_climate?location_id=eq.1&scenario_name=eq.ssp370&order=start_year';


--
-- Name: ue_environments; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_environments WITH (security_invoker='on') AS
 SELECT e.environment_id,
    e.location_id,
    l.location_name,
    e.scenario_id,
    s.scenario_name,
    e.variant_type_id,
    vt.variant_type_name,
    e.variant_name,
    e.start_date,
    e.end_date,
    (EXTRACT(year FROM e.start_date))::integer AS start_year,
    (EXTRACT(year FROM e.end_date))::integer AS end_year,
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
    e.process_id,
    p.process_name,
    p.version AS process_version,
    p.citation AS process_citation
   FROM ((((environments.environments e
     JOIN shared.locations l ON ((l.location_id = e.location_id)))
     LEFT JOIN shared.scenarios s ON ((s.scenario_id = e.scenario_id)))
     LEFT JOIN shared.variant_types vt ON ((vt.variant_type_id = e.variant_type_id)))
     LEFT JOIN shared.processes p ON ((p.process_id = e.process_id)));


ALTER TABLE public.ue_environments OWNER TO supabase_admin;

--
-- Name: VIEW ue_environments; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_environments IS 'environments.environments with its location, scenario, variant type and process joined to text, for Unreal. Every column is a scalar and the period is exposed as integer years as well as timestamps. A NULL scenario_name means the row is not a projection (an observed climatology or a permanent site property), not that a pathway is missing -- variant_name says which dataset it is. GET /rest/v1/ue_environments?location_id=eq.1&scenario_name=eq.ssp370&order=start_year';


--
-- Name: ue_scenarios; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_scenarios WITH (security_invoker='on') AS
 SELECT s.scenario_id,
    s.location_id,
    l.location_name,
    s.scenario_name,
    s.scenario_code,
    s.management_regime_id,
    mr.management_regime_name,
    s.climate_pathway_id,
    cp.climate_pathway_name,
    cp.label AS climate_pathway_label,
    s.description,
    agg.variant_count,
    agg.first_year,
    agg.last_year,
    (COALESCE(agg.variant_count, 0) > 0) AS has_trees,
    bl.baseline_variant_id,
    bv.simulation_year AS baseline_year
   FROM ((((((shared.scenarios s
     JOIN shared.locations l ON ((l.location_id = s.location_id)))
     LEFT JOIN shared.management_regimes mr ON ((mr.management_regime_id = s.management_regime_id)))
     LEFT JOIN shared.climate_pathways cp ON ((cp.climate_pathway_id = s.climate_pathway_id)))
     LEFT JOIN LATERAL ( SELECT (count(*))::integer AS variant_count,
            min(v.simulation_year) AS first_year,
            max(v.simulation_year) AS last_year
           FROM shared.variants v
          WHERE ((v.scenario_id = s.scenario_id) AND (EXISTS ( SELECT 1
                   FROM trees.trees t
                  WHERE (t.variant_id = v.variant_id))))) agg ON (true))
     LEFT JOIN LATERAL ( SELECT COALESCE(v.parent_variant_id, v.variant_id) AS baseline_variant_id
           FROM shared.variants v
          WHERE (v.scenario_id = s.scenario_id)
          ORDER BY v.sort_order, v.simulation_year
         LIMIT 1) bl ON (true))
     LEFT JOIN shared.variants bv ON ((bv.variant_id = bl.baseline_variant_id)));


ALTER TABLE public.ue_scenarios OWNER TO supabase_admin;

--
-- Name: VIEW ue_scenarios; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_scenarios IS 'Scenario picker for Unreal: every scenario with its numeric code and text axes, how many tree-holding variants it has and the years they span, and baseline_variant_id -- the measured state (in natural_growth) its chain was projected from, so a picker can offer the base year in every scenario. has_trees=false rows are climate-data buckets. GET /rest/v1/ue_scenarios?location_id=eq.1&has_trees=eq.true&order=scenario_code';


--
-- Name: ue_sensors; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_sensors WITH (security_invoker='on') AS
 SELECT s.sensor_id,
    s.source,
    s.external_id,
    s.serial_number AS sensor_serial_number,
    (s.external_metadata ->> 'Parameter'::text) AS parameter,
    st.sensor_type_id,
    st.sensor_type_name,
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
    t.tree_id,
    t.tree_entity_id,
    sp.common_name AS linked_tree_species_name,
    sp.scientific_name AS linked_tree_scientific_name,
    t.height_m AS linked_tree_height_m,
    extensions.st_y(s."position") AS latitude,
    extensions.st_x(s."position") AS longitude,
    (EXTRACT(epoch FROM lr."timestamp"))::bigint AS latest_timestamp_unix,
    "substring"((s.serial_number)::text, '^(?:Beech|DouglasFir|SilverFir)_(?:Pure|Mixed)_[0-9]+_(stem|middle|edge)_[NESW]$'::text) AS placement_ring,
        CASE
            WHEN ((s.serial_number)::text ~ '^(?:Beech|DouglasFir|SilverFir)_(?:Pure|Mixed)_[0-9]+_(?:stem|middle|edge)_[NESW]$'::text) THEN "right"((s.serial_number)::text, 1)
            WHEN ((s.serial_number)::text ~ '_depth[0-9]+cm_dist[0-9]+cm_[OW](?:_|$)'::text) THEN
            CASE "substring"((s.serial_number)::text, '_dist[0-9]+cm_([OW])'::text)
                WHEN 'O'::text THEN 'E'::text
                ELSE 'W'::text
            END
            WHEN ((s.serial_number)::text ~ '^SoilMoistureProfile_(?:south|west|northeast)_'::text) THEN
            CASE "substring"((s.serial_number)::text, '^SoilMoistureProfile_([a-z]+)_'::text)
                WHEN 'south'::text THEN 'S'::text
                WHEN 'west'::text THEN 'W'::text
                WHEN 'northeast'::text THEN 'NE'::text
                ELSE NULL::text
            END
            ELSE NULL::text
        END AS placement_direction,
    (COALESCE("substring"((s.serial_number)::text, '_depth([0-9]+)cm_dist[0-9]+cm_'::text), "substring"((s.serial_number)::text, '^(?:SoilPit_.+|(?:Clay|Stone|Clay_Stone|Test)_Profile)_-([0-9]+)cm$'::text), "substring"((s.serial_number)::text, '^SoilMoistureProfile_[a-z]+_([0-9]+)cm$'::text)))::integer AS placement_depth_cm,
    ("substring"((s.serial_number)::text, '_depth[0-9]+cm_dist([0-9]+)cm_'::text))::integer AS placement_distance_cm
   FROM (((((((sensor.sensors s
     JOIN sensor.sensor_types st ON ((s.sensor_type_id = st.sensor_type_id)))
     JOIN shared.locations l ON ((s.location_id = l.location_id)))
     LEFT JOIN shared.plots p ON ((s.plot_id = p.plot_id)))
     LEFT JOIN LATERAL ( SELECT sr."timestamp",
            sr.value,
            sr.quality
           FROM sensor.sensor_readings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) lr ON (true))
     LEFT JOIN sensor.sensor_tree_links stl ON ((stl.sensor_id = s.sensor_id)))
     LEFT JOIN trees.trees t ON ((stl.tree_id = t.tree_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)));


ALTER TABLE public.ue_sensors OWNER TO supabase_admin;

--
-- Name: VIEW ue_sensors; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_sensors IS 'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model (enriched instrument), data owner, location, latest reading (ISO and latest_timestamp_unix epoch seconds), linked tree info (populated after sensor_tree_links is filled), and the probe placement parsed from the label (placement_ring stem|middle|edge, placement_direction N|E|S|W|NE, placement_depth_cm, placement_distance_cm; NULL = the label carries none). GET /ue_sensors?tree_entity_id=eq.<tree_entity_id>';


--
-- Name: ue_stand_summary; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_stand_summary WITH (security_invoker='on') AS
 SELECT stand_summaries.variant_id,
    stand_summaries.variant_name,
    stand_summaries.simulation_year,
    stand_summaries.location_id,
    stand_summaries.location_name,
    stand_summaries.scenario_id,
    stand_summaries.scenario_name,
    stand_summaries.sampling_design_id,
    stand_summaries.design_name,
    stand_summaries.strategy,
    stand_summaries.by_species,
    stand_summaries.species_id,
    stand_summaries.species_name,
    stand_summaries.variable,
    stand_summaries.unit,
    stand_summaries.estimate,
    stand_summaries.standard_error,
    stand_summaries.relative_standard_error_pct,
    stand_summaries.margin_of_error,
    stand_summaries.sampling_error_pct,
    stand_summaries.ci_low,
    stand_summaries.ci_high,
    stand_summaries.confidence,
    stand_summaries.n_units,
    stand_summaries.area_ha,
    stand_summaries.total,
    stand_summaries.total_standard_error,
    stand_summaries.method
   FROM public.stand_summaries;


ALTER TABLE public.ue_stand_summary OWNER TO supabase_admin;

--
-- Name: VIEW ue_stand_summary; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_stand_summary IS 'public.stand_summaries under the ue_ prefix for Unreal: GET /ue_stand_summary?variant_id=eq.<id>&by_species=is.false';


--
-- Name: ue_trees; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_trees WITH (security_invoker='on') AS
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
    COALESCE(((t.crown_base_height_m / NULLIF(t.height_m, (0)::numeric)) > 0.6), false) AS has_competition,
    t.sensor_ref,
    (EXISTS ( SELECT 1
           FROM sensor.sensor_tree_links stl
          WHERE (stl.tree_id = t.tree_id))) AS has_sensors,
    extensions.st_x(COALESCE(t.position_original, extensions.st_transform(t."position", l.crs_epsg))) AS original_x,
    extensions.st_y(COALESCE(t.position_original, extensions.st_transform(t."position", l.crs_epsg))) AS original_y,
    COALESCE(t.source_crs,
        CASE
            WHEN ((t.position_original IS NULL) AND (t."position" IS NOT NULL)) THEN l.crs_epsg
            ELSE NULL::integer
        END) AS source_crs,
    extensions.st_y(t."position") AS latitude,
    extensions.st_x(t."position") AS longitude,
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
   FROM (((((((((((trees.trees t
     LEFT JOIN shared.locations l ON ((t.location_id = l.location_id)))
     LEFT JOIN shared.variants v ON ((t.variant_id = v.variant_id)))
     LEFT JOIN shared.scenarios s ON ((v.scenario_id = s.scenario_id)))
     LEFT JOIN shared.variant_types vt ON ((v.variant_type_id = vt.variant_type_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)))
     LEFT JOIN trees.stems st ON (((st.tree_id = t.tree_id) AND (st.stem_number = 1))))
     LEFT JOIN shared.management_regimes mr ON ((mr.management_regime_id = s.management_regime_id)))
     LEFT JOIN shared.climate_pathways cp ON ((cp.climate_pathway_id = s.climate_pathway_id)))
     LEFT JOIN trees.tree_status ts ON ((ts.tree_status_id = t.tree_status_id)))
     LEFT JOIN LATERAL ( SELECT m.campaign_id
           FROM trees.trees m
          WHERE ((t.campaign_id IS NULL) AND (m.tree_entity_id = t.tree_entity_id) AND (m.campaign_id IS NOT NULL))
          ORDER BY m.measurement_date DESC NULLS LAST, m.tree_id DESC
         LIMIT 1) src ON (true))
     LEFT JOIN shared.campaigns c ON ((c.campaign_id = COALESCE(t.campaign_id, src.campaign_id))));


ALTER TABLE public.ue_trees OWNER TO supabase_admin;

--
-- Name: VIEW ue_trees; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_trees IS 'Flat tree catalogue for UE Blueprint import. One row per tree with the location/scenario/variant hierarchy (id + name at each level), the scenario axes (scenario_code = regime*10 + pathway, management_regime, climate_pathway), the variant''s simulation_year / sort_order / time_delta_yrs, species, main-stem DBH, competition flag, tree_status (healthy | dead = standing snag, render it | harvested = gone, hide it), sensor cross-reference and projected source coordinates (original_x/original_y in source_crs, EPSG:32632 -- preferred for UE placement) plus flattened latitude/longitude. Filter by variant_id to load one time step. Pickers: ue_scenarios, ue_variants.';


--
-- Name: COLUMN ue_trees.licence; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON COLUMN public.ue_trees.licence IS 'Licence of the data behind this row: the tree''s campaign, or for a projection the campaign of the latest measurement of the same tree. NULL when neither exists.';


--
-- Name: ue_variants; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.ue_variants WITH (security_invoker='on') AS
 SELECT v.variant_id,
    v.location_id,
    l.location_name,
    v.scenario_id,
    s.scenario_name,
    s.scenario_code,
    mr.management_regime_name,
    cp.climate_pathway_name,
    v.variant_name,
    v.variant_type_id,
    vt.variant_type_name,
    v.simulation_year,
    v.time_delta_yrs,
    v.sort_order,
    v.parent_variant_id,
    v.description,
    ( SELECT (count(*))::integer AS count
           FROM trees.trees t
          WHERE (t.variant_id = v.variant_id)) AS tree_count
   FROM (((((shared.variants v
     JOIN shared.locations l ON ((l.location_id = v.location_id)))
     JOIN shared.scenarios s ON ((s.scenario_id = v.scenario_id)))
     LEFT JOIN shared.variant_types vt ON ((vt.variant_type_id = v.variant_type_id)))
     LEFT JOIN shared.management_regimes mr ON ((mr.management_regime_id = s.management_regime_id)))
     LEFT JOIN shared.climate_pathways cp ON ((cp.climate_pathway_id = s.climate_pathway_id)));


ALTER TABLE public.ue_variants OWNER TO supabase_admin;

--
-- Name: VIEW ue_variants; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.ue_variants IS 'Time-step picker for Unreal: one row per variant with simulation_year (the number), variant_name (the text), sort_order, lineage and the scenario axes. GET /rest/v1/ue_variants?location_id=eq.1&scenario_code=eq.23&order=sort_order then GET /rest/v1/ue_trees?variant_id=eq.<id>';


--
-- Name: variant_types; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.variant_types AS
 SELECT variant_types.variant_type_id,
    variant_types.variant_type_name,
    variant_types.description
   FROM shared.variant_types;


ALTER TABLE public.variant_types OWNER TO supabase_admin;

--
-- Name: VIEW variant_types; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.variant_types IS 'Public API view for data variant type classifications';


--
-- Name: variants; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.variants WITH (security_invoker='on') AS
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
    vt.variant_type_name,
    s.scenario_code,
    s.management_regime_id,
    mr.management_regime_name,
    s.climate_pathway_id,
    cp.climate_pathway_name
   FROM (((((shared.variants v
     LEFT JOIN shared.locations l ON ((v.location_id = l.location_id)))
     LEFT JOIN shared.scenarios s ON ((v.scenario_id = s.scenario_id)))
     LEFT JOIN shared.variant_types vt ON ((v.variant_type_id = vt.variant_type_id)))
     LEFT JOIN shared.management_regimes mr ON ((mr.management_regime_id = s.management_regime_id)))
     LEFT JOIN shared.climate_pathways cp ON ((cp.climate_pathway_id = s.climate_pathway_id)));


ALTER TABLE public.variants OWNER TO supabase_admin;

--
-- Name: VIEW variants; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.variants IS 'Forest-state variants with location/scenario/type names, parent_variant_id lineage and the scenario axes (scenario_code, management_regime_name, climate_pathway_name) joined. Filter by location_id+scenario_id and order by sort_order for a site+scenario timeline.';


--
-- Name: workflows; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.workflows WITH (security_invoker='on') AS
 SELECT p.workflow_key,
    p.process_name,
    p.description,
    p.category,
    p.version,
    p.param_schema
   FROM shared.processes p
  WHERE (p.workflow_key IS NOT NULL);


ALTER TABLE public.workflows OWNER TO supabase_admin;

--
-- Name: VIEW workflows; Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON VIEW public.workflows IS 'The workflows that can be requested with request_job(), one row each, with the JSON Schema of the parameters each accepts. A row here is a name and a contract only -- what it executes is defined solely in the runner private config on the host that runs it.';


--
-- Name: active_sensors_status; Type: VIEW; Schema: sensor; Owner: supabase_admin
--

CREATE VIEW sensor.active_sensors_status AS
 SELECT s.sensor_id,
    s.location_id,
    st.sensor_type_name,
    s.sensor_model,
    s.is_active,
    s.battery_level_percent,
    ( SELECT sr."timestamp"
           FROM sensor.sensor_readings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) AS last_reading_time,
    ( SELECT sr.value
           FROM sensor.sensor_readings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) AS last_reading_value,
    ( SELECT sr.quality
           FROM sensor.sensor_readings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) AS last_reading_quality
   FROM (sensor.sensors s
     JOIN sensor.sensor_types st ON ((s.sensor_type_id = st.sensor_type_id)))
  WHERE (s.is_active = true);


ALTER TABLE sensor.active_sensors_status OWNER TO supabase_admin;

--
-- Name: VIEW active_sensors_status; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON VIEW sensor.active_sensors_status IS 'Active sensors with their latest reading information';


--
-- Name: sensor_readings_sensor_reading_id_seq; Type: SEQUENCE; Schema: sensor; Owner: supabase_admin
--

CREATE SEQUENCE sensor.sensor_readings_sensor_reading_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE sensor.sensor_readings_sensor_reading_id_seq OWNER TO supabase_admin;

--
-- Name: sensor_readings_sensor_reading_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: supabase_admin
--

ALTER SEQUENCE sensor.sensor_readings_sensor_reading_id_seq OWNED BY sensor.sensor_readings.sensor_reading_id;


--
-- Name: sensor_tree_links_sensor_tree_link_id_seq; Type: SEQUENCE; Schema: sensor; Owner: supabase_admin
--

CREATE SEQUENCE sensor.sensor_tree_links_sensor_tree_link_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE sensor.sensor_tree_links_sensor_tree_link_id_seq OWNER TO supabase_admin;

--
-- Name: sensor_tree_links_sensor_tree_link_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: supabase_admin
--

ALTER SEQUENCE sensor.sensor_tree_links_sensor_tree_link_id_seq OWNED BY sensor.sensor_tree_links.sensor_tree_link_id;


--
-- Name: sensor_tree_view; Type: VIEW; Schema: sensor; Owner: supabase_admin
--

CREATE VIEW sensor.sensor_tree_view AS
 SELECT s.sensor_id,
    s.serial_number AS sensor_name,
    st.sensor_type_name,
    s.unit AS sensor_unit,
    s.is_active AS is_sensor_active,
    stl.description AS link_description,
    stl.created_at AS link_created_at,
    t.tree_id,
    sp.common_name AS tree_species_name,
    t.height_m AS tree_height_m,
    "substring"(t.field_notes, 'tree_id: [^|]+'::text) AS tree_identifier,
    "substring"(t.field_notes, 'FID: [0-9]+'::text) AS tree_fid,
    l.location_name AS tree_location_name,
    extensions.st_x(t."position") AS tree_longitude,
    extensions.st_y(t."position") AS tree_latitude
   FROM (((((sensor.sensor_tree_links stl
     JOIN sensor.sensors s ON ((stl.sensor_id = s.sensor_id)))
     JOIN sensor.sensor_types st ON ((s.sensor_type_id = st.sensor_type_id)))
     LEFT JOIN trees.trees t ON ((stl.tree_id = t.tree_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)))
     LEFT JOIN shared.locations l ON ((t.location_id = l.location_id)));


ALTER TABLE sensor.sensor_tree_view OWNER TO supabase_admin;

--
-- Name: VIEW sensor_tree_view; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON VIEW sensor.sensor_tree_view IS 'View showing relationships between sensors and trees with detailed information';


--
-- Name: sensor_types_sensor_type_id_seq; Type: SEQUENCE; Schema: sensor; Owner: supabase_admin
--

CREATE SEQUENCE sensor.sensor_types_sensor_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE sensor.sensor_types_sensor_type_id_seq OWNER TO supabase_admin;

--
-- Name: sensor_types_sensor_type_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: supabase_admin
--

ALTER SEQUENCE sensor.sensor_types_sensor_type_id_seq OWNED BY sensor.sensor_types.sensor_type_id;


--
-- Name: sensors_sensor_id_seq; Type: SEQUENCE; Schema: sensor; Owner: supabase_admin
--

CREATE SEQUENCE sensor.sensors_sensor_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE sensor.sensors_sensor_id_seq OWNER TO supabase_admin;

--
-- Name: sensors_sensor_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: supabase_admin
--

ALTER SEQUENCE sensor.sensors_sensor_id_seq OWNED BY sensor.sensors.sensor_id;


--
-- Name: units; Type: TABLE; Schema: sensor; Owner: supabase_admin
--

CREATE TABLE sensor.units (
    unit_id integer NOT NULL,
    unit_name character varying(32) NOT NULL,
    unit_display character varying(32) NOT NULL,
    description text
);


ALTER TABLE sensor.units OWNER TO supabase_admin;

--
-- Name: TABLE units; Type: COMMENT; Schema: sensor; Owner: supabase_admin
--

COMMENT ON TABLE sensor.units IS 'Canonical physical units for sensor.sensors.unit and sensor.sensor_types.typical_unit. unit_name is ASCII with _ as the divisor so it survives JSON, CSV, R and Unreal DataTable round trips; unit_display is the symbol to render.';


--
-- Name: units_unit_id_seq; Type: SEQUENCE; Schema: sensor; Owner: supabase_admin
--

CREATE SEQUENCE sensor.units_unit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE sensor.units_unit_id_seq OWNER TO supabase_admin;

--
-- Name: units_unit_id_seq; Type: SEQUENCE OWNED BY; Schema: sensor; Owner: supabase_admin
--

ALTER SEQUENCE sensor.units_unit_id_seq OWNED BY sensor.units.unit_id;


--
-- Name: account_events; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.account_events (
    account_event_id bigint NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_id uuid,
    actor_email text,
    target_email text NOT NULL,
    action text NOT NULL,
    old_role text,
    new_role text,
    team_id integer,
    CONSTRAINT account_events_action_check CHECK ((action = ANY (ARRAY['create'::text, 'set_role'::text, 'reset_password'::text, 'team_add'::text, 'team_remove'::text])))
);


ALTER TABLE shared.account_events OWNER TO supabase_admin;

--
-- Name: TABLE account_events; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.account_events IS 'Account creations, role changes and password resets made through public.create_account / set_account_role / reset_account_password. Written only by those functions; curators and admins can read it.';


--
-- Name: account_events_account_event_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.account_events ALTER COLUMN account_event_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME shared.account_events_account_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: attribute_provenance_attribute_provenance_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.attribute_provenance_attribute_provenance_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.attribute_provenance_attribute_provenance_id_seq OWNER TO supabase_admin;

--
-- Name: attribute_provenance_attribute_provenance_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.attribute_provenance_attribute_provenance_id_seq OWNED BY shared.attribute_provenance.attribute_provenance_id;


--
-- Name: audit_log; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.audit_log (
    audit_log_id bigint NOT NULL,
    field_name character varying(200) NOT NULL,
    old_value text,
    new_value text,
    change_reason text,
    user_id character varying(200),
    "timestamp" timestamp with time zone DEFAULT now(),
    change_type character varying(50),
    ip_address inet,
    user_agent text,
    CONSTRAINT audit_log_change_type_check CHECK (((change_type)::text = ANY (ARRAY[('field_update'::character varying)::text, ('bulk_update'::character varying)::text, ('revert'::character varying)::text, ('insert'::character varying)::text, ('delete'::character varying)::text])))
);


ALTER TABLE shared.audit_log OWNER TO supabase_admin;

--
-- Name: TABLE audit_log; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.audit_log IS 'Field-level change tracking with user attribution (linked via junction tables)';


--
-- Name: COLUMN audit_log.field_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.audit_log.field_name IS 'Name of the field that was changed';


--
-- Name: COLUMN audit_log.old_value; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.audit_log.old_value IS 'Previous value (stored as JSON text)';


--
-- Name: COLUMN audit_log.new_value; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.audit_log.new_value IS 'New value (stored as JSON text)';


--
-- Name: audit_log_audit_log_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.audit_log_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.audit_log_audit_log_id_seq OWNER TO supabase_admin;

--
-- Name: audit_log_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.audit_log_audit_log_id_seq OWNED BY shared.audit_log.audit_log_id;


--
-- Name: audit_log_environments; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.audit_log_environments (
    audit_log_id bigint NOT NULL,
    environment_id integer NOT NULL
);


ALTER TABLE shared.audit_log_environments OWNER TO supabase_admin;

--
-- Name: TABLE audit_log_environments; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.audit_log_environments IS 'Links audit log entries to environment records';


--
-- Name: audit_log_phenology_observations; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.audit_log_phenology_observations (
    audit_log_id bigint NOT NULL,
    phenology_observation_id integer NOT NULL
);


ALTER TABLE shared.audit_log_phenology_observations OWNER TO supabase_admin;

--
-- Name: TABLE audit_log_phenology_observations; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.audit_log_phenology_observations IS 'Links audit log entries to phenology observation records';


--
-- Name: audit_log_point_clouds; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.audit_log_point_clouds (
    audit_log_id bigint NOT NULL,
    point_cloud_id integer NOT NULL
);


ALTER TABLE shared.audit_log_point_clouds OWNER TO supabase_admin;

--
-- Name: TABLE audit_log_point_clouds; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.audit_log_point_clouds IS 'Links audit log entries to point cloud records';


--
-- Name: audit_log_stems; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.audit_log_stems (
    audit_log_id bigint NOT NULL,
    stem_id integer NOT NULL
);


ALTER TABLE shared.audit_log_stems OWNER TO supabase_admin;

--
-- Name: TABLE audit_log_stems; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.audit_log_stems IS 'Links audit log entries to individual stems';


--
-- Name: audit_log_trees; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.audit_log_trees (
    audit_log_id bigint NOT NULL,
    tree_id integer NOT NULL
);


ALTER TABLE shared.audit_log_trees OWNER TO supabase_admin;

--
-- Name: TABLE audit_log_trees; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.audit_log_trees IS 'Links audit log entries to tree records';


--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.campaigns_campaign_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.campaigns_campaign_id_seq OWNER TO supabase_admin;

--
-- Name: campaigns_campaign_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.campaigns_campaign_id_seq OWNED BY shared.campaigns.campaign_id;


--
-- Name: climate_zones; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.climate_zones (
    climate_zone_id integer NOT NULL,
    climate_zone_name character varying(10) NOT NULL,
    description text,
    CONSTRAINT chk_climate_zone_format CHECK (((climate_zone_name)::text ~ '^[A-Z][A-Za-z]{0,3}$'::text))
);


ALTER TABLE shared.climate_zones OWNER TO supabase_admin;

--
-- Name: TABLE climate_zones; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.climate_zones IS 'Köppen climate classification zones';


--
-- Name: COLUMN climate_zones.climate_zone_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.climate_zones.climate_zone_name IS 'Köppen climate classification code (e.g., Cfb, Dfb, ET, EF, BWh)';


--
-- Name: climate_zones_climate_zone_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.climate_zones_climate_zone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.climate_zones_climate_zone_id_seq OWNER TO supabase_admin;

--
-- Name: climate_zones_climate_zone_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.climate_zones_climate_zone_id_seq OWNED BY shared.climate_zones.climate_zone_id;


--
-- Name: disturbance_events_disturbance_event_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.disturbance_events_disturbance_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.disturbance_events_disturbance_event_id_seq OWNER TO supabase_admin;

--
-- Name: disturbance_events_disturbance_event_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.disturbance_events_disturbance_event_id_seq OWNED BY shared.disturbance_events.disturbance_event_id;


--
-- Name: disturbance_events_trees; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.disturbance_events_trees (
    disturbance_event_id integer NOT NULL,
    tree_id integer NOT NULL,
    damage_level character varying(50),
    notes text,
    CONSTRAINT disturbance_events_trees_damage_level_check CHECK (((damage_level)::text = ANY (ARRAY[('none'::character varying)::text, ('light'::character varying)::text, ('moderate'::character varying)::text, ('severe'::character varying)::text, ('destroyed'::character varying)::text])))
);


ALTER TABLE shared.disturbance_events_trees OWNER TO supabase_admin;

--
-- Name: TABLE disturbance_events_trees; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.disturbance_events_trees IS 'Links disturbance events to affected individual trees with damage assessment';


--
-- Name: COLUMN disturbance_events_trees.damage_level; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.disturbance_events_trees.damage_level IS 'Level of damage to individual tree';


--
-- Name: inclusion_rules_inclusion_rule_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.inclusion_rules_inclusion_rule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.inclusion_rules_inclusion_rule_id_seq OWNER TO supabase_admin;

--
-- Name: inclusion_rules_inclusion_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.inclusion_rules_inclusion_rule_id_seq OWNED BY shared.inclusion_rules.inclusion_rule_id;


--
-- Name: locations_location_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.locations_location_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.locations_location_id_seq OWNER TO supabase_admin;

--
-- Name: locations_location_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.locations_location_id_seq OWNED BY shared.locations.location_id;


--
-- Name: lookup_registry; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.lookup_registry (
    logical_key text NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    csv_file text NOT NULL,
    csv_columns text[] NOT NULL,
    natural_key text NOT NULL,
    description text
);


ALTER TABLE shared.lookup_registry OWNER TO supabase_admin;

--
-- Name: TABLE lookup_registry; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.lookup_registry IS 'Drives shared.refresh_lookup. csv_columns lists the TARGET column for each CSV column, in file order -- the CSV header is ignored, so a header whose spelling predates a column rename does not silently misload. natural_key is the column the upsert conflicts on.';


--
-- Name: COLUMN lookup_registry.csv_columns; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.lookup_registry.csv_columns IS 'Target column per CSV column, in file order. Length must equal the CSV''s column count; the loader asserts this rather than trusting it.';


--
-- Name: management_events_management_event_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.management_events_management_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.management_events_management_event_id_seq OWNER TO supabase_admin;

--
-- Name: management_events_management_event_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.management_events_management_event_id_seq OWNED BY shared.management_events.management_event_id;


--
-- Name: plots_plot_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.plots_plot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.plots_plot_id_seq OWNER TO supabase_admin;

--
-- Name: plots_plot_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.plots_plot_id_seq OWNED BY shared.plots.plot_id;


--
-- Name: process_metrics; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.process_metrics (
    process_metric_id integer NOT NULL,
    process_id integer NOT NULL,
    metric_name character varying(200) NOT NULL,
    metric_value numeric(10,6),
    source text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT chk_metric_name CHECK (((metric_name)::text = ANY (ARRAY[('accuracy'::character varying)::text, ('precision'::character varying)::text, ('recall'::character varying)::text, ('f1_score'::character varying)::text, ('rmse'::character varying)::text, ('mae'::character varying)::text, ('r_squared'::character varying)::text])))
);


ALTER TABLE shared.process_metrics OWNER TO supabase_admin;

--
-- Name: TABLE process_metrics; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.process_metrics IS 'Published performance metrics for processes';


--
-- Name: process_metrics_process_metric_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.process_metrics_process_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.process_metrics_process_metric_id_seq OWNER TO supabase_admin;

--
-- Name: process_metrics_process_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.process_metrics_process_metric_id_seq OWNED BY shared.process_metrics.process_metric_id;


--
-- Name: process_parameters; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.process_parameters (
    process_parameter_id integer NOT NULL,
    parameter_name character varying(200) NOT NULL,
    parameter_value text NOT NULL,
    data_type character varying(50),
    description text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT process_parameters_data_type_check CHECK (((data_type)::text = ANY (ARRAY[('float'::character varying)::text, ('int'::character varying)::text, ('string'::character varying)::text, ('boolean'::character varying)::text, ('json'::character varying)::text])))
);


ALTER TABLE shared.process_parameters OWNER TO supabase_admin;

--
-- Name: TABLE process_parameters; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.process_parameters IS 'Process parameters used for variants (linked via junction tables)';


--
-- Name: COLUMN process_parameters.parameter_value; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.process_parameters.parameter_value IS 'Parameter value as text (cast based on data_type)';


--
-- Name: process_parameters_environments; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.process_parameters_environments (
    process_parameter_id integer NOT NULL,
    environment_id integer NOT NULL
);


ALTER TABLE shared.process_parameters_environments OWNER TO supabase_admin;

--
-- Name: TABLE process_parameters_environments; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.process_parameters_environments IS 'Links process parameters to environment records';


--
-- Name: process_parameters_point_clouds; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.process_parameters_point_clouds (
    process_parameter_id integer NOT NULL,
    point_cloud_id integer NOT NULL
);


ALTER TABLE shared.process_parameters_point_clouds OWNER TO supabase_admin;

--
-- Name: TABLE process_parameters_point_clouds; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.process_parameters_point_clouds IS 'Links process parameters to point cloud records';


--
-- Name: process_parameters_process_parameter_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.process_parameters_process_parameter_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.process_parameters_process_parameter_id_seq OWNER TO supabase_admin;

--
-- Name: process_parameters_process_parameter_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.process_parameters_process_parameter_id_seq OWNED BY shared.process_parameters.process_parameter_id;


--
-- Name: process_parameters_stems; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.process_parameters_stems (
    process_parameter_id integer NOT NULL,
    stem_id integer NOT NULL
);


ALTER TABLE shared.process_parameters_stems OWNER TO supabase_admin;

--
-- Name: TABLE process_parameters_stems; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.process_parameters_stems IS 'Links process parameters to individual stems';


--
-- Name: process_parameters_trees; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.process_parameters_trees (
    process_parameter_id integer NOT NULL,
    tree_id integer NOT NULL
);


ALTER TABLE shared.process_parameters_trees OWNER TO supabase_admin;

--
-- Name: TABLE process_parameters_trees; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.process_parameters_trees IS 'Links process parameters to tree records';


--
-- Name: processes_process_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.processes_process_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.processes_process_id_seq OWNER TO supabase_admin;

--
-- Name: processes_process_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.processes_process_id_seq OWNED BY shared.processes.process_id;


--
-- Name: processing_jobs_processing_job_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.processing_jobs_processing_job_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.processing_jobs_processing_job_id_seq OWNER TO supabase_admin;

--
-- Name: processing_jobs_processing_job_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.processing_jobs_processing_job_id_seq OWNED BY shared.processing_jobs.processing_job_id;


--
-- Name: recent_changes; Type: VIEW; Schema: shared; Owner: supabase_admin
--

CREATE VIEW shared.recent_changes AS
 SELECT al.audit_log_id,
    COALESCE(
        CASE
            WHEN (alpc.point_cloud_id IS NOT NULL) THEN 'point_clouds'::text
            WHEN (alt.tree_id IS NOT NULL) THEN 'trees'::text
            WHEN (ale.environment_id IS NOT NULL) THEN 'environments'::text
            WHEN (als.stem_id IS NOT NULL) THEN 'stems'::text
            WHEN (alp.phenology_observation_id IS NOT NULL) THEN 'phenology_observations'::text
            ELSE NULL::text
        END) AS table_name,
    COALESCE(alpc.point_cloud_id, alt.tree_id, ale.environment_id, als.stem_id, alp.phenology_observation_id) AS record_id,
    al.field_name,
    al.old_value,
    al.new_value,
    al.change_type,
    al.user_id,
    al."timestamp",
    al.change_reason
   FROM (((((shared.audit_log al
     LEFT JOIN shared.audit_log_point_clouds alpc ON ((al.audit_log_id = alpc.audit_log_id)))
     LEFT JOIN shared.audit_log_trees alt ON ((al.audit_log_id = alt.audit_log_id)))
     LEFT JOIN shared.audit_log_environments ale ON ((al.audit_log_id = ale.audit_log_id)))
     LEFT JOIN shared.audit_log_stems als ON ((al.audit_log_id = als.audit_log_id)))
     LEFT JOIN shared.audit_log_phenology_observations alp ON ((al.audit_log_id = alp.audit_log_id)))
  ORDER BY al."timestamp" DESC;


ALTER TABLE shared.recent_changes OWNER TO supabase_admin;

--
-- Name: VIEW recent_changes; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON VIEW shared.recent_changes IS 'Unified view of recent changes across all audited tables';


--
-- Name: sampling_designs_sampling_design_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.sampling_designs_sampling_design_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.sampling_designs_sampling_design_id_seq OWNER TO supabase_admin;

--
-- Name: sampling_designs_sampling_design_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.sampling_designs_sampling_design_id_seq OWNED BY shared.sampling_designs.sampling_design_id;


--
-- Name: scenarios_scenario_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.scenarios_scenario_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.scenarios_scenario_id_seq OWNER TO supabase_admin;

--
-- Name: scenarios_scenario_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.scenarios_scenario_id_seq OWNED BY shared.scenarios.scenario_id;


--
-- Name: soil_types; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.soil_types (
    soil_type_id integer NOT NULL,
    soil_type_name character varying(100) NOT NULL,
    description text,
    CONSTRAINT chk_soil_type_name CHECK (((soil_type_name)::text = ANY (ARRAY[('Alfisol'::character varying)::text, ('Andisol'::character varying)::text, ('Aridisol'::character varying)::text, ('Entisol'::character varying)::text, ('Gelisol'::character varying)::text, ('Histosol'::character varying)::text, ('Inceptisol'::character varying)::text, ('Mollisol'::character varying)::text, ('Oxisol'::character varying)::text, ('Spodosol'::character varying)::text, ('Ultisol'::character varying)::text, ('Vertisol'::character varying)::text])))
);


ALTER TABLE shared.soil_types OWNER TO supabase_admin;

--
-- Name: TABLE soil_types; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.soil_types IS 'USDA soil classification reference table';


--
-- Name: COLUMN soil_types.soil_type_name; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON COLUMN shared.soil_types.soil_type_name IS 'USDA soil classification type';


--
-- Name: soil_types_soil_type_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.soil_types_soil_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.soil_types_soil_type_id_seq OWNER TO supabase_admin;

--
-- Name: soil_types_soil_type_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.soil_types_soil_type_id_seq OWNED BY shared.soil_types.soil_type_id;


--
-- Name: species_species_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.species_species_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.species_species_id_seq OWNER TO supabase_admin;

--
-- Name: species_species_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.species_species_id_seq OWNED BY shared.species.species_id;


--
-- Name: strata_stratum_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.strata_stratum_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.strata_stratum_id_seq OWNER TO supabase_admin;

--
-- Name: strata_stratum_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.strata_stratum_id_seq OWNED BY shared.strata.stratum_id;


--
-- Name: team_members; Type: TABLE; Schema: shared; Owner: supabase_admin
--

CREATE TABLE shared.team_members (
    team_id integer NOT NULL,
    user_id uuid NOT NULL,
    is_team_curator boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200)
);


ALTER TABLE shared.team_members OWNER TO supabase_admin;

--
-- Name: TABLE team_members; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON TABLE shared.team_members IS 'Who belongs to which team. Written through public.add_team_member / remove_team_member: curators and admins for any team, team curators for their own team (members only).';


--
-- Name: teams_team_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.teams_team_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.teams_team_id_seq OWNER TO supabase_admin;

--
-- Name: teams_team_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.teams_team_id_seq OWNED BY shared.teams.team_id;


--
-- Name: user_activity_summary; Type: VIEW; Schema: shared; Owner: supabase_admin
--

CREATE VIEW shared.user_activity_summary AS
 SELECT audit_log.user_id,
    count(*) AS total_changes,
    count(DISTINCT date(audit_log."timestamp")) AS active_days,
    min(audit_log."timestamp") AS first_change,
    max(audit_log."timestamp") AS last_change,
    count(*) FILTER (WHERE ((audit_log.change_type)::text = 'field_update'::text)) AS field_updates,
    count(*) FILTER (WHERE ((audit_log.change_type)::text = 'bulk_update'::text)) AS bulk_updates,
    count(*) FILTER (WHERE ((audit_log.change_type)::text = 'revert'::text)) AS reverts
   FROM shared.audit_log
  GROUP BY audit_log.user_id;


ALTER TABLE shared.user_activity_summary OWNER TO supabase_admin;

--
-- Name: VIEW user_activity_summary; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON VIEW shared.user_activity_summary IS 'Summary of user activity and change patterns';


--
-- Name: variant_types_variant_type_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.variant_types_variant_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.variant_types_variant_type_id_seq OWNER TO supabase_admin;

--
-- Name: variant_types_variant_type_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.variant_types_variant_type_id_seq OWNED BY shared.variant_types.variant_type_id;


--
-- Name: variants_variant_id_seq; Type: SEQUENCE; Schema: shared; Owner: supabase_admin
--

CREATE SEQUENCE shared.variants_variant_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE shared.variants_variant_id_seq OWNER TO supabase_admin;

--
-- Name: variants_variant_id_seq; Type: SEQUENCE OWNED BY; Schema: shared; Owner: supabase_admin
--

ALTER SEQUENCE shared.variants_variant_id_seq OWNED BY shared.variants.variant_id;


--
-- Name: axis_structures_axis_structure_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.axis_structures_axis_structure_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.axis_structures_axis_structure_id_seq OWNER TO supabase_admin;

--
-- Name: axis_structures_axis_structure_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.axis_structures_axis_structure_id_seq OWNED BY trees.axis_structures.axis_structure_id;


--
-- Name: bark_characteristics; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.bark_characteristics (
    bark_characteristic_id integer NOT NULL,
    bark_characteristic_name character varying(100) NOT NULL,
    description text,
    typical_species text
);


ALTER TABLE trees.bark_characteristics OWNER TO supabase_admin;

--
-- Name: TABLE bark_characteristics; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.bark_characteristics IS 'Bark texture and appearance classifications';


--
-- Name: bark_characteristics_bark_characteristic_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.bark_characteristics_bark_characteristic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.bark_characteristics_bark_characteristic_id_seq OWNER TO supabase_admin;

--
-- Name: bark_characteristics_bark_characteristic_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.bark_characteristics_bark_characteristic_id_seq OWNED BY trees.bark_characteristics.bark_characteristic_id;


--
-- Name: branch_elongation_habits_elongation_habit_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.branch_elongation_habits_elongation_habit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.branch_elongation_habits_elongation_habit_id_seq OWNER TO supabase_admin;

--
-- Name: branch_elongation_habits_elongation_habit_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.branch_elongation_habits_elongation_habit_id_seq OWNED BY trees.branch_elongation_habits.elongation_habit_id;


--
-- Name: branching_patterns; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.branching_patterns (
    branching_pattern_id integer NOT NULL,
    branching_pattern_name character varying(100) NOT NULL,
    description text
);


ALTER TABLE trees.branching_patterns OWNER TO supabase_admin;

--
-- Name: TABLE branching_patterns; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.branching_patterns IS 'Branch arrangement patterns on stems';


--
-- Name: branching_patterns_branching_pattern_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.branching_patterns_branching_pattern_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.branching_patterns_branching_pattern_id_seq OWNER TO supabase_admin;

--
-- Name: branching_patterns_branching_pattern_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.branching_patterns_branching_pattern_id_seq OWNED BY trees.branching_patterns.branching_pattern_id;


--
-- Name: crown_architectures_crown_architecture_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.crown_architectures_crown_architecture_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.crown_architectures_crown_architecture_id_seq OWNER TO supabase_admin;

--
-- Name: crown_architectures_crown_architecture_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.crown_architectures_crown_architecture_id_seq OWNED BY trees.crown_architectures.crown_architecture_id;


--
-- Name: crown_classes_crown_class_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.crown_classes_crown_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.crown_classes_crown_class_id_seq OWNER TO supabase_admin;

--
-- Name: crown_classes_crown_class_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.crown_classes_crown_class_id_seq OWNED BY trees.crown_classes.crown_class_id;


--
-- Name: crown_foliage_profiles_crown_foliage_profile_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.crown_foliage_profiles_crown_foliage_profile_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.crown_foliage_profiles_crown_foliage_profile_id_seq OWNER TO supabase_admin;

--
-- Name: crown_foliage_profiles_crown_foliage_profile_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.crown_foliage_profiles_crown_foliage_profile_id_seq OWNED BY trees.crown_foliage_profiles.crown_foliage_profile_id;


--
-- Name: crown_shapes_crown_shape_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.crown_shapes_crown_shape_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.crown_shapes_crown_shape_id_seq OWNER TO supabase_admin;

--
-- Name: crown_shapes_crown_shape_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.crown_shapes_crown_shape_id_seq OWNED BY trees.crown_shapes.crown_shape_id;


--
-- Name: damage_agents_damage_agent_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.damage_agents_damage_agent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.damage_agents_damage_agent_id_seq OWNER TO supabase_admin;

--
-- Name: damage_agents_damage_agent_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.damage_agents_damage_agent_id_seq OWNED BY trees.damage_agents.damage_agent_id;


--
-- Name: data_source_types_data_source_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.data_source_types_data_source_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.data_source_types_data_source_type_id_seq OWNER TO supabase_admin;

--
-- Name: data_source_types_data_source_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.data_source_types_data_source_type_id_seq OWNED BY trees.data_source_types.data_source_type_id;


--
-- Name: entity_matches_entity_match_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.entity_matches_entity_match_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.entity_matches_entity_match_id_seq OWNER TO supabase_admin;

--
-- Name: entity_matches_entity_match_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.entity_matches_entity_match_id_seq OWNED BY trees.entity_matches.entity_match_id;


--
-- Name: geometric_crown_solids_geometric_crown_solid_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.geometric_crown_solids_geometric_crown_solid_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.geometric_crown_solids_geometric_crown_solid_id_seq OWNER TO supabase_admin;

--
-- Name: geometric_crown_solids_geometric_crown_solid_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.geometric_crown_solids_geometric_crown_solid_id_seq OWNED BY trees.geometric_crown_solids.geometric_crown_solid_id;


--
-- Name: growth_forms_growth_form_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.growth_forms_growth_form_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.growth_forms_growth_form_id_seq OWNER TO supabase_admin;

--
-- Name: growth_forms_growth_form_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.growth_forms_growth_form_id_seq OWNED BY trees.growth_forms.growth_form_id;


--
-- Name: growth_orientations_growth_orientation_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.growth_orientations_growth_orientation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.growth_orientations_growth_orientation_id_seq OWNER TO supabase_admin;

--
-- Name: growth_orientations_growth_orientation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.growth_orientations_growth_orientation_id_seq OWNED BY trees.growth_orientations.growth_orientation_id;


--
-- Name: growth_simulations_growth_simulation_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.growth_simulations_growth_simulation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.growth_simulations_growth_simulation_id_seq OWNER TO supabase_admin;

--
-- Name: growth_simulations_growth_simulation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.growth_simulations_growth_simulation_id_seq OWNED BY trees.growth_simulations.growth_simulation_id;


--
-- Name: observations_observation_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.observations_observation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.observations_observation_id_seq OWNER TO supabase_admin;

--
-- Name: observations_observation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.observations_observation_id_seq OWNED BY trees.observations.observation_id;


--
-- Name: phanerophyte_height_classes_height_class_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.phanerophyte_height_classes_height_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.phanerophyte_height_classes_height_class_id_seq OWNER TO supabase_admin;

--
-- Name: phanerophyte_height_classes_height_class_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.phanerophyte_height_classes_height_class_id_seq OWNED BY trees.phanerophyte_height_classes.height_class_id;


--
-- Name: phenology_observations_phenology_observation_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.phenology_observations_phenology_observation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.phenology_observations_phenology_observation_id_seq OWNER TO supabase_admin;

--
-- Name: phenology_observations_phenology_observation_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.phenology_observations_phenology_observation_id_seq OWNED BY trees.phenology_observations.phenology_observation_id;


--
-- Name: qsm_cylinders; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.qsm_cylinders (
    qsm_cylinder_id bigint NOT NULL,
    qsm_id bigint NOT NULL,
    cylinder_index integer NOT NULL,
    parent_cylinder_index integer,
    start_point extensions.geometry(PointZ),
    axis double precision[],
    length_m numeric(8,4) NOT NULL,
    radius_m numeric(8,5) NOT NULL,
    branch_index integer,
    branch_order integer,
    branch_position integer,
    part_type_id smallint,
    created_at timestamp with time zone DEFAULT now(),
    raw_radius_m numeric(8,5),
    is_virtual boolean DEFAULT false NOT NULL,
    CONSTRAINT qsm_cylinders_axis_check CHECK (((axis IS NULL) OR (array_length(axis, 1) = 3))),
    CONSTRAINT qsm_cylinders_branch_order_check CHECK ((branch_order >= 0)),
    CONSTRAINT qsm_cylinders_length_m_check CHECK ((length_m >= (0)::numeric)),
    CONSTRAINT qsm_cylinders_radius_m_check CHECK ((radius_m >= (0)::numeric)),
    CONSTRAINT qsm_cylinders_raw_radius_m_check CHECK (((raw_radius_m IS NULL) OR (raw_radius_m >= (0)::numeric)))
);


ALTER TABLE trees.qsm_cylinders OWNER TO supabase_admin;

--
-- Name: TABLE qsm_cylinders; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.qsm_cylinders IS 'QSM cylinder geometry, Real Twig / rTwig standardised column set -- ~10^3-10^4 rows per tree';


--
-- Name: COLUMN qsm_cylinders.cylinder_index; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.cylinder_index IS 'Cylinder id within the QSM, as published (rTwig ''id'')';


--
-- Name: COLUMN qsm_cylinders.parent_cylinder_index; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.parent_cylinder_index IS 'Parent cylinder_index, self-referenced by index (not FK) to match the source files -- 0 for the base cylinder, per rTwig convention';


--
-- Name: COLUMN qsm_cylinders.start_point; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.start_point IS 'Cylinder base coordinate in the QSM''s local frame (trees.qsms.local_crs / origin_position)';


--
-- Name: COLUMN qsm_cylinders.axis; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.axis IS 'Unit vector [x,y,z] from cylinder base to top';


--
-- Name: COLUMN qsm_cylinders.length_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.length_m IS 'Cylinder length; 0 is allowed because TreeQSM output contains zero-length cylinders that other cylinders hang off';


--
-- Name: COLUMN qsm_cylinders.radius_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.radius_m IS 'Radius as the source delivered it: radius-corrected where the source corrects (see trees.qsms.is_corrected), raw otherwise';


--
-- Name: COLUMN qsm_cylinders.branch_index; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.branch_index IS 'Axis (branch) id from 1, by the lab''s single axis rule (the child with the longer supported subtree continues the axis), not the producing tool''s own id';


--
-- Name: COLUMN qsm_cylinders.branch_order; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.branch_order IS 'Axis order, 0 = trunk, by the same single axis rule';


--
-- Name: COLUMN qsm_cylinders.branch_position; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.branch_position IS 'Position along the axis, from 1 at its base';


--
-- Name: COLUMN qsm_cylinders.part_type_id; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.part_type_id IS 'CityGML part semantic (trunk/branch/twig) -- see trees.tree_part_types; assignment rule documented in this migration''s header';


--
-- Name: COLUMN qsm_cylinders.raw_radius_m; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.raw_radius_m IS 'Radius of the fitted cylinder before any correction (rTwig raw_radius, TreeQSM UnmodRadius); NULL when the source does not keep it';


--
-- Name: COLUMN qsm_cylinders.is_virtual; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.qsm_cylinders.is_virtual IS 'Cylinder added to bridge a gap in the point cloud (TreeQSM added, TreeML addedVirtual), not fitted to points';


--
-- Name: qsm_cylinders_qsm_cylinder_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.qsm_cylinders_qsm_cylinder_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.qsm_cylinders_qsm_cylinder_id_seq OWNER TO supabase_admin;

--
-- Name: qsm_cylinders_qsm_cylinder_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.qsm_cylinders_qsm_cylinder_id_seq OWNED BY trees.qsm_cylinders.qsm_cylinder_id;


--
-- Name: qsms_qsm_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.qsms_qsm_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.qsms_qsm_id_seq OWNER TO supabase_admin;

--
-- Name: qsms_qsm_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.qsms_qsm_id_seq OWNED BY trees.qsms.qsm_id;


--
-- Name: root_system_types_root_system_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.root_system_types_root_system_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.root_system_types_root_system_type_id_seq OWNER TO supabase_admin;

--
-- Name: root_system_types_root_system_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.root_system_types_root_system_type_id_seq OWNED BY trees.root_system_types.root_system_type_id;


--
-- Name: roots_root_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.roots_root_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.roots_root_id_seq OWNER TO supabase_admin;

--
-- Name: roots_root_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.roots_root_id_seq OWNED BY trees.roots.root_id;


--
-- Name: shoot_elongation_types_shoot_elongation_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.shoot_elongation_types_shoot_elongation_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.shoot_elongation_types_shoot_elongation_type_id_seq OWNER TO supabase_admin;

--
-- Name: shoot_elongation_types_shoot_elongation_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.shoot_elongation_types_shoot_elongation_type_id_seq OWNED BY trees.shoot_elongation_types.shoot_elongation_type_id;


--
-- Name: stems_stem_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.stems_stem_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.stems_stem_id_seq OWNER TO supabase_admin;

--
-- Name: stems_stem_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.stems_stem_id_seq OWNED BY trees.stems.stem_id;


--
-- Name: straightness_types; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.straightness_types (
    straightness_type_id integer NOT NULL,
    straightness_type_name character varying(100) NOT NULL,
    description text,
    deviation_angle_min_deg numeric(5,2),
    deviation_angle_max_deg numeric(5,2),
    CONSTRAINT chk_deviation_order CHECK ((deviation_angle_min_deg <= deviation_angle_max_deg)),
    CONSTRAINT straightness_types_deviation_angle_max_check CHECK (((deviation_angle_max_deg >= (0)::numeric) AND (deviation_angle_max_deg <= (90)::numeric))),
    CONSTRAINT straightness_types_deviation_angle_min_check CHECK (((deviation_angle_min_deg >= (0)::numeric) AND (deviation_angle_min_deg <= (90)::numeric)))
);


ALTER TABLE trees.straightness_types OWNER TO supabase_admin;

--
-- Name: TABLE straightness_types; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.straightness_types IS 'Stem straightness classifications';


--
-- Name: straightness_types_straightness_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.straightness_types_straightness_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.straightness_types_straightness_type_id_seq OWNER TO supabase_admin;

--
-- Name: straightness_types_straightness_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.straightness_types_straightness_type_id_seq OWNED BY trees.straightness_types.straightness_type_id;


--
-- Name: taper_types; Type: TABLE; Schema: trees; Owner: supabase_admin
--

CREATE TABLE trees.taper_types (
    taper_type_id integer NOT NULL,
    taper_type_name character varying(100) NOT NULL,
    description text,
    typical_taper_ratio_min numeric(4,3),
    typical_taper_ratio_max numeric(4,3),
    CONSTRAINT chk_taper_ratio_order CHECK ((typical_taper_ratio_min <= typical_taper_ratio_max)),
    CONSTRAINT taper_types_typical_taper_ratio_max_check CHECK (((typical_taper_ratio_max >= (0)::numeric) AND (typical_taper_ratio_max <= (1)::numeric))),
    CONSTRAINT taper_types_typical_taper_ratio_min_check CHECK (((typical_taper_ratio_min >= (0)::numeric) AND (typical_taper_ratio_min <= (1)::numeric)))
);


ALTER TABLE trees.taper_types OWNER TO supabase_admin;

--
-- Name: TABLE taper_types; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON TABLE trees.taper_types IS 'Stem taper form classifications';


--
-- Name: COLUMN taper_types.typical_taper_ratio_min; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON COLUMN trees.taper_types.typical_taper_ratio_min IS 'Minimum typical taper ratio (diameter at top / diameter at bottom)';


--
-- Name: taper_types_taper_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.taper_types_taper_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.taper_types_taper_type_id_seq OWNER TO supabase_admin;

--
-- Name: taper_types_taper_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.taper_types_taper_type_id_seq OWNED BY trees.taper_types.taper_type_id;


--
-- Name: tree_graph_edges_tree_graph_edge_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.tree_graph_edges_tree_graph_edge_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.tree_graph_edges_tree_graph_edge_id_seq OWNER TO supabase_admin;

--
-- Name: tree_graph_edges_tree_graph_edge_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.tree_graph_edges_tree_graph_edge_id_seq OWNED BY trees.tree_graph_edges.tree_graph_edge_id;


--
-- Name: tree_part_types_part_type_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.tree_part_types_part_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.tree_part_types_part_type_id_seq OWNER TO supabase_admin;

--
-- Name: tree_part_types_part_type_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.tree_part_types_part_type_id_seq OWNED BY trees.tree_part_types.part_type_id;


--
-- Name: tree_status_tree_status_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.tree_status_tree_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.tree_status_tree_status_id_seq OWNER TO supabase_admin;

--
-- Name: tree_status_tree_status_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.tree_status_tree_status_id_seq OWNED BY trees.tree_status.tree_status_id;


--
-- Name: trees_tree_id_seq; Type: SEQUENCE; Schema: trees; Owner: supabase_admin
--

CREATE SEQUENCE trees.trees_tree_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE trees.trees_tree_id_seq OWNER TO supabase_admin;

--
-- Name: trees_tree_id_seq; Type: SEQUENCE OWNED BY; Schema: trees; Owner: supabase_admin
--

ALTER SEQUENCE trees.trees_tree_id_seq OWNED BY trees.trees.tree_id;


--
-- Name: trees_with_metrics; Type: VIEW; Schema: trees; Owner: supabase_admin
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


ALTER TABLE trees.trees_with_metrics OWNER TO supabase_admin;

--
-- Name: VIEW trees_with_metrics; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON VIEW trees.trees_with_metrics IS 'Trees with computed metrics (basal area, crown volume, stem count)';


--
-- Name: environments environment_id; Type: DEFAULT; Schema: environments; Owner: supabase_admin
--

ALTER TABLE ONLY environments.environments ALTER COLUMN environment_id SET DEFAULT nextval('environments.environments_environment_id_seq'::regclass);


--
-- Name: deadwood deadwood_id; Type: DEFAULT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.deadwood ALTER COLUMN deadwood_id SET DEFAULT nextval('forest_floor.deadwood_deadwood_id_seq'::regclass);


--
-- Name: ground_vegetation ground_vegetation_id; Type: DEFAULT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.ground_vegetation ALTER COLUMN ground_vegetation_id SET DEFAULT nextval('forest_floor.ground_vegetation_ground_vegetation_id_seq'::regclass);


--
-- Name: regeneration regeneration_id; Type: DEFAULT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.regeneration ALTER COLUMN regeneration_id SET DEFAULT nextval('forest_floor.regeneration_regeneration_id_seq'::regclass);


--
-- Name: images image_id; Type: DEFAULT; Schema: imagery; Owner: supabase_admin
--

ALTER TABLE ONLY imagery.images ALTER COLUMN image_id SET DEFAULT nextval('imagery.images_image_id_seq'::regclass);


--
-- Name: point_clouds point_cloud_id; Type: DEFAULT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds ALTER COLUMN point_cloud_id SET DEFAULT nextval('point_clouds.point_clouds_point_cloud_id_seq'::regclass);


--
-- Name: scanner_types scanner_type_id; Type: DEFAULT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.scanner_types ALTER COLUMN scanner_type_id SET DEFAULT nextval('point_clouds.scanner_types_scanner_type_id_seq'::regclass);


--
-- Name: scanners scanner_id; Type: DEFAULT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.scanners ALTER COLUMN scanner_id SET DEFAULT nextval('point_clouds.scanners_scanner_id_seq'::regclass);


--
-- Name: campaigns access_level; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.campaigns ALTER COLUMN access_level SET DEFAULT 'public'::character varying;


--
-- Name: environments environment_id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.environments ALTER COLUMN environment_id SET DEFAULT nextval('environments.environments_environment_id_seq'::regclass);


--
-- Name: environments created_at; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.environments ALTER COLUMN created_at SET DEFAULT now();


--
-- Name: plots sampling_weight; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.plots ALTER COLUMN sampling_weight SET DEFAULT 1;


--
-- Name: point_clouds point_cloud_id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.point_clouds ALTER COLUMN point_cloud_id SET DEFAULT nextval('point_clouds.point_clouds_point_cloud_id_seq'::regclass);


--
-- Name: point_clouds created_at; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.point_clouds ALTER COLUMN created_at SET DEFAULT now();


--
-- Name: sensors sensor_id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sensors ALTER COLUMN sensor_id SET DEFAULT nextval('sensor.sensors_sensor_id_seq'::regclass);


--
-- Name: sensors installation_date; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sensors ALTER COLUMN installation_date SET DEFAULT now();


--
-- Name: sensors is_active; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sensors ALTER COLUMN is_active SET DEFAULT true;


--
-- Name: sensors created_at; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sensors ALTER COLUMN created_at SET DEFAULT now();


--
-- Name: sensors external_metadata; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sensors ALTER COLUMN external_metadata SET DEFAULT '{}'::jsonb;


--
-- Name: stems stem_id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.stems ALTER COLUMN stem_id SET DEFAULT nextval('trees.stems_stem_id_seq'::regclass);


--
-- Name: stems created_at; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.stems ALTER COLUMN created_at SET DEFAULT now();


--
-- Name: sensor_readings sensor_reading_id; Type: DEFAULT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_readings ALTER COLUMN sensor_reading_id SET DEFAULT nextval('sensor.sensor_readings_sensor_reading_id_seq'::regclass);


--
-- Name: sensor_tree_links sensor_tree_link_id; Type: DEFAULT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_tree_links ALTER COLUMN sensor_tree_link_id SET DEFAULT nextval('sensor.sensor_tree_links_sensor_tree_link_id_seq'::regclass);


--
-- Name: sensor_types sensor_type_id; Type: DEFAULT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_types ALTER COLUMN sensor_type_id SET DEFAULT nextval('sensor.sensor_types_sensor_type_id_seq'::regclass);


--
-- Name: sensors sensor_id; Type: DEFAULT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors ALTER COLUMN sensor_id SET DEFAULT nextval('sensor.sensors_sensor_id_seq'::regclass);


--
-- Name: units unit_id; Type: DEFAULT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.units ALTER COLUMN unit_id SET DEFAULT nextval('sensor.units_unit_id_seq'::regclass);


--
-- Name: attribute_provenance attribute_provenance_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.attribute_provenance ALTER COLUMN attribute_provenance_id SET DEFAULT nextval('shared.attribute_provenance_attribute_provenance_id_seq'::regclass);


--
-- Name: audit_log audit_log_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log ALTER COLUMN audit_log_id SET DEFAULT nextval('shared.audit_log_audit_log_id_seq'::regclass);


--
-- Name: campaigns campaign_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.campaigns ALTER COLUMN campaign_id SET DEFAULT nextval('shared.campaigns_campaign_id_seq'::regclass);


--
-- Name: climate_zones climate_zone_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.climate_zones ALTER COLUMN climate_zone_id SET DEFAULT nextval('shared.climate_zones_climate_zone_id_seq'::regclass);


--
-- Name: disturbance_events disturbance_event_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.disturbance_events ALTER COLUMN disturbance_event_id SET DEFAULT nextval('shared.disturbance_events_disturbance_event_id_seq'::regclass);


--
-- Name: inclusion_rules inclusion_rule_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.inclusion_rules ALTER COLUMN inclusion_rule_id SET DEFAULT nextval('shared.inclusion_rules_inclusion_rule_id_seq'::regclass);


--
-- Name: locations location_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.locations ALTER COLUMN location_id SET DEFAULT nextval('shared.locations_location_id_seq'::regclass);


--
-- Name: management_events management_event_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.management_events ALTER COLUMN management_event_id SET DEFAULT nextval('shared.management_events_management_event_id_seq'::regclass);


--
-- Name: plots plot_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.plots ALTER COLUMN plot_id SET DEFAULT nextval('shared.plots_plot_id_seq'::regclass);


--
-- Name: process_metrics process_metric_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_metrics ALTER COLUMN process_metric_id SET DEFAULT nextval('shared.process_metrics_process_metric_id_seq'::regclass);


--
-- Name: process_parameters process_parameter_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters ALTER COLUMN process_parameter_id SET DEFAULT nextval('shared.process_parameters_process_parameter_id_seq'::regclass);


--
-- Name: processes process_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.processes ALTER COLUMN process_id SET DEFAULT nextval('shared.processes_process_id_seq'::regclass);


--
-- Name: processing_jobs processing_job_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.processing_jobs ALTER COLUMN processing_job_id SET DEFAULT nextval('shared.processing_jobs_processing_job_id_seq'::regclass);


--
-- Name: sampling_designs sampling_design_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.sampling_designs ALTER COLUMN sampling_design_id SET DEFAULT nextval('shared.sampling_designs_sampling_design_id_seq'::regclass);


--
-- Name: scenarios scenario_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios ALTER COLUMN scenario_id SET DEFAULT nextval('shared.scenarios_scenario_id_seq'::regclass);


--
-- Name: soil_types soil_type_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.soil_types ALTER COLUMN soil_type_id SET DEFAULT nextval('shared.soil_types_soil_type_id_seq'::regclass);


--
-- Name: species species_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.species ALTER COLUMN species_id SET DEFAULT nextval('shared.species_species_id_seq'::regclass);


--
-- Name: strata stratum_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.strata ALTER COLUMN stratum_id SET DEFAULT nextval('shared.strata_stratum_id_seq'::regclass);


--
-- Name: teams team_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.teams ALTER COLUMN team_id SET DEFAULT nextval('shared.teams_team_id_seq'::regclass);


--
-- Name: variant_types variant_type_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variant_types ALTER COLUMN variant_type_id SET DEFAULT nextval('shared.variant_types_variant_type_id_seq'::regclass);


--
-- Name: variants variant_id; Type: DEFAULT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants ALTER COLUMN variant_id SET DEFAULT nextval('shared.variants_variant_id_seq'::regclass);


--
-- Name: axis_structures axis_structure_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.axis_structures ALTER COLUMN axis_structure_id SET DEFAULT nextval('trees.axis_structures_axis_structure_id_seq'::regclass);


--
-- Name: bark_characteristics bark_characteristic_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.bark_characteristics ALTER COLUMN bark_characteristic_id SET DEFAULT nextval('trees.bark_characteristics_bark_characteristic_id_seq'::regclass);


--
-- Name: branch_elongation_habits elongation_habit_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.branch_elongation_habits ALTER COLUMN elongation_habit_id SET DEFAULT nextval('trees.branch_elongation_habits_elongation_habit_id_seq'::regclass);


--
-- Name: branching_patterns branching_pattern_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.branching_patterns ALTER COLUMN branching_pattern_id SET DEFAULT nextval('trees.branching_patterns_branching_pattern_id_seq'::regclass);


--
-- Name: crown_architectures crown_architecture_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_architectures ALTER COLUMN crown_architecture_id SET DEFAULT nextval('trees.crown_architectures_crown_architecture_id_seq'::regclass);


--
-- Name: crown_classes crown_class_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_classes ALTER COLUMN crown_class_id SET DEFAULT nextval('trees.crown_classes_crown_class_id_seq'::regclass);


--
-- Name: crown_foliage_profiles crown_foliage_profile_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_foliage_profiles ALTER COLUMN crown_foliage_profile_id SET DEFAULT nextval('trees.crown_foliage_profiles_crown_foliage_profile_id_seq'::regclass);


--
-- Name: crown_shapes crown_shape_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_shapes ALTER COLUMN crown_shape_id SET DEFAULT nextval('trees.crown_shapes_crown_shape_id_seq'::regclass);


--
-- Name: damage_agents damage_agent_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.damage_agents ALTER COLUMN damage_agent_id SET DEFAULT nextval('trees.damage_agents_damage_agent_id_seq'::regclass);


--
-- Name: data_source_types data_source_type_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.data_source_types ALTER COLUMN data_source_type_id SET DEFAULT nextval('trees.data_source_types_data_source_type_id_seq'::regclass);


--
-- Name: entity_matches entity_match_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.entity_matches ALTER COLUMN entity_match_id SET DEFAULT nextval('trees.entity_matches_entity_match_id_seq'::regclass);


--
-- Name: geometric_crown_solids geometric_crown_solid_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.geometric_crown_solids ALTER COLUMN geometric_crown_solid_id SET DEFAULT nextval('trees.geometric_crown_solids_geometric_crown_solid_id_seq'::regclass);


--
-- Name: growth_forms growth_form_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_forms ALTER COLUMN growth_form_id SET DEFAULT nextval('trees.growth_forms_growth_form_id_seq'::regclass);


--
-- Name: growth_orientations growth_orientation_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_orientations ALTER COLUMN growth_orientation_id SET DEFAULT nextval('trees.growth_orientations_growth_orientation_id_seq'::regclass);


--
-- Name: growth_simulations growth_simulation_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations ALTER COLUMN growth_simulation_id SET DEFAULT nextval('trees.growth_simulations_growth_simulation_id_seq'::regclass);


--
-- Name: observations observation_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations ALTER COLUMN observation_id SET DEFAULT nextval('trees.observations_observation_id_seq'::regclass);


--
-- Name: phanerophyte_height_classes height_class_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.phanerophyte_height_classes ALTER COLUMN height_class_id SET DEFAULT nextval('trees.phanerophyte_height_classes_height_class_id_seq'::regclass);


--
-- Name: phenology_observations phenology_observation_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.phenology_observations ALTER COLUMN phenology_observation_id SET DEFAULT nextval('trees.phenology_observations_phenology_observation_id_seq'::regclass);


--
-- Name: qsm_cylinders qsm_cylinder_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsm_cylinders ALTER COLUMN qsm_cylinder_id SET DEFAULT nextval('trees.qsm_cylinders_qsm_cylinder_id_seq'::regclass);


--
-- Name: qsms qsm_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsms ALTER COLUMN qsm_id SET DEFAULT nextval('trees.qsms_qsm_id_seq'::regclass);


--
-- Name: root_system_types root_system_type_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.root_system_types ALTER COLUMN root_system_type_id SET DEFAULT nextval('trees.root_system_types_root_system_type_id_seq'::regclass);


--
-- Name: roots root_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.roots ALTER COLUMN root_id SET DEFAULT nextval('trees.roots_root_id_seq'::regclass);


--
-- Name: shoot_elongation_types shoot_elongation_type_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.shoot_elongation_types ALTER COLUMN shoot_elongation_type_id SET DEFAULT nextval('trees.shoot_elongation_types_shoot_elongation_type_id_seq'::regclass);


--
-- Name: stems stem_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.stems ALTER COLUMN stem_id SET DEFAULT nextval('trees.stems_stem_id_seq'::regclass);


--
-- Name: straightness_types straightness_type_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.straightness_types ALTER COLUMN straightness_type_id SET DEFAULT nextval('trees.straightness_types_straightness_type_id_seq'::regclass);


--
-- Name: taper_types taper_type_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.taper_types ALTER COLUMN taper_type_id SET DEFAULT nextval('trees.taper_types_taper_type_id_seq'::regclass);


--
-- Name: tree_graph_edges tree_graph_edge_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_graph_edges ALTER COLUMN tree_graph_edge_id SET DEFAULT nextval('trees.tree_graph_edges_tree_graph_edge_id_seq'::regclass);


--
-- Name: tree_part_types part_type_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_part_types ALTER COLUMN part_type_id SET DEFAULT nextval('trees.tree_part_types_part_type_id_seq'::regclass);


--
-- Name: tree_status tree_status_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_status ALTER COLUMN tree_status_id SET DEFAULT nextval('trees.tree_status_tree_status_id_seq'::regclass);


--
-- Name: trees tree_id; Type: DEFAULT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees ALTER COLUMN tree_id SET DEFAULT nextval('trees.trees_tree_id_seq'::regclass);


--
-- Name: environments environments_pkey; Type: CONSTRAINT; Schema: environments; Owner: supabase_admin
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_pkey PRIMARY KEY (environment_id);


--
-- Name: deadwood deadwood_pkey; Type: CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.deadwood
    ADD CONSTRAINT deadwood_pkey PRIMARY KEY (deadwood_id);


--
-- Name: ground_vegetation ground_vegetation_pkey; Type: CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.ground_vegetation
    ADD CONSTRAINT ground_vegetation_pkey PRIMARY KEY (ground_vegetation_id);


--
-- Name: regeneration regeneration_pkey; Type: CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.regeneration
    ADD CONSTRAINT regeneration_pkey PRIMARY KEY (regeneration_id);


--
-- Name: images images_pkey; Type: CONSTRAINT; Schema: imagery; Owner: supabase_admin
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_pkey PRIMARY KEY (image_id);


--
-- Name: point_clouds point_clouds_pkey; Type: CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_pkey PRIMARY KEY (point_cloud_id);


--
-- Name: scanner_types scanner_types_pkey; Type: CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.scanner_types
    ADD CONSTRAINT scanner_types_pkey PRIMARY KEY (scanner_type_id);


--
-- Name: scanner_types scanner_types_scanner_type_name_key; Type: CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.scanner_types
    ADD CONSTRAINT scanner_types_scanner_type_name_key UNIQUE (scanner_type_name);


--
-- Name: scanners scanners_pkey; Type: CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.scanners
    ADD CONSTRAINT scanners_pkey PRIMARY KEY (scanner_id);


--
-- Name: scanners scanners_serial_number_key; Type: CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.scanners
    ADD CONSTRAINT scanners_serial_number_key UNIQUE (serial_number);


--
-- Name: sensor_readings sensor_readings_pkey; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_readings
    ADD CONSTRAINT sensor_readings_pkey PRIMARY KEY (sensor_reading_id);


--
-- Name: sensor_readings sensor_readings_sensor_id_timestamp_unique; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_readings
    ADD CONSTRAINT sensor_readings_sensor_id_timestamp_unique UNIQUE (sensor_id, "timestamp");


--
-- Name: sensor_tree_links sensor_tree_links_pkey; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_pkey PRIMARY KEY (sensor_tree_link_id);


--
-- Name: sensor_tree_links sensor_tree_links_sensor_id_tree_id_key; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_sensor_id_tree_id_key UNIQUE (sensor_id, tree_id);


--
-- Name: sensor_types sensor_types_pkey; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_types
    ADD CONSTRAINT sensor_types_pkey PRIMARY KEY (sensor_type_id);


--
-- Name: sensor_types sensor_types_sensor_type_name_key; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_types
    ADD CONSTRAINT sensor_types_sensor_type_name_key UNIQUE (sensor_type_name);


--
-- Name: sensors sensors_external_id_key; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_external_id_key UNIQUE (external_id);


--
-- Name: sensors sensors_pkey; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_pkey PRIMARY KEY (sensor_id);


--
-- Name: units units_pkey; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (unit_id);


--
-- Name: units units_unit_name_key; Type: CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.units
    ADD CONSTRAINT units_unit_name_key UNIQUE (unit_name);


--
-- Name: account_events account_events_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.account_events
    ADD CONSTRAINT account_events_pkey PRIMARY KEY (account_event_id);


--
-- Name: attribute_provenance attribute_provenance_location_column_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.attribute_provenance
    ADD CONSTRAINT attribute_provenance_location_column_key UNIQUE (location_id, column_name);


--
-- Name: attribute_provenance attribute_provenance_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.attribute_provenance
    ADD CONSTRAINT attribute_provenance_pkey PRIMARY KEY (attribute_provenance_id);


--
-- Name: audit_log_environments audit_log_environments_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_environments
    ADD CONSTRAINT audit_log_environments_pkey PRIMARY KEY (audit_log_id, environment_id);


--
-- Name: audit_log_phenology_observations audit_log_phenology_observations_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_phenology_observations
    ADD CONSTRAINT audit_log_phenology_observations_pkey PRIMARY KEY (audit_log_id, phenology_observation_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (audit_log_id);


--
-- Name: audit_log_point_clouds audit_log_point_clouds_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_point_clouds
    ADD CONSTRAINT audit_log_point_clouds_pkey PRIMARY KEY (audit_log_id, point_cloud_id);


--
-- Name: audit_log_stems audit_log_stems_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_stems
    ADD CONSTRAINT audit_log_stems_pkey PRIMARY KEY (audit_log_id, stem_id);


--
-- Name: audit_log_trees audit_log_trees_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_trees
    ADD CONSTRAINT audit_log_trees_pkey PRIMARY KEY (audit_log_id, tree_id);


--
-- Name: campaigns campaigns_campaign_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.campaigns
    ADD CONSTRAINT campaigns_campaign_name_key UNIQUE (campaign_name);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (campaign_id);


--
-- Name: climate_pathways climate_pathways_climate_pathway_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.climate_pathways
    ADD CONSTRAINT climate_pathways_climate_pathway_name_key UNIQUE (climate_pathway_name);


--
-- Name: climate_pathways climate_pathways_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.climate_pathways
    ADD CONSTRAINT climate_pathways_pkey PRIMARY KEY (climate_pathway_id);


--
-- Name: climate_zones climate_zones_climate_zone_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.climate_zones
    ADD CONSTRAINT climate_zones_climate_zone_name_key UNIQUE (climate_zone_name);


--
-- Name: climate_zones climate_zones_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.climate_zones
    ADD CONSTRAINT climate_zones_pkey PRIMARY KEY (climate_zone_id);


--
-- Name: disturbance_events disturbance_events_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.disturbance_events
    ADD CONSTRAINT disturbance_events_pkey PRIMARY KEY (disturbance_event_id);


--
-- Name: disturbance_events_trees disturbance_events_trees_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.disturbance_events_trees
    ADD CONSTRAINT disturbance_events_trees_pkey PRIMARY KEY (disturbance_event_id, tree_id);


--
-- Name: inclusion_rules inclusion_rules_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.inclusion_rules
    ADD CONSTRAINT inclusion_rules_pkey PRIMARY KEY (inclusion_rule_id);


--
-- Name: locations locations_location_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_location_name_key UNIQUE (location_name);


--
-- Name: locations locations_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (location_id);


--
-- Name: lookup_registry lookup_registry_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.lookup_registry
    ADD CONSTRAINT lookup_registry_pkey PRIMARY KEY (logical_key);


--
-- Name: management_events management_events_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.management_events
    ADD CONSTRAINT management_events_pkey PRIMARY KEY (management_event_id);


--
-- Name: management_regimes management_regimes_management_regime_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.management_regimes
    ADD CONSTRAINT management_regimes_management_regime_name_key UNIQUE (management_regime_name);


--
-- Name: management_regimes management_regimes_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.management_regimes
    ADD CONSTRAINT management_regimes_pkey PRIMARY KEY (management_regime_id);


--
-- Name: plots plots_location_id_plot_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_location_id_plot_name_key UNIQUE (location_id, plot_name);


--
-- Name: plots plots_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_pkey PRIMARY KEY (plot_id);


--
-- Name: process_metrics process_metrics_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_metrics
    ADD CONSTRAINT process_metrics_pkey PRIMARY KEY (process_metric_id);


--
-- Name: process_parameters_environments process_parameters_environments_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_environments
    ADD CONSTRAINT process_parameters_environments_pkey PRIMARY KEY (process_parameter_id, environment_id);


--
-- Name: process_parameters process_parameters_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters
    ADD CONSTRAINT process_parameters_pkey PRIMARY KEY (process_parameter_id);


--
-- Name: process_parameters_point_clouds process_parameters_point_clouds_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_point_clouds
    ADD CONSTRAINT process_parameters_point_clouds_pkey PRIMARY KEY (process_parameter_id, point_cloud_id);


--
-- Name: process_parameters_stems process_parameters_stems_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_stems
    ADD CONSTRAINT process_parameters_stems_pkey PRIMARY KEY (process_parameter_id, stem_id);


--
-- Name: process_parameters_trees process_parameters_trees_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_trees
    ADD CONSTRAINT process_parameters_trees_pkey PRIMARY KEY (process_parameter_id, tree_id);


--
-- Name: processes processes_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.processes
    ADD CONSTRAINT processes_pkey PRIMARY KEY (process_id);


--
-- Name: processes processes_process_name_version_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.processes
    ADD CONSTRAINT processes_process_name_version_key UNIQUE (process_name, version);


--
-- Name: processes processes_workflow_key_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.processes
    ADD CONSTRAINT processes_workflow_key_key UNIQUE (workflow_key);


--
-- Name: processing_jobs processing_jobs_external_job_id_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.processing_jobs
    ADD CONSTRAINT processing_jobs_external_job_id_key UNIQUE (external_job_id);


--
-- Name: processing_jobs processing_jobs_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.processing_jobs
    ADD CONSTRAINT processing_jobs_pkey PRIMARY KEY (processing_job_id);


--
-- Name: sampling_designs sampling_designs_design_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.sampling_designs
    ADD CONSTRAINT sampling_designs_design_name_key UNIQUE (design_name);


--
-- Name: sampling_designs sampling_designs_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.sampling_designs
    ADD CONSTRAINT sampling_designs_pkey PRIMARY KEY (sampling_design_id);


--
-- Name: scenarios scenarios_location_axes_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_location_axes_key UNIQUE (location_id, management_regime_id, climate_pathway_id);


--
-- Name: scenarios scenarios_location_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_location_name_key UNIQUE (location_id, scenario_name);


--
-- Name: scenarios scenarios_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_pkey PRIMARY KEY (scenario_id);


--
-- Name: scenarios scenarios_scenario_location_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_scenario_location_key UNIQUE (scenario_id, location_id);


--
-- Name: soil_types soil_types_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.soil_types
    ADD CONSTRAINT soil_types_pkey PRIMARY KEY (soil_type_id);


--
-- Name: soil_types soil_types_soil_type_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.soil_types
    ADD CONSTRAINT soil_types_soil_type_name_key UNIQUE (soil_type_name);


--
-- Name: species species_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.species
    ADD CONSTRAINT species_pkey PRIMARY KEY (species_id);


--
-- Name: species species_scientific_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.species
    ADD CONSTRAINT species_scientific_name_key UNIQUE (scientific_name);


--
-- Name: strata strata_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.strata
    ADD CONSTRAINT strata_pkey PRIMARY KEY (stratum_id);


--
-- Name: strata strata_sampling_design_id_stratum_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.strata
    ADD CONSTRAINT strata_sampling_design_id_stratum_name_key UNIQUE (sampling_design_id, stratum_name);


--
-- Name: strata strata_stratum_id_sampling_design_id_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.strata
    ADD CONSTRAINT strata_stratum_id_sampling_design_id_key UNIQUE (stratum_id, sampling_design_id);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (team_id, user_id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (team_id);


--
-- Name: teams teams_team_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.teams
    ADD CONSTRAINT teams_team_name_key UNIQUE (team_name);


--
-- Name: variant_types variant_types_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variant_types
    ADD CONSTRAINT variant_types_pkey PRIMARY KEY (variant_type_id);


--
-- Name: variant_types variant_types_variant_type_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variant_types
    ADD CONSTRAINT variant_types_variant_type_name_key UNIQUE (variant_type_name);


--
-- Name: variants variants_identity_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_identity_key UNIQUE (variant_id, scenario_id, location_id, variant_type_id);


--
-- Name: variants variants_location_id_scenario_id_variant_name_key; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_location_id_scenario_id_variant_name_key UNIQUE (location_id, scenario_id, variant_name);


--
-- Name: variants variants_pkey; Type: CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_pkey PRIMARY KEY (variant_id);


--
-- Name: axis_structures axis_structures_axis_structure_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.axis_structures
    ADD CONSTRAINT axis_structures_axis_structure_name_key UNIQUE (axis_structure_name);


--
-- Name: axis_structures axis_structures_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.axis_structures
    ADD CONSTRAINT axis_structures_pkey PRIMARY KEY (axis_structure_id);


--
-- Name: bark_characteristics bark_characteristics_bark_characteristic_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.bark_characteristics
    ADD CONSTRAINT bark_characteristics_bark_characteristic_name_key UNIQUE (bark_characteristic_name);


--
-- Name: bark_characteristics bark_characteristics_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.bark_characteristics
    ADD CONSTRAINT bark_characteristics_pkey PRIMARY KEY (bark_characteristic_id);


--
-- Name: branch_elongation_habits branch_elongation_habits_elongation_habit_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.branch_elongation_habits
    ADD CONSTRAINT branch_elongation_habits_elongation_habit_name_key UNIQUE (elongation_habit_name);


--
-- Name: branch_elongation_habits branch_elongation_habits_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.branch_elongation_habits
    ADD CONSTRAINT branch_elongation_habits_pkey PRIMARY KEY (elongation_habit_id);


--
-- Name: branching_patterns branching_patterns_branching_pattern_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.branching_patterns
    ADD CONSTRAINT branching_patterns_branching_pattern_name_key UNIQUE (branching_pattern_name);


--
-- Name: branching_patterns branching_patterns_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.branching_patterns
    ADD CONSTRAINT branching_patterns_pkey PRIMARY KEY (branching_pattern_id);


--
-- Name: crown_architectures crown_architectures_crown_architecture_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_architectures
    ADD CONSTRAINT crown_architectures_crown_architecture_name_key UNIQUE (crown_architecture_name);


--
-- Name: crown_architectures crown_architectures_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_architectures
    ADD CONSTRAINT crown_architectures_pkey PRIMARY KEY (crown_architecture_id);


--
-- Name: crown_classes crown_classes_crown_class_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_classes
    ADD CONSTRAINT crown_classes_crown_class_name_key UNIQUE (crown_class_name);


--
-- Name: crown_classes crown_classes_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_classes
    ADD CONSTRAINT crown_classes_pkey PRIMARY KEY (crown_class_id);


--
-- Name: crown_foliage_profiles crown_foliage_profiles_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_foliage_profiles
    ADD CONSTRAINT crown_foliage_profiles_pkey PRIMARY KEY (crown_foliage_profile_id);


--
-- Name: crown_shapes crown_shapes_crown_shape_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_shapes
    ADD CONSTRAINT crown_shapes_crown_shape_name_key UNIQUE (crown_shape_name);


--
-- Name: crown_shapes crown_shapes_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_shapes
    ADD CONSTRAINT crown_shapes_pkey PRIMARY KEY (crown_shape_id);


--
-- Name: damage_agents damage_agents_damage_agent_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.damage_agents
    ADD CONSTRAINT damage_agents_damage_agent_name_key UNIQUE (damage_agent_name);


--
-- Name: damage_agents damage_agents_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.damage_agents
    ADD CONSTRAINT damage_agents_pkey PRIMARY KEY (damage_agent_id);


--
-- Name: data_source_types data_source_types_data_source_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.data_source_types
    ADD CONSTRAINT data_source_types_data_source_type_name_key UNIQUE (data_source_type_name);


--
-- Name: data_source_types data_source_types_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.data_source_types
    ADD CONSTRAINT data_source_types_pkey PRIMARY KEY (data_source_type_id);


--
-- Name: entity_matches entity_matches_id_observation_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.entity_matches
    ADD CONSTRAINT entity_matches_id_observation_key UNIQUE (entity_match_id, observation_id);


--
-- Name: entity_matches entity_matches_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.entity_matches
    ADD CONSTRAINT entity_matches_pkey PRIMARY KEY (entity_match_id);


--
-- Name: geometric_crown_solids geometric_crown_solids_geometric_crown_solid_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.geometric_crown_solids
    ADD CONSTRAINT geometric_crown_solids_geometric_crown_solid_name_key UNIQUE (geometric_crown_solid_name);


--
-- Name: geometric_crown_solids geometric_crown_solids_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.geometric_crown_solids
    ADD CONSTRAINT geometric_crown_solids_pkey PRIMARY KEY (geometric_crown_solid_id);


--
-- Name: growth_forms growth_forms_growth_form_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_forms
    ADD CONSTRAINT growth_forms_growth_form_name_key UNIQUE (growth_form_name);


--
-- Name: growth_forms growth_forms_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_forms
    ADD CONSTRAINT growth_forms_pkey PRIMARY KEY (growth_form_id);


--
-- Name: growth_orientations growth_orientations_growth_orientation_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_orientations
    ADD CONSTRAINT growth_orientations_growth_orientation_name_key UNIQUE (growth_orientation_name);


--
-- Name: growth_orientations growth_orientations_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_orientations
    ADD CONSTRAINT growth_orientations_pkey PRIMARY KEY (growth_orientation_id);


--
-- Name: growth_simulations growth_simulations_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations
    ADD CONSTRAINT growth_simulations_pkey PRIMARY KEY (growth_simulation_id);


--
-- Name: observations observations_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations
    ADD CONSTRAINT observations_pkey PRIMARY KEY (observation_id);


--
-- Name: phanerophyte_height_classes phanerophyte_height_classes_height_class_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.phanerophyte_height_classes
    ADD CONSTRAINT phanerophyte_height_classes_height_class_name_key UNIQUE (height_class_name);


--
-- Name: phanerophyte_height_classes phanerophyte_height_classes_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.phanerophyte_height_classes
    ADD CONSTRAINT phanerophyte_height_classes_pkey PRIMARY KEY (height_class_id);


--
-- Name: phenology_observations phenology_observations_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.phenology_observations
    ADD CONSTRAINT phenology_observations_pkey PRIMARY KEY (phenology_observation_id);


--
-- Name: qsm_cylinders qsm_cylinders_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsm_cylinders
    ADD CONSTRAINT qsm_cylinders_pkey PRIMARY KEY (qsm_cylinder_id);


--
-- Name: qsm_cylinders qsm_cylinders_qsm_id_cylinder_index_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsm_cylinders
    ADD CONSTRAINT qsm_cylinders_qsm_id_cylinder_index_key UNIQUE (qsm_id, cylinder_index);


--
-- Name: qsms qsms_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_pkey PRIMARY KEY (qsm_id);


--
-- Name: root_system_types root_system_types_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.root_system_types
    ADD CONSTRAINT root_system_types_pkey PRIMARY KEY (root_system_type_id);


--
-- Name: root_system_types root_system_types_root_system_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.root_system_types
    ADD CONSTRAINT root_system_types_root_system_type_name_key UNIQUE (root_system_type_name);


--
-- Name: roots roots_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_pkey PRIMARY KEY (root_id);


--
-- Name: shoot_elongation_types shoot_elongation_types_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.shoot_elongation_types
    ADD CONSTRAINT shoot_elongation_types_pkey PRIMARY KEY (shoot_elongation_type_id);


--
-- Name: shoot_elongation_types shoot_elongation_types_shoot_elongation_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.shoot_elongation_types
    ADD CONSTRAINT shoot_elongation_types_shoot_elongation_type_name_key UNIQUE (shoot_elongation_type_name);


--
-- Name: simulation_runs simulation_runs_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.simulation_runs
    ADD CONSTRAINT simulation_runs_pkey PRIMARY KEY (simulation_run_id);


--
-- Name: stems stems_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_pkey PRIMARY KEY (stem_id);


--
-- Name: stems stems_tree_id_stem_number_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_tree_id_stem_number_key UNIQUE (tree_id, stem_number);


--
-- Name: straightness_types straightness_types_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.straightness_types
    ADD CONSTRAINT straightness_types_pkey PRIMARY KEY (straightness_type_id);


--
-- Name: straightness_types straightness_types_straightness_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.straightness_types
    ADD CONSTRAINT straightness_types_straightness_name_key UNIQUE (straightness_type_name);


--
-- Name: taper_types taper_types_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.taper_types
    ADD CONSTRAINT taper_types_pkey PRIMARY KEY (taper_type_id);


--
-- Name: taper_types taper_types_taper_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.taper_types
    ADD CONSTRAINT taper_types_taper_type_name_key UNIQUE (taper_type_name);


--
-- Name: tree_graph_edges tree_graph_edges_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_graph_edges
    ADD CONSTRAINT tree_graph_edges_pkey PRIMARY KEY (tree_graph_edge_id);


--
-- Name: tree_graph_edges tree_graph_edges_qsm_from_to_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_graph_edges
    ADD CONSTRAINT tree_graph_edges_qsm_from_to_key UNIQUE (qsm_id, from_cylinder_index, to_cylinder_index);


--
-- Name: tree_part_types tree_part_types_part_type_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_part_types
    ADD CONSTRAINT tree_part_types_part_type_name_key UNIQUE (part_type_name);


--
-- Name: tree_part_types tree_part_types_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_part_types
    ADD CONSTRAINT tree_part_types_pkey PRIMARY KEY (part_type_id);


--
-- Name: tree_status tree_status_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_status
    ADD CONSTRAINT tree_status_pkey PRIMARY KEY (tree_status_id);


--
-- Name: tree_status tree_status_tree_status_name_key; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_status
    ADD CONSTRAINT tree_status_tree_status_name_key UNIQUE (tree_status_name);


--
-- Name: trees trees_pkey; Type: CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_pkey PRIMARY KEY (tree_id);


--
-- Name: idx_environments_created_at; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_created_at ON environments.environments USING btree (created_at DESC);


--
-- Name: idx_environments_created_by; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_created_by ON environments.environments USING btree (created_by);


--
-- Name: idx_environments_end_date; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_end_date ON environments.environments USING btree (end_date DESC NULLS LAST);


--
-- Name: idx_environments_location; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_location ON environments.environments USING btree (location_id);


--
-- Name: idx_environments_parent; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_parent ON environments.environments USING btree (parent_environment_id);


--
-- Name: idx_environments_process; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_process ON environments.environments USING btree (process_id);


--
-- Name: idx_environments_scenario; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_scenario ON environments.environments USING btree (scenario_id);


--
-- Name: idx_environments_start_date; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_start_date ON environments.environments USING btree (start_date DESC);


--
-- Name: idx_environments_variant_type; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE INDEX idx_environments_variant_type ON environments.environments USING btree (variant_type_id);


--
-- Name: uq_environments_natural_key; Type: INDEX; Schema: environments; Owner: supabase_admin
--

CREATE UNIQUE INDEX uq_environments_natural_key ON environments.environments USING btree (location_id, scenario_id, variant_type_id, variant_name, start_date, end_date) NULLS NOT DISTINCT;


--
-- Name: INDEX uq_environments_natural_key; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON INDEX environments.uq_environments_natural_key IS 'Natural key of an environment row, and the conflict target of public.upsert_environment. variant_name is part of it so that two differently-named projections of the same period stay distinct rows.';


--
-- Name: deadwood_campaign_id_idx; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX deadwood_campaign_id_idx ON forest_floor.deadwood USING btree (campaign_id);


--
-- Name: deadwood_campaign_source_id_key; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE UNIQUE INDEX deadwood_campaign_source_id_key ON forest_floor.deadwood USING btree (campaign_id, source_deadwood_id) WHERE (source_deadwood_id IS NOT NULL);


--
-- Name: deadwood_geom_idx; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX deadwood_geom_idx ON forest_floor.deadwood USING gist (geom);


--
-- Name: ground_vegetation_campaign_id_idx; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX ground_vegetation_campaign_id_idx ON forest_floor.ground_vegetation USING btree (campaign_id);


--
-- Name: idx_deadwood_location; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_deadwood_location ON forest_floor.deadwood USING btree (location_id);


--
-- Name: idx_deadwood_plot; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_deadwood_plot ON forest_floor.deadwood USING btree (plot_id);


--
-- Name: idx_deadwood_position; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_deadwood_position ON forest_floor.deadwood USING gist ("position");


--
-- Name: idx_deadwood_species; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_deadwood_species ON forest_floor.deadwood USING btree (species_id);


--
-- Name: idx_deadwood_tree; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_deadwood_tree ON forest_floor.deadwood USING btree (tree_id);


--
-- Name: idx_deadwood_type; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_deadwood_type ON forest_floor.deadwood USING btree (wood_type);


--
-- Name: idx_groundveg_date; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_groundveg_date ON forest_floor.ground_vegetation USING btree (measurement_date DESC);


--
-- Name: idx_groundveg_layer; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_groundveg_layer ON forest_floor.ground_vegetation USING btree (layer);


--
-- Name: idx_groundveg_location; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_groundveg_location ON forest_floor.ground_vegetation USING btree (location_id);


--
-- Name: idx_groundveg_plot; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX idx_groundveg_plot ON forest_floor.ground_vegetation USING btree (plot_id);


--
-- Name: regeneration_campaign_id_idx; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX regeneration_campaign_id_idx ON forest_floor.regeneration USING btree (campaign_id);


--
-- Name: regeneration_campaign_source_id_key; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE UNIQUE INDEX regeneration_campaign_source_id_key ON forest_floor.regeneration USING btree (campaign_id, source_regeneration_id) WHERE (source_regeneration_id IS NOT NULL);


--
-- Name: regeneration_location_id_idx; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX regeneration_location_id_idx ON forest_floor.regeneration USING btree (location_id);


--
-- Name: regeneration_plot_id_idx; Type: INDEX; Schema: forest_floor; Owner: supabase_admin
--

CREATE INDEX regeneration_plot_id_idx ON forest_floor.regeneration USING btree (plot_id);


--
-- Name: idx_images_campaign; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_campaign ON imagery.images USING btree (campaign_id);


--
-- Name: idx_images_capture_date; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_capture_date ON imagery.images USING btree (capture_date DESC);


--
-- Name: idx_images_created_at; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_created_at ON imagery.images USING btree (created_at DESC);


--
-- Name: idx_images_created_by; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_created_by ON imagery.images USING btree (created_by);


--
-- Name: idx_images_format; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_format ON imagery.images USING btree (file_format);


--
-- Name: idx_images_location; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_location ON imagery.images USING btree (location_id);


--
-- Name: idx_images_plot; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_plot ON imagery.images USING btree (plot_id);


--
-- Name: idx_images_position; Type: INDEX; Schema: imagery; Owner: supabase_admin
--

CREATE INDEX idx_images_position ON imagery.images USING gist ("position");


--
-- Name: idx_point_clouds_campaign; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_campaign ON point_clouds.point_clouds USING btree (campaign_id);


--
-- Name: idx_point_clouds_created_at; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_created_at ON point_clouds.point_clouds USING btree (created_at DESC);


--
-- Name: idx_point_clouds_created_by; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_created_by ON point_clouds.point_clouds USING btree (created_by);


--
-- Name: idx_point_clouds_location; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_location ON point_clouds.point_clouds USING btree (location_id);


--
-- Name: idx_point_clouds_parent; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_parent ON point_clouds.point_clouds USING btree (parent_point_cloud_id);


--
-- Name: idx_point_clouds_platform_type; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_platform_type ON point_clouds.point_clouds USING btree (platform_type);


--
-- Name: idx_point_clouds_process; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_process ON point_clouds.point_clouds USING btree (process_id);


--
-- Name: idx_point_clouds_processing_status; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_processing_status ON point_clouds.point_clouds USING btree (processing_status);


--
-- Name: idx_point_clouds_scan_bounds; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_scan_bounds ON point_clouds.point_clouds USING gist (scan_bounds);


--
-- Name: idx_point_clouds_scan_date; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_scan_date ON point_clouds.point_clouds USING btree (scan_date DESC);


--
-- Name: idx_point_clouds_scanner; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_scanner ON point_clouds.point_clouds USING btree (scanner_id);


--
-- Name: idx_point_clouds_scenario; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_scenario ON point_clouds.point_clouds USING btree (scenario_id);


--
-- Name: idx_point_clouds_variant_type; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_point_clouds_variant_type ON point_clouds.point_clouds USING btree (variant_type_id);


--
-- Name: idx_scanner_types_name; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_scanner_types_name ON point_clouds.scanner_types USING btree (scanner_type_name);


--
-- Name: idx_scanners_serial; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_scanners_serial ON point_clouds.scanners USING btree (serial_number);


--
-- Name: idx_scanners_type; Type: INDEX; Schema: point_clouds; Owner: supabase_admin
--

CREATE INDEX idx_scanners_type ON point_clouds.scanners USING btree (scanner_type_id);


--
-- Name: idx_sensor_readings_quality; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensor_readings_quality ON sensor.sensor_readings USING btree (quality);


--
-- Name: idx_sensor_readings_scenario; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensor_readings_scenario ON sensor.sensor_readings USING btree (scenario_id);


--
-- Name: idx_sensor_readings_timestamp; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensor_readings_timestamp ON sensor.sensor_readings USING btree ("timestamp" DESC);


--
-- Name: idx_sensor_tree_links_tree; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensor_tree_links_tree ON sensor.sensor_tree_links USING btree (tree_id);


--
-- Name: idx_sensor_types_name; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensor_types_name ON sensor.sensor_types USING btree (sensor_type_name);


--
-- Name: idx_sensors_campaign; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_campaign ON sensor.sensors USING btree (campaign_id);


--
-- Name: idx_sensors_created_by; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_created_by ON sensor.sensors USING btree (created_by);


--
-- Name: idx_sensors_external_id; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_external_id ON sensor.sensors USING btree (external_id);


--
-- Name: idx_sensors_installation_date; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_installation_date ON sensor.sensors USING btree (installation_date DESC);


--
-- Name: idx_sensors_is_active; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_is_active ON sensor.sensors USING btree (is_active);


--
-- Name: idx_sensors_location; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_location ON sensor.sensors USING btree (location_id);


--
-- Name: idx_sensors_plot; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_plot ON sensor.sensors USING btree (plot_id);


--
-- Name: idx_sensors_position; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_position ON sensor.sensors USING gist ("position");


--
-- Name: idx_sensors_sensor_type; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_sensor_type ON sensor.sensors USING btree (sensor_type_id);


--
-- Name: idx_sensors_serial_number; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_serial_number ON sensor.sensors USING btree (serial_number);


--
-- Name: idx_sensors_source; Type: INDEX; Schema: sensor; Owner: supabase_admin
--

CREATE INDEX idx_sensors_source ON sensor.sensors USING btree (source);


--
-- Name: idx_attribute_provenance_process; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_attribute_provenance_process ON shared.attribute_provenance USING btree (process_id);


--
-- Name: idx_audit_environments_audit; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_environments_audit ON shared.audit_log_environments USING btree (audit_log_id);


--
-- Name: idx_audit_environments_environment; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_environments_environment ON shared.audit_log_environments USING btree (environment_id);


--
-- Name: idx_audit_log_change_type; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_log_change_type ON shared.audit_log USING btree (change_type);


--
-- Name: idx_audit_log_field_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_log_field_name ON shared.audit_log USING btree (field_name);


--
-- Name: idx_audit_log_timestamp; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_log_timestamp ON shared.audit_log USING btree ("timestamp" DESC);


--
-- Name: idx_audit_log_user_id; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_log_user_id ON shared.audit_log USING btree (user_id);


--
-- Name: idx_audit_phenologyobservations_audit; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_phenologyobservations_audit ON shared.audit_log_phenology_observations USING btree (audit_log_id);


--
-- Name: idx_audit_phenologyobservations_phenology; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_phenologyobservations_phenology ON shared.audit_log_phenology_observations USING btree (phenology_observation_id);


--
-- Name: idx_audit_pointclouds_audit; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_pointclouds_audit ON shared.audit_log_point_clouds USING btree (audit_log_id);


--
-- Name: idx_audit_pointclouds_pointcloud; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_pointclouds_pointcloud ON shared.audit_log_point_clouds USING btree (point_cloud_id);


--
-- Name: idx_audit_stems_audit; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_stems_audit ON shared.audit_log_stems USING btree (audit_log_id);


--
-- Name: idx_audit_stems_stem; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_stems_stem ON shared.audit_log_stems USING btree (stem_id);


--
-- Name: idx_audit_trees_audit; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_trees_audit ON shared.audit_log_trees USING btree (audit_log_id);


--
-- Name: idx_audit_trees_tree; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_audit_trees_tree ON shared.audit_log_trees USING btree (tree_id);


--
-- Name: idx_campaigns_location; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_campaigns_location ON shared.campaigns USING btree (location_id);


--
-- Name: idx_campaigns_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_campaigns_name ON shared.campaigns USING btree (campaign_name);


--
-- Name: idx_campaigns_owner_team; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_campaigns_owner_team ON shared.campaigns USING btree (owner_team_id);


--
-- Name: idx_campaigns_start_date; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_campaigns_start_date ON shared.campaigns USING btree (start_date DESC);


--
-- Name: idx_campaigns_type; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_campaigns_type ON shared.campaigns USING btree (campaign_type);


--
-- Name: idx_dist_events_date; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_dist_events_date ON shared.disturbance_events USING btree (event_date DESC);


--
-- Name: idx_dist_events_location; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_dist_events_location ON shared.disturbance_events USING btree (location_id);


--
-- Name: idx_dist_events_plot; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_dist_events_plot ON shared.disturbance_events USING btree (plot_id);


--
-- Name: idx_dist_events_severity; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_dist_events_severity ON shared.disturbance_events USING btree (severity);


--
-- Name: idx_dist_events_type; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_dist_events_type ON shared.disturbance_events USING btree (disturbance_type);


--
-- Name: idx_dist_trees_event; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_dist_trees_event ON shared.disturbance_events_trees USING btree (disturbance_event_id);


--
-- Name: idx_dist_trees_tree; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_dist_trees_tree ON shared.disturbance_events_trees USING btree (tree_id);


--
-- Name: idx_inclusion_rules_design; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_inclusion_rules_design ON shared.inclusion_rules USING btree (sampling_design_id);


--
-- Name: idx_locations_boundary; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_locations_boundary ON shared.locations USING gist (boundary);


--
-- Name: idx_locations_centerpoint; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_locations_centerpoint ON shared.locations USING gist (center_point);


--
-- Name: idx_locations_climate_zone; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_locations_climate_zone ON shared.locations USING btree (climate_zone_id);


--
-- Name: idx_locations_soil_type; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_locations_soil_type ON shared.locations USING btree (soil_type_id);


--
-- Name: idx_mgmt_events_date; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_mgmt_events_date ON shared.management_events USING btree (event_date DESC);


--
-- Name: idx_mgmt_events_location; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_mgmt_events_location ON shared.management_events USING btree (location_id);


--
-- Name: idx_mgmt_events_plot; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_mgmt_events_plot ON shared.management_events USING btree (plot_id);


--
-- Name: idx_mgmt_events_type; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_mgmt_events_type ON shared.management_events USING btree (event_type);


--
-- Name: idx_plots_boundary; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_plots_boundary ON shared.plots USING gist (boundary);


--
-- Name: idx_plots_centerpoint; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_plots_centerpoint ON shared.plots USING gist (center_point);


--
-- Name: idx_plots_location; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_plots_location ON shared.plots USING btree (location_id);


--
-- Name: idx_plots_parent; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_plots_parent ON shared.plots USING btree (parent_plot_id);


--
-- Name: idx_plots_sampling_design; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_plots_sampling_design ON shared.plots USING btree (sampling_design_id);


--
-- Name: idx_pp_environments_environment; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_environments_environment ON shared.process_parameters_environments USING btree (environment_id);


--
-- Name: idx_pp_environments_parameter; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_environments_parameter ON shared.process_parameters_environments USING btree (process_parameter_id);


--
-- Name: idx_pp_pointclouds_parameter; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_pointclouds_parameter ON shared.process_parameters_point_clouds USING btree (process_parameter_id);


--
-- Name: idx_pp_pointclouds_pointcloud; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_pointclouds_pointcloud ON shared.process_parameters_point_clouds USING btree (point_cloud_id);


--
-- Name: idx_pp_stems_parameter; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_stems_parameter ON shared.process_parameters_stems USING btree (process_parameter_id);


--
-- Name: idx_pp_stems_stem; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_stems_stem ON shared.process_parameters_stems USING btree (stem_id);


--
-- Name: idx_pp_trees_parameter; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_trees_parameter ON shared.process_parameters_trees USING btree (process_parameter_id);


--
-- Name: idx_pp_trees_tree; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_pp_trees_tree ON shared.process_parameters_trees USING btree (tree_id);


--
-- Name: idx_process_metrics_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_process_metrics_name ON shared.process_metrics USING btree (metric_name);


--
-- Name: idx_process_metrics_process_id; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_process_metrics_process_id ON shared.process_metrics USING btree (process_id);


--
-- Name: idx_process_parameters_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_process_parameters_name ON shared.process_parameters USING btree (parameter_name);


--
-- Name: idx_processes_category; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processes_category ON shared.processes USING btree (category);


--
-- Name: idx_processes_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processes_name ON shared.processes USING btree (process_name);


--
-- Name: idx_processing_jobs_claimable; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processing_jobs_claimable ON shared.processing_jobs USING btree (submitted_at) WHERE ((status)::text = 'pending'::text);


--
-- Name: idx_processing_jobs_external_id; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processing_jobs_external_id ON shared.processing_jobs USING btree (external_job_id);


--
-- Name: idx_processing_jobs_status; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processing_jobs_status ON shared.processing_jobs USING btree (status);


--
-- Name: idx_processing_jobs_submitted_at; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processing_jobs_submitted_at ON shared.processing_jobs USING btree (submitted_at DESC);


--
-- Name: idx_processing_jobs_submitted_by; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processing_jobs_submitted_by ON shared.processing_jobs USING btree (submitted_by);


--
-- Name: idx_processing_jobs_workflow; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_processing_jobs_workflow ON shared.processing_jobs USING btree (workflow_name);


--
-- Name: idx_scenarios_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_scenarios_name ON shared.scenarios USING btree (scenario_name);


--
-- Name: idx_species_common_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_species_common_name ON shared.species USING btree (common_name);


--
-- Name: idx_species_growth_rate; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_species_growth_rate ON shared.species USING btree (growth_rate);


--
-- Name: idx_species_scientific_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_species_scientific_name ON shared.species USING btree (scientific_name);


--
-- Name: idx_species_shade_tolerance; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_species_shade_tolerance ON shared.species USING btree (shade_tolerance);


--
-- Name: idx_team_members_user; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_team_members_user ON shared.team_members USING btree (user_id);


--
-- Name: idx_variant_types_name; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_variant_types_name ON shared.variant_types USING btree (variant_type_name);


--
-- Name: idx_variants_location; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_variants_location ON shared.variants USING btree (location_id);


--
-- Name: idx_variants_location_scenario; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_variants_location_scenario ON shared.variants USING btree (location_id, scenario_id);


--
-- Name: idx_variants_scenario; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_variants_scenario ON shared.variants USING btree (scenario_id);


--
-- Name: idx_variants_sort; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_variants_sort ON shared.variants USING btree (location_id, scenario_id, sort_order);


--
-- Name: idx_variants_type; Type: INDEX; Schema: shared; Owner: supabase_admin
--

CREATE INDEX idx_variants_type ON shared.variants USING btree (variant_type_id);


--
-- Name: entity_matches_first_decision_key; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE UNIQUE INDEX entity_matches_first_decision_key ON trees.entity_matches USING btree (observation_id) WHERE (supersedes_entity_match_id IS NULL);


--
-- Name: entity_matches_supersedes_key; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE UNIQUE INDEX entity_matches_supersedes_key ON trees.entity_matches USING btree (supersedes_entity_match_id) WHERE (supersedes_entity_match_id IS NOT NULL);


--
-- Name: entity_matches_tree_entity_id_idx; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX entity_matches_tree_entity_id_idx ON trees.entity_matches USING btree (tree_entity_id);


--
-- Name: idx_axis_structures_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_axis_structures_name ON trees.axis_structures USING btree (axis_structure_name);


--
-- Name: idx_bark_characteristics_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_bark_characteristics_name ON trees.bark_characteristics USING btree (bark_characteristic_name);


--
-- Name: idx_branching_patterns_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_branching_patterns_name ON trees.branching_patterns USING btree (branching_pattern_name);


--
-- Name: idx_crown_architectures_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_crown_architectures_name ON trees.crown_architectures USING btree (crown_architecture_name);


--
-- Name: idx_crown_classes_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_crown_classes_name ON trees.crown_classes USING btree (crown_class_name);


--
-- Name: idx_crown_foliage_profiles_tree; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_crown_foliage_profiles_tree ON trees.crown_foliage_profiles USING btree (tree_id);


--
-- Name: idx_crown_shapes_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_crown_shapes_name ON trees.crown_shapes USING btree (crown_shape_name);


--
-- Name: idx_damage_agents_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_damage_agents_name ON trees.damage_agents USING btree (damage_agent_name);


--
-- Name: idx_elongation_habits_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_elongation_habits_name ON trees.branch_elongation_habits USING btree (elongation_habit_name);


--
-- Name: idx_geometric_solids_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_geometric_solids_name ON trees.geometric_crown_solids USING btree (geometric_crown_solid_name);


--
-- Name: idx_growth_forms_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_growth_forms_name ON trees.growth_forms USING btree (growth_form_name);


--
-- Name: idx_growth_orientations_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_growth_orientations_name ON trees.growth_orientations USING btree (growth_orientation_name);


--
-- Name: idx_growthsim_entity_run; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_growthsim_entity_run ON trees.growth_simulations USING btree (tree_entity_id, simulation_run_id);


--
-- Name: idx_growthsim_location_year; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_growthsim_location_year ON trees.growth_simulations USING btree (location_id, projection_year);


--
-- Name: idx_growthsim_run_year; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_growthsim_run_year ON trees.growth_simulations USING btree (simulation_run_id, projection_year);


--
-- Name: idx_growthsim_scenario_year; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_growthsim_scenario_year ON trees.growth_simulations USING btree (scenario_id, projection_year);


--
-- Name: idx_growthsim_simulator; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_growthsim_simulator ON trees.growth_simulations USING btree (simulator_name, scenario_id);


--
-- Name: idx_height_classes_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_height_classes_name ON trees.phanerophyte_height_classes USING btree (height_class_name);


--
-- Name: idx_phenology_date; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_phenology_date ON trees.phenology_observations USING btree (observation_date DESC);


--
-- Name: idx_phenology_tree; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_phenology_tree ON trees.phenology_observations USING btree (tree_id);


--
-- Name: idx_phenology_type; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_phenology_type ON trees.phenology_observations USING btree (phenophase_type);


--
-- Name: idx_qsm_cylinders_qsm_branch_order; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_qsm_cylinders_qsm_branch_order ON trees.qsm_cylinders USING btree (qsm_id, branch_order);


--
-- Name: idx_qsm_cylinders_qsm_parent; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_qsm_cylinders_qsm_parent ON trees.qsm_cylinders USING btree (qsm_id, parent_cylinder_index);


--
-- Name: idx_qsms_point_cloud; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_qsms_point_cloud ON trees.qsms USING btree (point_cloud_id);


--
-- Name: idx_qsms_tree; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_qsms_tree ON trees.qsms USING btree (tree_id);


--
-- Name: idx_qsms_tree_entity; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_qsms_tree_entity ON trees.qsms USING btree (tree_entity_id);


--
-- Name: idx_root_system_types_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_root_system_types_name ON trees.root_system_types USING btree (root_system_type_name);


--
-- Name: idx_roots_root_system_type; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_roots_root_system_type ON trees.roots USING btree (root_system_type_id);


--
-- Name: idx_roots_tree; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_roots_tree ON trees.roots USING btree (tree_id);


--
-- Name: idx_roots_tree_entity; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_roots_tree_entity ON trees.roots USING btree (tree_entity_id);


--
-- Name: idx_shoot_elongation_types_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_shoot_elongation_types_name ON trees.shoot_elongation_types USING btree (shoot_elongation_type_name);


--
-- Name: idx_simulation_runs_created_at; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_simulation_runs_created_at ON trees.simulation_runs USING btree (created_at DESC);


--
-- Name: idx_simulation_runs_location_scenario; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_simulation_runs_location_scenario ON trees.simulation_runs USING btree (location_id, scenario_id);


--
-- Name: idx_simulation_runs_simulator; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_simulation_runs_simulator ON trees.simulation_runs USING btree (simulator_name, simulator_version);


--
-- Name: idx_stems_dbh; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_stems_dbh ON trees.stems USING btree (dbh_cm);


--
-- Name: idx_stems_stem_number; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_stems_stem_number ON trees.stems USING btree (stem_number);


--
-- Name: idx_stems_straightness_type; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_stems_straightness_type ON trees.stems USING btree (straightness_type_id);


--
-- Name: idx_stems_taper_type; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_stems_taper_type ON trees.stems USING btree (taper_type_id);


--
-- Name: idx_stems_tree; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_stems_tree ON trees.stems USING btree (tree_id);


--
-- Name: idx_straightness_types_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_straightness_types_name ON trees.straightness_types USING btree (straightness_type_name);


--
-- Name: idx_taper_types_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_taper_types_name ON trees.taper_types USING btree (taper_type_name);


--
-- Name: idx_tree_graph_edges_qsm; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_tree_graph_edges_qsm ON trees.tree_graph_edges USING btree (qsm_id);


--
-- Name: idx_tree_graph_edges_qsm_type; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_tree_graph_edges_qsm_type ON trees.tree_graph_edges USING btree (qsm_id, edge_type);


--
-- Name: idx_tree_part_types_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_tree_part_types_name ON trees.tree_part_types USING btree (part_type_name);


--
-- Name: idx_tree_status_name; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_tree_status_name ON trees.tree_status USING btree (tree_status_name);


--
-- Name: idx_trees_axis_structure; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_axis_structure ON trees.trees USING btree (axis_structure_id);


--
-- Name: idx_trees_campaign; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_campaign ON trees.trees USING btree (campaign_id);


--
-- Name: idx_trees_created_at; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_created_at ON trees.trees USING btree (created_at DESC);


--
-- Name: idx_trees_created_by; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_created_by ON trees.trees USING btree (created_by);


--
-- Name: idx_trees_crown_architecture; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_crown_architecture ON trees.trees USING btree (crown_architecture_id);


--
-- Name: idx_trees_crown_boundary; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_crown_boundary ON trees.trees USING gist (crown_boundary);


--
-- Name: idx_trees_crown_class; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_crown_class ON trees.trees USING btree (crown_class_id);


--
-- Name: idx_trees_crown_shape; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_crown_shape ON trees.trees USING btree (crown_shape_id);


--
-- Name: idx_trees_damage_agent; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_damage_agent ON trees.trees USING btree (damage_agent_id);


--
-- Name: idx_trees_datasource_type; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_datasource_type ON trees.trees USING btree (data_source_type_id);


--
-- Name: idx_trees_elongation_habit; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_elongation_habit ON trees.trees USING btree (elongation_habit_id);


--
-- Name: idx_trees_geometric_solid; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_geometric_solid ON trees.trees USING btree (geometric_crown_solid_id);


--
-- Name: idx_trees_growth_form; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_growth_form ON trees.trees USING btree (growth_form_id);


--
-- Name: idx_trees_growth_orientation; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_growth_orientation ON trees.trees USING btree (growth_orientation_id);


--
-- Name: idx_trees_height; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_height ON trees.trees USING btree (height_m);


--
-- Name: idx_trees_height_class; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_height_class ON trees.trees USING btree (height_class_id);


--
-- Name: idx_trees_live_crown_ratio; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_live_crown_ratio ON trees.trees USING btree (live_crown_ratio);


--
-- Name: idx_trees_location_scenario; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_location_scenario ON trees.trees USING btree (location_id, scenario_id);


--
-- Name: idx_trees_measurement_date; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_measurement_date ON trees.trees USING btree (measurement_date DESC);


--
-- Name: idx_trees_parent; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_parent ON trees.trees USING btree (parent_tree_id);


--
-- Name: idx_trees_plot; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_plot ON trees.trees USING btree (plot_id);


--
-- Name: idx_trees_pointcloud; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_pointcloud ON trees.trees USING btree (point_cloud_id);


--
-- Name: idx_trees_position; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_position ON trees.trees USING gist ("position");


--
-- Name: idx_trees_process; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_process ON trees.trees USING btree (process_id);


--
-- Name: idx_trees_scenario; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_scenario ON trees.trees USING btree (scenario_id);


--
-- Name: idx_trees_sensor_ref; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_sensor_ref ON trees.trees USING btree (sensor_ref);


--
-- Name: idx_trees_shoot_elongation; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_shoot_elongation ON trees.trees USING btree (shoot_elongation_type_id);


--
-- Name: idx_trees_species; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_species ON trees.trees USING btree (species_id);


--
-- Name: idx_trees_tree_entity; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_tree_entity ON trees.trees USING btree (tree_entity_id);


--
-- Name: idx_trees_tree_number; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_tree_number ON trees.trees USING btree (tree_number);


--
-- Name: idx_trees_tree_status; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_tree_status ON trees.trees USING btree (tree_status_id);


--
-- Name: idx_trees_variant_type; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX idx_trees_variant_type ON trees.trees USING btree (variant_type_id);


--
-- Name: observations_campaign_id_idx; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX observations_campaign_id_idx ON trees.observations USING btree (campaign_id);


--
-- Name: observations_location_id_idx; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX observations_location_id_idx ON trees.observations USING btree (location_id);


--
-- Name: observations_point_cloud_instance_key; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE UNIQUE INDEX observations_point_cloud_instance_key ON trees.observations USING btree (point_cloud_id, instance_id) WHERE (instance_id IS NOT NULL);


--
-- Name: observations_position_idx; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE INDEX observations_position_idx ON trees.observations USING gist ("position");


--
-- Name: observations_tree_id_key; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE UNIQUE INDEX observations_tree_id_key ON trees.observations USING btree (tree_id) WHERE (tree_id IS NOT NULL);


--
-- Name: trees_campaign_variant_source_tree_id_key; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE UNIQUE INDEX trees_campaign_variant_source_tree_id_key ON trees.trees USING btree (campaign_id, variant_id, source_tree_id) NULLS NOT DISTINCT WHERE (source_tree_id IS NOT NULL);


--
-- Name: trees_variant_entity_key; Type: INDEX; Schema: trees; Owner: supabase_admin
--

CREATE UNIQUE INDEX trees_variant_entity_key ON trees.trees USING btree (variant_id, tree_entity_id);


--
-- Name: trees_with_metrics _RETURN; Type: RULE; Schema: trees; Owner: supabase_admin
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
-- Name: environments trigger_environments_audit; Type: TRIGGER; Schema: environments; Owner: supabase_admin
--

CREATE TRIGGER trigger_environments_audit AFTER UPDATE ON environments.environments FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: environments trigger_environments_created_by; Type: TRIGGER; Schema: environments; Owner: supabase_admin
--

CREATE TRIGGER trigger_environments_created_by BEFORE INSERT ON environments.environments FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: environments trigger_environments_updated_at; Type: TRIGGER; Schema: environments; Owner: supabase_admin
--

CREATE TRIGGER trigger_environments_updated_at BEFORE UPDATE ON environments.environments FOR EACH ROW EXECUTE FUNCTION environments.update_updated_at_column();


--
-- Name: environments trigger_environments_updated_by; Type: TRIGGER; Schema: environments; Owner: supabase_admin
--

CREATE TRIGGER trigger_environments_updated_by BEFORE UPDATE ON environments.environments FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: regeneration trigger_regeneration_created_by; Type: TRIGGER; Schema: forest_floor; Owner: supabase_admin
--

CREATE TRIGGER trigger_regeneration_created_by BEFORE INSERT ON forest_floor.regeneration FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: regeneration trigger_regeneration_updated_by; Type: TRIGGER; Schema: forest_floor; Owner: supabase_admin
--

CREATE TRIGGER trigger_regeneration_updated_by BEFORE UPDATE ON forest_floor.regeneration FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: images trigger_images_created_by; Type: TRIGGER; Schema: imagery; Owner: supabase_admin
--

CREATE TRIGGER trigger_images_created_by BEFORE INSERT ON imagery.images FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: images trigger_images_updated_at; Type: TRIGGER; Schema: imagery; Owner: supabase_admin
--

CREATE TRIGGER trigger_images_updated_at BEFORE UPDATE ON imagery.images FOR EACH ROW EXECUTE FUNCTION imagery.update_updated_at_column();


--
-- Name: images trigger_images_updated_by; Type: TRIGGER; Schema: imagery; Owner: supabase_admin
--

CREATE TRIGGER trigger_images_updated_by BEFORE UPDATE ON imagery.images FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: point_clouds trigger_pointclouds_audit; Type: TRIGGER; Schema: point_clouds; Owner: supabase_admin
--

CREATE TRIGGER trigger_pointclouds_audit AFTER UPDATE ON point_clouds.point_clouds FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: point_clouds trigger_pointclouds_created_by; Type: TRIGGER; Schema: point_clouds; Owner: supabase_admin
--

CREATE TRIGGER trigger_pointclouds_created_by BEFORE INSERT ON point_clouds.point_clouds FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: point_clouds trigger_pointclouds_updated_at; Type: TRIGGER; Schema: point_clouds; Owner: supabase_admin
--

CREATE TRIGGER trigger_pointclouds_updated_at BEFORE UPDATE ON point_clouds.point_clouds FOR EACH ROW EXECUTE FUNCTION point_clouds.update_updated_at_column();


--
-- Name: point_clouds trigger_pointclouds_updated_by; Type: TRIGGER; Schema: point_clouds; Owner: supabase_admin
--

CREATE TRIGGER trigger_pointclouds_updated_by BEFORE UPDATE ON point_clouds.point_clouds FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: campaigns campaigns_delete_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER campaigns_delete_trigger INSTEAD OF DELETE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.campaigns_delete();


--
-- Name: campaigns campaigns_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER campaigns_insert_trigger INSTEAD OF INSERT ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.campaigns_insert();


--
-- Name: campaigns campaigns_update_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER campaigns_update_trigger INSTEAD OF UPDATE ON public.campaigns FOR EACH ROW EXECUTE FUNCTION public.campaigns_update();


--
-- Name: crown_foliage_profiles crown_foliage_profiles_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER crown_foliage_profiles_insert_trigger INSTEAD OF INSERT ON public.crown_foliage_profiles FOR EACH ROW EXECUTE FUNCTION public.crown_foliage_profiles_insert();


--
-- Name: deadwood deadwood_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER deadwood_insert_trigger INSTEAD OF INSERT ON public.deadwood FOR EACH ROW EXECUTE FUNCTION public.deadwood_insert();


--
-- Name: disturbance_events disturbance_events_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER disturbance_events_insert_trigger INSTEAD OF INSERT ON public.disturbance_events FOR EACH ROW EXECUTE FUNCTION public.disturbance_events_insert();


--
-- Name: environments environments_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER environments_insert_trigger INSTEAD OF INSERT ON public.environments FOR EACH ROW EXECUTE FUNCTION public.environments_insert();


--
-- Name: ground_vegetation ground_vegetation_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER ground_vegetation_insert_trigger INSTEAD OF INSERT ON public.ground_vegetation FOR EACH ROW EXECUTE FUNCTION public.ground_vegetation_insert();


--
-- Name: images images_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER images_insert_trigger INSTEAD OF INSERT ON public.images FOR EACH ROW EXECUTE FUNCTION public.images_insert();


--
-- Name: management_events management_events_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER management_events_insert_trigger INSTEAD OF INSERT ON public.management_events FOR EACH ROW EXECUTE FUNCTION public.management_events_insert();


--
-- Name: phenology_observations phenology_observations_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER phenology_observations_insert_trigger INSTEAD OF INSERT ON public.phenology_observations FOR EACH ROW EXECUTE FUNCTION public.phenology_observations_insert();


--
-- Name: plots plots_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER plots_insert_trigger INSTEAD OF INSERT ON public.plots FOR EACH ROW EXECUTE FUNCTION public.plots_insert();


--
-- Name: point_clouds point_clouds_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER point_clouds_insert_trigger INSTEAD OF INSERT ON public.point_clouds FOR EACH ROW EXECUTE FUNCTION public.point_clouds_insert();


--
-- Name: qsms qsms_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER qsms_insert_trigger INSTEAD OF INSERT ON public.qsms FOR EACH ROW EXECUTE FUNCTION public.qsms_insert();


--
-- Name: roots roots_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER roots_insert_trigger INSTEAD OF INSERT ON public.roots FOR EACH ROW EXECUTE FUNCTION public.roots_insert();


--
-- Name: sensor_readings sensor_readings_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER sensor_readings_insert_trigger INSTEAD OF INSERT ON public.sensor_readings FOR EACH ROW EXECUTE FUNCTION public.sensor_readings_insert();


--
-- Name: sensors sensors_delete_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER sensors_delete_trigger INSTEAD OF DELETE ON public.sensors FOR EACH ROW EXECUTE FUNCTION public.sensors_delete();


--
-- Name: sensors sensors_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER sensors_insert_trigger INSTEAD OF INSERT ON public.sensors FOR EACH ROW EXECUTE FUNCTION public.sensors_insert();


--
-- Name: sensors sensors_update_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER sensors_update_trigger INSTEAD OF UPDATE ON public.sensors FOR EACH ROW EXECUTE FUNCTION public.sensors_update();


--
-- Name: stems stems_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER stems_insert_trigger INSTEAD OF INSERT ON public.stems FOR EACH ROW EXECUTE FUNCTION public.stems_insert();


--
-- Name: tree_graph_edges tree_graph_edges_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER tree_graph_edges_insert_trigger INSTEAD OF INSERT ON public.tree_graph_edges FOR EACH ROW EXECUTE FUNCTION public.tree_graph_edges_insert();


--
-- Name: trees trees_delete_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER trees_delete_trigger INSTEAD OF DELETE ON public.trees FOR EACH ROW EXECUTE FUNCTION public.trees_delete();


--
-- Name: trees trees_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER trees_insert_trigger INSTEAD OF INSERT ON public.trees FOR EACH ROW EXECUTE FUNCTION public.trees_insert();


--
-- Name: trees trees_update_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER trees_update_trigger INSTEAD OF UPDATE ON public.trees FOR EACH ROW EXECUTE FUNCTION public.trees_update();


--
-- Name: sensors trigger_sensors_created_by; Type: TRIGGER; Schema: sensor; Owner: supabase_admin
--

CREATE TRIGGER trigger_sensors_created_by BEFORE INSERT ON sensor.sensors FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: sensors trigger_sensors_updated_at; Type: TRIGGER; Schema: sensor; Owner: supabase_admin
--

CREATE TRIGGER trigger_sensors_updated_at BEFORE UPDATE ON sensor.sensors FOR EACH ROW EXECUTE FUNCTION sensor.update_updated_at_column();


--
-- Name: sensors trigger_sensors_updated_by; Type: TRIGGER; Schema: sensor; Owner: supabase_admin
--

CREATE TRIGGER trigger_sensors_updated_by BEFORE UPDATE ON sensor.sensors FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: scenarios trg_scenarios_derive_axes; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trg_scenarios_derive_axes BEFORE INSERT OR UPDATE OF scenario_name, management_regime_id, climate_pathway_id ON shared.scenarios FOR EACH ROW EXECUTE FUNCTION shared.scenarios_derive_axes();


--
-- Name: campaigns trigger_campaigns_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_campaigns_created_by BEFORE INSERT ON shared.campaigns FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: campaigns trigger_campaigns_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_campaigns_updated_by BEFORE UPDATE ON shared.campaigns FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: disturbance_events trigger_dist_events_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_dist_events_created_by BEFORE INSERT ON shared.disturbance_events FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: disturbance_events trigger_dist_events_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_dist_events_updated_by BEFORE UPDATE ON shared.disturbance_events FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: inclusion_rules trigger_inclusion_rules_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_inclusion_rules_created_by BEFORE INSERT ON shared.inclusion_rules FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: inclusion_rules trigger_inclusion_rules_no_overlap; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_inclusion_rules_no_overlap BEFORE INSERT OR UPDATE ON shared.inclusion_rules FOR EACH ROW EXECUTE FUNCTION shared.check_inclusion_rule_overlap();


--
-- Name: inclusion_rules trigger_inclusion_rules_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_inclusion_rules_updated_by BEFORE UPDATE ON shared.inclusion_rules FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: locations trigger_locations_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_locations_created_by BEFORE INSERT ON shared.locations FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: locations trigger_locations_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_locations_updated_by BEFORE UPDATE ON shared.locations FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: management_events trigger_mgmt_events_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_mgmt_events_created_by BEFORE INSERT ON shared.management_events FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: management_events trigger_mgmt_events_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_mgmt_events_updated_by BEFORE UPDATE ON shared.management_events FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: plots trigger_plots_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_plots_created_by BEFORE INSERT ON shared.plots FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: plots trigger_plots_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_plots_updated_by BEFORE UPDATE ON shared.plots FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: sampling_designs trigger_sampling_designs_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_sampling_designs_created_by BEFORE INSERT ON shared.sampling_designs FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: sampling_designs trigger_sampling_designs_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_sampling_designs_updated_by BEFORE UPDATE ON shared.sampling_designs FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: strata trigger_strata_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_strata_created_by BEFORE INSERT ON shared.strata FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: strata trigger_strata_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_strata_updated_by BEFORE UPDATE ON shared.strata FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: teams trigger_teams_created_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_teams_created_by BEFORE INSERT ON shared.teams FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: teams trigger_teams_updated_by; Type: TRIGGER; Schema: shared; Owner: supabase_admin
--

CREATE TRIGGER trigger_teams_updated_by BEFORE UPDATE ON shared.teams FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: trees trg_trees_assign_height_class; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trg_trees_assign_height_class BEFORE INSERT OR UPDATE OF height_m ON trees.trees FOR EACH ROW EXECUTE FUNCTION trees.assign_height_class();


--
-- Name: trees trg_trees_fill_from_variant; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trg_trees_fill_from_variant BEFORE INSERT ON trees.trees FOR EACH ROW EXECUTE FUNCTION trees.fill_from_variant();


--
-- Name: entity_matches trigger_entity_matches_created_by; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_entity_matches_created_by BEFORE INSERT ON trees.entity_matches FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: observations trigger_observations_created_by; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_observations_created_by BEFORE INSERT ON trees.observations FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: phenology_observations trigger_phenology_audit; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_phenology_audit AFTER UPDATE ON trees.phenology_observations FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: stems trigger_stems_audit; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_stems_audit AFTER UPDATE ON trees.stems FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: stems trigger_stems_updated_at; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_stems_updated_at BEFORE UPDATE ON trees.stems FOR EACH ROW EXECUTE FUNCTION trees.update_updated_at_column();


--
-- Name: trees trigger_trees_audit; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_trees_audit AFTER UPDATE ON trees.trees FOR EACH ROW EXECUTE FUNCTION shared.audit_update_trigger();


--
-- Name: trees trigger_trees_created_by; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_trees_created_by BEFORE INSERT ON trees.trees FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


--
-- Name: trees trigger_trees_updated_at; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_trees_updated_at BEFORE UPDATE ON trees.trees FOR EACH ROW EXECUTE FUNCTION trees.update_updated_at_column();


--
-- Name: trees trigger_trees_updated_by; Type: TRIGGER; Schema: trees; Owner: supabase_admin
--

CREATE TRIGGER trigger_trees_updated_by BEFORE UPDATE ON trees.trees FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


--
-- Name: environments environments_location_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: supabase_admin
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: environments environments_parent_environment_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: supabase_admin
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_parent_environment_id_fkey FOREIGN KEY (parent_environment_id) REFERENCES environments.environments(environment_id) ON DELETE SET NULL;


--
-- Name: environments environments_process_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: supabase_admin
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: environments environments_scenario_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: supabase_admin
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: environments environments_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: environments; Owner: supabase_admin
--

ALTER TABLE ONLY environments.environments
    ADD CONSTRAINT environments_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.variant_types(variant_type_id);


--
-- Name: deadwood deadwood_campaign_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.deadwood
    ADD CONSTRAINT deadwood_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: deadwood deadwood_location_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.deadwood
    ADD CONSTRAINT deadwood_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: deadwood deadwood_plot_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.deadwood
    ADD CONSTRAINT deadwood_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: deadwood deadwood_species_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.deadwood
    ADD CONSTRAINT deadwood_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: deadwood deadwood_tree_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.deadwood
    ADD CONSTRAINT deadwood_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE SET NULL;


--
-- Name: ground_vegetation ground_vegetation_campaign_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.ground_vegetation
    ADD CONSTRAINT ground_vegetation_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: ground_vegetation ground_vegetation_location_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.ground_vegetation
    ADD CONSTRAINT ground_vegetation_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: ground_vegetation ground_vegetation_plot_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.ground_vegetation
    ADD CONSTRAINT ground_vegetation_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: regeneration regeneration_campaign_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.regeneration
    ADD CONSTRAINT regeneration_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: regeneration regeneration_location_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.regeneration
    ADD CONSTRAINT regeneration_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: regeneration regeneration_plot_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.regeneration
    ADD CONSTRAINT regeneration_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: regeneration regeneration_species_id_fkey; Type: FK CONSTRAINT; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE ONLY forest_floor.regeneration
    ADD CONSTRAINT regeneration_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: images images_campaign_id_fkey; Type: FK CONSTRAINT; Schema: imagery; Owner: supabase_admin
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: images images_location_id_fkey; Type: FK CONSTRAINT; Schema: imagery; Owner: supabase_admin
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: images images_plot_id_fkey; Type: FK CONSTRAINT; Schema: imagery; Owner: supabase_admin
--

ALTER TABLE ONLY imagery.images
    ADD CONSTRAINT images_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: point_clouds point_clouds_campaign_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: point_clouds point_clouds_location_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: point_clouds point_clouds_parent_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_parent_point_cloud_id_fkey FOREIGN KEY (parent_point_cloud_id) REFERENCES point_clouds.point_clouds(point_cloud_id) ON DELETE SET NULL;


--
-- Name: point_clouds point_clouds_process_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: point_clouds point_clouds_scanner_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_scanner_id_fkey FOREIGN KEY (scanner_id) REFERENCES point_clouds.scanners(scanner_id) ON DELETE SET NULL;


--
-- Name: point_clouds point_clouds_scenario_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: point_clouds point_clouds_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.point_clouds
    ADD CONSTRAINT point_clouds_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.variant_types(variant_type_id);


--
-- Name: scanners scanners_scanner_type_id_fkey; Type: FK CONSTRAINT; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE ONLY point_clouds.scanners
    ADD CONSTRAINT scanners_scanner_type_id_fkey FOREIGN KEY (scanner_type_id) REFERENCES point_clouds.scanner_types(scanner_type_id);


--
-- Name: sensor_readings sensor_readings_scenario_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_readings
    ADD CONSTRAINT sensor_readings_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: sensor_readings sensor_readings_sensor_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_readings
    ADD CONSTRAINT sensor_readings_sensor_id_fkey FOREIGN KEY (sensor_id) REFERENCES sensor.sensors(sensor_id) ON DELETE CASCADE;


--
-- Name: sensor_tree_links sensor_tree_links_sensor_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_sensor_id_fkey FOREIGN KEY (sensor_id) REFERENCES sensor.sensors(sensor_id) ON DELETE CASCADE;


--
-- Name: sensor_tree_links sensor_tree_links_tree_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_tree_links
    ADD CONSTRAINT sensor_tree_links_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: sensor_types sensor_types_typical_unit_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensor_types
    ADD CONSTRAINT sensor_types_typical_unit_fkey FOREIGN KEY (typical_unit) REFERENCES sensor.units(unit_name);


--
-- Name: sensors sensors_campaign_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: sensors sensors_location_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: sensors sensors_plot_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: sensors sensors_sensor_type_id_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_sensor_type_id_fkey FOREIGN KEY (sensor_type_id) REFERENCES sensor.sensor_types(sensor_type_id);


--
-- Name: sensors sensors_unit_fkey; Type: FK CONSTRAINT; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE ONLY sensor.sensors
    ADD CONSTRAINT sensors_unit_fkey FOREIGN KEY (unit) REFERENCES sensor.units(unit_name);


--
-- Name: attribute_provenance attribute_provenance_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.attribute_provenance
    ADD CONSTRAINT attribute_provenance_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: attribute_provenance attribute_provenance_process_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.attribute_provenance
    ADD CONSTRAINT attribute_provenance_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE RESTRICT;


--
-- Name: audit_log_environments audit_log_environments_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_environments
    ADD CONSTRAINT audit_log_environments_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES shared.audit_log(audit_log_id) ON DELETE CASCADE;


--
-- Name: audit_log_environments audit_log_environments_environment_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_environments
    ADD CONSTRAINT audit_log_environments_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES environments.environments(environment_id) ON DELETE CASCADE;


--
-- Name: audit_log_phenology_observations audit_log_phenology_observations_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_phenology_observations
    ADD CONSTRAINT audit_log_phenology_observations_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES shared.audit_log(audit_log_id) ON DELETE CASCADE;


--
-- Name: audit_log_phenology_observations audit_log_phenology_observations_observation_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_phenology_observations
    ADD CONSTRAINT audit_log_phenology_observations_observation_fkey FOREIGN KEY (phenology_observation_id) REFERENCES trees.phenology_observations(phenology_observation_id) ON DELETE CASCADE;


--
-- Name: audit_log_point_clouds audit_log_point_clouds_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_point_clouds
    ADD CONSTRAINT audit_log_point_clouds_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES shared.audit_log(audit_log_id) ON DELETE CASCADE;


--
-- Name: audit_log_point_clouds audit_log_point_clouds_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_point_clouds
    ADD CONSTRAINT audit_log_point_clouds_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES point_clouds.point_clouds(point_cloud_id) ON DELETE CASCADE;


--
-- Name: audit_log_stems audit_log_stems_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_stems
    ADD CONSTRAINT audit_log_stems_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES shared.audit_log(audit_log_id) ON DELETE CASCADE;


--
-- Name: audit_log_stems audit_log_stems_stem_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_stems
    ADD CONSTRAINT audit_log_stems_stem_id_fkey FOREIGN KEY (stem_id) REFERENCES trees.stems(stem_id) ON DELETE CASCADE;


--
-- Name: audit_log_trees audit_log_trees_audit_log_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_trees
    ADD CONSTRAINT audit_log_trees_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES shared.audit_log(audit_log_id) ON DELETE CASCADE;


--
-- Name: audit_log_trees audit_log_trees_tree_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.audit_log_trees
    ADD CONSTRAINT audit_log_trees_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: campaigns campaigns_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.campaigns
    ADD CONSTRAINT campaigns_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE SET NULL;


--
-- Name: campaigns campaigns_owner_team_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.campaigns
    ADD CONSTRAINT campaigns_owner_team_id_fkey FOREIGN KEY (owner_team_id) REFERENCES shared.teams(team_id) ON DELETE RESTRICT;


--
-- Name: disturbance_events disturbance_events_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.disturbance_events
    ADD CONSTRAINT disturbance_events_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: disturbance_events disturbance_events_plot_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.disturbance_events
    ADD CONSTRAINT disturbance_events_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: disturbance_events_trees disturbance_events_trees_disturbance_event_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.disturbance_events_trees
    ADD CONSTRAINT disturbance_events_trees_disturbance_event_id_fkey FOREIGN KEY (disturbance_event_id) REFERENCES shared.disturbance_events(disturbance_event_id) ON DELETE CASCADE;


--
-- Name: disturbance_events_trees disturbance_events_trees_tree_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.disturbance_events_trees
    ADD CONSTRAINT disturbance_events_trees_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: inclusion_rules inclusion_rules_sampling_design_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.inclusion_rules
    ADD CONSTRAINT inclusion_rules_sampling_design_id_fkey FOREIGN KEY (sampling_design_id) REFERENCES shared.sampling_designs(sampling_design_id) ON DELETE CASCADE;


--
-- Name: locations locations_climate_zone_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_climate_zone_id_fkey FOREIGN KEY (climate_zone_id) REFERENCES shared.climate_zones(climate_zone_id);


--
-- Name: locations locations_soil_type_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.locations
    ADD CONSTRAINT locations_soil_type_id_fkey FOREIGN KEY (soil_type_id) REFERENCES shared.soil_types(soil_type_id);


--
-- Name: management_events management_events_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.management_events
    ADD CONSTRAINT management_events_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: management_events management_events_plot_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.management_events
    ADD CONSTRAINT management_events_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: plots plots_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: plots plots_parent_plot_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_parent_plot_id_fkey FOREIGN KEY (parent_plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: plots plots_sampling_design_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_sampling_design_id_fkey FOREIGN KEY (sampling_design_id) REFERENCES shared.sampling_designs(sampling_design_id) ON DELETE SET NULL;


--
-- Name: plots plots_stratum_in_design_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.plots
    ADD CONSTRAINT plots_stratum_in_design_fkey FOREIGN KEY (stratum_id, sampling_design_id) REFERENCES shared.strata(stratum_id, sampling_design_id);


--
-- Name: process_metrics process_metrics_process_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_metrics
    ADD CONSTRAINT process_metrics_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE CASCADE;


--
-- Name: process_parameters_environments process_parameters_environments_environment_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_environments
    ADD CONSTRAINT process_parameters_environments_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES environments.environments(environment_id) ON DELETE CASCADE;


--
-- Name: process_parameters_environments process_parameters_environments_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_environments
    ADD CONSTRAINT process_parameters_environments_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.process_parameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: process_parameters_point_clouds process_parameters_point_clouds_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_point_clouds
    ADD CONSTRAINT process_parameters_point_clouds_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES point_clouds.point_clouds(point_cloud_id) ON DELETE CASCADE;


--
-- Name: process_parameters_point_clouds process_parameters_point_clouds_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_point_clouds
    ADD CONSTRAINT process_parameters_point_clouds_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.process_parameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: process_parameters_stems process_parameters_stems_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_stems
    ADD CONSTRAINT process_parameters_stems_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.process_parameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: process_parameters_stems process_parameters_stems_stem_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_stems
    ADD CONSTRAINT process_parameters_stems_stem_id_fkey FOREIGN KEY (stem_id) REFERENCES trees.stems(stem_id) ON DELETE CASCADE;


--
-- Name: process_parameters_trees process_parameters_trees_process_parameter_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_trees
    ADD CONSTRAINT process_parameters_trees_process_parameter_id_fkey FOREIGN KEY (process_parameter_id) REFERENCES shared.process_parameters(process_parameter_id) ON DELETE CASCADE;


--
-- Name: process_parameters_trees process_parameters_trees_tree_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.process_parameters_trees
    ADD CONSTRAINT process_parameters_trees_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: scenarios scenarios_climate_pathway_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_climate_pathway_id_fkey FOREIGN KEY (climate_pathway_id) REFERENCES shared.climate_pathways(climate_pathway_id);


--
-- Name: scenarios scenarios_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: scenarios scenarios_management_regime_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.scenarios
    ADD CONSTRAINT scenarios_management_regime_id_fkey FOREIGN KEY (management_regime_id) REFERENCES shared.management_regimes(management_regime_id);


--
-- Name: strata strata_sampling_design_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.strata
    ADD CONSTRAINT strata_sampling_design_id_fkey FOREIGN KEY (sampling_design_id) REFERENCES shared.sampling_designs(sampling_design_id) ON DELETE CASCADE;


--
-- Name: team_members team_members_team_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.team_members
    ADD CONSTRAINT team_members_team_id_fkey FOREIGN KEY (team_id) REFERENCES shared.teams(team_id) ON DELETE CASCADE;


--
-- Name: team_members team_members_user_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.team_members
    ADD CONSTRAINT team_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: variants variants_location_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: variants variants_parent_variant_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_parent_variant_id_fkey FOREIGN KEY (parent_variant_id) REFERENCES shared.variants(variant_id) ON DELETE SET NULL;


--
-- Name: variants variants_scenario_location_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_scenario_location_fkey FOREIGN KEY (scenario_id, location_id) REFERENCES shared.scenarios(scenario_id, location_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: variants variants_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: shared; Owner: supabase_admin
--

ALTER TABLE ONLY shared.variants
    ADD CONSTRAINT variants_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.variant_types(variant_type_id);


--
-- Name: crown_foliage_profiles crown_foliage_profiles_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_foliage_profiles
    ADD CONSTRAINT crown_foliage_profiles_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: crown_foliage_profiles crown_foliage_profiles_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.crown_foliage_profiles
    ADD CONSTRAINT crown_foliage_profiles_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: entity_matches entity_matches_observation_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.entity_matches
    ADD CONSTRAINT entity_matches_observation_id_fkey FOREIGN KEY (observation_id) REFERENCES trees.observations(observation_id) ON DELETE CASCADE;


--
-- Name: entity_matches entity_matches_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.entity_matches
    ADD CONSTRAINT entity_matches_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: entity_matches entity_matches_reference_campaign_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.entity_matches
    ADD CONSTRAINT entity_matches_reference_campaign_id_fkey FOREIGN KEY (reference_campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: entity_matches entity_matches_supersedes_same_observation_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.entity_matches
    ADD CONSTRAINT entity_matches_supersedes_same_observation_fkey FOREIGN KEY (supersedes_entity_match_id, observation_id) REFERENCES trees.entity_matches(entity_match_id, observation_id) ON DELETE RESTRICT;


--
-- Name: growth_simulations growth_simulations_base_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations
    ADD CONSTRAINT growth_simulations_base_tree_id_fkey FOREIGN KEY (base_tree_id) REFERENCES trees.trees(tree_id) ON DELETE SET NULL;


--
-- Name: growth_simulations growth_simulations_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations
    ADD CONSTRAINT growth_simulations_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: growth_simulations growth_simulations_plot_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations
    ADD CONSTRAINT growth_simulations_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: growth_simulations growth_simulations_scenario_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations
    ADD CONSTRAINT growth_simulations_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: growth_simulations growth_simulations_simulation_run_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations
    ADD CONSTRAINT growth_simulations_simulation_run_id_fkey FOREIGN KEY (simulation_run_id) REFERENCES trees.simulation_runs(simulation_run_id) ON DELETE CASCADE;


--
-- Name: growth_simulations growth_simulations_species_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.growth_simulations
    ADD CONSTRAINT growth_simulations_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: observations observations_campaign_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations
    ADD CONSTRAINT observations_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE RESTRICT;


--
-- Name: observations observations_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations
    ADD CONSTRAINT observations_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: observations observations_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations
    ADD CONSTRAINT observations_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES point_clouds.point_clouds(point_cloud_id) ON DELETE SET NULL;


--
-- Name: observations observations_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations
    ADD CONSTRAINT observations_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: observations observations_species_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations
    ADD CONSTRAINT observations_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: observations observations_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.observations
    ADD CONSTRAINT observations_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE SET NULL;


--
-- Name: phenology_observations phenology_observations_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.phenology_observations
    ADD CONSTRAINT phenology_observations_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: qsm_cylinders qsm_cylinders_part_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsm_cylinders
    ADD CONSTRAINT qsm_cylinders_part_type_id_fkey FOREIGN KEY (part_type_id) REFERENCES trees.tree_part_types(part_type_id);


--
-- Name: qsm_cylinders qsm_cylinders_qsm_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsm_cylinders
    ADD CONSTRAINT qsm_cylinders_qsm_id_fkey FOREIGN KEY (qsm_id) REFERENCES trees.qsms(qsm_id) ON DELETE CASCADE;


--
-- Name: qsms qsms_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES point_clouds.point_clouds(point_cloud_id) ON DELETE SET NULL;


--
-- Name: qsms qsms_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: qsms qsms_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: roots roots_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: roots roots_root_system_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_root_system_type_id_fkey FOREIGN KEY (root_system_type_id) REFERENCES trees.root_system_types(root_system_type_id);


--
-- Name: roots roots_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: simulation_runs simulation_runs_base_variant_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.simulation_runs
    ADD CONSTRAINT simulation_runs_base_variant_id_fkey FOREIGN KEY (base_variant_id) REFERENCES shared.variants(variant_id) ON DELETE SET NULL;


--
-- Name: simulation_runs simulation_runs_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.simulation_runs
    ADD CONSTRAINT simulation_runs_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: simulation_runs simulation_runs_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.simulation_runs
    ADD CONSTRAINT simulation_runs_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: simulation_runs simulation_runs_scenario_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.simulation_runs
    ADD CONSTRAINT simulation_runs_scenario_id_fkey FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;


--
-- Name: stems stems_straightness_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_straightness_type_id_fkey FOREIGN KEY (straightness_type_id) REFERENCES trees.straightness_types(straightness_type_id);


--
-- Name: stems stems_taper_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_taper_type_id_fkey FOREIGN KEY (taper_type_id) REFERENCES trees.taper_types(taper_type_id);


--
-- Name: stems stems_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.stems
    ADD CONSTRAINT stems_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;


--
-- Name: tree_graph_edges tree_graph_edges_qsm_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.tree_graph_edges
    ADD CONSTRAINT tree_graph_edges_qsm_id_fkey FOREIGN KEY (qsm_id) REFERENCES trees.qsms(qsm_id) ON DELETE CASCADE;


--
-- Name: trees trees_axis_structure_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_axis_structure_id_fkey FOREIGN KEY (axis_structure_id) REFERENCES trees.axis_structures(axis_structure_id);


--
-- Name: trees trees_bark_characteristic_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_bark_characteristic_id_fkey FOREIGN KEY (bark_characteristic_id) REFERENCES trees.bark_characteristics(bark_characteristic_id);


--
-- Name: trees trees_branching_pattern_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_branching_pattern_id_fkey FOREIGN KEY (branching_pattern_id) REFERENCES trees.branching_patterns(branching_pattern_id);


--
-- Name: trees trees_campaign_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES shared.campaigns(campaign_id) ON DELETE SET NULL;


--
-- Name: trees trees_crown_architecture_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_crown_architecture_id_fkey FOREIGN KEY (crown_architecture_id) REFERENCES trees.crown_architectures(crown_architecture_id);


--
-- Name: trees trees_crown_class_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_crown_class_id_fkey FOREIGN KEY (crown_class_id) REFERENCES trees.crown_classes(crown_class_id);


--
-- Name: trees trees_crown_shape_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_crown_shape_id_fkey FOREIGN KEY (crown_shape_id) REFERENCES trees.crown_shapes(crown_shape_id);


--
-- Name: trees trees_damage_agent_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_damage_agent_id_fkey FOREIGN KEY (damage_agent_id) REFERENCES trees.damage_agents(damage_agent_id);


--
-- Name: trees trees_data_source_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_data_source_type_id_fkey FOREIGN KEY (data_source_type_id) REFERENCES trees.data_source_types(data_source_type_id) ON DELETE SET NULL;


--
-- Name: trees trees_elongation_habit_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_elongation_habit_id_fkey FOREIGN KEY (elongation_habit_id) REFERENCES trees.branch_elongation_habits(elongation_habit_id);


--
-- Name: trees trees_geometric_crown_solid_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_geometric_crown_solid_id_fkey FOREIGN KEY (geometric_crown_solid_id) REFERENCES trees.geometric_crown_solids(geometric_crown_solid_id);


--
-- Name: trees trees_growth_form_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_growth_form_id_fkey FOREIGN KEY (growth_form_id) REFERENCES trees.growth_forms(growth_form_id);


--
-- Name: trees trees_growth_orientation_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_growth_orientation_id_fkey FOREIGN KEY (growth_orientation_id) REFERENCES trees.growth_orientations(growth_orientation_id);


--
-- Name: trees trees_height_class_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_height_class_id_fkey FOREIGN KEY (height_class_id) REFERENCES trees.phanerophyte_height_classes(height_class_id);


--
-- Name: trees trees_location_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_location_id_fkey FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;


--
-- Name: trees trees_parent_tree_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_parent_tree_id_fkey FOREIGN KEY (parent_tree_id) REFERENCES trees.trees(tree_id) ON DELETE SET NULL;


--
-- Name: trees trees_plot_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES shared.plots(plot_id) ON DELETE SET NULL;


--
-- Name: trees trees_point_cloud_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES point_clouds.point_clouds(point_cloud_id) ON DELETE SET NULL;


--
-- Name: trees trees_process_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;


--
-- Name: trees trees_shoot_elongation_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_shoot_elongation_type_id_fkey FOREIGN KEY (shoot_elongation_type_id) REFERENCES trees.shoot_elongation_types(shoot_elongation_type_id);


--
-- Name: trees trees_species_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_species_id_fkey FOREIGN KEY (species_id) REFERENCES shared.species(species_id) ON DELETE SET NULL;


--
-- Name: trees trees_tree_status_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_tree_status_id_fkey FOREIGN KEY (tree_status_id) REFERENCES trees.tree_status(tree_status_id);


--
-- Name: trees trees_variant_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_variant_fkey FOREIGN KEY (variant_id, scenario_id, location_id, variant_type_id) REFERENCES shared.variants(variant_id, scenario_id, location_id, variant_type_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: trees trees_variant_type_id_fkey; Type: FK CONSTRAINT; Schema: trees; Owner: supabase_admin
--

ALTER TABLE ONLY trees.trees
    ADD CONSTRAINT trees_variant_type_id_fkey FOREIGN KEY (variant_type_id) REFERENCES shared.variant_types(variant_type_id);


--
-- Name: environments Contributors can create environments; Type: POLICY; Schema: environments; Owner: supabase_admin
--

CREATE POLICY "Contributors can create environments" ON environments.environments FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: environments Curators can delete environments; Type: POLICY; Schema: environments; Owner: supabase_admin
--

CREATE POLICY "Curators can delete environments" ON environments.environments FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: environments Curators can update environments; Type: POLICY; Schema: environments; Owner: supabase_admin
--

CREATE POLICY "Curators can update environments" ON environments.environments FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: environments Environments are viewable by everyone; Type: POLICY; Schema: environments; Owner: supabase_admin
--

CREATE POLICY "Environments are viewable by everyone" ON environments.environments FOR SELECT USING (true);


--
-- Name: POLICY "Environments are viewable by everyone" ON environments; Type: COMMENT; Schema: environments; Owner: supabase_admin
--

COMMENT ON POLICY "Environments are viewable by everyone" ON environments.environments IS 'Public read access to environmental conditions';


--
-- Name: environments Service role can manage all environments; Type: POLICY; Schema: environments; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all environments" ON environments.environments TO service_role USING (true) WITH CHECK (true);


--
-- Name: environments; Type: ROW SECURITY; Schema: environments; Owner: supabase_admin
--

ALTER TABLE environments.environments ENABLE ROW LEVEL SECURITY;

--
-- Name: deadwood Contributors can create deadwood records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Contributors can create deadwood records" ON forest_floor.deadwood FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: ground_vegetation Contributors can create ground vegetation records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Contributors can create ground vegetation records" ON forest_floor.ground_vegetation FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: regeneration Contributors can create regeneration records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Contributors can create regeneration records" ON forest_floor.regeneration FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: deadwood Curators can delete deadwood records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Curators can delete deadwood records" ON forest_floor.deadwood FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: ground_vegetation Curators can delete ground vegetation records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Curators can delete ground vegetation records" ON forest_floor.ground_vegetation FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: regeneration Curators can delete regeneration records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Curators can delete regeneration records" ON forest_floor.regeneration FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: deadwood Curators can update deadwood records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Curators can update deadwood records" ON forest_floor.deadwood FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: ground_vegetation Curators can update ground vegetation records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Curators can update ground vegetation records" ON forest_floor.ground_vegetation FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: regeneration Curators can update regeneration records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Curators can update regeneration records" ON forest_floor.regeneration FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: deadwood Dataset access level; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON forest_floor.deadwood AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR ((tree_id IS NULL) OR (NOT (tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids))))));


--
-- Name: ground_vegetation Dataset access level; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON forest_floor.ground_vegetation AS RESTRICTIVE FOR SELECT USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids))));


--
-- Name: regeneration Dataset access level; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON forest_floor.regeneration AS RESTRICTIVE FOR SELECT USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids))));


--
-- Name: deadwood Dataset access level: campaign; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset access level: campaign" ON forest_floor.deadwood AS RESTRICTIVE FOR SELECT USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids))));


--
-- Name: deadwood Dataset owner: delete; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON forest_floor.deadwood AS RESTRICTIVE FOR DELETE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: ground_vegetation Dataset owner: delete; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON forest_floor.ground_vegetation AS RESTRICTIVE FOR DELETE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: regeneration Dataset owner: delete; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON forest_floor.regeneration AS RESTRICTIVE FOR DELETE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: deadwood Dataset owner: insert; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON forest_floor.deadwood AS RESTRICTIVE FOR INSERT WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: ground_vegetation Dataset owner: insert; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON forest_floor.ground_vegetation AS RESTRICTIVE FOR INSERT WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: regeneration Dataset owner: insert; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON forest_floor.regeneration AS RESTRICTIVE FOR INSERT WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: deadwood Dataset owner: update; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON forest_floor.deadwood AS RESTRICTIVE FOR UPDATE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)))) WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: ground_vegetation Dataset owner: update; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON forest_floor.ground_vegetation AS RESTRICTIVE FOR UPDATE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)))) WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: regeneration Dataset owner: update; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON forest_floor.regeneration AS RESTRICTIVE FOR UPDATE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)))) WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: deadwood Deadwood records are viewable by everyone; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Deadwood records are viewable by everyone" ON forest_floor.deadwood FOR SELECT USING (true);


--
-- Name: ground_vegetation Ground vegetation records are viewable by everyone; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Ground vegetation records are viewable by everyone" ON forest_floor.ground_vegetation FOR SELECT USING (true);


--
-- Name: regeneration Regeneration records are viewable by everyone; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Regeneration records are viewable by everyone" ON forest_floor.regeneration FOR SELECT USING (true);


--
-- Name: deadwood Service role can manage all deadwood records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all deadwood records" ON forest_floor.deadwood TO service_role USING (true) WITH CHECK (true);


--
-- Name: ground_vegetation Service role can manage all ground vegetation; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all ground vegetation" ON forest_floor.ground_vegetation TO service_role USING (true) WITH CHECK (true);


--
-- Name: regeneration Service role can manage all regeneration records; Type: POLICY; Schema: forest_floor; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all regeneration records" ON forest_floor.regeneration TO service_role USING (true) WITH CHECK (true);


--
-- Name: deadwood; Type: ROW SECURITY; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE forest_floor.deadwood ENABLE ROW LEVEL SECURITY;

--
-- Name: ground_vegetation; Type: ROW SECURITY; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE forest_floor.ground_vegetation ENABLE ROW LEVEL SECURITY;

--
-- Name: regeneration; Type: ROW SECURITY; Schema: forest_floor; Owner: supabase_admin
--

ALTER TABLE forest_floor.regeneration ENABLE ROW LEVEL SECURITY;

--
-- Name: images Contributors can create images; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Contributors can create images" ON imagery.images FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: images Curators can delete images; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Curators can delete images" ON imagery.images FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: images Curators can update images; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Curators can update images" ON imagery.images FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: images Dataset access level; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON imagery.images AS RESTRICTIVE FOR SELECT USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids))));


--
-- Name: images Dataset owner: delete; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON imagery.images AS RESTRICTIVE FOR DELETE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: images Dataset owner: insert; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON imagery.images AS RESTRICTIVE FOR INSERT WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: images Dataset owner: update; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON imagery.images AS RESTRICTIVE FOR UPDATE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)))) WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: images Images are viewable by everyone; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Images are viewable by everyone" ON imagery.images FOR SELECT USING (true);


--
-- Name: images Service role can manage all images; Type: POLICY; Schema: imagery; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all images" ON imagery.images TO service_role USING (true) WITH CHECK (true);


--
-- Name: images; Type: ROW SECURITY; Schema: imagery; Owner: supabase_admin
--

ALTER TABLE imagery.images ENABLE ROW LEVEL SECURITY;

--
-- Name: point_clouds Contributors can create point clouds; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Contributors can create point clouds" ON point_clouds.point_clouds FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: scanners Contributors can manage scanners; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage scanners" ON point_clouds.scanners TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: point_clouds Curators can delete point clouds; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Curators can delete point clouds" ON point_clouds.point_clouds FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: point_clouds Curators can update point clouds; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Curators can update point clouds" ON point_clouds.point_clouds FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: point_clouds Dataset access level; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON point_clouds.point_clouds AS RESTRICTIVE FOR SELECT USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids))));


--
-- Name: point_clouds Dataset owner: delete; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON point_clouds.point_clouds AS RESTRICTIVE FOR DELETE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: point_clouds Dataset owner: insert; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON point_clouds.point_clouds AS RESTRICTIVE FOR INSERT WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: point_clouds Dataset owner: update; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON point_clouds.point_clouds AS RESTRICTIVE FOR UPDATE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)))) WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: point_clouds Point clouds are viewable by everyone; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Point clouds are viewable by everyone" ON point_clouds.point_clouds FOR SELECT USING (true);


--
-- Name: POLICY "Point clouds are viewable by everyone" ON point_clouds; Type: COMMENT; Schema: point_clouds; Owner: supabase_admin
--

COMMENT ON POLICY "Point clouds are viewable by everyone" ON point_clouds.point_clouds IS 'Public read access to point cloud metadata';


--
-- Name: scanner_types Scanner types are viewable by everyone; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Scanner types are viewable by everyone" ON point_clouds.scanner_types FOR SELECT USING (true);


--
-- Name: scanners Scanners are viewable by everyone; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Scanners are viewable by everyone" ON point_clouds.scanners FOR SELECT USING (true);


--
-- Name: point_clouds Service role can manage all point clouds; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all point clouds" ON point_clouds.point_clouds TO service_role USING (true) WITH CHECK (true);


--
-- Name: scanners Service role can manage all scanners; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all scanners" ON point_clouds.scanners TO service_role USING (true) WITH CHECK (true);


--
-- Name: scanner_types Service role can manage scanner types; Type: POLICY; Schema: point_clouds; Owner: supabase_admin
--

CREATE POLICY "Service role can manage scanner types" ON point_clouds.scanner_types TO service_role USING (true) WITH CHECK (true);


--
-- Name: point_clouds; Type: ROW SECURITY; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE point_clouds.point_clouds ENABLE ROW LEVEL SECURITY;

--
-- Name: scanner_types; Type: ROW SECURITY; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE point_clouds.scanner_types ENABLE ROW LEVEL SECURITY;

--
-- Name: scanners; Type: ROW SECURITY; Schema: point_clouds; Owner: supabase_admin
--

ALTER TABLE point_clouds.scanners ENABLE ROW LEVEL SECURITY;

--
-- Name: sensor_readings Contributors can insert sensor readings; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Contributors can insert sensor readings" ON sensor.sensor_readings FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: sensors Contributors can manage sensors; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage sensors" ON sensor.sensors TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: sensor_readings Dataset access level; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON sensor.sensor_readings AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (sensor_id IN ( SELECT shared.hidden_sensor_ids() AS hidden_sensor_ids)))));


--
-- Name: sensor_tree_links Dataset access level; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON sensor.sensor_tree_links AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR ((NOT (sensor_id IN ( SELECT shared.hidden_sensor_ids() AS hidden_sensor_ids))) AND (NOT (tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids))))));


--
-- Name: sensors Dataset access level; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON sensor.sensors AS RESTRICTIVE FOR SELECT USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids))));


--
-- Name: sensors Dataset owner: delete; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON sensor.sensors AS RESTRICTIVE FOR DELETE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: sensor_readings Dataset owner: insert; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON sensor.sensor_readings AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT (sensor_id IN ( SELECT shared.unwritable_sensor_ids() AS unwritable_sensor_ids))));


--
-- Name: sensors Dataset owner: insert; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON sensor.sensors AS RESTRICTIVE FOR INSERT WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: sensors Dataset owner: update; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON sensor.sensors AS RESTRICTIVE FOR UPDATE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)))) WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: sensor_readings Sensor readings are viewable by everyone; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Sensor readings are viewable by everyone" ON sensor.sensor_readings FOR SELECT USING (true);


--
-- Name: sensor_tree_links Sensor tree links are viewable by everyone; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Sensor tree links are viewable by everyone" ON sensor.sensor_tree_links FOR SELECT USING (true);


--
-- Name: sensor_types Sensor types are viewable by everyone; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Sensor types are viewable by everyone" ON sensor.sensor_types FOR SELECT USING (true);


--
-- Name: sensors Sensors are viewable by everyone; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Sensors are viewable by everyone" ON sensor.sensors FOR SELECT USING (true);


--
-- Name: sensor_readings Service role can manage all sensor readings; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all sensor readings" ON sensor.sensor_readings TO service_role USING (true) WITH CHECK (true);


--
-- Name: sensor_tree_links Service role can manage all sensor tree links; Type: POLICY; Schema: sensor; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all sensor tree links" ON sensor.sensor_tree_links TO service_role USING (true) WITH CHECK (true);


--
-- Name: sensor_readings; Type: ROW SECURITY; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE sensor.sensor_readings ENABLE ROW LEVEL SECURITY;

--
-- Name: sensor_tree_links; Type: ROW SECURITY; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE sensor.sensor_tree_links ENABLE ROW LEVEL SECURITY;

--
-- Name: sensor_types; Type: ROW SECURITY; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE sensor.sensor_types ENABLE ROW LEVEL SECURITY;

--
-- Name: sensors; Type: ROW SECURITY; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE sensor.sensors ENABLE ROW LEVEL SECURITY;

--
-- Name: attribute_provenance Attribute provenance is viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Attribute provenance is viewable by everyone" ON shared.attribute_provenance FOR SELECT USING (true);


--
-- Name: audit_log_environments Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.audit_log_environments FOR SELECT TO authenticated USING (true);


--
-- Name: audit_log_point_clouds Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.audit_log_point_clouds FOR SELECT TO authenticated USING (true);


--
-- Name: audit_log_stems Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.audit_log_stems FOR SELECT TO authenticated USING (true);


--
-- Name: audit_log_trees Audit links viewable by authenticated users; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Audit links viewable by authenticated users" ON shared.audit_log_trees FOR SELECT TO authenticated USING (true);


--
-- Name: campaigns Campaigns are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Campaigns are viewable by everyone" ON shared.campaigns FOR SELECT USING (true);


--
-- Name: climate_pathways Climate pathways are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Climate pathways are viewable by everyone" ON shared.climate_pathways FOR SELECT USING (true);


--
-- Name: locations Contributors can insert locations; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can insert locations" ON shared.locations FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: campaigns Contributors can manage campaigns; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage campaigns" ON shared.campaigns TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: disturbance_events Contributors can manage disturbance events; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage disturbance events" ON shared.disturbance_events TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: disturbance_events_trees Contributors can manage disturbance tree links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage disturbance tree links" ON shared.disturbance_events_trees TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: inclusion_rules Contributors can manage inclusion rules; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage inclusion rules" ON shared.inclusion_rules TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: management_events Contributors can manage management events; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage management events" ON shared.management_events TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: plots Contributors can manage plots; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage plots" ON shared.plots TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: process_metrics Contributors can manage process metrics; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage process metrics" ON shared.process_metrics TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: process_parameters_environments Contributors can manage process parameter links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage process parameter links" ON shared.process_parameters_environments TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: process_parameters_point_clouds Contributors can manage process parameter links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage process parameter links" ON shared.process_parameters_point_clouds TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: process_parameters_stems Contributors can manage process parameter links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage process parameter links" ON shared.process_parameters_stems TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: process_parameters_trees Contributors can manage process parameter links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage process parameter links" ON shared.process_parameters_trees TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: process_parameters Contributors can manage process parameters; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage process parameters" ON shared.process_parameters TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: processes Contributors can manage processes; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage processes" ON shared.processes TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: sampling_designs Contributors can manage sampling designs; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage sampling designs" ON shared.sampling_designs TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: scenarios Contributors can manage scenarios; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage scenarios" ON shared.scenarios TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: species Contributors can manage species; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage species" ON shared.species TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: strata Contributors can manage strata; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can manage strata" ON shared.strata TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: attribute_provenance Contributors can record attribute provenance; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can record attribute provenance" ON shared.attribute_provenance FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: attribute_provenance Contributors can update attribute provenance; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can update attribute provenance" ON shared.attribute_provenance FOR UPDATE TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: locations Contributors can update locations; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Contributors can update locations" ON shared.locations FOR UPDATE TO authenticated USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());


--
-- Name: attribute_provenance Curators can delete attribute provenance; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Curators can delete attribute provenance" ON shared.attribute_provenance FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: climate_pathways Curators can manage climate pathways; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Curators can manage climate pathways" ON shared.climate_pathways TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: management_regimes Curators can manage management regimes; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Curators can manage management regimes" ON shared.management_regimes TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: account_events Curators can read account events; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Curators can read account events" ON shared.account_events FOR SELECT TO authenticated USING (shared.is_curator());


--
-- Name: teams Curators manage teams; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Curators manage teams" ON shared.teams TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: audit_log Curators read all, others their own changes; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Curators read all, others their own changes" ON shared.audit_log FOR SELECT TO authenticated USING ((shared.is_curator() OR ((user_id)::text = (( SELECT auth.uid() AS uid))::text)));


--
-- Name: disturbance_events Disturbance events are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Disturbance events are viewable by everyone" ON shared.disturbance_events FOR SELECT USING (true);


--
-- Name: disturbance_events_trees Disturbance tree links are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Disturbance tree links are viewable by everyone" ON shared.disturbance_events_trees FOR SELECT USING (true);


--
-- Name: processing_jobs Enable all for service_role; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Enable all for service_role" ON shared.processing_jobs TO service_role USING (true) WITH CHECK (true);


--
-- Name: inclusion_rules Inclusion rules are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Inclusion rules are viewable by everyone" ON shared.inclusion_rules FOR SELECT USING (true);


--
-- Name: locations Locations are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Locations are viewable by everyone" ON shared.locations FOR SELECT USING (true);


--
-- Name: POLICY "Locations are viewable by everyone" ON locations; Type: COMMENT; Schema: shared; Owner: supabase_admin
--

COMMENT ON POLICY "Locations are viewable by everyone" ON shared.locations IS 'Public read access to location data';


--
-- Name: management_events Management events are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Management events are viewable by everyone" ON shared.management_events FOR SELECT USING (true);


--
-- Name: management_regimes Management regimes are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Management regimes are viewable by everyone" ON shared.management_regimes FOR SELECT USING (true);


--
-- Name: team_members Members see their teams, curators see all; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Members see their teams, curators see all" ON shared.team_members FOR SELECT TO authenticated USING ((shared.is_curator() OR (team_id IN ( SELECT shared.my_team_ids() AS my_team_ids))));


--
-- Name: plots Plots are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Plots are viewable by everyone" ON shared.plots FOR SELECT USING (true);


--
-- Name: process_metrics Process metrics are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Process metrics are viewable by everyone" ON shared.process_metrics FOR SELECT USING (true);


--
-- Name: process_parameters_environments Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.process_parameters_environments FOR SELECT USING (true);


--
-- Name: process_parameters_point_clouds Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.process_parameters_point_clouds FOR SELECT USING (true);


--
-- Name: process_parameters_stems Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.process_parameters_stems FOR SELECT USING (true);


--
-- Name: process_parameters_trees Process parameter links are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Process parameter links are viewable by everyone" ON shared.process_parameters_trees FOR SELECT USING (true);


--
-- Name: process_parameters Process parameters are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Process parameters are viewable by everyone" ON shared.process_parameters FOR SELECT USING (true);


--
-- Name: processes Processes are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Processes are viewable by everyone" ON shared.processes FOR SELECT USING (true);


--
-- Name: climate_zones Reference tables are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Reference tables are viewable by everyone" ON shared.climate_zones FOR SELECT USING (true);


--
-- Name: soil_types Reference tables are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Reference tables are viewable by everyone" ON shared.soil_types FOR SELECT USING (true);


--
-- Name: variant_types Reference tables are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Reference tables are viewable by everyone" ON shared.variant_types FOR SELECT USING (true);


--
-- Name: sampling_designs Sampling designs are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Sampling designs are viewable by everyone" ON shared.sampling_designs FOR SELECT USING (true);


--
-- Name: scenarios Scenarios are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Scenarios are viewable by everyone" ON shared.scenarios FOR SELECT USING (true);


--
-- Name: attribute_provenance Service role can manage all attribute provenance; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all attribute provenance" ON shared.attribute_provenance TO service_role USING (true) WITH CHECK (true);


--
-- Name: campaigns Service role can manage all campaigns; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all campaigns" ON shared.campaigns TO service_role USING (true) WITH CHECK (true);


--
-- Name: climate_pathways Service role can manage all climate pathways; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all climate pathways" ON shared.climate_pathways TO service_role USING (true) WITH CHECK (true);


--
-- Name: disturbance_events Service role can manage all disturbance events; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all disturbance events" ON shared.disturbance_events TO service_role USING (true) WITH CHECK (true);


--
-- Name: disturbance_events_trees Service role can manage all disturbance tree links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all disturbance tree links" ON shared.disturbance_events_trees TO service_role USING (true) WITH CHECK (true);


--
-- Name: inclusion_rules Service role can manage all inclusion rules; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all inclusion rules" ON shared.inclusion_rules TO service_role USING (true) WITH CHECK (true);


--
-- Name: management_events Service role can manage all management events; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all management events" ON shared.management_events TO service_role USING (true) WITH CHECK (true);


--
-- Name: management_regimes Service role can manage all management regimes; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all management regimes" ON shared.management_regimes TO service_role USING (true) WITH CHECK (true);


--
-- Name: plots Service role can manage all plots; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all plots" ON shared.plots TO service_role USING (true) WITH CHECK (true);


--
-- Name: sampling_designs Service role can manage all sampling designs; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all sampling designs" ON shared.sampling_designs TO service_role USING (true) WITH CHECK (true);


--
-- Name: strata Service role can manage all strata; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all strata" ON shared.strata TO service_role USING (true) WITH CHECK (true);


--
-- Name: team_members Service role can manage all team members; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all team members" ON shared.team_members TO service_role USING (true) WITH CHECK (true);


--
-- Name: teams Service role can manage all teams; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all teams" ON shared.teams TO service_role USING (true) WITH CHECK (true);


--
-- Name: audit_log_environments Service role can manage audit links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage audit links" ON shared.audit_log_environments TO service_role USING (true) WITH CHECK (true);


--
-- Name: audit_log_point_clouds Service role can manage audit links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage audit links" ON shared.audit_log_point_clouds TO service_role USING (true) WITH CHECK (true);


--
-- Name: audit_log_stems Service role can manage audit links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage audit links" ON shared.audit_log_stems TO service_role USING (true) WITH CHECK (true);


--
-- Name: audit_log_trees Service role can manage audit links; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage audit links" ON shared.audit_log_trees TO service_role USING (true) WITH CHECK (true);


--
-- Name: audit_log Service role can manage audit logs; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Service role can manage audit logs" ON shared.audit_log TO service_role USING (true) WITH CHECK (true);


--
-- Name: species Species are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Species are viewable by everyone" ON shared.species FOR SELECT USING (true);


--
-- Name: strata Strata are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Strata are viewable by everyone" ON shared.strata FOR SELECT USING (true);


--
-- Name: processing_jobs Submitters read own jobs, curators read all; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Submitters read own jobs, curators read all" ON shared.processing_jobs FOR SELECT TO authenticated USING ((((submitted_by)::text = (( SELECT auth.uid() AS uid))::text) OR shared.is_curator()));


--
-- Name: campaigns Team campaigns: change own team's; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Team campaigns: change own team's" ON shared.campaigns AS RESTRICTIVE FOR UPDATE USING (((owner_team_id IS NULL) OR shared.is_curator() OR (owner_team_id IN ( SELECT shared.my_team_ids() AS my_team_ids)))) WITH CHECK (((owner_team_id IS NULL) OR shared.is_curator() OR (owner_team_id IN ( SELECT shared.my_team_ids() AS my_team_ids))));


--
-- Name: campaigns Team campaigns: create for own team; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Team campaigns: create for own team" ON shared.campaigns AS RESTRICTIVE FOR INSERT WITH CHECK (((owner_team_id IS NULL) OR shared.is_curator() OR (owner_team_id IN ( SELECT shared.my_team_ids() AS my_team_ids))));


--
-- Name: campaigns Team campaigns: delete own team's; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Team campaigns: delete own team's" ON shared.campaigns AS RESTRICTIVE FOR DELETE USING (((owner_team_id IS NULL) OR shared.is_curator() OR (owner_team_id IN ( SELECT shared.my_team_ids() AS my_team_ids))));


--
-- Name: teams Teams are viewable by everyone; Type: POLICY; Schema: shared; Owner: supabase_admin
--

CREATE POLICY "Teams are viewable by everyone" ON shared.teams FOR SELECT USING (true);


--
-- Name: account_events; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.account_events ENABLE ROW LEVEL SECURITY;

--
-- Name: attribute_provenance; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.attribute_provenance ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log_environments; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.audit_log_environments ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log_point_clouds; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.audit_log_point_clouds ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log_stems; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.audit_log_stems ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log_trees; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.audit_log_trees ENABLE ROW LEVEL SECURITY;

--
-- Name: campaigns; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.campaigns ENABLE ROW LEVEL SECURITY;

--
-- Name: climate_pathways; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.climate_pathways ENABLE ROW LEVEL SECURITY;

--
-- Name: climate_zones; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.climate_zones ENABLE ROW LEVEL SECURITY;

--
-- Name: disturbance_events; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.disturbance_events ENABLE ROW LEVEL SECURITY;

--
-- Name: disturbance_events_trees; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.disturbance_events_trees ENABLE ROW LEVEL SECURITY;

--
-- Name: inclusion_rules; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.inclusion_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: locations; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.locations ENABLE ROW LEVEL SECURITY;

--
-- Name: management_events; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.management_events ENABLE ROW LEVEL SECURITY;

--
-- Name: management_regimes; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.management_regimes ENABLE ROW LEVEL SECURITY;

--
-- Name: plots; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.plots ENABLE ROW LEVEL SECURITY;

--
-- Name: process_metrics; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.process_metrics ENABLE ROW LEVEL SECURITY;

--
-- Name: process_parameters; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.process_parameters ENABLE ROW LEVEL SECURITY;

--
-- Name: process_parameters_environments; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.process_parameters_environments ENABLE ROW LEVEL SECURITY;

--
-- Name: process_parameters_point_clouds; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.process_parameters_point_clouds ENABLE ROW LEVEL SECURITY;

--
-- Name: process_parameters_stems; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.process_parameters_stems ENABLE ROW LEVEL SECURITY;

--
-- Name: process_parameters_trees; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.process_parameters_trees ENABLE ROW LEVEL SECURITY;

--
-- Name: processes; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.processes ENABLE ROW LEVEL SECURITY;

--
-- Name: processing_jobs; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.processing_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: sampling_designs; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.sampling_designs ENABLE ROW LEVEL SECURITY;

--
-- Name: scenarios; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.scenarios ENABLE ROW LEVEL SECURITY;

--
-- Name: soil_types; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.soil_types ENABLE ROW LEVEL SECURITY;

--
-- Name: species; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.species ENABLE ROW LEVEL SECURITY;

--
-- Name: strata; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.strata ENABLE ROW LEVEL SECURITY;

--
-- Name: team_members; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.team_members ENABLE ROW LEVEL SECURITY;

--
-- Name: teams; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.teams ENABLE ROW LEVEL SECURITY;

--
-- Name: variant_types; Type: ROW SECURITY; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.variant_types ENABLE ROW LEVEL SECURITY;

--
-- Name: entity_matches Contributors can create; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create" ON trees.entity_matches FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: observations Contributors can create; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create" ON trees.observations FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: qsm_cylinders Contributors can create QSM cylinders; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create QSM cylinders" ON trees.qsm_cylinders FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: qsms Contributors can create QSMs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create QSMs" ON trees.qsms FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: crown_foliage_profiles Contributors can create crown foliage profiles; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create crown foliage profiles" ON trees.crown_foliage_profiles FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: phenology_observations Contributors can create phenology observations; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create phenology observations" ON trees.phenology_observations FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: roots Contributors can create roots; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create roots" ON trees.roots FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: simulation_runs Contributors can create simulation runs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create simulation runs" ON trees.simulation_runs FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: stems Contributors can create stems; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create stems" ON trees.stems FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: tree_graph_edges Contributors can create tree graph edges; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create tree graph edges" ON trees.tree_graph_edges FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: trees Contributors can create trees; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Contributors can create trees" ON trees.trees FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());


--
-- Name: crown_foliage_profiles Crown foliage profiles are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Crown foliage profiles are viewable by everyone" ON trees.crown_foliage_profiles FOR SELECT USING (true);


--
-- Name: entity_matches Curators can delete; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete" ON trees.entity_matches FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: observations Curators can delete; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete" ON trees.observations FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: qsm_cylinders Curators can delete QSM cylinders; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete QSM cylinders" ON trees.qsm_cylinders FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: qsms Curators can delete QSMs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete QSMs" ON trees.qsms FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: crown_foliage_profiles Curators can delete crown foliage profiles; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete crown foliage profiles" ON trees.crown_foliage_profiles FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: phenology_observations Curators can delete phenology observations; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete phenology observations" ON trees.phenology_observations FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: roots Curators can delete roots; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete roots" ON trees.roots FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: simulation_runs Curators can delete simulation runs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete simulation runs" ON trees.simulation_runs FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: stems Curators can delete stems; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete stems" ON trees.stems FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: tree_graph_edges Curators can delete tree graph edges; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete tree graph edges" ON trees.tree_graph_edges FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: trees Curators can delete trees; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can delete trees" ON trees.trees FOR DELETE TO authenticated USING (shared.is_curator());


--
-- Name: entity_matches Curators can update; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update" ON trees.entity_matches FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: observations Curators can update; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update" ON trees.observations FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: qsm_cylinders Curators can update QSM cylinders; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update QSM cylinders" ON trees.qsm_cylinders FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: qsms Curators can update QSMs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update QSMs" ON trees.qsms FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: crown_foliage_profiles Curators can update crown foliage profiles; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update crown foliage profiles" ON trees.crown_foliage_profiles FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: phenology_observations Curators can update phenology observations; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update phenology observations" ON trees.phenology_observations FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: roots Curators can update roots; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update roots" ON trees.roots FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: simulation_runs Curators can update simulation runs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update simulation runs" ON trees.simulation_runs FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: stems Curators can update stems; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update stems" ON trees.stems FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: tree_graph_edges Curators can update tree graph edges; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update tree graph edges" ON trees.tree_graph_edges FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: trees Curators can update trees; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Curators can update trees" ON trees.trees FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());


--
-- Name: crown_foliage_profiles Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.crown_foliage_profiles AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids)))));


--
-- Name: entity_matches Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.entity_matches AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (observation_id IN ( SELECT shared.hidden_observation_ids() AS hidden_observation_ids)))));


--
-- Name: growth_simulations Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.growth_simulations AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR ((base_tree_id IS NULL) OR (NOT (base_tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids))))));


--
-- Name: observations Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.observations AS RESTRICTIVE FOR SELECT USING ((campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids)));


--
-- Name: phenology_observations Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.phenology_observations AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids)))));


--
-- Name: qsm_cylinders Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.qsm_cylinders AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (qsm_id IN ( SELECT shared.hidden_qsm_ids() AS hidden_qsm_ids)))));


--
-- Name: qsms Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.qsms AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (((tree_id IS NULL) OR (NOT (tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids)))) AND ((point_cloud_id IS NULL) OR (NOT (point_cloud_id IN ( SELECT shared.hidden_point_cloud_ids() AS hidden_point_cloud_ids)))))));


--
-- Name: roots Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.roots AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids)))));


--
-- Name: stems Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.stems AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (tree_id IN ( SELECT shared.hidden_tree_ids() AS hidden_tree_ids)))));


--
-- Name: tree_graph_edges Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.tree_graph_edges AS RESTRICTIVE FOR SELECT USING ((( SELECT (NOT shared.has_restricted_campaigns())) OR (NOT (qsm_id IN ( SELECT shared.hidden_qsm_ids() AS hidden_qsm_ids)))));


--
-- Name: trees Dataset access level; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset access level" ON trees.trees AS RESTRICTIVE FOR SELECT USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.readable_campaign_ids() AS readable_campaign_ids))));


--
-- Name: entity_matches Dataset owner: delete; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON trees.entity_matches AS RESTRICTIVE FOR DELETE USING ((observation_id IN ( SELECT shared.writable_observation_ids() AS writable_observation_ids)));


--
-- Name: observations Dataset owner: delete; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON trees.observations AS RESTRICTIVE FOR DELETE USING ((campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)));


--
-- Name: trees Dataset owner: delete; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: delete" ON trees.trees AS RESTRICTIVE FOR DELETE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: crown_foliage_profiles Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.crown_foliage_profiles AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT (tree_id IN ( SELECT shared.unwritable_tree_ids() AS unwritable_tree_ids))));


--
-- Name: entity_matches Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.entity_matches AS RESTRICTIVE FOR INSERT WITH CHECK ((observation_id IN ( SELECT shared.writable_observation_ids() AS writable_observation_ids)));


--
-- Name: observations Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.observations AS RESTRICTIVE FOR INSERT WITH CHECK ((campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)));


--
-- Name: phenology_observations Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.phenology_observations AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT (tree_id IN ( SELECT shared.unwritable_tree_ids() AS unwritable_tree_ids))));


--
-- Name: qsm_cylinders Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.qsm_cylinders AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT (qsm_id IN ( SELECT shared.unwritable_qsm_ids() AS unwritable_qsm_ids))));


--
-- Name: qsms Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.qsms AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((((tree_id IS NULL) OR (NOT (tree_id IN ( SELECT shared.unwritable_tree_ids() AS unwritable_tree_ids)))) AND ((point_cloud_id IS NULL) OR (NOT (point_cloud_id IN ( SELECT shared.unwritable_point_cloud_ids() AS unwritable_point_cloud_ids))))));


--
-- Name: roots Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.roots AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT (tree_id IN ( SELECT shared.unwritable_tree_ids() AS unwritable_tree_ids))));


--
-- Name: stems Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.stems AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT (tree_id IN ( SELECT shared.unwritable_tree_ids() AS unwritable_tree_ids))));


--
-- Name: tree_graph_edges Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.tree_graph_edges AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT (qsm_id IN ( SELECT shared.unwritable_qsm_ids() AS unwritable_qsm_ids))));


--
-- Name: trees Dataset owner: insert; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: insert" ON trees.trees AS RESTRICTIVE FOR INSERT WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: entity_matches Dataset owner: update; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON trees.entity_matches AS RESTRICTIVE FOR UPDATE USING ((observation_id IN ( SELECT shared.writable_observation_ids() AS writable_observation_ids))) WITH CHECK ((observation_id IN ( SELECT shared.writable_observation_ids() AS writable_observation_ids)));


--
-- Name: observations Dataset owner: update; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON trees.observations AS RESTRICTIVE FOR UPDATE USING ((campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))) WITH CHECK ((campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)));


--
-- Name: trees Dataset owner: update; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Dataset owner: update" ON trees.trees AS RESTRICTIVE FOR UPDATE USING (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids)))) WITH CHECK (((campaign_id IS NULL) OR (campaign_id IN ( SELECT shared.writable_campaign_ids() AS writable_campaign_ids))));


--
-- Name: growth_simulations Growth simulations are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Growth simulations are viewable by everyone" ON trees.growth_simulations FOR SELECT USING (true);


--
-- Name: phenology_observations Phenology observations are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Phenology observations are viewable by everyone" ON trees.phenology_observations FOR SELECT USING (true);


--
-- Name: qsm_cylinders QSM cylinders are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "QSM cylinders are viewable by everyone" ON trees.qsm_cylinders FOR SELECT USING (true);


--
-- Name: qsms QSMs are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "QSMs are viewable by everyone" ON trees.qsms FOR SELECT USING (true);


--
-- Name: roots Roots are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Roots are viewable by everyone" ON trees.roots FOR SELECT USING (true);


--
-- Name: entity_matches Service role can manage all; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all" ON trees.entity_matches TO service_role USING (true) WITH CHECK (true);


--
-- Name: observations Service role can manage all; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all" ON trees.observations TO service_role USING (true) WITH CHECK (true);


--
-- Name: qsm_cylinders Service role can manage all QSM cylinders; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all QSM cylinders" ON trees.qsm_cylinders TO service_role USING (true) WITH CHECK (true);


--
-- Name: qsms Service role can manage all QSMs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all QSMs" ON trees.qsms TO service_role USING (true) WITH CHECK (true);


--
-- Name: crown_foliage_profiles Service role can manage all crown foliage profiles; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all crown foliage profiles" ON trees.crown_foliage_profiles TO service_role USING (true) WITH CHECK (true);


--
-- Name: growth_simulations Service role can manage all growth simulations; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all growth simulations" ON trees.growth_simulations TO service_role USING (true) WITH CHECK (true);


--
-- Name: phenology_observations Service role can manage all phenology observations; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all phenology observations" ON trees.phenology_observations TO service_role USING (true) WITH CHECK (true);


--
-- Name: roots Service role can manage all roots; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all roots" ON trees.roots TO service_role USING (true) WITH CHECK (true);


--
-- Name: simulation_runs Service role can manage all simulation runs; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all simulation runs" ON trees.simulation_runs TO service_role USING (true) WITH CHECK (true);


--
-- Name: stems Service role can manage all stems; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all stems" ON trees.stems TO service_role USING (true) WITH CHECK (true);


--
-- Name: tree_graph_edges Service role can manage all tree graph edges; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all tree graph edges" ON trees.tree_graph_edges TO service_role USING (true) WITH CHECK (true);


--
-- Name: trees Service role can manage all trees; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Service role can manage all trees" ON trees.trees TO service_role USING (true) WITH CHECK (true);


--
-- Name: simulation_runs Simulation runs are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Simulation runs are viewable by everyone" ON trees.simulation_runs FOR SELECT USING (true);


--
-- Name: stems Stems are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Stems are viewable by everyone" ON trees.stems FOR SELECT USING (true);


--
-- Name: tree_graph_edges Tree graph edges are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree graph edges are viewable by everyone" ON trees.tree_graph_edges FOR SELECT USING (true);


--
-- Name: axis_structures Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.axis_structures FOR SELECT USING (true);


--
-- Name: bark_characteristics Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.bark_characteristics FOR SELECT USING (true);


--
-- Name: branch_elongation_habits Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.branch_elongation_habits FOR SELECT USING (true);


--
-- Name: branching_patterns Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.branching_patterns FOR SELECT USING (true);


--
-- Name: crown_architectures Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.crown_architectures FOR SELECT USING (true);


--
-- Name: crown_classes Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.crown_classes FOR SELECT USING (true);


--
-- Name: crown_shapes Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.crown_shapes FOR SELECT USING (true);


--
-- Name: damage_agents Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.damage_agents FOR SELECT USING (true);


--
-- Name: geometric_crown_solids Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.geometric_crown_solids FOR SELECT USING (true);


--
-- Name: growth_forms Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.growth_forms FOR SELECT USING (true);


--
-- Name: growth_orientations Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.growth_orientations FOR SELECT USING (true);


--
-- Name: phanerophyte_height_classes Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.phanerophyte_height_classes FOR SELECT USING (true);


--
-- Name: root_system_types Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.root_system_types FOR SELECT USING (true);


--
-- Name: shoot_elongation_types Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.shoot_elongation_types FOR SELECT USING (true);


--
-- Name: straightness_types Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.straightness_types FOR SELECT USING (true);


--
-- Name: taper_types Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.taper_types FOR SELECT USING (true);


--
-- Name: tree_part_types Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.tree_part_types FOR SELECT USING (true);


--
-- Name: tree_status Tree reference tables are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.tree_status FOR SELECT USING (true);


--
-- Name: trees Trees are viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Trees are viewable by everyone" ON trees.trees FOR SELECT USING (true);


--
-- Name: POLICY "Trees are viewable by everyone" ON trees; Type: COMMENT; Schema: trees; Owner: supabase_admin
--

COMMENT ON POLICY "Trees are viewable by everyone" ON trees.trees IS 'Public read access to tree measurement data';


--
-- Name: entity_matches Viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Viewable by everyone" ON trees.entity_matches FOR SELECT USING (true);


--
-- Name: observations Viewable by everyone; Type: POLICY; Schema: trees; Owner: supabase_admin
--

CREATE POLICY "Viewable by everyone" ON trees.observations FOR SELECT USING (true);


--
-- Name: axis_structures; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.axis_structures ENABLE ROW LEVEL SECURITY;

--
-- Name: bark_characteristics; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.bark_characteristics ENABLE ROW LEVEL SECURITY;

--
-- Name: branch_elongation_habits; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.branch_elongation_habits ENABLE ROW LEVEL SECURITY;

--
-- Name: branching_patterns; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.branching_patterns ENABLE ROW LEVEL SECURITY;

--
-- Name: crown_architectures; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.crown_architectures ENABLE ROW LEVEL SECURITY;

--
-- Name: crown_classes; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.crown_classes ENABLE ROW LEVEL SECURITY;

--
-- Name: crown_foliage_profiles; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.crown_foliage_profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: crown_shapes; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.crown_shapes ENABLE ROW LEVEL SECURITY;

--
-- Name: damage_agents; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.damage_agents ENABLE ROW LEVEL SECURITY;

--
-- Name: entity_matches; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.entity_matches ENABLE ROW LEVEL SECURITY;

--
-- Name: geometric_crown_solids; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.geometric_crown_solids ENABLE ROW LEVEL SECURITY;

--
-- Name: growth_forms; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.growth_forms ENABLE ROW LEVEL SECURITY;

--
-- Name: growth_orientations; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.growth_orientations ENABLE ROW LEVEL SECURITY;

--
-- Name: growth_simulations; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.growth_simulations ENABLE ROW LEVEL SECURITY;

--
-- Name: observations; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.observations ENABLE ROW LEVEL SECURITY;

--
-- Name: phanerophyte_height_classes; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.phanerophyte_height_classes ENABLE ROW LEVEL SECURITY;

--
-- Name: phenology_observations; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.phenology_observations ENABLE ROW LEVEL SECURITY;

--
-- Name: qsm_cylinders; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.qsm_cylinders ENABLE ROW LEVEL SECURITY;

--
-- Name: qsms; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.qsms ENABLE ROW LEVEL SECURITY;

--
-- Name: root_system_types; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.root_system_types ENABLE ROW LEVEL SECURITY;

--
-- Name: roots; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.roots ENABLE ROW LEVEL SECURITY;

--
-- Name: shoot_elongation_types; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.shoot_elongation_types ENABLE ROW LEVEL SECURITY;

--
-- Name: simulation_runs; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.simulation_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: stems; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.stems ENABLE ROW LEVEL SECURITY;

--
-- Name: straightness_types; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.straightness_types ENABLE ROW LEVEL SECURITY;

--
-- Name: taper_types; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.taper_types ENABLE ROW LEVEL SECURITY;

--
-- Name: tree_graph_edges; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.tree_graph_edges ENABLE ROW LEVEL SECURITY;

--
-- Name: tree_part_types; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.tree_part_types ENABLE ROW LEVEL SECURITY;

--
-- Name: tree_status; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.tree_status ENABLE ROW LEVEL SECURITY;

--
-- Name: trees; Type: ROW SECURITY; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.trees ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA environments; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA environments TO anon;
GRANT USAGE ON SCHEMA environments TO authenticated;
GRANT USAGE ON SCHEMA environments TO service_role;


--
-- Name: SCHEMA forest_floor; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA forest_floor TO anon;
GRANT USAGE ON SCHEMA forest_floor TO authenticated;
GRANT USAGE ON SCHEMA forest_floor TO service_role;


--
-- Name: SCHEMA imagery; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA imagery TO anon;
GRANT USAGE ON SCHEMA imagery TO authenticated;
GRANT USAGE ON SCHEMA imagery TO service_role;


--
-- Name: SCHEMA point_clouds; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA point_clouds TO anon;
GRANT USAGE ON SCHEMA point_clouds TO authenticated;
GRANT USAGE ON SCHEMA point_clouds TO service_role;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA sensor; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA sensor TO anon;
GRANT USAGE ON SCHEMA sensor TO authenticated;
GRANT USAGE ON SCHEMA sensor TO service_role;


--
-- Name: SCHEMA shared; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA shared TO anon;
GRANT USAGE ON SCHEMA shared TO authenticated;
GRANT USAGE ON SCHEMA shared TO service_role;


--
-- Name: SCHEMA trees; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA trees TO anon;
GRANT USAGE ON SCHEMA trees TO authenticated;
GRANT USAGE ON SCHEMA trees TO service_role;


--
-- Name: FUNCTION calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone); Type: ACL; Schema: environments; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) TO service_role;
GRANT ALL ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION environments.calculate_duration_days(start_date timestamp with time zone, end_date timestamp with time zone) TO authenticated;


--
-- Name: FUNCTION create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying); Type: ACL; Schema: environments; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) TO service_role;
GRANT ALL ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) TO anon;
GRANT ALL ON FUNCTION environments.create_from_sensor_data(location_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, variant_name_param character varying) TO authenticated;


--
-- Name: FUNCTION is_active(start_date timestamp with time zone, end_date timestamp with time zone); Type: ACL; Schema: environments; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) TO service_role;
GRANT ALL ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION environments.is_active(start_date timestamp with time zone, end_date timestamp with time zone) TO authenticated;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: environments; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION environments.update_updated_at_column() FROM PUBLIC;
GRANT ALL ON FUNCTION environments.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: imagery; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION imagery.update_updated_at_column() FROM PUBLIC;
GRANT ALL ON FUNCTION imagery.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION get_s3_bucket(file_path text); Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION point_clouds.get_s3_bucket(file_path text) FROM PUBLIC;
GRANT ALL ON FUNCTION point_clouds.get_s3_bucket(file_path text) TO service_role;
GRANT ALL ON FUNCTION point_clouds.get_s3_bucket(file_path text) TO anon;
GRANT ALL ON FUNCTION point_clouds.get_s3_bucket(file_path text) TO authenticated;


--
-- Name: FUNCTION get_s3_key(file_path text); Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION point_clouds.get_s3_key(file_path text) FROM PUBLIC;
GRANT ALL ON FUNCTION point_clouds.get_s3_key(file_path text) TO service_role;
GRANT ALL ON FUNCTION point_clouds.get_s3_key(file_path text) TO anon;
GRANT ALL ON FUNCTION point_clouds.get_s3_key(file_path text) TO authenticated;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION point_clouds.update_updated_at_column() FROM PUBLIC;
GRANT ALL ON FUNCTION point_clouds.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION validate_s3_uri(file_path text); Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION point_clouds.validate_s3_uri(file_path text) FROM PUBLIC;
GRANT ALL ON FUNCTION point_clouds.validate_s3_uri(file_path text) TO service_role;
GRANT ALL ON FUNCTION point_clouds.validate_s3_uri(file_path text) TO anon;
GRANT ALL ON FUNCTION point_clouds.validate_s3_uri(file_path text) TO authenticated;


--
-- Name: FUNCTION add_team_member(p_team_id integer, p_email text, p_is_team_curator boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.add_team_member(p_team_id integer, p_email text, p_is_team_curator boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_team_member(p_team_id integer, p_email text, p_is_team_curator boolean) TO postgres;
GRANT ALL ON FUNCTION public.add_team_member(p_team_id integer, p_email text, p_is_team_curator boolean) TO authenticated;
GRANT ALL ON FUNCTION public.add_team_member(p_team_id integer, p_email text, p_is_team_curator boolean) TO service_role;


--
-- Name: FUNCTION bulk_insert_readings(readings jsonb); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.bulk_insert_readings(readings jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bulk_insert_readings(readings jsonb) TO postgres;
GRANT ALL ON FUNCTION public.bulk_insert_readings(readings jsonb) TO service_role;


--
-- Name: FUNCTION bulk_upsert_sensors(p_sensors jsonb); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) TO postgres;
GRANT ALL ON FUNCTION public.bulk_upsert_sensors(p_sensors jsonb) TO service_role;


--
-- Name: FUNCTION campaigns_delete(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.campaigns_delete() TO postgres;
GRANT ALL ON FUNCTION public.campaigns_delete() TO anon;
GRANT ALL ON FUNCTION public.campaigns_delete() TO authenticated;
GRANT ALL ON FUNCTION public.campaigns_delete() TO service_role;


--
-- Name: FUNCTION campaigns_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.campaigns_insert() TO postgres;
GRANT ALL ON FUNCTION public.campaigns_insert() TO anon;
GRANT ALL ON FUNCTION public.campaigns_insert() TO authenticated;
GRANT ALL ON FUNCTION public.campaigns_insert() TO service_role;


--
-- Name: FUNCTION campaigns_update(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.campaigns_update() TO postgres;
GRANT ALL ON FUNCTION public.campaigns_update() TO anon;
GRANT ALL ON FUNCTION public.campaigns_update() TO authenticated;
GRANT ALL ON FUNCTION public.campaigns_update() TO service_role;


--
-- Name: FUNCTION create_account(p_email text, p_role text); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.create_account(p_email text, p_role text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_account(p_email text, p_role text) TO postgres;
GRANT ALL ON FUNCTION public.create_account(p_email text, p_role text) TO authenticated;
GRANT ALL ON FUNCTION public.create_account(p_email text, p_role text) TO service_role;


--
-- Name: FUNCTION crown_foliage_profiles_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.crown_foliage_profiles_insert() TO postgres;
GRANT ALL ON FUNCTION public.crown_foliage_profiles_insert() TO anon;
GRANT ALL ON FUNCTION public.crown_foliage_profiles_insert() TO authenticated;
GRANT ALL ON FUNCTION public.crown_foliage_profiles_insert() TO service_role;


--
-- Name: FUNCTION crownfoliageprofiles_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO postgres;
GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO anon;
GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO authenticated;
GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO service_role;


--
-- Name: FUNCTION deadwood_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.deadwood_insert() TO postgres;
GRANT ALL ON FUNCTION public.deadwood_insert() TO anon;
GRANT ALL ON FUNCTION public.deadwood_insert() TO authenticated;
GRANT ALL ON FUNCTION public.deadwood_insert() TO service_role;


--
-- Name: FUNCTION disturbance_events_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.disturbance_events_insert() TO postgres;
GRANT ALL ON FUNCTION public.disturbance_events_insert() TO anon;
GRANT ALL ON FUNCTION public.disturbance_events_insert() TO authenticated;
GRANT ALL ON FUNCTION public.disturbance_events_insert() TO service_role;


--
-- Name: FUNCTION environments_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.environments_insert() TO postgres;
GRANT ALL ON FUNCTION public.environments_insert() TO anon;
GRANT ALL ON FUNCTION public.environments_insert() TO authenticated;
GRANT ALL ON FUNCTION public.environments_insert() TO service_role;


--
-- Name: FUNCTION estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) TO postgres;
GRANT ALL ON FUNCTION public.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) TO anon;
GRANT ALL ON FUNCTION public.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) TO authenticated;
GRANT ALL ON FUNCTION public.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) TO service_role;


--
-- Name: FUNCTION ground_vegetation_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.ground_vegetation_insert() TO postgres;
GRANT ALL ON FUNCTION public.ground_vegetation_insert() TO anon;
GRANT ALL ON FUNCTION public.ground_vegetation_insert() TO authenticated;
GRANT ALL ON FUNCTION public.ground_vegetation_insert() TO service_role;


--
-- Name: FUNCTION images_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.images_insert() TO postgres;
GRANT ALL ON FUNCTION public.images_insert() TO anon;
GRANT ALL ON FUNCTION public.images_insert() TO authenticated;
GRANT ALL ON FUNCTION public.images_insert() TO service_role;


--
-- Name: FUNCTION list_accounts(); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.list_accounts() FROM PUBLIC;
GRANT ALL ON FUNCTION public.list_accounts() TO postgres;
GRANT ALL ON FUNCTION public.list_accounts() TO authenticated;
GRANT ALL ON FUNCTION public.list_accounts() TO service_role;


--
-- Name: FUNCTION list_team_members(p_team_id integer); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.list_team_members(p_team_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.list_team_members(p_team_id integer) TO postgres;
GRANT ALL ON FUNCTION public.list_team_members(p_team_id integer) TO authenticated;
GRANT ALL ON FUNCTION public.list_team_members(p_team_id integer) TO service_role;


--
-- Name: FUNCTION management_events_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.management_events_insert() TO postgres;
GRANT ALL ON FUNCTION public.management_events_insert() TO anon;
GRANT ALL ON FUNCTION public.management_events_insert() TO authenticated;
GRANT ALL ON FUNCTION public.management_events_insert() TO service_role;


--
-- Name: FUNCTION my_access(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.my_access() TO postgres;
GRANT ALL ON FUNCTION public.my_access() TO anon;
GRANT ALL ON FUNCTION public.my_access() TO authenticated;
GRANT ALL ON FUNCTION public.my_access() TO service_role;


--
-- Name: FUNCTION phenology_observations_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.phenology_observations_insert() TO postgres;
GRANT ALL ON FUNCTION public.phenology_observations_insert() TO anon;
GRANT ALL ON FUNCTION public.phenology_observations_insert() TO authenticated;
GRANT ALL ON FUNCTION public.phenology_observations_insert() TO service_role;


--
-- Name: FUNCTION plots_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.plots_insert() TO postgres;
GRANT ALL ON FUNCTION public.plots_insert() TO anon;
GRANT ALL ON FUNCTION public.plots_insert() TO authenticated;
GRANT ALL ON FUNCTION public.plots_insert() TO service_role;


--
-- Name: FUNCTION point_clouds_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.point_clouds_insert() TO postgres;
GRANT ALL ON FUNCTION public.point_clouds_insert() TO anon;
GRANT ALL ON FUNCTION public.point_clouds_insert() TO authenticated;
GRANT ALL ON FUNCTION public.point_clouds_insert() TO service_role;


--
-- Name: FUNCTION qsms_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.qsms_insert() TO postgres;
GRANT ALL ON FUNCTION public.qsms_insert() TO anon;
GRANT ALL ON FUNCTION public.qsms_insert() TO authenticated;
GRANT ALL ON FUNCTION public.qsms_insert() TO service_role;


--
-- Name: FUNCTION refresh_soil_aggregates(p_location_id integer, p_year integer, p_min_days_per_quarter integer, p_dry_run boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.refresh_soil_aggregates(p_location_id integer, p_year integer, p_min_days_per_quarter integer, p_dry_run boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.refresh_soil_aggregates(p_location_id integer, p_year integer, p_min_days_per_quarter integer, p_dry_run boolean) TO postgres;
GRANT ALL ON FUNCTION public.refresh_soil_aggregates(p_location_id integer, p_year integer, p_min_days_per_quarter integer, p_dry_run boolean) TO service_role;


--
-- Name: FUNCTION remove_team_member(p_team_id integer, p_email text); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.remove_team_member(p_team_id integer, p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.remove_team_member(p_team_id integer, p_email text) TO postgres;
GRANT ALL ON FUNCTION public.remove_team_member(p_team_id integer, p_email text) TO authenticated;
GRANT ALL ON FUNCTION public.remove_team_member(p_team_id integer, p_email text) TO service_role;


--
-- Name: FUNCTION request_job(workflow text, params jsonb, external_job_id text); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.request_job(workflow text, params jsonb, external_job_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.request_job(workflow text, params jsonb, external_job_id text) TO postgres;
GRANT ALL ON FUNCTION public.request_job(workflow text, params jsonb, external_job_id text) TO anon;
GRANT ALL ON FUNCTION public.request_job(workflow text, params jsonb, external_job_id text) TO authenticated;
GRANT ALL ON FUNCTION public.request_job(workflow text, params jsonb, external_job_id text) TO service_role;


--
-- Name: FUNCTION reset_account_password(p_email text); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.reset_account_password(p_email text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reset_account_password(p_email text) TO postgres;
GRANT ALL ON FUNCTION public.reset_account_password(p_email text) TO authenticated;
GRANT ALL ON FUNCTION public.reset_account_password(p_email text) TO service_role;


--
-- Name: FUNCTION roots_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.roots_insert() TO postgres;
GRANT ALL ON FUNCTION public.roots_insert() TO anon;
GRANT ALL ON FUNCTION public.roots_insert() TO authenticated;
GRANT ALL ON FUNCTION public.roots_insert() TO service_role;


--
-- Name: FUNCTION sensor_readings_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sensor_readings_insert() TO postgres;
GRANT ALL ON FUNCTION public.sensor_readings_insert() TO anon;
GRANT ALL ON FUNCTION public.sensor_readings_insert() TO authenticated;
GRANT ALL ON FUNCTION public.sensor_readings_insert() TO service_role;


--
-- Name: FUNCTION sensor_tree_links_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO postgres;
GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO anon;
GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO authenticated;
GRANT ALL ON FUNCTION public.sensor_tree_links_insert() TO service_role;


--
-- Name: FUNCTION sensors_delete(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sensors_delete() TO postgres;
GRANT ALL ON FUNCTION public.sensors_delete() TO anon;
GRANT ALL ON FUNCTION public.sensors_delete() TO authenticated;
GRANT ALL ON FUNCTION public.sensors_delete() TO service_role;


--
-- Name: FUNCTION sensors_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sensors_insert() TO postgres;
GRANT ALL ON FUNCTION public.sensors_insert() TO anon;
GRANT ALL ON FUNCTION public.sensors_insert() TO authenticated;
GRANT ALL ON FUNCTION public.sensors_insert() TO service_role;


--
-- Name: FUNCTION sensors_update(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.sensors_update() TO postgres;
GRANT ALL ON FUNCTION public.sensors_update() TO anon;
GRANT ALL ON FUNCTION public.sensors_update() TO authenticated;
GRANT ALL ON FUNCTION public.sensors_update() TO service_role;


--
-- Name: FUNCTION set_account_role(p_email text, p_role text); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.set_account_role(p_email text, p_role text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_account_role(p_email text, p_role text) TO postgres;
GRANT ALL ON FUNCTION public.set_account_role(p_email text, p_role text) TO authenticated;
GRANT ALL ON FUNCTION public.set_account_role(p_email text, p_role text) TO service_role;


--
-- Name: FUNCTION set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text, p_license character varying, p_fetched_at timestamp with time zone); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text, p_license character varying, p_fetched_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text, p_license character varying, p_fetched_at timestamp with time zone) TO postgres;
GRANT ALL ON FUNCTION public.set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text, p_license character varying, p_fetched_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION stems_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.stems_insert() TO postgres;
GRANT ALL ON FUNCTION public.stems_insert() TO anon;
GRANT ALL ON FUNCTION public.stems_insert() TO authenticated;
GRANT ALL ON FUNCTION public.stems_insert() TO service_role;


--
-- Name: FUNCTION tree_graph_edges_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.tree_graph_edges_insert() TO postgres;
GRANT ALL ON FUNCTION public.tree_graph_edges_insert() TO anon;
GRANT ALL ON FUNCTION public.tree_graph_edges_insert() TO authenticated;
GRANT ALL ON FUNCTION public.tree_graph_edges_insert() TO service_role;


--
-- Name: FUNCTION treegraphedges_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.treegraphedges_insert() TO postgres;
GRANT ALL ON FUNCTION public.treegraphedges_insert() TO anon;
GRANT ALL ON FUNCTION public.treegraphedges_insert() TO authenticated;
GRANT ALL ON FUNCTION public.treegraphedges_insert() TO service_role;


--
-- Name: FUNCTION trees_delete(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.trees_delete() TO postgres;
GRANT ALL ON FUNCTION public.trees_delete() TO anon;
GRANT ALL ON FUNCTION public.trees_delete() TO authenticated;
GRANT ALL ON FUNCTION public.trees_delete() TO service_role;


--
-- Name: FUNCTION trees_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.trees_insert() TO postgres;
GRANT ALL ON FUNCTION public.trees_insert() TO anon;
GRANT ALL ON FUNCTION public.trees_insert() TO authenticated;
GRANT ALL ON FUNCTION public.trees_insert() TO service_role;


--
-- Name: FUNCTION trees_update(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.trees_update() TO postgres;
GRANT ALL ON FUNCTION public.trees_update() TO anon;
GRANT ALL ON FUNCTION public.trees_update() TO authenticated;
GRANT ALL ON FUNCTION public.trees_update() TO service_role;


--
-- Name: TABLE sensor_readings; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT ON TABLE sensor.sensor_readings TO anon;
GRANT SELECT,INSERT ON TABLE sensor.sensor_readings TO authenticated;
GRANT ALL ON TABLE sensor.sensor_readings TO service_role;


--
-- Name: TABLE sensor_types; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT ON TABLE sensor.sensor_types TO anon;
GRANT SELECT ON TABLE sensor.sensor_types TO authenticated;
GRANT ALL ON TABLE sensor.sensor_types TO service_role;


--
-- Name: TABLE sensors; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT ON TABLE sensor.sensors TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE sensor.sensors TO authenticated;
GRANT ALL ON TABLE sensor.sensors TO service_role;


--
-- Name: TABLE ue_sensor_readings; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_sensor_readings TO postgres;
GRANT ALL ON TABLE public.ue_sensor_readings TO anon;
GRANT ALL ON TABLE public.ue_sensor_readings TO authenticated;
GRANT ALL ON TABLE public.ue_sensor_readings TO service_role;


--
-- Name: FUNCTION ue_sensor_readings_latest(p_limit integer, p_location_id integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.ue_sensor_readings_latest(p_limit integer, p_location_id integer) TO postgres;
GRANT ALL ON FUNCTION public.ue_sensor_readings_latest(p_limit integer, p_location_id integer) TO anon;
GRANT ALL ON FUNCTION public.ue_sensor_readings_latest(p_limit integer, p_location_id integer) TO authenticated;
GRANT ALL ON FUNCTION public.ue_sensor_readings_latest(p_limit integer, p_location_id integer) TO service_role;


--
-- Name: FUNCTION ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval) TO postgres;
GRANT ALL ON FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval) TO anon;
GRANT ALL ON FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval) TO authenticated;
GRANT ALL ON FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval) TO service_role;


--
-- Name: FUNCTION upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb, p_scenario_id integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text); Type: ACL; Schema: public; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION public.upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb, p_scenario_id integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb, p_scenario_id integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text) TO postgres;
GRANT ALL ON FUNCTION public.upsert_environment(p_location_id integer, p_variant_type_id integer, p_variant_name character varying, p_process_id integer, p_values jsonb, p_scenario_id integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text) TO service_role;


--
-- Name: FUNCTION aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer); Type: ACL; Schema: sensor; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) FROM PUBLIC;
GRANT ALL ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) TO service_role;
GRANT ALL ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) TO anon;
GRANT ALL ON FUNCTION sensor.aggregate_readings(sensor_id_param integer, start_time timestamp with time zone, end_time timestamp with time zone, interval_minutes integer) TO authenticated;


--
-- Name: FUNCTION check_sensor_health(sensor_id_param integer, hours_back integer); Type: ACL; Schema: sensor; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) FROM PUBLIC;
GRANT ALL ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) TO service_role;
GRANT ALL ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) TO anon;
GRANT ALL ON FUNCTION sensor.check_sensor_health(sensor_id_param integer, hours_back integer) TO authenticated;


--
-- Name: FUNCTION get_latest_reading(sensor_id_param integer); Type: ACL; Schema: sensor; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) FROM PUBLIC;
GRANT ALL ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) TO service_role;
GRANT ALL ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) TO anon;
GRANT ALL ON FUNCTION sensor.get_latest_reading(sensor_id_param integer) TO authenticated;


--
-- Name: FUNCTION link_sensors_to_trees_by_pattern(); Type: ACL; Schema: sensor; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION sensor.link_sensors_to_trees_by_pattern() FROM PUBLIC;
GRANT ALL ON FUNCTION sensor.link_sensors_to_trees_by_pattern() TO service_role;
GRANT ALL ON FUNCTION sensor.link_sensors_to_trees_by_pattern() TO anon;
GRANT ALL ON FUNCTION sensor.link_sensors_to_trees_by_pattern() TO authenticated;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: sensor; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION sensor.update_updated_at_column() FROM PUBLIC;
GRANT ALL ON FUNCTION sensor.update_updated_at_column() TO service_role;


--
-- Name: FUNCTION attribute_is_acquired(p_location_id integer, p_column_name text); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) TO postgres;
GRANT ALL ON FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) TO service_role;
GRANT ALL ON FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) TO anon;
GRANT ALL ON FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text) TO authenticated;


--
-- Name: FUNCTION audit_update_trigger(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.audit_update_trigger() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.audit_update_trigger() TO service_role;


--
-- Name: FUNCTION check_inclusion_rule_overlap(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.check_inclusion_rule_overlap() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.check_inclusion_rule_overlap() TO service_role;


--
-- Name: FUNCTION create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.create_audit_log(table_name_param character varying, variant_id_param integer, field_name_param character varying, old_value_param text, new_value_param text, change_reason_param text, change_type_param character varying) TO service_role;


--
-- Name: FUNCTION current_user_id(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.current_user_id() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.current_user_id() TO service_role;


--
-- Name: FUNCTION ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric) TO service_role;
GRANT ALL ON FUNCTION shared.ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric) TO anon;
GRANT ALL ON FUNCTION shared.ef_value(p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric, p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric) TO authenticated;


--
-- Name: FUNCTION estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) TO service_role;
GRANT ALL ON FUNCTION shared.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) TO anon;
GRANT ALL ON FUNCTION shared.estimate_stand(p_sampling_design_id integer, p_variant_id integer, p_by_species boolean, p_confidence numeric) TO authenticated;


--
-- Name: FUNCTION estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric) TO service_role;
GRANT ALL ON FUNCTION shared.estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric) TO anon;
GRANT ALL ON FUNCTION shared.estimate_stand_domains(p_sampling_design_id integer, p_variant_id integer, p_all_species boolean, p_per_species boolean, p_confidence numeric) TO authenticated;


--
-- Name: FUNCTION expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric) TO service_role;
GRANT ALL ON FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric) TO anon;
GRANT ALL ON FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric) TO authenticated;


--
-- Name: FUNCTION get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer) TO service_role;


--
-- Name: FUNCTION has_restricted_campaigns(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.has_restricted_campaigns() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.has_restricted_campaigns() TO service_role;
GRANT ALL ON FUNCTION shared.has_restricted_campaigns() TO anon;
GRANT ALL ON FUNCTION shared.has_restricted_campaigns() TO authenticated;


--
-- Name: FUNCTION hidden_observation_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.hidden_observation_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.hidden_observation_ids() TO service_role;
GRANT ALL ON FUNCTION shared.hidden_observation_ids() TO anon;
GRANT ALL ON FUNCTION shared.hidden_observation_ids() TO authenticated;


--
-- Name: FUNCTION hidden_point_cloud_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.hidden_point_cloud_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.hidden_point_cloud_ids() TO service_role;
GRANT ALL ON FUNCTION shared.hidden_point_cloud_ids() TO anon;
GRANT ALL ON FUNCTION shared.hidden_point_cloud_ids() TO authenticated;


--
-- Name: FUNCTION hidden_qsm_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.hidden_qsm_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.hidden_qsm_ids() TO service_role;
GRANT ALL ON FUNCTION shared.hidden_qsm_ids() TO anon;
GRANT ALL ON FUNCTION shared.hidden_qsm_ids() TO authenticated;


--
-- Name: FUNCTION hidden_sensor_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.hidden_sensor_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.hidden_sensor_ids() TO service_role;
GRANT ALL ON FUNCTION shared.hidden_sensor_ids() TO anon;
GRANT ALL ON FUNCTION shared.hidden_sensor_ids() TO authenticated;


--
-- Name: FUNCTION hidden_tree_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.hidden_tree_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.hidden_tree_ids() TO service_role;
GRANT ALL ON FUNCTION shared.hidden_tree_ids() TO anon;
GRANT ALL ON FUNCTION shared.hidden_tree_ids() TO authenticated;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.is_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.is_admin() TO service_role;
GRANT ALL ON FUNCTION shared.is_admin() TO anon;
GRANT ALL ON FUNCTION shared.is_admin() TO authenticated;


--
-- Name: FUNCTION is_contributor(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.is_contributor() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.is_contributor() TO service_role;
GRANT ALL ON FUNCTION shared.is_contributor() TO anon;
GRANT ALL ON FUNCTION shared.is_contributor() TO authenticated;


--
-- Name: FUNCTION is_curator(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.is_curator() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.is_curator() TO service_role;
GRANT ALL ON FUNCTION shared.is_curator() TO anon;
GRANT ALL ON FUNCTION shared.is_curator() TO authenticated;


--
-- Name: FUNCTION may_manage_role(p_role text); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.may_manage_role(p_role text) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.may_manage_role(p_role text) TO service_role;
GRANT ALL ON FUNCTION shared.may_manage_role(p_role text) TO authenticated;


--
-- Name: FUNCTION my_curated_team_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.my_curated_team_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.my_curated_team_ids() TO service_role;
GRANT ALL ON FUNCTION shared.my_curated_team_ids() TO anon;
GRANT ALL ON FUNCTION shared.my_curated_team_ids() TO authenticated;


--
-- Name: FUNCTION my_team_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.my_team_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.my_team_ids() TO service_role;
GRANT ALL ON FUNCTION shared.my_team_ids() TO anon;
GRANT ALL ON FUNCTION shared.my_team_ids() TO authenticated;


--
-- Name: FUNCTION new_account_password(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.new_account_password() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.new_account_password() TO service_role;
GRANT ALL ON FUNCTION shared.new_account_password() TO anon;
GRANT ALL ON FUNCTION shared.new_account_password() TO authenticated;


--
-- Name: FUNCTION readable_campaign_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.readable_campaign_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.readable_campaign_ids() TO service_role;
GRANT ALL ON FUNCTION shared.readable_campaign_ids() TO anon;
GRANT ALL ON FUNCTION shared.readable_campaign_ids() TO authenticated;


--
-- Name: FUNCTION refresh_all_lookups(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.refresh_all_lookups() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.refresh_all_lookups() TO service_role;


--
-- Name: FUNCTION refresh_lookup(p_table_name text); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.refresh_lookup(p_table_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.refresh_lookup(p_table_name text) TO service_role;


--
-- Name: FUNCTION refresh_lookup_generic(p_key text); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.refresh_lookup_generic(p_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.refresh_lookup_generic(p_key text) TO service_role;


--
-- Name: FUNCTION request_network(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.request_network() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.request_network() TO service_role;
GRANT ALL ON FUNCTION shared.request_network() TO anon;
GRANT ALL ON FUNCTION shared.request_network() TO authenticated;


--
-- Name: FUNCTION sample_unit_id(p_plot_id integer); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.sample_unit_id(p_plot_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.sample_unit_id(p_plot_id integer) TO service_role;
GRANT ALL ON FUNCTION shared.sample_unit_id(p_plot_id integer) TO anon;
GRANT ALL ON FUNCTION shared.sample_unit_id(p_plot_id integer) TO authenticated;


--
-- Name: FUNCTION scenario_axes_from_name(p_name text); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.scenario_axes_from_name(p_name text) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.scenario_axes_from_name(p_name text) TO service_role;
GRANT ALL ON FUNCTION shared.scenario_axes_from_name(p_name text) TO anon;
GRANT ALL ON FUNCTION shared.scenario_axes_from_name(p_name text) TO authenticated;


--
-- Name: FUNCTION scenarios_derive_axes(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.scenarios_derive_axes() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.scenarios_derive_axes() TO service_role;


--
-- Name: FUNCTION set_created_by(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.set_created_by() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.set_created_by() TO service_role;


--
-- Name: FUNCTION set_updated_by(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.set_updated_by() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.set_updated_by() TO service_role;


--
-- Name: FUNCTION t_quantile(p_confidence numeric, p_df integer); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.t_quantile(p_confidence numeric, p_df integer) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.t_quantile(p_confidence numeric, p_df integer) TO service_role;
GRANT ALL ON FUNCTION shared.t_quantile(p_confidence numeric, p_df integer) TO anon;
GRANT ALL ON FUNCTION shared.t_quantile(p_confidence numeric, p_df integer) TO authenticated;


--
-- Name: FUNCTION unwritable_point_cloud_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.unwritable_point_cloud_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.unwritable_point_cloud_ids() TO service_role;
GRANT ALL ON FUNCTION shared.unwritable_point_cloud_ids() TO authenticated;


--
-- Name: FUNCTION unwritable_qsm_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.unwritable_qsm_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.unwritable_qsm_ids() TO service_role;
GRANT ALL ON FUNCTION shared.unwritable_qsm_ids() TO authenticated;


--
-- Name: FUNCTION unwritable_sensor_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.unwritable_sensor_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.unwritable_sensor_ids() TO service_role;
GRANT ALL ON FUNCTION shared.unwritable_sensor_ids() TO authenticated;


--
-- Name: FUNCTION unwritable_tree_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.unwritable_tree_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.unwritable_tree_ids() TO service_role;
GRANT ALL ON FUNCTION shared.unwritable_tree_ids() TO authenticated;


--
-- Name: FUNCTION validate_against_param_schema(schema jsonb, params jsonb); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb) TO service_role;
GRANT ALL ON FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb) TO anon;
GRANT ALL ON FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb) TO authenticated;


--
-- Name: FUNCTION writable_campaign_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.writable_campaign_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.writable_campaign_ids() TO service_role;
GRANT ALL ON FUNCTION shared.writable_campaign_ids() TO anon;
GRANT ALL ON FUNCTION shared.writable_campaign_ids() TO authenticated;


--
-- Name: FUNCTION writable_observation_ids(); Type: ACL; Schema: shared; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION shared.writable_observation_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION shared.writable_observation_ids() TO service_role;
GRANT ALL ON FUNCTION shared.writable_observation_ids() TO anon;
GRANT ALL ON FUNCTION shared.writable_observation_ids() TO authenticated;


--
-- Name: FUNCTION assign_height_class(); Type: ACL; Schema: trees; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION trees.assign_height_class() FROM PUBLIC;
GRANT ALL ON FUNCTION trees.assign_height_class() TO service_role;


--
-- Name: FUNCTION calculate_basal_area(dbh_cm numeric); Type: ACL; Schema: trees; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) TO service_role;
GRANT ALL ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) TO anon;
GRANT ALL ON FUNCTION trees.calculate_basal_area(dbh_cm numeric) TO authenticated;


--
-- Name: FUNCTION calculate_crown_volume(crown_width_m numeric, crown_height_m numeric); Type: ACL; Schema: trees; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) TO service_role;
GRANT ALL ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) TO anon;
GRANT ALL ON FUNCTION trees.calculate_crown_volume(crown_width_m numeric, crown_height_m numeric) TO authenticated;


--
-- Name: FUNCTION fill_from_variant(); Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT ALL ON FUNCTION trees.fill_from_variant() TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: trees; Owner: supabase_admin
--

REVOKE ALL ON FUNCTION trees.update_updated_at_column() FROM PUBLIC;
GRANT ALL ON FUNCTION trees.update_updated_at_column() TO service_role;


--
-- Name: TABLE environments; Type: ACL; Schema: environments; Owner: supabase_admin
--

GRANT SELECT ON TABLE environments.environments TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE environments.environments TO authenticated;
GRANT ALL ON TABLE environments.environments TO service_role;


--
-- Name: TABLE locations; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.locations TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE shared.locations TO authenticated;
GRANT ALL ON TABLE shared.locations TO service_role;


--
-- Name: TABLE scenarios; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.scenarios TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.scenarios TO authenticated;
GRANT ALL ON TABLE shared.scenarios TO service_role;


--
-- Name: TABLE variant_types; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.variant_types TO anon;
GRANT SELECT ON TABLE shared.variant_types TO authenticated;
GRANT ALL ON TABLE shared.variant_types TO service_role;


--
-- Name: TABLE active_environments; Type: ACL; Schema: environments; Owner: supabase_admin
--

GRANT SELECT ON TABLE environments.active_environments TO anon;
GRANT SELECT ON TABLE environments.active_environments TO authenticated;
GRANT ALL ON TABLE environments.active_environments TO service_role;


--
-- Name: SEQUENCE environments_environment_id_seq; Type: ACL; Schema: environments; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE environments.environments_environment_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE environments.environments_environment_id_seq TO service_role;


--
-- Name: TABLE location_environment_summary; Type: ACL; Schema: environments; Owner: supabase_admin
--

GRANT SELECT ON TABLE environments.location_environment_summary TO anon;
GRANT SELECT ON TABLE environments.location_environment_summary TO authenticated;
GRANT ALL ON TABLE environments.location_environment_summary TO service_role;


--
-- Name: TABLE deadwood; Type: ACL; Schema: forest_floor; Owner: supabase_admin
--

GRANT SELECT ON TABLE forest_floor.deadwood TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE forest_floor.deadwood TO authenticated;
GRANT ALL ON TABLE forest_floor.deadwood TO service_role;


--
-- Name: SEQUENCE deadwood_deadwood_id_seq; Type: ACL; Schema: forest_floor; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE forest_floor.deadwood_deadwood_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE forest_floor.deadwood_deadwood_id_seq TO service_role;


--
-- Name: TABLE ground_vegetation; Type: ACL; Schema: forest_floor; Owner: supabase_admin
--

GRANT SELECT ON TABLE forest_floor.ground_vegetation TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE forest_floor.ground_vegetation TO authenticated;
GRANT ALL ON TABLE forest_floor.ground_vegetation TO service_role;


--
-- Name: SEQUENCE ground_vegetation_ground_vegetation_id_seq; Type: ACL; Schema: forest_floor; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE forest_floor.ground_vegetation_ground_vegetation_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE forest_floor.ground_vegetation_ground_vegetation_id_seq TO service_role;


--
-- Name: TABLE regeneration; Type: ACL; Schema: forest_floor; Owner: supabase_admin
--

GRANT SELECT ON TABLE forest_floor.regeneration TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE forest_floor.regeneration TO authenticated;
GRANT ALL ON TABLE forest_floor.regeneration TO service_role;


--
-- Name: SEQUENCE regeneration_regeneration_id_seq; Type: ACL; Schema: forest_floor; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE forest_floor.regeneration_regeneration_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE forest_floor.regeneration_regeneration_id_seq TO service_role;


--
-- Name: TABLE images; Type: ACL; Schema: imagery; Owner: supabase_admin
--

GRANT SELECT ON TABLE imagery.images TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE imagery.images TO authenticated;
GRANT ALL ON TABLE imagery.images TO service_role;


--
-- Name: SEQUENCE images_image_id_seq; Type: ACL; Schema: imagery; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE imagery.images_image_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE imagery.images_image_id_seq TO service_role;


--
-- Name: TABLE point_clouds; Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

GRANT SELECT ON TABLE point_clouds.point_clouds TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE point_clouds.point_clouds TO authenticated;
GRANT ALL ON TABLE point_clouds.point_clouds TO service_role;


--
-- Name: SEQUENCE point_clouds_point_cloud_id_seq; Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE point_clouds.point_clouds_point_cloud_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE point_clouds.point_clouds_point_cloud_id_seq TO service_role;


--
-- Name: TABLE processing_lineage; Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

GRANT SELECT ON TABLE point_clouds.processing_lineage TO anon;
GRANT SELECT ON TABLE point_clouds.processing_lineage TO authenticated;
GRANT ALL ON TABLE point_clouds.processing_lineage TO service_role;


--
-- Name: TABLE scanner_types; Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

GRANT SELECT ON TABLE point_clouds.scanner_types TO anon;
GRANT SELECT ON TABLE point_clouds.scanner_types TO authenticated;
GRANT ALL ON TABLE point_clouds.scanner_types TO service_role;


--
-- Name: SEQUENCE scanner_types_scanner_type_id_seq; Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE point_clouds.scanner_types_scanner_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE point_clouds.scanner_types_scanner_type_id_seq TO service_role;


--
-- Name: TABLE scanners; Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

GRANT SELECT ON TABLE point_clouds.scanners TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE point_clouds.scanners TO authenticated;
GRANT ALL ON TABLE point_clouds.scanners TO service_role;


--
-- Name: SEQUENCE scanners_scanner_id_seq; Type: ACL; Schema: point_clouds; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE point_clouds.scanners_scanner_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE point_clouds.scanners_scanner_id_seq TO service_role;


--
-- Name: TABLE attribute_provenance; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.attribute_provenance TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.attribute_provenance TO authenticated;
GRANT ALL ON TABLE shared.attribute_provenance TO service_role;


--
-- Name: TABLE processes; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.processes TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.processes TO authenticated;
GRANT ALL ON TABLE shared.processes TO service_role;


--
-- Name: TABLE attribute_provenance; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.attribute_provenance TO postgres;
GRANT ALL ON TABLE public.attribute_provenance TO anon;
GRANT ALL ON TABLE public.attribute_provenance TO authenticated;
GRANT ALL ON TABLE public.attribute_provenance TO service_role;


--
-- Name: TABLE axis_structures; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.axis_structures TO authenticated;


--
-- Name: TABLE axis_structures; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.axis_structures TO postgres;
GRANT ALL ON TABLE public.axis_structures TO anon;
GRANT ALL ON TABLE public.axis_structures TO authenticated;
GRANT ALL ON TABLE public.axis_structures TO service_role;


--
-- Name: TABLE branch_elongation_habits; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.branch_elongation_habits TO authenticated;


--
-- Name: TABLE branch_elongation_habits; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.branch_elongation_habits TO postgres;
GRANT ALL ON TABLE public.branch_elongation_habits TO anon;
GRANT ALL ON TABLE public.branch_elongation_habits TO authenticated;
GRANT ALL ON TABLE public.branch_elongation_habits TO service_role;


--
-- Name: TABLE campaigns; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.campaigns TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.campaigns TO authenticated;
GRANT ALL ON TABLE shared.campaigns TO service_role;


--
-- Name: TABLE campaigns; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.campaigns TO postgres;
GRANT ALL ON TABLE public.campaigns TO anon;
GRANT ALL ON TABLE public.campaigns TO authenticated;
GRANT ALL ON TABLE public.campaigns TO service_role;


--
-- Name: TABLE climate_pathways; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.climate_pathways TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.climate_pathways TO authenticated;
GRANT ALL ON TABLE shared.climate_pathways TO service_role;


--
-- Name: TABLE climate_pathways; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.climate_pathways TO postgres;
GRANT ALL ON TABLE public.climate_pathways TO anon;
GRANT ALL ON TABLE public.climate_pathways TO authenticated;
GRANT ALL ON TABLE public.climate_pathways TO service_role;


--
-- Name: TABLE crown_architectures; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.crown_architectures TO authenticated;


--
-- Name: TABLE crown_architectures; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.crown_architectures TO postgres;
GRANT ALL ON TABLE public.crown_architectures TO anon;
GRANT ALL ON TABLE public.crown_architectures TO authenticated;
GRANT ALL ON TABLE public.crown_architectures TO service_role;


--
-- Name: TABLE crown_classes; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.crown_classes TO authenticated;


--
-- Name: TABLE crown_classes; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.crown_classes TO postgres;
GRANT ALL ON TABLE public.crown_classes TO anon;
GRANT ALL ON TABLE public.crown_classes TO authenticated;
GRANT ALL ON TABLE public.crown_classes TO service_role;


--
-- Name: TABLE crown_foliage_profiles; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.crown_foliage_profiles TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.crown_foliage_profiles TO authenticated;
GRANT ALL ON TABLE trees.crown_foliage_profiles TO service_role;


--
-- Name: TABLE crown_foliage_profiles; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.crown_foliage_profiles TO postgres;
GRANT ALL ON TABLE public.crown_foliage_profiles TO anon;
GRANT ALL ON TABLE public.crown_foliage_profiles TO authenticated;
GRANT ALL ON TABLE public.crown_foliage_profiles TO service_role;


--
-- Name: TABLE crown_shapes; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.crown_shapes TO authenticated;


--
-- Name: TABLE crown_shapes; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.crown_shapes TO postgres;
GRANT ALL ON TABLE public.crown_shapes TO anon;
GRANT ALL ON TABLE public.crown_shapes TO authenticated;
GRANT ALL ON TABLE public.crown_shapes TO service_role;


--
-- Name: TABLE entity_matches; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.entity_matches TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.entity_matches TO authenticated;
GRANT ALL ON TABLE trees.entity_matches TO service_role;


--
-- Name: TABLE observations; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.observations TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.observations TO authenticated;
GRANT ALL ON TABLE trees.observations TO service_role;


--
-- Name: TABLE current_entity_matches; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.current_entity_matches TO postgres;
GRANT ALL ON TABLE public.current_entity_matches TO anon;
GRANT ALL ON TABLE public.current_entity_matches TO authenticated;
GRANT ALL ON TABLE public.current_entity_matches TO service_role;


--
-- Name: TABLE damage_agents; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.damage_agents TO authenticated;


--
-- Name: TABLE damage_agents; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.damage_agents TO postgres;
GRANT ALL ON TABLE public.damage_agents TO anon;
GRANT ALL ON TABLE public.damage_agents TO authenticated;
GRANT ALL ON TABLE public.damage_agents TO service_role;


--
-- Name: TABLE data_source_types; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.data_source_types TO anon;
GRANT SELECT ON TABLE trees.data_source_types TO authenticated;
GRANT ALL ON TABLE trees.data_source_types TO service_role;


--
-- Name: TABLE data_source_types; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.data_source_types TO postgres;
GRANT ALL ON TABLE public.data_source_types TO anon;
GRANT ALL ON TABLE public.data_source_types TO authenticated;
GRANT ALL ON TABLE public.data_source_types TO service_role;


--
-- Name: TABLE deadwood; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.deadwood TO postgres;
GRANT ALL ON TABLE public.deadwood TO anon;
GRANT ALL ON TABLE public.deadwood TO authenticated;
GRANT ALL ON TABLE public.deadwood TO service_role;


--
-- Name: TABLE disturbance_events; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.disturbance_events TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.disturbance_events TO authenticated;
GRANT ALL ON TABLE shared.disturbance_events TO service_role;


--
-- Name: TABLE disturbance_events; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.disturbance_events TO postgres;
GRANT ALL ON TABLE public.disturbance_events TO anon;
GRANT ALL ON TABLE public.disturbance_events TO authenticated;
GRANT ALL ON TABLE public.disturbance_events TO service_role;


--
-- Name: TABLE entity_matches; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.entity_matches TO postgres;
GRANT ALL ON TABLE public.entity_matches TO anon;
GRANT ALL ON TABLE public.entity_matches TO authenticated;
GRANT ALL ON TABLE public.entity_matches TO service_role;


--
-- Name: TABLE environments; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.environments TO postgres;
GRANT ALL ON TABLE public.environments TO anon;
GRANT ALL ON TABLE public.environments TO authenticated;
GRANT ALL ON TABLE public.environments TO service_role;


--
-- Name: TABLE geometric_crown_solids; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.geometric_crown_solids TO authenticated;


--
-- Name: TABLE geometric_crown_solids; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.geometric_crown_solids TO postgres;
GRANT ALL ON TABLE public.geometric_crown_solids TO anon;
GRANT ALL ON TABLE public.geometric_crown_solids TO authenticated;
GRANT ALL ON TABLE public.geometric_crown_solids TO service_role;


--
-- Name: TABLE ground_vegetation; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ground_vegetation TO postgres;
GRANT ALL ON TABLE public.ground_vegetation TO anon;
GRANT ALL ON TABLE public.ground_vegetation TO authenticated;
GRANT ALL ON TABLE public.ground_vegetation TO service_role;


--
-- Name: TABLE growth_forms; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.growth_forms TO authenticated;


--
-- Name: TABLE growth_forms; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.growth_forms TO postgres;
GRANT ALL ON TABLE public.growth_forms TO anon;
GRANT ALL ON TABLE public.growth_forms TO authenticated;
GRANT ALL ON TABLE public.growth_forms TO service_role;


--
-- Name: TABLE growth_orientations; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.growth_orientations TO authenticated;


--
-- Name: TABLE growth_orientations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.growth_orientations TO postgres;
GRANT ALL ON TABLE public.growth_orientations TO anon;
GRANT ALL ON TABLE public.growth_orientations TO authenticated;
GRANT ALL ON TABLE public.growth_orientations TO service_role;


--
-- Name: TABLE species; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.species TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.species TO authenticated;
GRANT ALL ON TABLE shared.species TO service_role;


--
-- Name: TABLE growth_simulations; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT INSERT,UPDATE ON TABLE trees.growth_simulations TO postgres;
GRANT SELECT ON TABLE trees.growth_simulations TO anon;
GRANT SELECT ON TABLE trees.growth_simulations TO authenticated;


--
-- Name: TABLE growth_simulations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.growth_simulations TO postgres;
GRANT ALL ON TABLE public.growth_simulations TO anon;
GRANT ALL ON TABLE public.growth_simulations TO authenticated;
GRANT ALL ON TABLE public.growth_simulations TO service_role;


--
-- Name: TABLE images; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.images TO postgres;
GRANT ALL ON TABLE public.images TO anon;
GRANT ALL ON TABLE public.images TO authenticated;
GRANT ALL ON TABLE public.images TO service_role;


--
-- Name: TABLE inclusion_rules; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.inclusion_rules TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.inclusion_rules TO authenticated;
GRANT ALL ON TABLE shared.inclusion_rules TO service_role;


--
-- Name: TABLE inclusion_rules; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.inclusion_rules TO postgres;
GRANT ALL ON TABLE public.inclusion_rules TO anon;
GRANT ALL ON TABLE public.inclusion_rules TO authenticated;
GRANT ALL ON TABLE public.inclusion_rules TO service_role;


--
-- Name: TABLE processing_jobs; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT ALL ON TABLE shared.processing_jobs TO service_role;
GRANT SELECT ON TABLE shared.processing_jobs TO authenticated;
GRANT SELECT ON TABLE shared.processing_jobs TO anon;


--
-- Name: TABLE job_status; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.job_status TO postgres;
GRANT ALL ON TABLE public.job_status TO anon;
GRANT ALL ON TABLE public.job_status TO authenticated;
GRANT ALL ON TABLE public.job_status TO service_role;


--
-- Name: TABLE locations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.locations TO postgres;
GRANT ALL ON TABLE public.locations TO anon;
GRANT ALL ON TABLE public.locations TO authenticated;
GRANT ALL ON TABLE public.locations TO service_role;


--
-- Name: TABLE management_events; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.management_events TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.management_events TO authenticated;
GRANT ALL ON TABLE shared.management_events TO service_role;


--
-- Name: TABLE management_events; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.management_events TO postgres;
GRANT ALL ON TABLE public.management_events TO anon;
GRANT ALL ON TABLE public.management_events TO authenticated;
GRANT ALL ON TABLE public.management_events TO service_role;


--
-- Name: TABLE management_regimes; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.management_regimes TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.management_regimes TO authenticated;
GRANT ALL ON TABLE shared.management_regimes TO service_role;


--
-- Name: TABLE management_regimes; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.management_regimes TO postgres;
GRANT ALL ON TABLE public.management_regimes TO anon;
GRANT ALL ON TABLE public.management_regimes TO authenticated;
GRANT ALL ON TABLE public.management_regimes TO service_role;


--
-- Name: TABLE observations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.observations TO postgres;
GRANT ALL ON TABLE public.observations TO anon;
GRANT ALL ON TABLE public.observations TO authenticated;
GRANT ALL ON TABLE public.observations TO service_role;


--
-- Name: TABLE phanerophyte_height_classes; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.phanerophyte_height_classes TO authenticated;


--
-- Name: TABLE phanerophyte_height_classes; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.phanerophyte_height_classes TO postgres;
GRANT ALL ON TABLE public.phanerophyte_height_classes TO anon;
GRANT ALL ON TABLE public.phanerophyte_height_classes TO authenticated;
GRANT ALL ON TABLE public.phanerophyte_height_classes TO service_role;


--
-- Name: TABLE phenology_observations; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.phenology_observations TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.phenology_observations TO authenticated;
GRANT ALL ON TABLE trees.phenology_observations TO service_role;


--
-- Name: TABLE phenology_observations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.phenology_observations TO postgres;
GRANT ALL ON TABLE public.phenology_observations TO anon;
GRANT ALL ON TABLE public.phenology_observations TO authenticated;
GRANT ALL ON TABLE public.phenology_observations TO service_role;


--
-- Name: TABLE plots; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.plots TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.plots TO authenticated;
GRANT ALL ON TABLE shared.plots TO service_role;


--
-- Name: TABLE sampling_designs; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.sampling_designs TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.sampling_designs TO authenticated;
GRANT ALL ON TABLE shared.sampling_designs TO service_role;


--
-- Name: TABLE plot_inclusion; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.plot_inclusion TO anon;
GRANT SELECT ON TABLE shared.plot_inclusion TO authenticated;
GRANT SELECT ON TABLE shared.plot_inclusion TO service_role;


--
-- Name: TABLE stems; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.stems TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.stems TO authenticated;
GRANT ALL ON TABLE trees.stems TO service_role;


--
-- Name: TABLE tree_status; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.tree_status TO anon;
GRANT SELECT ON TABLE trees.tree_status TO authenticated;
GRANT ALL ON TABLE trees.tree_status TO service_role;


--
-- Name: TABLE trees; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.trees TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.trees TO authenticated;
GRANT ALL ON TABLE trees.trees TO service_role;


--
-- Name: TABLE plot_summaries; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.plot_summaries TO postgres;
GRANT ALL ON TABLE public.plot_summaries TO anon;
GRANT ALL ON TABLE public.plot_summaries TO authenticated;
GRANT ALL ON TABLE public.plot_summaries TO service_role;


--
-- Name: TABLE plots; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.plots TO postgres;
GRANT ALL ON TABLE public.plots TO anon;
GRANT ALL ON TABLE public.plots TO authenticated;
GRANT ALL ON TABLE public.plots TO service_role;


--
-- Name: TABLE point_clouds; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.point_clouds TO postgres;
GRANT ALL ON TABLE public.point_clouds TO anon;
GRANT ALL ON TABLE public.point_clouds TO authenticated;
GRANT ALL ON TABLE public.point_clouds TO service_role;


--
-- Name: TABLE qsms; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.qsms TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.qsms TO authenticated;
GRANT ALL ON TABLE trees.qsms TO service_role;


--
-- Name: TABLE qsms; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.qsms TO postgres;
GRANT ALL ON TABLE public.qsms TO anon;
GRANT ALL ON TABLE public.qsms TO authenticated;
GRANT ALL ON TABLE public.qsms TO service_role;


--
-- Name: TABLE regeneration; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.regeneration TO postgres;
GRANT ALL ON TABLE public.regeneration TO anon;
GRANT ALL ON TABLE public.regeneration TO authenticated;
GRANT ALL ON TABLE public.regeneration TO service_role;


--
-- Name: TABLE regeneration_per_ha; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.regeneration_per_ha TO postgres;
GRANT ALL ON TABLE public.regeneration_per_ha TO anon;
GRANT ALL ON TABLE public.regeneration_per_ha TO authenticated;
GRANT ALL ON TABLE public.regeneration_per_ha TO service_role;


--
-- Name: TABLE root_system_types; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.root_system_types TO anon;
GRANT SELECT ON TABLE trees.root_system_types TO authenticated;
GRANT ALL ON TABLE trees.root_system_types TO service_role;


--
-- Name: TABLE root_system_types; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.root_system_types TO postgres;
GRANT ALL ON TABLE public.root_system_types TO anon;
GRANT ALL ON TABLE public.root_system_types TO authenticated;
GRANT ALL ON TABLE public.root_system_types TO service_role;


--
-- Name: TABLE roots; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.roots TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.roots TO authenticated;
GRANT ALL ON TABLE trees.roots TO service_role;


--
-- Name: TABLE roots; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.roots TO postgres;
GRANT ALL ON TABLE public.roots TO anon;
GRANT ALL ON TABLE public.roots TO authenticated;
GRANT ALL ON TABLE public.roots TO service_role;


--
-- Name: TABLE sampling_designs; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.sampling_designs TO postgres;
GRANT ALL ON TABLE public.sampling_designs TO anon;
GRANT ALL ON TABLE public.sampling_designs TO authenticated;
GRANT ALL ON TABLE public.sampling_designs TO service_role;


--
-- Name: TABLE scenarios; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.scenarios TO postgres;
GRANT ALL ON TABLE public.scenarios TO anon;
GRANT ALL ON TABLE public.scenarios TO authenticated;
GRANT ALL ON TABLE public.scenarios TO service_role;


--
-- Name: TABLE sensor_readings; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.sensor_readings TO postgres;
GRANT ALL ON TABLE public.sensor_readings TO anon;
GRANT ALL ON TABLE public.sensor_readings TO authenticated;
GRANT ALL ON TABLE public.sensor_readings TO service_role;


--
-- Name: TABLE sensor_tree_links; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT ALL ON TABLE sensor.sensor_tree_links TO service_role;
GRANT SELECT ON TABLE sensor.sensor_tree_links TO authenticated;
GRANT SELECT ON TABLE sensor.sensor_tree_links TO anon;


--
-- Name: TABLE sensor_tree_links; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.sensor_tree_links TO postgres;
GRANT ALL ON TABLE public.sensor_tree_links TO anon;
GRANT ALL ON TABLE public.sensor_tree_links TO authenticated;
GRANT ALL ON TABLE public.sensor_tree_links TO service_role;


--
-- Name: TABLE sensor_types; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.sensor_types TO postgres;
GRANT ALL ON TABLE public.sensor_types TO anon;
GRANT ALL ON TABLE public.sensor_types TO authenticated;
GRANT ALL ON TABLE public.sensor_types TO service_role;


--
-- Name: TABLE sensors; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.sensors TO postgres;
GRANT ALL ON TABLE public.sensors TO anon;
GRANT ALL ON TABLE public.sensors TO authenticated;
GRANT ALL ON TABLE public.sensors TO service_role;


--
-- Name: TABLE shoot_elongation_types; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.shoot_elongation_types TO authenticated;


--
-- Name: TABLE shoot_elongation_types; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.shoot_elongation_types TO postgres;
GRANT ALL ON TABLE public.shoot_elongation_types TO anon;
GRANT ALL ON TABLE public.shoot_elongation_types TO authenticated;
GRANT ALL ON TABLE public.shoot_elongation_types TO service_role;


--
-- Name: TABLE variants; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.variants TO anon;
GRANT SELECT ON TABLE shared.variants TO authenticated;
GRANT ALL ON TABLE shared.variants TO service_role;


--
-- Name: TABLE simulation_runs; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.simulation_runs TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.simulation_runs TO authenticated;
GRANT ALL ON TABLE trees.simulation_runs TO service_role;


--
-- Name: TABLE simulation_runs; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.simulation_runs TO postgres;
GRANT ALL ON TABLE public.simulation_runs TO anon;
GRANT ALL ON TABLE public.simulation_runs TO authenticated;
GRANT ALL ON TABLE public.simulation_runs TO service_role;


--
-- Name: TABLE species; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.species TO postgres;
GRANT ALL ON TABLE public.species TO anon;
GRANT ALL ON TABLE public.species TO authenticated;
GRANT ALL ON TABLE public.species TO service_role;


--
-- Name: TABLE stand_summaries; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.stand_summaries TO postgres;
GRANT ALL ON TABLE public.stand_summaries TO anon;
GRANT ALL ON TABLE public.stand_summaries TO authenticated;
GRANT ALL ON TABLE public.stand_summaries TO service_role;


--
-- Name: TABLE stems; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.stems TO postgres;
GRANT ALL ON TABLE public.stems TO anon;
GRANT ALL ON TABLE public.stems TO authenticated;
GRANT ALL ON TABLE public.stems TO service_role;


--
-- Name: TABLE strata; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.strata TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.strata TO authenticated;
GRANT ALL ON TABLE shared.strata TO service_role;


--
-- Name: TABLE strata; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.strata TO postgres;
GRANT ALL ON TABLE public.strata TO anon;
GRANT ALL ON TABLE public.strata TO authenticated;
GRANT ALL ON TABLE public.strata TO service_role;


--
-- Name: TABLE teams; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.teams TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.teams TO authenticated;
GRANT ALL ON TABLE shared.teams TO service_role;


--
-- Name: TABLE teams; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.teams TO postgres;
GRANT ALL ON TABLE public.teams TO anon;
GRANT ALL ON TABLE public.teams TO authenticated;
GRANT ALL ON TABLE public.teams TO service_role;


--
-- Name: TABLE tree_expansion_factors; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.tree_expansion_factors TO postgres;
GRANT ALL ON TABLE public.tree_expansion_factors TO anon;
GRANT ALL ON TABLE public.tree_expansion_factors TO authenticated;
GRANT ALL ON TABLE public.tree_expansion_factors TO service_role;


--
-- Name: TABLE tree_graph_edges; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.tree_graph_edges TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.tree_graph_edges TO authenticated;
GRANT ALL ON TABLE trees.tree_graph_edges TO service_role;


--
-- Name: TABLE tree_graph_edges; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.tree_graph_edges TO postgres;
GRANT ALL ON TABLE public.tree_graph_edges TO anon;
GRANT ALL ON TABLE public.tree_graph_edges TO authenticated;
GRANT ALL ON TABLE public.tree_graph_edges TO service_role;


--
-- Name: TABLE tree_part_types; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.tree_part_types TO anon;
GRANT SELECT ON TABLE trees.tree_part_types TO authenticated;
GRANT ALL ON TABLE trees.tree_part_types TO service_role;


--
-- Name: TABLE tree_part_types; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.tree_part_types TO postgres;
GRANT ALL ON TABLE public.tree_part_types TO anon;
GRANT ALL ON TABLE public.tree_part_types TO authenticated;
GRANT ALL ON TABLE public.tree_part_types TO service_role;


--
-- Name: TABLE trees; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.trees TO postgres;
GRANT ALL ON TABLE public.trees TO anon;
GRANT ALL ON TABLE public.trees TO authenticated;
GRANT ALL ON TABLE public.trees TO service_role;


--
-- Name: TABLE ue_climate; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_climate TO postgres;
GRANT ALL ON TABLE public.ue_climate TO anon;
GRANT ALL ON TABLE public.ue_climate TO authenticated;
GRANT ALL ON TABLE public.ue_climate TO service_role;


--
-- Name: TABLE ue_environments; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_environments TO postgres;
GRANT ALL ON TABLE public.ue_environments TO anon;
GRANT ALL ON TABLE public.ue_environments TO authenticated;
GRANT ALL ON TABLE public.ue_environments TO service_role;


--
-- Name: TABLE ue_scenarios; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_scenarios TO postgres;
GRANT ALL ON TABLE public.ue_scenarios TO anon;
GRANT ALL ON TABLE public.ue_scenarios TO authenticated;
GRANT ALL ON TABLE public.ue_scenarios TO service_role;


--
-- Name: TABLE ue_sensors; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_sensors TO postgres;
GRANT ALL ON TABLE public.ue_sensors TO anon;
GRANT ALL ON TABLE public.ue_sensors TO authenticated;
GRANT ALL ON TABLE public.ue_sensors TO service_role;


--
-- Name: TABLE ue_stand_summary; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_stand_summary TO postgres;
GRANT ALL ON TABLE public.ue_stand_summary TO anon;
GRANT ALL ON TABLE public.ue_stand_summary TO authenticated;
GRANT ALL ON TABLE public.ue_stand_summary TO service_role;


--
-- Name: TABLE ue_trees; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_trees TO postgres;
GRANT ALL ON TABLE public.ue_trees TO anon;
GRANT ALL ON TABLE public.ue_trees TO authenticated;
GRANT ALL ON TABLE public.ue_trees TO service_role;


--
-- Name: TABLE ue_variants; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ue_variants TO postgres;
GRANT ALL ON TABLE public.ue_variants TO anon;
GRANT ALL ON TABLE public.ue_variants TO authenticated;
GRANT ALL ON TABLE public.ue_variants TO service_role;


--
-- Name: TABLE variant_types; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.variant_types TO postgres;
GRANT ALL ON TABLE public.variant_types TO anon;
GRANT ALL ON TABLE public.variant_types TO authenticated;
GRANT ALL ON TABLE public.variant_types TO service_role;


--
-- Name: TABLE variants; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.variants TO postgres;
GRANT ALL ON TABLE public.variants TO anon;
GRANT ALL ON TABLE public.variants TO authenticated;
GRANT ALL ON TABLE public.variants TO service_role;


--
-- Name: TABLE workflows; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.workflows TO postgres;
GRANT ALL ON TABLE public.workflows TO anon;
GRANT ALL ON TABLE public.workflows TO authenticated;
GRANT ALL ON TABLE public.workflows TO service_role;


--
-- Name: TABLE active_sensors_status; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT ON TABLE sensor.active_sensors_status TO anon;
GRANT SELECT ON TABLE sensor.active_sensors_status TO authenticated;
GRANT ALL ON TABLE sensor.active_sensors_status TO service_role;


--
-- Name: SEQUENCE sensor_readings_sensor_reading_id_seq; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_readings_sensor_reading_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_readings_sensor_reading_id_seq TO service_role;


--
-- Name: SEQUENCE sensor_tree_links_sensor_tree_link_id_seq; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_tree_links_sensor_tree_link_id_seq TO service_role;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_tree_links_sensor_tree_link_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_tree_links_sensor_tree_link_id_seq TO anon;


--
-- Name: TABLE sensor_tree_view; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT ON TABLE sensor.sensor_tree_view TO authenticated;
GRANT SELECT ON TABLE sensor.sensor_tree_view TO anon;


--
-- Name: SEQUENCE sensor_types_sensor_type_id_seq; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_types_sensor_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensor_types_sensor_type_id_seq TO service_role;


--
-- Name: SEQUENCE sensors_sensor_id_seq; Type: ACL; Schema: sensor; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE sensor.sensors_sensor_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE sensor.sensors_sensor_id_seq TO service_role;


--
-- Name: TABLE account_events; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.account_events TO authenticated;
GRANT ALL ON TABLE shared.account_events TO service_role;


--
-- Name: SEQUENCE attribute_provenance_attribute_provenance_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE shared.attribute_provenance_attribute_provenance_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.attribute_provenance_attribute_provenance_id_seq TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.audit_log TO anon;
GRANT SELECT ON TABLE shared.audit_log TO authenticated;
GRANT ALL ON TABLE shared.audit_log TO service_role;


--
-- Name: SEQUENCE audit_log_audit_log_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.audit_log_audit_log_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.audit_log_audit_log_id_seq TO service_role;


--
-- Name: TABLE audit_log_environments; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.audit_log_environments TO authenticated;


--
-- Name: TABLE audit_log_point_clouds; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.audit_log_point_clouds TO authenticated;


--
-- Name: TABLE audit_log_stems; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.audit_log_stems TO authenticated;


--
-- Name: TABLE audit_log_trees; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.audit_log_trees TO authenticated;


--
-- Name: SEQUENCE campaigns_campaign_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.campaigns_campaign_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.campaigns_campaign_id_seq TO service_role;


--
-- Name: TABLE climate_zones; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.climate_zones TO anon;
GRANT SELECT ON TABLE shared.climate_zones TO authenticated;
GRANT ALL ON TABLE shared.climate_zones TO service_role;


--
-- Name: SEQUENCE climate_zones_climate_zone_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.climate_zones_climate_zone_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.climate_zones_climate_zone_id_seq TO service_role;


--
-- Name: SEQUENCE disturbance_events_disturbance_event_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.disturbance_events_disturbance_event_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.disturbance_events_disturbance_event_id_seq TO service_role;


--
-- Name: TABLE disturbance_events_trees; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.disturbance_events_trees TO authenticated;


--
-- Name: SEQUENCE inclusion_rules_inclusion_rule_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE shared.inclusion_rules_inclusion_rule_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.inclusion_rules_inclusion_rule_id_seq TO service_role;


--
-- Name: SEQUENCE locations_location_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.locations_location_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.locations_location_id_seq TO service_role;


--
-- Name: SEQUENCE management_events_management_event_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.management_events_management_event_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.management_events_management_event_id_seq TO service_role;


--
-- Name: SEQUENCE plots_plot_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.plots_plot_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.plots_plot_id_seq TO service_role;


--
-- Name: TABLE process_metrics; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.process_metrics TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.process_metrics TO authenticated;
GRANT ALL ON TABLE shared.process_metrics TO service_role;


--
-- Name: SEQUENCE process_metrics_process_metric_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.process_metrics_process_metric_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.process_metrics_process_metric_id_seq TO service_role;


--
-- Name: TABLE process_parameters; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.process_parameters TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.process_parameters TO authenticated;
GRANT ALL ON TABLE shared.process_parameters TO service_role;


--
-- Name: TABLE process_parameters_environments; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.process_parameters_environments TO authenticated;


--
-- Name: TABLE process_parameters_point_clouds; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.process_parameters_point_clouds TO authenticated;


--
-- Name: SEQUENCE process_parameters_process_parameter_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.process_parameters_process_parameter_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.process_parameters_process_parameter_id_seq TO service_role;


--
-- Name: TABLE process_parameters_stems; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.process_parameters_stems TO authenticated;


--
-- Name: TABLE process_parameters_trees; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE shared.process_parameters_trees TO authenticated;


--
-- Name: SEQUENCE processes_process_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.processes_process_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.processes_process_id_seq TO service_role;


--
-- Name: SEQUENCE processing_jobs_processing_job_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.processing_jobs_processing_job_id_seq TO service_role;
GRANT SELECT,USAGE ON SEQUENCE shared.processing_jobs_processing_job_id_seq TO authenticated;


--
-- Name: SEQUENCE sampling_designs_sampling_design_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE shared.sampling_designs_sampling_design_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.sampling_designs_sampling_design_id_seq TO service_role;


--
-- Name: SEQUENCE scenarios_scenario_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.scenarios_scenario_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.scenarios_scenario_id_seq TO service_role;


--
-- Name: TABLE soil_types; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.soil_types TO anon;
GRANT SELECT ON TABLE shared.soil_types TO authenticated;
GRANT ALL ON TABLE shared.soil_types TO service_role;


--
-- Name: SEQUENCE soil_types_soil_type_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.soil_types_soil_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.soil_types_soil_type_id_seq TO service_role;


--
-- Name: SEQUENCE species_species_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.species_species_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.species_species_id_seq TO service_role;


--
-- Name: SEQUENCE strata_stratum_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE shared.strata_stratum_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.strata_stratum_id_seq TO service_role;


--
-- Name: TABLE team_members; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT ON TABLE shared.team_members TO authenticated;
GRANT ALL ON TABLE shared.team_members TO service_role;


--
-- Name: SEQUENCE teams_team_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE shared.teams_team_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.teams_team_id_seq TO service_role;


--
-- Name: SEQUENCE variant_types_variant_type_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.variant_types_variant_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.variant_types_variant_type_id_seq TO service_role;


--
-- Name: SEQUENCE variants_variant_id_seq; Type: ACL; Schema: shared; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE shared.variants_variant_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE shared.variants_variant_id_seq TO service_role;


--
-- Name: TABLE bark_characteristics; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.bark_characteristics TO anon;
GRANT SELECT ON TABLE trees.bark_characteristics TO authenticated;
GRANT ALL ON TABLE trees.bark_characteristics TO service_role;


--
-- Name: SEQUENCE bark_characteristics_bark_characteristic_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.bark_characteristics_bark_characteristic_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.bark_characteristics_bark_characteristic_id_seq TO service_role;


--
-- Name: TABLE branching_patterns; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.branching_patterns TO anon;
GRANT SELECT ON TABLE trees.branching_patterns TO authenticated;
GRANT ALL ON TABLE trees.branching_patterns TO service_role;


--
-- Name: SEQUENCE branching_patterns_branching_pattern_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.branching_patterns_branching_pattern_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.branching_patterns_branching_pattern_id_seq TO service_role;


--
-- Name: SEQUENCE crown_foliage_profiles_crown_foliage_profile_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.crown_foliage_profiles_crown_foliage_profile_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.crown_foliage_profiles_crown_foliage_profile_id_seq TO service_role;


--
-- Name: SEQUENCE data_source_types_data_source_type_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.data_source_types_data_source_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.data_source_types_data_source_type_id_seq TO service_role;


--
-- Name: SEQUENCE entity_matches_entity_match_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE trees.entity_matches_entity_match_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.entity_matches_entity_match_id_seq TO service_role;


--
-- Name: SEQUENCE growth_simulations_growth_simulation_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.growth_simulations_growth_simulation_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.growth_simulations_growth_simulation_id_seq TO postgres;


--
-- Name: SEQUENCE observations_observation_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE trees.observations_observation_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.observations_observation_id_seq TO service_role;


--
-- Name: SEQUENCE phenology_observations_phenology_observation_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.phenology_observations_phenology_observation_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.phenology_observations_phenology_observation_id_seq TO service_role;


--
-- Name: TABLE qsm_cylinders; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.qsm_cylinders TO anon;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE trees.qsm_cylinders TO authenticated;
GRANT ALL ON TABLE trees.qsm_cylinders TO service_role;


--
-- Name: SEQUENCE qsm_cylinders_qsm_cylinder_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.qsm_cylinders_qsm_cylinder_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.qsm_cylinders_qsm_cylinder_id_seq TO service_role;


--
-- Name: SEQUENCE qsms_qsm_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.qsms_qsm_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.qsms_qsm_id_seq TO service_role;


--
-- Name: SEQUENCE root_system_types_root_system_type_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE trees.root_system_types_root_system_type_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.root_system_types_root_system_type_id_seq TO service_role;


--
-- Name: SEQUENCE roots_root_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.roots_root_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.roots_root_id_seq TO service_role;


--
-- Name: SEQUENCE stems_stem_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.stems_stem_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.stems_stem_id_seq TO service_role;


--
-- Name: TABLE straightness_types; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.straightness_types TO anon;
GRANT SELECT ON TABLE trees.straightness_types TO authenticated;
GRANT ALL ON TABLE trees.straightness_types TO service_role;


--
-- Name: SEQUENCE straightness_types_straightness_type_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.straightness_types_straightness_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.straightness_types_straightness_type_id_seq TO service_role;


--
-- Name: TABLE taper_types; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.taper_types TO anon;
GRANT SELECT ON TABLE trees.taper_types TO authenticated;
GRANT ALL ON TABLE trees.taper_types TO service_role;


--
-- Name: SEQUENCE taper_types_taper_type_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.taper_types_taper_type_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.taper_types_taper_type_id_seq TO service_role;


--
-- Name: SEQUENCE tree_graph_edges_tree_graph_edge_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.tree_graph_edges_tree_graph_edge_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.tree_graph_edges_tree_graph_edge_id_seq TO service_role;


--
-- Name: SEQUENCE tree_part_types_part_type_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT USAGE ON SEQUENCE trees.tree_part_types_part_type_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.tree_part_types_part_type_id_seq TO service_role;


--
-- Name: SEQUENCE tree_status_tree_status_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.tree_status_tree_status_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.tree_status_tree_status_id_seq TO service_role;


--
-- Name: SEQUENCE trees_tree_id_seq; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE trees.trees_tree_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.trees_tree_id_seq TO service_role;


--
-- Name: TABLE trees_with_metrics; Type: ACL; Schema: trees; Owner: supabase_admin
--

GRANT SELECT ON TABLE trees.trees_with_metrics TO anon;
GRANT SELECT ON TABLE trees.trees_with_metrics TO authenticated;
GRANT ALL ON TABLE trees.trees_with_metrics TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: environments; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA environments GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: forest_floor; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA forest_floor GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: imagery; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA imagery GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: point_clouds; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA point_clouds GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: sensor; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA sensor GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: shared; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA shared GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: trees; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA trees GRANT ALL ON FUNCTIONS  TO service_role;


--
-- PostgreSQL database dump complete
--


-- New functions are closed to PUBLIC (migration 20261109100000): a global
-- default, which a schema-scoped dump does not carry.
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
