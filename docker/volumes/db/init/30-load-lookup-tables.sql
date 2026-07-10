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
    soil_type_name VARCHAR(100),
    Description TEXT
);

\copy temp_soil_types FROM '/var/lib/postgresql/lookups/soil_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.SoilTypes (soil_type_name, Description)
SELECT soil_type_name, Description FROM temp_soil_types
ON CONFLICT (soil_type_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_soil_types;

-- =============================================================================
-- LOAD CLIMATE ZONES
-- =============================================================================
CREATE TEMP TABLE temp_climate_zones (
    climate_zone_name VARCHAR(10),
    Description TEXT
);

\copy temp_climate_zones FROM '/var/lib/postgresql/lookups/climate_zones.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.ClimateZones (climate_zone_name, Description)
SELECT climate_zone_name, Description FROM temp_climate_zones
ON CONFLICT (climate_zone_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_climate_zones;

-- =============================================================================
-- LOAD VARIANT TYPES
-- =============================================================================
CREATE TEMP TABLE temp_variant_types (
    variant_type_name VARCHAR(100),
    Description TEXT
);

\copy temp_variant_types FROM '/var/lib/postgresql/lookups/variant_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.VariantTypes (variant_type_name, Description)
SELECT variant_type_name, Description FROM temp_variant_types
ON CONFLICT (variant_type_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_variant_types;

-- =============================================================================
-- SCENARIOS — intentionally NOT seeded here.
-- Scenarios are location-scoped (Location -> Scenario -> Variant, see
-- 37-scenario-variant-hierarchy.sql) and are created per site by the growth-
-- variant seed scripts (scripts/seed/{ecosense,mathisle}_growth_variants.sql),
-- each owning its baseline. A global scenarios.csv no longer fits the model.
-- =============================================================================

-- =============================================================================
-- LOAD SPECIES
-- =============================================================================
CREATE TEMP TABLE temp_species (
    common_name VARCHAR(200),
    scientific_name VARCHAR(200),
    max_height_m NUMERIC(6, 2),
    max_dbh_cm NUMERIC(6, 2),
    typical_lifespan_years INTEGER,
    growth_rate VARCHAR(20),
    shade_tolerance VARCHAR(20),
    is_deciduous BOOLEAN,
    gbif_key INTEGER,
    gbif_accepted_name VARCHAR(200)
);

\copy temp_species FROM '/var/lib/postgresql/lookups/species.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.Species (common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name)
SELECT common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name
FROM temp_species
ON CONFLICT (scientific_name) DO UPDATE SET
    common_name = EXCLUDED.common_name,
    max_height_m = EXCLUDED.max_height_m,
    max_dbh_cm = EXCLUDED.max_dbh_cm,
    typical_lifespan_years = EXCLUDED.typical_lifespan_years,
    growth_rate = EXCLUDED.growth_rate,
    shade_tolerance = EXCLUDED.shade_tolerance,
    is_deciduous = EXCLUDED.is_deciduous,
    gbif_key = EXCLUDED.gbif_key,
    gbif_accepted_name = EXCLUDED.gbif_accepted_name;

DROP TABLE temp_species;

-- =============================================================================
-- LOAD SENSOR TYPES
-- =============================================================================
CREATE TEMP TABLE temp_sensor_types (
    sensor_type_name VARCHAR(100),
    Description TEXT,
    typical_unit VARCHAR(50),
    typical_range_min NUMERIC(12, 4),
    typical_range_max NUMERIC(12, 4)
);

\copy temp_sensor_types FROM '/var/lib/postgresql/lookups/sensor_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO sensor.SensorTypes (sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max)
SELECT sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max 
FROM temp_sensor_types
ON CONFLICT (sensor_type_name) DO UPDATE SET
    Description = EXCLUDED.Description,
    typical_unit = EXCLUDED.typical_unit,
    typical_range_min = EXCLUDED.typical_range_min,
    typical_range_max = EXCLUDED.typical_range_max;

DROP TABLE temp_sensor_types;

-- =============================================================================
-- LOAD TREE STATUS
-- =============================================================================
CREATE TEMP TABLE temp_tree_status (
    tree_status_name VARCHAR(100),
    Description TEXT
);

\copy temp_tree_status FROM '/var/lib/postgresql/lookups/tree_status.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.TreeStatus (tree_status_name, Description)
SELECT tree_status_name, Description FROM temp_tree_status
ON CONFLICT (tree_status_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_tree_status;

-- =============================================================================
-- LOAD TAPER TYPES
-- =============================================================================
CREATE TEMP TABLE temp_taper_types (
    taper_type_name VARCHAR(100),
    Description TEXT,
    typical_taper_ratio_min NUMERIC(4, 3),
    typical_taper_ratio_max NUMERIC(4, 3)
);

\copy temp_taper_types FROM '/var/lib/postgresql/lookups/taper_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.TaperTypes (taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max)
SELECT taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max FROM temp_taper_types
ON CONFLICT (taper_type_name) DO UPDATE SET 
    Description = EXCLUDED.Description,
    typical_taper_ratio_min = EXCLUDED.typical_taper_ratio_min,
    typical_taper_ratio_max = EXCLUDED.typical_taper_ratio_max;

DROP TABLE temp_taper_types;

-- =============================================================================
-- LOAD STRAIGHTNESS TYPES
-- =============================================================================
CREATE TEMP TABLE temp_straightness_types (
    straightness_name VARCHAR(100),
    Description TEXT,
    deviation_angle_min NUMERIC(5, 2),
    deviation_angle_max NUMERIC(5, 2)
);

\copy temp_straightness_types FROM '/var/lib/postgresql/lookups/straightness_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.StraightnessTypes (straightness_name, Description, deviation_angle_min, deviation_angle_max)
SELECT straightness_name, Description, deviation_angle_min, deviation_angle_max FROM temp_straightness_types
ON CONFLICT (straightness_name) DO UPDATE SET 
    Description = EXCLUDED.Description,
    deviation_angle_min = EXCLUDED.deviation_angle_min,
    deviation_angle_max = EXCLUDED.deviation_angle_max;

DROP TABLE temp_straightness_types;

-- =============================================================================
-- LOAD BRANCHING PATTERNS
-- =============================================================================
CREATE TEMP TABLE temp_branching_patterns (
    branching_pattern_name VARCHAR(100),
    Description TEXT
);

\copy temp_branching_patterns FROM '/var/lib/postgresql/lookups/branching_patterns.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.BranchingPatterns (branching_pattern_name, Description)
SELECT branching_pattern_name, Description FROM temp_branching_patterns
ON CONFLICT (branching_pattern_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_branching_patterns;

-- =============================================================================
-- LOAD BARK CHARACTERISTICS
-- =============================================================================
CREATE TEMP TABLE temp_bark_characteristics (
    bark_characteristic_name VARCHAR(100),
    Description TEXT,
    typical_species TEXT
);

\copy temp_bark_characteristics FROM '/var/lib/postgresql/lookups/bark_characteristics.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.BarkCharacteristics (bark_characteristic_name, Description, typical_species)
SELECT bark_characteristic_name, Description, typical_species FROM temp_bark_characteristics
ON CONFLICT (bark_characteristic_name) DO UPDATE SET 
    Description = EXCLUDED.Description,
    typical_species = EXCLUDED.typical_species;

DROP TABLE temp_bark_characteristics;

-- =============================================================================
-- LOAD LOCATIONS
-- =============================================================================
CREATE TEMP TABLE temp_locations (
    location_name VARCHAR(200),
    Description TEXT,
    CenterLongitude NUMERIC(10, 6),
    CenterLatitude NUMERIC(10, 6),
    Elevation_m NUMERIC(8, 2),
    Slope_deg NUMERIC(5, 2),
    Aspect VARCHAR(3),
    soil_type_name VARCHAR(100),
    climate_zone_name VARCHAR(10)
);

\copy temp_locations FROM '/var/lib/postgresql/lookups/locations.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO shared.Locations (location_name, Description, center_point, Elevation_m, Slope_deg, Aspect, soil_type_id, climate_zone_id)
SELECT 
    t.location_name,
    t.Description,
    CASE WHEN t.CenterLongitude IS NOT NULL AND t.CenterLatitude IS NOT NULL 
         THEN extensions.ST_SetSRID(extensions.ST_MakePoint(t.CenterLongitude, t.CenterLatitude), 4326)
         ELSE NULL 
    END,
    t.Elevation_m,
    t.Slope_deg,
    t.Aspect,
    (SELECT soil_type_id FROM shared.SoilTypes WHERE soil_type_name = t.soil_type_name),
    (SELECT climate_zone_id FROM shared.ClimateZones WHERE climate_zone_name = t.climate_zone_name)
FROM temp_locations t
ON CONFLICT (location_name) DO UPDATE SET
    Description = EXCLUDED.Description,
    center_point = EXCLUDED.center_point,
    Elevation_m = EXCLUDED.Elevation_m,
    Slope_deg = EXCLUDED.Slope_deg,
    Aspect = EXCLUDED.Aspect,
    soil_type_id = EXCLUDED.soil_type_id,
    climate_zone_id = EXCLUDED.climate_zone_id;

DROP TABLE temp_locations;

-- =============================================================================
-- LOAD PLOTS
-- =============================================================================
-- Create plots for each research location.
-- plot_number corresponds to the local plot identifier used in field campaigns.

-- Ecosense tree subplots 1-18 (the field survey grid) under the ecosense site.
-- plot_number matches the import CSV's plot_id; import_trees.py resolves plots by
-- (location_id, plot_number) so a clean rebuild stays consistent. The named
-- monitoring plots (mixed_plot, douglas_fir_plot, ...) are created separately by
-- 36-restructure-locations-plots-snakecase.sql for the sensor layer.
INSERT INTO shared.Plots (location_id, plot_name, plot_number, created_by)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'ecosense'),
    'ecosense_plot_' || n,
    n,
    'init'
FROM generate_series(1, 18) AS n
ON CONFLICT (location_id, plot_name) DO NOTHING;

-- Mathisle single plot (plot_number 1; import CSV plot_id normalised to 1)
INSERT INTO shared.Plots (location_id, plot_name, plot_number, created_by)
VALUES (
    (SELECT location_id FROM shared.Locations WHERE location_name = 'mathisle'),
    'mathisle',
    1,
    'init'
)
ON CONFLICT (location_id, plot_name) DO NOTHING;

-- =============================================================================
-- LOAD PHANEROPHYTE HEIGHT CLASSES (Tree Morphology)
-- =============================================================================
CREATE TEMP TABLE temp_height_classes (
    height_class_name VARCHAR(50),
    Description TEXT,
    min_height_m NUMERIC(6, 2),
    max_height_m NUMERIC(6, 2)
);

\copy temp_height_classes FROM '/var/lib/postgresql/lookups/phanerophyte_height_classes.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.PhanerophyteHeightClasses (height_class_name, Description, min_height_m, max_height_m)
SELECT height_class_name, Description, min_height_m, max_height_m FROM temp_height_classes
ON CONFLICT (height_class_name) DO UPDATE SET 
    Description = EXCLUDED.Description,
    min_height_m = EXCLUDED.min_height_m,
    max_height_m = EXCLUDED.max_height_m;

DROP TABLE temp_height_classes;

-- =============================================================================
-- LOAD CROWN ARCHITECTURES
-- =============================================================================
CREATE TEMP TABLE temp_crown_architectures (
    crown_architecture_name VARCHAR(50),
    Description TEXT,
    typical_examples TEXT
);

\copy temp_crown_architectures FROM '/var/lib/postgresql/lookups/crown_architectures.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.CrownArchitectures (crown_architecture_name, Description, typical_examples)
SELECT crown_architecture_name, Description, typical_examples FROM temp_crown_architectures
ON CONFLICT (crown_architecture_name) DO UPDATE SET 
    Description = EXCLUDED.Description,
    typical_examples = EXCLUDED.typical_examples;

DROP TABLE temp_crown_architectures;

-- =============================================================================
-- LOAD BRANCH ELONGATION HABITS
-- =============================================================================
CREATE TEMP TABLE temp_elongation_habits (
    elongation_habit_name VARCHAR(50),
    Description TEXT
);

\copy temp_elongation_habits FROM '/var/lib/postgresql/lookups/branch_elongation_habits.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.BranchElongationHabits (elongation_habit_name, Description)
SELECT elongation_habit_name, Description FROM temp_elongation_habits
ON CONFLICT (elongation_habit_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_elongation_habits;

-- =============================================================================
-- LOAD GROWTH ORIENTATIONS
-- =============================================================================
CREATE TEMP TABLE temp_growth_orientations (
    growth_orientation_name VARCHAR(50),
    Description TEXT
);

\copy temp_growth_orientations FROM '/var/lib/postgresql/lookups/growth_orientations.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.GrowthOrientations (growth_orientation_name, Description)
SELECT growth_orientation_name, Description FROM temp_growth_orientations
ON CONFLICT (growth_orientation_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_growth_orientations;

-- =============================================================================
-- LOAD SHOOT ELONGATION TYPES
-- =============================================================================
CREATE TEMP TABLE temp_shoot_elongation (
    shoot_elongation_type_name VARCHAR(50),
    Description TEXT
);

\copy temp_shoot_elongation FROM '/var/lib/postgresql/lookups/shoot_elongation_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.ShootElongationTypes (shoot_elongation_type_name, Description)
SELECT shoot_elongation_type_name, Description FROM temp_shoot_elongation
ON CONFLICT (shoot_elongation_type_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_shoot_elongation;

-- =============================================================================
-- LOAD CROWN SHAPES
-- =============================================================================
CREATE TEMP TABLE temp_crown_shapes (
    crown_shape_name VARCHAR(50),
    Description TEXT
);

\copy temp_crown_shapes FROM '/var/lib/postgresql/lookups/crown_shapes.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.CrownShapes (crown_shape_name, Description)
SELECT crown_shape_name, Description FROM temp_crown_shapes
ON CONFLICT (crown_shape_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_crown_shapes;

-- =============================================================================
-- LOAD GEOMETRIC CROWN SOLIDS
-- =============================================================================
CREATE TEMP TABLE temp_geometric_solids (
    geometric_solid_name VARCHAR(50),
    Description TEXT,
    relative_lateral_area NUMERIC(4, 2),
    relative_volume NUMERIC(4, 2),
    relative_drag NUMERIC(4, 2)
);

\copy temp_geometric_solids FROM '/var/lib/postgresql/lookups/geometric_crown_solids.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.GeometricCrownSolids (geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag)
SELECT geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag FROM temp_geometric_solids
ON CONFLICT (geometric_solid_name) DO UPDATE SET 
    Description = EXCLUDED.Description,
    relative_lateral_area = EXCLUDED.relative_lateral_area,
    relative_volume = EXCLUDED.relative_volume,
    relative_drag = EXCLUDED.relative_drag;

DROP TABLE temp_geometric_solids;

-- =============================================================================
-- LOAD AXIS STRUCTURES
-- =============================================================================
CREATE TEMP TABLE temp_axis_structures (
    axis_structure_name VARCHAR(50),
    Description TEXT
);

\copy temp_axis_structures FROM '/var/lib/postgresql/lookups/axis_structures.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.AxisStructures (axis_structure_name, Description)
SELECT axis_structure_name, Description FROM temp_axis_structures
ON CONFLICT (axis_structure_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_axis_structures;

-- =============================================================================
-- LOAD GROWTH FORMS
-- =============================================================================
CREATE TEMP TABLE temp_growth_forms (
    growth_form_name VARCHAR(50),
    Description TEXT
);

\copy temp_growth_forms FROM '/var/lib/postgresql/lookups/growth_forms.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.GrowthForms (growth_form_name, Description)
SELECT growth_form_name, Description FROM temp_growth_forms
ON CONFLICT (growth_form_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_growth_forms;

-- =============================================================================
-- LOAD DATASOURCE TYPES
-- =============================================================================
CREATE TEMP TABLE temp_datasource_types (
    data_source_type_name VARCHAR(50),
    Description TEXT
);

\copy temp_datasource_types FROM '/var/lib/postgresql/lookups/datasource_types.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.DataSourceTypes (data_source_type_name, Description)
SELECT data_source_type_name, Description FROM temp_datasource_types
ON CONFLICT (data_source_type_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_datasource_types;

-- =============================================================================
-- LOAD CROWN CLASSES
-- =============================================================================
CREATE TEMP TABLE temp_crown_classes (
    crown_class_name VARCHAR(50),
    Description TEXT
);

\copy temp_crown_classes FROM '/var/lib/postgresql/lookups/crown_classes.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.CrownClasses (crown_class_name, Description)
SELECT crown_class_name, Description FROM temp_crown_classes
ON CONFLICT (crown_class_name) DO UPDATE SET Description = EXCLUDED.Description;

DROP TABLE temp_crown_classes;

-- =============================================================================
-- LOAD DAMAGE AGENTS
-- =============================================================================
CREATE TEMP TABLE temp_damage_agents (
    damage_agent_name VARCHAR(50),
    Description TEXT
);

\copy temp_damage_agents FROM '/var/lib/postgresql/lookups/damage_agents.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO trees.DamageAgents (damage_agent_name, Description)
SELECT damage_agent_name, Description FROM temp_damage_agents
ON CONFLICT (damage_agent_name) DO UPDATE SET Description = EXCLUDED.Description;

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
