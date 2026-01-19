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
                ShadeTolerance VARCHAR(20)
            ) ON COMMIT DROP;
            TRUNCATE _temp_species;
            
            EXECUTE format('COPY _temp_species FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'species.csv');
            
            INSERT INTO shared.Species (CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance)
            SELECT CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance 
            FROM _temp_species
            ON CONFLICT (ScientificName) DO UPDATE SET
                CommonName = EXCLUDED.CommonName,
                MaxHeight_m = EXCLUDED.MaxHeight_m,
                MaxDBH_cm = EXCLUDED.MaxDBH_cm,
                TypicalLifespan_years = EXCLUDED.TypicalLifespan_years,
                GrowthRate = EXCLUDED.GrowthRate,
                ShadeTolerance = EXCLUDED.ShadeTolerance;
            
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
            
        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0, 'ERROR: Unknown table. Use: species, locations, sensor_types, tree_status, soil_types, climate_zones';
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
    RETURN QUERY SELECT * FROM shared.refresh_lookup('species');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('locations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('sensor_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('tree_status');
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
    RAISE NOTICE '  soil_types, climate_zones';
    RAISE NOTICE '=======================================================';
END $$;
