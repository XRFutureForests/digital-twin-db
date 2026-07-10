-- XR Future Forests Lab — Mathisle Growth Variants (synthetic)
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually:
--
--   docker exec -i dftdb-db psql -U postgres -d <POSTGRES_DB> -f - < scripts/seed/mathisle_growth_variants.sql
--
-- What this does
-- ==============
-- 1. Backfills scenario_id = Current_Conditions on the real Mathisle
--    baseline import (import_trees.py does not set scenario_id — see
--    scripts/import/import_trees.py — so without this, the baseline is
--    invisible to `ue_trees?scenario_name=eq.Current_Conditions`).
-- 2. Creates two chained growth variants from that baseline:
--      Mathisle_Growth_2035  (parent: Current_Conditions, +10y)
--      Mathisle_Growth_2045  (parent: Mathisle_Growth_2035, +10y)
--    Each variant: scales Height_m/DBH_cm up by a flat percentage,
--    GENERATES crown dimensions synthetically (crown_width_m and
--    crown_base_height_m are NULL in the Mathisle baseline — heights come
--    from allometric predictions produced by fill_missing_heights.py, not
--    field measurements; crown dimensions are not field-measured and must
--    therefore be synthesized here), drops a random subset of trees
--    (mortality — "missing" in that variant), and adds a handful of new
--    sapling trees (regeneration).
--
-- Growth rates reflect Black Forest montane forest conditions (slower
-- than Ecosense): closed-canopy Norway spruce / Silver fir stands with
-- a drier climate signal from the 2030s onward.
--
-- IMPORTANT: the growth/mortality/regeneration numbers below are simple
-- placeholders for exercising the schema and UE variant-switching end to
-- end — they are NOT a calibrated growth model (that is what the SILVA
-- coupling in docs/growth-simulation-schema.md is for). Treat this as
-- synthetic test data.
--
-- Idempotent: each variant block is guarded by a NOT EXISTS check on the
-- scenario already having tree rows, so re-running this file is a no-op
-- once applied.
--
-- HOW TO ADD YOUR OWN VARIANT
-- ===========================
-- Copy one of the two `DO $$ ... $$` blocks below and adjust:
--   - the new scenario_name (must be unique in shared.Scenarios)
--   - the new variant_name (must be unique within the Scenario in shared.Variants)
--   - the source scenario to grow from (the WHERE scenario_name = '...' inside
--     the baseline CTE) — point it at any existing scenario, including one
--     you generated with this same script
--   - growth factors (1.08 = +8%, etc.) on Height_m and DBH_cm
--   - the crown generation formulae (grown_height * coefficient + random())
--     for crown_width_m and crown_base_height_m
--   - the interval added to measurement_date / Age_years
--   - the mortality fraction (the `r >= 0.04` cutoff — raise/lower as needed)
--   - the regeneration fraction (the `r < 0.02` cutoff and the LIMIT)
-- Nothing else needs to change — tree_entity_id/parent_tree_id/lineage and the
-- Stems insert are handled generically from whatever baseline you select.

SET search_path TO shared, trees, extensions, public;

-- ============================================================
-- STEP 0: Create natural_growth scenario + baseline variant, assign trees
-- ============================================================

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
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'original'),
    'baseline_2025',
    2025, 0, 0,
    'Mathisle field measurements, March 2025'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle' AND v.variant_name = 'baseline_2025'
);

UPDATE trees.Trees t
SET
    variant_id  = (
        SELECT v.variant_id FROM shared.Variants v
        JOIN shared.Locations l ON v.location_id = l.location_id
        WHERE l.location_name = 'mathisle' AND v.variant_name = 'baseline_2025'
    ),
    scenario_id = (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth')
FROM shared.Locations l
WHERE t.location_id = l.location_id
  AND l.location_name = 'mathisle'
  AND t.variant_id IS NULL;

-- Reproducible randomness for crown synthesis, mortality/regeneration sampling below
SELECT setseed(0.43);

-- ============================================================
-- SCENARIOS
-- ============================================================

-- (Growth states are variants of the single natural_growth scenario, not
--  separate scenarios — see STEP 0.)

-- ============================================================
-- VARIANTS (one per scenario time step)
-- ============================================================

INSERT INTO shared.Variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'mathisle'),
    (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
    'growth_2035',
    2035, 10, 0,
    'Synthetic +10y growth from Mathisle Current_Conditions baseline'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2035'
);

