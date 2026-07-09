-- XR Future Forests Lab - Tree Catalogue / Forest State View (XRFF-240)
-- Exposes scenarios, variant types, and the flat ue_trees view for UE HTTPS
-- Blueprint queries.
--
-- History: this file originally created public.forest_state, with public.ue_trees
-- as a column-scoped alias of it. The two were consolidated into a single
-- self-contained public.ue_trees (forest_state removed) — see 33-consolidate-
-- ue-trees.sql for the in-place migration applied to existing databases.
--
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
-- UE_TREES VIEW (PRIMARY UE TREE ENDPOINT)
-- =============================================================================
-- Flat view of all tree records with variant, scenario, species, main-stem DBH,
-- and position joined in — one row per tree, no PostGIS parsing needed in UE
-- Blueprint (pre-flattened latitude/longitude). Filter by variantid to load all
-- trees at one time step: GET /ue_trees?variantid=eq.<id>
--
-- Naming convention: ue_* prefix groups all Unreal Engine query views.

CREATE OR REPLACE VIEW public.ue_trees AS
SELECT
    t.treeid,
    t.treeentityid,
    t.parenttreeid,
    t.locationid,
    t.plotid,
    -- Variant info (use variantid to load all trees at one time step)
    t.variantid,
    v.variantname,
    v.simulationyear,
    v.timedelta_yrs,
    v.sortorder         AS variant_sortorder,
    -- Scenario info (allows UE to filter by name, not just ID)
    s.scenarioid,
    s.scenarioname,
    -- Variant type comes from the variant, not the individual tree row
    v.varianttypeid,
    vt.varianttypename,
    -- Species info (common name is the UE asset lookup key)
    sp.speciesid,
    sp.commonname       AS speciesname,
    sp.scientificname,
    -- Tree measurements
    t.height_m,
    t.crownwidth_m,
    t.crownbaseheight_m,
    st.dbh_cm,          -- main stem (StemNumber=1), flattened
    t.age_years,
    t.healthscore,
    t.measurementdate,
    dst.datasourcetypename AS datasourcetype,
    -- Competition proxy: crown starts above 60% of tree height → high pressure
    COALESCE((t.crownbaseheight_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    -- NOTE: trees.AquariusName (added by migration 32) and has_sensors are added
    -- to ue_trees later, by 33/34 — do not reference them here, 25 runs first.
    -- Flat lat/lon for UE JSON parsing (no PostGIS parsing needed in Blueprint)
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude,
    -- Full geometry for PostGIS queries if needed
    t.position
FROM trees.trees t
LEFT JOIN shared.variants     v   ON t.variantid       = v.variantid
LEFT JOIN shared.scenarios    s   ON v.scenarioid      = s.scenarioid
LEFT JOIN shared.varianttypes vt  ON v.varianttypeid   = vt.varianttypeid
LEFT JOIN shared.species      sp  ON t.speciesid       = sp.speciesid
LEFT JOIN trees.stems         st  ON st.treeid = t.treeid AND st.stemnumber = 1
LEFT JOIN trees.datasourcetypes dst ON t.datasourcetypeid = dst.datasourcetypeid;

COMMENT ON VIEW public.ue_trees IS
    'Flat tree catalogue for UE Blueprint import. One row per tree with variant, '
    'scenario, species, main-stem DBH, pre-flattened latitude/longitude, and the '
    'Aquarius sensor anchor. Filter by variantid to load one time step: '
    'GET /ue_trees?variantid=eq.<id>. For a tree''s sensors: '
    'GET /ue_sensors?linked_tree_entity_id=eq.<treeentityid>.';

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
GRANT SELECT ON public.ue_trees        TO anon, authenticated;

GRANT ALL ON public.varianttypes    TO service_role;
GRANT ALL ON public.datasourcetypes TO service_role;
GRANT ALL ON public.ue_trees        TO service_role;
