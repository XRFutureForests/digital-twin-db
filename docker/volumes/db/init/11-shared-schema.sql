-- XR Future Forests Lab - Shared Schema Migration
-- This migration creates the shared schema with reference tables used across all domains
-- Dependencies: PostgreSQL with PostGIS extension

-- Enable required extensions
-- Note: These extensions are already available in the Supabase postgres image
-- CREATE EXTENSION IF NOT EXISTS postgis;
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create shared schema
CREATE SCHEMA IF NOT EXISTS shared;

-- Set search path
SET search_path TO shared, public;

-- =============================================================================
-- LOCATION AND ENVIRONMENTAL CONTEXT TABLES
-- =============================================================================

-- Soil Types Reference Table
CREATE TABLE shared.SoilTypes (
    SoilTypeID SERIAL PRIMARY KEY,
    SoilTypeName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_soil_type_name CHECK (SoilTypeName IN (
        'Alfisol', 'Andisol', 'Aridisol', 'Entisol', 'Gelisol',
        'Histosol', 'Inceptisol', 'Mollisol', 'Oxisol', 'Spodosol',
        'Ultisol', 'Vertisol'
    ))
);

COMMENT ON TABLE shared.SoilTypes IS 'USDA soil classification reference table';
COMMENT ON COLUMN shared.SoilTypes.SoilTypeName IS 'USDA soil classification type';

-- Climate Zones Reference Table
CREATE TABLE shared.ClimateZones (
    ClimateZoneID SERIAL PRIMARY KEY,
    ClimateZoneName VARCHAR(10) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_climate_zone_format CHECK (ClimateZoneName ~ '^[A-Z][A-Za-z]{0,3}$')
);

COMMENT ON TABLE shared.ClimateZones IS 'Köppen climate classification zones';
COMMENT ON COLUMN shared.ClimateZones.ClimateZoneName IS 'Köppen climate classification code (e.g., Cfb, Dfb, ET, EF, BWh)';

-- Locations Table
CREATE TABLE shared.Locations (
    LocationID SERIAL PRIMARY KEY,
    LocationName VARCHAR(200) NOT NULL,
    Boundary extensions.GEOMETRY(Polygon, 4326),
    CenterPoint extensions.GEOMETRY(Point, 4326),
    Description TEXT,
    Elevation_m NUMERIC(8, 2),
    Slope_deg NUMERIC(5, 2) CHECK (Slope_deg >= 0 AND Slope_deg <= 90),
    Aspect VARCHAR(3) CHECK (Aspect IN ('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')),
    SoilTypeID INTEGER REFERENCES shared.SoilTypes(SoilTypeID),
    ClimateZoneID INTEGER REFERENCES shared.ClimateZones(ClimateZoneID),
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ
);

COMMENT ON TABLE shared.Locations IS 'Forest plot locations with spatial boundaries and environmental context';
COMMENT ON COLUMN shared.Locations.Boundary IS 'PostGIS polygon defining plot boundaries in WGS84';
COMMENT ON COLUMN shared.Locations.CenterPoint IS 'PostGIS point for plot center in WGS84';

-- Create spatial indexes
CREATE INDEX idx_locations_boundary ON shared.Locations USING GIST (Boundary);
CREATE INDEX idx_locations_centerpoint ON shared.Locations USING GIST (CenterPoint);
CREATE INDEX idx_locations_soil_type ON shared.Locations(SoilTypeID);
CREATE INDEX idx_locations_climate_zone ON shared.Locations(ClimateZoneID);

-- =============================================================================
-- SPECIES REFERENCE TABLE
-- =============================================================================

CREATE TABLE shared.Species (
    SpeciesID SERIAL PRIMARY KEY,
    CommonName VARCHAR(200),
    ScientificName VARCHAR(200) NOT NULL UNIQUE,
    GrowthCharacteristics JSONB,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ
);

COMMENT ON TABLE shared.Species IS 'Tree species reference with growth characteristics';
COMMENT ON COLUMN shared.Species.GrowthCharacteristics IS 'JSON object containing typical growth patterns, max height, lifespan, etc.';

CREATE INDEX idx_species_scientific_name ON shared.Species(ScientificName);
CREATE INDEX idx_species_common_name ON shared.Species(CommonName);
CREATE INDEX idx_species_growth_characteristics ON shared.Species USING GIN (GrowthCharacteristics);

