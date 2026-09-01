-- XR Future Forests Lab — Ecosense baseline scenario + variant
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually after the
-- baseline import:
--
--   docker exec -i dftdb-db psql -U supabase_admin -d postgres < scripts/seed/ecosense_baseline_variant.sql
--
-- What this does
-- ==============
-- 1. Creates the location-scoped 'natural_growth' scenario.
-- 2. Creates its 'baseline_2025' variant (variant_type 'original').
-- 3. Assigns the imported ecosense baseline trees to it, and backfills their
--    scenario_id. import_trees.py writes neither (it always sets
--    scenario_id = NULL, see its comment at the scenario_id assignment), so
--    without this the baseline trees have no variant and are invisible to
--    ?variant_id= queries from UE.
--
-- History
-- =======
-- This file used to also create synthetic 'growth_2035' / 'growth_2045'
-- variants by scaling dimensions up a flat percentage. Those were placeholders
-- for exercising the schema and UE variant-switching before a real growth model
-- existed. They were retired on 2026-08-31, superseded by silva-connector,
-- which runs SILVA against this baseline and writes calibrated
-- simulated_growth variants (silva_2030, silva_2035, ...). See
-- silva-connector/README.md.
--
-- Idempotent: each block is guarded so re-running is a no-op.

SET search_path TO shared, trees, extensions, public;

-- Scenarios are location-scoped (Location -> Scenario -> Variant). The ecosense
-- growth trajectory is ONE scenario ('natural_growth') that owns the baseline;
-- baseline_2025 and the simulator's variants are its successive states.
INSERT INTO shared.Scenarios (location_id, scenario_name, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'ecosense'),
    'natural_growth',
    'Baseline field inventory developing under no active management (growth only).'
ON CONFLICT (location_id, scenario_name) DO NOTHING;

-- Create the baseline variant (original field measurements, year 2025)
INSERT INTO shared.Variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'ecosense'),
    (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'original'),
    'baseline_2025',
    2025,
    0,
    0,
    'ecosense field measurements, September 2025'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'baseline_2025'
);

-- Assign all Ecosense baseline trees to this variant, and resync scenario_id
-- from it so the Location -> Scenario -> Variant chain is complete.
UPDATE trees.Trees t
SET
    variant_id  = (
        SELECT v.variant_id FROM shared.Variants v
        JOIN shared.Locations l ON v.location_id = l.location_id
        WHERE l.location_name = 'ecosense' AND v.variant_name = 'baseline_2025'
    ),
    scenario_id = (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth')
FROM shared.Locations l
WHERE t.location_id = l.location_id
  AND l.location_name = 'ecosense'
  AND t.variant_type_id = (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'original')
  AND (t.variant_id IS NULL OR t.scenario_id IS NULL);
