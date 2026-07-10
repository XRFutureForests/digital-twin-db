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
    soil_type_id SERIAL PRIMARY KEY,
    soil_type_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_soil_type_name CHECK (soil_type_name IN (
        'Alfisol', 'Andisol', 'Aridisol', 'Entisol', 'Gelisol',
        'Histosol', 'Inceptisol', 'Mollisol', 'Oxisol', 'Spodosol',
        'Ultisol', 'Vertisol'
    ))
);

COMMENT ON TABLE shared.SoilTypes IS 'USDA soil classification reference table';
COMMENT ON COLUMN shared.SoilTypes.soil_type_name IS 'USDA soil classification type';

-- Climate Zones Reference Table
CREATE TABLE shared.ClimateZones (
    climate_zone_id SERIAL PRIMARY KEY,
    climate_zone_name VARCHAR(10) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_climate_zone_format CHECK (climate_zone_name ~ '^[A-Z][A-Za-z]{0,3}$')
);

COMMENT ON TABLE shared.ClimateZones IS 'Köppen climate classification zones';
COMMENT ON COLUMN shared.ClimateZones.climate_zone_name IS 'Köppen climate classification code (e.g., Cfb, Dfb, ET, EF, BWh)';

-- Locations Table
CREATE TABLE shared.Locations (
    location_id SERIAL PRIMARY KEY,
    location_name VARCHAR(200) NOT NULL UNIQUE,
    Boundary extensions.GEOMETRY(Polygon, 4326),
    center_point extensions.GEOMETRY(Point, 4326),
    Description TEXT,
    Elevation_m NUMERIC(8, 2),
    Slope_deg NUMERIC(5, 2) CHECK (Slope_deg >= 0 AND Slope_deg <= 90),
    Aspect VARCHAR(3) CHECK (Aspect IN ('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')),
    soil_type_id INTEGER REFERENCES shared.SoilTypes(soil_type_id),
    climate_zone_id INTEGER REFERENCES shared.ClimateZones(climate_zone_id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200)
);

COMMENT ON TABLE shared.Locations IS 'Forest plot locations with spatial boundaries and environmental context';
COMMENT ON COLUMN shared.Locations.Boundary IS 'PostGIS polygon defining plot boundaries in WGS84';
COMMENT ON COLUMN shared.Locations.center_point IS 'PostGIS point for plot center in WGS84';

-- Create spatial indexes
CREATE INDEX idx_locations_boundary ON shared.Locations USING GIST (Boundary);
CREATE INDEX idx_locations_centerpoint ON shared.Locations USING GIST (center_point);
CREATE INDEX idx_locations_soil_type ON shared.Locations(soil_type_id);
CREATE INDEX idx_locations_climate_zone ON shared.Locations(climate_zone_id);

-- =============================================================================
-- SPECIES REFERENCE TABLE
-- =============================================================================

