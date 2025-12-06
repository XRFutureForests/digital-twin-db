-- Aquarius Integration Migration
-- Adds support for external sensor IDs and linking sensors to trees

SET search_path TO sensor, trees, shared, public;

-- 1. Add ExternalID and Metadata to Sensors table
ALTER TABLE sensor.Sensors 
ADD COLUMN IF NOT EXISTS ExternalID VARCHAR(200) UNIQUE,
ADD COLUMN IF NOT EXISTS ExternalMetadata JSONB DEFAULT '{}'::jsonb;

COMMENT ON COLUMN sensor.Sensors.ExternalID IS 'Unique identifier from external system (e.g., Aquarius TimeSeriesIdentifier)';
COMMENT ON COLUMN sensor.Sensors.ExternalMetadata IS 'Additional metadata from external system';

-- 2. Add missing Sensor Types
INSERT INTO sensor.SensorTypes (SensorTypeName, Description, TypicalUnit, TypicalRangeMin, TypicalRangeMax)
VALUES 
    ('Stem_Radial_Variation', 'Dendrometer readings for stem radial variation', 'mV', 0, 5000)
ON CONFLICT (SensorTypeName) DO NOTHING;

-- 3. Create Sensor-Tree Link table
CREATE TABLE IF NOT EXISTS sensor.SensorTreeLinks (
    LinkID SERIAL PRIMARY KEY,
    SensorID INTEGER NOT NULL REFERENCES sensor.Sensors(SensorID) ON DELETE CASCADE,
    TreeVariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    Description TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(SensorID, TreeVariantID)
);

COMMENT ON TABLE sensor.SensorTreeLinks IS 'Links sensors to specific tree variants';

-- 4. Create index for external ID lookups
CREATE INDEX IF NOT EXISTS idx_sensors_external_id ON sensor.Sensors(ExternalID);

-- 5. Grant permissions
GRANT ALL ON sensor.SensorTreeLinks TO service_role;
GRANT SELECT ON sensor.SensorTreeLinks TO authenticated, anon;
