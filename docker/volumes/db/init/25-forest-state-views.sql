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
-- Blueprint (pre-flattened latitude/longitude). Filter by variant_id to load all
-- trees at one time step: GET /ue_trees?variant_id=eq.<id>
--
-- Naming convention: ue_* prefix groups all Unreal Engine query views.

CREATE OR REPLACE VIEW public.ue_trees AS
SELECT
    t.tree_id,
    t.tree_entity_id,
    t.parent_tree_id,
    t.location_id,
    t.plot_id,
    -- Variant info (use variant_id to load all trees at one time step)
    t.variant_id,
    v.variant_name,
    v.simulation_year,
    v.time_delta_yrs,
    v.sort_order         AS variant_sortorder,
    -- Scenario info (allows UE to filter by name, not just ID)
    s.scenario_id,
    s.scenario_name,
    -- Variant type comes from the variant, not the individual tree row
    v.variant_type_id,
    vt.variant_type_name,
    -- Species info (common name is the UE asset lookup key)
    sp.species_id,
    sp.common_name       AS species_name,
    sp.scientific_name,
    -- Tree measurements
    t.height_m,
    t.crown_width_m,
    t.crown_base_height_m,
    st.dbh_cm,          -- main stem (stem_number=1), flattened
    t.age_years,
    t.health_score,
    t.measurement_date,
    dst.data_source_type_name AS datasourcetype,
    -- Competition proxy: crown starts above 60% of tree height → high pressure
    COALESCE((t.crown_base_height_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    -- NOTE: trees.sensor_ref (added by migration 32) and has_sensors are added
    -- to ue_trees later, by 33/34 — do not reference them here, 25 runs first.
    -- Flat lat/lon for UE JSON parsing (no PostGIS parsing needed in Blueprint)
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude,
    -- Full geometry for PostGIS queries if needed
    t.position
FROM trees.trees t
LEFT JOIN shared.variants     v   ON t.variant_id       = v.variant_id
LEFT JOIN shared.scenarios    s   ON v.scenario_id      = s.scenario_id
LEFT JOIN shared.varianttypes vt  ON v.variant_type_id   = vt.variant_type_id
LEFT JOIN shared.species      sp  ON t.species_id       = sp.species_id
LEFT JOIN trees.stems         st  ON st.tree_id = t.tree_id AND st.stem_number = 1
LEFT JOIN trees.datasourcetypes dst ON t.data_source_type_id = dst.data_source_type_id;

COMMENT ON VIEW public.ue_trees IS
    'Flat tree catalogue for UE Blueprint import. One row per tree with variant, '
    'scenario, species, main-stem DBH, pre-flattened latitude/longitude, and the '
    'Sensor-cluster reference (sensor_ref). Filter by variant_id to load one time step: '
    'GET /ue_trees?variant_id=eq.<id>. For a tree''s sensors: '
    'GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>.';

-- =============================================================================
-- PERFORMANCE INDEXES
-- =============================================================================

-- scenario_id on trees — critical for variant switching performance
CREATE INDEX IF NOT EXISTS idx_trees_scenario_id
    ON trees.trees (scenario_id);

-- location_id + scenario_id composite — common UE query pattern
CREATE INDEX IF NOT EXISTS idx_trees_location_scenario
    ON trees.trees (location_id, scenario_id);

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON public.varianttypes    TO anon, authenticated;
GRANT SELECT ON public.datasourcetypes TO anon, authenticated;
GRANT SELECT ON public.ue_trees        TO anon, authenticated;

GRANT ALL ON public.varianttypes    TO service_role;
GRANT ALL ON public.datasourcetypes TO service_role;
GRANT ALL ON public.ue_trees        TO service_role;
