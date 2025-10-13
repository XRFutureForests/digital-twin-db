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
    SensorTypeID SERIAL PRIMARY KEY,
    SensorTypeName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    TypicalUnit VARCHAR(50),
    TypicalRangeMin NUMERIC(12, 4),
    TypicalRangeMax NUMERIC(12, 4),
    CONSTRAINT chk_typical_range CHECK (TypicalRangeMin IS NULL OR TypicalRangeMax IS NULL OR TypicalRangeMin <= TypicalRangeMax)
);

COMMENT ON TABLE sensor.SensorTypes IS 'Environmental sensor type classifications';

INSERT INTO sensor.SensorTypes (SensorTypeName, Description, TypicalUnit, TypicalRangeMin, TypicalRangeMax) VALUES
    ('Temperature', 'Air or soil temperature sensor', '°C', -50, 60),
    ('Humidity', 'Relative humidity sensor', '%', 0, 100),
    ('CO2', 'Carbon dioxide concentration sensor', 'ppm', 200, 2000),
    ('Light', 'Light intensity or PAR sensor', 'lux', 0, 200000),
    ('Soil_Moisture', 'Soil volumetric water content', '%', 0, 100),
    ('Wind_Speed', 'Wind speed anemometer', 'm/s', 0, 50),
    ('Wind_Direction', 'Wind direction vane', 'degrees', 0, 360),
    ('Precipitation', 'Rain gauge', 'mm', 0, 500),
    ('Barometric_Pressure', 'Atmospheric pressure', 'hPa', 900, 1100),
    ('Solar_Radiation', 'Solar irradiance', 'W/m²', 0, 1500),
    ('Soil_Temperature', 'Subsurface soil temperature', '°C', -20, 40),
    ('Leaf_Wetness', 'Leaf surface moisture', 'units', 0, 15),
    ('Sap_Flow', 'Tree sap flow rate', 'g/h', 0, 10000);

CREATE INDEX idx_sensor_types_name ON sensor.SensorTypes(SensorTypeName);

-- =============================================================================
-- SENSORS TABLE
-- =============================================================================

CREATE TABLE sensor.Sensors (
    SensorID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    SensorTypeID INTEGER NOT NULL REFERENCES sensor.SensorTypes(SensorTypeID),
    SensorModel VARCHAR(200) NOT NULL,
    SerialNumber VARCHAR(100),
    Position GEOMETRY(Point, 4326) NOT NULL,
    InstallationDate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    DecommissionDate TIMESTAMPTZ,
    CalibrationDate TIMESTAMPTZ,
    NextCalibrationDate TIMESTAMPTZ,
    SamplingInterval_seconds INTEGER NOT NULL CHECK (SamplingInterval_seconds > 0),
    ReadingType VARCHAR(100),
    Unit VARCHAR(50),
    MinValue NUMERIC(12, 4),
    MaxValue NUMERIC(12, 4),
    Accuracy NUMERIC(8, 4),
    BatteryLevel_percent NUMERIC(5, 2) CHECK (BatteryLevel_percent >= 0 AND BatteryLevel_percent <= 100),
    IsActive BOOLEAN DEFAULT TRUE,
    MaintenanceNotes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    CONSTRAINT chk_value_range CHECK (MinValue IS NULL OR MaxValue IS NULL OR MinValue <= MaxValue),
    CONSTRAINT chk_decommission_date CHECK (DecommissionDate IS NULL OR DecommissionDate >= InstallationDate)
);

COMMENT ON TABLE sensor.Sensors IS 'Physical sensor installations with metadata and configuration';
COMMENT ON COLUMN sensor.Sensors.Position IS 'PostGIS point for sensor location in WGS84';
COMMENT ON COLUMN sensor.Sensors.SamplingInterval_seconds IS 'Frequency of sensor measurements in seconds';
COMMENT ON COLUMN sensor.Sensors.IsActive IS 'Whether sensor is currently collecting data';

-- Create indexes
CREATE INDEX idx_sensors_location ON sensor.Sensors(LocationID);
CREATE INDEX idx_sensors_sensor_type ON sensor.Sensors(SensorTypeID);
CREATE INDEX idx_sensors_position ON sensor.Sensors USING GIST (Position);
CREATE INDEX idx_sensors_is_active ON sensor.Sensors(IsActive);
CREATE INDEX idx_sensors_installation_date ON sensor.Sensors(InstallationDate DESC);
CREATE INDEX idx_sensors_serial_number ON sensor.Sensors(SerialNumber);
CREATE INDEX idx_sensors_created_by ON sensor.Sensors(CreatedBy);

-- =============================================================================
-- SENSOR READINGS TABLE (TIME-SERIES DATA)
-- =============================================================================

