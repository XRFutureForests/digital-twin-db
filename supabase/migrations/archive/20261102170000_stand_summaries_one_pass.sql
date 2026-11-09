-- =============================================================================
-- Stand summaries: all-species and per-species estimates in one pass
-- =============================================================================
-- Follow-up to 20261102160000. public.stand_summaries called
-- shared.estimate_stand twice per design and variant, once for all species
-- and once by species, and each call summed the variant's trees again. An
-- unfiltered read (what the portal's data page sends to count rows) took
-- 3.8 s on dt.unr, past the anonymous 3 s timeout.
--
-- shared.estimate_stand_domains(design, variant, all_species, per_species,
-- confidence) holds the estimator (body unchanged from 20261102140000 except
-- which domains it returns) and returns both domain sets from one pass over
-- the trees. shared.estimate_stand keeps its signature and results and calls
-- it; the view calls it once per design and variant.
--
-- Mirrored to init 78-stand-summaries-one-pass.sql.
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.estimate_stand_domains(
    p_sampling_design_id integer,
    p_variant_id         integer,
    p_all_species        boolean,
    p_per_species        boolean,
    p_confidence         numeric
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
        SELECT DISTINCT ps.species_id, true AS by_sp FROM ps WHERE p_per_species
        UNION ALL
        SELECT NULL::integer, false WHERE p_all_species
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

COMMENT ON FUNCTION shared.estimate_stand_domains(integer, integer, boolean, boolean, numeric) IS
    'The design-based estimator behind shared.estimate_stand, returning the all-species rows (by_species false), the per-species rows, or both from one pass over the trees. See shared.estimate_stand for the method.';

GRANT EXECUTE ON FUNCTION shared.estimate_stand_domains(integer, integer, boolean, boolean, numeric)
    TO anon, authenticated, service_role;

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
LANGUAGE sql
STABLE
SET search_path TO ''
AS $$
    SELECT * FROM shared.estimate_stand_domains(p_sampling_design_id, p_variant_id,
                                                NOT p_by_species, p_by_species, p_confidence);
$$;

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
 CROSS JOIN LATERAL shared.estimate_stand_domains(pr.sampling_design_id, pr.variant_id, true, true, 0.95) e
  LEFT JOIN shared.species sp     ON sp.species_id = e.species_id
 WHERE e.n_units > 0;

NOTIFY pgrst, 'reload schema';
