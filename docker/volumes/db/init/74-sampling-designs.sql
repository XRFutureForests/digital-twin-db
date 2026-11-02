-- =============================================================================
-- Sampling designs, inclusion rules, strata and a per-tree expansion factor
-- =============================================================================
-- XRFF-626. Until now the database could only hold full censuses: every tree
-- of a site mapped, and `shared.plots` carrying nothing but an optional
-- `area_m2` (empty on every plot today). A sampled inventory -- fixed-radius
-- circles, nested circles with DBH thresholds, angle-count plots, strata,
-- clusters -- could be loaded tree by tree, but no per-hectare value could be
-- computed from it, because nothing said how much forest each tree stands for.
--
-- The model follows Open Foris Arena's chain sampling design
-- (openforis/arena, common/analysis/chainSamplingDesign.js: strategy, base
-- unit, cluster, stratum, weight per base unit, measured area per entity) and
-- adds what Arena leaves to the survey author: the inclusion rule that decides
-- in which radius a tree of a given DBH was measured, including angle-count
-- sampling (a basal-area factor instead of a radius).
--
-- * shared.sampling_designs  one per inventory protocol: strategy, protocol and
--                            version, DBH measuring height, minimum DBH,
--                            reporting area.
-- * shared.inclusion_rules   per design, per DBH range: a fixed radius or a
--                            basal-area factor. No rules = the plot's own area
--                            is the inclusion area (census or fixed-area plot).
-- * shared.strata            per design, with area in ha.
-- * shared.plots             + design, stratum, parent plot (cluster -> plot ->
--                            subplot), sampling weight, area source.
-- * trees.stems              + dbh_measuring_height_m (NULL = design / 1.3 m).
-- * shared.expansion_factor_ha(plot_id, dbh_cm)
--                            trees per hectare that one tree stands for.
-- * public.sampling_designs, public.inclusion_rules, public.strata,
--   public.tree_expansion_factors; public.plots and public.stems gain the
--   new columns.
--
-- The sampling weight is kept apart from the expansion factor, as in Arena:
-- the expansion factor turns a tree into per-hectare terms, the weight is the
-- estimator's business (XRFF-627).
--
-- Existing data is untouched: every new column is NULL or defaults to the
-- value that means "as before" (sampling_weight 1). No plot has an area yet,
-- so no expansion factor exists until one is entered. Both current sites are
-- fully mapped: scripts/seed/census_site_plots.sql gives each a site-wide
-- census plot whose area is the convex hull of the measured baseline (as
-- silva-connector derives stand area, R/stand.R) and hangs the existing plots
-- under it; the expansion factor walks up to that area.
--
-- Additive only: no column of an existing view changes or moves, so callers
-- are unaffected. Consumers checked (AGENTS.md rule): silva-connector and
-- digital-twin-dashboard name their columns of shared.plots / trees.stems.
--
-- Mirrored to init 74-sampling-designs.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS shared.sampling_designs (
    sampling_design_id      serial PRIMARY KEY,
    design_name             varchar(200) NOT NULL UNIQUE,
    strategy                varchar(30)  NOT NULL
        CHECK (strategy IN ('census', 'simple_random', 'systematic',
                            'stratified_random', 'stratified_systematic', 'two_phase')),
    protocol_name           varchar(200),
    protocol_version        varchar(50),
    dbh_measuring_height_m  numeric(4,2) NOT NULL DEFAULT 1.3
        CHECK (dbh_measuring_height_m > 0),
    min_dbh_cm              numeric(6,2) CHECK (min_dbh_cm >= 0),
    reporting_area_ha       numeric(14,4) CHECK (reporting_area_ha > 0),
    description             text,
    created_at              timestamptz DEFAULT now(),
    updated_at              timestamptz DEFAULT now(),
    created_by              varchar(200),
    updated_by              varchar(200)
);

COMMENT ON TABLE shared.sampling_designs IS
    'One inventory protocol: how plots were chosen (strategy), which field manual and version, at which height DBH is measured and from which DBH trees are recorded. Plots point here; inclusion rules and strata hang off it. strategy = census means every tree of the plot area was recorded.';
COMMENT ON COLUMN shared.sampling_designs.strategy IS
    'How the sample units were chosen: census | simple_random | systematic | stratified_random | stratified_systematic | two_phase (Open Foris Arena''s strategies plus census).';
COMMENT ON COLUMN shared.sampling_designs.protocol_name IS
    'Field manual or inventory protocol the data was measured under, e.g. BWI 2022 Aufnahmeanweisung.';
