-- XR Future Forests Lab - Seed Data for Development and Testing
-- This migration provides sample data for local development

-- =============================================================================
-- SAMPLE LOCATIONS
-- =============================================================================

INSERT INTO shared.Locations (LocationName, Boundary, CenterPoint, Description, Elevation_m, Slope_deg, Aspect, SoilTypeID, ClimateZoneID) VALUES
    (
        'University Forest Plot A',
        ST_GeomFromText('POLYGON((7.85 47.99, 7.86 47.99, 7.86 48.00, 7.85 48.00, 7.85 47.99))', 4326),
        ST_GeomFromText('POINT(7.855 47.995)', 4326),
        'Primary research plot in mature mixed forest near Freiburg, Germany',
        450.0,
        12.5,
        'NW',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Alfisol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Cfb')
    ),
    (
        'University Forest Plot B',
        ST_GeomFromText('POLYGON((7.87 47.98, 7.88 47.98, 7.88 47.99, 7.87 47.99, 7.87 47.98))', 4326),
        ST_GeomFromText('POINT(7.875 47.985)', 4326),
        'Secondary research plot in regenerating forest',
        425.0,
        8.3,
        'N',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Alfisol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Cfb')
    ),
    (
        'Black Forest Test Site',
        ST_GeomFromText('POLYGON((8.10 48.50, 8.12 48.50, 8.12 48.52, 8.10 48.52, 8.10 48.50))', 4326),
        ST_GeomFromText('POINT(8.11 48.51)', 4326),
        'High-elevation Black Forest monitoring site',
        950.0,
        22.0,
        'SW',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Spodosol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Dfb')
    );

-- =============================================================================
-- SAMPLE SPECIES
-- =============================================================================

INSERT INTO shared.Species (CommonName, ScientificName, GrowthCharacteristics) VALUES
    (
        'European Beech',
        'Fagus sylvatica',
        '{"max_height_m": 40, "max_dbh_cm": 150, "typical_lifespan_years": 300, "growth_rate": "moderate", "shade_tolerance": "high"}'::jsonb
    ),
    (
        'Pedunculate Oak',
        'Quercus robur',
        '{"max_height_m": 35, "max_dbh_cm": 200, "typical_lifespan_years": 500, "growth_rate": "slow", "shade_tolerance": "moderate"}'::jsonb
    ),
    (
        'Norway Spruce',
        'Picea abies',
        '{"max_height_m": 50, "max_dbh_cm": 150, "typical_lifespan_years": 200, "growth_rate": "fast", "shade_tolerance": "high"}'::jsonb
    ),
    (
        'Silver Fir',
        'Abies alba',
        '{"max_height_m": 50, "max_dbh_cm": 200, "typical_lifespan_years": 500, "growth_rate": "moderate", "shade_tolerance": "very_high"}'::jsonb
    ),
    (
        'Scots Pine',
        'Pinus sylvestris',
        '{"max_height_m": 35, "max_dbh_cm": 100, "typical_lifespan_years": 300, "growth_rate": "moderate", "shade_tolerance": "low"}'::jsonb
    );

-- =============================================================================
-- SAMPLE PROCESSES
-- =============================================================================

INSERT INTO shared.Processes (ProcessName, AlgorithmName, Version, Description, Category) VALUES
    (
        'LiDAR_Tree_Segmentation',
        'TreeSegmentation_v2',
        'v2.1.0',
        'Individual tree segmentation from LiDAR point clouds using watershed algorithm',
        'detection'
    ),
    (
        'Species_Classification_ML',
        'RandomForest',
        'v1.5.3',
        'Machine learning-based species classification from point cloud features',
        'classification'
    ),
    (
        'SILVA_Growth_Simulation',
        'SILVA',
        'v4.0',
        'Individual tree growth simulation using SILVA forest model',
        'simulation'
    ),
    (
        'Sensor_Data_Aggregation',
        'Statistical',
        'v1.0.0',
        'Aggregation of sensor readings into environmental variants',
        'aggregation'
    );

