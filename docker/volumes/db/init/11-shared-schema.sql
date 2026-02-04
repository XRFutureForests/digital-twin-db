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
    LocationName VARCHAR(200) NOT NULL UNIQUE,
    Boundary extensions.GEOMETRY(Polygon, 4326),
    CenterPoint extensions.GEOMETRY(Point, 4326),
    Description TEXT,
    Elevation_m NUMERIC(8, 2),
    Slope_deg NUMERIC(5, 2) CHECK (Slope_deg >= 0 AND Slope_deg <= 90),
    Aspect VARCHAR(3) CHECK (Aspect IN ('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')),
    SoilTypeID INTEGER REFERENCES shared.SoilTypes(SoilTypeID),
    ClimateZoneID INTEGER REFERENCES shared.ClimateZones(ClimateZoneID),
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200)
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
    -- Growth characteristics as proper columns
    MaxHeight_m NUMERIC(6, 2),
    MaxDBH_cm NUMERIC(6, 2),
    TypicalLifespan_years INTEGER,
    GrowthRate VARCHAR(20) CHECK (GrowthRate IN ('very_slow', 'slow', 'moderate', 'fast', 'very_fast')),
    ShadeTolerance VARCHAR(20) CHECK (ShadeTolerance IN ('very_low', 'low', 'moderate', 'high', 'very_high')),
    IsDeciduous BOOLEAN,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ
);

COMMENT ON TABLE shared.Species IS 'Tree species reference with growth characteristics';
COMMENT ON COLUMN shared.Species.MaxHeight_m IS 'Maximum typical height in meters';
COMMENT ON COLUMN shared.Species.MaxDBH_cm IS 'Maximum typical diameter at breast height in centimeters';
COMMENT ON COLUMN shared.Species.TypicalLifespan_years IS 'Typical lifespan in years';
COMMENT ON COLUMN shared.Species.GrowthRate IS 'Relative growth rate (very_slow, slow, moderate, fast, very_fast)';
COMMENT ON COLUMN shared.Species.ShadeTolerance IS 'Shade tolerance level (very_low, low, moderate, high, very_high)';
COMMENT ON COLUMN shared.Species.IsDeciduous IS 'Whether species is deciduous (true) or evergreen (false), NULL if unknown';

CREATE INDEX idx_species_scientific_name ON shared.Species(ScientificName);
CREATE INDEX idx_species_common_name ON shared.Species(CommonName);
CREATE INDEX idx_species_growth_rate ON shared.Species(GrowthRate);
CREATE INDEX idx_species_shade_tolerance ON shared.Species(ShadeTolerance);

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
        'original', 'processed', 'manual', 'simulated_growth', 'user_input', 'sensor_derived', 'model_output', 'repeat_measurement'
    ))
);

COMMENT ON TABLE shared.VariantTypes IS 'Types of data variants (original, processed, simulated, etc.)';

CREATE INDEX idx_variant_types_name ON shared.VariantTypes(VariantTypeName);

-- =============================================================================
-- CAMPAIGNS (INVENTORY EVENTS AND DATA COLLECTION)
-- =============================================================================

CREATE TABLE shared.Campaigns (
    CampaignID SERIAL PRIMARY KEY,
    CampaignName VARCHAR(200) NOT NULL UNIQUE,
    CampaignType VARCHAR(50) NOT NULL CHECK (CampaignType IN (
        'lidar_flight', 'field_inventory', 'sensor_deployment', 'drone_survey', 'manual_update'
    )),
    LocationID INTEGER REFERENCES shared.Locations(LocationID) ON DELETE SET NULL,
    StartDate DATE NOT NULL,
    EndDate DATE,
    Description TEXT,
    Methodology TEXT,
    Equipment TEXT,
    Personnel TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    CONSTRAINT chk_campaign_dates CHECK (EndDate IS NULL OR EndDate >= StartDate)
);

COMMENT ON TABLE shared.Campaigns IS 'Data collection campaigns (LiDAR flights, field inventories, sensor deployments)';
COMMENT ON COLUMN shared.Campaigns.CampaignType IS 'Type of data collection campaign';
COMMENT ON COLUMN shared.Campaigns.Methodology IS 'Description of data collection methodology used';
COMMENT ON COLUMN shared.Campaigns.Equipment IS 'Equipment used (e.g., scanner model, measurement tools)';

CREATE INDEX idx_campaigns_name ON shared.Campaigns(CampaignName);
CREATE INDEX idx_campaigns_type ON shared.Campaigns(CampaignType);
CREATE INDEX idx_campaigns_location ON shared.Campaigns(LocationID);
CREATE INDEX idx_campaigns_start_date ON shared.Campaigns(StartDate DESC);

-- =============================================================================
-- PLOTS (SUB-DIVISIONS WITHIN LOCATIONS)
-- =============================================================================

