-- XR Future Forests Lab - Sensor Schema Migration
-- This migration creates the sensor schema for environmental monitoring hardware and time-series readings

-- Create sensor schema
CREATE SCHEMA IF NOT EXISTS sensor;

-- Set search path
SET search_path TO sensor, shared, public;

-- =============================================================================
-- SENSOR TYPES REFERENCE TABLE
-- =============================================================================

CREATE TABLE sensor.SensorTypes (
    sensor_type_id SERIAL PRIMARY KEY,
    sensor_type_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    typical_unit VARCHAR(50),
    typical_range_min NUMERIC(12, 4),
    typical_range_max NUMERIC(12, 4),
    CONSTRAINT chk_typical_range CHECK (typical_range_min IS NULL OR typical_range_max IS NULL OR typical_range_min <= typical_range_max)
);

COMMENT ON TABLE sensor.SensorTypes IS 'Environmental sensor type classifications';

-- =============================================================================
-- NOTE: Sensor type data is now loaded from CSV files in data/lookups/
-- by 30-load-lookup-tables.sql
-- =============================================================================

CREATE INDEX idx_sensor_types_name ON sensor.SensorTypes(sensor_type_name);

-- =============================================================================
-- SENSORS TABLE
-- =============================================================================

CREATE TABLE sensor.Sensors (
    sensor_id SERIAL PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    sensor_type_id INTEGER NOT NULL REFERENCES sensor.SensorTypes(sensor_type_id),
    campaign_id INTEGER REFERENCES shared.Campaigns(campaign_id) ON DELETE SET NULL,
    plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    sensor_model VARCHAR(200) NOT NULL,
    serial_number VARCHAR(100),
    Position extensions.GEOMETRY(Point, 4326) NOT NULL,
    position_original extensions.GEOMETRY,
    source_crs INTEGER,
    installation_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    installation_height_m NUMERIC(5, 2) CHECK (installation_height_m >= 0),
    decommission_date TIMESTAMPTZ,
    calibration_date TIMESTAMPTZ,
    next_calibration_date TIMESTAMPTZ,
    sampling_interval_seconds INTEGER NOT NULL CHECK (sampling_interval_seconds > 0),
    reading_type VARCHAR(100),
    Unit VARCHAR(50),
    min_value NUMERIC(12, 4),
    max_value NUMERIC(12, 4),
    Accuracy NUMERIC(8, 4),
    battery_level_percent NUMERIC(5, 2) CHECK (battery_level_percent >= 0 AND battery_level_percent <= 100),
    is_active BOOLEAN DEFAULT TRUE,
    maintenance_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    CONSTRAINT chk_value_range CHECK (min_value IS NULL OR max_value IS NULL OR min_value <= max_value),
    CONSTRAINT chk_decommission_date CHECK (decommission_date IS NULL OR decommission_date >= installation_date)
);

COMMENT ON TABLE sensor.Sensors IS 'Physical sensor installations with metadata and configuration';
COMMENT ON COLUMN sensor.Sensors.Position IS 'PostGIS point for sensor location in WGS84';
COMMENT ON COLUMN sensor.Sensors.position_original IS 'Original coordinates in source CRS before WGS84 transformation';
COMMENT ON COLUMN sensor.Sensors.sampling_interval_seconds IS 'Frequency of sensor measurements in seconds';
COMMENT ON COLUMN sensor.Sensors.is_active IS 'Whether sensor is currently collecting data';
COMMENT ON COLUMN sensor.Sensors.campaign_id IS 'Deployment campaign this sensor was installed during';
COMMENT ON COLUMN sensor.Sensors.source_crs IS 'EPSG code of original coordinate reference system for position_original';
COMMENT ON COLUMN sensor.Sensors.installation_height_m IS 'Height of sensor installation above ground in meters';

-- Create indexes
CREATE INDEX idx_sensors_location ON sensor.Sensors(location_id);
CREATE INDEX idx_sensors_sensor_type ON sensor.Sensors(sensor_type_id);
CREATE INDEX idx_sensors_position ON sensor.Sensors USING GIST (Position);
CREATE INDEX idx_sensors_is_active ON sensor.Sensors(is_active);
CREATE INDEX idx_sensors_installation_date ON sensor.Sensors(installation_date DESC);
CREATE INDEX idx_sensors_serial_number ON sensor.Sensors(serial_number);
CREATE INDEX idx_sensors_created_by ON sensor.Sensors(created_by);
CREATE INDEX idx_sensors_campaign ON sensor.Sensors(campaign_id);

