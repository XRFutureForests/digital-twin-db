-- XR Future Forests Lab - Load Lookup Tables from CSV
-- This migration loads all reference/lookup data from CSV files in /data/lookups/
-- 
-- The CSV files are the source of truth for lookup data. Edit them to add/modify
-- lookup values, then rebuild the database to apply changes.
--
-- Dependencies: Schema tables must exist (created by prior migrations)

SET search_path TO shared, sensor, trees, public;

-- =============================================================================
-- HELPER FUNCTION: Load CSV via COPY
-- =============================================================================
-- Note: PostgreSQL COPY requires absolute paths. In Docker, the data volume
-- is mounted at /var/lib/postgresql/lookups/

-- =============================================================================
-- LOAD SOIL TYPES
-- =============================================================================
CREATE TEMP TABLE temp_soil_types (
    SoilTypeName VARCHAR(100),
    Description TEXT
);

\copy temp_soil_types FROM '/var/lib/postgresql/lookups/soil_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.SoilTypes (SoilTypeName, Description)
SELECT SoilTypeName, Description FROM temp_soil_types
ON CONFLICT (SoilTypeName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_soil_types;

-- =============================================================================
-- LOAD CLIMATE ZONES
-- =============================================================================
CREATE TEMP TABLE temp_climate_zones (
    ClimateZoneName VARCHAR(10),
    Description TEXT
);

\copy temp_climate_zones FROM '/var/lib/postgresql/lookups/climate_zones.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.ClimateZones (ClimateZoneName, Description)
SELECT ClimateZoneName, Description FROM temp_climate_zones
ON CONFLICT (ClimateZoneName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_climate_zones;

-- =============================================================================
-- LOAD VARIANT TYPES
-- =============================================================================
CREATE TEMP TABLE temp_variant_types (
    VariantTypeName VARCHAR(100),
    Description TEXT
);

\copy temp_variant_types FROM '/var/lib/postgresql/lookups/variant_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.VariantTypes (VariantTypeName, Description)
SELECT VariantTypeName, Description FROM temp_variant_types
ON CONFLICT (VariantTypeName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_variant_types;

-- =============================================================================
-- LOAD SCENARIOS
-- =============================================================================
CREATE TEMP TABLE temp_scenarios (
    ScenarioName VARCHAR(200),
    Description TEXT
);

\copy temp_scenarios FROM '/var/lib/postgresql/lookups/scenarios.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.Scenarios (ScenarioName, Description)
SELECT ScenarioName, Description FROM temp_scenarios
ON CONFLICT (ScenarioName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_scenarios;

-- =============================================================================
-- LOAD SPECIES
-- =============================================================================
CREATE TEMP TABLE temp_species (
    CommonName VARCHAR(200),
    ScientificName VARCHAR(200),
    MaxHeight_m NUMERIC(6, 2),
    MaxDBH_cm NUMERIC(6, 2),
    TypicalLifespan_years INTEGER,
    GrowthRate VARCHAR(20),
    ShadeTolerance VARCHAR(20),
    IsDeciduous BOOLEAN
);

\copy temp_species FROM '/var/lib/postgresql/lookups/species.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.Species (CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance, IsDeciduous)
SELECT CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance, IsDeciduous
FROM temp_species
ON CONFLICT (ScientificName) DO UPDATE SET
    CommonName = EXCLUDED.CommonName,
    MaxHeight_m = EXCLUDED.MaxHeight_m,
    MaxDBH_cm = EXCLUDED.MaxDBH_cm,
    TypicalLifespan_years = EXCLUDED.TypicalLifespan_years,
    GrowthRate = EXCLUDED.GrowthRate,
    ShadeTolerance = EXCLUDED.ShadeTolerance,
    IsDeciduous = EXCLUDED.IsDeciduous;

DROP TABLE temp_species;

-- =============================================================================
-- LOAD SENSOR TYPES
-- =============================================================================
CREATE TEMP TABLE temp_sensor_types (
    SensorTypeName VARCHAR(100),
    Description TEXT,
    TypicalUnit VARCHAR(50),
    TypicalRangeMin NUMERIC(12, 4),
    TypicalRangeMax NUMERIC(12, 4)
);

\copy temp_sensor_types FROM '/var/lib/postgresql/lookups/sensor_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO sensor.SensorTypes (SensorTypeName, Description, TypicalUnit, TypicalRangeMin, TypicalRangeMax)
SELECT SensorTypeName, Description, TypicalUnit, TypicalRangeMin, TypicalRangeMax 
FROM temp_sensor_types
ON CONFLICT (SensorTypeName) DO UPDATE SET
    Description = EXCLUDED.Description,
    TypicalUnit = EXCLUDED.TypicalUnit,
    TypicalRangeMin = EXCLUDED.TypicalRangeMin,
    TypicalRangeMax = EXCLUDED.TypicalRangeMax;

DROP TABLE temp_sensor_types;

-- =============================================================================
-- LOAD TREE STATUS
-- =============================================================================
CREATE TEMP TABLE temp_tree_status (
    TreeStatusName VARCHAR(100),
    Description TEXT
);

\copy temp_tree_status FROM '/var/lib/postgresql/lookups/tree_status.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.TreeStatus (TreeStatusName, Description)
SELECT TreeStatusName, Description FROM temp_tree_status
ON CONFLICT (TreeStatusName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_tree_status;

-- =============================================================================
-- LOAD TAPER TYPES
-- =============================================================================
CREATE TEMP TABLE temp_taper_types (
    TaperTypeName VARCHAR(100),
    Description TEXT,
    TypicalTaperRatioMin NUMERIC(4, 3),
    TypicalTaperRatioMax NUMERIC(4, 3)
);

\copy temp_taper_types FROM '/var/lib/postgresql/lookups/taper_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.TaperTypes (TaperTypeName, Description, TypicalTaperRatioMin, TypicalTaperRatioMax)
SELECT TaperTypeName, Description, TypicalTaperRatioMin, TypicalTaperRatioMax FROM temp_taper_types
ON CONFLICT (TaperTypeName) DO UPDATE SET 
    Description = EXCLUDED.Description,
    TypicalTaperRatioMin = EXCLUDED.TypicalTaperRatioMin,
    TypicalTaperRatioMax = EXCLUDED.TypicalTaperRatioMax;

DROP TABLE temp_taper_types;

-- =============================================================================
-- LOAD STRAIGHTNESS TYPES
-- =============================================================================
CREATE TEMP TABLE temp_straightness_types (
    StraightnessName VARCHAR(100),
    Description TEXT,
    DeviationAngleMin NUMERIC(5, 2),
    DeviationAngleMax NUMERIC(5, 2)
);

\copy temp_straightness_types FROM '/var/lib/postgresql/lookups/straightness_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.StraightnessTypes (StraightnessName, Description, DeviationAngleMin, DeviationAngleMax)
SELECT StraightnessName, Description, DeviationAngleMin, DeviationAngleMax FROM temp_straightness_types
ON CONFLICT (StraightnessName) DO UPDATE SET 
    Description = EXCLUDED.Description,
    DeviationAngleMin = EXCLUDED.DeviationAngleMin,
    DeviationAngleMax = EXCLUDED.DeviationAngleMax;

DROP TABLE temp_straightness_types;

-- =============================================================================
-- LOAD BRANCHING PATTERNS
-- =============================================================================
CREATE TEMP TABLE temp_branching_patterns (
    BranchingPatternName VARCHAR(100),
    Description TEXT
);

\copy temp_branching_patterns FROM '/var/lib/postgresql/lookups/branching_patterns.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.BranchingPatterns (BranchingPatternName, Description)
SELECT BranchingPatternName, Description FROM temp_branching_patterns
ON CONFLICT (BranchingPatternName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_branching_patterns;

-- =============================================================================
-- LOAD BARK CHARACTERISTICS
-- =============================================================================
CREATE TEMP TABLE temp_bark_characteristics (
    BarkCharacteristicName VARCHAR(100),
    Description TEXT,
    TypicalSpecies TEXT
);

\copy temp_bark_characteristics FROM '/var/lib/postgresql/lookups/bark_characteristics.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.BarkCharacteristics (BarkCharacteristicName, Description, TypicalSpecies)
SELECT BarkCharacteristicName, Description, TypicalSpecies FROM temp_bark_characteristics
ON CONFLICT (BarkCharacteristicName) DO UPDATE SET 
    Description = EXCLUDED.Description,
    TypicalSpecies = EXCLUDED.TypicalSpecies;

DROP TABLE temp_bark_characteristics;

-- =============================================================================
-- LOAD LOCATIONS
-- =============================================================================
CREATE TEMP TABLE temp_locations (
    LocationName VARCHAR(200),
    Description TEXT,
    CenterLongitude NUMERIC(10, 6),
    CenterLatitude NUMERIC(10, 6),
    Elevation_m NUMERIC(8, 2),
    Slope_deg NUMERIC(5, 2),
    Aspect VARCHAR(3),
    SoilTypeName VARCHAR(100),
    ClimateZoneName VARCHAR(10)
);

\copy temp_locations FROM '/var/lib/postgresql/lookups/locations.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.Locations (LocationName, Description, CenterPoint, Elevation_m, Slope_deg, Aspect, SoilTypeID, ClimateZoneID)
SELECT 
    t.LocationName,
    t.Description,
    CASE WHEN t.CenterLongitude IS NOT NULL AND t.CenterLatitude IS NOT NULL 
         THEN extensions.ST_SetSRID(extensions.ST_MakePoint(t.CenterLongitude, t.CenterLatitude), 4326)
         ELSE NULL 
    END,
    t.Elevation_m,
    t.Slope_deg,
    t.Aspect,
    (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = t.SoilTypeName),
    (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = t.ClimateZoneName)
FROM temp_locations t
ON CONFLICT (LocationName) DO UPDATE SET
    Description = EXCLUDED.Description,
    CenterPoint = EXCLUDED.CenterPoint,
    Elevation_m = EXCLUDED.Elevation_m,
    Slope_deg = EXCLUDED.Slope_deg,
    Aspect = EXCLUDED.Aspect,
    SoilTypeID = EXCLUDED.SoilTypeID,
    ClimateZoneID = EXCLUDED.ClimateZoneID;

DROP TABLE temp_locations;

-- =============================================================================
-- SUMMARY
-- =============================================================================
DO $$
DECLARE
    soil_count INTEGER;
    climate_count INTEGER;
    variant_count INTEGER;
    scenario_count INTEGER;
    species_count INTEGER;
    sensor_type_count INTEGER;
    location_count INTEGER;
    tree_status_count INTEGER;
    taper_type_count INTEGER;
    straightness_count INTEGER;
    branching_count INTEGER;
    bark_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO soil_count FROM shared.SoilTypes;
    SELECT COUNT(*) INTO climate_count FROM shared.ClimateZones;
    SELECT COUNT(*) INTO variant_count FROM shared.VariantTypes;
    SELECT COUNT(*) INTO scenario_count FROM shared.Scenarios;
    SELECT COUNT(*) INTO species_count FROM shared.Species;
    SELECT COUNT(*) INTO sensor_type_count FROM sensor.SensorTypes;
    SELECT COUNT(*) INTO location_count FROM shared.Locations;
    SELECT COUNT(*) INTO tree_status_count FROM trees.TreeStatus;
    SELECT COUNT(*) INTO taper_type_count FROM trees.TaperTypes;
    SELECT COUNT(*) INTO straightness_count FROM trees.StraightnessTypes;
    SELECT COUNT(*) INTO branching_count FROM trees.BranchingPatterns;
    SELECT COUNT(*) INTO bark_count FROM trees.BarkCharacteristics;
    
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Lookup Tables Loaded from CSV';
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Shared Schema:';
    RAISE NOTICE '  Soil Types:       % rows', soil_count;
    RAISE NOTICE '  Climate Zones:    % rows', climate_count;
    RAISE NOTICE '  Variant Types:    % rows', variant_count;
    RAISE NOTICE '  Scenarios:        % rows', scenario_count;
    RAISE NOTICE '  Species:          % rows', species_count;
    RAISE NOTICE '  Locations:        % rows', location_count;
    RAISE NOTICE 'Sensor Schema:';
    RAISE NOTICE '  Sensor Types:     % rows', sensor_type_count;
    RAISE NOTICE 'Trees Schema:';
    RAISE NOTICE '  Tree Status:      % rows', tree_status_count;
    RAISE NOTICE '  Taper Types:      % rows', taper_type_count;
    RAISE NOTICE '  Straightness:     % rows', straightness_count;
    RAISE NOTICE '  Branching:        % rows', branching_count;
    RAISE NOTICE '  Bark Types:       % rows', bark_count;
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Edit CSV files in data/lookups/ and rebuild to update';
    RAISE NOTICE '=======================================================';
END $$;
