-- XR Future Forests Lab - ue_trees: hierarchy names + projected coordinates
-- Adds to public.ue_trees (last defined in 34-ue-view-refinements.sql):
--   * locationname  — name for the already-present locationid
--   * scenarioid    — id for the already-present scenarioname
--   * original_x / original_y / source_crs — the tree's position in its source
--     projected CRS (trees.Trees.PositionOriginal, EPSG:32632 / UTM 32N here).
--     Unreal Engine places trees more reliably from local projected metres than
--     from WGS84 lat/lon, so we expose the pre-transform coordinates alongside.
--
-- The Location -> Scenario -> Variant hierarchy now surfaces both id and name
-- for each level (locationid/locationname, scenarioid/scenarioname,
-- variantid/variantname).
--
-- View is DROP+CREATE'd because CREATE OR REPLACE cannot add/reorder columns.
-- Nothing depends on ue_trees.
--
-- Dependencies: 34-ue-view-refinements.sql

DROP VIEW IF EXISTS public.ue_trees;

CREATE VIEW public.ue_trees AS
SELECT
    t.treeid,
    t.treeentityid,
    -- Location -> Scenario -> Variant hierarchy (id + name at each level)
    t.locationid,
    l.locationname,
    s.scenarioid,
    s.scenarioname,
    -- Time-step selector: filter by variantid to load one forest state
    t.variantid,
    v.variantname,
    v.simulationyear,
    vt.varianttypename,
    -- Species (names are the UE asset lookup keys)
    sp.commonname       AS speciesname,
    sp.scientificname,
    -- Measurements for placement / rendering
    t.height_m,
    t.crownwidth_m,
    t.crownbaseheight_m,
    st.dbh_cm,          -- main stem (StemNumber=1)
    t.age_years,
    t.healthscore,
    -- Competition proxy: crown starts above 60% of tree height → high pressure
    COALESCE((t.crownbaseheight_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    -- Sensor cross-reference
    t.aquariusname      AS aquarius_name,
    EXISTS (
        SELECT 1 FROM sensor.sensor_tree_links stl WHERE stl.tree_id = t.treeid
    )                   AS has_sensors,
    -- Projected source coordinates (UE handles local metres better than lat/lon)
    ST_X(t.positionoriginal) AS original_x,
    ST_Y(t.positionoriginal) AS original_y,
    t.sourcecrs         AS source_crs,
    -- Flat lat/lon for UE JSON parsing (no PostGIS parsing needed in Blueprint)
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude
FROM trees.trees t
LEFT JOIN shared.locations    l   ON t.locationid      = l.locationid
LEFT JOIN shared.variants     v   ON t.variantid       = v.variantid
LEFT JOIN shared.scenarios    s   ON v.scenarioid      = s.scenarioid
LEFT JOIN shared.varianttypes vt  ON v.varianttypeid   = vt.varianttypeid
LEFT JOIN shared.species      sp  ON t.speciesid       = sp.speciesid
LEFT JOIN trees.stems         st  ON st.treeid = t.treeid AND st.stemnumber = 1;

COMMENT ON VIEW public.ue_trees IS
    'Flat tree catalogue for UE Blueprint import. One row per tree with the '
    'location/scenario/variant hierarchy (id + name at each level), species, '
    'main-stem DBH, competition flag, sensor cross-reference (aquarius_name + '
    'has_sensors), projected source coordinates (original_x/original_y in '
    'source_crs, EPSG:32632/UTM 32N — preferred for UE placement) and flattened '
    'latitude/longitude. Filter by variantid to load one time step. For a tree''s '
    'sensors: GET /ue_sensors?linked_tree_entity_id=eq.<treeentityid>.';

GRANT SELECT ON public.ue_trees TO anon, authenticated;
GRANT ALL    ON public.ue_trees TO service_role;
