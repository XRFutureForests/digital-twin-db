-- XR Future Forests Lab - Audit Functions and Triggers
-- This migration implements automatic audit logging for data changes

-- =============================================================================
-- AUDIT LOGGING FUNCTIONS
-- =============================================================================

-- Function to create audit log entry
CREATE OR REPLACE FUNCTION shared.create_audit_log(
    table_name_param VARCHAR,
    variant_id_param INTEGER,
    field_name_param VARCHAR,
    old_value_param TEXT,
    new_value_param TEXT,
    change_reason_param TEXT DEFAULT NULL,
    change_type_param VARCHAR DEFAULT 'field_update'
)
RETURNS BIGINT AS $$
DECLARE
    audit_id BIGINT;
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
    RETURNING audit_id INTO audit_id;

    -- Create junction table entry based on table name
    CASE table_name_param
        WHEN 'PointClouds' THEN
            INSERT INTO shared.AuditLog_PointClouds (audit_id, point_cloud_id)
            VALUES (audit_id, variant_id_param);
        WHEN 'Trees' THEN
            INSERT INTO shared.AuditLog_Trees (audit_id, tree_id)
            VALUES (audit_id, variant_id_param);
        WHEN 'Environments' THEN
            INSERT INTO shared.AuditLog_Environments (audit_id, environment_id)
            VALUES (audit_id, variant_id_param);
        WHEN 'Stems' THEN
            INSERT INTO shared.AuditLog_Stems (audit_id, stem_id)
            VALUES (audit_id, variant_id_param);
    END CASE;

    RETURN audit_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION shared.create_audit_log IS 'Creates audit log entry with junction table link';

-- Function to get audit history for a variant
CREATE OR REPLACE FUNCTION shared.get_audit_history(
    table_name_param VARCHAR,
    variant_id_param INTEGER,
    limit_param INTEGER DEFAULT 100
)
RETURNS TABLE (
    audit_id BIGINT,
    field_name VARCHAR,
    old_value TEXT,
    new_value TEXT,
    change_reason TEXT,
    user_id VARCHAR,
    "Timestamp" TIMESTAMPTZ,
    change_type VARCHAR
) AS $$
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
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION shared.get_audit_history IS 'Retrieves audit history for a specific variant or record';

-- Function to revert a field change
CREATE OR REPLACE FUNCTION shared.revert_field_change(
    audit_id_param BIGINT,
    change_reason_param TEXT DEFAULT 'Reverted change'
)
RETURNS BOOLEAN AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION shared.revert_field_change IS 'Creates audit log entry for reverting a field change';

-- =============================================================================
-- AUTOMATIC AUDIT TRIGGERS
-- =============================================================================

-- Generic function to audit UPDATE operations
CREATE OR REPLACE FUNCTION shared.audit_update_trigger()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION shared.audit_update_trigger IS 'Automatically creates audit log entries for critical field updates';

-- Apply audit triggers
CREATE TRIGGER trigger_trees_audit
    AFTER UPDATE ON trees.Trees
    FOR EACH ROW
    EXECUTE FUNCTION shared.audit_update_trigger();

CREATE TRIGGER trigger_stems_audit
    AFTER UPDATE ON trees.Stems
    FOR EACH ROW
    EXECUTE FUNCTION shared.audit_update_trigger();

CREATE TRIGGER trigger_environments_audit
    AFTER UPDATE ON environments.Environments
    FOR EACH ROW
    EXECUTE FUNCTION shared.audit_update_trigger();

CREATE TRIGGER trigger_pointclouds_audit
    AFTER UPDATE ON pointclouds.PointClouds
    FOR EACH ROW
    EXECUTE FUNCTION shared.audit_update_trigger();

-- =============================================================================
-- HELPER VIEWS FOR AUDIT REPORTING
-- =============================================================================

-- View: Recent changes across all tables
CREATE OR REPLACE VIEW shared.recent_changes AS
SELECT
    al.audit_id,
    COALESCE(
        CASE WHEN alpc.point_cloud_id IS NOT NULL THEN 'PointClouds'
             WHEN alt.tree_id IS NOT NULL THEN 'Trees'
             WHEN ale.environment_id IS NOT NULL THEN 'Environments'
             WHEN als.stem_id IS NOT NULL THEN 'Stems'
        END
    ) AS table_name,
    COALESCE(alpc.point_cloud_id, alt.tree_id, ale.environment_id, als.stem_id) AS record_id,
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
ORDER BY al.Timestamp DESC;

COMMENT ON VIEW shared.recent_changes IS 'Unified view of recent changes across all audited tables';

-- View: User activity summary
CREATE OR REPLACE VIEW shared.user_activity_summary AS
SELECT
    user_id,
    COUNT(*) AS total_changes,
    COUNT(DISTINCT DATE(Timestamp)) AS active_days,
    MIN(Timestamp) AS first_change,
    MAX(Timestamp) AS last_change,
    COUNT(*) FILTER (WHERE change_type = 'field_update') AS field_updates,
    COUNT(*) FILTER (WHERE change_type = 'bulk_update') AS bulk_updates,
    COUNT(*) FILTER (WHERE change_type = 'revert') AS reverts
FROM shared.AuditLog
GROUP BY user_id;

COMMENT ON VIEW shared.user_activity_summary IS 'Summary of user activity and change patterns';

-- Grant permissions
GRANT EXECUTE ON FUNCTION shared.create_audit_log TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.get_audit_history TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.revert_field_change TO authenticated, service_role;
