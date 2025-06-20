-- XR Future Forests Lab - Database Initialization
-- Creates the comprehensive database schema for the three specialized databases
-- Based on the detailed design document specifications

\c xr_forests_lab;

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- SHARED REFERENCE TABLES
-- =====================================================

-- Shared Locations table used across all three databases
CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    location_name VARCHAR(200) NOT NULL,
    plot_boundary GEOMETRY(POLYGON, 4326),
    center_point GEOMETRY(POINT, 4326),
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Shared Species table used across databases
CREATE TABLE species (
    id SERIAL PRIMARY KEY,
    common_name VARCHAR(200),
    scientific_name VARCHAR(200) NOT NULL UNIQUE,
    growth_characteristics JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- POINT CLOUD DATABASE SCHEMA
-- =====================================================

-- Point Cloud Reference Tables
CREATE TABLE processing_status_types (
    id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE, -- Raw, Segmented, Classified
    description TEXT
);

CREATE TABLE sensor_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE, -- TLS, UAV_LiDAR, Terrestrial_Camera, etc.
    description TEXT
);

-- Point Cloud Core Tables
CREATE TABLE point_clouds (
    id SERIAL PRIMARY KEY,
    file_path VARCHAR(500) NOT NULL, -- Path/URI to raw point cloud file (.las, .laz)
    scan_date TIMESTAMP NOT NULL,
    location_id INTEGER REFERENCES locations(id),
    sensor_type_id INTEGER REFERENCES sensor_types(id),
    processing_status_type_id INTEGER REFERENCES processing_status_types(id),
    quality_metrics JSONB, -- JSON: density, accuracy, coverage
    last_processed_date TIMESTAMP,
    point_count BIGINT, -- Total number of points in scan
    file_size_mb DECIMAL(10,2), -- File size in megabytes
    scan_bounds GEOMETRY(POLYGON, 4326), -- PostGIS polygon defining scan coverage area
    scanner_model VARCHAR(200), -- Model of LiDAR scanner used
    scan_parameters JSONB, -- JSON: scan settings, resolution, etc.
    created_by VARCHAR(200), -- Operator or automated system
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE processing_jobs (
    id SERIAL PRIMARY KEY,
    job_type VARCHAR(100) NOT NULL, -- segmentation, classification, attribute_extraction, simulation
    input_id INTEGER, -- ID of input data (PointCloudID, SegmentationResultID, etc.)
    status VARCHAR(50) DEFAULT 'queued', -- queued, processing, completed, failed, cancelled
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    priority VARCHAR(20) DEFAULT 'normal', -- low, normal, high
    queue_position INTEGER,
    progress_percent DECIMAL(5,2) DEFAULT 0, -- Processing progress (0-100)
    configuration JSONB, -- JSON: algorithm parameters and settings
    results JSONB, -- JSON: processing results and output references
    error_details TEXT, -- Error information if job failed
    submitted_by VARCHAR(200), -- User or system that submitted job
    estimated_duration_minutes INTEGER, -- Estimated processing time
    actual_duration_minutes INTEGER, -- Actual processing time
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE point_cloud_segmentation_results (
    id SERIAL PRIMARY KEY,
    point_cloud_id INTEGER REFERENCES point_clouds(id),
    process_date TIMESTAMP NOT NULL,
    segmentation_algorithm VARCHAR(200), -- Algorithm used (e.g., TreeLearn, 3D Forest)
    segment_data_ref JSONB, -- JSON: references to tree segments
    metrics JSONB, -- JSON: segmentation quality
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tree_classification_results (
    id SERIAL PRIMARY KEY,
    segmentation_result_id INTEGER REFERENCES point_cloud_segmentation_results(id),
    process_date TIMESTAMP NOT NULL,
    classification_algorithm VARCHAR(200), -- Algorithm used (e.g., ML model)
    model_version VARCHAR(100), -- Version of classification model used
    confidence_threshold DECIMAL(3,2), -- Minimum confidence threshold applied
    classified_trees_data JSONB, -- JSON: tree IDs, species IDs, probabilities, confidence scores
    feature_importance JSONB, -- JSON: importance of different morphological features
    overall_accuracy DECIMAL(3,2), -- Overall classification accuracy score
    uncertain_classifications INTEGER, -- Number of trees with low confidence
    metrics JSONB, -- JSON: classification accuracy, model performance
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- TREE DATABASE SCHEMA
-- =====================================================

-- Tree Reference Tables
CREATE TABLE health_status (
    id SERIAL PRIMARY KEY,
    status VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE phenology_status (
    id SERIAL PRIMARY KEY,
    status VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE data_quality_types (
    id SERIAL PRIMARY KEY,
    quality_type VARCHAR(50) NOT NULL UNIQUE, -- Direct_Measurement, Point_Cloud_Derived, Model_Estimated
    description TEXT
);

CREATE TABLE live_status_types (
    id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE, -- alive, dead, decaying, snag
    description TEXT
);

CREATE TABLE variant_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE, -- Original, Growth_Simulation, Species_Replacement, Manual_Edit, New
    description TEXT
);

CREATE TABLE structure_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE, -- QSM, LSystem, DeepTree, Manual, Procedural
    description TEXT
);

CREATE TABLE microhabitat_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE, -- cavity, dead_branch, epiphyte, bark_feature, root_buttress
    description TEXT
);

CREATE TABLE microhabitat_sizes (
    id SERIAL PRIMARY KEY,
    size_name VARCHAR(50) NOT NULL UNIQUE, -- small, medium, large
    description TEXT
);

CREATE TABLE microhabitat_conditions (
    id SERIAL PRIMARY KEY,
    condition_name VARCHAR(50) NOT NULL UNIQUE, -- active, inactive, developing
    description TEXT
);

CREATE TABLE stem_quality_types (
    id SERIAL PRIMARY KEY,
    quality_name VARCHAR(50) NOT NULL UNIQUE, -- excellent, good, fair, poor
    description TEXT
);

CREATE TABLE stem_defect_types (
    id SERIAL PRIMARY KEY,
    defect_name VARCHAR(100) NOT NULL UNIQUE, -- sweep, crook, fork, rot, damage
    description TEXT
);

CREATE TABLE crown_morphology_types (
    id SERIAL PRIMARY KEY,
    morphology_name VARCHAR(100) NOT NULL UNIQUE, -- symmetrical, asymmetrical, suppressed, dominant
    description TEXT
);

CREATE TABLE root_condition_types (
    id SERIAL PRIMARY KEY,
    condition_name VARCHAR(50) NOT NULL UNIQUE, -- healthy, stressed, damaged, exposed
    description TEXT
);

-- Tree Core Tables
CREATE TABLE scenarios (
    id SERIAL PRIMARY KEY,
    scenario_name VARCHAR(200) NOT NULL,
    created_by_user_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scenario_parameters JSONB
);

CREATE TABLE trees (
    id SERIAL PRIMARY KEY,
    location_id INTEGER REFERENCES locations(id),
    species_id INTEGER REFERENCES species(id),
    initial_capture_date TIMESTAMP,
    initial_height_m DECIMAL(5,2),
    initial_dbh_cm DECIMAL(5,2),
    initial_crown_width_m DECIMAL(5,2),
    initial_volume_m3 DECIMAL(8,3),
    health_status_id INTEGER REFERENCES health_status(id),
    point_cloud_id INTEGER REFERENCES point_clouds(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE environmental_snapshots (
    id SERIAL PRIMARY KEY,
    location_id INTEGER REFERENCES locations(id),
    timestamp TIMESTAMP NOT NULL,
    avg_temperature_c DECIMAL(5,2),
    avg_humidity_percent DECIMAL(5,2),
    total_precipitation_mm DECIMAL(6,2),
    avg_global_radiation DECIMAL(8,2),
    avg_co2_ppm DECIMAL(6,2),
    avg_wind_speed_ms DECIMAL(4,2),
    dominant_wind_direction_deg DECIMAL(5,2),
    obstacle_voxel_grid_ref TEXT,
    other_environmental_factors JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tree_variants (
    id SERIAL PRIMARY KEY,
    tree_id INTEGER REFERENCES trees(id), -- Nullable: NULL if new tree in scenario
    scenario_id INTEGER REFERENCES scenarios(id),
    parent_variant_id INTEGER REFERENCES tree_variants(id), -- Nullable: NULL if original or first variant
    species_id INTEGER REFERENCES species(id),
    variant_timestamp TIMESTAMP NOT NULL,
    height_m DECIMAL(5,2),
    dbh_cm DECIMAL(5,2),
    crown_width_m DECIMAL(5,2),
    crown_base_height_m DECIMAL(5,2), -- Height to lowest live branch
    crown_volume_m3 DECIMAL(8,3), -- 3D crown volume
    crown_density_percent DECIMAL(5,2), -- Foliage density within crown
    volume_m3 DECIMAL(8,3),
    live_status_type_id INTEGER REFERENCES live_status_types(id),
    estimated_age_years DECIMAL(5,1), -- Tree age estimation
    health_status_id INTEGER REFERENCES health_status(id),
    position GEOMETRY(POINT, 4326), -- PostGIS point geometry (plot coordinates)
    absolute_position GEOMETRY(POINT, 4326), -- PostGIS point geometry (GPS coordinates)
    local_density_trees_per_ha DECIMAL(8,2), -- Tree density in immediate vicinity
    nearest_neighbor_distance_m DECIMAL(6,2), -- Distance to nearest tree
    variant_type_id INTEGER REFERENCES variant_types(id),
    time_delta_yrs DECIMAL(5,2), -- Time passed since parent state (years) - for growth simulations
    model_type VARCHAR(200), -- For growth simulations: model used
    model_parameters JSONB, -- JSON: model-specific parameters used
    mortality_risk_prob DECIMAL(3,2), -- For growth simulations: predicted mortality risk
    predicted_structure_data JSONB, -- For growth simulations: predicted structure data
    environmental_snapshot_id INTEGER REFERENCES environmental_snapshots(id), -- For growth simulations: environmental context
    created_by VARCHAR(200), -- User or system that created this variant
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

CREATE TABLE tree_structures (
    id SERIAL PRIMARY KEY,
    tree_variant_id INTEGER REFERENCES tree_variants(id),
    structure_type_id INTEGER REFERENCES structure_types(id),
    file_path VARCHAR(500), -- Path to model file (if any)
    structure_data JSONB, -- JSON or string (e.g. L-system, latent vector, QSM params)
    generation_date TIMESTAMP,
    software VARCHAR(200), -- Tool or method used
    metadata JSONB, -- Additional parameters
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE structure_branches (
    id SERIAL PRIMARY KEY,
    structure_id INTEGER REFERENCES tree_structures(id),
    length_m DECIMAL(6,3),
    diameter_cm DECIMAL(5,2),
    direction_deg DECIMAL(5,2), -- Azimuth (horizontal direction in degrees)
    inclination_deg DECIMAL(5,2), -- Inclination angle from vertical (degrees)
    start_height_m DECIMAL(6,3), -- Height of branch start on parent (m)
    start_radius_cm DECIMAL(5,2), -- Radius at branch base (cm)
    geometry JSONB -- JSON/OBJ
);

CREATE TABLE structure_twigs (
    id SERIAL PRIMARY KEY,
    branch_id INTEGER REFERENCES structure_branches(id),
    length_m DECIMAL(6,3),
    diameter_cm DECIMAL(5,2),
    direction_deg DECIMAL(5,2),
    inclination_deg DECIMAL(5,2),
    start_height_m DECIMAL(6,3),
    geometry JSONB -- JSON/OBJ
);

CREATE TABLE structure_leaves (
    id SERIAL PRIMARY KEY,
    twig_id INTEGER REFERENCES structure_twigs(id),
    geometry JSONB, -- JSON/OBJ
    phenology_status_id INTEGER REFERENCES phenology_status(id),
    direction_deg DECIMAL(5,2),
    inclination_deg DECIMAL(5,2),
    start_height_m DECIMAL(6,3),
    color VARCHAR(50) -- Optional: leaf color for phenology/health
);

CREATE TABLE tree_microhabitats (
    id SERIAL PRIMARY KEY,
    tree_variant_id INTEGER REFERENCES tree_variants(id),
    microhabitat_type_id INTEGER REFERENCES microhabitat_types(id),
    height_m DECIMAL(6,3), -- Height of microhabitat feature
    size_id INTEGER REFERENCES microhabitat_sizes(id),
    condition_id INTEGER REFERENCES microhabitat_conditions(id),
    description TEXT, -- Detailed description of microhabitat
    first_observed TIMESTAMP, -- When microhabitat was first noted
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tree_quality_assessment (
    id SERIAL PRIMARY KEY,
    tree_variant_id INTEGER REFERENCES tree_variants(id),
    height_quality_id INTEGER REFERENCES data_quality_types(id),
    dbh_quality_id INTEGER REFERENCES data_quality_types(id),
    crown_width_quality_id INTEGER REFERENCES data_quality_types(id),
    volume_quality_id INTEGER REFERENCES data_quality_types(id),
    stem_straightness_index DECIMAL(3,2), -- 0-1: trunk straightness quality
    stem_quality_type_id INTEGER REFERENCES stem_quality_types(id),
    knot_frequency_per_m DECIMAL(5,2), -- Number of knots per meter
    stem_defect_type_id INTEGER REFERENCES stem_defect_types(id),
    crown_morphology_type_id INTEGER REFERENCES crown_morphology_types(id),
    crown_height_ratio DECIMAL(3,2), -- Crown height / total height
    root_condition_type_id INTEGER REFERENCES root_condition_types(id),
    timber_value_index DECIMAL(3,2), -- 0-1: estimated timber quality
    quality_notes TEXT, -- Additional quality observations
    assessment_date TIMESTAMP, -- When quality assessment was performed
    assessed_by VARCHAR(200), -- Personnel or method that performed assessment
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- =====================================================
-- ENVIRONMENT DATABASE SCHEMA
-- =====================================================

-- Environment Reference Tables
CREATE TABLE environment_sensor_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE, -- Temperature, Humidity, CO2, Light, Soil_Moisture, Wind
    description TEXT
);

CREATE TABLE sensor_status_types (
    id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE, -- active, inactive, maintenance, error
    description TEXT
);

CREATE TABLE aspect_types (
    id SERIAL PRIMARY KEY,
    aspect_name VARCHAR(10) NOT NULL UNIQUE, -- N, NE, E, SE, S, SW, W, NW
    description TEXT
);

CREATE TABLE spatial_dataset_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE, -- elevation, soil, vegetation, climate, canopy
    description TEXT
);

CREATE TABLE spatial_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) NOT NULL UNIQUE, -- raster, vector, point_cloud
    description TEXT
);

CREATE TABLE data_format_types (
    id SERIAL PRIMARY KEY,
    format_name VARCHAR(50) NOT NULL UNIQUE, -- GeoTIFF, Shapefile, LAS, NetCDF
    description TEXT
);

CREATE TABLE data_source_types (
    id SERIAL PRIMARY KEY,
    source_name VARCHAR(100) NOT NULL UNIQUE, -- survey, satellite, lidar, model
    description TEXT
);

CREATE TABLE quality_level_types (
    id SERIAL PRIMARY KEY,
    level_name VARCHAR(50) NOT NULL UNIQUE, -- high, medium, low
    description TEXT
);

CREATE TABLE extraction_method_types (
    id SERIAL PRIMARY KEY,
    method_name VARCHAR(100) NOT NULL UNIQUE, -- point_sample, area_average, interpolation
    description TEXT
);

CREATE TABLE trait_types (
    id SERIAL PRIMARY KEY,
    trait_name VARCHAR(100) NOT NULL UNIQUE, -- elevation, slope, soil_type, canopy_cover, drainage, fertility
    description TEXT
);

CREATE TABLE soil_types (
    id SERIAL PRIMARY KEY,
    soil_name VARCHAR(100) NOT NULL UNIQUE, -- Sandy, Clay, Loam, Peat, Rocky
    description TEXT
);

CREATE TABLE climate_zone_types (
    id SERIAL PRIMARY KEY,
    zone_name VARCHAR(10) NOT NULL UNIQUE, -- Köppen climate classification codes
    description TEXT
);

CREATE TABLE vegetation_types (
    id SERIAL PRIMARY KEY,
    type_name VARCHAR(100) NOT NULL UNIQUE, -- Deciduous, Coniferous, Mixed, Grassland, Shrubland
    description TEXT
);

-- Environment Core Tables
CREATE TABLE sensors (
    id SERIAL PRIMARY KEY,
    location_id INTEGER REFERENCES locations(id),
    sensor_type_id INTEGER REFERENCES environment_sensor_types(id),
    installation_date TIMESTAMP,
    status_type_id INTEGER REFERENCES sensor_status_types(id),
    sensor_config JSONB, -- JSON: config/calibration
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sensor_readings (
    id SERIAL PRIMARY KEY,
    sensor_id INTEGER REFERENCES sensors(id),
    timestamp TIMESTAMP NOT NULL,
    reading_type VARCHAR(100), -- Type (e.g. Temperature)
    value DECIMAL(12,4), -- Value
    unit VARCHAR(20), -- Unit
    quality_score DECIMAL(3,2), -- Reading quality score (0-1)
    validation_flags JSONB, -- JSON: validation status, outlier detection
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE site_characteristics (
    id SERIAL PRIMARY KEY,
    location_id INTEGER REFERENCES locations(id),
    elevation_m DECIMAL(8,2),
    slope_deg DECIMAL(5,2),
    aspect_type_id INTEGER REFERENCES aspect_types(id),
    soil_type_id INTEGER REFERENCES soil_types(id),
    climate_zone_type_id INTEGER REFERENCES climate_zone_types(id),
    annual_precipitation_mm DECIMAL(8,2),
    mean_temperature_c DECIMAL(5,2),
    vegetation_type_id INTEGER REFERENCES vegetation_types(id),
    canopy_cover_percent DECIMAL(5,2),
    additional_metadata JSONB,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE spatial_datasets (
    id SERIAL PRIMARY KEY,
    location_id INTEGER REFERENCES locations(id),
    dataset_name VARCHAR(200),
    dataset_type_id INTEGER REFERENCES spatial_dataset_types(id),
    spatial_type_id INTEGER REFERENCES spatial_types(id),
    data_format_type_id INTEGER REFERENCES data_format_types(id),
    file_path VARCHAR(500),
    resolution_m DECIMAL(8,4),
    coordinate_system VARCHAR(50), -- EPSG code
    bounding_geometry GEOMETRY(POLYGON, 4326),
    metadata JSONB,
    acquisition_date TIMESTAMP,
    import_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_source_type_id INTEGER REFERENCES data_source_types(id),
    quality_level_id INTEGER REFERENCES quality_level_types(id)
);

CREATE TABLE spatial_trait_mappings (
    id SERIAL PRIMARY KEY,
    spatial_dataset_id INTEGER REFERENCES spatial_datasets(id),
    trait_type_id INTEGER REFERENCES trait_types(id),
    extraction_method_type_id INTEGER REFERENCES extraction_method_types(id),
    extraction_parameters JSONB,
    units VARCHAR(50),
    created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);
-- =====================================================
-- CRITICAL CONSTRAINTS
-- =====================================================

-- Point Cloud Database Constraints
ALTER TABLE point_clouds ADD CONSTRAINT chk_processing_status 
CHECK (processing_status_type_id IN (1,2,3)); -- Raw, Segmented, Classified

ALTER TABLE point_clouds ADD CONSTRAINT chk_scan_date 
CHECK (scan_date >= '2020-01-01' AND scan_date <= CURRENT_DATE);

ALTER TABLE point_clouds ADD CONSTRAINT chk_point_count 
CHECK (point_count > 0);

-- Tree Database Constraints
ALTER TABLE tree_variants ADD CONSTRAINT chk_positive_measurements 
CHECK (height_m > 0 AND dbh_cm > 0 AND volume_m3 >= 0);

ALTER TABLE tree_variants ADD CONSTRAINT chk_crown_logic 
CHECK (crown_base_height_m >= 0 AND crown_base_height_m <= height_m);

ALTER TABLE tree_variants ADD CONSTRAINT chk_no_self_parent 
CHECK (id != parent_variant_id);

ALTER TABLE tree_variants ADD CONSTRAINT chk_mortality_risk 
CHECK (mortality_risk_prob >= 0 AND mortality_risk_prob <= 1);

-- Environment Database Constraints
ALTER TABLE environmental_snapshots ADD CONSTRAINT chk_temperature_range 
CHECK (avg_temperature_c >= -50 AND avg_temperature_c <= 60);

ALTER TABLE environmental_snapshots ADD CONSTRAINT chk_humidity_range 
CHECK (avg_humidity_percent >= 0 AND avg_humidity_percent <= 100);

ALTER TABLE environmental_snapshots ADD CONSTRAINT chk_precipitation_positive 
CHECK (total_precipitation_mm >= 0);

-- =====================================================
-- PERFORMANCE INDEXES
-- =====================================================

-- Spatial indexes for point cloud coverage
CREATE INDEX idx_point_clouds_scan_bounds ON point_clouds USING GIST (scan_bounds);
CREATE INDEX idx_locations_plot_boundary ON locations USING GIST (plot_boundary);
CREATE INDEX idx_locations_center_point ON locations USING GIST (center_point);

-- Temporal indexes for time-based queries
CREATE INDEX idx_point_clouds_scan_date ON point_clouds (scan_date);
CREATE INDEX idx_segmentation_process_date ON point_cloud_segmentation_results (process_date);

-- Foreign key indexes for Point Cloud DB
CREATE INDEX idx_point_clouds_location ON point_clouds (location_id);
CREATE INDEX idx_point_clouds_sensor_type ON point_clouds (sensor_type_id);
CREATE INDEX idx_processing_jobs_input ON processing_jobs (input_id);
CREATE INDEX idx_segmentation_results_point_cloud ON point_cloud_segmentation_results (point_cloud_id);
CREATE INDEX idx_classification_results_segmentation ON tree_classification_results (segmentation_result_id);

-- Spatial indexes for tree positions
CREATE INDEX idx_tree_variants_position ON tree_variants USING GIST (position);
CREATE INDEX idx_tree_variants_absolute_position ON tree_variants USING GIST (absolute_position);

-- Scenario and variant relationship indexes
CREATE INDEX idx_tree_variants_scenario ON tree_variants (scenario_id);
CREATE INDEX idx_tree_variants_parent ON tree_variants (parent_variant_id);
CREATE INDEX idx_tree_variants_tree_id ON tree_variants (tree_id);

-- Species and temporal indexes
CREATE INDEX idx_tree_variants_species ON tree_variants (species_id);
CREATE INDEX idx_tree_variants_timestamp ON tree_variants (variant_timestamp);
CREATE INDEX idx_trees_species ON trees (species_id);

-- Composite indexes for common queries
CREATE INDEX idx_trees_location_species ON trees (location_id, species_id);
CREATE INDEX idx_tree_variants_scenario_species ON tree_variants (scenario_id, species_id);

-- Tree structure relationship indexes
CREATE INDEX idx_tree_structures_variant ON tree_structures (tree_variant_id);
CREATE INDEX idx_structure_branches_structure ON structure_branches (structure_id);
CREATE INDEX idx_structure_twigs_branch ON structure_twigs (branch_id);
CREATE INDEX idx_structure_leaves_twig ON structure_leaves (twig_id);

-- Tree assessment indexes
CREATE INDEX idx_tree_microhabitats_variant ON tree_microhabitats (tree_variant_id);
CREATE INDEX idx_tree_quality_assessment_variant ON tree_quality_assessment (tree_variant_id);

-- Temporal indexes for sensor data
CREATE INDEX idx_sensor_readings_timestamp ON sensor_readings (timestamp);
CREATE INDEX idx_sensor_readings_sensor_timestamp ON sensor_readings (sensor_id, timestamp);
CREATE INDEX idx_environmental_snapshots_timestamp ON environmental_snapshots (timestamp);

-- Spatial indexes for environment
CREATE INDEX idx_spatial_datasets_bounding ON spatial_datasets USING GIST (bounding_geometry);
CREATE INDEX idx_sensors_location ON sensors (location_id);

-- Composite indexes for common environmental queries
CREATE INDEX idx_sensors_location_type ON sensors (location_id, sensor_type_id);
CREATE INDEX idx_sensor_readings_type_timestamp ON sensor_readings (reading_type, timestamp);

-- =====================================================
-- UNIQUE CONSTRAINTS
-- =====================================================

-- Prevent duplicate sensors of same type at same location
ALTER TABLE sensors ADD CONSTRAINT uk_sensors_location_type 
UNIQUE (location_id, sensor_type_id, installation_date);

-- Prevent duplicate spatial datasets
ALTER TABLE spatial_datasets ADD CONSTRAINT uk_spatial_dataset_location_type 
UNIQUE (location_id, dataset_type_id, acquisition_date);

-- =====================================================
-- INSERT INITIAL REFERENCE DATA
-- =====================================================

-- Processing Status Types
INSERT INTO processing_status_types (status_name, description) VALUES 
    ('Raw', 'Raw point cloud data'),
    ('Segmented', 'Trees segmented from point cloud'),
    ('Classified', 'Species classification completed');

-- Sensor Types
INSERT INTO sensor_types (type_name, description) VALUES 
    ('TLS', 'Terrestrial Laser Scanner'),
    ('UAV_LiDAR', 'UAV-mounted LiDAR'),
    ('Terrestrial_Camera', 'Ground-based camera system'),
    ('Mobile_LiDAR', 'Mobile mapping LiDAR system');

-- Species data
INSERT INTO species (common_name, scientific_name, growth_characteristics) VALUES 
    ('European Beech', 'Fagus sylvatica', '{"max_height_m": 40.0, "longevity_years": 300}'),
    ('Sessile Oak', 'Quercus petraea', '{"max_height_m": 35.0, "longevity_years": 800}'),
    ('Norway Spruce', 'Picea abies', '{"max_height_m": 50.0, "longevity_years": 400}'),
    ('Scots Pine', 'Pinus sylvestris', '{"max_height_m": 35.0, "longevity_years": 700}'),
    ('Silver Fir', 'Abies alba', '{"max_height_m": 50.0, "longevity_years": 600}');

-- Health Status
INSERT INTO health_status (status, description) VALUES 
    ('healthy', 'Tree shows no signs of stress or disease'),
    ('stressed', 'Tree shows minor signs of stress'),
    ('declining', 'Tree health is deteriorating'),
    ('dead', 'Tree is dead but standing'),
    ('fallen', 'Tree has fallen');

-- Phenology Status
INSERT INTO phenology_status (status, description) VALUES 
    ('dormant', 'Winter dormancy'),
    ('budbreak', 'Bud break stage'),
    ('leafout', 'Leaf emergence'),
    ('full_leaf', 'Full leaf development'),
    ('senescence', 'Autumn senescence'),
    ('abscission', 'Leaf drop');

-- Data Quality Types
INSERT INTO data_quality_types (quality_type, description) VALUES 
    ('Direct_Measurement', 'Directly measured in field'),
    ('Point_Cloud_Derived', 'Derived from point cloud analysis'),
    ('Model_Estimated', 'Estimated using predictive models');

-- Live Status Types
INSERT INTO live_status_types (status_name, description) VALUES 
    ('alive', 'Tree is alive and healthy'),
    ('dead', 'Tree is dead'),
    ('decaying', 'Tree is in decay process'),
    ('snag', 'Standing dead tree');

-- Variant Types
INSERT INTO variant_types (type_name, description) VALUES 
    ('Original', 'Original measured/observed tree'),
    ('Growth_Simulation', 'Simulated growth state'),
    ('Species_Replacement', 'Alternative species scenario'),
    ('Manual_Edit', 'Manually edited tree variant'),
    ('New', 'New tree in scenario');

-- Structure Types
INSERT INTO structure_types (type_name, description) VALUES 
    ('QSM', 'Quantitative Structure Model'),
    ('LSystem', 'L-System generated structure'),
    ('DeepTree', 'Deep learning generated structure'),
    ('Manual', 'Manually created structure'),
    ('Procedural', 'Procedurally generated structure');

-- Microhabitat Types
INSERT INTO microhabitat_types (type_name, description) VALUES 
    ('cavity', 'Tree cavity for wildlife'),
    ('dead_branch', 'Dead branch providing habitat'),
    ('epiphyte', 'Epiphytic plant growth'),
    ('bark_feature', 'Distinctive bark features'),
    ('root_buttress', 'Root buttress formations');

-- Microhabitat Sizes
INSERT INTO microhabitat_sizes (size_name, description) VALUES 
    ('small', 'Small microhabitat feature'),
    ('medium', 'Medium-sized microhabitat feature'),
    ('large', 'Large microhabitat feature');

-- Microhabitat Conditions
INSERT INTO microhabitat_conditions (condition_name, description) VALUES 
    ('active', 'Currently active habitat'),
    ('inactive', 'Inactive habitat'),
    ('developing', 'Developing habitat feature');

-- Stem Quality Types
INSERT INTO stem_quality_types (quality_name, description) VALUES 
    ('excellent', 'Excellent timber quality'),
    ('good', 'Good timber quality'),
    ('fair', 'Fair timber quality'),
    ('poor', 'Poor timber quality');

-- Stem Defect Types
INSERT INTO stem_defect_types (defect_name, description) VALUES 
    ('sweep', 'Stem sweep defect'),
    ('crook', 'Stem crook defect'),
    ('fork', 'Stem fork defect'),
    ('rot', 'Stem rot defect'),
    ('damage', 'Physical damage');

-- Crown Morphology Types
INSERT INTO crown_morphology_types (morphology_name, description) VALUES 
    ('symmetrical', 'Symmetrical crown shape'),
    ('asymmetrical', 'Asymmetrical crown shape'),
    ('suppressed', 'Suppressed crown development'),
    ('dominant', 'Dominant crown development');

-- Root Condition Types
INSERT INTO root_condition_types (condition_name, description) VALUES 
    ('healthy', 'Healthy root system'),
    ('stressed', 'Stressed root system'),
    ('damaged', 'Damaged root system'),
    ('exposed', 'Exposed root system');

-- Environment Sensor Types
INSERT INTO environment_sensor_types (type_name, description) VALUES 
    ('Temperature', 'Temperature measurement'),
    ('Humidity', 'Humidity measurement'),
    ('CO2', 'Carbon dioxide measurement'),
    ('Light', 'Light intensity measurement'),
    ('Soil_Moisture', 'Soil moisture measurement'),
    ('Wind', 'Wind speed and direction measurement');

-- Sensor Status Types
INSERT INTO sensor_status_types (status_name, description) VALUES 
    ('active', 'Sensor is active and recording'),
    ('inactive', 'Sensor is inactive'),
    ('maintenance', 'Sensor is under maintenance'),
    ('error', 'Sensor has an error condition');

-- Aspect Types
INSERT INTO aspect_types (aspect_name, description) VALUES 
    ('N', 'North facing'),
    ('NE', 'Northeast facing'),
    ('E', 'East facing'),
    ('SE', 'Southeast facing'),
    ('S', 'South facing'),
    ('SW', 'Southwest facing'),
    ('W', 'West facing'),
    ('NW', 'Northwest facing');

-- Spatial Dataset Types
INSERT INTO spatial_dataset_types (type_name, description) VALUES 
    ('elevation', 'Elevation/topographic data'),
    ('soil', 'Soil type and characteristics'),
    ('vegetation', 'Vegetation classification'),
    ('climate', 'Climate data'),
    ('canopy', 'Canopy cover data');

-- Spatial Types
INSERT INTO spatial_types (type_name, description) VALUES 
    ('raster', 'Raster/grid data'),
    ('vector', 'Vector data'),
    ('point_cloud', 'Point cloud data');

-- Data Format Types
INSERT INTO data_format_types (format_name, description) VALUES 
    ('GeoTIFF', 'GeoTIFF raster format'),
    ('Shapefile', 'ESRI Shapefile format'),
    ('LAS', 'LAS point cloud format'),
    ('NetCDF', 'NetCDF data format');

-- Data Source Types
INSERT INTO data_source_types (source_name, description) VALUES 
    ('survey', 'Field survey data'),
    ('satellite', 'Satellite imagery'),
    ('lidar', 'LiDAR scanning'),
    ('model', 'Model-generated data');

-- Quality Level Types
INSERT INTO quality_level_types (level_name, description) VALUES 
    ('high', 'High quality data'),
    ('medium', 'Medium quality data'),
    ('low', 'Low quality data');

-- Extraction Method Types
INSERT INTO extraction_method_types (method_name, description) VALUES 
    ('point_sample', 'Point sampling extraction'),
    ('area_average', 'Area averaging extraction'),
    ('interpolation', 'Interpolation-based extraction');

-- Trait Types
INSERT INTO trait_types (trait_name, description) VALUES 
    ('elevation', 'Site elevation'),
    ('slope', 'Site slope'),
    ('soil_type', 'Soil classification'),
    ('canopy_cover', 'Canopy cover percentage'),
    ('drainage', 'Site drainage characteristics'),
    ('fertility', 'Soil fertility indicators');

-- Soil Types
INSERT INTO soil_types (soil_name, description) VALUES 
    ('Sandy', 'Sandy soil type'),
    ('Clay', 'Clay soil type'),
    ('Loam', 'Loam soil type'),
    ('Peat', 'Peat soil type'),
    ('Rocky', 'Rocky soil type');

-- Climate Zone Types
INSERT INTO climate_zone_types (zone_name, description) VALUES 
    ('Cfb', 'Oceanic climate'),
    ('Dfb', 'Warm-summer humid continental climate'),
    ('Dfa', 'Hot-summer humid continental climate');

-- Vegetation Types
INSERT INTO vegetation_types (type_name, description) VALUES 
    ('Deciduous', 'Deciduous forest'),
    ('Coniferous', 'Coniferous forest'),
    ('Mixed', 'Mixed forest'),
    ('Grassland', 'Grassland vegetation'),
    ('Shrubland', 'Shrubland vegetation');

-- =====================================================
-- INSERT SAMPLE DATA
-- =====================================================

-- Sample location
INSERT INTO locations (location_name, description, center_point) VALUES 
    ('Test Forest Plot A', 'Sample forest plot for testing', 
     ST_SetSRID(ST_MakePoint(7.8494, 48.0041), 4326));

-- Sample scenario
INSERT INTO scenarios (scenario_name, scenario_parameters) VALUES 
    ('Baseline Current State', '{"description": "Current measured state of forest", "year": 2025}'),
    ('Climate Change 2050', '{"description": "Projected state under climate change", "year": 2050, "temperature_increase": 2.0}');

COMMIT;
