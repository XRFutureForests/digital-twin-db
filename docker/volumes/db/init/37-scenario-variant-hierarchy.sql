-- XR Future Forests Lab - Enforce Location -> Scenario -> Variant hierarchy
--
-- Previously "scenario" was conflated with "location + time step": each simulated
-- year was its own scenario (ecosense_growth_2035, mathisle_growth_2045, ...) and
-- every such scenario held exactly one variant, while the shared current_conditions
-- scenario held the baselines. A single growth trajectory was thus split across
-- three scenarios, and shared.Scenarios was a global table with no link to a site.
--
-- Correct model (strictly nested):
--   Location  (ecosense, mathisle)
--     Scenario  = a management regime that owns its initial conditions / baseline
--                 (e.g. natural_growth, intensive_management, extensive_management)
--       Variant = a state in that regime's timeline (baseline -> growth cycle ->
--                 management intervention -> ...), each developing from its parent
--
-- Changes:
--   * shared.Scenarios gains location_id (scenarios are now per-site); the global
--     UNIQUE(scenario_name) becomes UNIQUE(location_id, scenario_name).
--   * shared.Variants gains parent_variant_id (explicit lineage, mirrors
--     trees.parent_tree_id); sort_order is set to the timeline order.
--   * The existing per-year scenarios are consolidated into ONE 'natural_growth'
--     scenario per location, carrying baseline_2025 -> growth_2035 -> growth_2045.
--   * trees.scenario_id (redundant, was inconsistently populated) is resynced from
--     each tree's variant. The 7 empty demo scenarios are removed.
--
-- Idempotent: guarded DDL; re-pointing/cleanup are keyed on the pre-migration
-- shape (scenarios with NULL location_id), so a second run is a no-op.
--
-- Dependencies: 11-shared-schema.sql, 36-restructure-locations-plots-snakecase.sql

BEGIN;

-- =============================================================================
-- PART A — schema: scenarios become location-scoped
-- =============================================================================
ALTER TABLE shared.Scenarios
    ADD COLUMN IF NOT EXISTS location_id INTEGER REFERENCES shared.Locations(location_id) ON DELETE CASCADE;
-- Drop the auto-named global UNIQUE(scenario_name) from 11-shared-schema
-- (post column-rename the constraint is scenarios_scenario_name_key).
ALTER TABLE shared.Scenarios DROP CONSTRAINT IF EXISTS scenarios_scenario_name_key;
ALTER TABLE shared.Scenarios DROP CONSTRAINT IF EXISTS scenarios_scenarioname_key;
DO $$ BEGIN
    ALTER TABLE shared.Scenarios ADD CONSTRAINT scenarios_location_name_key UNIQUE (location_id, scenario_name);
EXCEPTION WHEN duplicate_table THEN NULL; END $$;

COMMENT ON COLUMN shared.Scenarios.location_id IS
    'The site this management regime belongs to — top of the Location -> Scenario -> Variant hierarchy.';

-- =============================================================================
-- PART B — schema: variant lineage
-- =============================================================================
ALTER TABLE shared.Variants
    ADD COLUMN IF NOT EXISTS parent_variant_id INTEGER REFERENCES shared.Variants(variant_id) ON DELETE SET NULL;
COMMENT ON COLUMN shared.Variants.parent_variant_id IS
    'The variant this state developed from (baseline has none). Encodes the '
    'timeline/intervention lineage within a scenario.';

-- =============================================================================
-- PART C — one natural_growth scenario per location that has variants
-- =============================================================================
INSERT INTO shared.Scenarios (location_id, scenario_name, Description)
SELECT DISTINCT v.location_id, 'natural_growth',
       'Baseline field inventory developing under no active management (growth only). '
       'Owns the site''s baseline initial conditions; variants are successive growth states.'
FROM shared.Variants v
WHERE v.location_id IS NOT NULL
ON CONFLICT (location_id, scenario_name) DO NOTHING;

-- =============================================================================
-- PART D — re-point every variant to its location's natural_growth scenario
-- =============================================================================
UPDATE shared.Variants v
SET scenario_id = s.scenario_id
FROM shared.Scenarios s
WHERE s.location_id = v.location_id
  AND s.scenario_name = 'natural_growth';

-- Timeline order + lineage within each (now consolidated) scenario, by year
WITH ordered AS (
    SELECT variant_id,
           row_number() OVER (PARTITION BY scenario_id ORDER BY simulation_year, variant_id) - 1 AS so,
           lag(variant_id) OVER (PARTITION BY scenario_id ORDER BY simulation_year, variant_id)    AS parent
    FROM shared.Variants
)
UPDATE shared.Variants v
SET sort_order = o.so, parent_variant_id = o.parent
FROM ordered o
WHERE v.variant_id = o.variant_id;

-- =============================================================================
-- PART E — resync the redundant trees.scenario_id from each tree's variant
-- =============================================================================
UPDATE trees.Trees t
SET scenario_id = v.scenario_id
FROM shared.Variants v
WHERE t.variant_id = v.variant_id
  AND t.scenario_id IS DISTINCT FROM v.scenario_id;

-- =============================================================================
-- PART F — remove the old global scenarios (per-year splits + empty demos).
-- After Part D no variant references them; the remaining FKs are ON DELETE
-- SET NULL. Old scenarios are exactly those still carrying a NULL location_id.
-- =============================================================================
DELETE FROM shared.Scenarios WHERE location_id IS NULL;

-- All surviving scenarios are location-scoped: enforce it.
ALTER TABLE shared.Scenarios ALTER COLUMN location_id SET NOT NULL;

COMMENT ON TABLE shared.Scenarios IS
    'Management regimes, one set per location (Location -> Scenario -> Variant). '
    'Each scenario owns its baseline initial conditions; its variants are the '
    'successive states (growth cycles, interventions) developing from that baseline.';

-- =============================================================================
-- PART G — refresh public API views so the new columns surface over PostgREST.
-- (24-public-api-views.sql expands SELECT * at creation time, before these
--  columns existed, so the REST views must be rebuilt here.)
-- =============================================================================
DROP VIEW IF EXISTS public.scenarios;
CREATE VIEW public.scenarios AS SELECT * FROM shared.Scenarios;
COMMENT ON VIEW public.scenarios IS
    'Public API view: location-scoped management regimes (Location -> Scenario -> Variant).';
GRANT SELECT ON public.scenarios TO anon, authenticated;
GRANT ALL    ON public.scenarios TO service_role;

DROP VIEW IF EXISTS public.variants;
CREATE VIEW public.variants AS
SELECT
    v.*,
    l.location_name,
    s.scenario_name,
    vt.variant_type_name
FROM shared.Variants v
LEFT JOIN shared.Locations    l  ON v.location_id    = l.location_id
LEFT JOIN shared.Scenarios    s  ON v.scenario_id    = s.scenario_id
LEFT JOIN shared.VariantTypes vt ON v.variant_type_id = vt.variant_type_id;
COMMENT ON VIEW public.variants IS
    'Forest-state variants with location/scenario/type names and parent_variant_id '
    'lineage joined. Filter by location_id+scenario_id for a site+scenario timeline.';
GRANT SELECT ON public.variants TO anon, authenticated;
GRANT ALL    ON public.variants TO service_role;

COMMIT;
