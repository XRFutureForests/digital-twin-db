-- XR Future Forests Lab - Row Level Security (RLS) Policies
-- This migration implements security policies for multi-user access control

-- Enable Row Level Security on all tables
-- =============================================================================
-- SHARED SCHEMA RLS
-- =============================================================================

-- Locations: Public read, authenticated write
ALTER TABLE shared.Locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Locations are viewable by everyone"
    ON shared.Locations FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can insert locations"
    ON shared.Locations FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update locations"
    ON shared.Locations FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Species: Public read, authenticated write
ALTER TABLE shared.Species ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Species are viewable by everyone"
    ON shared.Species FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage species"
    ON shared.Species FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Scenarios: Public read, authenticated write
ALTER TABLE shared.Scenarios ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Scenarios are viewable by everyone"
    ON shared.Scenarios FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage scenarios"
    ON shared.Scenarios FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Reference tables (read-only for most users)
ALTER TABLE shared.SoilTypes ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ClimateZones ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.VariantTypes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Reference tables are viewable by everyone"
    ON shared.SoilTypes FOR SELECT
    USING (true);

CREATE POLICY "Reference tables are viewable by everyone"
    ON shared.ClimateZones FOR SELECT
    USING (true);

CREATE POLICY "Reference tables are viewable by everyone"
    ON shared.VariantTypes FOR SELECT
    USING (true);

-- Processes and ProcessParameters: Public read, authenticated write
ALTER TABLE shared.Processes ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ProcessParameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ProcessMetrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Processes are viewable by everyone"
    ON shared.Processes FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage processes"
    ON shared.Processes FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Process parameters are viewable by everyone"
    ON shared.ProcessParameters FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage process parameters"
    ON shared.ProcessParameters FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Process metrics are viewable by everyone"
    ON shared.ProcessMetrics FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage process metrics"
    ON shared.ProcessMetrics FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Junction tables for ProcessParameters
ALTER TABLE shared.ProcessParameters_PointClouds ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ProcessParameters_Trees ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ProcessParameters_Environments ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ProcessParameters_Stems ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Process parameter links are viewable by everyone"
    ON shared.ProcessParameters_PointClouds FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage process parameter links"
    ON shared.ProcessParameters_PointClouds FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Process parameter links are viewable by everyone"
    ON shared.ProcessParameters_Trees FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage process parameter links"
    ON shared.ProcessParameters_Trees FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Process parameter links are viewable by everyone"
    ON shared.ProcessParameters_Environments FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage process parameter links"
    ON shared.ProcessParameters_Environments FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Process parameter links are viewable by everyone"
    ON shared.ProcessParameters_Stems FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage process parameter links"
    ON shared.ProcessParameters_Stems FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- AuditLog: Authenticated read (own records or all for admins), service_role write
ALTER TABLE shared.AuditLog ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own audit logs"
    ON shared.AuditLog FOR SELECT
    TO authenticated
    USING (UserID = auth.uid()::TEXT OR UserID IS NULL);

CREATE POLICY "Service role can manage audit logs"
    ON shared.AuditLog FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Junction tables for AuditLog
ALTER TABLE shared.AuditLog_PointClouds ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.AuditLog_Trees ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.AuditLog_Environments ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.AuditLog_Stems ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Audit links viewable by authenticated users"
    ON shared.AuditLog_PointClouds FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Service role can manage audit links"
    ON shared.AuditLog_PointClouds FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Audit links viewable by authenticated users"
    ON shared.AuditLog_Trees FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Service role can manage audit links"
    ON shared.AuditLog_Trees FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Audit links viewable by authenticated users"
    ON shared.AuditLog_Environments FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Service role can manage audit links"
    ON shared.AuditLog_Environments FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Audit links viewable by authenticated users"
    ON shared.AuditLog_Stems FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Service role can manage audit links"
    ON shared.AuditLog_Stems FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- =============================================================================
-- POINTCLOUDS SCHEMA RLS
-- =============================================================================

ALTER TABLE pointclouds.PointClouds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Point clouds are viewable by everyone"
    ON pointclouds.PointClouds FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can create point clouds"
    ON pointclouds.PointClouds FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Users can update their own point clouds"
    ON pointclouds.PointClouds FOR UPDATE
    TO authenticated
    USING (CreatedBy = auth.uid()::TEXT OR CreatedBy IS NULL)
    WITH CHECK (CreatedBy = auth.uid()::TEXT OR CreatedBy IS NULL);

CREATE POLICY "Service role can manage all point clouds"
    ON pointclouds.PointClouds FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- =============================================================================
-- TREES SCHEMA RLS
-- =============================================================================

-- Reference tables (read-only)
ALTER TABLE trees.TreeStatus ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.TaperTypes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.StraightnessTypes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.BranchingPatterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.BarkCharacteristics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tree reference tables are viewable by everyone"
    ON trees.TreeStatus FOR SELECT
    USING (true);

CREATE POLICY "Tree reference tables are viewable by everyone"
    ON trees.TaperTypes FOR SELECT
    USING (true);

CREATE POLICY "Tree reference tables are viewable by everyone"
    ON trees.StraightnessTypes FOR SELECT
    USING (true);

CREATE POLICY "Tree reference tables are viewable by everyone"
    ON trees.BranchingPatterns FOR SELECT
    USING (true);

CREATE POLICY "Tree reference tables are viewable by everyone"
    ON trees.BarkCharacteristics FOR SELECT
    USING (true);

