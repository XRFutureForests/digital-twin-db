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
    environment_id SERIAL PRIMARY KEY,
    parent_environment_id INTEGER REFERENCES environments.Environments(environment_id) ON DELETE SET NULL,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    scenario_id INTEGER REFERENCES shared.Scenarios(scenario_id) ON DELETE SET NULL,
    variant_type_id INTEGER NOT NULL REFERENCES shared.VariantTypes(variant_type_id),
    process_id INTEGER REFERENCES shared.Processes(process_id) ON DELETE SET NULL,
    variant_name VARCHAR(300) NOT NULL,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    avg_temperature_c NUMERIC(6, 2) CHECK (avg_temperature_c >= -50 AND avg_temperature_c <= 60),
    avg_humidity_percent NUMERIC(5, 2) CHECK (avg_humidity_percent >= 0 AND avg_humidity_percent <= 100),
    total_precipitation_mm NUMERIC(8, 2) CHECK (total_precipitation_mm >= 0),
    avg_global_radiation_w_m2 NUMERIC(8, 2) CHECK (avg_global_radiation_w_m2 >= 0),
    avg_co2_ppm NUMERIC(7, 2) CHECK (avg_co2_ppm >= 200 AND avg_co2_ppm <= 2000),
    avg_wind_speed_ms NUMERIC(6, 2) CHECK (avg_wind_speed_ms >= 0 AND avg_wind_speed_ms <= 100),
    dominant_wind_direction_deg NUMERIC(5, 2) CHECK (dominant_wind_direction_deg >= 0 AND dominant_wind_direction_deg < 360),
    avg_soil_moisture_percent NUMERIC(5, 2) CHECK (avg_soil_moisture_percent >= 0 AND avg_soil_moisture_percent <= 100),
    avg_soil_temperature_c NUMERIC(6, 2) CHECK (avg_soil_temperature_c >= -20 AND avg_soil_temperature_c <= 40),
    soil_ph NUMERIC(4, 2) CHECK (soil_ph >= 3 AND soil_ph <= 10),
    nutrient_nitrogen_mg_kg NUMERIC(8, 2) CHECK (nutrient_nitrogen_mg_kg >= 0),
    nutrient_phosphorus_mg_kg NUMERIC(8, 2) CHECK (nutrient_phosphorus_mg_kg >= 0),
    nutrient_potassium_mg_kg NUMERIC(8, 2) CHECK (nutrient_potassium_mg_kg >= 0),
    stress_factor NUMERIC(3, 2) CHECK (stress_factor >= 0 AND stress_factor <= 1),
    Description TEXT,
    research_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    CONSTRAINT chk_date_range CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

COMMENT ON TABLE environments.Environments IS 'Environmental condition variants derived from sensors, models, or user input';
COMMENT ON COLUMN environments.Environments.environment_id IS 'Unique identifier for this environment record';
COMMENT ON COLUMN environments.Environments.parent_environment_id IS 'Parent environment for tracking environmental modifications';
COMMENT ON COLUMN environments.Environments.start_date IS 'Start of environmental measurement period';
COMMENT ON COLUMN environments.Environments.end_date IS 'End of environmental measurement period (NULL for ongoing)';
COMMENT ON COLUMN environments.Environments.avg_global_radiation_w_m2 IS 'Average global radiation in W/m²';
COMMENT ON COLUMN environments.Environments.stress_factor IS 'Environmental stress index (0=optimal, 1=severe stress)';

-- Create indexes
CREATE INDEX idx_environments_parent ON environments.Environments(parent_environment_id);
CREATE INDEX idx_environments_location ON environments.Environments(location_id);
CREATE INDEX idx_environments_scenario ON environments.Environments(scenario_id);
CREATE INDEX idx_environments_variant_type ON environments.Environments(variant_type_id);
CREATE INDEX idx_environments_process ON environments.Environments(process_id);
CREATE INDEX idx_environments_start_date ON environments.Environments(start_date DESC);
CREATE INDEX idx_environments_end_date ON environments.Environments(end_date DESC NULLS LAST);
CREATE INDEX idx_environments_created_at ON environments.Environments(created_at DESC);
CREATE INDEX idx_environments_created_by ON environments.Environments(created_by);

-- =============================================================================
-- JUNCTION TABLE: PROCESS PARAMETERS FOR ENVIRONMENTS
-- =============================================================================

CREATE TABLE shared.ProcessParameters_Environments (
    process_parameter_id INTEGER NOT NULL REFERENCES shared.ProcessParameters(process_parameter_id) ON DELETE CASCADE,
    environment_id INTEGER NOT NULL REFERENCES environments.Environments(environment_id) ON DELETE CASCADE,
    PRIMARY KEY (process_parameter_id, environment_id)
);

