-- Refresh Lookup Tables Functions
-- Provides functions to reload lookup data from CSV files without full database rebuild
--
-- Usage:
--   SELECT shared.refresh_all_lookups();          -- Reload all lookup tables
--   SELECT shared.refresh_lookup('species');      -- Reload specific table
--
-- NOTE: CSV files must be mounted at /var/lib/postgresql/lookups/

SET search_path TO shared, sensor, trees, public;

-- =============================================================================
-- MAIN REFRESH FUNCTION
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.refresh_lookup(p_table_name TEXT)
RETURNS TABLE(table_name TEXT, rows_before INT, rows_after INT, status TEXT) AS $$
DECLARE
    v_rows_before INT;
    v_rows_after INT;
    v_csv_path TEXT;
BEGIN
    -- Normalize table name
    p_table_name := lower(trim(p_table_name));
    
    -- Map table names to CSV files
    v_csv_path := '/var/lib/postgresql/lookups/';
    
    CASE p_table_name
        WHEN 'species' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.species;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_species (
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
            ) ON COMMIT DROP;
            TRUNCATE _temp_species;

            EXECUTE format('COPY _temp_species FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'species.csv');

            INSERT INTO shared.Species (common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name)
            SELECT common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name
            FROM _temp_species
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
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.species;
            
        WHEN 'locations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.locations;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_locations (
                location_name VARCHAR(200),
                Description TEXT,
                CenterLongitude NUMERIC(10, 6),
                CenterLatitude NUMERIC(10, 6),
                Elevation_m NUMERIC(8, 2),
                Slope_deg NUMERIC(5, 2),
                Aspect VARCHAR(3),
                soil_type_name VARCHAR(100),
                climate_zone_name VARCHAR(10)
            ) ON COMMIT DROP;
            TRUNCATE _temp_locations;
            
            EXECUTE format('COPY _temp_locations FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'locations.csv');
            
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
            FROM _temp_locations t
            ON CONFLICT (location_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                center_point = EXCLUDED.center_point,
                Elevation_m = EXCLUDED.Elevation_m,
                Slope_deg = EXCLUDED.Slope_deg,
                Aspect = EXCLUDED.Aspect,
                soil_type_id = EXCLUDED.soil_type_id,
                climate_zone_id = EXCLUDED.climate_zone_id;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.locations;
            
        WHEN 'sensor_types', 'sensortypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM sensor.sensortypes;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_sensor_types (
                sensor_type_name VARCHAR(100),
                Description TEXT,
                typical_unit VARCHAR(50),
                typical_range_min NUMERIC(12, 4),
                typical_range_max NUMERIC(12, 4)
            ) ON COMMIT DROP;
            TRUNCATE _temp_sensor_types;
            
            EXECUTE format('COPY _temp_sensor_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'sensor_types.csv');
            
            INSERT INTO sensor.SensorTypes (sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max)
            SELECT sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max 
            FROM _temp_sensor_types
            ON CONFLICT (sensor_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_unit = EXCLUDED.typical_unit,
                typical_range_min = EXCLUDED.typical_range_min,
                typical_range_max = EXCLUDED.typical_range_max;
            
            SELECT COUNT(*) INTO v_rows_after FROM sensor.sensortypes;
            p_table_name := 'sensor_types';
            
        WHEN 'tree_status', 'treestatus' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.treestatus;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_tree_status (
                tree_status_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_tree_status;
            
            EXECUTE format('COPY _temp_tree_status FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'tree_status.csv');
            
            INSERT INTO trees.TreeStatus (tree_status_name, Description)
            SELECT tree_status_name, Description FROM _temp_tree_status
            ON CONFLICT (tree_status_name) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM trees.treestatus;
            p_table_name := 'tree_status';
            
        WHEN 'soil_types', 'soiltypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.soiltypes;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_soil_types (
                soil_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_soil_types;
            
            EXECUTE format('COPY _temp_soil_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'soil_types.csv');
            
            INSERT INTO shared.SoilTypes (soil_type_name, Description)
            SELECT soil_type_name, Description FROM _temp_soil_types
            ON CONFLICT (soil_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.soiltypes;
            p_table_name := 'soil_types';
            
        WHEN 'climate_zones', 'climatezones' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.climatezones;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_climate_zones (
                climate_zone_name VARCHAR(10),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_climate_zones;
            
            EXECUTE format('COPY _temp_climate_zones FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'climate_zones.csv');
            
            INSERT INTO shared.ClimateZones (climate_zone_name, Description)
            SELECT climate_zone_name, Description FROM _temp_climate_zones
            ON CONFLICT (climate_zone_name) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.climatezones;
            p_table_name := 'climate_zones';
            
        WHEN 'variant_types', 'varianttypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.varianttypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_variant_types (
                variant_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_variant_types;

            EXECUTE format('COPY _temp_variant_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'variant_types.csv');

            INSERT INTO shared.VariantTypes (variant_type_name, Description)
            SELECT variant_type_name, Description FROM _temp_variant_types
            ON CONFLICT (variant_type_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM shared.varianttypes;
            p_table_name := 'variant_types';

        WHEN 'scenarios' THEN
            -- Scenarios are location-scoped (Scenarios.location_id NOT NULL,
            -- UNIQUE(location_id, scenario_name)) and are created per site by the
            -- growth-variant seed scripts — not a refreshable global lookup CSV.
            SELECT COUNT(*) INTO v_rows_before FROM shared.scenarios;
            RAISE NOTICE 'scenarios are location-scoped; not refreshed from a global CSV (skipped)';
            v_rows_after := v_rows_before;

        WHEN 'taper_types', 'tapertypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.tapertypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_taper_types (
                taper_type_name VARCHAR(100),
                Description TEXT,
                typical_taper_ratio_min NUMERIC(4, 3),
                typical_taper_ratio_max NUMERIC(4, 3)
            ) ON COMMIT DROP;
            TRUNCATE _temp_taper_types;

            EXECUTE format('COPY _temp_taper_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'taper_types.csv');

            INSERT INTO trees.TaperTypes (taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max)
            SELECT taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max FROM _temp_taper_types
            ON CONFLICT (taper_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_taper_ratio_min = EXCLUDED.typical_taper_ratio_min,
                typical_taper_ratio_max = EXCLUDED.typical_taper_ratio_max;

            SELECT COUNT(*) INTO v_rows_after FROM trees.tapertypes;
            p_table_name := 'taper_types';

        WHEN 'straightness_types', 'straightnesstypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.straightnesstypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_straightness_types (
                straightness_name VARCHAR(100),
                Description TEXT,
                deviation_angle_min NUMERIC(5, 2),
                deviation_angle_max NUMERIC(5, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_straightness_types;

            EXECUTE format('COPY _temp_straightness_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'straightness_types.csv');

            INSERT INTO trees.StraightnessTypes (straightness_name, Description, deviation_angle_min, deviation_angle_max)
            SELECT straightness_name, Description, deviation_angle_min, deviation_angle_max FROM _temp_straightness_types
            ON CONFLICT (straightness_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                deviation_angle_min = EXCLUDED.deviation_angle_min,
                deviation_angle_max = EXCLUDED.deviation_angle_max;

            SELECT COUNT(*) INTO v_rows_after FROM trees.straightnesstypes;
            p_table_name := 'straightness_types';

        WHEN 'branching_patterns', 'branchingpatterns' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branchingpatterns;

            CREATE TEMP TABLE IF NOT EXISTS _temp_branching_patterns (
                branching_pattern_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_branching_patterns;

            EXECUTE format('COPY _temp_branching_patterns FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branching_patterns.csv');

            INSERT INTO trees.BranchingPatterns (branching_pattern_name, Description)
            SELECT branching_pattern_name, Description FROM _temp_branching_patterns
            ON CONFLICT (branching_pattern_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.branchingpatterns;
            p_table_name := 'branching_patterns';

        WHEN 'bark_characteristics', 'barkcharacteristics' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.barkcharacteristics;

            CREATE TEMP TABLE IF NOT EXISTS _temp_bark_characteristics (
                bark_characteristic_name VARCHAR(100),
                Description TEXT,
                typical_species TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_bark_characteristics;

            EXECUTE format('COPY _temp_bark_characteristics FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'bark_characteristics.csv');

            INSERT INTO trees.BarkCharacteristics (bark_characteristic_name, Description, typical_species)
            SELECT bark_characteristic_name, Description, typical_species FROM _temp_bark_characteristics
            ON CONFLICT (bark_characteristic_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_species = EXCLUDED.typical_species;

            SELECT COUNT(*) INTO v_rows_after FROM trees.barkcharacteristics;
            p_table_name := 'bark_characteristics';

        WHEN 'datasource_types', 'datasourcetypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.datasourcetypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_datasource_types (
                data_source_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_datasource_types;

            EXECUTE format('COPY _temp_datasource_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'datasource_types.csv');

            INSERT INTO trees.DataSourceTypes (data_source_type_name, Description)
            SELECT data_source_type_name, Description FROM _temp_datasource_types
            ON CONFLICT (data_source_type_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.datasourcetypes;
            p_table_name := 'datasource_types';

        -- =====================================================================
        -- TREE MORPHOLOGY TABLES (from tree_anatomy.pdf)
        -- =====================================================================

        WHEN 'height_classes', 'phanerophyte_height_classes', 'phanerophyteheightclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.phanerophyteheightclasses;

            CREATE TEMP TABLE IF NOT EXISTS _temp_height_classes (
                height_class_name VARCHAR(50),
                Description TEXT,
                min_height_m NUMERIC(6, 2),
                max_height_m NUMERIC(6, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_height_classes;

            EXECUTE format('COPY _temp_height_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'phanerophyte_height_classes.csv');

            INSERT INTO trees.PhanerophyteHeightClasses (height_class_name, Description, min_height_m, max_height_m)
            SELECT height_class_name, Description, min_height_m, max_height_m FROM _temp_height_classes
            ON CONFLICT (height_class_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                min_height_m = EXCLUDED.min_height_m,
                max_height_m = EXCLUDED.max_height_m;

            SELECT COUNT(*) INTO v_rows_after FROM trees.phanerophyteheightclasses;
            p_table_name := 'height_classes';

        WHEN 'crown_architectures', 'crownarchitectures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownarchitectures;

            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_arch (
                crown_architecture_name VARCHAR(50),
                Description TEXT,
                typical_examples TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_arch;

            EXECUTE format('COPY _temp_crown_arch FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_architectures.csv');

            INSERT INTO trees.CrownArchitectures (crown_architecture_name, Description, typical_examples)
            SELECT crown_architecture_name, Description, typical_examples FROM _temp_crown_arch
            ON CONFLICT (crown_architecture_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_examples = EXCLUDED.typical_examples;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownarchitectures;
            p_table_name := 'crown_architectures';

        WHEN 'branch_elongation_habits', 'branchelongationhabits', 'elongation_habits' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branchelongationhabits;

            CREATE TEMP TABLE IF NOT EXISTS _temp_elongation (
                elongation_habit_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_elongation;

            EXECUTE format('COPY _temp_elongation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branch_elongation_habits.csv');

            INSERT INTO trees.BranchElongationHabits (elongation_habit_name, Description)
            SELECT elongation_habit_name, Description FROM _temp_elongation
            ON CONFLICT (elongation_habit_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.branchelongationhabits;
            p_table_name := 'branch_elongation_habits';

        WHEN 'growth_orientations', 'growthorientations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growthorientations;

            CREATE TEMP TABLE IF NOT EXISTS _temp_orientation (
                growth_orientation_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_orientation;

            EXECUTE format('COPY _temp_orientation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_orientations.csv');

            INSERT INTO trees.GrowthOrientations (growth_orientation_name, Description)
            SELECT growth_orientation_name, Description FROM _temp_orientation
            ON CONFLICT (growth_orientation_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.growthorientations;
            p_table_name := 'growth_orientations';

        WHEN 'shoot_elongation_types', 'shootelongationtypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.shootelongationtypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_shoot (
                shoot_elongation_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shoot;

            EXECUTE format('COPY _temp_shoot FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'shoot_elongation_types.csv');

            INSERT INTO trees.ShootElongationTypes (shoot_elongation_type_name, Description)
            SELECT shoot_elongation_type_name, Description FROM _temp_shoot
            ON CONFLICT (shoot_elongation_type_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.shootelongationtypes;
            p_table_name := 'shoot_elongation_types';

        WHEN 'crown_shapes', 'crownshapes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownshapes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_shapes (
                crown_shape_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shapes;

            EXECUTE format('COPY _temp_shapes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_shapes.csv');

            INSERT INTO trees.CrownShapes (crown_shape_name, Description)
            SELECT crown_shape_name, Description FROM _temp_shapes
            ON CONFLICT (crown_shape_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownshapes;
            p_table_name := 'crown_shapes';

        WHEN 'geometric_crown_solids', 'geometriccrownsolids', 'geometric_solids' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.geometriccrownsolids;

            CREATE TEMP TABLE IF NOT EXISTS _temp_solids (
                geometric_solid_name VARCHAR(50),
                Description TEXT,
                relative_lateral_area NUMERIC(4, 2),
                relative_volume NUMERIC(4, 2),
                relative_drag NUMERIC(4, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_solids;

            EXECUTE format('COPY _temp_solids FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'geometric_crown_solids.csv');

            INSERT INTO trees.GeometricCrownSolids (geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag)
            SELECT geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag FROM _temp_solids
            ON CONFLICT (geometric_solid_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                relative_lateral_area = EXCLUDED.relative_lateral_area,
                relative_volume = EXCLUDED.relative_volume,
                relative_drag = EXCLUDED.relative_drag;

            SELECT COUNT(*) INTO v_rows_after FROM trees.geometriccrownsolids;
            p_table_name := 'geometric_crown_solids';

        WHEN 'axis_structures', 'axisstructures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.axisstructures;

            CREATE TEMP TABLE IF NOT EXISTS _temp_axis (
                axis_structure_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_axis;

            EXECUTE format('COPY _temp_axis FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'axis_structures.csv');

            INSERT INTO trees.AxisStructures (axis_structure_name, Description)
            SELECT axis_structure_name, Description FROM _temp_axis
            ON CONFLICT (axis_structure_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.axisstructures;
            p_table_name := 'axis_structures';

        WHEN 'growth_forms', 'growthforms' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growthforms;

            CREATE TEMP TABLE IF NOT EXISTS _temp_forms (
                growth_form_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_forms;

            EXECUTE format('COPY _temp_forms FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_forms.csv');

            INSERT INTO trees.GrowthForms (growth_form_name, Description)
            SELECT growth_form_name, Description FROM _temp_forms
            ON CONFLICT (growth_form_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.growthforms;
            p_table_name := 'growth_forms';

        -- =====================================================================
        -- TREE CONDITION TABLES (FIA/NEON/ICP Forests-aligned)
        -- =====================================================================

        WHEN 'crown_classes', 'crownclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownclasses;

            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_classes (
                crown_class_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_classes;

            EXECUTE format('COPY _temp_crown_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_classes.csv');

            INSERT INTO trees.CrownClasses (crown_class_name, Description)
            SELECT crown_class_name, Description FROM _temp_crown_classes
            ON CONFLICT (crown_class_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownclasses;
            p_table_name := 'crown_classes';

        WHEN 'damage_agents', 'damageagents' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.damageagents;

            CREATE TEMP TABLE IF NOT EXISTS _temp_damage_agents (
                damage_agent_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_damage_agents;

            EXECUTE format('COPY _temp_damage_agents FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'damage_agents.csv');

            INSERT INTO trees.DamageAgents (damage_agent_name, Description)
            SELECT damage_agent_name, Description FROM _temp_damage_agents
            ON CONFLICT (damage_agent_name) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.damageagents;
            p_table_name := 'damage_agents';

        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0, 'ERROR: Unknown table. Use: species, locations, sensor_types, tree_status, soil_types, climate_zones, variant_types, scenarios, taper_types, straightness_types, branching_patterns, bark_characteristics, datasource_types, height_classes, crown_architectures, branch_elongation_habits, growth_orientations, shoot_elongation_types, crown_shapes, geometric_crown_solids, axis_structures, growth_forms, crown_classes, damage_agents';
            RETURN;
    END CASE;
    
    RETURN QUERY SELECT p_table_name, v_rows_before, v_rows_after, 'OK';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION shared.refresh_lookup IS 'Reload a specific lookup table from its CSV file without full database rebuild';

-- =============================================================================
-- REFRESH ALL LOOKUPS
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.refresh_all_lookups()
RETURNS TABLE(table_name TEXT, rows_before INT, rows_after INT, status TEXT) AS $$
BEGIN
    -- Refresh in dependency order
    RETURN QUERY SELECT * FROM shared.refresh_lookup('soil_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('climate_zones');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('variant_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('scenarios');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('species');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('locations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('sensor_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('tree_status');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('taper_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('straightness_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branching_patterns');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('bark_characteristics');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('datasource_types');
    -- Tree Morphology tables (from tree_anatomy.pdf)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('height_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_architectures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branch_elongation_habits');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_orientations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('shoot_elongation_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_shapes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('geometric_crown_solids');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('axis_structures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_forms');
    -- Tree Condition tables (FIA/NEON/ICP Forests-aligned)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('damage_agents');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION shared.refresh_all_lookups IS 'Reload all lookup tables from CSV files without full database rebuild';

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

GRANT EXECUTE ON FUNCTION shared.refresh_lookup TO service_role;
GRANT EXECUTE ON FUNCTION shared.refresh_all_lookups TO service_role;

-- =============================================================================
-- SUMMARY
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Lookup Refresh Functions Created';
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Usage:';
    RAISE NOTICE '  SELECT * FROM shared.refresh_all_lookups();';
    RAISE NOTICE '  SELECT * FROM shared.refresh_lookup(''species'');';
    RAISE NOTICE '';
    RAISE NOTICE 'Supported tables:';
    RAISE NOTICE '  species, locations, sensor_types, tree_status,';
    RAISE NOTICE '  soil_types, climate_zones, variant_types, scenarios,';
    RAISE NOTICE '  taper_types, straightness_types, branching_patterns,';
    RAISE NOTICE '  bark_characteristics, datasource_types';
    RAISE NOTICE '';
    RAISE NOTICE 'Tree Morphology (from tree_anatomy.pdf):';
    RAISE NOTICE '  height_classes, crown_architectures, branch_elongation_habits,';
    RAISE NOTICE '  growth_orientations, shoot_elongation_types, crown_shapes,';
    RAISE NOTICE '  geometric_crown_solids, axis_structures, growth_forms';
    RAISE NOTICE '';
    RAISE NOTICE 'Tree Condition (FIA/NEON/ICP Forests-aligned):';
    RAISE NOTICE '  crown_classes, damage_agents';
    RAISE NOTICE '=======================================================';
END $$;
