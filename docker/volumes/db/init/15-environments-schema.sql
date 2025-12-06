-- XR Future Forests Lab - Environments Schema Migration
-- This migration creates the environments schema for environmental condition variants

-- Create environments schema
CREATE SCHEMA IF NOT EXISTS environments;

-- Set search path
SET search_path TO environments, shared, sensor, public;

-- =============================================================================
-- ENVIRONMENTS TABLE (VARIANT-BASED)
-- =============================================================================

CREATE TABLE environments.Environments (
    VariantID SERIAL PRIMARY KEY,
    ParentVariantID INTEGER REFERENCES environments.Environments(VariantID) ON DELETE SET NULL,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    ScenarioID INTEGER REFERENCES shared.Scenarios(ScenarioID) ON DELETE SET NULL,
    VariantTypeID INTEGER NOT NULL REFERENCES shared.VariantTypes(VariantTypeID),
    ProcessID INTEGER REFERENCES shared.Processes(ProcessID) ON DELETE SET NULL,
    VariantName VARCHAR(300) NOT NULL,
    StartDate TIMESTAMPTZ,
    EndDate TIMESTAMPTZ,
    AvgTemperature_C NUMERIC(6, 2) CHECK (AvgTemperature_C >= -50 AND AvgTemperature_C <= 60),
    AvgHumidity_percent NUMERIC(5, 2) CHECK (AvgHumidity_percent >= 0 AND AvgHumidity_percent <= 100),
    TotalPrecipitation_mm NUMERIC(8, 2) CHECK (TotalPrecipitation_mm >= 0),
    AvgGlobalRadiation NUMERIC(8, 2) CHECK (AvgGlobalRadiation >= 0),
    AvgCO2_ppm NUMERIC(7, 2) CHECK (AvgCO2_ppm >= 200 AND AvgCO2_ppm <= 2000),
    AvgWindSpeed_ms NUMERIC(6, 2) CHECK (AvgWindSpeed_ms >= 0 AND AvgWindSpeed_ms <= 100),
    DominantWindDirection_deg NUMERIC(5, 2) CHECK (DominantWindDirection_deg >= 0 AND DominantWindDirection_deg < 360),
    AvgSoilMoisture_percent NUMERIC(5, 2) CHECK (AvgSoilMoisture_percent >= 0 AND AvgSoilMoisture_percent <= 100),
    AvgSoilTemperature_C NUMERIC(6, 2) CHECK (AvgSoilTemperature_C >= -20 AND AvgSoilTemperature_C <= 40),
    SoilPH NUMERIC(4, 2) CHECK (SoilPH >= 3 AND SoilPH <= 10),
    NutrientNitrogen_mg_kg NUMERIC(8, 2) CHECK (NutrientNitrogen_mg_kg >= 0),
    NutrientPhosphorus_mg_kg NUMERIC(8, 2) CHECK (NutrientPhosphorus_mg_kg >= 0),
    NutrientPotassium_mg_kg NUMERIC(8, 2) CHECK (NutrientPotassium_mg_kg >= 0),
    StressFactor NUMERIC(3, 2) CHECK (StressFactor >= 0 AND StressFactor <= 1),
    Description TEXT,
    ResearchNotes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    CONSTRAINT chk_date_range CHECK (EndDate IS NULL OR StartDate IS NULL OR EndDate >= StartDate)
);

COMMENT ON TABLE environments.Environments IS 'Environmental condition variants derived from sensors, models, or user input';
COMMENT ON COLUMN environments.Environments.VariantID IS 'Unique identifier for this environment variant';
COMMENT ON COLUMN environments.Environments.ParentVariantID IS 'Parent variant for tracking environmental modifications';
COMMENT ON COLUMN environments.Environments.StartDate IS 'Start of environmental measurement period';
COMMENT ON COLUMN environments.Environments.EndDate IS 'End of environmental measurement period (NULL for ongoing)';
COMMENT ON COLUMN environments.Environments.AvgGlobalRadiation IS 'Average global radiation in W/m²';
COMMENT ON COLUMN environments.Environments.StressFactor IS 'Environmental stress index (0=optimal, 1=severe stress)';

