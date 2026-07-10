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
--   * shared.Scenarios gains LocationID (scenarios are now per-site); the global
--     UNIQUE(ScenarioName) becomes UNIQUE(LocationID, ScenarioName).
--   * shared.Variants gains ParentVariantID (explicit lineage, mirrors
--     trees.ParentTreeID); SortOrder is set to the timeline order.
--   * The existing per-year scenarios are consolidated into ONE 'natural_growth'
--     scenario per location, carrying baseline_2025 -> growth_2035 -> growth_2045.
--   * trees.ScenarioID (redundant, was inconsistently populated) is resynced from
--     each tree's variant. The 7 empty demo scenarios are removed.
--
-- Idempotent: guarded DDL; re-pointing/cleanup are keyed on the pre-migration
-- shape (scenarios with NULL LocationID), so a second run is a no-op.
--
-- Dependencies: 11-shared-schema.sql, 36-restructure-locations-plots-snakecase.sql

BEGIN;

-- =============================================================================
-- PART A — schema: scenarios become location-scoped
-- =============================================================================
ALTER TABLE shared.Scenarios
    ADD COLUMN IF NOT EXISTS LocationID INTEGER REFERENCES shared.Locations(LocationID) ON DELETE CASCADE;
ALTER TABLE shared.Scenarios DROP CONSTRAINT IF EXISTS scenarios_scenarioname_key;
DO $$ BEGIN
    ALTER TABLE shared.Scenarios ADD CONSTRAINT scenarios_location_name_key UNIQUE (LocationID, ScenarioName);
EXCEPTION WHEN duplicate_table THEN NULL; END $$;

COMMENT ON COLUMN shared.Scenarios.LocationID IS
    'The site this management regime belongs to — top of the Location -> Scenario -> Variant hierarchy.';

-- =============================================================================
-- PART B — schema: variant lineage
-- =============================================================================
ALTER TABLE shared.Variants
    ADD COLUMN IF NOT EXISTS ParentVariantID INTEGER REFERENCES shared.Variants(VariantID) ON DELETE SET NULL;
COMMENT ON COLUMN shared.Variants.ParentVariantID IS
    'The variant this state developed from (baseline has none). Encodes the '
    'timeline/intervention lineage within a scenario.';

-- =============================================================================
-- PART C — one natural_growth scenario per location that has variants
-- =============================================================================
INSERT INTO shared.Scenarios (LocationID, ScenarioName, Description)
SELECT DISTINCT v.LocationID, 'natural_growth',
       'Baseline field inventory developing under no active management (growth only). '
       'Owns the site''s baseline initial conditions; variants are successive growth states.'
FROM shared.Variants v
WHERE v.LocationID IS NOT NULL
ON CONFLICT (LocationID, ScenarioName) DO NOTHING;

-- =============================================================================
-- PART D — re-point every variant to its location's natural_growth scenario
-- =============================================================================
UPDATE shared.Variants v
SET ScenarioID = s.ScenarioID
FROM shared.Scenarios s
WHERE s.LocationID = v.LocationID
  AND s.ScenarioName = 'natural_growth';

-- Timeline order + lineage within each (now consolidated) scenario, by year
WITH ordered AS (
    SELECT VariantID,
           row_number() OVER (PARTITION BY ScenarioID ORDER BY SimulationYear, VariantID) - 1 AS so,
           lag(VariantID) OVER (PARTITION BY ScenarioID ORDER BY SimulationYear, VariantID)    AS parent
    FROM shared.Variants
)
UPDATE shared.Variants v
SET SortOrder = o.so, ParentVariantID = o.parent
FROM ordered o
WHERE v.VariantID = o.VariantID;

-- =============================================================================
-- PART E — resync the redundant trees.ScenarioID from each tree's variant
-- =============================================================================
UPDATE trees.Trees t
SET ScenarioID = v.ScenarioID
FROM shared.Variants v
WHERE t.VariantID = v.VariantID
  AND t.ScenarioID IS DISTINCT FROM v.ScenarioID;

-- =============================================================================
-- PART F — remove the old global scenarios (per-year splits + empty demos).
-- After Part D no variant references them; the remaining FKs are ON DELETE
-- SET NULL. Old scenarios are exactly those still carrying a NULL LocationID.
-- =============================================================================
DELETE FROM shared.Scenarios WHERE LocationID IS NULL;

-- All surviving scenarios are location-scoped: enforce it.
ALTER TABLE shared.Scenarios ALTER COLUMN LocationID SET NOT NULL;

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
    l.locationname,
    s.scenarioname,
    vt.varianttypename
FROM shared.Variants v
LEFT JOIN shared.Locations    l  ON v.locationid    = l.locationid
LEFT JOIN shared.Scenarios    s  ON v.scenarioid    = s.scenarioid
LEFT JOIN shared.VariantTypes vt ON v.varianttypeid = vt.varianttypeid;
COMMENT ON VIEW public.variants IS
    'Forest-state variants with location/scenario/type names and ParentVariantID '
    'lineage joined. Filter by locationid+scenarioid for a site+scenario timeline.';
GRANT SELECT ON public.variants TO anon, authenticated;
GRANT ALL    ON public.variants TO service_role;

COMMIT;