COMMENT ON TABLE shared.ProcessParameters_Environments IS 'Links process parameters to environment records';

CREATE INDEX idx_pp_environments_parameter ON shared.ProcessParameters_Environments(process_parameter_id);
CREATE INDEX idx_pp_environments_environment ON shared.ProcessParameters_Environments(environment_id);

-- =============================================================================
-- JUNCTION TABLE: AUDIT LOG FOR ENVIRONMENTS
-- =============================================================================

CREATE TABLE shared.AuditLog_Environments (
    audit_id BIGINT NOT NULL REFERENCES shared.AuditLog(audit_id) ON DELETE CASCADE,
    environment_id INTEGER NOT NULL REFERENCES environments.Environments(environment_id) ON DELETE CASCADE,
    PRIMARY KEY (audit_id, environment_id)
);

COMMENT ON TABLE shared.AuditLog_Environments IS 'Links audit log entries to environment records';

CREATE INDEX idx_audit_environments_audit ON shared.AuditLog_Environments(audit_id);
CREATE INDEX idx_audit_environments_environment ON shared.AuditLog_Environments(environment_id);

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
        location_id,
        variant_type_id,
        process_id,
        variant_name,
        start_date,
        end_date,
        avg_temperature_c,
        avg_humidity_percent,
        total_precipitation_mm,
        avg_co2_ppm,
        avg_wind_speed_ms,
        avg_soil_moisture_percent,
        avg_soil_temperature_c
    )
    SELECT
        location_id_param,
        (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'sensor_derived'),
        (SELECT process_id FROM shared.Processes WHERE process_name = 'Sensor_Data_Aggregation' LIMIT 1),
        calculated_variant_name,
        start_time,
        end_time,
        AVG(CASE WHEN st.sensor_type_name = 'Temperature' THEN sr.Value END) AS avg_temperature_c,
        AVG(CASE WHEN st.sensor_type_name = 'Humidity' THEN sr.Value END) AS avg_humidity_percent,
        SUM(CASE WHEN st.sensor_type_name = 'Precipitation' THEN sr.Value END) AS total_precipitation_mm,
        AVG(CASE WHEN st.sensor_type_name = 'CO2' THEN sr.Value END) AS avg_co2_ppm,
        AVG(CASE WHEN st.sensor_type_name = 'Wind_Speed' THEN sr.Value END) AS avg_wind_speed_ms,
        AVG(CASE WHEN st.sensor_type_name = 'Soil_Moisture' THEN sr.Value END) AS avg_soil_moisture_percent,
        AVG(CASE WHEN st.sensor_type_name = 'Soil_Temperature' THEN sr.Value END) AS avg_soil_temperature_c
    FROM sensor.SensorReadings sr
    JOIN sensor.Sensors s ON sr.sensor_id = s.sensor_id
    JOIN sensor.SensorTypes st ON s.sensor_type_id = st.sensor_type_id
    WHERE s.location_id = location_id_param
        AND sr.Timestamp >= start_time
        AND sr.Timestamp <= end_time
        AND sr.Quality IN ('good', 'suspect')
    HAVING COUNT(*) > 0
    RETURNING environment_id INTO new_variant_id;

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
    NEW.updated_at = NOW();
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
    environments.calculate_duration_days(e.start_date, e.end_date) AS duration_days,
    environments.is_active(e.start_date, e.end_date) AS is_active,
    l.location_name,
    s.scenario_name,
    vt.variant_type_name
FROM environments.Environments e
LEFT JOIN shared.Locations l ON e.location_id = l.location_id
LEFT JOIN shared.Scenarios s ON e.scenario_id = s.scenario_id
LEFT JOIN shared.VariantTypes vt ON e.variant_type_id = vt.variant_type_id
WHERE environments.is_active(e.start_date, e.end_date) = TRUE;

COMMENT ON VIEW environments.active_environments IS 'Currently active environment variants with location and scenario context';

-- View: Environment summary statistics by location
CREATE OR REPLACE VIEW environments.location_environment_summary AS
SELECT
    l.location_id,
    l.location_name,
    COUNT(e.environment_id) AS environment_count,
    AVG(e.avg_temperature_c) AS avg_temperature,
    AVG(e.avg_humidity_percent) AS avg_humidity,
    AVG(e.avg_co2_ppm) AS avg_co2,
    AVG(e.stress_factor) AS avg_stress_factor,
    MIN(e.start_date) AS earliest_measurement,
    MAX(e.end_date) AS latest_measurement
FROM shared.Locations l
LEFT JOIN environments.Environments e ON l.location_id = e.location_id
GROUP BY l.location_id, l.location_name;

COMMENT ON VIEW environments.location_environment_summary IS 'Summary statistics of environmental conditions by location';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA environments TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA environments TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA environments TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA environments TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA environments TO anon, authenticated, service_role;
