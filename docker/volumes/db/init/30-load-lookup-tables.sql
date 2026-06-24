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
    IsDeciduous BOOLEAN,
    GBIFKey INTEGER,
    GBIFAcceptedName VARCHAR(200)
);

\copy temp_species FROM '/var/lib/postgresql/lookups/species.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.Species (CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance, IsDeciduous, GBIFKey, GBIFAcceptedName)
SELECT CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance, IsDeciduous, GBIFKey, GBIFAcceptedName
FROM temp_species
ON CONFLICT (ScientificName) DO UPDATE SET
    CommonName = EXCLUDED.CommonName,
    MaxHeight_m = EXCLUDED.MaxHeight_m,
    MaxDBH_cm = EXCLUDED.MaxDBH_cm,
    TypicalLifespan_years = EXCLUDED.TypicalLifespan_years,
    GrowthRate = EXCLUDED.GrowthRate,
    ShadeTolerance = EXCLUDED.ShadeTolerance,
    IsDeciduous = EXCLUDED.IsDeciduous,
    GBIFKey = EXCLUDED.GBIFKey,
    GBIFAcceptedName = EXCLUDED.GBIFAcceptedName;

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
-- LOAD PLOTS
-- =============================================================================
-- Create plots for each research location.
-- PlotNumber corresponds to the local plot identifier used in field campaigns.

-- EcoSense plots 1-18 at the Ecosense_MixedPlot location
INSERT INTO shared.Plots (LocationID, PlotName, PlotNumber, CreatedBy)
SELECT 
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'Ecosense_MixedPlot'),
    'EcoSense Plot ' || n,
    n,
    'init'
FROM generate_series(1, 18) AS n
ON CONFLICT (LocationID, PlotName) DO NOTHING;

-- Mathisle single plot
INSERT INTO shared.Plots (LocationID, PlotName, PlotNumber, CreatedBy)
VALUES (
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'Mathisle'),
    'Mathisle',
    1,
    'init'
)
ON CONFLICT (LocationID, PlotName) DO NOTHING;

-- =============================================================================
-- LOAD PHANEROPHYTE HEIGHT CLASSES (Tree Morphology)
-- =============================================================================
CREATE TEMP TABLE temp_height_classes (
    HeightClassName VARCHAR(50),
    Description TEXT,
    MinHeight_m NUMERIC(6, 2),
    MaxHeight_m NUMERIC(6, 2)
);

\copy temp_height_classes FROM '/var/lib/postgresql/lookups/phanerophyte_height_classes.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.PhanerophyteHeightClasses (HeightClassName, Description, MinHeight_m, MaxHeight_m)
SELECT HeightClassName, Description, MinHeight_m, MaxHeight_m FROM temp_height_classes
ON CONFLICT (HeightClassName) DO UPDATE SET 
    Description = EXCLUDED.Description,
    MinHeight_m = EXCLUDED.MinHeight_m,
    MaxHeight_m = EXCLUDED.MaxHeight_m;

DROP TABLE temp_height_classes;

-- =============================================================================
-- LOAD CROWN ARCHITECTURES
-- =============================================================================
CREATE TEMP TABLE temp_crown_architectures (
    CrownArchitectureName VARCHAR(50),
    Description TEXT,
    TypicalExamples TEXT
);

\copy temp_crown_architectures FROM '/var/lib/postgresql/lookups/crown_architectures.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.CrownArchitectures (CrownArchitectureName, Description, TypicalExamples)
SELECT CrownArchitectureName, Description, TypicalExamples FROM temp_crown_architectures
ON CONFLICT (CrownArchitectureName) DO UPDATE SET 
    Description = EXCLUDED.Description,
    TypicalExamples = EXCLUDED.TypicalExamples;

DROP TABLE temp_crown_architectures;

-- =============================================================================
-- LOAD BRANCH ELONGATION HABITS
-- =============================================================================
CREATE TEMP TABLE temp_elongation_habits (
    ElongationHabitName VARCHAR(50),
    Description TEXT
);

