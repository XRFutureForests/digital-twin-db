-- =============================================================================
-- Restructure Deadwood/GroundVegetation out of trees schema; add
-- PhenologyObservations audit logging
-- =============================================================================
-- Decision (XRFF-255): trees.Deadwood and trees.GroundVegetation are plot/site
-- level surveys (location_id + optional plot_id; Deadwood.tree_id is only an
-- optional link to a known dead tree) -- not per-tree data, so they move to
-- their own schema. trees.PhenologyObservations IS genuinely per-tree
-- (tree_id NOT NULL, ON DELETE CASCADE) and stays, brought up to the same
-- audit-logging standard as Trees/Stems/Environments/PointClouds.
-- All three tables were verified empty (0 rows) before this migration.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Move Deadwood and GroundVegetation into their own schema
-- -----------------------------------------------------------------------------
-- ALTER TABLE ... SET SCHEMA moves the table, its indexes, constraints,
-- comments, RLS policies, table-level grants, and owned sequences together --
-- no need to redefine any of that. Public API views (public.deadwood,
-- public.groundvegetation) resolve by relation OID, not by schema-qualified
-- text, so they keep working unchanged; verified via throwaway container.

CREATE SCHEMA IF NOT EXISTS forest_floor;

ALTER TABLE trees.deadwood SET SCHEMA forest_floor;
ALTER TABLE trees.groundvegetation SET SCHEMA forest_floor;

GRANT USAGE ON SCHEMA forest_floor TO anon, authenticated, service_role;

COMMENT ON SCHEMA forest_floor IS 'Plot/site-level forest floor surveys (deadwood, ground vegetation) -- not tied to a single tree';

-- The public.deadwood / public.groundvegetation views' INSTEAD OF INSERT
-- trigger functions hardcode the target table by schema-qualified name in
-- their body text -- unlike plain views (resolved by relation OID), trigger
-- function bodies are opaque text to Postgres's dependency tracker and do
-- NOT get repointed by ALTER TABLE ... SET SCHEMA. Repoint them explicitly.

CREATE OR REPLACE FUNCTION public.deadwood_insert() RETURNS trigger
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

COMMENT ON FUNCTION public.deadwood_insert IS 'INSTEAD OF INSERT trigger function for public.deadwood view';

