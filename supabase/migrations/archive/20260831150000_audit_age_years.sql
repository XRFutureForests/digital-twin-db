-- =============================================================================
-- Audit trail: add age_years
-- =============================================================================
-- shared.audit_update_trigger() records column-level changes into
-- shared.AuditLog, which is the twin's provenance mechanism for values that are
-- computed rather than measured -- it already captured the pylometree height
-- fill (1,029 rows, field_name = 'Height_m').
--
-- Two gaps blocked using it for a wider allometric fill:
--
--   1. The tracked column list was fixed and did not include
--      crown_base_height_m or volume_m3 on trees.Trees, nor stem_volume_m3 on
--      trees.Stems. Filling those would have left no trace at all.
--   2. change_reason was hardcoded NULL, so an audit row could say *what*
--      changed but never *why* or by which process.
--
-- This replaces the function with the same logic plus those columns, and reads
-- change_reason from the `app.change_reason` session setting. Any writer can now
-- annotate its updates:
--
--   SET LOCAL app.change_reason = 'SILVA allometry fill (shared.Processes id 8)';
--
-- The setting is read with the missing_ok flag, so existing writers that do not
-- set it keep working and simply record NULL as before.
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.audit_update_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    audit_id BIGINT;
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

COMMENT ON FUNCTION shared.audit_update_trigger() IS
    'Records column-level changes into shared.AuditLog. Set app.change_reason '
    '(SET LOCAL) before an UPDATE to record why a value changed; leave it unset '
    'for ordinary edits.';