CREATE TABLE sensor.SensorReadings (
    ReadingID BIGSERIAL PRIMARY KEY,
    SensorID INTEGER NOT NULL REFERENCES sensor.Sensors(SensorID) ON DELETE CASCADE,
    Timestamp TIMESTAMPTZ NOT NULL,
    Value NUMERIC(12, 4) NOT NULL,
    Quality VARCHAR(50) CHECK (Quality IN ('good', 'suspect', 'bad', 'missing', 'calibration')),
    ScenarioID INTEGER REFERENCES shared.Scenarios(ScenarioID) ON DELETE SET NULL,
    BatteryVoltage NUMERIC(4, 2),
    SignalStrength NUMERIC(6, 2),
    Notes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE sensor.SensorReadings IS 'Time-series environmental sensor measurements';
COMMENT ON COLUMN sensor.SensorReadings.Quality IS 'Data quality flag (good, suspect, bad, missing, calibration)';
COMMENT ON COLUMN sensor.SensorReadings.ScenarioID IS 'NULL for real readings, references scenario for simulated data';
COMMENT ON COLUMN sensor.SensorReadings.SignalStrength IS 'Wireless signal strength in dBm';

-- Create indexes optimized for time-series queries
CREATE INDEX idx_sensor_readings_sensor_id ON sensor.SensorReadings(SensorID);
CREATE INDEX idx_sensor_readings_timestamp ON sensor.SensorReadings(Timestamp DESC);
CREATE INDEX idx_sensor_readings_sensor_timestamp ON sensor.SensorReadings(SensorID, Timestamp DESC);
CREATE INDEX idx_sensor_readings_quality ON sensor.SensorReadings(Quality);
CREATE INDEX idx_sensor_readings_scenario ON sensor.SensorReadings(ScenarioID);

-- Partial index for recent readings (last 30 days) - frequently queried
CREATE INDEX idx_sensor_readings_recent ON sensor.SensorReadings(SensorID, Timestamp DESC)
    WHERE Timestamp > NOW() - INTERVAL '30 days';

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to get latest reading for a sensor
CREATE OR REPLACE FUNCTION sensor.get_latest_reading(sensor_id_param INTEGER)
RETURNS TABLE (
    ReadingID BIGINT,
    Timestamp TIMESTAMPTZ,
    Value NUMERIC,
    Quality VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sr.ReadingID,
        sr.Timestamp,
        sr.Value,
        sr.Quality
    FROM sensor.SensorReadings sr
    WHERE sr.SensorID = sensor_id_param
    ORDER BY sr.Timestamp DESC
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
        date_trunc('hour', sr.Timestamp) +
            (EXTRACT(HOUR FROM sr.Timestamp)::INTEGER / (interval_minutes / 60)) *
            (interval_minutes || ' minutes')::INTERVAL AS time_bucket,
        AVG(sr.Value) AS avg_value,
        MIN(sr.Value) AS min_value,
        MAX(sr.Value) AS max_value,
        COUNT(*) AS reading_count
    FROM sensor.SensorReadings sr
    WHERE sr.SensorID = sensor_id_param
        AND sr.Timestamp >= start_time
        AND sr.Timestamp <= end_time
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
    SensorID INTEGER,
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
    SELECT s.SamplingInterval_seconds, sr.Timestamp
    INTO sampling_interval, last_reading
    FROM sensor.Sensors s
    LEFT JOIN sensor.SensorReadings sr ON s.SensorID = sr.SensorID
    WHERE s.SensorID = sensor_id_param
    ORDER BY sr.Timestamp DESC
    LIMIT 1;

    -- Calculate expected readings
    expected_readings := (hours_back * 3600) / sampling_interval;

    -- Count actual readings
    SELECT COUNT(*), COUNT(*) FILTER (WHERE Quality = 'good')
    INTO actual_readings, good_readings
    FROM sensor.SensorReadings sr
    WHERE sr.SensorID = sensor_id_param
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
    NEW.UpdatedAt = NOW();
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
    s.SensorID,
    s.LocationID,
    st.SensorTypeName,
    s.SensorModel,
    s.IsActive,
    s.BatteryLevel_percent,
    (SELECT sr.Timestamp FROM sensor.SensorReadings sr
     WHERE sr.SensorID = s.SensorID
     ORDER BY sr.Timestamp DESC LIMIT 1) AS last_reading_time,
    (SELECT sr.Value FROM sensor.SensorReadings sr
     WHERE sr.SensorID = s.SensorID
     ORDER BY sr.Timestamp DESC LIMIT 1) AS last_reading_value,
    (SELECT sr.Quality FROM sensor.SensorReadings sr
     WHERE sr.SensorID = s.SensorID
     ORDER BY sr.Timestamp DESC LIMIT 1) AS last_reading_quality
FROM sensor.Sensors s
JOIN sensor.SensorTypes st ON s.SensorTypeID = st.SensorTypeID
WHERE s.IsActive = TRUE;

COMMENT ON VIEW sensor.active_sensors_status IS 'Active sensors with their latest reading information';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA sensor TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA sensor TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA sensor TO service_role;
GRANT INSERT ON sensor.SensorReadings TO authenticated;  -- Allow authenticated users to insert readings
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA sensor TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sensor TO anon, authenticated, service_role;