CREATE OR REPLACE FUNCTION public.groundvegetation_insert() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO forest_floor.groundvegetation (
        location_id, plot_id, species_name, cover_percent,
        height_cm, layer, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.species_name, NEW.cover_percent,
        NEW.height_cm, NEW.layer, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING ground_vegetation_id INTO NEW.ground_vegetation_id;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.groundvegetation_insert IS 'INSTEAD OF INSERT trigger function for public.groundvegetation view';

-- -----------------------------------------------------------------------------
-- 2. PhenologyObservations audit logging
-- -----------------------------------------------------------------------------
-- Mirrors the existing Trees/Stems/Environments/PointClouds pattern in
-- shared.create_audit_log / get_audit_history / revert_field_change /
-- audit_update_trigger / recent_changes. Audits phenophase_status and
-- intensity_percent -- the fields that actually change over the life of an
-- observation, matching how the other tables audit their "measurement"
-- fields rather than administrative ones.

CREATE TABLE shared.auditlog_phenologyobservations (
    audit_id bigint NOT NULL REFERENCES shared.auditlog(audit_id) ON DELETE CASCADE,
    phenology_observation_id integer NOT NULL REFERENCES trees.phenologyobservations(phenology_observation_id) ON DELETE CASCADE,
    PRIMARY KEY (audit_id, phenology_observation_id)
);

COMMENT ON TABLE shared.auditlog_phenologyobservations IS 'Links audit log entries to phenology observation records';

CREATE INDEX idx_audit_phenologyobservations_audit ON shared.auditlog_phenologyobservations(audit_id);
CREATE INDEX idx_audit_phenologyobservations_phenology ON shared.auditlog_phenologyobservations(phenology_observation_id);

CREATE OR REPLACE FUNCTION shared.create_audit_log(
    table_name_param character varying,
    variant_id_param integer,
    field_name_param character varying,
    old_value_param text,
    new_value_param text,
    change_reason_param text DEFAULT NULL::text,
    change_type_param character varying DEFAULT 'field_update'::character varying
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_audit_id BIGINT;
BEGIN
    INSERT INTO shared.AuditLog (
        field_name, old_value, new_value, change_reason,
        user_id, change_type, ip_address
    ) VALUES (
        field_name_param, old_value_param, new_value_param, change_reason_param,
        auth.uid()::TEXT, change_type_param, inet_client_addr()
    )
    RETURNING audit_id INTO v_audit_id;

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
        WHEN 'PhenologyObservations' THEN
            INSERT INTO shared.auditlog_phenologyobservations (audit_id, phenology_observation_id)
            VALUES (v_audit_id, variant_id_param);
    END CASE;

    RETURN v_audit_id;
END;
$$;

COMMENT ON FUNCTION shared.create_audit_log IS 'Creates audit log entry with junction table link';

CREATE OR REPLACE FUNCTION shared.get_audit_history(
    table_name_param character varying,
    variant_id_param integer,
    limit_param integer DEFAULT 100
) RETURNS TABLE(
    audit_id bigint,
    field_name character varying,
    old_value text,
    new_value text,
    change_reason text,
    user_id character varying,
    "Timestamp" timestamp with time zone,
    change_type character varying
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
BEGIN
    IF table_name_param = 'PointClouds' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_PointClouds alpc ON al.audit_id = alpc.audit_id
            WHERE alpc.point_cloud_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Trees' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Trees alt ON al.audit_id = alt.audit_id
            WHERE alt.tree_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Environments' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Environments ale ON al.audit_id = ale.audit_id
            WHERE ale.environment_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'Stems' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Stems als ON al.audit_id = als.audit_id
            WHERE als.stem_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    ELSIF table_name_param = 'PhenologyObservations' THEN
        RETURN QUERY
            SELECT al.audit_id, al.field_name, al.old_value, al.new_value, al.change_reason,
                   al.user_id, al.Timestamp, al.change_type
            FROM shared.AuditLog al
            JOIN shared.auditlog_phenologyobservations alp ON al.audit_id = alp.audit_id
            WHERE alp.phenology_observation_id = variant_id_param
            ORDER BY al.Timestamp DESC LIMIT limit_param;
    END IF;
    RETURN;
END;
$$;

COMMENT ON FUNCTION shared.get_audit_history IS 'Retrieves audit history for a specific variant or record';

CREATE OR REPLACE FUNCTION shared.revert_field_change(
    audit_id_param bigint,
    change_reason_param text DEFAULT 'Reverted change'::text
) RETURNS boolean
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
    SELECT * INTO audit_record FROM shared.AuditLog WHERE audit_id = audit_id_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Audit record % not found', audit_id_param;
    END IF;

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
    ELSIF EXISTS (SELECT 1 FROM shared.auditlog_phenologyobservations WHERE audit_id = audit_id_param) THEN
        table_name := 'PhenologyObservations';
        SELECT phenology_observation_id INTO variant_id FROM shared.auditlog_phenologyobservations WHERE audit_id = audit_id_param;
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
$$;

COMMENT ON FUNCTION shared.revert_field_change IS 'Creates audit log entry for reverting a field change';

CREATE OR REPLACE FUNCTION shared.audit_update_trigger() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    audit_id BIGINT;
    record_id INTEGER;
BEGIN
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
                PERFORM shared.create_audit_log('Trees', record_id, 'Height_m', OLD.Height_m::TEXT, NEW.Height_m::TEXT, NULL, 'field_update');
            END IF;
            IF OLD.crown_width_m IS DISTINCT FROM NEW.crown_width_m THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'crown_width_m', OLD.crown_width_m::TEXT, NEW.crown_width_m::TEXT, NULL, 'field_update');
            END IF;
            IF OLD.health_score IS DISTINCT FROM NEW.health_score THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'health_score', OLD.health_score::TEXT, NEW.health_score::TEXT, NULL, 'field_update');
            END IF;
            IF OLD.tree_status_id IS DISTINCT FROM NEW.tree_status_id THEN
                PERFORM shared.create_audit_log('Trees', record_id, 'tree_status_id', OLD.tree_status_id::TEXT, NEW.tree_status_id::TEXT, NULL, 'field_update');
            END IF;

        WHEN 'stems' THEN
            IF OLD.DBH_cm IS DISTINCT FROM NEW.DBH_cm THEN
                PERFORM shared.create_audit_log('Stems', record_id, 'DBH_cm', OLD.DBH_cm::TEXT, NEW.DBH_cm::TEXT, NULL, 'field_update');
            END IF;
            IF OLD.stem_height_m IS DISTINCT FROM NEW.stem_height_m THEN
                PERFORM shared.create_audit_log('Stems', record_id, 'stem_height_m', OLD.stem_height_m::TEXT, NEW.stem_height_m::TEXT, NULL, 'field_update');
            END IF;

        WHEN 'environments' THEN
            IF OLD.avg_temperature_c IS DISTINCT FROM NEW.avg_temperature_c THEN
                PERFORM shared.create_audit_log('Environments', record_id, 'avg_temperature_c', OLD.avg_temperature_c::TEXT, NEW.avg_temperature_c::TEXT, NULL, 'field_update');
            END IF;
            IF OLD.stress_factor IS DISTINCT FROM NEW.stress_factor THEN
                PERFORM shared.create_audit_log('Environments', record_id, 'stress_factor', OLD.stress_factor::TEXT, NEW.stress_factor::TEXT, NULL, 'field_update');
            END IF;

        WHEN 'pointclouds' THEN
            IF OLD.processing_status IS DISTINCT FROM NEW.processing_status THEN
                PERFORM shared.create_audit_log('PointClouds', record_id, 'processing_status', OLD.processing_status::TEXT, NEW.processing_status::TEXT, NULL, 'field_update');
            END IF;

        WHEN 'phenologyobservations' THEN
            IF OLD.phenophase_status IS DISTINCT FROM NEW.phenophase_status THEN
                PERFORM shared.create_audit_log('PhenologyObservations', record_id, 'phenophase_status', OLD.phenophase_status::TEXT, NEW.phenophase_status::TEXT, NULL, 'field_update');
            END IF;
            IF OLD.intensity_percent IS DISTINCT FROM NEW.intensity_percent THEN
                PERFORM shared.create_audit_log('PhenologyObservations', record_id, 'intensity_percent', OLD.intensity_percent::TEXT, NEW.intensity_percent::TEXT, NULL, 'field_update');
            END IF;
    END CASE;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION shared.audit_update_trigger IS 'Automatically creates audit log entries for critical field updates';

DROP TRIGGER IF EXISTS trigger_phenology_audit ON trees.phenologyobservations;
CREATE TRIGGER trigger_phenology_audit
    AFTER UPDATE ON trees.phenologyobservations
    FOR EACH ROW
    EXECUTE FUNCTION shared.audit_update_trigger();

CREATE OR REPLACE VIEW shared.recent_changes AS
SELECT
    al.audit_id,
    COALESCE(
        CASE WHEN alpc.point_cloud_id IS NOT NULL THEN 'PointClouds'
             WHEN alt.tree_id IS NOT NULL THEN 'Trees'
             WHEN ale.environment_id IS NOT NULL THEN 'Environments'
             WHEN als.stem_id IS NOT NULL THEN 'Stems'
             WHEN alp.phenology_observation_id IS NOT NULL THEN 'PhenologyObservations'
        END
    ) AS table_name,
    COALESCE(alpc.point_cloud_id, alt.tree_id, ale.environment_id, als.stem_id, alp.phenology_observation_id) AS record_id,
    al.field_name,
    al.old_value,
    al.new_value,
    al.change_type,
    al.user_id,
    al.Timestamp,
    al.change_reason
FROM shared.AuditLog al
LEFT JOIN shared.AuditLog_PointClouds alpc ON al.audit_id = alpc.audit_id
LEFT JOIN shared.AuditLog_Trees alt ON al.audit_id = alt.audit_id
LEFT JOIN shared.AuditLog_Environments ale ON al.audit_id = ale.audit_id
LEFT JOIN shared.AuditLog_Stems als ON al.audit_id = als.audit_id
LEFT JOIN shared.auditlog_phenologyobservations alp ON al.audit_id = alp.audit_id
ORDER BY al.Timestamp DESC;

COMMENT ON VIEW shared.recent_changes IS 'Unified view of recent changes across all audited tables';
