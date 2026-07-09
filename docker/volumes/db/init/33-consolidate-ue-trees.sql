-- XR Future Forests Lab - Consolidate ue_trees / drop forest_state
-- Consolidates the overlapping public.forest_state and public.ue_trees into a
-- single self-contained public.ue_trees (defined in 25-forest-state-views.sql)
-- and removes public.forest_state.
--
-- forest_state (XRFF-240) predated the ue_* naming convention; ue_trees was a
-- column-scoped alias of it. Consolidating removes the redundant view. The new
-- ue_trees is a strict superset of the old ue_trees columns (adds parenttreeid,
-- plotid, timedelta_yrs, variant_sortorder, measurementdate, datasourcetype,
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
    t.treeid,
    t.treeentityid,
    t.parenttreeid,
    t.locationid,
    t.plotid,
    t.variantid,
    v.variantname,
    v.simulationyear,
    v.timedelta_yrs,
    v.sortorder         AS variant_sortorder,
    s.scenarioid,
    s.scenarioname,
    v.varianttypeid,
    vt.varianttypename,
    sp.speciesid,
    sp.commonname       AS speciesname,
    sp.scientificname,
    t.height_m,
    t.crownwidth_m,
    t.crownbaseheight_m,
    st.dbh_cm,
    t.age_years,
    t.healthscore,
    t.measurementdate,
    dst.datasourcetypename AS datasourcetype,
    COALESCE((t.crownbaseheight_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    t.aquariusname      AS aquarius_name,
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude,
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

GRANT SELECT ON public.ue_trees TO anon, authenticated;
GRANT ALL    ON public.ue_trees TO service_role;