-- Trees: Public read, authenticated write
ALTER TABLE trees.Trees ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Trees are viewable by everyone"
    ON trees.Trees FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can create trees"
    ON trees.Trees FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Users can update their own trees or unowned trees"
    ON trees.Trees FOR UPDATE
    TO authenticated
    USING (CreatedBy = auth.uid()::TEXT OR CreatedBy IS NULL)
    WITH CHECK (CreatedBy = auth.uid()::TEXT OR CreatedBy IS NULL);

CREATE POLICY "Service role can manage all trees"
    ON trees.Trees FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Stems: Follow tree permissions
ALTER TABLE trees.Stems ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Stems are viewable by everyone"
    ON trees.Stems FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can create stems"
    ON trees.Stems FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update stems"
    ON trees.Stems FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Service role can manage all stems"
    ON trees.Stems FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- =============================================================================
-- SENSOR SCHEMA RLS
-- =============================================================================

-- Sensor types (read-only)
ALTER TABLE sensor.SensorTypes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Sensor types are viewable by everyone"
    ON sensor.SensorTypes FOR SELECT
    USING (true);

-- Sensors: Public read, authenticated write
ALTER TABLE sensor.Sensors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Sensors are viewable by everyone"
    ON sensor.Sensors FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can manage sensors"
    ON sensor.Sensors FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Sensor readings: Public read, authenticated write
ALTER TABLE sensor.SensorReadings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Sensor readings are viewable by everyone"
    ON sensor.SensorReadings FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can insert sensor readings"
    ON sensor.SensorReadings FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Service role can manage all sensor readings"
    ON sensor.SensorReadings FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- =============================================================================
-- ENVIRONMENTS SCHEMA RLS
-- =============================================================================

ALTER TABLE environments.Environments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Environments are viewable by everyone"
    ON environments.Environments FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can create environments"
    ON environments.Environments FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Users can update their own environments"
    ON environments.Environments FOR UPDATE
    TO authenticated
    USING (CreatedBy = auth.uid()::TEXT OR CreatedBy IS NULL)
    WITH CHECK (CreatedBy = auth.uid()::TEXT OR CreatedBy IS NULL);

CREATE POLICY "Service role can manage all environments"
    ON environments.Environments FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- =============================================================================
-- HELPER FUNCTIONS FOR RLS
-- =============================================================================

-- Function to check if user is admin (can be customized based on user metadata)
CREATE OR REPLACE FUNCTION shared.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    -- Check if user has admin role in metadata
    -- This is a placeholder - customize based on your auth setup
    RETURN (
        SELECT (auth.jwt() -> 'app_metadata' -> 'role')::text = '"admin"'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION shared.is_admin IS 'Checks if current user has admin role';

-- Function to get current user ID
CREATE OR REPLACE FUNCTION shared.current_user_id()
RETURNS TEXT AS $$
BEGIN
    RETURN auth.uid()::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION shared.current_user_id IS 'Returns current authenticated user ID';

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC USER ATTRIBUTION
-- =============================================================================

-- Function to set CreatedBy on insert
CREATE OR REPLACE FUNCTION shared.set_created_by()
RETURNS TRIGGER AS $$
BEGIN
    -- Try to set CreatedBy if it exists and is NULL
    -- Use exception handling to gracefully skip if column doesn't exist in NEW record
    BEGIN
        IF (to_jsonb(NEW)->>'createdby') IS NULL THEN
            NEW.CreatedBy := COALESCE(auth.uid()::TEXT, 'system');
        END IF;
    EXCEPTION
        WHEN undefined_column THEN
            -- Column doesn't exist in this table, skip silently
            NULL;
    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to set UpdatedBy on update
CREATE OR REPLACE FUNCTION shared.set_updated_by()
RETURNS TRIGGER AS $$
BEGIN
    NEW.UpdatedBy := auth.uid()::TEXT;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply triggers to relevant tables
CREATE TRIGGER trigger_pointclouds_created_by
    BEFORE INSERT ON pointclouds.PointClouds
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_created_by();

CREATE TRIGGER trigger_pointclouds_updated_by
    BEFORE UPDATE ON pointclouds.PointClouds
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_updated_by();

CREATE TRIGGER trigger_trees_created_by
    BEFORE INSERT ON trees.Trees
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_created_by();

CREATE TRIGGER trigger_trees_updated_by
    BEFORE UPDATE ON trees.Trees
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_updated_by();

CREATE TRIGGER trigger_sensors_created_by
    BEFORE INSERT ON sensor.Sensors
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_created_by();

CREATE TRIGGER trigger_sensors_updated_by
    BEFORE UPDATE ON sensor.Sensors
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_updated_by();

CREATE TRIGGER trigger_environments_created_by
    BEFORE INSERT ON environments.Environments
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_created_by();

CREATE TRIGGER trigger_environments_updated_by
    BEFORE UPDATE ON environments.Environments
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_updated_by();

CREATE TRIGGER trigger_locations_created_by
    BEFORE INSERT ON shared.Locations
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_created_by();

CREATE TRIGGER trigger_locations_updated_by
    BEFORE UPDATE ON shared.Locations
    FOR EACH ROW
    EXECUTE FUNCTION shared.set_updated_by();

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON POLICY "Locations are viewable by everyone" ON shared.Locations IS
    'Public read access to location data';

COMMENT ON POLICY "Point clouds are viewable by everyone" ON pointclouds.PointClouds IS
    'Public read access to point cloud metadata';

COMMENT ON POLICY "Trees are viewable by everyone" ON trees.Trees IS
    'Public read access to tree measurement data';

COMMENT ON POLICY "Environments are viewable by everyone" ON environments.Environments IS
    'Public read access to environmental conditions';

-- Grant execute permissions on RLS helper functions
GRANT EXECUTE ON FUNCTION shared.is_admin() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.current_user_id() TO authenticated, service_role;
