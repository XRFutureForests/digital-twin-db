-- =============================================================================
-- Stand summaries fast enough for an unfiltered REST request
-- =============================================================================
-- Follow-up to 20261102150000. On dt.unr an unfiltered GET of
-- /rest/v1/plot_summaries (what the portal's data page and its CSV download
-- send) still ran past the anonymous 3 s statement timeout. Two causes:
--
-- 1. shared.ef_value carried `SET search_path TO ''`. A SQL function with a SET
--    clause is never inlined, so the formula ran as a separate function call
--    for every use in every row: about 1.8 million calls. It only calls the
--    built-in pi(), now schema-qualified, so it needs no search_path and is
--    inlined.
-- 2. plot_summaries used the factor in about twelve aggregate expressions, so
--    even inlined, the numeric formula was evaluated twelve times per tree.
--    Each tree's factor and its per-hectare products are now computed once,
--    in a per-row sub-select the planner may not flatten (OFFSET 0); the
--    variant filter still reaches the trees.
--
-- Measured on dt.unr as anon: unfiltered 3.0 s -> 1.5 s; PostgREST's LIMIT 100
-- form 3.0 s -> 0.9 s; one variant 9 ms. Results unchanged (checksums of all
-- 1,215 rows identical).
--
-- Mirrored to init 77-stand-summaries-compute-once.sql.
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.ef_value(
    p_has_rules boolean, p_rule_type text, p_radius_m numeric, p_basal_area_factor_m2ha numeric,
    p_area_m2 numeric, p_min_dbh_cm numeric, p_dbh_cm numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT (CASE
        WHEN p_min_dbh_cm IS NOT NULL AND (p_dbh_cm IS NULL OR p_dbh_cm < p_min_dbh_cm) THEN NULL
        WHEN p_has_rules THEN CASE p_rule_type
            WHEN 'fixed_radius' THEN 10000 / (pg_catalog.pi() * p_radius_m ^ 2)
            WHEN 'angle_count'  THEN p_basal_area_factor_m2ha / (pg_catalog.pi() * (p_dbh_cm / 200.0) ^ 2)
        END
        WHEN p_area_m2 > 0 THEN 10000 / p_area_m2
    END)::numeric;
$$;

CREATE OR REPLACE VIEW public.plot_summaries WITH (security_invoker = on) AS
WITH tree_rows AS (
    SELECT t.variant_id, t.location_id, t.species_id, pi.sample_unit_id AS plot_id,
           e.ef, e.ba_ha, e.vol_ha, e.bio_ha, e.c_ha,
           ba.basal_area_m2, t.volume_m3, t.biomass_kg, t.carbon_content_kg
      FROM trees.trees t
      JOIN shared.plot_inclusion pi  ON pi.plot_id = t.plot_id
      LEFT JOIN trees.stems s1       ON s1.tree_id = t.tree_id AND s1.stem_number = 1
      LEFT JOIN shared.inclusion_rules ir
             ON ir.sampling_design_id = pi.sampling_design_id
            AND s1.dbh_cm >= ir.min_dbh_cm
            AND (ir.max_dbh_cm IS NULL OR s1.dbh_cm < ir.max_dbh_cm)
            AND s1.dbh_cm > 0
      LEFT JOIN trees.tree_status ts ON ts.tree_status_id = t.tree_status_id
      LEFT JOIN LATERAL (
            SELECT sum(pi() * (s.dbh_cm / 200.0) ^ 2)::numeric AS basal_area_m2
              FROM trees.stems s WHERE s.tree_id = t.tree_id
      ) ba ON true
      CROSS JOIN LATERAL (
            SELECT x.ef, x.ef * ba.basal_area_m2 AS ba_ha, x.ef * t.volume_m3 AS vol_ha,
                   x.ef * t.biomass_kg AS bio_ha, x.ef * t.carbon_content_kg AS c_ha
              FROM (SELECT shared.ef_value(pi.has_rules, ir.rule_type, ir.radius_m, ir.basal_area_factor_m2ha,
                                           pi.area_m2, pi.min_dbh_cm, s1.dbh_cm) AS ef OFFSET 0) x
      ) e
     WHERE coalesce(ts.tree_status_name, '') NOT IN ('dead', 'harvested', 'missing', 'downed')
)
SELECT r.plot_id, r.variant_id, r.location_id, p.sampling_design_id, p.stratum_id, p.sampling_weight, r.species_id,
       count(r.ef)::integer AS trees_measured,
       (count(*) - count(r.ef))::integer AS trees_without_expansion_factor,
       round(coalesce(sum(r.ef), 0), 4) AS stems_ha,
       CASE WHEN count(r.basal_area_m2) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.ba_ha), 0), 6) END AS basal_area_m2ha,
       CASE WHEN count(r.volume_m3) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.vol_ha), 0), 6) END AS volume_m3ha,
       CASE WHEN count(r.biomass_kg) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.bio_ha), 0) / 1000, 6) END AS biomass_tha,
       CASE WHEN count(r.carbon_content_kg) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.c_ha), 0) / 1000, 6) END AS carbon_tha
  FROM tree_rows r
  JOIN shared.plots p ON p.plot_id = r.plot_id
 GROUP BY r.plot_id, r.variant_id, r.location_id, p.sampling_design_id, p.stratum_id, p.sampling_weight, r.species_id;

COMMENT ON FUNCTION shared.ef_value(boolean, text, numeric, numeric, numeric, numeric, numeric) IS
    'The expansion-factor formula, given an already resolved design (has rules?), the inclusion rule matching the DBH (NULL when none), the inclusion area and the minimum DBH: fixed radius 10000/(pi r²), angle count BAF/basal area, otherwise 10000/area. Inlinable: no SET clause, only pg_catalog calls. Used by shared.expansion_factor_ha and the summary views.';

NOTIFY pgrst, 'reload schema';
