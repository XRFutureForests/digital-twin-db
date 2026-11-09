-- =============================================================================
-- Stand summaries: per-plot per-hectare values and design-based estimates
-- =============================================================================
-- XRFF-627. The database held single trees and no stand-level results, which
-- are what forest practitioners work with. This adds the aggregation inside
-- the database, as views and SQL functions over the sampling designs of
-- XRFF-626 (migration 20261102130000). No simulator and no external job
-- (owner, 2026-11-02).
--
-- * shared.sample_unit_id(plot_id)
--     the sample unit a tree's plot belongs to: the plot itself when its
--     design has inclusion rules (fixed radius, nested circles, angle count),
--     otherwise the nearest plot up the parent chain that has an area. On a
--     fully mapped site that is the site-wide census plot; the plots inside it
--     are labels.
-- * public.plot_summaries
--     per sample unit x variant x species: stems, basal area, volume, biomass
--     and carbon per hectare, each tree weighted by its expansion factor.
--     Living trees only (status not dead, harvested, missing or downed; no
--     status counts as living). A value is NULL when a counted tree lacks it,
--     so a partial sum never passes for a complete one.
-- * shared.t_quantile(confidence, df)
--     two-sided Student t quantile for 0.90 / 0.95 / 0.99 from a table
--     (df 1-30, 40, 60, 120, infinity); between table rows the next lower df
--     is used, which widens the interval slightly rather than narrowing it.
-- * shared.estimate_stand(design, variant, by_species, confidence)
--     design-based estimate per variable: mean per hectare and its accuracy
--     in the forms forestry reports it -- standard error, relative standard
--     error in %, margin of error (t x SE) and sampling error in % of the
--     estimate at the chosen confidence (the usual "+/- x % at 95 %"), and the
--     confidence interval -- plus number of units, area and total.
--       census        area-weighted mean of the units; no sampling error
--       simple_random, systematic
--                     weighted mean over units (sampling_weight); variance
--                     n/(n-1) * sum(w_i (y_i - ybar))^2 / (sum w)^2, i.e. with
--                     replacement and without finite population correction,
--                     as R survey's svymean and Open Foris Arena compute it.
--                     A systematic sample is treated as simple random, which
--                     usually overstates its error.
--       stratified_random, stratified_systematic
--                     the same within each stratum, combined with weights
--                     strata.area_ha / sum(area_ha); df = n - number of strata
--       two_phase     not supported yet: rows come back with NULL values and
--                     the reason in `method`.
--     Units without living trees count as zero; by species, a unit without
--     that species counts as zero for it. Totals use the design's
--     reporting_area_ha, else the strata or census area.
-- * public.estimate_stand(...)  the same, callable as /rest/v1/rpc/estimate_stand
-- * public.stand_summaries, public.ue_stand_summary
--     every design x variant of its location, all species and by species,
--     flat with names, 95 % intervals. Filter on variant_id.
--
-- Mirrored to init 75-stand-summaries.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Sample unit of a plot
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION shared.sample_unit_id(p_plot_id integer)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path TO ''
AS $$
    WITH RECURSIVE up AS (
        SELECT p.plot_id, p.parent_plot_id, p.sampling_design_id, p.area_m2, 0 AS depth
          FROM shared.plots p
         WHERE p.plot_id = p_plot_id
        UNION ALL
        SELECT q.plot_id, q.parent_plot_id, q.sampling_design_id, q.area_m2, up.depth + 1
          FROM shared.plots q
          JOIN up ON q.plot_id = up.parent_plot_id
         WHERE up.depth < 10
    ),
    design AS (
        SELECT u.sampling_design_id
          FROM up u
         WHERE u.sampling_design_id IS NOT NULL
         ORDER BY u.depth
         LIMIT 1
    )
    SELECT CASE
        WHEN EXISTS (SELECT 1 FROM shared.inclusion_rules r
                      WHERE r.sampling_design_id = (SELECT sampling_design_id FROM design))
            THEN (SELECT u.plot_id FROM up u WHERE u.depth = 0)
        ELSE (SELECT u.plot_id FROM up u WHERE u.area_m2 > 0 ORDER BY u.depth LIMIT 1)
    END;
