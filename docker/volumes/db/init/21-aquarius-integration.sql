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

-- 6. Create bulk upsert function for sensors (views don't support ON CONFLICT)
CREATE OR REPLACE FUNCTION public.bulk_upsert_sensors(
    p_sensors JSONB
) RETURNS TABLE(externalid VARCHAR, sensorid INT) AS $$
DECLARE
    sensor_rec JSONB;
BEGIN
    FOR sensor_rec IN SELECT * FROM jsonb_array_elements(p_sensors)
    LOOP
        INSERT INTO sensor.sensors (
            locationid, sensortypeid, sensormodel, serialnumber, 
            position, samplinginterval_seconds, unit, externalid,
            externalmetadata, isactive, createdby
        )
        VALUES (
            (sensor_rec->>'locationid')::INT,
            (sensor_rec->>'sensortypeid')::INT,
            sensor_rec->>'sensormodel',
            sensor_rec->>'serialnumber',
            ST_GeomFromText(sensor_rec->>'position', 4326),
            (sensor_rec->>'samplinginterval_seconds')::INT,
            sensor_rec->>'unit',
            sensor_rec->>'externalid',
            (sensor_rec->'externalmetadata')::JSONB,
            (sensor_rec->>'isactive')::BOOLEAN,
            sensor_rec->>'createdby'
        )
        ON CONFLICT (externalid) DO UPDATE SET
            locationid = EXCLUDED.locationid,
            sensortypeid = EXCLUDED.sensortypeid,
            sensormodel = EXCLUDED.sensormodel,
            serialnumber = EXCLUDED.serialnumber,
            position = EXCLUDED.position,
            samplinginterval_seconds = EXCLUDED.samplinginterval_seconds,
            unit = EXCLUDED.unit,
            externalmetadata = EXCLUDED.externalmetadata,
            isactive = EXCLUDED.isactive,
            updatedby = EXCLUDED.createdby,
            updatedat = NOW();
        
        RETURN QUERY SELECT 
            sensor_rec->>'externalid', 
            (SELECT s.sensorid FROM sensor.sensors s WHERE s.externalid = sensor_rec->>'externalid');
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.bulk_upsert_sensors IS 'Bulk upserts sensors from JSON array, returns external IDs and sensor IDs';
GRANT EXECUTE ON FUNCTION public.bulk_upsert_sensors TO service_role;
