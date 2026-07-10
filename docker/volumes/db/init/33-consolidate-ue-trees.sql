-- XR Future Forests Lab - Consolidate ue_trees / drop forest_state
-- Consolidates the overlapping public.forest_state and public.ue_trees into a
-- single self-contained public.ue_trees (defined in 25-forest-state-views.sql)
-- and removes public.forest_state.
--
-- forest_state (XRFF-240) predated the ue_* naming convention; ue_trees was a
-- column-scoped alias of it. Consolidating removes the redundant view. The new
-- ue_trees is a strict superset of the old ue_trees columns (adds parent_tree_id,
-- plot_id, time_delta_yrs, variant_sortorder, measurement_date, datasourcetype,
-- aquarius_name, position), so no data is lost — only the /forest_state endpoint
-- is retired in favour of /ue_trees.
--
-- Idempotent: safe on a fresh install (25 already builds the consolidated
-- ue_trees; forest_state never exists) and on an existing database.
--
-- Dependencies: 25-forest-state-views.sql

-- ue_trees currently depends on forest_state on already-provisioned databases,
-- so drop it first, then forest_state, then let 25's definition be re-applied.
DROP VIEW IF EXISTS public.ue_trees;
DROP VIEW IF EXISTS public.forest_state;

CREATE OR REPLACE VIEW public.ue_trees AS
SELECT
    t.tree_id,
    t.tree_entity_id,
    t.parent_tree_id,
    t.location_id,
    t.plot_id,
    t.variant_id,
    v.variant_name,
    v.simulation_year,
    v.time_delta_yrs,
    v.sort_order         AS variant_sortorder,
    s.scenario_id,
    s.scenario_name,
    v.variant_type_id,
    vt.variant_type_name,
    sp.species_id,
    sp.common_name       AS species_name,
    sp.scientific_name,
    t.height_m,
    t.crown_width_m,
    t.crown_base_height_m,
    st.dbh_cm,
    t.age_years,
    t.health_score,
    t.measurement_date,
    dst.data_source_type_name AS datasourcetype,
    COALESCE((t.crown_base_height_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    t.aquarius_name      AS aquarius_name,
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude,
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
    'Aquarius sensor anchor. Filter by variant_id to load one time step: '
    'GET /ue_trees?variant_id=eq.<id>. For a tree''s sensors: '
    'GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>.';

GRANT SELECT ON public.ue_trees TO anon, authenticated;
GRANT ALL    ON public.ue_trees TO service_role;
