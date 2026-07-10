-- Aquarius Integration Migration
-- Adds support for external sensor IDs and linking sensors to trees

SET search_path TO sensor, trees, shared, public;

-- 1. Generic external-source fields on Sensors. These are source-agnostic: a
--    sensor's data may come from any provider (Aquarius is one of many). The
--    Aquarius-specific import logic lives in scripts/import/, not in the schema.
ALTER TABLE sensor.Sensors
ADD COLUMN IF NOT EXISTS source VARCHAR(50),
ADD COLUMN IF NOT EXISTS external_id VARCHAR(200) UNIQUE,
ADD COLUMN IF NOT EXISTS external_metadata JSONB DEFAULT '{}'::jsonb;

COMMENT ON COLUMN sensor.Sensors.source IS 'External system this sensor''s data comes from (e.g. ''aquarius''). One of many possible providers.';
COMMENT ON COLUMN sensor.Sensors.external_id IS 'Unique identifier for this sensor within its source system (see source).';
COMMENT ON COLUMN sensor.Sensors.external_metadata IS 'Additional source-specific metadata (raw payload from the provider).';
CREATE INDEX IF NOT EXISTS idx_sensors_source ON sensor.Sensors(source);

-- NOTE: Sensor types (including Stem_Radial_Variation) are loaded from data/lookups/sensor_types.csv
-- NOTE: Sensor-tree links table is created in 16-sensor-tree-links-schema.sql

-- 2. Create index for external ID lookups
CREATE INDEX IF NOT EXISTS idx_sensors_external_id ON sensor.Sensors(external_id);

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
            location_id, plot_id, source, sensor_type_id, sensor_model, serial_number,
            position, sampling_interval_seconds, unit, external_id,
            external_metadata, is_active, created_by
        )
        VALUES (
            (sensor_rec->>'location_id')::INT,
            (sensor_rec->>'plot_id')::INT,
            sensor_rec->>'source',
            (sensor_rec->>'sensor_type_id')::INT,
            sensor_rec->>'sensor_model',
            sensor_rec->>'serial_number',
            v_position,
            (sensor_rec->>'sampling_interval_seconds')::INT,
            sensor_rec->>'unit',
            sensor_rec->>'external_id',
            (sensor_rec->'external_metadata')::JSONB,
            (sensor_rec->>'is_active')::BOOLEAN,
            sensor_rec->>'created_by'
        )
        ON CONFLICT (external_id) DO UPDATE SET
            location_id = EXCLUDED.location_id,
            plot_id = EXCLUDED.plot_id,
            source = EXCLUDED.source,
            sensor_type_id = EXCLUDED.sensor_type_id,
            sensor_model = EXCLUDED.sensor_model,
            serial_number = EXCLUDED.serial_number,
            position = EXCLUDED.position,
            sampling_interval_seconds = EXCLUDED.sampling_interval_seconds,
            unit = EXCLUDED.unit,
            external_metadata = EXCLUDED.external_metadata,
            is_active = EXCLUDED.is_active,
            updated_by = EXCLUDED.created_by,
            updated_at = NOW();
        
        RETURN QUERY SELECT 
            (sensor_rec->>'external_id')::VARCHAR AS out_externalid, 
            (SELECT s.sensor_id FROM sensor.sensors s WHERE s.external_id = sensor_rec->>'external_id') AS out_sensorid;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.bulk_upsert_sensors IS 'Bulk upserts sensors from JSON array, returns external IDs and sensor IDs';
GRANT EXECUTE ON FUNCTION public.bulk_upsert_sensors TO service_role, anon, authenticated;

-- 7. Create bulk insert function for readings with ON CONFLICT DO NOTHING
-- Add unique constraint for sensor_id,timestamp if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'sensorreadings_sensorid_timestamp_unique' 
        AND conrelid = 'sensor.sensorreadings'::regclass
    ) THEN
        ALTER TABLE sensor.sensorreadings 
        ADD CONSTRAINT sensorreadings_sensorid_timestamp_unique 
        UNIQUE (sensor_id, timestamp);
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
    INSERT INTO sensor.sensorreadings (sensor_id, timestamp, value, quality)
    SELECT 
        (r->>'sensor_id')::integer,
        (r->>'timestamp')::timestamptz,
        (r->>'value')::numeric,
        COALESCE(r->>'quality', 'good')
    FROM jsonb_array_elements(readings) AS r
    ON CONFLICT (sensor_id, timestamp) DO NOTHING;
    
    GET DIAGNOSTICS inserted_count = ROW_COUNT;
    
    RETURN QUERY SELECT inserted_count;
END;
$$;

COMMENT ON FUNCTION public.bulk_insert_readings IS 'Bulk inserts readings from JSON array, skips duplicates';
GRANT EXECUTE ON FUNCTION public.bulk_insert_readings(jsonb) TO anon, authenticated, service_role;
