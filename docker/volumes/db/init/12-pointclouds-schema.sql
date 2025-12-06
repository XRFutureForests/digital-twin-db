-- XR Future Forests Lab - Point Clouds Schema Migration
-- This migration creates the pointclouds schema for LiDAR scan data and processing variants
-- Point cloud files are stored in S3 buckets with FilePath storing S3 URIs

-- Create pointclouds schema
CREATE SCHEMA IF NOT EXISTS pointclouds;

-- Set search path
SET search_path TO pointclouds, shared, public;

-- =============================================================================
-- POINT CLOUDS TABLE (UNIFIED VARIANT-BASED APPROACH)
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
    UpdatedBy VARCHAR(200),
    -- Note: Cannot use subquery in CHECK constraint, validation moved to application/trigger level
    CONSTRAINT chk_s3_filepath CHECK (FilePath ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$')
);

COMMENT ON TABLE pointclouds.PointClouds IS 'LiDAR point cloud variants - original scans and processed results';
COMMENT ON COLUMN pointclouds.PointClouds.VariantID IS 'Unique identifier for this point cloud variant';
COMMENT ON COLUMN pointclouds.PointClouds.ParentVariantID IS 'Parent variant for processing lineage tracking';
COMMENT ON COLUMN pointclouds.PointClouds.FilePath IS 'S3 URI to point cloud file (e.g., s3://bucket-name/path/file.las)';
COMMENT ON COLUMN pointclouds.PointClouds.ScanBounds IS 'PostGIS polygon defining point cloud coverage area in WGS84';
COMMENT ON COLUMN pointclouds.PointClouds.ProcessingStatus IS 'NULL for original scans, status for processed variants';
COMMENT ON COLUMN pointclouds.PointClouds.ProcessingProgress IS 'Processing completion percentage (0-100)';

-- Create indexes
CREATE INDEX idx_pointclouds_parent_variant ON pointclouds.PointClouds(ParentVariantID);
CREATE INDEX idx_pointclouds_location ON pointclouds.PointClouds(LocationID);
CREATE INDEX idx_pointclouds_scenario ON pointclouds.PointClouds(ScenarioID);
CREATE INDEX idx_pointclouds_variant_type ON pointclouds.PointClouds(VariantTypeID);
CREATE INDEX idx_pointclouds_process ON pointclouds.PointClouds(ProcessID);
CREATE INDEX idx_pointclouds_scan_date ON pointclouds.PointClouds(ScanDate DESC);
CREATE INDEX idx_pointclouds_processing_status ON pointclouds.PointClouds(ProcessingStatus);
CREATE INDEX idx_pointclouds_created_at ON pointclouds.PointClouds(CreatedAt DESC);
CREATE INDEX idx_pointclouds_scan_bounds ON pointclouds.PointClouds USING GIST (ScanBounds);
CREATE INDEX idx_pointclouds_created_by ON pointclouds.PointClouds(CreatedBy);

-- =============================================================================
-- JUNCTION TABLE: PROCESS PARAMETERS FOR POINT CLOUDS
-- =============================================================================

CREATE TABLE shared.ProcessParameters_PointClouds (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES pointclouds.PointClouds(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, VariantID)
);

COMMENT ON TABLE shared.ProcessParameters_PointClouds IS 'Links process parameters to point cloud variants';

CREATE INDEX idx_pp_pointclouds_parameter ON shared.ProcessParameters_PointClouds(ParameterID);
CREATE INDEX idx_pp_pointclouds_variant ON shared.ProcessParameters_PointClouds(VariantID);

-- =============================================================================
-- JUNCTION TABLE: AUDIT LOG FOR POINT CLOUDS
-- =============================================================================

CREATE TABLE shared.AuditLog_PointClouds (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES pointclouds.PointClouds(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, VariantID)
);

COMMENT ON TABLE shared.AuditLog_PointClouds IS 'Links audit log entries to point cloud variants';

CREATE INDEX idx_audit_pointclouds_audit ON shared.AuditLog_PointClouds(AuditID);
CREATE INDEX idx_audit_pointclouds_variant ON shared.AuditLog_PointClouds(VariantID);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to extract S3 bucket name from FilePath
CREATE OR REPLACE FUNCTION pointclouds.get_s3_bucket(filepath TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN substring(filepath FROM 's3://([^/]+)/');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION pointclouds.get_s3_bucket IS 'Extracts S3 bucket name from FilePath';

-- Function to extract S3 key (path) from FilePath
CREATE OR REPLACE FUNCTION pointclouds.get_s3_key(filepath TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN substring(filepath FROM 's3://[^/]+/(.+)');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION pointclouds.get_s3_key IS 'Extracts S3 object key (path) from FilePath';

-- Function to validate S3 URI format
CREATE OR REPLACE FUNCTION pointclouds.validate_s3_uri(filepath TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN filepath ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION pointclouds.validate_s3_uri IS 'Validates S3 URI format for point cloud files';

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
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

-- =============================================================================
-- VIEW: POINT CLOUD PROCESSING LINEAGE
-- =============================================================================

CREATE OR REPLACE VIEW pointclouds.processing_lineage AS
WITH RECURSIVE lineage AS (
    -- Base case: original point clouds
    SELECT
        VariantID,
        ParentVariantID,
        VariantName,
        ProcessID,
        ProcessingStatus,
        1 AS depth,
        ARRAY[VariantID] AS lineage_path
    FROM pointclouds.PointClouds
    WHERE ParentVariantID IS NULL

    UNION ALL

    -- Recursive case: processed variants
    SELECT
        pc.VariantID,
        pc.ParentVariantID,
        pc.VariantName,
        pc.ProcessID,
        pc.ProcessingStatus,
        l.depth + 1,
        l.lineage_path || pc.VariantID
    FROM pointclouds.PointClouds pc
    INNER JOIN lineage l ON pc.ParentVariantID = l.VariantID
)
SELECT * FROM lineage;

COMMENT ON VIEW pointclouds.processing_lineage IS 'Recursive view showing point cloud processing lineage and depth';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA pointclouds TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA pointclouds TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA pointclouds TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pointclouds TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pointclouds TO anon, authenticated, service_role;
