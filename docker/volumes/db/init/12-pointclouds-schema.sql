-- XR Future Forests Lab - Point Clouds Schema Migration
-- This migration creates the pointclouds schema for LiDAR scan data and processing variants
-- Point cloud files are stored in S3 buckets with file_path storing S3 URIs

-- Create pointclouds schema
CREATE SCHEMA IF NOT EXISTS pointclouds;

-- Set search path
SET search_path TO pointclouds, shared, public;

-- =============================================================================
-- SCANNER TYPES REFERENCE TABLE
-- =============================================================================

CREATE TABLE pointclouds.ScannerTypes (
    scanner_type_id SERIAL PRIMARY KEY,
    scanner_type_name VARCHAR(100) NOT NULL UNIQUE,
    Manufacturer VARCHAR(200),
    Description TEXT
);

COMMENT ON TABLE pointclouds.ScannerTypes IS 'LiDAR scanner type classifications and manufacturers';
COMMENT ON COLUMN pointclouds.ScannerTypes.scanner_type_name IS 'Scanner type name (e.g., Terrestrial_TLS, Aerial_ALS, Mobile_MLS, UAV_ULS)';

CREATE INDEX idx_scanner_types_name ON pointclouds.ScannerTypes(scanner_type_name);

-- =============================================================================
-- SCANNERS TABLE (INDIVIDUAL SCANNER HARDWARE)
-- =============================================================================

