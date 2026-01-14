-- =============================================================================
-- 03: POINTCLOUDS SCHEMA
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- LiDAR scan data and processing variants
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS pointclouds;
SET search_path TO pointclouds, shared, public, extensions;

-- =============================================================================
-- POINT CLOUDS TABLE
-- =============================================================================

CREATE TABLE pointclouds.PointClouds (
    VariantID SERIAL PRIMARY KEY,
    ParentVariantID INTEGER REFERENCES pointclouds.PointClouds(VariantID) ON DELETE SET NULL,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    ScenarioID INTEGER REFERENCES shared.Scenarios(ScenarioID) ON DELETE SET NULL,
    VariantTypeID INTEGER NOT NULL REFERENCES shared.VariantTypes(VariantTypeID),
    ProcessID INTEGER REFERENCES shared.Processes(ProcessID) ON DELETE SET NULL,
    VariantName VARCHAR(300) NOT NULL,
    ScanDate TIMESTAMPTZ,
    SensorModel VARCHAR(200),
    ScanBounds extensions.GEOMETRY(Polygon, 4326),
    FilePath TEXT NOT NULL,
    PointCount BIGINT CHECK (PointCount >= 0),
    FileSizeMB NUMERIC(12, 2) CHECK (FileSizeMB >= 0),
    ProcessingStatus VARCHAR(50) CHECK (ProcessingStatus IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    ProcessingProgress NUMERIC(5, 2) CHECK (ProcessingProgress >= 0 AND ProcessingProgress <= 100),
    ErrorMessage TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200)
);

COMMENT ON TABLE pointclouds.PointClouds IS 'LiDAR point cloud variants - original scans and processed results';

-- Create indexes
CREATE INDEX idx_pointclouds_location ON pointclouds.PointClouds(LocationID);
CREATE INDEX idx_pointclouds_scan_date ON pointclouds.PointClouds(ScanDate DESC);
CREATE INDEX idx_pointclouds_scan_bounds ON pointclouds.PointClouds USING GIST (ScanBounds);

-- =============================================================================
-- JUNCTION TABLES
-- =============================================================================

CREATE TABLE shared.ProcessParameters_PointClouds (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES pointclouds.PointClouds(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, VariantID)
);

CREATE TABLE shared.AuditLog_PointClouds (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES pointclouds.PointClouds(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, VariantID)
);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

CREATE OR REPLACE FUNCTION pointclouds.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.UpdatedAt = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_pointclouds_updated_at
    BEFORE UPDATE ON pointclouds.PointClouds
    FOR EACH ROW
    EXECUTE FUNCTION pointclouds.update_updated_at_column();

DO $$
BEGIN
    RAISE NOTICE '✅ Pointclouds schema created';
END
$$;
