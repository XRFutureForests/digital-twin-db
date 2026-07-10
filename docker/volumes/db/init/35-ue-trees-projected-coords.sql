-- XR Future Forests Lab - ue_trees: hierarchy names + projected coordinates
-- Adds to public.ue_trees (last defined in 34-ue-view-refinements.sql):
--   * location_name  — name for the already-present location_id
--   * scenario_id    — id for the already-present scenario_name
--   * original_x / original_y / source_crs — the tree's position in its source
--     projected CRS (trees.Trees.position_original, EPSG:32632 / UTM 32N here).
--     Unreal Engine places trees more reliably from local projected metres than
--     from WGS84 lat/lon, so we expose the pre-transform coordinates alongside.
--
-- The Location -> Scenario -> Variant hierarchy now surfaces both id and name
-- for each level (location_id/location_name, scenario_id/scenario_name,
-- variant_id/variant_name).
--
-- View is DROP+CREATE'd because CREATE OR REPLACE cannot add/reorder columns.
-- Nothing depends on ue_trees.
--
-- Dependencies: 34-ue-view-refinements.sql

DROP VIEW IF EXISTS public.ue_trees;

CREATE VIEW public.ue_trees AS
SELECT
    t.tree_id,
    t.tree_entity_id,
    -- Location -> Scenario -> Variant hierarchy (id + name at each level)
    t.location_id,
    l.location_name,
    s.scenario_id,
    s.scenario_name,
    -- Time-step selector: filter by variant_id to load one forest state
    t.variant_id,
    v.variant_name,
    v.simulation_year,
    vt.variant_type_name,
    -- Species (names are the UE asset lookup keys)
    sp.common_name       AS species_name,
    sp.scientific_name,
    -- Measurements for placement / rendering
    t.height_m,
    t.crown_width_m,
    t.crown_base_height_m,
    st.dbh_cm,          -- main stem (stem_number=1)
    t.age_years,
    t.health_score,
    -- Competition proxy: crown starts above 60% of tree height → high pressure
    COALESCE((t.crown_base_height_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    -- Sensor cross-reference
    t.aquarius_name      AS aquarius_name,
    EXISTS (
        SELECT 1 FROM sensor.sensor_tree_links stl WHERE stl.tree_id = t.tree_id
    )                   AS has_sensors,
    -- Projected source coordinates (UE handles local metres better than lat/lon)
    ST_X(t.position_original) AS original_x,
    ST_Y(t.position_original) AS original_y,
    t.source_crs         AS source_crs,
    -- Flat lat/lon for UE JSON parsing (no PostGIS parsing needed in Blueprint)
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude
FROM trees.trees t
LEFT JOIN shared.locations    l   ON t.location_id      = l.location_id
LEFT JOIN shared.variants     v   ON t.variant_id       = v.variant_id
LEFT JOIN shared.scenarios    s   ON v.scenario_id      = s.scenario_id
LEFT JOIN shared.varianttypes vt  ON v.variant_type_id   = vt.variant_type_id
LEFT JOIN shared.species      sp  ON t.species_id       = sp.species_id
LEFT JOIN trees.stems         st  ON st.tree_id = t.tree_id AND st.stem_number = 1;

COMMENT ON VIEW public.ue_trees IS
    'Flat tree catalogue for UE Blueprint import. One row per tree with the '
    'location/scenario/variant hierarchy (id + name at each level), species, '
    'main-stem DBH, competition flag, sensor cross-reference (aquarius_name + '
    'has_sensors), projected source coordinates (original_x/original_y in '
    'source_crs, EPSG:32632/UTM 32N — preferred for UE placement) and flattened '
    'latitude/longitude. Filter by variant_id to load one time step. For a tree''s '
    'sensors: GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>.';

GRANT SELECT ON public.ue_trees TO anon, authenticated;
GRANT ALL    ON public.ue_trees TO service_role;
