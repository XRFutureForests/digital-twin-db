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
-- Uses extensions.ST_GeomFromText since PostGIS is in extensions schema
CREATE OR REPLACE FUNCTION public.bulk_upsert_sensors(
    p_sensors JSONB
) RETURNS TABLE(out_externalid VARCHAR, out_sensorid INT) AS $$
DECLARE
    sensor_rec JSONB;
    v_position extensions.geometry;
BEGIN
    FOR sensor_rec IN SELECT * FROM jsonb_array_elements(p_sensors)
    LOOP
        -- Parse position WKT if provided
        IF sensor_rec->>'position' IS NOT NULL THEN
            v_position := extensions.ST_GeomFromText(sensor_rec->>'position', 4326);
        ELSE
            v_position := NULL;
        END IF;

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
            v_position,
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
            (sensor_rec->>'externalid')::VARCHAR AS out_externalid, 
            (SELECT s.sensorid FROM sensor.sensors s WHERE s.externalid = sensor_rec->>'externalid') AS out_sensorid;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.bulk_upsert_sensors IS 'Bulk upserts sensors from JSON array, returns external IDs and sensor IDs';
GRANT EXECUTE ON FUNCTION public.bulk_upsert_sensors TO service_role, anon, authenticated;

-- 7. Create bulk insert function for readings with ON CONFLICT DO NOTHING
-- Add unique constraint for sensorid,timestamp if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'sensorreadings_sensorid_timestamp_unique' 
        AND conrelid = 'sensor.sensorreadings'::regclass
    ) THEN
        ALTER TABLE sensor.sensorreadings 
        ADD CONSTRAINT sensorreadings_sensorid_timestamp_unique 
        UNIQUE (sensorid, timestamp);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.bulk_insert_readings(readings jsonb)
RETURNS TABLE (out_inserted_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, sensor
AS $$
DECLARE
    inserted_count integer;
BEGIN
    INSERT INTO sensor.sensorreadings (sensorid, timestamp, value, quality)
    SELECT 
        (r->>'sensorid')::integer,
        (r->>'timestamp')::timestamptz,
        (r->>'value')::numeric,
        COALESCE(r->>'quality', 'good')
    FROM jsonb_array_elements(readings) AS r
    ON CONFLICT (sensorid, timestamp) DO NOTHING;
    
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    
    RETURN QUERY SELECT inserted_count;
END;
$$;

COMMENT ON FUNCTION public.bulk_insert_readings IS 'Bulk inserts readings from JSON array, skips duplicates';
GRANT EXECUTE ON FUNCTION public.bulk_insert_readings(jsonb) TO anon, authenticated, service_role;