-- Create indexes
CREATE INDEX idx_environments_parent_variant ON environments.Environments(ParentVariantID);
CREATE INDEX idx_environments_location ON environments.Environments(LocationID);
CREATE INDEX idx_environments_scenario ON environments.Environments(ScenarioID);
CREATE INDEX idx_environments_variant_type ON environments.Environments(VariantTypeID);
CREATE INDEX idx_environments_process ON environments.Environments(ProcessID);
CREATE INDEX idx_environments_start_date ON environments.Environments(StartDate DESC);
CREATE INDEX idx_environments_end_date ON environments.Environments(EndDate DESC NULLS LAST);
CREATE INDEX idx_environments_created_at ON environments.Environments(CreatedAt DESC);
CREATE INDEX idx_environments_created_by ON environments.Environments(CreatedBy);

-- =============================================================================
-- JUNCTION TABLE: PROCESS PARAMETERS FOR ENVIRONMENTS
-- =============================================================================

CREATE TABLE shared.ProcessParameters_Environments (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES environments.Environments(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, VariantID)
);

COMMENT ON TABLE shared.ProcessParameters_Environments IS 'Links process parameters to environment variants';

CREATE INDEX idx_pp_environments_parameter ON shared.ProcessParameters_Environments(ParameterID);
CREATE INDEX idx_pp_environments_variant ON shared.ProcessParameters_Environments(VariantID);

-- =============================================================================
-- JUNCTION TABLE: AUDIT LOG FOR ENVIRONMENTS
-- =============================================================================

CREATE TABLE shared.AuditLog_Environments (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES environments.Environments(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, VariantID)
);

COMMENT ON TABLE shared.AuditLog_Environments IS 'Links audit log entries to environment variants';

CREATE INDEX idx_audit_environments_audit ON shared.AuditLog_Environments(AuditID);
CREATE INDEX idx_audit_environments_variant ON shared.AuditLog_Environments(VariantID);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to calculate environment duration in days
CREATE OR REPLACE FUNCTION environments.calculate_duration_days(start_date TIMESTAMPTZ, end_date TIMESTAMPTZ)
RETURNS INTEGER AS $$
BEGIN
    IF start_date IS NULL OR end_date IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN EXTRACT(DAY FROM (end_date - start_date))::INTEGER;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION environments.calculate_duration_days IS 'Calculates duration in days between start and end dates';

-- Function to check if environment is currently active
CREATE OR REPLACE FUNCTION environments.is_active(start_date TIMESTAMPTZ, end_date TIMESTAMPTZ)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW());
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION environments.is_active IS 'Checks if environment variant is currently active';

