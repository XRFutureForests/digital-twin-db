-- XR Future Forests Lab — Mathisle baseline scenario + variant
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually BEFORE the
-- baseline import, which names the variant it creates (--variant baseline_2025):
--
--   docker exec -i dftdb-db psql -U supabase_admin -d postgres < scripts/seed/mathisle_baseline_variant.sql
--
-- What this does
-- ==============
-- 1. Creates the location-scoped 'natural_growth' scenario.
-- 2. Creates its 'baseline_2025' variant (variant_type 'original').
-- The trees' scenario and variant type follow from the variant when
-- import_trees.py writes them (trees_variant_fkey, XRFF-661).
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

-- Location-scoped scenario (Location -> Scenario -> Variant) owning the baseline.
INSERT INTO shared.Scenarios (location_id, scenario_name, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'mathisle'),
    'natural_growth',
    'Baseline field inventory developing under no active management (growth only).'
ON CONFLICT (location_id, scenario_name) DO NOTHING;

INSERT INTO shared.Variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'mathisle'),
    (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth'),
    (SELECT variant_type_id FROM shared.variant_types WHERE variant_type_name = 'original'),
    'baseline_2025',
    2025, 0, 0,
    'Mathisle field measurements, March 2025'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle' AND v.variant_name = 'baseline_2025'
);