CREATE TABLE pointclouds.Scanners (
    scanner_id SERIAL PRIMARY KEY,
    scanner_type_id INTEGER NOT NULL REFERENCES pointclouds.ScannerTypes(scanner_type_id),
    serial_number VARCHAR(100) UNIQUE,
    acquisition_date DATE,
    calibration_date DATE,
    Notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

COMMENT ON TABLE pointclouds.Scanners IS 'Individual LiDAR scanner hardware instances';
COMMENT ON COLUMN pointclouds.Scanners.serial_number IS 'Unique hardware serial number';
COMMENT ON COLUMN pointclouds.Scanners.acquisition_date IS 'Date scanner was acquired';
COMMENT ON COLUMN pointclouds.Scanners.calibration_date IS 'Last calibration date';

CREATE INDEX idx_scanners_type ON pointclouds.Scanners(scanner_type_id);
CREATE INDEX idx_scanners_serial ON pointclouds.Scanners(serial_number);

-- =============================================================================
-- POINT CLOUDS TABLE (UNIFIED VARIANT-BASED APPROACH)
-- =============================================================================

CREATE TABLE pointclouds.PointClouds (
    point_cloud_id SERIAL PRIMARY KEY,
    parent_point_cloud_id INTEGER REFERENCES pointclouds.PointClouds(point_cloud_id) ON DELETE SET NULL,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    scenario_id INTEGER REFERENCES shared.Scenarios(scenario_id) ON DELETE SET NULL,
    variant_type_id INTEGER NOT NULL REFERENCES shared.VariantTypes(variant_type_id),
    process_id INTEGER REFERENCES shared.Processes(process_id) ON DELETE SET NULL,
    campaign_id INTEGER REFERENCES shared.Campaigns(campaign_id) ON DELETE SET NULL,
    scanner_id INTEGER REFERENCES pointclouds.Scanners(scanner_id) ON DELETE SET NULL,
    variant_name VARCHAR(300) NOT NULL,
    scan_date TIMESTAMPTZ,
    sensor_model VARCHAR(200),
    source_crs INTEGER,
    platform_type VARCHAR(50) CHECK (platform_type IN ('terrestrial', 'aerial', 'mobile', 'UAV')),
    scan_bounds extensions.GEOMETRY(Polygon, 4326),
    file_path TEXT NOT NULL,
    flight_altitude_m NUMERIC(8, 2) CHECK (flight_altitude_m > 0),
    flight_speed_ms NUMERIC(6, 2) CHECK (flight_speed_ms >= 0),
    scan_angle_deg NUMERIC(5, 2) CHECK (scan_angle_deg >= 0 AND scan_angle_deg <= 360),
    Overlap_percent NUMERIC(5, 2) CHECK (Overlap_percent >= 0 AND Overlap_percent <= 100),
    point_count BIGINT CHECK (point_count >= 0),
    point_density_per_m2 NUMERIC(10, 2) CHECK (point_density_per_m2 >= 0),
    file_size_mb NUMERIC(12, 2) CHECK (file_size_mb >= 0),
    processing_status VARCHAR(50) CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    processing_progress NUMERIC(5, 2) CHECK (processing_progress >= 0 AND processing_progress <= 100),
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    -- Note: Cannot use subquery in CHECK constraint, validation moved to application/trigger level
    CONSTRAINT chk_s3_filepath CHECK (file_path ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$')
);

COMMENT ON TABLE pointclouds.PointClouds IS 'LiDAR point cloud variants - original scans and processed results';
COMMENT ON COLUMN pointclouds.PointClouds.point_cloud_id IS 'Unique identifier for this point cloud record';
COMMENT ON COLUMN pointclouds.PointClouds.parent_point_cloud_id IS 'Parent point cloud for processing lineage tracking';
COMMENT ON COLUMN pointclouds.PointClouds.file_path IS 'S3 URI to point cloud file (e.g., s3://bucket-name/path/file.las)';
COMMENT ON COLUMN pointclouds.PointClouds.scan_bounds IS 'PostGIS polygon defining point cloud coverage area in WGS84';
COMMENT ON COLUMN pointclouds.PointClouds.processing_status IS 'NULL for original scans, status for processed variants';
COMMENT ON COLUMN pointclouds.PointClouds.processing_progress IS 'Processing completion percentage (0-100)';
COMMENT ON COLUMN pointclouds.PointClouds.campaign_id IS 'Data collection campaign this scan belongs to';
COMMENT ON COLUMN pointclouds.PointClouds.scanner_id IS 'Physical scanner hardware used for this scan';
COMMENT ON COLUMN pointclouds.PointClouds.source_crs IS 'EPSG code of original coordinate reference system';
COMMENT ON COLUMN pointclouds.PointClouds.platform_type IS 'Scanning platform: terrestrial, aerial, mobile, UAV';
COMMENT ON COLUMN pointclouds.PointClouds.flight_altitude_m IS 'Flight altitude above ground in meters (for aerial/UAV)';
COMMENT ON COLUMN pointclouds.PointClouds.flight_speed_ms IS 'Platform speed during scanning in m/s';
COMMENT ON COLUMN pointclouds.PointClouds.scan_angle_deg IS 'Scanner field of view angle in degrees';
COMMENT ON COLUMN pointclouds.PointClouds.Overlap_percent IS 'Swath overlap percentage (for aerial scans)';
COMMENT ON COLUMN pointclouds.PointClouds.point_density_per_m2 IS 'Average point density in points per square meter';

-- Create indexes
CREATE INDEX idx_pointclouds_parent ON pointclouds.PointClouds(parent_point_cloud_id);
CREATE INDEX idx_pointclouds_location ON pointclouds.PointClouds(location_id);
CREATE INDEX idx_pointclouds_scenario ON pointclouds.PointClouds(scenario_id);
CREATE INDEX idx_pointclouds_variant_type ON pointclouds.PointClouds(variant_type_id);
CREATE INDEX idx_pointclouds_process ON pointclouds.PointClouds(process_id);
CREATE INDEX idx_pointclouds_scan_date ON pointclouds.PointClouds(scan_date DESC);
CREATE INDEX idx_pointclouds_processing_status ON pointclouds.PointClouds(processing_status);
CREATE INDEX idx_pointclouds_created_at ON pointclouds.PointClouds(created_at DESC);
CREATE INDEX idx_pointclouds_scan_bounds ON pointclouds.PointClouds USING GIST (scan_bounds);
CREATE INDEX idx_pointclouds_created_by ON pointclouds.PointClouds(created_by);
CREATE INDEX idx_pointclouds_campaign ON pointclouds.PointClouds(campaign_id);
CREATE INDEX idx_pointclouds_scanner ON pointclouds.PointClouds(scanner_id);
CREATE INDEX idx_pointclouds_platform_type ON pointclouds.PointClouds(platform_type);

-- =============================================================================
-- JUNCTION TABLE: PROCESS PARAMETERS FOR POINT CLOUDS
-- =============================================================================

CREATE TABLE shared.ProcessParameters_PointClouds (
    process_parameter_id INTEGER NOT NULL REFERENCES shared.ProcessParameters(process_parameter_id) ON DELETE CASCADE,
    point_cloud_id INTEGER NOT NULL REFERENCES pointclouds.PointClouds(point_cloud_id) ON DELETE CASCADE,
    PRIMARY KEY (process_parameter_id, point_cloud_id)
);

COMMENT ON TABLE shared.ProcessParameters_PointClouds IS 'Links process parameters to point cloud records';

CREATE INDEX idx_pp_pointclouds_parameter ON shared.ProcessParameters_PointClouds(process_parameter_id);
CREATE INDEX idx_pp_pointclouds_pointcloud ON shared.ProcessParameters_PointClouds(point_cloud_id);

-- =============================================================================
-- JUNCTION TABLE: AUDIT LOG FOR POINT CLOUDS
-- =============================================================================

CREATE TABLE shared.AuditLog_PointClouds (
    audit_id BIGINT NOT NULL REFERENCES shared.AuditLog(audit_id) ON DELETE CASCADE,
    point_cloud_id INTEGER NOT NULL REFERENCES pointclouds.PointClouds(point_cloud_id) ON DELETE CASCADE,
    PRIMARY KEY (audit_id, point_cloud_id)
);

COMMENT ON TABLE shared.AuditLog_PointClouds IS 'Links audit log entries to point cloud records';

CREATE INDEX idx_audit_pointclouds_audit ON shared.AuditLog_PointClouds(audit_id);
CREATE INDEX idx_audit_pointclouds_pointcloud ON shared.AuditLog_PointClouds(point_cloud_id);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to extract S3 bucket name from file_path
CREATE OR REPLACE FUNCTION pointclouds.get_s3_bucket(file_path TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN substring(file_path FROM 's3://([^/]+)/');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION pointclouds.get_s3_bucket IS 'Extracts S3 bucket name from file_path';

-- Function to extract S3 key (path) from file_path
CREATE OR REPLACE FUNCTION pointclouds.get_s3_key(file_path TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN substring(file_path FROM 's3://[^/]+/(.+)');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION pointclouds.get_s3_key IS 'Extracts S3 object key (path) from file_path';

-- Function to validate S3 URI format
CREATE OR REPLACE FUNCTION pointclouds.validate_s3_uri(file_path TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN file_path ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION pointclouds.validate_s3_uri IS 'Validates S3 URI format for point cloud files';

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
-- =============================================================================

CREATE OR REPLACE FUNCTION pointclouds.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
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
        point_cloud_id,
        parent_point_cloud_id,
        variant_name,
        process_id,
        processing_status,
        1 AS depth,
        ARRAY[point_cloud_id] AS lineage_path
    FROM pointclouds.PointClouds
    WHERE parent_point_cloud_id IS NULL

    UNION ALL

    -- Recursive case: derived point clouds
    SELECT
        pc.point_cloud_id,
        pc.parent_point_cloud_id,
        pc.variant_name,
        pc.process_id,
        pc.processing_status,
        l.depth + 1,
        l.lineage_path || pc.point_cloud_id
    FROM pointclouds.PointClouds pc
    INNER JOIN lineage l ON pc.parent_point_cloud_id = l.point_cloud_id
)
SELECT * FROM lineage;

COMMENT ON VIEW pointclouds.processing_lineage IS 'Recursive view showing point cloud processing lineage and depth';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA pointclouds TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA pointclouds TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA pointclouds TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pointclouds TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pointclouds TO anon, authenticated, service_role;