-- Function to create environment variant from sensor aggregation
CREATE OR REPLACE FUNCTION environments.create_from_sensor_data(
    location_id_param INTEGER,
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    variant_name_param VARCHAR DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    new_variant_id INTEGER;
    calculated_variant_name VARCHAR;
BEGIN
    -- Generate variant name if not provided
    IF variant_name_param IS NULL THEN
        calculated_variant_name := 'Sensor_Aggregation_' ||
            location_id_param || '_' ||
            TO_CHAR(start_time, 'YYYY-MM-DD') || '_to_' ||
            TO_CHAR(end_time, 'YYYY-MM-DD');
    ELSE
        calculated_variant_name := variant_name_param;
    END IF;

    -- Insert aggregated environment variant
    INSERT INTO environments.Environments (
        LocationID,
        VariantTypeID,
        ProcessID,
        VariantName,
        StartDate,
        EndDate,
        AvgTemperature_C,
        AvgHumidity_percent,
        TotalPrecipitation_mm,
        AvgCO2_ppm,
        AvgWindSpeed_ms,
        AvgSoilMoisture_percent,
        AvgSoilTemperature_C
    )
    SELECT
        location_id_param,
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'sensor_derived'),
        (SELECT ProcessID FROM shared.Processes WHERE ProcessName = 'Sensor_Data_Aggregation' LIMIT 1),
        calculated_variant_name,
        start_time,
        end_time,
        AVG(CASE WHEN st.SensorTypeName = 'Temperature' THEN sr.Value END) AS AvgTemperature_C,
        AVG(CASE WHEN st.SensorTypeName = 'Humidity' THEN sr.Value END) AS AvgHumidity_percent,
        SUM(CASE WHEN st.SensorTypeName = 'Precipitation' THEN sr.Value END) AS TotalPrecipitation_mm,
        AVG(CASE WHEN st.SensorTypeName = 'CO2' THEN sr.Value END) AS AvgCO2_ppm,
        AVG(CASE WHEN st.SensorTypeName = 'Wind_Speed' THEN sr.Value END) AS AvgWindSpeed_ms,
        AVG(CASE WHEN st.SensorTypeName = 'Soil_Moisture' THEN sr.Value END) AS AvgSoilMoisture_percent,
        AVG(CASE WHEN st.SensorTypeName = 'Soil_Temperature' THEN sr.Value END) AS AvgSoilTemperature_C
    FROM sensor.SensorReadings sr
    JOIN sensor.Sensors s ON sr.SensorID = s.SensorID
    JOIN sensor.SensorTypes st ON s.SensorTypeID = st.SensorTypeID
    WHERE s.LocationID = location_id_param
        AND sr.Timestamp >= start_time
        AND sr.Timestamp <= end_time
        AND sr.Quality IN ('good', 'suspect')
    HAVING COUNT(*) > 0
    RETURNING VariantID INTO new_variant_id;

    RETURN new_variant_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION environments.create_from_sensor_data IS 'Creates environment variant by aggregating sensor readings';

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
-- =============================================================================

CREATE OR REPLACE FUNCTION environments.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.UpdatedAt = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_environments_updated_at
    BEFORE UPDATE ON environments.Environments
    FOR EACH ROW
    EXECUTE FUNCTION environments.update_updated_at_column();

-- =============================================================================
-- VIEWS FOR COMMON QUERIES
-- =============================================================================

-- View: Active environments with computed metrics
CREATE OR REPLACE VIEW environments.active_environments AS
SELECT
    e.*,
    environments.calculate_duration_days(e.StartDate, e.EndDate) AS duration_days,
    environments.is_active(e.StartDate, e.EndDate) AS is_active,
    l.LocationName,
    s.ScenarioName,
    vt.VariantTypeName
FROM environments.Environments e
LEFT JOIN shared.Locations l ON e.LocationID = l.LocationID
LEFT JOIN shared.Scenarios s ON e.ScenarioID = s.ScenarioID
LEFT JOIN shared.VariantTypes vt ON e.VariantTypeID = vt.VariantTypeID
WHERE environments.is_active(e.StartDate, e.EndDate) = TRUE;

COMMENT ON VIEW environments.active_environments IS 'Currently active environment variants with location and scenario context';

-- View: Environment summary statistics by location
CREATE OR REPLACE VIEW environments.location_environment_summary AS
SELECT
    l.LocationID,
    l.LocationName,
    COUNT(e.VariantID) AS environment_count,
    AVG(e.AvgTemperature_C) AS avg_temperature,
    AVG(e.AvgHumidity_percent) AS avg_humidity,
    AVG(e.AvgCO2_ppm) AS avg_co2,
    AVG(e.StressFactor) AS avg_stress_factor,
    MIN(e.StartDate) AS earliest_measurement,
    MAX(e.EndDate) AS latest_measurement
FROM shared.Locations l
LEFT JOIN environments.Environments e ON l.LocationID = e.LocationID
GROUP BY l.LocationID, l.LocationName;

COMMENT ON VIEW environments.location_environment_summary IS 'Summary statistics of environmental conditions by location';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA environments TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA environments TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA environments TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA environments TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA environments TO anon, authenticated, service_role;