-- =============================================================================
-- SAMPLE POINT CLOUDS
-- =============================================================================

INSERT INTO pointclouds.PointClouds (LocationID, VariantTypeID, VariantName, ScanDate, SensorModel, ScanBounds, FilePath, PointCount, FileSizeMB) VALUES
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original'),
        'Plot_A_Summer_2024',
        '2024-07-15 10:30:00+02',
        'Leica BLK360',
        ST_GeomFromText('POLYGON((7.85 47.99, 7.86 47.99, 7.86 48.00, 7.85 48.00, 7.85 47.99))', 4326),
        's3://xr-forests-pointclouds/plot-a/2024-07-15_scan_original.las',
        15847239,
        485.2
    ),
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot B'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original'),
        'Plot_B_Summer_2024',
        '2024-07-16 09:15:00+02',
        'Leica BLK360',
        ST_GeomFromText('POLYGON((7.87 47.98, 7.88 47.98, 7.88 47.99, 7.87 47.99, 7.87 47.98))', 4326),
        's3://xr-forests-pointclouds/plot-b/2024-07-16_scan_original.las',
        12354789,
        378.5
    );

-- Create processed variants
INSERT INTO pointclouds.PointClouds (ParentVariantID, LocationID, VariantTypeID, ProcessID, VariantName, ScanDate, SensorModel, ScanBounds, FilePath, PointCount, FileSizeMB, ProcessingStatus) VALUES
    (
        (SELECT VariantID FROM pointclouds.PointClouds WHERE VariantName = 'Plot_A_Summer_2024'),
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'processed'),
        (SELECT ProcessID FROM shared.Processes WHERE ProcessName = 'LiDAR_Tree_Segmentation'),
        'Plot_A_Summer_2024_Segmented',
        '2024-07-15 10:30:00+02',
        'Leica BLK360',
        ST_GeomFromText('POLYGON((7.85 47.99, 7.86 47.99, 7.86 48.00, 7.85 48.00, 7.85 47.99))', 4326),
        's3://xr-forests-pointclouds/plot-a/2024-07-15_scan_segmented.las',
        15847239,
        492.8,
        'completed'
    );

-- =============================================================================
-- SAMPLE TREES
-- =============================================================================

INSERT INTO trees.Trees (
    LocationID, VariantTypeID, ProcessID, PointCloudVariantID, SpeciesID, TreeStatusID,
    Height_m, CrownWidth_m, CrownBaseHeight_m, Volume_m3, Position,
    Age_years, HealthScore
) VALUES
    -- European Beech trees
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'processed'),
        (SELECT ProcessID FROM shared.Processes WHERE ProcessName = 'LiDAR_Tree_Segmentation'),
        (SELECT VariantID FROM pointclouds.PointClouds WHERE VariantName = 'Plot_A_Summer_2024_Segmented'),
        (SELECT SpeciesID FROM shared.Species WHERE ScientificName = 'Fagus sylvatica'),
        (SELECT TreeStatusID FROM trees.TreeStatus WHERE TreeStatusName = 'healthy'),
        28.5, 9.2, 12.3, 3.45,
        ST_GeomFromText('POINT(7.8525 47.9975)', 4326),
        85, 0.92
    ),
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'processed'),
        (SELECT ProcessID FROM shared.Processes WHERE ProcessName = 'LiDAR_Tree_Segmentation'),
        (SELECT VariantID FROM pointclouds.PointClouds WHERE VariantName = 'Plot_A_Summer_2024_Segmented'),
        (SELECT SpeciesID FROM shared.Species WHERE ScientificName = 'Fagus sylvatica'),
        (SELECT TreeStatusID FROM trees.TreeStatus WHERE TreeStatusName = 'healthy'),
        31.2, 10.5, 14.1, 4.82,
        ST_GeomFromText('POINT(7.8535 47.9982)', 4326),
        95, 0.95
    ),
    -- Oak trees
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'processed'),
        (SELECT ProcessID FROM shared.Processes WHERE ProcessName = 'LiDAR_Tree_Segmentation'),
        (SELECT VariantID FROM pointclouds.PointClouds WHERE VariantName = 'Plot_A_Summer_2024_Segmented'),
        (SELECT SpeciesID FROM shared.Species WHERE ScientificName = 'Quercus robur'),
        (SELECT TreeStatusID FROM trees.TreeStatus WHERE TreeStatusName = 'healthy'),
        26.8, 11.3, 10.5, 4.15,
        ST_GeomFromText('POINT(7.8545 47.9970)', 4326),
        120, 0.88
    ),
    -- Norway Spruce
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'processed'),
        (SELECT ProcessID FROM shared.Processes WHERE ProcessName = 'LiDAR_Tree_Segmentation'),
        (SELECT VariantID FROM pointclouds.PointClouds WHERE VariantName = 'Plot_A_Summer_2024_Segmented'),
        (SELECT SpeciesID FROM shared.Species WHERE ScientificName = 'Picea abies'),
        (SELECT TreeStatusID FROM trees.TreeStatus WHERE TreeStatusName = 'stressed'),
        22.4, 6.8, 8.2, 1.95,
        ST_GeomFromText('POINT(7.8555 47.9965)', 4326),
        65, 0.72
    );

