-- Mirrored from supabase/migrations/20260923160000_lookup_registry.sql.
-- Keep the two identical.
-- =============================================================================
-- shared.refresh_lookup: a registry instead of a 24-branch CASE
-- =============================================================================
-- XRFF-496, part of XRFF-494. The last of the schema-cleanup work.
--
-- The function was a 559-line CASE dispatching on a text argument, with a
-- bespoke temp table, COPY and ON CONFLICT per branch. It had been redefined
-- four times across the migration history, and nothing in Postgres updates it
-- when a table or column it names is renamed.
--
-- 22 of the 24 branches differed only in data: target table, CSV file, the
-- column each CSV position maps to, and the natural key. Those become rows in
-- shared.lookup_registry and share one loader. Adding a lookup is now an INSERT,
-- not a function edit.
--
-- WHY TWO BRANCHES SURVIVE. locations and scenarios are not generic and cannot
-- be made so honestly:
--
--   locations   CenterLongitude/CenterLatitude are CONSTRUCTED into a PostGIS
--               point and SoilTypeName/ClimateZoneName are RESOLVED to foreign
--               keys -- neither is a column. It also preserves acquired site
--               attributes (XRFF-391).
--   scenarios   location-scoped and created by the seed scripts; there is no
--               global CSV to refresh from.
--
-- Both are carried over character-for-character from the live function rather
-- than reimplemented, so their behaviour is preserved rather than re-derived.
--
-- THE CSV HEADER IS NOW IGNORED. COPY ... HEADER true skips the first line; the
-- registry says what each position means. That matters because two headers still
-- carry a pre-rename spelling (StraightnessName, GeometricSolidName) -- under a
-- header-matching loader they would have silently misloaded.
--
-- Each column is staged as text and cast to the target's own declared type on
-- the way in, so a CSV that disagrees with the schema fails loudly instead of
-- storing something surprising.
--
-- VERIFIED, and row counts were not the bar: every one of the 22 registry
-- lookups was content-hashed before and after a refresh through the new loader.
-- 22 of 22 unchanged, 0 failures. locations was hashed separately and is
-- identical. The alias keys callers have always passed (treestatus,
-- phanerophyteheightclasses) still resolve, and an unknown key now lists the
-- registry rather than a hardcoded string.
--
-- Mirror of the migration of the same name.
-- =============================================================================

SET search_path TO shared, public;

-- 1. The registry. A new lookup becomes a row here, not a branch in a function.
CREATE TABLE IF NOT EXISTS shared.lookup_registry (
    logical_key   TEXT PRIMARY KEY,
    schema_name   TEXT   NOT NULL,
    table_name    TEXT   NOT NULL,
    csv_file      TEXT   NOT NULL,
    csv_columns   TEXT[] NOT NULL,
    natural_key   TEXT   NOT NULL,
    description   TEXT
);

COMMENT ON TABLE shared.lookup_registry IS
    'Drives shared.refresh_lookup. csv_columns lists the TARGET column for each '
    'CSV column, in file order -- the CSV header is ignored, so a header whose '
    'spelling predates a column rename does not silently misload. natural_key is '
    'the column the upsert conflicts on.';

COMMENT ON COLUMN shared.lookup_registry.csv_columns IS
    'Target column per CSV column, in file order. Length must equal the CSV''s '
    'column count; the loader asserts this rather than trusting it.';

