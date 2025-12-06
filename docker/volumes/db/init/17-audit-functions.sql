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
        FieldName,
        OldValue,
        NewValue,
        ChangeReason,
        UserID,
        ChangeType,
        IPAddress
    ) VALUES (
        field_name_param,
        old_value_param,
        new_value_param,
        change_reason_param,
        auth.uid()::TEXT,
        change_type_param,
        inet_client_addr()
    )
    RETURNING AuditID INTO audit_id;

    -- Create junction table entry based on table name
    CASE table_name_param
        WHEN 'PointClouds' THEN
            INSERT INTO shared.AuditLog_PointClouds (AuditID, VariantID)
            VALUES (audit_id, variant_id_param);
        WHEN 'Trees' THEN
            INSERT INTO shared.AuditLog_Trees (AuditID, VariantID)
            VALUES (audit_id, variant_id_param);
        WHEN 'Environments' THEN
            INSERT INTO shared.AuditLog_Environments (AuditID, VariantID)
            VALUES (audit_id, variant_id_param);
        WHEN 'Stems' THEN
            INSERT INTO shared.AuditLog_Stems (AuditID, StemID)
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
    AuditID BIGINT,
    FieldName VARCHAR,
    OldValue TEXT,
    NewValue TEXT,
    ChangeReason TEXT,
    UserID VARCHAR,
    "Timestamp" TIMESTAMPTZ,
    ChangeType VARCHAR
) AS $$
BEGIN
    IF table_name_param = 'PointClouds' THEN
        RETURN QUERY
            SELECT
                al.AuditID,
                al.FieldName,
                al.OldValue,
                al.NewValue,
                al.ChangeReason,
                al.UserID,
                al.Timestamp,
                al.ChangeType
            FROM shared.AuditLog al
            JOIN shared.AuditLog_PointClouds alpc ON al.AuditID = alpc.AuditID
            WHERE alpc.VariantID = variant_id_param
            ORDER BY al.Timestamp DESC
            LIMIT limit_param;
    ELSIF table_name_param = 'Trees' THEN
        RETURN QUERY
            SELECT
                al.AuditID,
                al.FieldName,
                al.OldValue,
                al.NewValue,
                al.ChangeReason,
                al.UserID,
                al.Timestamp,
                al.ChangeType
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Trees alt ON al.AuditID = alt.AuditID
            WHERE alt.VariantID = variant_id_param
            ORDER BY al.Timestamp DESC
            LIMIT limit_param;
    ELSIF table_name_param = 'Environments' THEN
        RETURN QUERY
            SELECT
                al.AuditID,
                al.FieldName,
                al.OldValue,
                al.NewValue,
                al.ChangeReason,
                al.UserID,
                al.Timestamp,
                al.ChangeType
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Environments ale ON al.AuditID = ale.AuditID
            WHERE ale.VariantID = variant_id_param
            ORDER BY al.Timestamp DESC
            LIMIT limit_param;
    ELSIF table_name_param = 'Stems' THEN
        RETURN QUERY
            SELECT
                al.AuditID,
                al.FieldName,
                al.OldValue,
                al.NewValue,
                al.ChangeReason,
                al.UserID,
                al.Timestamp,
                al.ChangeType
            FROM shared.AuditLog al
            JOIN shared.AuditLog_Stems als ON al.AuditID = als.AuditID
            WHERE als.StemID = variant_id_param
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
    WHERE AuditID = audit_id_param;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Audit record % not found', audit_id_param;
    END IF;

    -- Determine table and variant from junction tables
    IF EXISTS (SELECT 1 FROM shared.AuditLog_PointClouds WHERE AuditID = audit_id_param) THEN
        table_name := 'PointClouds';
        SELECT VariantID INTO variant_id FROM shared.AuditLog_PointClouds WHERE AuditID = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.AuditLog_Trees WHERE AuditID = audit_id_param) THEN
        table_name := 'Trees';
        SELECT VariantID INTO variant_id FROM shared.AuditLog_Trees WHERE AuditID = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.AuditLog_Environments WHERE AuditID = audit_id_param) THEN
        table_name := 'Environments';
        SELECT VariantID INTO variant_id FROM shared.AuditLog_Environments WHERE AuditID = audit_id_param;
    ELSIF EXISTS (SELECT 1 FROM shared.AuditLog_Stems WHERE AuditID = audit_id_param) THEN
        table_name := 'Stems';
        SELECT StemID INTO variant_id FROM shared.AuditLog_Stems WHERE AuditID = audit_id_param;
    ELSE
        RAISE EXCEPTION 'Could not determine table for audit record %', audit_id_param;
    END IF;

    field_name := audit_record.FieldName;
    old_value := audit_record.OldValue;

    -- Create revert audit log
    SELECT shared.create_audit_log(
        table_name,
        variant_id,
        field_name,
        audit_record.NewValue,  -- Current value becomes old value
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
            record_id := NEW.VariantID;
        WHEN 'trees' THEN
            record_id := NEW.VariantID;
        WHEN 'environments' THEN
            record_id := NEW.VariantID;
        WHEN 'stems' THEN
            record_id := NEW.StemID;
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
            IF OLD.CrownWidth_m IS DISTINCT FROM NEW.CrownWidth_m THEN
                PERFORM shared.create_audit_log(
                    'Trees', record_id, 'CrownWidth_m',
                    OLD.CrownWidth_m::TEXT, NEW.CrownWidth_m::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.HealthScore IS DISTINCT FROM NEW.HealthScore THEN
                PERFORM shared.create_audit_log(
                    'Trees', record_id, 'HealthScore',
                    OLD.HealthScore::TEXT, NEW.HealthScore::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.TreeStatusID IS DISTINCT FROM NEW.TreeStatusID THEN
                PERFORM shared.create_audit_log(
                    'Trees', record_id, 'TreeStatusID',
                    OLD.TreeStatusID::TEXT, NEW.TreeStatusID::TEXT,
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
            IF OLD.StemHeight_m IS DISTINCT FROM NEW.StemHeight_m THEN
                PERFORM shared.create_audit_log(
                    'Stems', record_id, 'StemHeight_m',
                    OLD.StemHeight_m::TEXT, NEW.StemHeight_m::TEXT,
                    NULL, 'field_update'
                );
            END IF;

        WHEN 'environments' THEN
            -- Audit environmental parameters
            IF OLD.AvgTemperature_C IS DISTINCT FROM NEW.AvgTemperature_C THEN
                PERFORM shared.create_audit_log(
                    'Environments', record_id, 'AvgTemperature_C',
                    OLD.AvgTemperature_C::TEXT, NEW.AvgTemperature_C::TEXT,
                    NULL, 'field_update'
                );
            END IF;
            IF OLD.StressFactor IS DISTINCT FROM NEW.StressFactor THEN
                PERFORM shared.create_audit_log(
                    'Environments', record_id, 'StressFactor',
                    OLD.StressFactor::TEXT, NEW.StressFactor::TEXT,
                    NULL, 'field_update'
                );
            END IF;

        WHEN 'pointclouds' THEN
            -- Audit processing status changes
            IF OLD.ProcessingStatus IS DISTINCT FROM NEW.ProcessingStatus THEN
                PERFORM shared.create_audit_log(
                    'PointClouds', record_id, 'ProcessingStatus',
                    OLD.ProcessingStatus::TEXT, NEW.ProcessingStatus::TEXT,
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
    al.AuditID,
    COALESCE(
        CASE WHEN alpc.VariantID IS NOT NULL THEN 'PointClouds'
             WHEN alt.VariantID IS NOT NULL THEN 'Trees'
             WHEN ale.VariantID IS NOT NULL THEN 'Environments'
             WHEN als.StemID IS NOT NULL THEN 'Stems'
        END
    ) AS table_name,
    COALESCE(alpc.VariantID, alt.VariantID, ale.VariantID, als.StemID) AS record_id,
    al.FieldName,
    al.OldValue,
    al.NewValue,
    al.ChangeType,
    al.UserID,
    al.Timestamp,
    al.ChangeReason
FROM shared.AuditLog al
LEFT JOIN shared.AuditLog_PointClouds alpc ON al.AuditID = alpc.AuditID
LEFT JOIN shared.AuditLog_Trees alt ON al.AuditID = alt.AuditID
LEFT JOIN shared.AuditLog_Environments ale ON al.AuditID = ale.AuditID
LEFT JOIN shared.AuditLog_Stems als ON al.AuditID = als.AuditID
ORDER BY al.Timestamp DESC;

COMMENT ON VIEW shared.recent_changes IS 'Unified view of recent changes across all audited tables';

-- View: User activity summary
CREATE OR REPLACE VIEW shared.user_activity_summary AS
SELECT
    UserID,
    COUNT(*) AS total_changes,
    COUNT(DISTINCT DATE(Timestamp)) AS active_days,
    MIN(Timestamp) AS first_change,
    MAX(Timestamp) AS last_change,
    COUNT(*) FILTER (WHERE ChangeType = 'field_update') AS field_updates,
    COUNT(*) FILTER (WHERE ChangeType = 'bulk_update') AS bulk_updates,
    COUNT(*) FILTER (WHERE ChangeType = 'revert') AS reverts
FROM shared.AuditLog
GROUP BY UserID;

COMMENT ON VIEW shared.user_activity_summary IS 'Summary of user activity and change patterns';

-- Grant permissions
GRANT EXECUTE ON FUNCTION shared.create_audit_log TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.get_audit_history TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.revert_field_change TO authenticated, service_role;
