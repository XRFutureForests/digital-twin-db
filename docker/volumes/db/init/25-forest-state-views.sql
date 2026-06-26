-- XR Future Forests Lab - Forest State Views (XRFF-240)
-- Exposes scenarios, variant types, and a flat forest_state view for UE HTTPS Blueprint queries.
-- Dependencies: 11-shared-schema.sql, 13-trees-schema.sql, 24-public-api-views.sql

-- =============================================================================
-- MISSING PUBLIC VIEWS FOR LOOKUP TABLES
-- =============================================================================

-- VariantTypes view
CREATE OR REPLACE VIEW public.varianttypes AS
SELECT * FROM shared.varianttypes;

COMMENT ON VIEW public.varianttypes IS 'Public API view for data variant type classifications';

-- DataSourceTypes view
CREATE OR REPLACE VIEW public.datasourcetypes AS
SELECT * FROM trees.DataSourceTypes;
COMMENT ON VIEW public.datasourcetypes IS 'Data source type classifications (field, lidar, photogrammetry, estimated, simulated)';

-- =============================================================================
-- FOREST STATE VIEW (PRIMARY UE QUERY TARGET)
-- =============================================================================
-- Joins trees + scenario + species into a single flat view.
-- UE can filter by scenario name directly: ?scenarioname=eq.Current_Conditions
-- This avoids a two-step query (lookup ScenarioID first, then query trees).

CREATE OR REPLACE VIEW public.forest_state AS
SELECT
    t.treeid,
    t.treeentityid,
    t.parenttreeid,
    t.locationid,
    t.plotid,
    -- Variant info (use VariantID to load all trees at one time step)
    t.variantid,
    v.variantname,
    v.simulationyear,
    v.timedelta_yrs,
    v.sortorder AS variant_sortorder,
    -- Scenario info (allows UE to filter by name, not just ID)
    s.scenarioid,
    s.scenarioname,
    -- Variant type info
    vt.varianttypeid,
    vt.varianttypename,
    -- Species info (common name is the UE asset lookup key)
    sp.speciesid,
    sp.commonname       AS speciesname,
    sp.scientificname,
    -- Tree measurements
    t.height_m,
    t.crownwidth_m,
    t.crownbaseheight_m,
    t.age_years,
    t.healthscore,
    t.measurementdate,
    dst.datasourcetypename AS datasourcetype,
    -- Main stem diameter (StemNumber=1) — flattened so UE gets height+DBH in one query
    st.dbh_cm,
    -- Flat lat/lon for UE JSON parsing (no PostGIS parsing needed in Blueprint)
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude,
    -- Full geometry for PostGIS queries if needed
    t.position
FROM trees.trees t
LEFT JOIN shared.variants    v  ON t.variantid    = v.variantid
LEFT JOIN shared.scenarios   s  ON v.scenarioid   = s.scenarioid
LEFT JOIN shared.varianttypes vt ON t.varianttypeid = vt.varianttypeid
LEFT JOIN shared.species      sp ON t.speciesid    = sp.speciesid
LEFT JOIN trees.stems         st ON st.treeid = t.treeid AND st.stemnumber = 1
LEFT JOIN trees.DataSourceTypes dst ON t.datasourcetypeid = dst.datasourcetypeid;

COMMENT ON VIEW public.forest_state IS
    'Flat view of all tree records with variant, scenario, species, and position. '
    'Primary UE query target: filter by variantid to load all trees at one time step. '
    'Example: GET /forest_state?variantid=eq.3';

-- =============================================================================
-- PERFORMANCE INDEXES
-- =============================================================================

-- ScenarioID on trees — critical for variant switching performance
CREATE INDEX IF NOT EXISTS idx_trees_scenario_id
    ON trees.trees (scenarioid);

-- LocationID + ScenarioID composite — common UE query pattern
CREATE INDEX IF NOT EXISTS idx_trees_location_scenario
    ON trees.trees (locationid, scenarioid);

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON public.varianttypes    TO anon, authenticated;
GRANT SELECT ON public.datasourcetypes TO anon, authenticated;
GRANT SELECT ON public.forest_state    TO anon, authenticated;

GRANT ALL ON public.varianttypes    TO service_role;
GRANT ALL ON public.datasourcetypes TO service_role;
GRANT ALL ON public.forest_state    TO service_role;