$$;

COMMENT ON FUNCTION shared.sample_unit_id(integer) IS
    'Sample unit a plot''s trees belong to: the plot itself when its design has inclusion rules, otherwise the nearest plot up the parent chain with an area (on a fully mapped site, the census plot). NULL when there is none.';

GRANT EXECUTE ON FUNCTION shared.sample_unit_id(integer) TO anon, authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 2. Per-plot summaries
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.plot_summaries WITH (security_invoker = on) AS
WITH tree_rows AS (
    SELECT t.variant_id,
           t.location_id,
           t.species_id,
           shared.sample_unit_id(t.plot_id)                   AS plot_id,
           shared.expansion_factor_ha(t.plot_id, s1.dbh_cm)   AS ef,
           ba.basal_area_m2,
           t.volume_m3,
           t.biomass_kg,
           t.carbon_content_kg
      FROM trees.trees t
      LEFT JOIN trees.stems s1       ON s1.tree_id = t.tree_id AND s1.stem_number = 1
      LEFT JOIN trees.tree_status ts ON ts.tree_status_id = t.tree_status_id
      LEFT JOIN LATERAL (
            SELECT sum(pi() * (s.dbh_cm / 200.0) ^ 2)::numeric AS basal_area_m2
              FROM trees.stems s
             WHERE s.tree_id = t.tree_id
      ) ba ON true
     WHERE t.plot_id IS NOT NULL
       AND coalesce(ts.tree_status_name, '') NOT IN ('dead', 'harvested', 'missing', 'downed')
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

COMMENT ON VIEW public.plot_summaries IS
    'Per sample unit (plot, or the census plot of a fully mapped site), variant and species: living trees per hectare and their basal area, volume, biomass and carbon per hectare, each tree weighted by its expansion factor. A value is NULL when a counted tree lacks it. Sum over species for the all-species value. Filter on variant_id.';


-- -----------------------------------------------------------------------------
-- 3. Student t quantile
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION shared.t_quantile(p_confidence numeric, p_df integer)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $$
    SELECT CASE p_confidence WHEN 0.90 THEN t.q90 WHEN 0.95 THEN t.q95 WHEN 0.99 THEN t.q99 END
      FROM (VALUES
        (1, 6.314, 12.706, 63.657), (2, 2.920, 4.303, 9.925), (3, 2.353, 3.182, 5.841),
        (4, 2.132, 2.776, 4.604),   (5, 2.015, 2.571, 4.032), (6, 1.943, 2.447, 3.707),
        (7, 1.895, 2.365, 3.499),   (8, 1.860, 2.306, 3.355), (9, 1.833, 2.262, 3.250),
        (10, 1.812, 2.228, 3.169),  (11, 1.796, 2.201, 3.106), (12, 1.782, 2.179, 3.055),
        (13, 1.771, 2.160, 3.012),  (14, 1.761, 2.145, 2.977), (15, 1.753, 2.131, 2.947),
        (16, 1.746, 2.120, 2.921),  (17, 1.740, 2.110, 2.898), (18, 1.734, 2.101, 2.878),
        (19, 1.729, 2.093, 2.861),  (20, 1.725, 2.086, 2.845), (21, 1.721, 2.080, 2.831),
        (22, 1.717, 2.074, 2.819),  (23, 1.714, 2.069, 2.807), (24, 1.711, 2.064, 2.797),
        (25, 1.708, 2.060, 2.787),  (26, 1.706, 2.056, 2.779), (27, 1.703, 2.052, 2.771),
        (28, 1.701, 2.048, 2.763),  (29, 1.699, 2.045, 2.756), (30, 1.697, 2.042, 2.750),
        (40, 1.684, 2.021, 2.704),  (60, 1.671, 2.000, 2.660), (120, 1.658, 1.980, 2.617),
        (2147483647, 1.645, 1.960, 2.576)
      ) AS t(df, q90, q95, q99)
     WHERE p_df >= 1 AND t.df <= p_df
     ORDER BY t.df DESC
     LIMIT 1;
$$;

COMMENT ON FUNCTION shared.t_quantile(numeric, integer) IS
    'Two-sided Student t quantile for confidence 0.90, 0.95 or 0.99 and df >= 1, from a table (df 1-30, 40, 60, 120, infinity; between rows the next lower df, i.e. slightly wider). NULL otherwise.';

GRANT EXECUTE ON FUNCTION shared.t_quantile(numeric, integer) TO anon, authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 4. Design-based estimate
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION shared.estimate_stand(
    p_sampling_design_id integer,
    p_variant_id         integer,
    p_by_species         boolean DEFAULT false,
    p_confidence         numeric DEFAULT 0.95
)
RETURNS TABLE (
    sampling_design_id   integer,
    variant_id           integer,
    by_species           boolean,
    species_id           integer,
    variable             text,
    unit                 text,
    estimate             numeric,
    standard_error       numeric,
    relative_standard_error_pct numeric,
    margin_of_error      numeric,
    sampling_error_pct   numeric,
    ci_low               numeric,
    ci_high              numeric,
    confidence           numeric,
    n_units              integer,
    area_ha              numeric,
    total                numeric,
    total_standard_error numeric,
    method               text
)
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $$
DECLARE
    v_strategy   text;
    v_reporting  numeric;
    v_has_rules  boolean;
    v_location   integer;
    v_stratified boolean;
    v_method     text;
BEGIN
    IF p_confidence IS NULL OR p_confidence NOT IN (0.90, 0.95, 0.99) THEN
        RAISE EXCEPTION 'confidence must be 0.90, 0.95 or 0.99, got %', p_confidence;
    END IF;

    SELECT d.strategy, d.reporting_area_ha,
           EXISTS (SELECT 1 FROM shared.inclusion_rules r WHERE r.sampling_design_id = d.sampling_design_id)
      INTO v_strategy, v_reporting, v_has_rules
      FROM shared.sampling_designs d
     WHERE d.sampling_design_id = p_sampling_design_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT v.location_id INTO v_location FROM shared.variants v WHERE v.variant_id = p_variant_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    v_stratified := v_strategy IN ('stratified_random', 'stratified_systematic');
    v_method := CASE v_strategy
        WHEN 'census'                THEN 'census: area-weighted mean of the census units, no sampling error'
        WHEN 'simple_random'         THEN 'simple random: weighted mean, with-replacement variance, no finite population correction'
        WHEN 'systematic'            THEN 'systematic, estimated as simple random (usually overstates the error): weighted mean, with-replacement variance, no finite population correction'
        WHEN 'stratified_random'     THEN 'stratified: per-stratum weighted mean combined by stratum area, with-replacement variance, no finite population correction'
        WHEN 'stratified_systematic' THEN 'stratified systematic, estimated as stratified random: per-stratum weighted mean combined by stratum area, with-replacement variance, no finite population correction'
        ELSE 'not supported: ' || v_strategy
    END;

    RETURN QUERY
    WITH units AS (
        -- Sample units of the design at the variant's site. Rule designs: every
        -- plot of the design without child plots of the design. Area designs:
        -- every plot of the design with an area.
        SELECT p.plot_id, p.stratum_id, p.sampling_weight AS w, p.area_m2
          FROM shared.plots p
         WHERE p.sampling_design_id = p_sampling_design_id
           AND p.location_id = v_location
           AND CASE WHEN v_has_rules
                    THEN NOT EXISTS (SELECT 1 FROM shared.plots c
                                      WHERE c.parent_plot_id = p.plot_id
                                        AND c.sampling_design_id = p_sampling_design_id)
                    ELSE p.area_m2 > 0
               END
    ),
    ps AS (
        SELECT s.*
          FROM public.plot_summaries s
         WHERE s.variant_id = p_variant_id
           AND s.plot_id IN (SELECT u.plot_id FROM units u)
    ),
    domains AS (
        SELECT DISTINCT ps.species_id, true AS by_sp FROM ps WHERE p_by_species
        UNION ALL
        SELECT NULL::integer, false WHERE NOT p_by_species
    ),
    vars (variable, unit, ord) AS (
        VALUES ('stems_ha', '1/ha', 1), ('basal_area_m2ha', 'm2/ha', 2), ('volume_m3ha', 'm3/ha', 3),
               ('biomass_tha', 't/ha', 4), ('carbon_tha', 't/ha', 5)
    ),
    y AS (
        -- one value per unit, domain and variable; a unit without trees in the
        -- domain is a zero, a unit with an incomplete value is NULL
        SELECT u.plot_id, u.stratum_id, u.w, u.area_m2, dm.species_id, dm.by_sp,
               vr.variable, vr.unit, vr.ord,
               CASE WHEN count(ps.plot_id) = 0 THEN 0
                    WHEN bool_and(CASE vr.variable
                                      WHEN 'stems_ha'        THEN ps.stems_ha
                                      WHEN 'basal_area_m2ha' THEN ps.basal_area_m2ha
                                      WHEN 'volume_m3ha'     THEN ps.volume_m3ha
                                      WHEN 'biomass_tha'     THEN ps.biomass_tha
                                      WHEN 'carbon_tha'      THEN ps.carbon_tha
                                  END IS NOT NULL)
                    THEN sum(CASE vr.variable
                                 WHEN 'stems_ha'        THEN ps.stems_ha
                                 WHEN 'basal_area_m2ha' THEN ps.basal_area_m2ha
                                 WHEN 'volume_m3ha'     THEN ps.volume_m3ha
                                 WHEN 'biomass_tha'     THEN ps.biomass_tha
                                 WHEN 'carbon_tha'      THEN ps.carbon_tha
                             END)
               END AS y
          FROM units u
         CROSS JOIN domains dm
         CROSS JOIN vars vr
          LEFT JOIN ps ON ps.plot_id = u.plot_id
                      AND (NOT dm.by_sp OR ps.species_id IS NOT DISTINCT FROM dm.species_id)
         GROUP BY u.plot_id, u.stratum_id, u.w, u.area_m2, dm.species_id, dm.by_sp,
                  vr.variable, vr.unit, vr.ord
    ),
    per_stratum AS (
        SELECT y.species_id, y.by_sp, y.variable, y.unit, y.ord,
               CASE WHEN v_stratified THEN y.stratum_id ELSE 0 END AS h,
               count(*)                     AS n_h,
               bool_and(y.y IS NOT NULL)    AS complete,
               sum(y.w)                     AS w_h,
               sum(y.w * y.y) / sum(y.w)    AS ybar_h,
               sum(y.area_m2 * y.y) / nullif(sum(y.area_m2), 0) AS area_mean_h,
               sum(y.area_m2)               AS area_m2_h
          FROM y
         GROUP BY 1, 2, 3, 4, 5, 6
    ),
    with_var AS (
        SELECT s.*,
               CASE WHEN s.n_h >= 2
                    THEN s.n_h::numeric / (s.n_h - 1)
                         * (SELECT sum((y.w * (y.y - s.ybar_h)) ^ 2)
                              FROM y
                             WHERE y.species_id IS NOT DISTINCT FROM s.species_id
                               AND y.by_sp = s.by_sp
                               AND y.variable = s.variable
                               AND (CASE WHEN v_stratified THEN y.stratum_id ELSE 0 END)
                                   IS NOT DISTINCT FROM s.h)
                         / s.w_h ^ 2
               END AS var_h,
               st.area_ha AS stratum_area_ha
          FROM per_stratum s
          LEFT JOIN shared.strata st ON v_stratified AND st.stratum_id = s.h
    ),
    combined AS (
        SELECT c.species_id, c.by_sp, c.variable, c.unit, c.ord,
               sum(c.n_h)::integer                          AS n,
               count(*)                                     AS n_strata,
               bool_and(c.complete)                         AS complete,
               bool_and(c.h IS NOT NULL AND (NOT v_stratified OR c.stratum_area_ha IS NOT NULL))
                                                            AS weights_ok,
               bool_and(c.var_h IS NOT NULL)                AS var_ok,
               sum(c.stratum_area_ha)                       AS strata_area_ha,
               sum(c.area_m2_h) / 10000                     AS census_area_ha,
               CASE WHEN v_strategy = 'census'
                    THEN sum(c.area_mean_h * c.area_m2_h) / nullif(sum(c.area_m2_h), 0)
                    WHEN v_stratified
                    THEN sum(c.stratum_area_ha * c.ybar_h) / nullif(sum(c.stratum_area_ha), 0)
                    ELSE sum(c.ybar_h)
               END                                          AS est,
               CASE WHEN v_stratified
                    THEN sum((c.stratum_area_ha / nullif((SELECT sum(c2.stratum_area_ha) FROM with_var c2
                                                          WHERE c2.species_id IS NOT DISTINCT FROM c.species_id
                                                            AND c2.by_sp = c.by_sp AND c2.variable = c.variable), 0)) ^ 2
                             * c.var_h)
                    ELSE sum(c.var_h)
               END                                          AS var
          FROM with_var c
         GROUP BY 1, 2, 3, 4, 5
    ),
    final AS (
        SELECT c.*,
               CASE WHEN v_strategy NOT IN ('census', 'simple_random', 'systematic',
                                            'stratified_random', 'stratified_systematic')
                         OR NOT c.complete OR NOT c.weights_ok
                    THEN NULL ELSE c.est END AS est_ok,
               CASE WHEN v_strategy IN ('simple_random', 'systematic',
                                        'stratified_random', 'stratified_systematic')
                         AND c.complete AND c.weights_ok AND c.var_ok
                    THEN sqrt(c.var) END AS se,
               shared.t_quantile(p_confidence, (c.n - c.n_strata)::integer) AS tq,
               CASE WHEN v_strategy = 'census' THEN c.census_area_ha
                    WHEN v_stratified THEN c.strata_area_ha END AS area
          FROM combined c
    )
    SELECT p_sampling_design_id,
           p_variant_id,
           f.by_sp,
           f.species_id,
           f.variable,
           f.unit,
           round(f.est_ok, 4),
           round(f.se, 4),
           round(100 * f.se / nullif(f.est_ok, 0), 2),
           round(f.tq * f.se, 4),
           round(100 * f.tq * f.se / nullif(f.est_ok, 0), 2),
           round(f.est_ok - f.tq * f.se, 4),
           round(f.est_ok + f.tq * f.se, 4),
           p_confidence,
           f.n,
           round(f.area, 4),
           round(f.est_ok * coalesce(v_reporting, f.area), 2),
           round(f.se * coalesce(v_reporting, f.area), 2),
           v_method
      FROM final f
     ORDER BY f.by_sp, f.species_id NULLS FIRST, f.ord;
END;
$$;

COMMENT ON FUNCTION shared.estimate_stand(integer, integer, boolean, numeric) IS
    'Design-based estimate per variable (stems, basal area, volume, biomass, carbon per hectare) for one sampling design and variant: mean, standard error, confidence interval (0.90/0.95/0.99), number of units, area and total. Census, simple random, systematic (as simple random) and stratified designs; two_phase returns NULLs. With-replacement variance, no finite population correction. `method` states which estimator was used.';

GRANT EXECUTE ON FUNCTION shared.estimate_stand(integer, integer, boolean, numeric) TO anon, authenticated, service_role;

-- Callable over REST as /rest/v1/rpc/estimate_stand.
CREATE OR REPLACE FUNCTION public.estimate_stand(
    p_sampling_design_id integer,
    p_variant_id         integer,
    p_by_species         boolean DEFAULT false,
    p_confidence         numeric DEFAULT 0.95
)
RETURNS TABLE (
    sampling_design_id   integer,
    variant_id           integer,
    by_species           boolean,
    species_id           integer,
    variable             text,
    unit                 text,
    estimate             numeric,
    standard_error       numeric,
    relative_standard_error_pct numeric,
    margin_of_error      numeric,
    sampling_error_pct   numeric,
    ci_low               numeric,
    ci_high              numeric,
    confidence           numeric,
    n_units              integer,
    area_ha              numeric,
    total                numeric,
    total_standard_error numeric,
    method               text
)
LANGUAGE sql
STABLE
SET search_path TO ''
AS $$
    SELECT * FROM shared.estimate_stand(p_sampling_design_id, p_variant_id, p_by_species, p_confidence);
$$;

COMMENT ON FUNCTION public.estimate_stand(integer, integer, boolean, numeric) IS
    'REST entry point for shared.estimate_stand: POST /rest/v1/rpc/estimate_stand {"p_sampling_design_id":..,"p_variant_id":..,"p_by_species":false,"p_confidence":0.95}.';

GRANT EXECUTE ON FUNCTION public.estimate_stand(integer, integer, boolean, numeric) TO anon, authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 5. Stand summaries for every design and variant
-- -----------------------------------------------------------------------------
-- One estimate per sampling design x variant of the design's site, for all
-- species together and by species, at 95 %. Filter on variant_id (the filter
-- reaches the design/variant pairs, so only that variant is computed).

CREATE OR REPLACE VIEW public.stand_summaries WITH (security_invoker = on) AS
WITH pairs AS (
    SELECT DISTINCT p.sampling_design_id, v.variant_id
      FROM shared.variants v
      JOIN shared.plots p ON p.location_id = v.location_id
     WHERE p.sampling_design_id IS NOT NULL
)
SELECT pr.variant_id,
       v.variant_name,
       v.simulation_year,
       v.location_id,
       l.location_name,
       v.scenario_id,
       sc.scenario_name,
       pr.sampling_design_id,
       d.design_name,
       d.strategy,
       e.by_species,
       e.species_id,
       sp.scientific_name AS species_name,
       e.variable,
       e.unit,
       e.estimate,
       e.standard_error,
       e.relative_standard_error_pct,
       e.margin_of_error,
       e.sampling_error_pct,
       e.ci_low,
       e.ci_high,
       e.confidence,
       e.n_units,
       e.area_ha,
       e.total,
       e.total_standard_error,
       e.method
  FROM pairs pr
  JOIN shared.variants v          ON v.variant_id = pr.variant_id
  JOIN shared.locations l         ON l.location_id = v.location_id
  LEFT JOIN shared.scenarios sc   ON sc.scenario_id = v.scenario_id
  JOIN shared.sampling_designs d  ON d.sampling_design_id = pr.sampling_design_id
 CROSS JOIN LATERAL (
        SELECT * FROM shared.estimate_stand(pr.sampling_design_id, pr.variant_id, false, 0.95)
        UNION ALL
        SELECT * FROM shared.estimate_stand(pr.sampling_design_id, pr.variant_id, true, 0.95)
 ) e
  LEFT JOIN shared.species sp     ON sp.species_id = e.species_id
 WHERE e.n_units > 0;

COMMENT ON VIEW public.stand_summaries IS
    'Per-hectare stand values of every variant for each sampling design of its site, all species (by_species false) and per species: estimate, standard error, relative standard error %, margin of error and sampling error % at 95 %, confidence interval, units, area and total. Census designs have no sampling error. Filter on variant_id; other confidence levels via /rpc/estimate_stand.';

-- Unreal reads the same flat rows under the ue_ prefix its other views use.
CREATE OR REPLACE VIEW public.ue_stand_summary WITH (security_invoker = on) AS
SELECT * FROM public.stand_summaries;

COMMENT ON VIEW public.ue_stand_summary IS
    'public.stand_summaries under the ue_ prefix for Unreal: GET /ue_stand_summary?variant_id=eq.<id>&by_species=is.false';

GRANT SELECT ON public.plot_summaries, public.stand_summaries, public.ue_stand_summary
    TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