-- =============================================================================
-- SCENARIOS AND VARIANT TYPES
-- =============================================================================

CREATE TABLE shared.Scenarios (
    ScenarioID SERIAL PRIMARY KEY,
    ScenarioName VARCHAR(200) NOT NULL UNIQUE,
    Description TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ
);

COMMENT ON TABLE shared.Scenarios IS 'Simulation scenarios (e.g., Current_Conditions, Climate_Change_2050, Drought_Test)';

CREATE INDEX idx_scenarios_name ON shared.Scenarios(ScenarioName);

CREATE TABLE shared.VariantTypes (
    VariantTypeID SERIAL PRIMARY KEY,
    VariantTypeName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_variant_type_name CHECK (VariantTypeName IN (
        'original', 'processed', 'manual', 'simulated_growth', 'user_input', 'sensor_derived', 'model_output'
    ))
);

COMMENT ON TABLE shared.VariantTypes IS 'Types of data variants (original, processed, simulated, etc.)';

CREATE INDEX idx_variant_types_name ON shared.VariantTypes(VariantTypeName);

-- =============================================================================
-- PROCESS MANAGEMENT AND ALGORITHM TRACKING
-- =============================================================================

CREATE TABLE shared.Processes (
    ProcessID SERIAL PRIMARY KEY,
    ProcessName VARCHAR(200) NOT NULL,
    AlgorithmName VARCHAR(200),
    Version VARCHAR(50),
    Description TEXT,
    Author VARCHAR(200),
    PublicationDate DATE,
    Citation TEXT,
    Category VARCHAR(100) CHECK (Category IN ('detection', 'classification', 'simulation', 'analysis', 'aggregation')),
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    UNIQUE (ProcessName, Version)
);

COMMENT ON TABLE shared.Processes IS 'Processing algorithms and methods with versioning and academic attribution';
COMMENT ON COLUMN shared.Processes.ProcessName IS 'Process name (e.g., LiDAR_Segmentation, Tree_Detection, Growth_Simulation)';
COMMENT ON COLUMN shared.Processes.AlgorithmName IS 'Algorithm used (e.g., RandomForest, DeepLearning, RulesBased)';

CREATE INDEX idx_processes_name ON shared.Processes(ProcessName);
CREATE INDEX idx_processes_category ON shared.Processes(Category);