INSERT INTO shared.Variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'mathisle'),
    (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
    'growth_2045',
    2045, 20, 0,
    'Synthetic +20y growth from Mathisle_Growth_2035'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2045'
);

-- ============================================================
-- VARIANT 1: Mathisle_Growth_2035 (from Current_Conditions, +10 years)
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM trees.Trees t
        JOIN shared.Variants v ON t.variant_id = v.variant_id
        JOIN shared.Locations l ON v.location_id = l.location_id
        WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2035'
    ) THEN

        CREATE TEMP TABLE _m2035_base AS
        SELECT
            t.tree_id AS base_tree_id, t.tree_entity_id, t.location_id, t.plot_id, t.campaign_id,
            t.species_id, t.tree_status_id, t.branching_pattern_id, t.bark_characteristic_id,
            t.Height_m, t.Position, t.position_original, t.source_crs,
            t.Age_years, t.health_score, t.measurement_date,
            st.DBH_cm, st.taper_type_id, st.straightness_type_id,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Variants bv ON t.variant_id = bv.variant_id
        JOIN shared.Locations l ON bv.location_id = l.location_id
        LEFT JOIN trees.Stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
        WHERE l.location_name = 'mathisle'
          AND bv.variant_name = 'baseline_2025';

        -- ~4% mortality (steeper than Ecosense — drier climate signal): these trees are simply absent from the new variant
        CREATE TEMP TABLE _m2035_survivors AS
        SELECT * FROM _m2035_base WHERE r >= 0.04;

        -- Grow survivors forward 10 years; insert new tree rows + scaled stems
        -- Crown dimensions are synthesized from grown height: closed-canopy Black Forest spruce/fir ratios
        WITH ins AS (
            INSERT INTO trees.Trees (
                tree_entity_id, parent_tree_id,
                variant_id,
                location_id, plot_id, campaign_id, scenario_id, variant_type_id,
                species_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
                measurement_date, data_source_type_id, Height_m, crown_width_m, crown_base_height_m,
                Position, position_original, source_crs, time_delta_yrs, Age_years, health_score, created_by
            )
            SELECT
                b.tree_entity_id, b.base_tree_id,
                (SELECT v.variant_id FROM shared.Variants v JOIN shared.Locations l ON v.location_id = l.location_id WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2035'),
                b.location_id, b.plot_id, b.campaign_id,
                (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth'),
                (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
                b.species_id, b.tree_status_id, b.branching_pattern_id, b.bark_characteristic_id,
                b.measurement_date + INTERVAL '10 years', (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
                ROUND((b.Height_m * 1.08)::numeric, 2),
                -- crown_width_m synthesized: 28–38% of grown height (closed-canopy Black Forest)
                ROUND(((b.Height_m * 1.08) * (0.28 + random() * 0.10))::numeric, 2),
                -- crown_base_height_m synthesized: 40–50% of grown height (heavily suppressed lower crown)
                ROUND(((b.Height_m * 1.08) * (0.40 + random() * 0.10))::numeric, 2),
                b.Position, b.position_original, b.source_crs,
                10, b.Age_years + 10, b.health_score, 'growth_variant_seed'
            FROM _m2035_survivors b
            RETURNING tree_id, tree_entity_id
        )
        INSERT INTO trees.Stems (tree_id, stem_number, DBH_cm, taper_type_id, straightness_type_id)
        SELECT ins.tree_id, 1, ROUND((s.DBH_cm * 1.10)::numeric, 2), s.taper_type_id, s.straightness_type_id
        FROM ins
        JOIN _m2035_survivors s ON s.tree_entity_id = ins.tree_entity_id
        WHERE s.DBH_cm IS NOT NULL;

        -- ~2% regeneration: brand-new saplings, no parent_tree_id, jittered near an existing tree
        INSERT INTO trees.Trees (
            tree_entity_id,
            variant_id,
            location_id, plot_id, campaign_id, scenario_id, variant_type_id,
            species_id, measurement_date, data_source_type_id, Height_m, crown_width_m, crown_base_height_m,
            Position, Age_years, health_score, created_by
        )
        SELECT
            gen_random_uuid(),
            (SELECT variant_id FROM shared.Variants WHERE variant_name = 'Mathisle_2035_Baseline'),
            b.location_id, b.plot_id, b.campaign_id,
            (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth'),
            (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
            b.species_id, b.measurement_date + INTERVAL '10 years', (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
            ROUND((2 + random() * 2)::numeric, 2),
            ROUND((0.5 + random())::numeric, 2),
            ROUND((0.3 + random() * 0.4)::numeric, 2),
            ST_SetSRID(ST_MakePoint(
                ST_X(b.Position) + (random() - 0.5) * 0.0006,
                ST_Y(b.Position) + (random() - 0.5) * 0.0006
            ), 4326),
            0, 0.95, 'growth_variant_seed'
        FROM _m2035_base b
        WHERE b.r < 0.02
        LIMIT 15;

        DROP TABLE _m2035_base;
        DROP TABLE _m2035_survivors;
    END IF;
END $$;

-- ============================================================
-- VARIANT 2: Mathisle_Growth_2045 (from Mathisle_Growth_2035, +10 more years)
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM trees.Trees t
        JOIN shared.Variants v ON t.variant_id = v.variant_id
        JOIN shared.Locations l ON v.location_id = l.location_id
        WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2045'
    ) THEN

        CREATE TEMP TABLE _m2045_base AS
        SELECT
            t.tree_id AS base_tree_id, t.tree_entity_id, t.location_id, t.plot_id, t.campaign_id,
            t.species_id, t.tree_status_id, t.branching_pattern_id, t.bark_characteristic_id,
            t.Height_m, t.crown_width_m, t.crown_base_height_m, t.Position, t.position_original, t.source_crs,
            t.Age_years, t.health_score, t.measurement_date,
            st.DBH_cm, st.taper_type_id, st.straightness_type_id,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Variants bv ON t.variant_id = bv.variant_id
        JOIN shared.Locations bl ON bv.location_id = bl.location_id
        LEFT JOIN trees.Stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
        WHERE bl.location_name = 'mathisle' AND bv.variant_name = 'growth_2035';

        -- ~6% mortality over the second decade
        CREATE TEMP TABLE _m2045_survivors AS
        SELECT * FROM _m2045_base WHERE r >= 0.06;

        -- Grow survivors forward 10 more years
        -- Crown dimensions re-synthesized from already-grown heights (same formula applied to 2035 heights)
        WITH ins AS (
            INSERT INTO trees.Trees (
                tree_entity_id, parent_tree_id,
                variant_id,
                location_id, plot_id, campaign_id, scenario_id, variant_type_id,
                species_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
                measurement_date, data_source_type_id, Height_m, crown_width_m, crown_base_height_m,
                Position, position_original, source_crs, time_delta_yrs, Age_years, health_score, created_by
            )
            SELECT
                b.tree_entity_id, b.base_tree_id,
                (SELECT v.variant_id FROM shared.Variants v JOIN shared.Locations l ON v.location_id = l.location_id WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2045'),
                b.location_id, b.plot_id, b.campaign_id,
                (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth'),
                (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
                b.species_id, b.tree_status_id, b.branching_pattern_id, b.bark_characteristic_id,
                b.measurement_date + INTERVAL '10 years', (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
                ROUND((b.Height_m * 1.07)::numeric, 2),
                -- crown_width_m synthesized: 28–38% of grown height (same formula, applied to 2035 heights)
                ROUND(((b.Height_m * 1.07) * (0.28 + random() * 0.10))::numeric, 2),
                -- crown_base_height_m synthesized: 40–50% of grown height
                ROUND(((b.Height_m * 1.07) * (0.40 + random() * 0.10))::numeric, 2),
                b.Position, b.position_original, b.source_crs,
                10, b.Age_years + 10, b.health_score, 'growth_variant_seed'
            FROM _m2045_survivors b
            RETURNING tree_id, tree_entity_id
        )
        INSERT INTO trees.Stems (tree_id, stem_number, DBH_cm, taper_type_id, straightness_type_id)
        SELECT ins.tree_id, 1, ROUND((s.DBH_cm * 1.08)::numeric, 2), s.taper_type_id, s.straightness_type_id
        FROM ins
        JOIN _m2045_survivors s ON s.tree_entity_id = ins.tree_entity_id
        WHERE s.DBH_cm IS NOT NULL;

        -- ~2% further regeneration
        INSERT INTO trees.Trees (
            tree_entity_id,
            variant_id,
            location_id, plot_id, campaign_id, scenario_id, variant_type_id,
            species_id, measurement_date, data_source_type_id, Height_m, crown_width_m, crown_base_height_m,
            Position, Age_years, health_score, created_by
        )
        SELECT
            gen_random_uuid(),
            (SELECT variant_id FROM shared.Variants WHERE variant_name = 'Mathisle_2045_Baseline'),
            b.location_id, b.plot_id, b.campaign_id,
            (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'mathisle' AND s.scenario_name = 'natural_growth'),
            (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
            b.species_id, b.measurement_date + INTERVAL '10 years', (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
            ROUND((2 + random() * 2)::numeric, 2),
            ROUND((0.5 + random())::numeric, 2),
            ROUND((0.3 + random() * 0.4)::numeric, 2),
            ST_SetSRID(ST_MakePoint(
                ST_X(b.Position) + (random() - 0.5) * 0.0006,
                ST_Y(b.Position) + (random() - 0.5) * 0.0006
            ), 4326),
            0, 0.95, 'growth_variant_seed'
        FROM _m2045_base b
        WHERE b.r < 0.02
        LIMIT 15;

        DROP TABLE _m2045_base;
        DROP TABLE _m2045_survivors;
    END IF;
END $$;

-- ============================================================
-- SUMMARY
-- ============================================================

-- Timeline order + lineage within natural_growth; resync trees.scenario_id
WITH ordered AS (
    SELECT v.variant_id,
           row_number() OVER (PARTITION BY v.scenario_id ORDER BY v.simulation_year, v.variant_id) - 1 AS so,
           lag(v.variant_id) OVER (PARTITION BY v.scenario_id ORDER BY v.simulation_year, v.variant_id) AS parent
    FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle'
)
UPDATE shared.Variants v
SET sort_order = o.so, parent_variant_id = o.parent
FROM ordered o WHERE v.variant_id = o.variant_id;

UPDATE trees.Trees t
SET scenario_id = v.scenario_id
FROM shared.Variants v
WHERE t.variant_id = v.variant_id
  AND t.scenario_id IS DISTINCT FROM v.scenario_id
  AND t.location_id = (SELECT location_id FROM shared.Locations WHERE location_name = 'mathisle');

DO $$
DECLARE
    v_baseline INTEGER;
    v_2035     INTEGER;
    v_2045     INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_baseline FROM trees.Trees t
    JOIN shared.Variants v ON t.variant_id = v.variant_id
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle' AND v.variant_name = 'baseline_2025';

    SELECT COUNT(*) INTO v_2035 FROM trees.Trees t
    JOIN shared.Variants v ON t.variant_id = v.variant_id
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2035';

    SELECT COUNT(*) INTO v_2045 FROM trees.Trees t
    JOIN shared.Variants v ON t.variant_id = v.variant_id
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'mathisle' AND v.variant_name = 'growth_2045';

    RAISE NOTICE 'Mathisle Baseline_2025 : % trees', v_baseline;
    RAISE NOTICE 'Mathisle Growth_2035   : % trees', v_2035;
    RAISE NOTICE 'Mathisle Growth_2045   : % trees', v_2045;
END $$;
