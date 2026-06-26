-- XR Future Forests Lab - Point Clouds Schema Migration
-- This migration creates the pointclouds schema for LiDAR scan data and processing variants
-- Point cloud files are stored in S3 buckets with FilePath storing S3 URIs

-- Create pointclouds schema
CREATE SCHEMA IF NOT EXISTS pointclouds;

-- Set search path
SET search_path TO pointclouds, shared, public;

-- =============================================================================
-- SCANNER TYPES REFERENCE TABLE
-- =============================================================================

CREATE TABLE pointclouds.ScannerTypes (
    ScannerTypeID SERIAL PRIMARY KEY,
    ScannerTypeName VARCHAR(100) NOT NULL UNIQUE,
    Manufacturer VARCHAR(200),
    Description TEXT
);

COMMENT ON TABLE pointclouds.ScannerTypes IS 'LiDAR scanner type classifications and manufacturers';
COMMENT ON COLUMN pointclouds.ScannerTypes.ScannerTypeName IS 'Scanner type name (e.g., Terrestrial_TLS, Aerial_ALS, Mobile_MLS, UAV_ULS)';

CREATE INDEX idx_scanner_types_name ON pointclouds.ScannerTypes(ScannerTypeName);

-- =============================================================================
-- SCANNERS TABLE (INDIVIDUAL SCANNER HARDWARE)
-- =============================================================================

CREATE TABLE pointclouds.Scanners (
    ScannerID SERIAL PRIMARY KEY,
    ScannerTypeID INTEGER NOT NULL REFERENCES pointclouds.ScannerTypes(ScannerTypeID),
    SerialNumber VARCHAR(100) UNIQUE,
    AcquisitionDate DATE,
    CalibrationDate DATE,
    Notes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ
);

COMMENT ON TABLE pointclouds.Scanners IS 'Individual LiDAR scanner hardware instances';
COMMENT ON COLUMN pointclouds.Scanners.SerialNumber IS 'Unique hardware serial number';
COMMENT ON COLUMN pointclouds.Scanners.AcquisitionDate IS 'Date scanner was acquired';
COMMENT ON COLUMN pointclouds.Scanners.CalibrationDate IS 'Last calibration date';

CREATE INDEX idx_scanners_type ON pointclouds.Scanners(ScannerTypeID);
CREATE INDEX idx_scanners_serial ON pointclouds.Scanners(SerialNumber);

-- =============================================================================
-- POINT CLOUDS TABLE (UNIFIED VARIANT-BASED APPROACH)
-- =============================================================================

