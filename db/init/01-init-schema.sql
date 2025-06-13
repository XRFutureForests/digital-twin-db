-- XR Future Forests Lab - Database Initialization
-- Creates the minimal database schema for the three specialized databases

\c xr_forests_lab;

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- POINT CLOUD DATABASE SCHEMA (Minimal)
-- =====================================================

-- Reference Tables
CREATE TABLE processing_status_types (
    id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

INSERT INTO processing_status_types (status_name, description) VALUES 
    ('uploaded', 'Point cloud file uploaded, awaiting processing'),
    ('processing', 'Point cloud being processed'),
    ('segmented', 'Trees segmented from point cloud'),
    ('classified', 'Species classification completed'),
    ('completed', 'All processing completed successfully'),
    ('failed', 'Processing failed');

CREATE TABLE sensor_types (
    id SERIAL PRIMARY KEY,
    sensor_name VARCHAR(100) NOT NULL UNIQUE,
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    description TEXT
);

INSERT INTO sensor_types (sensor_name, manufacturer, model, description) VALUES 
    ('Terrestrial LiDAR', 'FARO', 'Focus S350', 'High-precision terrestrial laser scanner'),
    ('Airborne LiDAR', 'Riegl', 'VUX-1LR', 'Airborne laser scanning system'),
    ('Mobile LiDAR', 'KAARTA', 'Stencil-2', 'Handheld mobile mapping system');

-- Core Tables
CREATE TABLE locations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    location_name VARCHAR(200) NOT NULL,
    description TEXT,
    plot_boundary GEOMETRY(POLYGON, 4326),
    center_point GEOMETRY(POINT, 4326),
    elevation_m DECIMAL(8,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE point_clouds (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    location_id UUID REFERENCES locations(id),
    file_path VARCHAR(500) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    scan_date TIMESTAMP NOT NULL,
    sensor_type_id INTEGER REFERENCES sensor_types(id),
    processing_status_id INTEGER REFERENCES processing_status_types(id) DEFAULT 1,
    point_count BIGINT,
    file_size_mb DECIMAL(10,2),
    scan_bounds GEOMETRY(POLYGON, 4326),
    scan_resolution_m DECIMAL(6,4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    point_cloud_metadata JSONB
);

CREATE TABLE processing_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    point_cloud_id UUID REFERENCES point_clouds(id),
    job_type VARCHAR(50) NOT NULL, -- 'segmentation', 'classification', 'extraction'
    status VARCHAR(20) DEFAULT 'queued', -- 'queued', 'running', 'completed', 'failed'
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    progress_percent INTEGER DEFAULT 0,
    error_message TEXT,
    result_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- TREE DATABASE SCHEMA (Minimal)
-- =====================================================

-- Reference Tables
CREATE TABLE species (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    scientific_name VARCHAR(200) NOT NULL UNIQUE,
    common_name VARCHAR(200),
    species_code VARCHAR(10) UNIQUE,
    max_height_m DECIMAL(5,2),
    longevity_years INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO species (scientific_name, common_name, species_code, max_height_m, longevity_years) VALUES 
    ('Fagus sylvatica', 'European Beech', 'FASY', 40.0, 300),
    ('Quercus petraea', 'Sessile Oak', 'QUPE', 35.0, 800),
    ('Picea abies', 'Norway Spruce', 'PIAB', 50.0, 400),
    ('Pinus sylvestris', 'Scots Pine', 'PISY', 35.0, 700),
    ('Abies alba', 'Silver Fir', 'ABAL', 50.0, 600);

CREATE TABLE health_status_types (
    id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

INSERT INTO health_status_types (status_name, description) VALUES 
    ('healthy', 'Tree shows no signs of stress or disease'),
    ('stressed', 'Tree shows minor signs of stress'),
    ('declining', 'Tree health is deteriorating'),
    ('dead', 'Tree is dead but standing'),
    ('fallen', 'Tree has fallen');

-- Core Tables
CREATE TABLE trees (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    location_id UUID REFERENCES locations(id),
    tree_tag VARCHAR(50), -- Field identification tag
    species_id UUID REFERENCES species(id),
    position GEOMETRY(POINT, 4326) NOT NULL,
    discovery_date DATE DEFAULT CURRENT_DATE,
    discovery_method VARCHAR(50) DEFAULT 'field_survey', -- 'field_survey', 'point_cloud', 'remote_sensing'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tree_measurements (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    tree_id UUID REFERENCES trees(id),
    measurement_date TIMESTAMP NOT NULL,
    height_m DECIMAL(5,2) CHECK (height_m > 0),
    dbh_cm DECIMAL(5,2) CHECK (dbh_cm > 0),
    crown_width_m DECIMAL(5,2) CHECK (crown_width_m > 0),
    crown_height_m DECIMAL(5,2),
    health_status_id INTEGER REFERENCES health_status_types(id),
    measurement_method VARCHAR(50) DEFAULT 'manual', -- 'manual', 'point_cloud_derived', 'estimated'
    measurement_quality CHAR(1) DEFAULT 'B' CHECK (measurement_quality IN ('A', 'B', 'C', 'D')),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    measured_by VARCHAR(100)
);

-- =====================================================
-- ENVIRONMENT DATABASE SCHEMA (Minimal)
-- =====================================================

-- Reference Tables
CREATE TABLE environment_sensor_types (
    id SERIAL PRIMARY KEY,
    sensor_name VARCHAR(100) NOT NULL UNIQUE,
    measurement_unit VARCHAR(20),
    measurement_range VARCHAR(50),
    description TEXT
);

INSERT INTO environment_sensor_types (sensor_name, measurement_unit, measurement_range, description) VALUES 
    ('Temperature', '°C', '-40 to +60', 'Air temperature sensor'),
    ('Humidity', '%', '0 to 100', 'Relative humidity sensor'),
    ('Soil Moisture', '%', '0 to 100', 'Volumetric soil moisture content'),
    ('Light Intensity', 'lux', '0 to 100000', 'Photosynthetically active radiation'),
    ('Wind Speed', 'm/s', '0 to 50', 'Wind speed measurement'),
    ('Precipitation', 'mm', '0 to 1000', 'Rainfall measurement');

-- Core Tables
CREATE TABLE environment_sensors (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    location_id UUID REFERENCES locations(id),
    sensor_type_id INTEGER REFERENCES environment_sensor_types(id),
    sensor_name VARCHAR(100) NOT NULL,
    position GEOMETRY(POINT, 4326),
    installation_date DATE,
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'maintenance', 'offline'
    last_reading_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sensor_readings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    sensor_id UUID REFERENCES environment_sensors(id),
    reading_timestamp TIMESTAMP NOT NULL,
    value DECIMAL(10,4) NOT NULL,
    quality_flag CHAR(1) DEFAULT 'A' CHECK (quality_flag IN ('A', 'B', 'C', 'D')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE environmental_snapshots (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    location_id UUID REFERENCES locations(id),
    snapshot_timestamp TIMESTAMP NOT NULL,
    avg_temperature_c DECIMAL(5,2),
    avg_humidity_percent DECIMAL(5,2),
    avg_soil_moisture_percent DECIMAL(5,2),
    total_precipitation_mm DECIMAL(6,2),
    avg_light_intensity_lux DECIMAL(8,2),
    avg_wind_speed_ms DECIMAL(4,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- INDEXES FOR PERFORMANCE
-- =====================================================

-- Spatial indexes
CREATE INDEX idx_locations_plot_boundary ON locations USING GIST (plot_boundary);
CREATE INDEX idx_locations_center_point ON locations USING GIST (center_point);
CREATE INDEX idx_point_clouds_scan_bounds ON point_clouds USING GIST (scan_bounds);
CREATE INDEX idx_trees_position ON trees USING GIST (position);
CREATE INDEX idx_sensors_position ON environment_sensors USING GIST (position);

-- Temporal indexes
CREATE INDEX idx_point_clouds_scan_date ON point_clouds (scan_date);
CREATE INDEX idx_tree_measurements_date ON tree_measurements (measurement_date);
CREATE INDEX idx_sensor_readings_timestamp ON sensor_readings (reading_timestamp);
CREATE INDEX idx_environmental_snapshots_timestamp ON environmental_snapshots (snapshot_timestamp);

-- Foreign key indexes
CREATE INDEX idx_point_clouds_location ON point_clouds (location_id);
CREATE INDEX idx_trees_location ON trees (location_id);
CREATE INDEX idx_trees_species ON trees (species_id);
CREATE INDEX idx_tree_measurements_tree ON tree_measurements (tree_id);
CREATE INDEX idx_sensors_location ON environment_sensors (location_id);
CREATE INDEX idx_sensor_readings_sensor ON sensor_readings (sensor_id);

-- =====================================================
-- INSERT SAMPLE DATA
-- =====================================================

-- Sample location
INSERT INTO locations (location_name, description, center_point, elevation_m) VALUES 
    ('Test Forest Plot A', 'Sample forest plot for testing', 
     ST_SetSRID(ST_MakePoint(7.8494, 48.0041), 4326), 450.0);

-- Get the location ID for sample data
DO $$
DECLARE
    location_uuid UUID;
    tree_uuid UUID;
    sensor_uuid UUID;
BEGIN
    -- Get the sample location ID
    SELECT id INTO location_uuid FROM locations WHERE location_name = 'Test Forest Plot A';
    
    -- Insert sample trees
    INSERT INTO trees (location_id, tree_tag, species_id, position) VALUES 
        (location_uuid, 'T001', (SELECT id FROM species WHERE species_code = 'FASY'), 
         ST_SetSRID(ST_MakePoint(7.8495, 48.0042), 4326)),
        (location_uuid, 'T002', (SELECT id FROM species WHERE species_code = 'QUPE'), 
         ST_SetSRID(ST_MakePoint(7.8496, 48.0043), 4326)),
        (location_uuid, 'T003', (SELECT id FROM species WHERE species_code = 'PIAB'), 
         ST_SetSRID(ST_MakePoint(7.8497, 48.0044), 4326));
    
    -- Insert sample measurements for first tree
    SELECT id INTO tree_uuid FROM trees WHERE tree_tag = 'T001';
    INSERT INTO tree_measurements (tree_id, measurement_date, height_m, dbh_cm, crown_width_m, health_status_id) VALUES 
        (tree_uuid, CURRENT_TIMESTAMP, 15.5, 25.3, 8.2, 1),
        (tree_uuid, CURRENT_TIMESTAMP - INTERVAL '1 year', 14.8, 23.1, 7.8, 1);
    
    -- Insert sample environmental sensor
    INSERT INTO environment_sensors (location_id, sensor_type_id, sensor_name, position) VALUES 
        (location_uuid, 1, 'Weather Station Alpha', ST_SetSRID(ST_MakePoint(7.8494, 48.0041), 4326));
    
    -- Insert sample sensor readings
    SELECT id INTO sensor_uuid FROM environment_sensors WHERE sensor_name = 'Weather Station Alpha';
    INSERT INTO sensor_readings (sensor_id, reading_timestamp, value) VALUES 
        (sensor_uuid, CURRENT_TIMESTAMP, 18.5),
        (sensor_uuid, CURRENT_TIMESTAMP - INTERVAL '1 hour', 17.8),
        (sensor_uuid, CURRENT_TIMESTAMP - INTERVAL '2 hours', 17.2);
        
END $$;