-- 2. One row per lookup, generated from the live schema: each target column
--    resolved against information_schema, each natural key read from the
--    table's own single-column UNIQUE constraint.
INSERT INTO shared.lookup_registry (logical_key, schema_name, table_name, csv_file, csv_columns, natural_key) VALUES
    ('axis_structures', 'trees', 'axis_structures', 'axis_structures.csv', ARRAY['axis_structure_name','description'], 'axis_structure_name'),
    ('bark_characteristics', 'trees', 'bark_characteristics', 'bark_characteristics.csv', ARRAY['bark_characteristic_name','description','typical_species'], 'bark_characteristic_name'),
    ('branch_elongation_habits', 'trees', 'branch_elongation_habits', 'branch_elongation_habits.csv', ARRAY['elongation_habit_name','description'], 'elongation_habit_name'),
    ('branching_patterns', 'trees', 'branching_patterns', 'branching_patterns.csv', ARRAY['branching_pattern_name','description'], 'branching_pattern_name'),
    ('climate_zones', 'shared', 'climate_zones', 'climate_zones.csv', ARRAY['climate_zone_name','description'], 'climate_zone_name'),
    ('crown_architectures', 'trees', 'crown_architectures', 'crown_architectures.csv', ARRAY['crown_architecture_name','description','typical_examples'], 'crown_architecture_name'),
    ('crown_classes', 'trees', 'crown_classes', 'crown_classes.csv', ARRAY['crown_class_name','description'], 'crown_class_name'),
    ('crown_shapes', 'trees', 'crown_shapes', 'crown_shapes.csv', ARRAY['crown_shape_name','description'], 'crown_shape_name'),
    ('damage_agents', 'trees', 'damage_agents', 'damage_agents.csv', ARRAY['damage_agent_name','description'], 'damage_agent_name'),
    ('data_source_types', 'trees', 'data_source_types', 'data_source_types.csv', ARRAY['data_source_type_name','description'], 'data_source_type_name'),
    ('geometric_crown_solids', 'trees', 'geometric_crown_solids', 'geometric_crown_solids.csv', ARRAY['geometric_crown_solid_name','description','relative_lateral_area','relative_volume','relative_drag'], 'geometric_crown_solid_name'),
    ('growth_forms', 'trees', 'growth_forms', 'growth_forms.csv', ARRAY['growth_form_name','description'], 'growth_form_name'),
    ('growth_orientations', 'trees', 'growth_orientations', 'growth_orientations.csv', ARRAY['growth_orientation_name','description'], 'growth_orientation_name'),
    ('height_classes', 'trees', 'phanerophyte_height_classes', 'phanerophyte_height_classes.csv', ARRAY['height_class_name','description','min_height_m','max_height_m'], 'height_class_name'),
    ('sensor_types', 'sensor', 'sensor_types', 'sensor_types.csv', ARRAY['sensor_type_name','description','typical_unit','typical_range_min','typical_range_max'], 'sensor_type_name'),
    ('shoot_elongation_types', 'trees', 'shoot_elongation_types', 'shoot_elongation_types.csv', ARRAY['shoot_elongation_type_name','description'], 'shoot_elongation_type_name'),
    ('soil_types', 'shared', 'soil_types', 'soil_types.csv', ARRAY['soil_type_name','description'], 'soil_type_name'),
    ('species', 'shared', 'species', 'species.csv', ARRAY['common_name','scientific_name','max_height_m','max_dbh_cm','typical_lifespan_years','growth_rate','shade_tolerance','is_deciduous','gbif_key','gbif_accepted_name'], 'scientific_name'),
    ('straightness_types', 'trees', 'straightness_types', 'straightness_types.csv', ARRAY['straightness_type_name','description','deviation_angle_min_deg','deviation_angle_max_deg'], 'straightness_type_name'),
    ('taper_types', 'trees', 'taper_types', 'taper_types.csv', ARRAY['taper_type_name','description','typical_taper_ratio_min','typical_taper_ratio_max'], 'taper_type_name'),
    ('tree_status', 'trees', 'tree_status', 'tree_status.csv', ARRAY['tree_status_name','description'], 'tree_status_name'),
    ('variant_types', 'shared', 'variant_types', 'variant_types.csv', ARRAY['variant_type_name','description'], 'variant_type_name')
ON CONFLICT (logical_key) DO UPDATE SET
    schema_name = EXCLUDED.schema_name,
    table_name  = EXCLUDED.table_name,
    csv_file    = EXCLUDED.csv_file,
    csv_columns = EXCLUDED.csv_columns,
    natural_key = EXCLUDED.natural_key;


