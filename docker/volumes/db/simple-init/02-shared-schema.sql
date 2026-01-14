-- =============================================================================
-- 02: SHARED SCHEMA
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- Reference tables used across all domains
-- =============================================================================

-- Create shared schema
CREATE SCHEMA IF NOT EXISTS shared;

-- Set search path
SET search_path TO shared, public, extensions;

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

-- Climate Zones Reference Table
CREATE TABLE shared.ClimateZones (
    ClimateZoneID SERIAL PRIMARY KEY,
    ClimateZoneName VARCHAR(10) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_climate_zone_format CHECK (ClimateZoneName ~ '^[A-Z][A-Za-z]{0,3}$')
);

COMMENT ON TABLE shared.ClimateZones IS 'Köppen climate classification zones';

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

-- Create spatial indexes
CREATE INDEX idx_locations_boundary ON shared.Locations USING GIST (Boundary);
CREATE INDEX idx_locations_centerpoint ON shared.Locations USING GIST (CenterPoint);

-- =============================================================================
-- SPECIES REFERENCE TABLE
-- =============================================================================

CREATE TABLE shared.Species (
    SpeciesID SERIAL PRIMARY KEY,
    CommonName VARCHAR(200),
    ScientificName VARCHAR(200) NOT NULL UNIQUE,
    MaxHeight_m NUMERIC(6, 2),
    MaxDBH_cm NUMERIC(6, 2),
    TypicalLifespan_years INTEGER,
    GrowthRate VARCHAR(20) CHECK (GrowthRate IN ('very_slow', 'slow', 'moderate', 'fast', 'very_fast')),
    ShadeTolerance VARCHAR(20) CHECK (ShadeTolerance IN ('very_low', 'low', 'moderate', 'high', 'very_high')),
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ
);

COMMENT ON TABLE shared.Species IS 'Tree species reference with growth characteristics';

CREATE INDEX idx_species_scientific_name ON shared.Species(ScientificName);
CREATE INDEX idx_species_common_name ON shared.Species(CommonName);

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

COMMENT ON TABLE shared.Scenarios IS 'Simulation scenarios';

CREATE TABLE shared.VariantTypes (
    VariantTypeID SERIAL PRIMARY KEY,
    VariantTypeName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_variant_type_name CHECK (VariantTypeName IN (
        'original', 'processed', 'manual', 'simulated_growth', 'user_input', 'sensor_derived', 'model_output'
    ))
);

COMMENT ON TABLE shared.VariantTypes IS 'Types of data variants';

-- =============================================================================
-- PROCESS MANAGEMENT
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

COMMENT ON TABLE shared.Processes IS 'Processing algorithms and methods';

CREATE TABLE shared.ProcessParameters (
    ParameterID SERIAL PRIMARY KEY,
    ParameterName VARCHAR(200) NOT NULL,
    ParameterValue TEXT NOT NULL,
    DataType VARCHAR(50) CHECK (DataType IN ('float', 'int', 'string', 'boolean', 'json')),
    Description TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE shared.ProcessMetrics (
    MetricID SERIAL PRIMARY KEY,
    ProcessID INTEGER NOT NULL REFERENCES shared.Processes(ProcessID) ON DELETE CASCADE,
    MetricName VARCHAR(200) NOT NULL,
    MetricValue NUMERIC(10, 6),
    Source TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- AUDIT LOG
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

COMMENT ON TABLE shared.AuditLog IS 'Field-level change tracking';

CREATE INDEX idx_audit_log_timestamp ON shared.AuditLog(Timestamp DESC);

-- =============================================================================
-- SEED REFERENCE DATA
-- =============================================================================

-- Insert soil types
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

-- Insert climate zones
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

-- Insert variant types
INSERT INTO shared.VariantTypes (VariantTypeName, Description) VALUES
    ('original', 'Original data from field measurements or sensors'),
    ('processed', 'Data processed by automated algorithms'),
    ('manual', 'Manually entered or corrected data'),
    ('simulated_growth', 'Data from growth simulation models'),
    ('user_input', 'User-defined or modified data'),
    ('sensor_derived', 'Aggregated or derived from sensor readings'),
    ('model_output', 'Output from external models');

-- Insert scenarios
INSERT INTO shared.Scenarios (ScenarioName, Description) VALUES
    ('Current_Conditions', 'Baseline scenario with current environmental conditions'),
    ('Climate_Change_2050', 'Projected conditions for year 2050'),
    ('Climate_Change_2100', 'Projected conditions for year 2100'),
    ('Drought_Test', 'Extreme drought stress scenario'),
    ('Heat_Wave', 'Extended heat wave scenario'),
    ('Increased_CO2', 'Elevated atmospheric CO2 concentration'),
    ('Management_Thinning', 'Forest management with selective thinning'),
    ('No_Management', 'Natural forest development without intervention');

-- Insert species
INSERT INTO shared.Species (CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance) VALUES
    ('European Beech', 'Fagus sylvatica', 40, 150, 300, 'moderate', 'high'),
    ('Beech', 'Fagus sylvatica', 40, 150, 300, 'moderate', 'high'),
    ('Pedunculate Oak', 'Quercus robur', 35, 200, 500, 'slow', 'moderate'),
    ('Oak', 'Quercus robur', 35, 200, 500, 'slow', 'moderate'),
    ('Norway Spruce', 'Picea abies', 50, 150, 200, 'fast', 'high'),
    ('Spruce', 'Picea abies', 50, 150, 200, 'fast', 'high'),
    ('Silver Fir', 'Abies alba', 50, 200, 500, 'moderate', 'very_high'),
    ('Scots Pine', 'Pinus sylvestris', 35, 100, 300, 'moderate', 'low'),
    ('Douglas Fir', 'Pseudotsuga menziesii', 60, 180, 500, 'fast', 'moderate')
ON CONFLICT (ScientificName) DO NOTHING;

DO $$
BEGIN
    RAISE NOTICE '✅ Shared schema created with reference data';
END
$$;