CREATE TABLE shared.ProcessParameters (
    ParameterID SERIAL PRIMARY KEY,
    ParameterName VARCHAR(200) NOT NULL,
    ParameterValue TEXT NOT NULL,
    DataType VARCHAR(50) CHECK (DataType IN ('float', 'int', 'string', 'boolean', 'json')),
    Description TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE shared.ProcessParameters IS 'Process parameters used for variants (linked via junction tables)';
COMMENT ON COLUMN shared.ProcessParameters.ParameterValue IS 'Parameter value as text (cast based on DataType)';

CREATE INDEX idx_process_parameters_name ON shared.ProcessParameters(ParameterName);

CREATE TABLE shared.ProcessMetrics (
    MetricID SERIAL PRIMARY KEY,
    ProcessID INTEGER NOT NULL REFERENCES shared.Processes(ProcessID) ON DELETE CASCADE,
    MetricName VARCHAR(200) NOT NULL,
    MetricValue NUMERIC(10, 6),
    Source TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_metric_name CHECK (MetricName IN ('accuracy', 'precision', 'recall', 'f1_score', 'rmse', 'mae', 'r_squared'))
);

COMMENT ON TABLE shared.ProcessMetrics IS 'Published performance metrics for processes';

CREATE INDEX idx_process_metrics_process_id ON shared.ProcessMetrics(ProcessID);
CREATE INDEX idx_process_metrics_name ON shared.ProcessMetrics(MetricName);

-- =============================================================================
-- FIELD-LEVEL CHANGE TRACKING (AUDIT LOG)
-- =============================================================================

CREATE TABLE shared.AuditLog (
    AuditID BIGSERIAL PRIMARY KEY,
    FieldName VARCHAR(200) NOT NULL,
    OldValue TEXT,
    NewValue TEXT,
    ChangeReason TEXT,
    UserID VARCHAR(200),
    Timestamp TIMESTAMPTZ DEFAULT NOW(),
    ChangeType VARCHAR(50) CHECK (ChangeType IN ('field_update', 'bulk_update', 'revert', 'insert', 'delete')),
    IPAddress INET,
    UserAgent TEXT
);

COMMENT ON TABLE shared.AuditLog IS 'Field-level change tracking with user attribution (linked via junction tables)';
COMMENT ON COLUMN shared.AuditLog.FieldName IS 'Name of the field that was changed';
COMMENT ON COLUMN shared.AuditLog.OldValue IS 'Previous value (stored as JSON text)';
COMMENT ON COLUMN shared.AuditLog.NewValue IS 'New value (stored as JSON text)';

CREATE INDEX idx_audit_log_timestamp ON shared.AuditLog(Timestamp DESC);
CREATE INDEX idx_audit_log_user_id ON shared.AuditLog(UserID);
CREATE INDEX idx_audit_log_field_name ON shared.AuditLog(FieldName);
CREATE INDEX idx_audit_log_change_type ON shared.AuditLog(ChangeType);

-- =============================================================================
-- SEED REFERENCE DATA
-- =============================================================================

-- Insert common soil types
INSERT INTO shared.SoilTypes (SoilTypeName, Description) VALUES
    ('Alfisol', 'Moderately leached soils with high native fertility'),
    ('Andisol', 'Soils formed in volcanic ash'),
    ('Aridisol', 'Desert soils with low organic matter'),
    ('Entisol', 'Young soils with little profile development'),
    ('Gelisol', 'Permafrost-affected soils'),
    ('Histosol', 'Organic soils (peat, muck)'),
    ('Inceptisol', 'Young soils with minimal horizon development'),
    ('Mollisol', 'Grassland soils with thick, dark surface layer'),
    ('Oxisol', 'Highly weathered tropical soils'),
    ('Spodosol', 'Acidic forest soils with organic accumulation'),
    ('Ultisol', 'Highly weathered, acidic forest soils'),
    ('Vertisol', 'Clay-rich soils that shrink and swell');

-- Insert common climate zones
INSERT INTO shared.ClimateZones (ClimateZoneName, Description) VALUES
    ('Af', 'Tropical rainforest'),
    ('Am', 'Tropical monsoon'),
    ('Aw', 'Tropical savanna'),
    ('BWh', 'Hot desert'),
    ('BWk', 'Cold desert'),
    ('BSh', 'Hot semi-arid'),
    ('BSk', 'Cold semi-arid'),
    ('Csa', 'Hot-summer Mediterranean'),
    ('Csb', 'Warm-summer Mediterranean'),
    ('Cfa', 'Humid subtropical'),
    ('Cfb', 'Oceanic'),
    ('Cfc', 'Subpolar oceanic'),
    ('Dfa', 'Hot-summer humid continental'),
    ('Dfb', 'Warm-summer humid continental'),
    ('Dfc', 'Subarctic'),
    ('Dfd', 'Extremely cold subarctic'),
    ('ET', 'Tundra'),
    ('EF', 'Ice cap');

-- Insert common variant types
INSERT INTO shared.VariantTypes (VariantTypeName, Description) VALUES
    ('original', 'Original data from field measurements or sensors'),
    ('processed', 'Data processed by automated algorithms'),
    ('manual', 'Manually entered or corrected data'),
    ('simulated_growth', 'Data from growth simulation models'),
    ('user_input', 'User-defined or modified data in XR environment'),
    ('sensor_derived', 'Aggregated or derived from sensor readings'),
    ('model_output', 'Output from external models (SILVA, climate models)');

-- Insert common scenarios
INSERT INTO shared.Scenarios (ScenarioName, Description) VALUES
    ('Current_Conditions', 'Baseline scenario with current environmental conditions'),
    ('Climate_Change_2050', 'Projected conditions for year 2050 based on IPCC scenarios'),
    ('Climate_Change_2100', 'Projected conditions for year 2100 based on IPCC scenarios'),
    ('Drought_Test', 'Extreme drought stress scenario'),
    ('Heat_Wave', 'Extended heat wave scenario'),
    ('Increased_CO2', 'Elevated atmospheric CO2 concentration'),
    ('Management_Thinning', 'Forest management with selective thinning'),
    ('No_Management', 'Natural forest development without intervention');

-- Grant appropriate permissions (to be customized based on RLS policies)
GRANT USAGE ON SCHEMA shared TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA shared TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA shared TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA shared TO authenticated, service_role;