-- =============================================================================
-- SENSOR READINGS TABLE (TIME-SERIES DATA)
-- =============================================================================

CREATE TABLE sensor.SensorReadings (
    sensor_reading_id BIGSERIAL PRIMARY KEY,
    sensor_id INTEGER NOT NULL REFERENCES sensor.Sensors(sensor_id) ON DELETE CASCADE,
    Timestamp TIMESTAMPTZ NOT NULL,
    Value NUMERIC(12, 4) NOT NULL,
    Quality VARCHAR(50) CHECK (Quality IN ('good', 'suspect', 'bad', 'missing', 'calibration')),
    scenario_id INTEGER REFERENCES shared.Scenarios(scenario_id) ON DELETE SET NULL,
    battery_voltage NUMERIC(4, 2),
    signal_strength NUMERIC(6, 2),
    Notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE sensor.SensorReadings IS 'Time-series environmental sensor measurements';
COMMENT ON COLUMN sensor.SensorReadings.Quality IS 'Data quality flag (good, suspect, bad, missing, calibration)';
COMMENT ON COLUMN sensor.SensorReadings.scenario_id IS 'NULL for real readings, references scenario for simulated data';
COMMENT ON COLUMN sensor.SensorReadings.signal_strength IS 'Wireless signal strength in dBm';

-- Create indexes optimized for time-series queries
CREATE INDEX idx_sensor_readings_sensor_id ON sensor.SensorReadings(sensor_id);
CREATE INDEX idx_sensor_readings_timestamp ON sensor.SensorReadings(Timestamp DESC);
CREATE INDEX idx_sensor_readings_sensor_timestamp ON sensor.SensorReadings(sensor_id, Timestamp DESC);
CREATE INDEX idx_sensor_readings_quality ON sensor.SensorReadings(Quality);
CREATE INDEX idx_sensor_readings_scenario ON sensor.SensorReadings(scenario_id);

-- Note: idx_sensor_readings_sensor_timestamp already covers recent reading queries

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to get latest reading for a sensor
CREATE OR REPLACE FUNCTION sensor.get_latest_reading(sensor_id_param INTEGER)
RETURNS TABLE (
    sensor_reading_id BIGINT,
    reading_timestamp TIMESTAMPTZ,
    Value NUMERIC,
    Quality VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sr.sensor_reading_id,
        sr."Timestamp",
        sr.Value,
        sr.Quality
    FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = sensor_id_param
    ORDER BY sr."Timestamp" DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION sensor.get_latest_reading IS 'Returns the most recent reading for a sensor';

-- Function to aggregate sensor readings by time interval
CREATE OR REPLACE FUNCTION sensor.aggregate_readings(
    sensor_id_param INTEGER,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    interval_minutes INTEGER DEFAULT 60
)
RETURNS TABLE (
    time_bucket TIMESTAMPTZ,
    avg_value NUMERIC,
    min_value NUMERIC,
    max_value NUMERIC,
    reading_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        date_trunc('hour', sr."Timestamp") +
            ((EXTRACT(MINUTE FROM sr."Timestamp")::INTEGER / interval_minutes) * interval_minutes || ' minutes')::INTERVAL AS time_bucket,
        AVG(sr.Value) AS avg_value,
        MIN(sr.Value) AS min_value,
        MAX(sr.Value) AS max_value,
        COUNT(*) AS reading_count
    FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = sensor_id_param
        AND sr."Timestamp" >= start_time
        AND sr."Timestamp" <= end_time
        AND sr.Quality IN ('good', 'suspect')
    GROUP BY time_bucket
    ORDER BY time_bucket;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION sensor.aggregate_readings IS 'Aggregates sensor readings into time intervals';

-- Function to check sensor health based on recent readings
CREATE OR REPLACE FUNCTION sensor.check_sensor_health(
    sensor_id_param INTEGER,
    hours_back INTEGER DEFAULT 24
)
RETURNS TABLE (
    sensor_id INTEGER,
    IsHealthy BOOLEAN,
    LastReading TIMESTAMPTZ,
    ReadingsCount BIGINT,
    GoodQualityPercent NUMERIC,
    Issues TEXT
) AS $$
DECLARE
    expected_readings INTEGER;
    actual_readings BIGINT;
    good_readings BIGINT;
    last_reading TIMESTAMPTZ;
    sampling_interval INTEGER;
    health_issues TEXT := '';
BEGIN
    -- Get sensor sampling interval
    SELECT s.sampling_interval_seconds, sr.Timestamp
    INTO sampling_interval, last_reading
    FROM sensor.Sensors s
    LEFT JOIN sensor.SensorReadings sr ON s.sensor_id = sr.sensor_id
    WHERE s.sensor_id = sensor_id_param
    ORDER BY sr.Timestamp DESC
    LIMIT 1;

    -- Calculate expected readings
    expected_readings := (hours_back * 3600) / sampling_interval;

    -- Count actual readings
    SELECT COUNT(*), COUNT(*) FILTER (WHERE Quality = 'good')
    INTO actual_readings, good_readings
    FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = sensor_id_param
        AND sr.Timestamp > NOW() - (hours_back || ' hours')::INTERVAL;

    -- Check for issues
    IF last_reading < NOW() - (hours_back || ' hours')::INTERVAL THEN
        health_issues := health_issues || 'No recent readings; ';
    END IF;

    IF actual_readings < (expected_readings * 0.8) THEN
        health_issues := health_issues || 'Missing readings; ';
    END IF;

    IF actual_readings > 0 AND (good_readings::NUMERIC / actual_readings) < 0.9 THEN
        health_issues := health_issues || 'Low quality readings; ';
    END IF;

    RETURN QUERY SELECT
        sensor_id_param,
        (health_issues = '') AS IsHealthy,
        last_reading,
        actual_readings,
        CASE WHEN actual_readings > 0
            THEN ROUND((good_readings::NUMERIC / actual_readings * 100), 2)
            ELSE 0
        END AS GoodQualityPercent,
        NULLIF(TRIM(health_issues), '') AS Issues;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION sensor.check_sensor_health IS 'Checks sensor health based on recent reading patterns';

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
-- =============================================================================

CREATE OR REPLACE FUNCTION sensor.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_sensors_updated_at
    BEFORE UPDATE ON sensor.Sensors
    FOR EACH ROW
    EXECUTE FUNCTION sensor.update_updated_at_column();

-- =============================================================================
-- VIEWS FOR COMMON QUERIES
-- =============================================================================

-- View: Active sensors with latest readings
CREATE OR REPLACE VIEW sensor.active_sensors_status AS
SELECT
    s.sensor_id,
    s.location_id,
    st.sensor_type_name,
    s.sensor_model,
    s.is_active,
    s.battery_level_percent,
    (SELECT sr.Timestamp FROM sensor.SensorReadings sr
     WHERE sr.sensor_id = s.sensor_id
     ORDER BY sr.Timestamp DESC LIMIT 1) AS last_reading_time,
    (SELECT sr.Value FROM sensor.SensorReadings sr
     WHERE sr.sensor_id = s.sensor_id
     ORDER BY sr.Timestamp DESC LIMIT 1) AS last_reading_value,
    (SELECT sr.Quality FROM sensor.SensorReadings sr
     WHERE sr.sensor_id = s.sensor_id
     ORDER BY sr.Timestamp DESC LIMIT 1) AS last_reading_quality
FROM sensor.Sensors s
JOIN sensor.SensorTypes st ON s.sensor_type_id = st.sensor_type_id
WHERE s.is_active = TRUE;

COMMENT ON VIEW sensor.active_sensors_status IS 'Active sensors with their latest reading information';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA sensor TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA sensor TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA sensor TO service_role;
GRANT INSERT ON sensor.SensorReadings TO authenticated;  -- Allow authenticated users to insert readings
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA sensor TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sensor TO anon, authenticated, service_role;