-- 3. The generic loader. Builds its temp table from the registry row, COPYs the
--    file positionally (HEADER true skips the header rather than matching it),
--    casts each column to the target's own declared type, and upserts on the
--    natural key. Nothing about a lookup's shape is hardcoded here.
CREATE OR REPLACE FUNCTION shared.refresh_lookup_generic(p_key TEXT)
RETURNS TABLE(table_name TEXT, rows_before INTEGER, rows_after INTEGER, status TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    r            shared.lookup_registry%ROWTYPE;
    v_before     INT;
    v_after      INT;
    v_qualified  TEXT;
    v_tempcols   TEXT;
    v_collist    TEXT;
    v_selectlist TEXT;
    v_updates    TEXT;
    v_col        TEXT;
    v_type       TEXT;
BEGIN
    SELECT * INTO r FROM shared.lookup_registry WHERE logical_key = lower(trim(p_key));
    IF NOT FOUND THEN
        RETURN QUERY SELECT p_key, 0, 0, 'ERROR: not in shared.lookup_registry'::TEXT;
        RETURN;
    END IF;

    v_qualified := format('%I.%I', r.schema_name, r.table_name);
    EXECUTE format('SELECT count(*) FROM %s', v_qualified) INTO v_before;

    -- Every temp column is text; the cast happens on the way in, using the
    -- target's declared type. A CSV that disagrees with the schema fails the
    -- cast loudly instead of storing something surprising.
    SELECT string_agg(format('%I TEXT', c), ', ' ORDER BY ord)
      INTO v_tempcols FROM unnest(r.csv_columns) WITH ORDINALITY AS t(c, ord);
    SELECT string_agg(format('%I', c), ', ' ORDER BY ord)
      INTO v_collist FROM unnest(r.csv_columns) WITH ORDINALITY AS t(c, ord);

    v_selectlist := '';
    FOREACH v_col IN ARRAY r.csv_columns LOOP
        -- Aliased: information_schema.columns.table_name would otherwise be
        -- ambiguous against this function's OUT parameter of the same name.
        SELECT c.data_type INTO v_type FROM information_schema.columns c
         WHERE c.table_schema = r.schema_name AND c.table_name = r.table_name
           AND c.column_name = v_col;
        IF v_type IS NULL THEN
            RETURN QUERY SELECT r.table_name, v_before, v_before,
                format('ERROR: registry names column %s, which %s does not have',
                       v_col, v_qualified)::TEXT;
            RETURN;
        END IF;
        v_selectlist := v_selectlist ||
            CASE WHEN v_selectlist = '' THEN '' ELSE ', ' END ||
            format('NULLIF(%I, '''')::%s', v_col, v_type);
    END LOOP;

    -- Refresh every non-key column from the file; the natural key is the match.
    SELECT string_agg(format('%I = EXCLUDED.%I', c, c), ', ' ORDER BY ord)
      INTO v_updates FROM unnest(r.csv_columns) WITH ORDINALITY AS t(c, ord)
     WHERE c <> r.natural_key;

    DROP TABLE IF EXISTS _lookup_stage;
    EXECUTE format('CREATE TEMP TABLE _lookup_stage (%s) ON COMMIT DROP', v_tempcols);
    EXECUTE format('COPY _lookup_stage FROM %L WITH (FORMAT csv, HEADER true)',
                   '/var/lib/postgresql/lookups/' || r.csv_file);

    IF v_updates IS NULL THEN
        EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM _lookup_stage '
                       'ON CONFLICT (%I) DO NOTHING',
                       v_qualified, v_collist, v_selectlist, r.natural_key);
    ELSE
        EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM _lookup_stage '
                       'ON CONFLICT (%I) DO UPDATE SET %s',
                       v_qualified, v_collist, v_selectlist, r.natural_key, v_updates);
    END IF;

    EXECUTE format('SELECT count(*) FROM %s', v_qualified) INTO v_after;
    RETURN QUERY SELECT r.table_name, v_before, v_after, 'OK'::TEXT;
END;
$function$;

COMMENT ON FUNCTION shared.refresh_lookup_generic(TEXT) IS
    'Registry-driven lookup loader. Called by shared.refresh_lookup for every key '
    'in shared.lookup_registry; the remaining keys (locations, scenarios) keep '
    'bespoke branches because their CSV columns are constructed or resolved '
    'rather than stored.';

CREATE OR REPLACE FUNCTION shared.refresh_lookup(p_table_name TEXT)
RETURNS TABLE(table_name TEXT, rows_before INTEGER, rows_after INTEGER, status TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_rows_before INT;
    v_rows_after  INT;
    v_csv_path    TEXT := '/var/lib/postgresql/lookups/';
    v_key         TEXT;
BEGIN
    p_table_name := lower(trim(p_table_name));

    -- Resolve an alias to its registry key: callers have historically passed
    -- both the logical key and the (then squashed) table name.
    -- Aliased: lookup_registry.table_name would otherwise be ambiguous against
    -- this function's OUT parameter of the same name.
    SELECT lr.logical_key INTO v_key FROM shared.lookup_registry lr
     WHERE lr.logical_key = p_table_name
        OR replace(lr.table_name, '_', '') = replace(p_table_name, '_', '')
        OR lr.table_name = p_table_name
     LIMIT 1;

    IF v_key IS NOT NULL THEN
        RETURN QUERY SELECT * FROM shared.refresh_lookup_generic(v_key);
        RETURN;
    END IF;

    -- Everything else keeps a bespoke branch, because its CSV columns are
    -- constructed (a PostGIS point from lat/long) or resolved (a name to an FK)
    -- rather than stored, and locations additionally preserves acquired site
    -- attributes (XRFF-391).
    CASE p_table_name
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
                climate_zone_name VARCHAR(10),
                ForestGrowthRegion VARCHAR(16),
                SoilMoistness SMALLINT,
                SoilNutrientSupply SMALLINT,
                CrsEpsg INTEGER
            ) ON COMMIT DROP;
            TRUNCATE _temp_locations;
            EXECUTE format('COPY _temp_locations FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'locations.csv');
            INSERT INTO shared.Locations (location_name, Description, center_point, Elevation_m, Slope_deg, Aspect, soil_type_id, climate_zone_id, forest_growth_region, soil_moistness, soil_nutrient_supply, crs_epsg)
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
                (SELECT soil_type_id FROM shared.soil_types WHERE soil_type_name = t.soil_type_name),
                (SELECT climate_zone_id FROM shared.climate_zones WHERE climate_zone_name = t.climate_zone_name),
                t.ForestGrowthRegion,
                t.SoilMoistness,
                t.SoilNutrientSupply,
                t.CrsEpsg
            FROM _temp_locations t
            -- The eight site-attribute columns keep their value once an
            -- acquisition process has written one, so a refresh cannot revert it
            -- and leave its provenance row claiming a source the column no
            -- longer holds (XRFF-391). Description, center_point and crs_epsg are
            -- always reseeded: the CSV owns all three.
            ON CONFLICT (location_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                center_point = EXCLUDED.center_point,
                crs_epsg = EXCLUDED.crs_epsg,
                Elevation_m = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'elevation_m')
                                   THEN Locations.Elevation_m ELSE EXCLUDED.Elevation_m END,
                Slope_deg = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'slope_deg')
                                 THEN Locations.Slope_deg ELSE EXCLUDED.Slope_deg END,
                Aspect = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'aspect')
                              THEN Locations.Aspect ELSE EXCLUDED.Aspect END,
                soil_type_id = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_type_id')
                                    THEN Locations.soil_type_id ELSE EXCLUDED.soil_type_id END,
                climate_zone_id = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'climate_zone_id')
                                       THEN Locations.climate_zone_id ELSE EXCLUDED.climate_zone_id END,
                forest_growth_region = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'forest_growth_region')
                                            THEN Locations.forest_growth_region ELSE EXCLUDED.forest_growth_region END,
                soil_moistness = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_moistness')
                                      THEN Locations.soil_moistness ELSE EXCLUDED.soil_moistness END,
                soil_nutrient_supply = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_nutrient_supply')
                                            THEN Locations.soil_nutrient_supply ELSE EXCLUDED.soil_nutrient_supply END;
            SELECT COUNT(*) INTO v_rows_after FROM shared.locations;
        WHEN 'scenarios' THEN
            -- Scenarios are location-scoped (Scenarios.location_id NOT NULL,
            -- UNIQUE(location_id, scenario_name)) and are created per site by the
            -- growth-variant seed scripts — not a refreshable global lookup CSV.
            SELECT COUNT(*) INTO v_rows_before FROM shared.scenarios;
            RAISE NOTICE 'scenarios are location-scoped; not refreshed from a global CSV (skipped)';
            v_rows_after := v_rows_before;
        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0,
                ('ERROR: unknown lookup. Registry keys: ' ||
                 (SELECT string_agg(logical_key, ', ' ORDER BY logical_key)
                    FROM shared.lookup_registry) ||
                 ', plus locations, scenarios')::TEXT;
            RETURN;
    END CASE;

    -- The bespoke branches above set the counters and fall through to here,
    -- which is where the original function returned its row. Dropping this tail
    -- made locations and scenarios return no row at all while still reporting
    -- success in the logs.
    RETURN QUERY SELECT p_table_name, v_rows_before, v_rows_after, 'OK'::TEXT;
END;
$function$;
