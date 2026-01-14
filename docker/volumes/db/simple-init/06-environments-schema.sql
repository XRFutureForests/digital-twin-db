-- =============================================================================
-- 06: ENVIRONMENTS SCHEMA
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- Environmental condition variants
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS environments;
SET search_path TO environments, shared, sensor, public, extensions;

-- =============================================================================
-- ENVIRONMENTS TABLE
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
    AvgWindSpeed_ms NUMERIC(6, 2) CHECK (AvgWindSpeed_ms >= 0),
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

COMMENT ON TABLE environments.Environments IS 'Environmental condition variants';

CREATE INDEX idx_environments_location ON environments.Environments(LocationID);
CREATE INDEX idx_environments_start_date ON environments.Environments(StartDate DESC);
CREATE INDEX idx_environments_created_at ON environments.Environments(CreatedAt DESC);

-- =============================================================================
-- JUNCTION TABLES
-- =============================================================================

CREATE TABLE shared.ProcessParameters_Environments (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES environments.Environments(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, VariantID)
);

CREATE TABLE shared.AuditLog_Environments (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES environments.Environments(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, VariantID)
);

-- =============================================================================
-- TRIGGERS
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

DO $$
BEGIN
    RAISE NOTICE '✅ Environments schema created';
END
$$;