\copy temp_elongation_habits FROM '/var/lib/postgresql/lookups/branch_elongation_habits.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.BranchElongationHabits (ElongationHabitName, Description)
SELECT ElongationHabitName, Description FROM temp_elongation_habits
ON CONFLICT (ElongationHabitName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_elongation_habits;

-- =============================================================================
-- LOAD GROWTH ORIENTATIONS
-- =============================================================================
CREATE TEMP TABLE temp_growth_orientations (
    GrowthOrientationName VARCHAR(50),
    Description TEXT
);

\copy temp_growth_orientations FROM '/var/lib/postgresql/lookups/growth_orientations.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.GrowthOrientations (GrowthOrientationName, Description)
SELECT GrowthOrientationName, Description FROM temp_growth_orientations
ON CONFLICT (GrowthOrientationName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_growth_orientations;

-- =============================================================================
-- LOAD SHOOT ELONGATION TYPES
-- =============================================================================
CREATE TEMP TABLE temp_shoot_elongation (
    ShootElongationTypeName VARCHAR(50),
    Description TEXT
);

\copy temp_shoot_elongation FROM '/var/lib/postgresql/lookups/shoot_elongation_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.ShootElongationTypes (ShootElongationTypeName, Description)
SELECT ShootElongationTypeName, Description FROM temp_shoot_elongation
ON CONFLICT (ShootElongationTypeName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_shoot_elongation;

-- =============================================================================
-- LOAD CROWN SHAPES
-- =============================================================================
CREATE TEMP TABLE temp_crown_shapes (
    CrownShapeName VARCHAR(50),
    Description TEXT
);

\copy temp_crown_shapes FROM '/var/lib/postgresql/lookups/crown_shapes.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.CrownShapes (CrownShapeName, Description)
SELECT CrownShapeName, Description FROM temp_crown_shapes
ON CONFLICT (CrownShapeName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_crown_shapes;

-- =============================================================================
-- LOAD GEOMETRIC CROWN SOLIDS
-- =============================================================================
CREATE TEMP TABLE temp_geometric_solids (
    GeometricSolidName VARCHAR(50),
    Description TEXT,
    RelativeLateralArea NUMERIC(4, 2),
    RelativeVolume NUMERIC(4, 2),
    RelativeDrag NUMERIC(4, 2)
);

\copy temp_geometric_solids FROM '/var/lib/postgresql/lookups/geometric_crown_solids.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.GeometricCrownSolids (GeometricSolidName, Description, RelativeLateralArea, RelativeVolume, RelativeDrag)
SELECT GeometricSolidName, Description, RelativeLateralArea, RelativeVolume, RelativeDrag FROM temp_geometric_solids
ON CONFLICT (GeometricSolidName) DO UPDATE SET 
    Description = EXCLUDED.Description,
    RelativeLateralArea = EXCLUDED.RelativeLateralArea,
    RelativeVolume = EXCLUDED.RelativeVolume,
    RelativeDrag = EXCLUDED.RelativeDrag;

DROP TABLE temp_geometric_solids;

-- =============================================================================
-- LOAD AXIS STRUCTURES
-- =============================================================================
CREATE TEMP TABLE temp_axis_structures (
    AxisStructureName VARCHAR(50),
    Description TEXT
);

\copy temp_axis_structures FROM '/var/lib/postgresql/lookups/axis_structures.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.AxisStructures (AxisStructureName, Description)
SELECT AxisStructureName, Description FROM temp_axis_structures
ON CONFLICT (AxisStructureName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_axis_structures;

-- =============================================================================
-- LOAD GROWTH FORMS
-- =============================================================================
CREATE TEMP TABLE temp_growth_forms (
    GrowthFormName VARCHAR(50),
    Description TEXT
);

\copy temp_growth_forms FROM '/var/lib/postgresql/lookups/growth_forms.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.GrowthForms (GrowthFormName, Description)
SELECT GrowthFormName, Description FROM temp_growth_forms
ON CONFLICT (GrowthFormName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_growth_forms;

-- =============================================================================
-- LOAD DATASOURCE TYPES
-- =============================================================================
CREATE TEMP TABLE temp_datasource_types (
    DataSourceTypeName VARCHAR(50),
    Description TEXT
);

\copy temp_datasource_types FROM '/var/lib/postgresql/lookups/datasource_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.DataSourceTypes (DataSourceTypeName, Description)
SELECT DataSourceTypeName, Description FROM temp_datasource_types
ON CONFLICT (DataSourceTypeName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_datasource_types;

-- =============================================================================
-- LOAD CROWN CLASSES
-- =============================================================================
CREATE TEMP TABLE temp_crown_classes (
    CrownClassName VARCHAR(50),
    Description TEXT
);

\copy temp_crown_classes FROM '/var/lib/postgresql/lookups/crown_classes.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.CrownClasses (CrownClassName, Description)
SELECT CrownClassName, Description FROM temp_crown_classes
ON CONFLICT (CrownClassName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_crown_classes;

-- =============================================================================
-- LOAD DAMAGE AGENTS
-- =============================================================================
CREATE TEMP TABLE temp_damage_agents (
    DamageAgentName VARCHAR(50),
    Description TEXT
);

\copy temp_damage_agents FROM '/var/lib/postgresql/lookups/damage_agents.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.DamageAgents (DamageAgentName, Description)
SELECT DamageAgentName, Description FROM temp_damage_agents
ON CONFLICT (DamageAgentName) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_damage_agents;

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
    datasource_type_count INTEGER;
    height_class_count INTEGER;
    crown_arch_count INTEGER;
    elongation_count INTEGER;
    growth_orient_count INTEGER;
    shoot_elong_count INTEGER;
    crown_shape_count INTEGER;
    geo_solid_count INTEGER;
    axis_struct_count INTEGER;
    growth_form_count INTEGER;
    crown_class_count INTEGER;
    damage_agent_count INTEGER;
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
    SELECT COUNT(*) INTO datasource_type_count FROM trees.DataSourceTypes;
    SELECT COUNT(*) INTO height_class_count FROM trees.PhanerophyteHeightClasses;
    SELECT COUNT(*) INTO crown_arch_count FROM trees.CrownArchitectures;
    SELECT COUNT(*) INTO elongation_count FROM trees.BranchElongationHabits;
    SELECT COUNT(*) INTO growth_orient_count FROM trees.GrowthOrientations;
    SELECT COUNT(*) INTO shoot_elong_count FROM trees.ShootElongationTypes;
    SELECT COUNT(*) INTO crown_shape_count FROM trees.CrownShapes;
    SELECT COUNT(*) INTO geo_solid_count FROM trees.GeometricCrownSolids;
    SELECT COUNT(*) INTO axis_struct_count FROM trees.AxisStructures;
    SELECT COUNT(*) INTO growth_form_count FROM trees.GrowthForms;
    SELECT COUNT(*) INTO crown_class_count FROM trees.CrownClasses;
    SELECT COUNT(*) INTO damage_agent_count FROM trees.DamageAgents;

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
    RAISE NOTICE '  DataSource Types: % rows', datasource_type_count;
    RAISE NOTICE 'Tree Morphology (from tree_anatomy.pdf):';
    RAISE NOTICE '  Height Classes:   % rows', height_class_count;
    RAISE NOTICE '  Crown Arch:       % rows', crown_arch_count;
    RAISE NOTICE '  Elongation:       % rows', elongation_count;
    RAISE NOTICE '  Growth Orient:    % rows', growth_orient_count;
    RAISE NOTICE '  Shoot Elong:      % rows', shoot_elong_count;
    RAISE NOTICE '  Crown Shapes:     % rows', crown_shape_count;
    RAISE NOTICE '  Geo Solids:       % rows', geo_solid_count;
    RAISE NOTICE '  Axis Struct:      % rows', axis_struct_count;
    RAISE NOTICE '  Growth Forms:     % rows', growth_form_count;
    RAISE NOTICE 'Tree Condition (FIA/NEON/ICP Forests-aligned):';
    RAISE NOTICE '  Crown Classes:    % rows', crown_class_count;
    RAISE NOTICE '  Damage Agents:    % rows', damage_agent_count;
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Edit CSV files in data/lookups/ and rebuild to update';
    RAISE NOTICE '=======================================================';
END $$;