-- =============================================================================
-- SAMPLE STEMS (for multi-stem trees)
-- =============================================================================

INSERT INTO trees.Stems (TreeVariantID, StemNumber, TaperTypeID, StraightnessTypeID, DBH_cm, StemHeight_m, StemVolume_m3) VALUES
    -- Beech tree 1 - single stem
    (
        (SELECT VariantID FROM trees.Trees WHERE Height_m = 28.5 LIMIT 1),
        1,
        (SELECT TaperTypeID FROM trees.TaperTypes WHERE TaperTypeName = 'Paraboloid'),
        (SELECT StraightnessTypeID FROM trees.StraightnessTypes WHERE StraightnessName = 'Straight'),
        52.3, 28.5, 3.45
    ),
    -- Beech tree 2 - single stem
    (
        (SELECT VariantID FROM trees.Trees WHERE Height_m = 31.2 LIMIT 1),
        1,
        (SELECT TaperTypeID FROM trees.TaperTypes WHERE TaperTypeName = 'Paraboloid'),
        (SELECT StraightnessTypeID FROM trees.StraightnessTypes WHERE StraightnessName = 'Straight'),
        58.7, 31.2, 4.82
    ),
    -- Oak - single stem
    (
        (SELECT VariantID FROM trees.Trees WHERE Height_m = 26.8 LIMIT 1),
        1,
        (SELECT TaperTypeID FROM trees.TaperTypes WHERE TaperTypeName = 'Cone'),
        (SELECT StraightnessTypeID FROM trees.StraightnessTypes WHERE StraightnessName = 'Slight_sweep'),
        64.2, 26.8, 4.15
    ),
    -- Spruce - single stem
    (
        (SELECT VariantID FROM trees.Trees WHERE Height_m = 22.4 LIMIT 1),
        1,
        (SELECT TaperTypeID FROM trees.TaperTypes WHERE TaperTypeName = 'Cone'),
        (SELECT StraightnessTypeID FROM trees.StraightnessTypes WHERE StraightnessName = 'Straight'),
        38.5, 22.4, 1.95
    );

-- =============================================================================
-- SAMPLE SENSORS
-- =============================================================================