CREATE TABLE shared.Species (
    species_id SERIAL PRIMARY KEY,
    common_name VARCHAR(200),
    scientific_name VARCHAR(200) NOT NULL UNIQUE,
    -- Growth characteristics as proper columns
    max_height_m NUMERIC(6, 2),
    max_dbh_cm NUMERIC(6, 2),
    typical_lifespan_years INTEGER,
    growth_rate VARCHAR(20) CHECK (growth_rate IN ('very_slow', 'slow', 'moderate', 'fast', 'very_fast')),
    shade_tolerance VARCHAR(20) CHECK (shade_tolerance IN ('very_low', 'low', 'moderate', 'high', 'very_high')),
    is_deciduous BOOLEAN,
    gbif_key INTEGER,
    gbif_accepted_name VARCHAR(200),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

COMMENT ON TABLE shared.Species IS 'Tree species reference with growth characteristics';
COMMENT ON COLUMN shared.Species.max_height_m IS 'Maximum typical height in meters';
COMMENT ON COLUMN shared.Species.max_dbh_cm IS 'Maximum typical diameter at breast height in centimeters';
COMMENT ON COLUMN shared.Species.typical_lifespan_years IS 'Typical lifespan in years';
COMMENT ON COLUMN shared.Species.growth_rate IS 'Relative growth rate (very_slow, slow, moderate, fast, very_fast)';
COMMENT ON COLUMN shared.Species.shade_tolerance IS 'Shade tolerance level (very_low, low, moderate, high, very_high)';
COMMENT ON COLUMN shared.Species.is_deciduous IS 'Whether species is deciduous (true) or evergreen (false), NULL if unknown';

CREATE INDEX idx_species_scientific_name ON shared.Species(scientific_name);
CREATE INDEX idx_species_common_name ON shared.Species(common_name);
CREATE INDEX idx_species_growth_rate ON shared.Species(growth_rate);
CREATE INDEX idx_species_shade_tolerance ON shared.Species(shade_tolerance);

-- =============================================================================
-- SCENARIOS AND VARIANT TYPES
-- =============================================================================

CREATE TABLE shared.Scenarios (
    scenario_id SERIAL PRIMARY KEY,
    scenario_name VARCHAR(200) NOT NULL UNIQUE,
    Description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

COMMENT ON TABLE shared.Scenarios IS 'Simulation scenarios (e.g., Current_Conditions, Climate_Change_2050, Drought_Test)';

CREATE INDEX idx_scenarios_name ON shared.Scenarios(scenario_name);

-- VariantTypes must be created before Variants (Variants.variant_type_id references it)
CREATE TABLE shared.VariantTypes (
    variant_type_id SERIAL PRIMARY KEY,
    variant_type_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_variant_type_name CHECK (variant_type_name IN (
        'original', 'processed', 'manual', 'simulated_growth', 'user_input', 'sensor_derived', 'model_output', 'repeat_measurement'
    ))
);

COMMENT ON TABLE shared.VariantTypes IS 'Types of data variants (original, processed, simulated, etc.)';

CREATE INDEX idx_variant_types_name ON shared.VariantTypes(variant_type_name);

-- =============================================================================
-- VARIANTS (FOREST STATE SNAPSHOTS WITHIN A SCENARIO)
-- =============================================================================

CREATE TABLE shared.Variants (
    variant_id      SERIAL PRIMARY KEY,
    location_id     INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    scenario_id     INTEGER NOT NULL REFERENCES shared.Scenarios(scenario_id) ON DELETE CASCADE,
    variant_type_id  INTEGER NOT NULL REFERENCES shared.VariantTypes(variant_type_id),
    variant_name    VARCHAR(200) NOT NULL,
    simulation_year INTEGER CHECK (simulation_year >= 1900 AND simulation_year <= 2300),
    time_delta_yrs  NUMERIC(8, 2) CHECK (time_delta_yrs >= 0),
    sort_order      INTEGER NOT NULL DEFAULT 0,
    Description    TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (location_id, scenario_id, variant_name)
);

COMMENT ON TABLE shared.Variants IS 'Forest state snapshots — each row is one time step at one location within one scenario. variant_id groups all trees at that state. Use for UE time-travel switching.';
COMMENT ON COLUMN shared.Variants.location_id IS 'The forest site this variant belongs to — top level of the Location → Scenario → Variant hierarchy';
COMMENT ON COLUMN shared.Variants.scenario_id IS 'The scenario (set of assumptions) this variant belongs to';
COMMENT ON COLUMN shared.Variants.variant_type_id IS 'Type of data in this variant (original field measurement, simulated growth, etc.)';
COMMENT ON COLUMN shared.Variants.simulation_year IS 'Calendar year this forest state represents';
COMMENT ON COLUMN shared.Variants.time_delta_yrs IS 'Years elapsed from the scenario baseline';
COMMENT ON COLUMN shared.Variants.sort_order IS 'Display order for time-slider UI in UE (0=earliest)';

CREATE INDEX idx_variants_location ON shared.Variants(location_id);
CREATE INDEX idx_variants_scenario ON shared.Variants(scenario_id);
CREATE INDEX idx_variants_type ON shared.Variants(variant_type_id);
CREATE INDEX idx_variants_location_scenario ON shared.Variants(location_id, scenario_id);
CREATE INDEX idx_variants_sort ON shared.Variants(location_id, scenario_id, sort_order);

GRANT SELECT ON shared.Variants TO anon, authenticated;
GRANT ALL ON shared.Variants TO service_role;
GRANT USAGE, SELECT ON SEQUENCE shared.variants_variant_id_seq TO authenticated, service_role;

-- =============================================================================
-- CAMPAIGNS (INVENTORY EVENTS AND DATA COLLECTION)
-- =============================================================================

CREATE TABLE shared.Campaigns (
    campaign_id SERIAL PRIMARY KEY,
    campaign_name VARCHAR(200) NOT NULL UNIQUE,
    campaign_type VARCHAR(50) NOT NULL CHECK (campaign_type IN (
        'lidar_flight', 'field_inventory', 'sensor_deployment', 'drone_survey', 'manual_update'
    )),
    location_id INTEGER REFERENCES shared.Locations(location_id) ON DELETE SET NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    Description TEXT,
    Methodology TEXT,
    Equipment TEXT,
    Personnel TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    CONSTRAINT chk_campaign_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

COMMENT ON TABLE shared.Campaigns IS 'Data collection campaigns (LiDAR flights, field inventories, sensor deployments)';
COMMENT ON COLUMN shared.Campaigns.campaign_type IS 'Type of data collection campaign';
COMMENT ON COLUMN shared.Campaigns.Methodology IS 'Description of data collection methodology used';
COMMENT ON COLUMN shared.Campaigns.Equipment IS 'Equipment used (e.g., scanner model, measurement tools)';

CREATE INDEX idx_campaigns_name ON shared.Campaigns(campaign_name);
CREATE INDEX idx_campaigns_type ON shared.Campaigns(campaign_type);
CREATE INDEX idx_campaigns_location ON shared.Campaigns(location_id);
CREATE INDEX idx_campaigns_start_date ON shared.Campaigns(start_date DESC);

-- =============================================================================
-- PLOTS (SUB-DIVISIONS WITHIN LOCATIONS)
-- =============================================================================

CREATE TABLE shared.Plots (
    plot_id SERIAL PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_name VARCHAR(200) NOT NULL,
    plot_number INTEGER,
    Area_m2 NUMERIC(12, 2) CHECK (Area_m2 > 0),
    Boundary extensions.GEOMETRY(Polygon, 4326),
    center_point extensions.GEOMETRY(Point, 4326),
    Description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    UNIQUE (location_id, plot_name)
);

COMMENT ON TABLE shared.Plots IS 'Sub-plot divisions within locations for detailed research grids';
COMMENT ON COLUMN shared.Plots.plot_name IS 'Plot identifier, unique within a location';
COMMENT ON COLUMN shared.Plots.plot_number IS 'Numeric plot identifier for ordering';
COMMENT ON COLUMN shared.Plots.Area_m2 IS 'Plot area in square meters';
COMMENT ON COLUMN shared.Plots.Boundary IS 'PostGIS polygon defining plot boundaries in WGS84';

CREATE INDEX idx_plots_location ON shared.Plots(location_id);
CREATE INDEX idx_plots_boundary ON shared.Plots USING GIST (Boundary);
CREATE INDEX idx_plots_centerpoint ON shared.Plots USING GIST (center_point);

-- =============================================================================
-- MANAGEMENT EVENTS (FOREST MANAGEMENT ACTIVITIES)
-- =============================================================================

CREATE TABLE shared.ManagementEvents (
    management_event_id SERIAL PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'thinning', 'planting', 'harvesting', 'pruning', 'fertilization',
        'prescribed_burn', 'salvage_logging', 'site_preparation', 'other'
    )),
    event_date DATE NOT NULL,
    end_date DATE,
    Description TEXT,
    affected_area_m2 NUMERIC(12, 2) CHECK (affected_area_m2 > 0),
    performed_by VARCHAR(200),
    Notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    CONSTRAINT chk_mgmt_event_dates CHECK (end_date IS NULL OR end_date >= event_date)
);

COMMENT ON TABLE shared.ManagementEvents IS 'Forest management activities (thinning, planting, harvesting, etc.)';
COMMENT ON COLUMN shared.ManagementEvents.event_type IS 'Type of management activity';
COMMENT ON COLUMN shared.ManagementEvents.affected_area_m2 IS 'Area affected by the management activity in m²';

CREATE INDEX idx_mgmt_events_location ON shared.ManagementEvents(location_id);
CREATE INDEX idx_mgmt_events_plot ON shared.ManagementEvents(plot_id);
CREATE INDEX idx_mgmt_events_type ON shared.ManagementEvents(event_type);
CREATE INDEX idx_mgmt_events_date ON shared.ManagementEvents(event_date DESC);

-- =============================================================================
-- DISTURBANCE EVENTS (NATURAL DISTURBANCES)
-- =============================================================================

CREATE TABLE shared.DisturbanceEvents (
    disturbance_event_id SERIAL PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    disturbance_type VARCHAR(50) NOT NULL CHECK (disturbance_type IN (
        'storm', 'fire', 'insect', 'drought', 'disease', 'flood',
        'frost', 'snow_damage', 'landslide', 'other'
    )),
    event_date DATE NOT NULL,
    end_date DATE,
    Severity VARCHAR(20) CHECK (Severity IN ('low', 'moderate', 'high', 'severe')),
    affected_area_m2 NUMERIC(12, 2) CHECK (affected_area_m2 > 0),
    Description TEXT,
    Notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    CONSTRAINT chk_dist_event_dates CHECK (end_date IS NULL OR end_date >= event_date)
);

COMMENT ON TABLE shared.DisturbanceEvents IS 'Natural disturbance events affecting forest areas (storms, fire, insects, etc.)';
COMMENT ON COLUMN shared.DisturbanceEvents.disturbance_type IS 'Type of natural disturbance';
COMMENT ON COLUMN shared.DisturbanceEvents.Severity IS 'Disturbance severity level';
COMMENT ON COLUMN shared.DisturbanceEvents.affected_area_m2 IS 'Estimated area affected in m²';

CREATE INDEX idx_dist_events_location ON shared.DisturbanceEvents(location_id);
CREATE INDEX idx_dist_events_plot ON shared.DisturbanceEvents(plot_id);
CREATE INDEX idx_dist_events_type ON shared.DisturbanceEvents(disturbance_type);
CREATE INDEX idx_dist_events_date ON shared.DisturbanceEvents(event_date DESC);
CREATE INDEX idx_dist_events_severity ON shared.DisturbanceEvents(Severity);

-- =============================================================================
-- PROCESS MANAGEMENT AND ALGORITHM TRACKING
-- =============================================================================

CREATE TABLE shared.Processes (
    process_id SERIAL PRIMARY KEY,
    process_name VARCHAR(200) NOT NULL,
    algorithm_name VARCHAR(200),
    Version VARCHAR(50),
    Description TEXT,
    Author VARCHAR(200),
    publication_date DATE,
    Citation TEXT,
    Category VARCHAR(100) CHECK (Category IN ('detection', 'classification', 'simulation', 'analysis', 'aggregation')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (process_name, Version)
);

COMMENT ON TABLE shared.Processes IS 'Processing algorithms and methods with versioning and academic attribution';
COMMENT ON COLUMN shared.Processes.process_name IS 'Process name (e.g., LiDAR_Segmentation, Tree_Detection, Growth_Simulation)';
COMMENT ON COLUMN shared.Processes.algorithm_name IS 'Algorithm used (e.g., RandomForest, DeepLearning, RulesBased)';

CREATE INDEX idx_processes_name ON shared.Processes(process_name);
CREATE INDEX idx_processes_category ON shared.Processes(Category);

CREATE TABLE shared.ProcessParameters (
    process_parameter_id SERIAL PRIMARY KEY,
    parameter_name VARCHAR(200) NOT NULL,
    parameter_value TEXT NOT NULL,
    data_type VARCHAR(50) CHECK (data_type IN ('float', 'int', 'string', 'boolean', 'json')),
    Description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE shared.ProcessParameters IS 'Process parameters used for variants (linked via junction tables)';
COMMENT ON COLUMN shared.ProcessParameters.parameter_value IS 'Parameter value as text (cast based on data_type)';

CREATE INDEX idx_process_parameters_name ON shared.ProcessParameters(parameter_name);

CREATE TABLE shared.ProcessMetrics (
    process_metric_id SERIAL PRIMARY KEY,
    process_id INTEGER NOT NULL REFERENCES shared.Processes(process_id) ON DELETE CASCADE,
    metric_name VARCHAR(200) NOT NULL,
    metric_value NUMERIC(10, 6),
    Source TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_metric_name CHECK (metric_name IN ('accuracy', 'precision', 'recall', 'f1_score', 'rmse', 'mae', 'r_squared'))
);

COMMENT ON TABLE shared.ProcessMetrics IS 'Published performance metrics for processes';

CREATE INDEX idx_process_metrics_process_id ON shared.ProcessMetrics(process_id);
CREATE INDEX idx_process_metrics_name ON shared.ProcessMetrics(metric_name);

-- =============================================================================
-- FIELD-LEVEL CHANGE TRACKING (AUDIT LOG)
-- =============================================================================

CREATE TABLE shared.AuditLog (
    audit_id BIGSERIAL PRIMARY KEY,
    field_name VARCHAR(200) NOT NULL,
    old_value TEXT,
    new_value TEXT,
    change_reason TEXT,
    user_id VARCHAR(200),
    Timestamp TIMESTAMPTZ DEFAULT NOW(),
    change_type VARCHAR(50) CHECK (change_type IN ('field_update', 'bulk_update', 'revert', 'insert', 'delete')),
    ip_address INET,
    user_agent TEXT
);

COMMENT ON TABLE shared.AuditLog IS 'Field-level change tracking with user attribution (linked via junction tables)';
COMMENT ON COLUMN shared.AuditLog.field_name IS 'Name of the field that was changed';
COMMENT ON COLUMN shared.AuditLog.old_value IS 'Previous value (stored as JSON text)';
COMMENT ON COLUMN shared.AuditLog.new_value IS 'New value (stored as JSON text)';

CREATE INDEX idx_audit_log_timestamp ON shared.AuditLog(Timestamp DESC);
CREATE INDEX idx_audit_log_user_id ON shared.AuditLog(user_id);
CREATE INDEX idx_audit_log_field_name ON shared.AuditLog(field_name);
CREATE INDEX idx_audit_log_change_type ON shared.AuditLog(change_type);

-- =============================================================================
-- NOTE: Lookup data (SoilTypes, ClimateZones, VariantTypes, Scenarios, Species)
-- is now loaded from CSV files in data/lookups/ by 30-load-lookup-tables.sql
-- =============================================================================

-- Grant appropriate permissions (to be customized based on RLS policies)
GRANT USAGE ON SCHEMA shared TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA shared TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA shared TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA shared TO authenticated, service_role;
