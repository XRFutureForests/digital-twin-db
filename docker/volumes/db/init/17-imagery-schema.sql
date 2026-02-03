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
    ImageID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotID INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL,
    CampaignID INTEGER REFERENCES shared.Campaigns(CampaignID) ON DELETE SET NULL,
    CaptureDate TIMESTAMPTZ,
    FilePath TEXT NOT NULL,
    FileFormat VARCHAR(20) CHECK (FileFormat IN ('jpg', 'png', 'tiff', 'raw', 'geotiff')),
    Resolution_px VARCHAR(50),
    CameraModel VARCHAR(200),
    Position extensions.GEOMETRY(Point, 4326),
    Altitude_m NUMERIC(8, 2),
    Heading_deg NUMERIC(5, 2) CHECK (Heading_deg >= 0 AND Heading_deg < 360),
    Pitch_deg NUMERIC(5, 2) CHECK (Pitch_deg >= -90 AND Pitch_deg <= 90),
    Roll_deg NUMERIC(5, 2) CHECK (Roll_deg >= -180 AND Roll_deg <= 180),
    GroundSampleDistance_cm NUMERIC(8, 4) CHECK (GroundSampleDistance_cm > 0),
    Description TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200)
);

COMMENT ON TABLE imagery.Images IS 'Aerial and ground-based imagery with spatial metadata and camera parameters';
COMMENT ON COLUMN imagery.Images.FilePath IS 'Path or URI to image file';
COMMENT ON COLUMN imagery.Images.FileFormat IS 'Image file format (jpg, png, tiff, raw, geotiff)';
COMMENT ON COLUMN imagery.Images.Resolution_px IS 'Image resolution in pixels (e.g., 4000x3000)';
COMMENT ON COLUMN imagery.Images.Position IS 'Camera position in WGS84 (EPSG:4326)';
COMMENT ON COLUMN imagery.Images.Altitude_m IS 'Camera altitude above ground in meters';
COMMENT ON COLUMN imagery.Images.Heading_deg IS 'Camera heading in degrees (0=North, clockwise)';
COMMENT ON COLUMN imagery.Images.Pitch_deg IS 'Camera pitch angle (-90 to 90 degrees)';
COMMENT ON COLUMN imagery.Images.Roll_deg IS 'Camera roll angle (-180 to 180 degrees)';
COMMENT ON COLUMN imagery.Images.GroundSampleDistance_cm IS 'Ground sample distance in centimeters per pixel';

-- Create indexes
CREATE INDEX idx_images_location ON imagery.Images(LocationID);
CREATE INDEX idx_images_plot ON imagery.Images(PlotID);
CREATE INDEX idx_images_campaign ON imagery.Images(CampaignID);
CREATE INDEX idx_images_capture_date ON imagery.Images(CaptureDate DESC);
CREATE INDEX idx_images_position ON imagery.Images USING GIST (Position);
CREATE INDEX idx_images_format ON imagery.Images(FileFormat);
CREATE INDEX idx_images_created_at ON imagery.Images(CreatedAt DESC);
CREATE INDEX idx_images_created_by ON imagery.Images(CreatedBy);

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
-- =============================================================================

CREATE OR REPLACE FUNCTION imagery.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.UpdatedAt = NOW();
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