INSERT INTO sensor.Sensors (
    LocationID, SensorTypeID, SensorModel, SerialNumber, Position,
    InstallationDate, SamplingInterval_seconds, ReadingType, Unit, IsActive
) VALUES
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT SensorTypeID FROM sensor.SensorTypes WHERE SensorTypeName = 'Temperature'),
        'EcoSense TH-100',
        'TH100-2024-001',
        ST_GeomFromText('POINT(7.8530 47.9978)', 4326),
        '2024-01-15 08:00:00+01',
        600,  -- 10 minutes
        'Air Temperature',
        '°C',
        TRUE
    ),
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT SensorTypeID FROM sensor.SensorTypes WHERE SensorTypeName = 'Humidity'),
        'EcoSense TH-100',
        'TH100-2024-001',
        ST_GeomFromText('POINT(7.8530 47.9978)', 4326),
        '2024-01-15 08:00:00+01',
        600,  -- 10 minutes
        'Relative Humidity',
        '%',
        TRUE
    ),
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT SensorTypeID FROM sensor.SensorTypes WHERE SensorTypeName = 'Soil_Moisture'),
        'EcoSense SM-50',
        'SM50-2024-012',
        ST_GeomFromText('POINT(7.8532 47.9972)', 4326),
        '2024-01-20 10:30:00+01',
        1800,  -- 30 minutes
        'Soil Volumetric Water Content',
        '%',
        TRUE
    );

-- =============================================================================
-- SAMPLE SENSOR READINGS (recent data)
-- =============================================================================

-- Temperature readings for the last 24 hours
INSERT INTO sensor.SensorReadings (SensorID, Timestamp, Value, Quality)
SELECT
    (SELECT SensorID FROM sensor.Sensors WHERE SerialNumber = 'TH100-2024-001' AND ReadingType = 'Air Temperature'),
    NOW() - (interval '10 minutes' * generate_series(0, 143)),  -- Last 24 hours
    15 + 8 * SIN(generate_series(0, 143) * PI() / 72) + (random() - 0.5) * 2,  -- Simulated diurnal pattern
    'good'
FROM generate_series(0, 143);

-- Humidity readings
INSERT INTO sensor.SensorReadings (SensorID, Timestamp, Value, Quality)
SELECT
    (SELECT SensorID FROM sensor.Sensors WHERE SerialNumber = 'TH100-2024-001' AND ReadingType = 'Relative Humidity'),
    NOW() - (interval '10 minutes' * generate_series(0, 143)),
    65 - 20 * SIN(generate_series(0, 143) * PI() / 72) + (random() - 0.5) * 5,  -- Inverse diurnal pattern
    'good'
FROM generate_series(0, 143);

-- Soil moisture readings
INSERT INTO sensor.SensorReadings (SensorID, Timestamp, Value, Quality)
SELECT
    (SELECT SensorID FROM sensor.Sensors WHERE SerialNumber = 'SM50-2024-012'),
    NOW() - (interval '30 minutes' * generate_series(0, 47)),  -- Last 24 hours
    35 + (random() - 0.5) * 3,  -- Relatively stable soil moisture
    'good'
FROM generate_series(0, 47);

-- =============================================================================
-- SAMPLE ENVIRONMENTS
-- =============================================================================

INSERT INTO environments.Environments (
    LocationID, VariantTypeID, VariantName, StartDate, EndDate,
    AvgTemperature_C, AvgHumidity_percent, AvgCO2_ppm
) VALUES
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'sensor_derived'),
        'Plot_A_July_2024_Baseline',
        '2024-07-01 00:00:00+02',
        '2024-07-31 23:59:59+02',
        18.5, 68.2, 415.3
    ),
    (
        (SELECT LocationID FROM shared.Locations WHERE LocationName = 'University Forest Plot A'),
        (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'user_input'),
        'Plot_A_Climate_Change_2050',
        '2050-07-01 00:00:00+02',
        '2050-07-31 23:59:59+02',
        22.5, 62.0, 550.0
    );

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE shared.Locations IS 'Sample locations include University Forest plots near Freiburg, Germany';
COMMENT ON TABLE shared.Species IS 'Common Central European forest species';
COMMENT ON TABLE trees.Trees IS 'Sample trees detected from LiDAR scans in Plot A';
COMMENT ON TABLE sensor.Sensors IS 'EcoSense environmental monitoring sensors';
COMMENT ON TABLE sensor.SensorReadings IS 'Simulated sensor readings for the last 24 hours';
