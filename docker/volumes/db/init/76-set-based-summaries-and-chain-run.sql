-- =============================================================================
-- Set-based stand summaries; which SILVA run holds a scenario's variant chain
-- =============================================================================
-- Two follow-ups to XRFF-627 (migration 20261102140000).
--
-- 1. plot_summaries without a variant filter took 16 s on dev and hit the
--    anonymous 3 s statement timeout on dt.unr, so the portal's data page,
--    which lists any view 25 rows at a time, showed an error for it. The cause:
--    every tree called the recursive functions shared.sample_unit_id() and
--    shared.expansion_factor_ha(), and the planner evaluated the factor once
--    per aggregate that used it. Now each plot's sample unit, design, area and
--    minimum DBH are resolved once for all plots (view shared.plot_inclusion),
--    the matching inclusion rule is a join, and the factor itself is one
--    inlinable formula, shared.ef_value(), which shared.expansion_factor_ha()
--    uses too -- so there is still one formula. plot_summaries and
--    tree_expansion_factors keep their columns.
--
-- 2. trees.simulation_runs.is_promoted is set when a run writes the variant
--    chain and never cleared: a later run with --replace takes the chain over,
--    but the earlier run keeps is_promoted = true. Nine scenarios have two to
--    four promoted runs (2026-11-02). That is the recorded history, not an
--    error; what was missing is which run holds the chain now. The newest
--    promoted run of a location and scenario does (silva-connector writes the
--    chain on every promoted run, and the dashboard already reads it so).
--    public.simulation_runs gains holds_variant_chain. No data changes.
--
-- Mirrored to init 76-set-based-summaries-and-chain-run.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1a. One expansion-factor formula
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION shared.ef_value(
    p_has_rules              boolean,
    p_rule_type              text,
    p_radius_m               numeric,
    p_basal_area_factor_m2ha numeric,
    p_area_m2                numeric,
    p_min_dbh_cm             numeric,
    p_dbh_cm                 numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $$
    SELECT (CASE
        WHEN p_min_dbh_cm IS NOT NULL AND (p_dbh_cm IS NULL OR p_dbh_cm < p_min_dbh_cm) THEN NULL
        WHEN p_has_rules THEN CASE p_rule_type
            WHEN 'fixed_radius' THEN 10000 / (pi() * p_radius_m ^ 2)
            WHEN 'angle_count'  THEN p_basal_area_factor_m2ha / (pi() * (p_dbh_cm / 200.0) ^ 2)
        END
        WHEN p_area_m2 > 0 THEN 10000 / p_area_m2
    END)::numeric;
$$;

COMMENT ON FUNCTION shared.ef_value(boolean, text, numeric, numeric, numeric, numeric, numeric) IS
    'The expansion-factor formula, given an already resolved design (has rules?), the inclusion rule matching the DBH (NULL when none), the inclusion area and the minimum DBH: fixed radius 10000/(pi r²), angle count BAF/basal area, otherwise 10000/area. Used by shared.expansion_factor_ha and the summary views.';

GRANT EXECUTE ON FUNCTION shared.ef_value(boolean, text, numeric, numeric, numeric, numeric, numeric)
    TO anon, authenticated, service_role;

-- The single-plot function keeps its resolution (walk up from one plot) and
-- now uses the shared formula.
CREATE OR REPLACE FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO ''
AS $$
    WITH RECURSIVE up AS (
        SELECT p.parent_plot_id, p.sampling_design_id, p.area_m2, 0 AS depth
          FROM shared.plots p
         WHERE p.plot_id = p_plot_id
        UNION ALL
        SELECT q.parent_plot_id, q.sampling_design_id, q.area_m2, up.depth + 1
          FROM shared.plots q
          JOIN up ON q.plot_id = up.parent_plot_id
         WHERE up.depth < 10
    ),
    resolved AS (
        SELECT EXISTS (SELECT 1 FROM up) AS plot_exists,
               (SELECT u.sampling_design_id FROM up u WHERE u.sampling_design_id IS NOT NULL
                 ORDER BY u.depth LIMIT 1) AS design_id,
               (SELECT u.area_m2 FROM up u WHERE u.area_m2 > 0
                 ORDER BY u.depth LIMIT 1) AS area_m2
    )
    SELECT CASE WHEN res.plot_exists THEN
               shared.ef_value(
                   EXISTS (SELECT 1 FROM shared.inclusion_rules r WHERE r.sampling_design_id = res.design_id),
                   ir.rule_type, ir.radius_m, ir.basal_area_factor_m2ha,
                   res.area_m2, d.min_dbh_cm, p_dbh_cm)
           END
      FROM resolved res
      LEFT JOIN shared.sampling_designs d ON d.sampling_design_id = res.design_id
      LEFT JOIN shared.inclusion_rules ir
             ON ir.sampling_design_id = res.design_id
            AND p_dbh_cm >= ir.min_dbh_cm
            AND (ir.max_dbh_cm IS NULL OR p_dbh_cm < ir.max_dbh_cm)
            AND p_dbh_cm > 0;
$$;


-- -----------------------------------------------------------------------------
-- 1b. Every plot resolved once
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW shared.plot_inclusion WITH (security_invoker = on) AS
WITH RECURSIVE up AS (
    SELECT p.plot_id AS start_plot_id, p.plot_id, p.parent_plot_id, p.sampling_design_id,
           p.area_m2, 0 AS depth
      FROM shared.plots p
    UNION ALL
    SELECT up.start_plot_id, q.plot_id, q.parent_plot_id, q.sampling_design_id, q.area_m2, up.depth + 1
      FROM shared.plots q
      JOIN up ON q.plot_id = up.parent_plot_id
     WHERE up.depth < 10
),
resolved AS (
    SELECT start_plot_id AS plot_id,
           (array_agg(sampling_design_id ORDER BY depth) FILTER (WHERE sampling_design_id IS NOT NULL))[1]
               AS sampling_design_id,
           (array_agg(area_m2 ORDER BY depth) FILTER (WHERE area_m2 > 0))[1] AS area_m2,
           (array_agg(plot_id ORDER BY depth) FILTER (WHERE area_m2 > 0))[1] AS area_plot_id
      FROM up
     GROUP BY start_plot_id
)
SELECT r.plot_id,
       r.sampling_design_id,
       r.area_m2,
       d.min_dbh_cm,
       hr.has_rules,
       CASE WHEN hr.has_rules THEN r.plot_id ELSE r.area_plot_id END AS sample_unit_id
  FROM resolved r
  LEFT JOIN shared.sampling_designs d ON d.sampling_design_id = r.sampling_design_id
 CROSS JOIN LATERAL (
        SELECT EXISTS (SELECT 1 FROM shared.inclusion_rules ir
                        WHERE ir.sampling_design_id = r.sampling_design_id) AS has_rules
 ) hr;

COMMENT ON VIEW shared.plot_inclusion IS
    'Every plot with its resolved sampling design and inclusion area (its own, else the nearest enclosing plot''s), the design''s minimum DBH, whether the design has inclusion rules, and the sample unit its trees belong to. The set-based equivalent of shared.sample_unit_id() and the resolution in shared.expansion_factor_ha().';

GRANT SELECT ON shared.plot_inclusion TO anon, authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 1c. Views rebuilt on it (same columns)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.tree_expansion_factors WITH (security_invoker = on) AS
SELECT t.tree_id,
       t.tree_entity_id,
       t.variant_id,
       t.location_id,
       t.plot_id,
       p.sampling_design_id,
       p.stratum_id,
       p.sampling_weight,
       s.dbh_cm,
       CASE WHEN pi.plot_id IS NOT NULL THEN
           shared.ef_value(pi.has_rules, ir.rule_type, ir.radius_m, ir.basal_area_factor_m2ha,
                           pi.area_m2, pi.min_dbh_cm, s.dbh_cm)
       END AS expansion_factor_ha
  FROM trees.trees t
  LEFT JOIN shared.plots p           ON p.plot_id = t.plot_id
  LEFT JOIN shared.plot_inclusion pi ON pi.plot_id = t.plot_id
  LEFT JOIN trees.stems s            ON s.tree_id = t.tree_id AND s.stem_number = 1
  LEFT JOIN shared.inclusion_rules ir
         ON ir.sampling_design_id = pi.sampling_design_id
        AND s.dbh_cm >= ir.min_dbh_cm
        AND (ir.max_dbh_cm IS NULL OR s.dbh_cm < ir.max_dbh_cm)
        AND s.dbh_cm > 0;

CREATE OR REPLACE VIEW public.plot_summaries WITH (security_invoker = on) AS
WITH tree_rows AS (
    SELECT t.variant_id,
           t.location_id,
           t.species_id,
           pi.sample_unit_id AS plot_id,
           shared.ef_value(pi.has_rules, ir.rule_type, ir.radius_m, ir.basal_area_factor_m2ha,
                           pi.area_m2, pi.min_dbh_cm, s1.dbh_cm) AS ef,
           ba.basal_area_m2,
           t.volume_m3,
           t.biomass_kg,
           t.carbon_content_kg
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
              FROM trees.stems s
             WHERE s.tree_id = t.tree_id
      ) ba ON true
     WHERE coalesce(ts.tree_status_name, '') NOT IN ('dead', 'harvested', 'missing', 'downed')
)
SELECT r.plot_id,
       r.variant_id,
       r.location_id,
       p.sampling_design_id,
       p.stratum_id,
       p.sampling_weight,
       r.species_id,
       count(r.ef)::integer                                   AS trees_measured,
       (count(*) - count(r.ef))::integer                      AS trees_without_expansion_factor,
       round(coalesce(sum(r.ef), 0), 4)                       AS stems_ha,
       CASE WHEN count(r.basal_area_m2) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.ef * r.basal_area_m2), 0), 6) END            AS basal_area_m2ha,
       CASE WHEN count(r.volume_m3) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.ef * r.volume_m3), 0), 6) END                AS volume_m3ha,
       CASE WHEN count(r.biomass_kg) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.ef * r.biomass_kg), 0) / 1000, 6) END        AS biomass_tha,
       CASE WHEN count(r.carbon_content_kg) FILTER (WHERE r.ef IS NOT NULL) = count(r.ef)
            THEN round(coalesce(sum(r.ef * r.carbon_content_kg), 0) / 1000, 6) END AS carbon_tha
  FROM tree_rows r
  JOIN shared.plots p ON p.plot_id = r.plot_id
 GROUP BY r.plot_id, r.variant_id, r.location_id, p.sampling_design_id, p.stratum_id,
          p.sampling_weight, r.species_id;