COMMENT ON COLUMN shared.sampling_designs.dbh_measuring_height_m IS
    'Height above ground at which DBH is measured under this protocol (1.3 m in Europe, 1.37 m in the US). trees.stems.dbh_measuring_height_m overrides it per stem.';
COMMENT ON COLUMN shared.sampling_designs.min_dbh_cm IS
    'Smallest DBH recorded under this protocol. Trees below it get no expansion factor. NULL = no threshold.';
COMMENT ON COLUMN shared.sampling_designs.reporting_area_ha IS
    'Area of the population the sample represents (the inventory area), for totals. NULL = per-hectare results only.';

CREATE TABLE IF NOT EXISTS shared.inclusion_rules (
    inclusion_rule_id        serial PRIMARY KEY,
    sampling_design_id       integer NOT NULL
        REFERENCES shared.sampling_designs (sampling_design_id) ON DELETE CASCADE,
    min_dbh_cm               numeric(6,2) NOT NULL DEFAULT 0 CHECK (min_dbh_cm >= 0),
    max_dbh_cm               numeric(6,2),
    rule_type                varchar(20) NOT NULL
        CHECK (rule_type IN ('fixed_radius', 'angle_count')),
    radius_m                 numeric(7,3) CHECK (radius_m > 0),
    basal_area_factor_m2ha   numeric(7,3) CHECK (basal_area_factor_m2ha > 0),
    description              text,
    created_at               timestamptz DEFAULT now(),
    updated_at               timestamptz DEFAULT now(),
    created_by               varchar(200),
    updated_by               varchar(200),
    CHECK (max_dbh_cm IS NULL OR max_dbh_cm > min_dbh_cm),
    CHECK ((rule_type = 'fixed_radius' AND radius_m IS NOT NULL AND basal_area_factor_m2ha IS NULL)
        OR (rule_type = 'angle_count'  AND basal_area_factor_m2ha IS NOT NULL AND radius_m IS NULL))
);

COMMENT ON TABLE shared.inclusion_rules IS
    'Which trees a plot of this design records, by DBH range: within a fixed radius (one rule = fixed-radius plot, several = nested circles) or by angle count with a basal-area factor. Ranges of one design must not overlap. A design without rules uses each plot''s own area (shared.plots.area_m2) as the inclusion area.';
COMMENT ON COLUMN shared.inclusion_rules.min_dbh_cm IS 'Lower DBH bound of the rule, inclusive.';
COMMENT ON COLUMN shared.inclusion_rules.max_dbh_cm IS 'Upper DBH bound of the rule, exclusive. NULL = no upper bound.';
COMMENT ON COLUMN shared.inclusion_rules.radius_m IS 'Horizontal plot radius for fixed_radius rules.';
COMMENT ON COLUMN shared.inclusion_rules.basal_area_factor_m2ha IS 'Basal-area factor (m²/ha per counted tree) for angle_count rules, e.g. 4 in the German national inventory.';

CREATE INDEX IF NOT EXISTS idx_inclusion_rules_design ON shared.inclusion_rules (sampling_design_id);

-- Overlapping DBH ranges would make the expansion factor ambiguous. A trigger
-- rather than an exclusion constraint, which would need btree_gist.
CREATE OR REPLACE FUNCTION shared.check_inclusion_rule_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM shared.inclusion_rules r
         WHERE r.sampling_design_id = NEW.sampling_design_id
           AND r.inclusion_rule_id <> NEW.inclusion_rule_id
           AND numrange(r.min_dbh_cm, r.max_dbh_cm, '[)') && numrange(NEW.min_dbh_cm, NEW.max_dbh_cm, '[)')
    ) THEN
        RAISE EXCEPTION 'Inclusion rule DBH range [%, %) overlaps another rule of sampling design %',
            NEW.min_dbh_cm, coalesce(NEW.max_dbh_cm::text, 'inf'), NEW.sampling_design_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_inclusion_rules_no_overlap ON shared.inclusion_rules;
CREATE TRIGGER trigger_inclusion_rules_no_overlap
    BEFORE INSERT OR UPDATE ON shared.inclusion_rules
    FOR EACH ROW EXECUTE FUNCTION shared.check_inclusion_rule_overlap();

CREATE TABLE IF NOT EXISTS shared.strata (
    stratum_id          serial PRIMARY KEY,
    sampling_design_id  integer NOT NULL
        REFERENCES shared.sampling_designs (sampling_design_id) ON DELETE CASCADE,
    stratum_name        varchar(200) NOT NULL,
    area_ha             numeric(14,4) CHECK (area_ha > 0),
    description         text,
    created_at          timestamptz DEFAULT now(),
    updated_at          timestamptz DEFAULT now(),
    created_by          varchar(200),
    updated_by          varchar(200),
    UNIQUE (sampling_design_id, stratum_name),
    UNIQUE (stratum_id, sampling_design_id)   -- target of the plots composite FK
);