CREATE TABLE pointclouds.PointClouds (
    PointCloudID SERIAL PRIMARY KEY,
    ParentPointCloudID INTEGER REFERENCES pointclouds.PointClouds(PointCloudID) ON DELETE SET NULL,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    ScenarioID INTEGER REFERENCES shared.Scenarios(ScenarioID) ON DELETE SET NULL,
    VariantTypeID INTEGER NOT NULL REFERENCES shared.VariantTypes(VariantTypeID),
    ProcessID INTEGER REFERENCES shared.Processes(ProcessID) ON DELETE SET NULL,
    CampaignID INTEGER REFERENCES shared.Campaigns(CampaignID) ON DELETE SET NULL,
    ScannerID INTEGER REFERENCES pointclouds.Scanners(ScannerID) ON DELETE SET NULL,
    VariantName VARCHAR(300) NOT NULL,
    ScanDate TIMESTAMPTZ,
    SensorModel VARCHAR(200),
    SourceCRS INTEGER,
    PlatformType VARCHAR(50) CHECK (PlatformType IN ('terrestrial', 'aerial', 'mobile', 'UAV')),
    ScanBounds extensions.GEOMETRY(Polygon, 4326),
    FilePath TEXT NOT NULL,
    FlightAltitude_m NUMERIC(8, 2) CHECK (FlightAltitude_m > 0),
    FlightSpeed_ms NUMERIC(6, 2) CHECK (FlightSpeed_ms >= 0),
    ScanAngle_deg NUMERIC(5, 2) CHECK (ScanAngle_deg >= 0 AND ScanAngle_deg <= 360),
    Overlap_percent NUMERIC(5, 2) CHECK (Overlap_percent >= 0 AND Overlap_percent <= 100),
    PointCount BIGINT CHECK (PointCount >= 0),
    PointDensity_per_m2 NUMERIC(10, 2) CHECK (PointDensity_per_m2 >= 0),
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
COMMENT ON COLUMN pointclouds.PointClouds.PointCloudID IS 'Unique identifier for this point cloud record';
COMMENT ON COLUMN pointclouds.PointClouds.ParentPointCloudID IS 'Parent point cloud for processing lineage tracking';
COMMENT ON COLUMN pointclouds.PointClouds.FilePath IS 'S3 URI to point cloud file (e.g., s3://bucket-name/path/file.las)';
COMMENT ON COLUMN pointclouds.PointClouds.ScanBounds IS 'PostGIS polygon defining point cloud coverage area in WGS84';
COMMENT ON COLUMN pointclouds.PointClouds.ProcessingStatus IS 'NULL for original scans, status for processed variants';
COMMENT ON COLUMN pointclouds.PointClouds.ProcessingProgress IS 'Processing completion percentage (0-100)';
COMMENT ON COLUMN pointclouds.PointClouds.CampaignID IS 'Data collection campaign this scan belongs to';
COMMENT ON COLUMN pointclouds.PointClouds.ScannerID IS 'Physical scanner hardware used for this scan';
COMMENT ON COLUMN pointclouds.PointClouds.SourceCRS IS 'EPSG code of original coordinate reference system';
COMMENT ON COLUMN pointclouds.PointClouds.PlatformType IS 'Scanning platform: terrestrial, aerial, mobile, UAV';
COMMENT ON COLUMN pointclouds.PointClouds.FlightAltitude_m IS 'Flight altitude above ground in meters (for aerial/UAV)';
COMMENT ON COLUMN pointclouds.PointClouds.FlightSpeed_ms IS 'Platform speed during scanning in m/s';
COMMENT ON COLUMN pointclouds.PointClouds.ScanAngle_deg IS 'Scanner field of view angle in degrees';
COMMENT ON COLUMN pointclouds.PointClouds.Overlap_percent IS 'Swath overlap percentage (for aerial scans)';
COMMENT ON COLUMN pointclouds.PointClouds.PointDensity_per_m2 IS 'Average point density in points per square meter';

-- Create indexes
CREATE INDEX idx_pointclouds_parent ON pointclouds.PointClouds(ParentPointCloudID);
CREATE INDEX idx_pointclouds_location ON pointclouds.PointClouds(LocationID);
CREATE INDEX idx_pointclouds_scenario ON pointclouds.PointClouds(ScenarioID);
CREATE INDEX idx_pointclouds_variant_type ON pointclouds.PointClouds(VariantTypeID);
CREATE INDEX idx_pointclouds_process ON pointclouds.PointClouds(ProcessID);
CREATE INDEX idx_pointclouds_scan_date ON pointclouds.PointClouds(ScanDate DESC);
CREATE INDEX idx_pointclouds_processing_status ON pointclouds.PointClouds(ProcessingStatus);
CREATE INDEX idx_pointclouds_created_at ON pointclouds.PointClouds(CreatedAt DESC);
CREATE INDEX idx_pointclouds_scan_bounds ON pointclouds.PointClouds USING GIST (ScanBounds);
CREATE INDEX idx_pointclouds_created_by ON pointclouds.PointClouds(CreatedBy);
CREATE INDEX idx_pointclouds_campaign ON pointclouds.PointClouds(CampaignID);
CREATE INDEX idx_pointclouds_scanner ON pointclouds.PointClouds(ScannerID);
CREATE INDEX idx_pointclouds_platform_type ON pointclouds.PointClouds(PlatformType);

-- =============================================================================
-- JUNCTION TABLE: PROCESS PARAMETERS FOR POINT CLOUDS
-- =============================================================================

CREATE TABLE shared.ProcessParameters_PointClouds (
    ProcessParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ProcessParameterID) ON DELETE CASCADE,
    PointCloudID INTEGER NOT NULL REFERENCES pointclouds.PointClouds(PointCloudID) ON DELETE CASCADE,
    PRIMARY KEY (ProcessParameterID, PointCloudID)
);

COMMENT ON TABLE shared.ProcessParameters_PointClouds IS 'Links process parameters to point cloud records';

CREATE INDEX idx_pp_pointclouds_parameter ON shared.ProcessParameters_PointClouds(ProcessParameterID);
CREATE INDEX idx_pp_pointclouds_pointcloud ON shared.ProcessParameters_PointClouds(PointCloudID);

-- =============================================================================
-- JUNCTION TABLE: AUDIT LOG FOR POINT CLOUDS
-- =============================================================================

CREATE TABLE shared.AuditLog_PointClouds (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    PointCloudID INTEGER NOT NULL REFERENCES pointclouds.PointClouds(PointCloudID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, PointCloudID)
);

COMMENT ON TABLE shared.AuditLog_PointClouds IS 'Links audit log entries to point cloud records';

CREATE INDEX idx_audit_pointclouds_audit ON shared.AuditLog_PointClouds(AuditID);
CREATE INDEX idx_audit_pointclouds_pointcloud ON shared.AuditLog_PointClouds(PointCloudID);

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
    -- Base case: original point clouds (no parent)
    SELECT
        PointCloudID,
        ParentPointCloudID,
        VariantName,
        ProcessID,
        ProcessingStatus,
        1 AS depth,
        ARRAY[PointCloudID] AS lineage_path
    FROM pointclouds.PointClouds
    WHERE ParentPointCloudID IS NULL

    UNION ALL

    -- Recursive case: derived point clouds
    SELECT
        pc.PointCloudID,
        pc.ParentPointCloudID,
        pc.VariantName,
        pc.ProcessID,
        pc.ProcessingStatus,
        l.depth + 1,
        l.lineage_path || pc.PointCloudID
    FROM pointclouds.PointClouds pc
    INNER JOIN lineage l ON pc.ParentPointCloudID = l.PointCloudID
)
SELECT * FROM lineage;

COMMENT ON VIEW pointclouds.processing_lineage IS 'Recursive view showing point cloud processing lineage and depth';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA pointclouds TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA pointclouds TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA pointclouds TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pointclouds TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pointclouds TO anon, authenticated, service_role;