-- -----------------------------------------------------------------------------
-- 2. Which run holds the variant chain
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.simulation_runs AS
SELECT r.simulation_run_id,
       r.simulator_name,
       r.simulator_version,
       s.scenario_name,
       l.location_name,
       agg.first_year,
       agg.last_year,
       agg.year_steps,
       agg.tree_count,
       r.created_at,
       r.created_by::text AS created_by,
       r.base_year,
       r.horizon_years,
       bv.variant_name AS base_variant_name,
       r.seed,
       r.is_mortality_enabled,
       r.is_promoted,
       r.run_params,
       (r.is_promoted AND NOT EXISTS (
            SELECT 1 FROM trees.simulation_runs newer
             WHERE newer.is_promoted
               AND newer.location_id = r.location_id
               AND newer.scenario_id = r.scenario_id
               AND newer.created_at > r.created_at)) AS holds_variant_chain
  FROM trees.simulation_runs r
  LEFT JOIN shared.scenarios s  ON s.scenario_id = r.scenario_id
  LEFT JOIN shared.locations l  ON l.location_id = r.location_id
  LEFT JOIN shared.variants bv  ON bv.variant_id = r.base_variant_id
  LEFT JOIN LATERAL (
        SELECT min(gs.projection_year) AS first_year,
               max(gs.projection_year) AS last_year,
               count(DISTINCT gs.projection_year) AS year_steps,
               count(DISTINCT gs.tree_entity_id) AS tree_count
          FROM trees.growth_simulations gs
         WHERE gs.simulation_run_id = r.simulation_run_id
  ) agg ON true;

COMMENT ON COLUMN trees.simulation_runs.is_promoted IS
    'True if the run wrote the shared.variants chain UE reads when it ran. Never cleared: a later promoted run of the same location and scenario (--replace) takes the chain over, and public.simulation_runs.holds_variant_chain marks the one that holds it now. False for a comparison-only run (silva-connector --no-promote).';

NOTIFY pgrst, 'reload schema';
