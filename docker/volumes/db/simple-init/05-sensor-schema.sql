-- =============================================================================
-- 05: SENSOR SCHEMA
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- Environmental sensor hardware and time-series readings
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS sensor;
SET search_path TO sensor, shared, public, extensions;

-- =============================================================================
-- SENSOR TYPES REFERENCE TABLE
-- =============================================================================

CREATE TABLE sensor.SensorTypes (
    SensorTypeID SERIAL PRIMARY KEY,
    SensorTypeName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    TypicalUnit VARCHAR(50),
    TypicalRangeMin NUMERIC(12, 4),
    TypicalRangeMax NUMERIC(12, 4)
);

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
    ('Sap_Flow', 'Tree sap flow rate', 'g/h', 0, 10000),
    ('Stem_Radial_Variation', 'Dendrometer stem diameter', 'mm', -10, 100);

-- =============================================================================
-- SENSORS TABLE
-- =============================================================================

CREATE TABLE sensor.Sensors (
    SensorID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    SensorTypeID INTEGER NOT NULL REFERENCES sensor.SensorTypes(SensorTypeID),
    SensorModel VARCHAR(200) NOT NULL,
    SerialNumber VARCHAR(100),
    Position GEOMETRY(Point, 4326),
    PositionOriginal GEOMETRY,
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
    ExternalID VARCHAR(200),
    ExternalMetadata JSONB,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200)
);

COMMENT ON TABLE sensor.Sensors IS 'Physical sensor installations with metadata';

CREATE INDEX idx_sensors_location ON sensor.Sensors(LocationID);
CREATE INDEX idx_sensors_sensor_type ON sensor.Sensors(SensorTypeID);
CREATE INDEX idx_sensors_position ON sensor.Sensors USING GIST (Position);
CREATE INDEX idx_sensors_is_active ON sensor.Sensors(IsActive);
CREATE INDEX idx_sensors_external_id ON sensor.Sensors(ExternalID);

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

CREATE INDEX idx_sensor_readings_sensor_id ON sensor.SensorReadings(SensorID);
CREATE INDEX idx_sensor_readings_timestamp ON sensor.SensorReadings(Timestamp DESC);
CREATE INDEX idx_sensor_readings_sensor_timestamp ON sensor.SensorReadings(SensorID, Timestamp DESC);
CREATE INDEX idx_sensor_readings_quality ON sensor.SensorReadings(Quality);

-- =============================================================================
-- SENSOR-TREE LINKS TABLE
-- =============================================================================

CREATE TABLE sensor.SensorTreeLinks (
    LinkID SERIAL PRIMARY KEY,
    SensorID INTEGER NOT NULL REFERENCES sensor.Sensors(SensorID) ON DELETE CASCADE,
    TreeVariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    Description TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (SensorID, TreeVariantID)
);

COMMENT ON TABLE sensor.SensorTreeLinks IS 'Links sensors to specific trees for growth monitoring';

CREATE INDEX idx_sensor_tree_links_sensor ON sensor.SensorTreeLinks(SensorID);
CREATE INDEX idx_sensor_tree_links_tree ON sensor.SensorTreeLinks(TreeVariantID);

-- =============================================================================
-- TRIGGERS
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

DO $$
BEGIN
    RAISE NOTICE '✅ Sensor schema created';
END
$$;