COMMENT ON TABLE shared.strata IS
    'Strata of a stratified sampling design, with their area. A plot''s stratum must belong to the plot''s design.';
COMMENT ON COLUMN shared.strata.area_ha IS 'Stratum area in hectares; stratified estimators weight by it.';


-- -----------------------------------------------------------------------------
-- 2. New columns on plots and stems
-- -----------------------------------------------------------------------------

ALTER TABLE shared.plots
    ADD COLUMN IF NOT EXISTS sampling_design_id integer
        REFERENCES shared.sampling_designs (sampling_design_id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS stratum_id integer,
    ADD COLUMN IF NOT EXISTS parent_plot_id integer
        REFERENCES shared.plots (plot_id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS sampling_weight numeric(12,6) NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS area_source varchar(20);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plots_stratum_in_design_fkey') THEN
        ALTER TABLE shared.plots ADD CONSTRAINT plots_stratum_in_design_fkey
            FOREIGN KEY (stratum_id, sampling_design_id)
            REFERENCES shared.strata (stratum_id, sampling_design_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plots_sampling_weight_check') THEN
        ALTER TABLE shared.plots ADD CONSTRAINT plots_sampling_weight_check CHECK (sampling_weight > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plots_area_source_check') THEN
        ALTER TABLE shared.plots ADD CONSTRAINT plots_area_source_check
            CHECK (area_source IN ('surveyed', 'nominal', 'convex_hull'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plots_not_own_parent_check') THEN
        ALTER TABLE shared.plots ADD CONSTRAINT plots_not_own_parent_check
            CHECK (parent_plot_id IS NULL OR parent_plot_id <> plot_id);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_plots_sampling_design ON shared.plots (sampling_design_id);
CREATE INDEX IF NOT EXISTS idx_plots_parent ON shared.plots (parent_plot_id);

COMMENT ON COLUMN shared.plots.area_m2 IS
    'Plot area in square metres: the inclusion area of every tree when the design has no inclusion rules (census or fixed-area plot). A plot without an area inherits the nearest enclosing plot''s (parent_plot_id). Horizontal area; area_source says where it comes from.';
COMMENT ON COLUMN shared.plots.sampling_design_id IS 'Sampling design (protocol) this plot was laid out and measured under. NULL = none recorded.';
COMMENT ON COLUMN shared.plots.stratum_id IS 'Stratum of a stratified design; must belong to sampling_design_id.';
COMMENT ON COLUMN shared.plots.parent_plot_id IS 'Enclosing sample unit: a plot''s cluster, or a subplot''s plot. NULL = top level.';
COMMENT ON COLUMN shared.plots.sampling_weight IS 'Sampling weight of this unit for the estimator (Open Foris Arena''s weight); 1 = equal weight. Not part of the expansion factor.';
COMMENT ON COLUMN shared.plots.area_source IS 'Where area_m2 comes from: surveyed (measured boundary) | nominal (protocol size) | convex_hull (hull of the stem positions, as silva-connector derives stand area).';

ALTER TABLE trees.stems
    ADD COLUMN IF NOT EXISTS dbh_measuring_height_m numeric(4,2);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'stems_dbh_measuring_height_check') THEN
        ALTER TABLE trees.stems ADD CONSTRAINT stems_dbh_measuring_height_check
            CHECK (dbh_measuring_height_m IS NULL OR dbh_measuring_height_m > 0);
    END IF;
END;
$$;

COMMENT ON COLUMN trees.stems.dbh_cm IS
    'Stem diameter in centimetres at the measuring height: dbh_measuring_height_m, else the sampling design''s, else 1.3 m.';
COMMENT ON COLUMN trees.stems.dbh_measuring_height_m IS
    'Height at which dbh_cm was measured, when it differs from the design''s (e.g. raised above a buttress or a fork). NULL = the design''s height, 1.3 m without a design.';


-- -----------------------------------------------------------------------------
-- 3. Expansion factor
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION shared.expansion_factor_ha(p_plot_id integer, p_dbh_cm numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO ''
AS $$
    -- Trees per hectare one tree of DBH p_dbh_cm on plot p_plot_id stands for.
    --   fixed_radius rule: 10000 / (pi r^2)
    --   angle_count rule : BAF / g, with g = pi (dbh/200)^2 the tree's basal area in m^2
    --   no rules         : 10000 / area_m2
    -- Design and area are taken from the plot itself or, where it has none,
    -- from the nearest enclosing plot (parent_plot_id). That is what makes a
    -- fully mapped site work: one site-wide census plot carries the area, and
    -- the plots inside it are only labels. The walk stops after 10 levels, so
    -- a parent cycle cannot loop.
    -- NULL when it cannot be known: no plot, no area, no DBH where the rule
    -- needs one, or a DBH outside every rule or below the design's threshold.
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
    SELECT CASE
        WHEN NOT res.plot_exists THEN NULL
        WHEN d.min_dbh_cm IS NOT NULL AND (p_dbh_cm IS NULL OR p_dbh_cm < d.min_dbh_cm) THEN NULL
        WHEN EXISTS (SELECT 1 FROM shared.inclusion_rules r WHERE r.sampling_design_id = res.design_id) THEN (
            SELECT CASE r.rule_type
                       WHEN 'fixed_radius' THEN 10000 / (pi() * r.radius_m ^ 2)
                       WHEN 'angle_count'  THEN r.basal_area_factor_m2ha / (pi() * (p_dbh_cm / 200.0) ^ 2)
                   END
              FROM shared.inclusion_rules r
             WHERE r.sampling_design_id = res.design_id
               AND p_dbh_cm >= r.min_dbh_cm
               AND (r.max_dbh_cm IS NULL OR p_dbh_cm < r.max_dbh_cm)
               AND p_dbh_cm > 0
        )
        WHEN res.area_m2 > 0 THEN 10000 / res.area_m2
        ELSE NULL
    END::numeric
      FROM resolved res
      LEFT JOIN shared.sampling_designs d ON d.sampling_design_id = res.design_id;
$$;

COMMENT ON FUNCTION shared.expansion_factor_ha(integer, numeric) IS
    'Trees per hectare that one tree of the given DBH on the given plot stands for, from the sampling design: fixed radius 10000/(pi r²), angle count BAF/basal area, otherwise 10000/area_m2. Design and area come from the plot or, where it has none, its nearest enclosing plot (a fully mapped site: one census plot with the area, the plots inside it as labels). NULL when unknown. Excludes the sampling weight.';

GRANT EXECUTE ON FUNCTION shared.expansion_factor_ha(integer, numeric) TO anon, authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 4. Grants and row-level security (same pattern as shared.plots)
-- -----------------------------------------------------------------------------

GRANT SELECT ON TABLE shared.sampling_designs, shared.inclusion_rules, shared.strata TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE shared.sampling_designs, shared.inclusion_rules, shared.strata TO authenticated;
GRANT ALL ON TABLE shared.sampling_designs, shared.inclusion_rules, shared.strata TO service_role;
GRANT USAGE ON SEQUENCE shared.sampling_designs_sampling_design_id_seq,
                        shared.inclusion_rules_inclusion_rule_id_seq,
                        shared.strata_stratum_id_seq TO authenticated, service_role;

ALTER TABLE shared.sampling_designs ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.inclusion_rules  ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.strata           ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    t     record;
BEGIN
    FOR t IN SELECT * FROM (VALUES
        ('sampling_designs', 'Sampling designs'),
        ('inclusion_rules',  'Inclusion rules'),
        ('strata',           'Strata')
    ) AS v(tbl, label)
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON shared.%I', t.label || ' are viewable by everyone', t.tbl);
        EXECUTE format('CREATE POLICY %I ON shared.%I FOR SELECT USING (true)',
                       t.label || ' are viewable by everyone', t.tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I ON shared.%I', 'Contributors can manage ' || lower(t.label), t.tbl);
        EXECUTE format('CREATE POLICY %I ON shared.%I FOR ALL TO authenticated '
                       'USING (shared.is_contributor()) WITH CHECK (shared.is_contributor())',
                       'Contributors can manage ' || lower(t.label), t.tbl);
        EXECUTE format('DROP POLICY IF EXISTS %I ON shared.%I', 'Service role can manage all ' || lower(t.label), t.tbl);
        EXECUTE format('CREATE POLICY %I ON shared.%I TO service_role USING (true) WITH CHECK (true)',
                       'Service role can manage all ' || lower(t.label), t.tbl);

        EXECUTE format('DROP TRIGGER IF EXISTS %I ON shared.%I', 'trigger_' || t.tbl || '_created_by', t.tbl);
        EXECUTE format('CREATE TRIGGER %I BEFORE INSERT ON shared.%I FOR EACH ROW EXECUTE FUNCTION shared.set_created_by()',
                       'trigger_' || t.tbl || '_created_by', t.tbl);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON shared.%I', 'trigger_' || t.tbl || '_updated_by', t.tbl);
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON shared.%I FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by()',
                       'trigger_' || t.tbl || '_updated_by', t.tbl);
    END LOOP;
END;
$$;


-- -----------------------------------------------------------------------------
-- 5. Public views
-- -----------------------------------------------------------------------------
-- New pass-through views are auto-updatable, so inserts and updates go
-- through them with the caller's rights (security_invoker) and RLS applies.

CREATE OR REPLACE VIEW public.sampling_designs WITH (security_invoker = on) AS
SELECT sampling_design_id, design_name, strategy, protocol_name, protocol_version,
       dbh_measuring_height_m, min_dbh_cm, reporting_area_ha, description,
       created_at, updated_at, created_by, updated_by
  FROM shared.sampling_designs;

CREATE OR REPLACE VIEW public.inclusion_rules WITH (security_invoker = on) AS
SELECT inclusion_rule_id, sampling_design_id, min_dbh_cm, max_dbh_cm, rule_type,
       radius_m, basal_area_factor_m2ha, description,
       created_at, updated_at, created_by, updated_by
  FROM shared.inclusion_rules;

CREATE OR REPLACE VIEW public.strata WITH (security_invoker = on) AS
SELECT stratum_id, sampling_design_id, stratum_name, area_ha, description,
       created_at, updated_at, created_by, updated_by
  FROM shared.strata;

COMMENT ON VIEW public.sampling_designs IS 'Sampling designs (inventory protocols). Readable by everyone; contributors write.';
COMMENT ON VIEW public.inclusion_rules  IS 'Inclusion rules per sampling design: fixed radius or angle count by DBH range.';
COMMENT ON VIEW public.strata           IS 'Strata of stratified sampling designs, with area.';

-- public.plots: append the new columns (existing columns keep their order) and
-- let the INSTEAD OF INSERT trigger write them.
CREATE OR REPLACE VIEW public.plots WITH (security_invoker = on) AS
SELECT plot_id, location_id, plot_name, plot_number, area_m2, boundary, center_point,
       description, created_at, updated_at, created_by, updated_by,
       sampling_design_id, stratum_id, parent_plot_id, sampling_weight, area_source
  FROM shared.plots;

ALTER VIEW public.plots ALTER COLUMN sampling_weight SET DEFAULT 1;

CREATE OR REPLACE FUNCTION public.plots_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO shared.plots (
        location_id, plot_name, plot_number, area_m2,
        boundary, center_point, description,
        created_by, updated_by,
        sampling_design_id, stratum_id, parent_plot_id, sampling_weight, area_source
    ) VALUES (
        NEW.location_id, NEW.plot_name, NEW.plot_number, NEW.area_m2,
        NEW.boundary, NEW.center_point, NEW.description,
        NEW.created_by, NEW.updated_by,
        NEW.sampling_design_id, NEW.stratum_id, NEW.parent_plot_id,
        coalesce(NEW.sampling_weight, 1), NEW.area_source
    ) RETURNING plot_id INTO NEW.plot_id;
    RETURN NEW;
END;
$$;

-- public.stems: its insert trigger copies NEW.* positionally, so the view and
-- trees.stems must list the same columns in the same order. Both gain
-- dbh_measuring_height_m as their last column.
CREATE OR REPLACE VIEW public.stems WITH (security_invoker = on) AS
SELECT stem_id, tree_id, stem_number, taper_type_id, straightness_type_id, dbh_cm,
       taper_ratio, sweep_cm_per_m, stem_height_m, stem_volume_m3, bark_thickness_mm,
       wood_density_kg_m3, created_at, updated_at, dbh_measuring_height_m
  FROM trees.stems;

-- Per-tree expansion factor, from the main stem's DBH.
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
       shared.expansion_factor_ha(t.plot_id, s.dbh_cm) AS expansion_factor_ha
  FROM trees.trees t
  LEFT JOIN shared.plots p ON p.plot_id = t.plot_id
  LEFT JOIN trees.stems s  ON s.tree_id = t.tree_id AND s.stem_number = 1;

COMMENT ON VIEW public.tree_expansion_factors IS
    'Trees per hectare each tree stands for (shared.expansion_factor_ha on the main stem''s DBH), with the plot''s design, stratum and sampling weight. Filter on variant_id. NULL where the plot has no area or design.';

GRANT SELECT ON public.sampling_designs, public.inclusion_rules, public.strata,
                public.tree_expansion_factors TO anon, authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.sampling_designs, public.inclusion_rules, public.strata
    TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
