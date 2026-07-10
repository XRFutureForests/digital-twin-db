-- XR Future Forests Lab - Imagery Schema Migration
-- This migration creates the imagery schema for aerial and ground-based image data

-- Create imagery schema
CREATE SCHEMA IF NOT EXISTS imagery;

-- Set search path
SET search_path TO imagery, shared, public;

-- =============================================================================
-- IMAGES TABLE
-- =============================================================================

CREATE TABLE imagery.Images (
    image_id SERIAL PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    campaign_id INTEGER REFERENCES shared.Campaigns(campaign_id) ON DELETE SET NULL,
    capture_date TIMESTAMPTZ,
    file_path TEXT NOT NULL,
    file_format VARCHAR(20) CHECK (file_format IN ('jpg', 'png', 'tiff', 'raw', 'geotiff')),
    Resolution_px VARCHAR(50),
    camera_model VARCHAR(200),
    Position extensions.GEOMETRY(Point, 4326),
    Altitude_m NUMERIC(8, 2),
    Heading_deg NUMERIC(5, 2) CHECK (Heading_deg >= 0 AND Heading_deg < 360),
    Pitch_deg NUMERIC(5, 2) CHECK (Pitch_deg >= -90 AND Pitch_deg <= 90),
    Roll_deg NUMERIC(5, 2) CHECK (Roll_deg >= -180 AND Roll_deg <= 180),
    ground_sample_distance_cm NUMERIC(8, 4) CHECK (ground_sample_distance_cm > 0),
    Description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200)
);

COMMENT ON TABLE imagery.Images IS 'Aerial and ground-based imagery with spatial metadata and camera parameters';
COMMENT ON COLUMN imagery.Images.file_path IS 'Path or URI to image file';
COMMENT ON COLUMN imagery.Images.file_format IS 'Image file format (jpg, png, tiff, raw, geotiff)';
COMMENT ON COLUMN imagery.Images.Resolution_px IS 'Image resolution in pixels (e.g., 4000x3000)';
COMMENT ON COLUMN imagery.Images.Position IS 'Camera position in WGS84 (EPSG:4326)';
COMMENT ON COLUMN imagery.Images.Altitude_m IS 'Camera altitude above ground in meters';
COMMENT ON COLUMN imagery.Images.Heading_deg IS 'Camera heading in degrees (0=North, clockwise)';
COMMENT ON COLUMN imagery.Images.Pitch_deg IS 'Camera pitch angle (-90 to 90 degrees)';
COMMENT ON COLUMN imagery.Images.Roll_deg IS 'Camera roll angle (-180 to 180 degrees)';
COMMENT ON COLUMN imagery.Images.ground_sample_distance_cm IS 'Ground sample distance in centimeters per pixel';

-- Create indexes
CREATE INDEX idx_images_location ON imagery.Images(location_id);
CREATE INDEX idx_images_plot ON imagery.Images(plot_id);
CREATE INDEX idx_images_campaign ON imagery.Images(campaign_id);
CREATE INDEX idx_images_capture_date ON imagery.Images(capture_date DESC);
CREATE INDEX idx_images_position ON imagery.Images USING GIST (Position);
CREATE INDEX idx_images_format ON imagery.Images(file_format);
CREATE INDEX idx_images_created_at ON imagery.Images(created_at DESC);
CREATE INDEX idx_images_created_by ON imagery.Images(created_by);

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
-- =============================================================================

CREATE OR REPLACE FUNCTION imagery.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_images_updated_at
    BEFORE UPDATE ON imagery.Images
    FOR EACH ROW
    EXECUTE FUNCTION imagery.update_updated_at_column();

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA imagery TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA imagery TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA imagery TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA imagery TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA imagery TO anon, authenticated, service_role;
