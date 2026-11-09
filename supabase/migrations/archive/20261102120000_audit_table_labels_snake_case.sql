-- Name the audited tables by their table names in the audit functions.
--
-- shared.create_audit_log() and shared.get_audit_history() took a CamelCase
-- label ('PointClouds', 'Trees', 'Environments', 'Stems',
-- 'PhenologyObservations') to pick the link table, and shared.recent_changes
-- and shared.revert_field_change() returned the same labels. Every other name
-- in the database is snake_case, and the audit triggers already switch on
-- TG_TABLE_NAME, so the labels are now the table names: 'point_clouds',
-- 'trees', 'environments', 'stems', 'phenology_observations'.
--
-- No stored data changes: shared.audit_log has no table column; the table is
-- given by which shared.audit_log_<table> link row exists.
--
-- A caller still passing an old label now gets an error from both functions
-- (create_audit_log: CASE not found; get_audit_history: "Unknown table name")
-- instead of an empty history.

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
        WHEN 'point_clouds' THEN
            INSERT INTO shared.audit_log_point_clouds (audit_log_id, point_cloud_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'trees' THEN
            INSERT INTO shared.audit_log_trees (audit_log_id, tree_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'environments' THEN
            INSERT INTO shared.audit_log_environments (audit_log_id, environment_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'stems' THEN
            INSERT INTO shared.audit_log_stems (audit_log_id, stem_id)
            VALUES (v_audit_id, variant_id_param);
        WHEN 'phenology_observations' THEN
            INSERT INTO shared.audit_log_phenology_observations (audit_log_id, phenology_observation_id)
            VALUES (v_audit_id, variant_id_param);
    END CASE;
    RETURN v_audit_id;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.get_audit_history(table_name_param character varying, variant_id_param integer, limit_param integer DEFAULT 100)
 RETURNS TABLE(audit_log_id bigint, field_name character varying, old_value text, new_value text, change_reason text, user_id character varying, "Timestamp" timestamp with time zone, change_type character varying)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
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
        table_name := 'point_clouds';
        SELECT point_cloud_id INTO variant_id FROM shared.audit_log_point_clouds WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_trees WHERE audit_log_id = audit_id_param) THEN
        table_name := 'trees';
        SELECT tree_id INTO variant_id FROM shared.audit_log_trees WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_environments WHERE audit_log_id = audit_id_param) THEN
        table_name := 'environments';
        SELECT environment_id INTO variant_id FROM shared.audit_log_environments WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_stems WHERE audit_log_id = audit_id_param) THEN
        table_name := 'stems';
        SELECT stem_id INTO variant_id FROM shared.audit_log_stems WHERE audit_log_id = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.audit_log_phenology_observations WHERE audit_log_id = audit_id_param) THEN
        table_name := 'phenology_observations';
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

CREATE OR REPLACE VIEW shared.recent_changes AS
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
