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
            ) ON COMMIT DROP;
            TRUNCATE _temp_species;

            EXECUTE format('COPY _temp_species FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'species.csv');

            INSERT INTO shared.Species (CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance, IsDeciduous, GBIFKey, GBIFAcceptedName)
            SELECT CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance, IsDeciduous, GBIFKey, GBIFAcceptedName
            FROM _temp_species
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
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.species;
            
        WHEN 'locations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.locations;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_locations (
                LocationName VARCHAR(200),
                Description TEXT,
                CenterLongitude NUMERIC(10, 6),
                CenterLatitude NUMERIC(10, 6),
                Elevation_m NUMERIC(8, 2),
                Slope_deg NUMERIC(5, 2),
                Aspect VARCHAR(3),
                SoilTypeName VARCHAR(100),
                ClimateZoneName VARCHAR(10)
            ) ON COMMIT DROP;
            TRUNCATE _temp_locations;
            
            EXECUTE format('COPY _temp_locations FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'locations.csv');
            
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
            FROM _temp_locations t
            ON CONFLICT (LocationName) DO UPDATE SET
                Description = EXCLUDED.Description,
                CenterPoint = EXCLUDED.CenterPoint,
                Elevation_m = EXCLUDED.Elevation_m,
                Slope_deg = EXCLUDED.Slope_deg,
                Aspect = EXCLUDED.Aspect,
                SoilTypeID = EXCLUDED.SoilTypeID,
                ClimateZoneID = EXCLUDED.ClimateZoneID;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.locations;
            
        WHEN 'sensor_types', 'sensortypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM sensor.sensortypes;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_sensor_types (
                SensorTypeName VARCHAR(100),
                Description TEXT,
                TypicalUnit VARCHAR(50),
                TypicalRangeMin NUMERIC(12, 4),
                TypicalRangeMax NUMERIC(12, 4)
            ) ON COMMIT DROP;
            TRUNCATE _temp_sensor_types;
            
            EXECUTE format('COPY _temp_sensor_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'sensor_types.csv');
            
            INSERT INTO sensor.SensorTypes (SensorTypeName, Description, TypicalUnit, TypicalRangeMin, TypicalRangeMax)
            SELECT SensorTypeName, Description, TypicalUnit, TypicalRangeMin, TypicalRangeMax 
            FROM _temp_sensor_types
            ON CONFLICT (SensorTypeName) DO UPDATE SET
                Description = EXCLUDED.Description,
                TypicalUnit = EXCLUDED.TypicalUnit,
                TypicalRangeMin = EXCLUDED.TypicalRangeMin,
                TypicalRangeMax = EXCLUDED.TypicalRangeMax;
            
            SELECT COUNT(*) INTO v_rows_after FROM sensor.sensortypes;
            p_table_name := 'sensor_types';
            
        WHEN 'tree_status', 'treestatus' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.treestatus;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_tree_status (
                TreeStatusName VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_tree_status;
            
            EXECUTE format('COPY _temp_tree_status FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'tree_status.csv');
            
            INSERT INTO trees.TreeStatus (TreeStatusName, Description)
            SELECT TreeStatusName, Description FROM _temp_tree_status
            ON CONFLICT (TreeStatusName) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM trees.treestatus;
            p_table_name := 'tree_status';
            
        WHEN 'soil_types', 'soiltypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.soiltypes;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_soil_types (
                SoilTypeName VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_soil_types;
            
            EXECUTE format('COPY _temp_soil_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'soil_types.csv');
            
            INSERT INTO shared.SoilTypes (SoilTypeName, Description)
            SELECT SoilTypeName, Description FROM _temp_soil_types
            ON CONFLICT (SoilTypeName) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.soiltypes;
            p_table_name := 'soil_types';
            
        WHEN 'climate_zones', 'climatezones' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.climatezones;
            
            CREATE TEMP TABLE IF NOT EXISTS _temp_climate_zones (
                ClimateZoneName VARCHAR(10),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_climate_zones;
            
            EXECUTE format('COPY _temp_climate_zones FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'climate_zones.csv');
            
            INSERT INTO shared.ClimateZones (ClimateZoneName, Description)
            SELECT ClimateZoneName, Description FROM _temp_climate_zones
            ON CONFLICT (ClimateZoneName) DO UPDATE SET Description = EXCLUDED.Description;
            
            SELECT COUNT(*) INTO v_rows_after FROM shared.climatezones;
            p_table_name := 'climate_zones';
            
        WHEN 'variant_types', 'varianttypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.varianttypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_variant_types (
                VariantTypeName VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_variant_types;

            EXECUTE format('COPY _temp_variant_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'variant_types.csv');

            INSERT INTO shared.VariantTypes (VariantTypeName, Description)
            SELECT VariantTypeName, Description FROM _temp_variant_types
            ON CONFLICT (VariantTypeName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM shared.varianttypes;
            p_table_name := 'variant_types';

        WHEN 'scenarios' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.scenarios;

            CREATE TEMP TABLE IF NOT EXISTS _temp_scenarios (
                ScenarioName VARCHAR(200),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_scenarios;

            EXECUTE format('COPY _temp_scenarios FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'scenarios.csv');

            INSERT INTO shared.Scenarios (ScenarioName, Description)
            SELECT ScenarioName, Description FROM _temp_scenarios
            ON CONFLICT (ScenarioName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM shared.scenarios;

        WHEN 'taper_types', 'tapertypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.tapertypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_taper_types (
                TaperTypeName VARCHAR(100),
                Description TEXT,
                TypicalTaperRatioMin NUMERIC(4, 3),
                TypicalTaperRatioMax NUMERIC(4, 3)
            ) ON COMMIT DROP;
            TRUNCATE _temp_taper_types;

            EXECUTE format('COPY _temp_taper_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'taper_types.csv');

            INSERT INTO trees.TaperTypes (TaperTypeName, Description, TypicalTaperRatioMin, TypicalTaperRatioMax)
            SELECT TaperTypeName, Description, TypicalTaperRatioMin, TypicalTaperRatioMax FROM _temp_taper_types
            ON CONFLICT (TaperTypeName) DO UPDATE SET
                Description = EXCLUDED.Description,
                TypicalTaperRatioMin = EXCLUDED.TypicalTaperRatioMin,
                TypicalTaperRatioMax = EXCLUDED.TypicalTaperRatioMax;

            SELECT COUNT(*) INTO v_rows_after FROM trees.tapertypes;
            p_table_name := 'taper_types';

        WHEN 'straightness_types', 'straightnesstypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.straightnesstypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_straightness_types (
                StraightnessName VARCHAR(100),
                Description TEXT,
                DeviationAngleMin NUMERIC(5, 2),
                DeviationAngleMax NUMERIC(5, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_straightness_types;

            EXECUTE format('COPY _temp_straightness_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'straightness_types.csv');

            INSERT INTO trees.StraightnessTypes (StraightnessName, Description, DeviationAngleMin, DeviationAngleMax)
            SELECT StraightnessName, Description, DeviationAngleMin, DeviationAngleMax FROM _temp_straightness_types
            ON CONFLICT (StraightnessName) DO UPDATE SET
                Description = EXCLUDED.Description,
                DeviationAngleMin = EXCLUDED.DeviationAngleMin,
                DeviationAngleMax = EXCLUDED.DeviationAngleMax;

            SELECT COUNT(*) INTO v_rows_after FROM trees.straightnesstypes;
            p_table_name := 'straightness_types';

        WHEN 'branching_patterns', 'branchingpatterns' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branchingpatterns;

            CREATE TEMP TABLE IF NOT EXISTS _temp_branching_patterns (
                BranchingPatternName VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_branching_patterns;

            EXECUTE format('COPY _temp_branching_patterns FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branching_patterns.csv');

            INSERT INTO trees.BranchingPatterns (BranchingPatternName, Description)
            SELECT BranchingPatternName, Description FROM _temp_branching_patterns
            ON CONFLICT (BranchingPatternName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.branchingpatterns;
            p_table_name := 'branching_patterns';

        WHEN 'bark_characteristics', 'barkcharacteristics' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.barkcharacteristics;

            CREATE TEMP TABLE IF NOT EXISTS _temp_bark_characteristics (
                BarkCharacteristicName VARCHAR(100),
                Description TEXT,
                TypicalSpecies TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_bark_characteristics;

            EXECUTE format('COPY _temp_bark_characteristics FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'bark_characteristics.csv');

            INSERT INTO trees.BarkCharacteristics (BarkCharacteristicName, Description, TypicalSpecies)
            SELECT BarkCharacteristicName, Description, TypicalSpecies FROM _temp_bark_characteristics
            ON CONFLICT (BarkCharacteristicName) DO UPDATE SET
                Description = EXCLUDED.Description,
                TypicalSpecies = EXCLUDED.TypicalSpecies;

            SELECT COUNT(*) INTO v_rows_after FROM trees.barkcharacteristics;
            p_table_name := 'bark_characteristics';

        -- =====================================================================
        -- TREE MORPHOLOGY TABLES (from tree_anatomy.pdf)
        -- =====================================================================

        WHEN 'height_classes', 'phanerophyte_height_classes', 'phanerophyteheightclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.phanerophyteheightclasses;

            CREATE TEMP TABLE IF NOT EXISTS _temp_height_classes (
                HeightClassName VARCHAR(50),
                Description TEXT,
                MinHeight_m NUMERIC(6, 2),
                MaxHeight_m NUMERIC(6, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_height_classes;

            EXECUTE format('COPY _temp_height_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'phanerophyte_height_classes.csv');

            INSERT INTO trees.PhanerophyteHeightClasses (HeightClassName, Description, MinHeight_m, MaxHeight_m)
            SELECT HeightClassName, Description, MinHeight_m, MaxHeight_m FROM _temp_height_classes
            ON CONFLICT (HeightClassName) DO UPDATE SET
                Description = EXCLUDED.Description,
                MinHeight_m = EXCLUDED.MinHeight_m,
                MaxHeight_m = EXCLUDED.MaxHeight_m;

            SELECT COUNT(*) INTO v_rows_after FROM trees.phanerophyteheightclasses;
            p_table_name := 'height_classes';

        WHEN 'crown_architectures', 'crownarchitectures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownarchitectures;

            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_arch (
                CrownArchitectureName VARCHAR(50),
                Description TEXT,
                TypicalExamples TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_arch;

            EXECUTE format('COPY _temp_crown_arch FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_architectures.csv');

            INSERT INTO trees.CrownArchitectures (CrownArchitectureName, Description, TypicalExamples)
            SELECT CrownArchitectureName, Description, TypicalExamples FROM _temp_crown_arch
            ON CONFLICT (CrownArchitectureName) DO UPDATE SET
                Description = EXCLUDED.Description,
                TypicalExamples = EXCLUDED.TypicalExamples;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownarchitectures;
            p_table_name := 'crown_architectures';

        WHEN 'branch_elongation_habits', 'branchelongationhabits', 'elongation_habits' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branchelongationhabits;

            CREATE TEMP TABLE IF NOT EXISTS _temp_elongation (
                ElongationHabitName VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_elongation;

            EXECUTE format('COPY _temp_elongation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branch_elongation_habits.csv');

            INSERT INTO trees.BranchElongationHabits (ElongationHabitName, Description)
            SELECT ElongationHabitName, Description FROM _temp_elongation
            ON CONFLICT (ElongationHabitName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.branchelongationhabits;
            p_table_name := 'branch_elongation_habits';

        WHEN 'growth_orientations', 'growthorientations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growthorientations;

            CREATE TEMP TABLE IF NOT EXISTS _temp_orientation (
                GrowthOrientationName VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_orientation;

            EXECUTE format('COPY _temp_orientation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_orientations.csv');

            INSERT INTO trees.GrowthOrientations (GrowthOrientationName, Description)
            SELECT GrowthOrientationName, Description FROM _temp_orientation
            ON CONFLICT (GrowthOrientationName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.growthorientations;
            p_table_name := 'growth_orientations';

        WHEN 'shoot_elongation_types', 'shootelongationtypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.shootelongationtypes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_shoot (
                ShootElongationTypeName VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shoot;

            EXECUTE format('COPY _temp_shoot FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'shoot_elongation_types.csv');

            INSERT INTO trees.ShootElongationTypes (ShootElongationTypeName, Description)
            SELECT ShootElongationTypeName, Description FROM _temp_shoot
            ON CONFLICT (ShootElongationTypeName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.shootelongationtypes;
            p_table_name := 'shoot_elongation_types';

        WHEN 'crown_shapes', 'crownshapes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crownshapes;

            CREATE TEMP TABLE IF NOT EXISTS _temp_shapes (
                CrownShapeName VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shapes;

            EXECUTE format('COPY _temp_shapes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_shapes.csv');

            INSERT INTO trees.CrownShapes (CrownShapeName, Description)
            SELECT CrownShapeName, Description FROM _temp_shapes
            ON CONFLICT (CrownShapeName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.crownshapes;
            p_table_name := 'crown_shapes';

        WHEN 'geometric_crown_solids', 'geometriccrownsolids', 'geometric_solids' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.geometriccrownsolids;

            CREATE TEMP TABLE IF NOT EXISTS _temp_solids (
                GeometricSolidName VARCHAR(50),
                Description TEXT,
                RelativeLateralArea NUMERIC(4, 2),
                RelativeVolume NUMERIC(4, 2),
                RelativeDrag NUMERIC(4, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_solids;

            EXECUTE format('COPY _temp_solids FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'geometric_crown_solids.csv');

            INSERT INTO trees.GeometricCrownSolids (GeometricSolidName, Description, RelativeLateralArea, RelativeVolume, RelativeDrag)
            SELECT GeometricSolidName, Description, RelativeLateralArea, RelativeVolume, RelativeDrag FROM _temp_solids
            ON CONFLICT (GeometricSolidName) DO UPDATE SET
                Description = EXCLUDED.Description,
                RelativeLateralArea = EXCLUDED.RelativeLateralArea,
                RelativeVolume = EXCLUDED.RelativeVolume,
                RelativeDrag = EXCLUDED.RelativeDrag;

            SELECT COUNT(*) INTO v_rows_after FROM trees.geometriccrownsolids;
            p_table_name := 'geometric_crown_solids';

        WHEN 'axis_structures', 'axisstructures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.axisstructures;

            CREATE TEMP TABLE IF NOT EXISTS _temp_axis (
                AxisStructureName VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_axis;

            EXECUTE format('COPY _temp_axis FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'axis_structures.csv');

            INSERT INTO trees.AxisStructures (AxisStructureName, Description)
            SELECT AxisStructureName, Description FROM _temp_axis
            ON CONFLICT (AxisStructureName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.axisstructures;
            p_table_name := 'axis_structures';

        WHEN 'growth_forms', 'growthforms' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growthforms;

            CREATE TEMP TABLE IF NOT EXISTS _temp_forms (
                GrowthFormName VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_forms;

            EXECUTE format('COPY _temp_forms FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_forms.csv');

            INSERT INTO trees.GrowthForms (GrowthFormName, Description)
            SELECT GrowthFormName, Description FROM _temp_forms
            ON CONFLICT (GrowthFormName) DO UPDATE SET Description = EXCLUDED.Description;

            SELECT COUNT(*) INTO v_rows_after FROM trees.growthforms;
            p_table_name := 'growth_forms';

        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0, 'ERROR: Unknown table. Use: species, locations, sensor_types, tree_status, soil_types, climate_zones, variant_types, scenarios, taper_types, straightness_types, branching_patterns, bark_characteristics, height_classes, crown_architectures, branch_elongation_habits, growth_orientations, shoot_elongation_types, crown_shapes, geometric_crown_solids, axis_structures, growth_forms';
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
    RAISE NOTICE '  bark_characteristics';
    RAISE NOTICE '';
    RAISE NOTICE 'Tree Morphology (from tree_anatomy.pdf):';
    RAISE NOTICE '  height_classes, crown_architectures, branch_elongation_habits,';
    RAISE NOTICE '  growth_orientations, shoot_elongation_types, crown_shapes,';
    RAISE NOTICE '  geometric_crown_solids, axis_structures, growth_forms';
    RAISE NOTICE '=======================================================';
END $$;
