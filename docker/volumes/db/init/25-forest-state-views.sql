-- XR Future Forests Lab - Forest State Views (XRFF-240)
-- Exposes scenarios, variant types, and a flat forest_state view for UE HTTPS Blueprint queries.
-- Dependencies: 11-shared-schema.sql, 13-trees-schema.sql, 24-public-api-views.sql

-- =============================================================================
-- MISSING PUBLIC VIEWS FOR LOOKUP TABLES
-- =============================================================================

-- Scenarios view (UE queries this to populate the variant selector UI)
CREATE OR REPLACE VIEW public.scenarios AS
SELECT * FROM shared.scenarios;

COMMENT ON VIEW public.scenarios IS 'Public API view for simulation scenarios (Current_Conditions, Climate_Change_2050, etc.)';

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
    t.variantid,
    t.treeentityid,
    t.parentvariantid,
    t.locationid,
    t.plotid,
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
LEFT JOIN shared.scenarios   s  ON t.scenarioid   = s.scenarioid
LEFT JOIN shared.varianttypes vt ON t.varianttypeid = vt.varianttypeid
LEFT JOIN shared.species      sp ON t.speciesid    = sp.speciesid
LEFT JOIN trees.stems         st ON st.treevariantid = t.variantid AND st.stemnumber = 1
LEFT JOIN trees.DataSourceTypes dst ON t.datasourcetypeid = dst.datasourcetypeid;

COMMENT ON VIEW public.forest_state IS
    'Flat view of all tree variants with scenario, species, and position. '
    'Primary UE query target: filter by scenarioname to load a specific forest state. '
    'Example: GET /forest_state?scenarioname=eq.Current_Conditions';

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

GRANT SELECT ON public.scenarios       TO anon, authenticated;
GRANT SELECT ON public.varianttypes    TO anon, authenticated;
GRANT SELECT ON public.datasourcetypes TO anon, authenticated;
GRANT SELECT ON public.forest_state    TO anon, authenticated;

GRANT ALL ON public.scenarios       TO service_role;
GRANT ALL ON public.varianttypes    TO service_role;
GRANT ALL ON public.datasourcetypes TO service_role;
GRANT ALL ON public.forest_state    TO service_role;

-- Scenarios: allow authenticated users to add new scenarios (e.g. SILVA output)
GRANT INSERT, UPDATE ON public.scenarios TO authenticated;