CREATE TABLE shared.Plots (
    PlotID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotName VARCHAR(200) NOT NULL,
    PlotNumber INTEGER,
    Area_m2 NUMERIC(12, 2) CHECK (Area_m2 > 0),
    Boundary extensions.GEOMETRY(Polygon, 4326),
    CenterPoint extensions.GEOMETRY(Point, 4326),
    Description TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    UNIQUE (LocationID, PlotName)
);

COMMENT ON TABLE shared.Plots IS 'Sub-plot divisions within locations for detailed research grids';
COMMENT ON COLUMN shared.Plots.PlotName IS 'Plot identifier, unique within a location';
COMMENT ON COLUMN shared.Plots.PlotNumber IS 'Numeric plot identifier for ordering';
COMMENT ON COLUMN shared.Plots.Area_m2 IS 'Plot area in square meters';
COMMENT ON COLUMN shared.Plots.Boundary IS 'PostGIS polygon defining plot boundaries in WGS84';

CREATE INDEX idx_plots_location ON shared.Plots(LocationID);
CREATE INDEX idx_plots_boundary ON shared.Plots USING GIST (Boundary);
CREATE INDEX idx_plots_centerpoint ON shared.Plots USING GIST (CenterPoint);

-- =============================================================================
-- MANAGEMENT EVENTS (FOREST MANAGEMENT ACTIVITIES)
-- =============================================================================

CREATE TABLE shared.ManagementEvents (
    EventID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotID INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL,
    EventType VARCHAR(50) NOT NULL CHECK (EventType IN (
        'thinning', 'planting', 'harvesting', 'pruning', 'fertilization',
        'prescribed_burn', 'salvage_logging', 'site_preparation', 'other'
    )),
    EventDate DATE NOT NULL,
    EndDate DATE,
    Description TEXT,
    AffectedArea_m2 NUMERIC(12, 2) CHECK (AffectedArea_m2 > 0),
    PerformedBy VARCHAR(200),
    Notes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    CONSTRAINT chk_mgmt_event_dates CHECK (EndDate IS NULL OR EndDate >= EventDate)
);

COMMENT ON TABLE shared.ManagementEvents IS 'Forest management activities (thinning, planting, harvesting, etc.)';
COMMENT ON COLUMN shared.ManagementEvents.EventType IS 'Type of management activity';
COMMENT ON COLUMN shared.ManagementEvents.AffectedArea_m2 IS 'Area affected by the management activity in m²';

CREATE INDEX idx_mgmt_events_location ON shared.ManagementEvents(LocationID);
CREATE INDEX idx_mgmt_events_plot ON shared.ManagementEvents(PlotID);
CREATE INDEX idx_mgmt_events_type ON shared.ManagementEvents(EventType);
CREATE INDEX idx_mgmt_events_date ON shared.ManagementEvents(EventDate DESC);

-- =============================================================================
-- DISTURBANCE EVENTS (NATURAL DISTURBANCES)
-- =============================================================================

CREATE TABLE shared.DisturbanceEvents (
    EventID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotID INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL,
    DisturbanceType VARCHAR(50) NOT NULL CHECK (DisturbanceType IN (
        'storm', 'fire', 'insect', 'drought', 'disease', 'flood',
        'frost', 'snow_damage', 'landslide', 'other'
    )),
    EventDate DATE NOT NULL,
    EndDate DATE,
    Severity VARCHAR(20) CHECK (Severity IN ('low', 'moderate', 'high', 'severe')),
    AffectedArea_m2 NUMERIC(12, 2) CHECK (AffectedArea_m2 > 0),
    Description TEXT,
    Notes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    CONSTRAINT chk_dist_event_dates CHECK (EndDate IS NULL OR EndDate >= EventDate)
);

COMMENT ON TABLE shared.DisturbanceEvents IS 'Natural disturbance events affecting forest areas (storms, fire, insects, etc.)';
COMMENT ON COLUMN shared.DisturbanceEvents.DisturbanceType IS 'Type of natural disturbance';
COMMENT ON COLUMN shared.DisturbanceEvents.Severity IS 'Disturbance severity level';
COMMENT ON COLUMN shared.DisturbanceEvents.AffectedArea_m2 IS 'Estimated area affected in m²';

CREATE INDEX idx_dist_events_location ON shared.DisturbanceEvents(LocationID);
CREATE INDEX idx_dist_events_plot ON shared.DisturbanceEvents(PlotID);
CREATE INDEX idx_dist_events_type ON shared.DisturbanceEvents(DisturbanceType);
CREATE INDEX idx_dist_events_date ON shared.DisturbanceEvents(EventDate DESC);
CREATE INDEX idx_dist_events_severity ON shared.DisturbanceEvents(Severity);

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
-- NOTE: Lookup data (SoilTypes, ClimateZones, VariantTypes, Scenarios, Species)
-- is now loaded from CSV files in data/lookups/ by 30-load-lookup-tables.sql
-- =============================================================================

-- Grant appropriate permissions (to be customized based on RLS policies)
GRANT USAGE ON SCHEMA shared TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA shared TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA shared TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA shared TO authenticated, service_role;
