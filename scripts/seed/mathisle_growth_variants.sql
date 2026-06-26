-- XR Future Forests Lab — Mathisle Growth Variants (synthetic)
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually:
--
--   docker exec -i dftdb-db psql -U postgres -d <POSTGRES_DB> -f - < scripts/seed/mathisle_growth_variants.sql
--
-- What this does
-- ==============
-- 1. Backfills ScenarioID = Current_Conditions on the real Mathisle
--    baseline import (import_trees.py does not set ScenarioID — see
--    scripts/import/import_trees.py — so without this, the baseline is
--    invisible to `forest_state?scenarioname=eq.Current_Conditions`).
-- 2. Creates two chained growth variants from that baseline:
--      Mathisle_Growth_2035  (parent: Current_Conditions, +10y)
--      Mathisle_Growth_2045  (parent: Mathisle_Growth_2035, +10y)
--    Each variant: scales Height_m/DBH_cm up by a flat percentage,
--    GENERATES crown dimensions synthetically (CrownWidth_m and
--    CrownBaseHeight_m are NULL in the Mathisle baseline — heights come
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
--   - the new ScenarioName (must be unique in shared.Scenarios)
--   - the new VariantName (must be unique within the Scenario in shared.Variants)
--   - the source scenario to grow from (the WHERE ScenarioName = '...' inside
--     the baseline CTE) — point it at any existing scenario, including one
--     you generated with this same script
--   - growth factors (1.08 = +8%, etc.) on Height_m and DBH_cm
--   - the crown generation formulae (grown_height * coefficient + random())
--     for CrownWidth_m and CrownBaseHeight_m
--   - the interval added to MeasurementDate / Age_years
--   - the mortality fraction (the `r >= 0.04` cutoff — raise/lower as needed)
--   - the regeneration fraction (the `r < 0.02` cutoff and the LIMIT)
-- Nothing else needs to change — TreeEntityID/ParentTreeID/lineage and the
-- Stems insert are handled generically from whatever baseline you select.

SET search_path TO shared, trees, extensions, public;

-- ============================================================
-- STEP 0: Backfill ScenarioID on the real Mathisle baseline import
-- ============================================================

UPDATE trees.Trees t
SET ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Current_Conditions')
FROM shared.Locations l
WHERE t.LocationID = l.LocationID
  AND l.LocationName = 'Mathisle'
  AND t.VariantTypeID = (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original')
  AND t.ScenarioID IS NULL;

-- Reproducible randomness for crown synthesis, mortality/regeneration sampling below
SELECT setseed(0.43);

-- ============================================================
-- SCENARIOS
-- ============================================================

INSERT INTO shared.Scenarios (ScenarioName, Description)
SELECT v.name, v.description
FROM (VALUES
    ('Mathisle_Growth_2035', '+10y synthetic growth projection from Mathisle Current_Conditions baseline. Crown dimensions synthesized; heights from allometric predictions. Placeholder percentages, not a calibrated growth model.'),
    ('Mathisle_Growth_2045', '+20y synthetic growth projection, chained from Mathisle_Growth_2035. Crown dimensions synthesized.')
) v(name, description)
WHERE NOT EXISTS (SELECT 1 FROM shared.Scenarios s WHERE s.ScenarioName = v.name);

-- ============================================================
-- VARIANTS (one per scenario time step)
-- ============================================================

INSERT INTO shared.Variants (ScenarioID, VariantName, SimulationYear, TimeDelta_yrs, SortOrder, Description)
SELECT
    (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2035'),
    'Mathisle_2035_Baseline',
    2035,
    10,
    0,
    'Synthetic +10y growth from Mathisle Current_Conditions baseline'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants
    WHERE VariantName = 'Mathisle_2035_Baseline'
);

INSERT INTO shared.Variants (ScenarioID, VariantName, SimulationYear, TimeDelta_yrs, SortOrder, Description)
SELECT
    (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2045'),
    'Mathisle_2045_Baseline',
    2045,
    20,
    0,
    'Synthetic +20y growth from Mathisle_Growth_2035'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants
    WHERE VariantName = 'Mathisle_2045_Baseline'
);

-- ============================================================
-- VARIANT 1: Mathisle_Growth_2035 (from Current_Conditions, +10 years)
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM trees.Trees t
        WHERE t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2035')
    ) THEN

        CREATE TEMP TABLE _m2035_base AS
        SELECT
            t.TreeID AS base_tree_id, t.TreeEntityID, t.LocationID, t.PlotID, t.CampaignID,
            t.SpeciesID, t.TreeStatusID, t.BranchingPatternID, t.BarkCharacteristicID,
            t.Height_m, t.Position, t.PositionOriginal, t.SourceCRS,
            t.Age_years, t.HealthScore, t.MeasurementDate,
            st.DBH_cm, st.TaperTypeID, st.StraightnessTypeID,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Locations l ON t.LocationID = l.LocationID
        LEFT JOIN trees.Stems st ON st.TreeID = t.TreeID AND st.StemNumber = 1
        WHERE l.LocationName = 'Mathisle'
          AND t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Current_Conditions')
          AND t.VariantTypeID = (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original');

        -- ~4% mortality (steeper than Ecosense — drier climate signal): these trees are simply absent from the new variant
        CREATE TEMP TABLE _m2035_survivors AS
        SELECT * FROM _m2035_base WHERE r >= 0.04;

        -- Grow survivors forward 10 years; insert new tree rows + scaled stems
        -- Crown dimensions are synthesized from grown height: closed-canopy Black Forest spruce/fir ratios
        WITH ins AS (
            INSERT INTO trees.Trees (
                TreeEntityID, ParentTreeID,
                VariantID,
                LocationID, PlotID, CampaignID, ScenarioID, VariantTypeID,
                SpeciesID, TreeStatusID, BranchingPatternID, BarkCharacteristicID,
                MeasurementDate, DataSourceTypeID, Height_m, CrownWidth_m, CrownBaseHeight_m,
                Position, PositionOriginal, SourceCRS, TimeDelta_yrs, Age_years, HealthScore, CreatedBy
            )
            SELECT
                b.TreeEntityID, b.base_tree_id,
                (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Mathisle_2035_Baseline'),
                b.LocationID, b.PlotID, b.CampaignID,
                (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2035'),
                (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
                b.SpeciesID, b.TreeStatusID, b.BranchingPatternID, b.BarkCharacteristicID,
                b.MeasurementDate + INTERVAL '10 years', (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
                ROUND((b.Height_m * 1.08)::numeric, 2),
                -- CrownWidth_m synthesized: 28–38% of grown height (closed-canopy Black Forest)
                ROUND(((b.Height_m * 1.08) * (0.28 + random() * 0.10))::numeric, 2),
                -- CrownBaseHeight_m synthesized: 40–50% of grown height (heavily suppressed lower crown)
                ROUND(((b.Height_m * 1.08) * (0.40 + random() * 0.10))::numeric, 2),
                b.Position, b.PositionOriginal, b.SourceCRS,
                10, b.Age_years + 10, b.HealthScore, 'growth_variant_seed'
            FROM _m2035_survivors b
            RETURNING TreeID, TreeEntityID
        )
        INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm, TaperTypeID, StraightnessTypeID)
        SELECT ins.TreeID, 1, ROUND((s.DBH_cm * 1.10)::numeric, 2), s.TaperTypeID, s.StraightnessTypeID
        FROM ins
        JOIN _m2035_survivors s ON s.TreeEntityID = ins.TreeEntityID
        WHERE s.DBH_cm IS NOT NULL;

        -- ~2% regeneration: brand-new saplings, no ParentTreeID, jittered near an existing tree
        INSERT INTO trees.Trees (
            TreeEntityID,
            VariantID,
            LocationID, PlotID, CampaignID, ScenarioID, VariantTypeID,
            SpeciesID, MeasurementDate, DataSourceTypeID, Height_m, CrownWidth_m, CrownBaseHeight_m,
            Position, Age_years, HealthScore, CreatedBy
        )
        SELECT
            gen_random_uuid(),
            (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Mathisle_2035_Baseline'),
            b.LocationID, b.PlotID, b.CampaignID,
            (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2035'),
            (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
            b.SpeciesID, b.MeasurementDate + INTERVAL '10 years', (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
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
        WHERE t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2045')
    ) THEN

        CREATE TEMP TABLE _m2045_base AS
        SELECT
            t.TreeID AS base_tree_id, t.TreeEntityID, t.LocationID, t.PlotID, t.CampaignID,
            t.SpeciesID, t.TreeStatusID, t.BranchingPatternID, t.BarkCharacteristicID,
            t.Height_m, t.CrownWidth_m, t.CrownBaseHeight_m, t.Position, t.PositionOriginal, t.SourceCRS,
            t.Age_years, t.HealthScore, t.MeasurementDate,
            st.DBH_cm, st.TaperTypeID, st.StraightnessTypeID,
            random() AS r
        FROM trees.Trees t
        LEFT JOIN trees.Stems st ON st.TreeID = t.TreeID AND st.StemNumber = 1
        WHERE t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2035');

        -- ~6% mortality over the second decade
        CREATE TEMP TABLE _m2045_survivors AS
        SELECT * FROM _m2045_base WHERE r >= 0.06;

        -- Grow survivors forward 10 more years
        -- Crown dimensions re-synthesized from already-grown heights (same formula applied to 2035 heights)
        WITH ins AS (
            INSERT INTO trees.Trees (
                TreeEntityID, ParentTreeID,
                VariantID,
                LocationID, PlotID, CampaignID, ScenarioID, VariantTypeID,
                SpeciesID, TreeStatusID, BranchingPatternID, BarkCharacteristicID,
                MeasurementDate, DataSourceTypeID, Height_m, CrownWidth_m, CrownBaseHeight_m,
                Position, PositionOriginal, SourceCRS, TimeDelta_yrs, Age_years, HealthScore, CreatedBy
            )
            SELECT
                b.TreeEntityID, b.base_tree_id,
                (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Mathisle_2045_Baseline'),
                b.LocationID, b.PlotID, b.CampaignID,
                (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2045'),
                (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
                b.SpeciesID, b.TreeStatusID, b.BranchingPatternID, b.BarkCharacteristicID,
                b.MeasurementDate + INTERVAL '10 years', (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
                ROUND((b.Height_m * 1.07)::numeric, 2),
                -- CrownWidth_m synthesized: 28–38% of grown height (same formula, applied to 2035 heights)
                ROUND(((b.Height_m * 1.07) * (0.28 + random() * 0.10))::numeric, 2),
                -- CrownBaseHeight_m synthesized: 40–50% of grown height
                ROUND(((b.Height_m * 1.07) * (0.40 + random() * 0.10))::numeric, 2),
                b.Position, b.PositionOriginal, b.SourceCRS,
                10, b.Age_years + 10, b.HealthScore, 'growth_variant_seed'
            FROM _m2045_survivors b
            RETURNING TreeID, TreeEntityID
        )
        INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm, TaperTypeID, StraightnessTypeID)
        SELECT ins.TreeID, 1, ROUND((s.DBH_cm * 1.08)::numeric, 2), s.TaperTypeID, s.StraightnessTypeID
        FROM ins
        JOIN _m2045_survivors s ON s.TreeEntityID = ins.TreeEntityID
        WHERE s.DBH_cm IS NOT NULL;

        -- ~2% further regeneration
        INSERT INTO trees.Trees (
            TreeEntityID,
            VariantID,
            LocationID, PlotID, CampaignID, ScenarioID, VariantTypeID,
            SpeciesID, MeasurementDate, DataSourceTypeID, Height_m, CrownWidth_m, CrownBaseHeight_m,
            Position, Age_years, HealthScore, CreatedBy
        )
        SELECT
            gen_random_uuid(),
            (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Mathisle_2045_Baseline'),
            b.LocationID, b.PlotID, b.CampaignID,
            (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2045'),
            (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
            b.SpeciesID, b.MeasurementDate + INTERVAL '10 years', (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
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

DO $$
DECLARE
    v_2035 INTEGER;
    v_2045 INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_2035 FROM trees.Trees
    WHERE ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2035');
    SELECT COUNT(*) INTO v_2045 FROM trees.Trees
    WHERE ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Mathisle_Growth_2045');

    RAISE NOTICE 'Mathisle_Growth_2035: % tree rows', v_2035;
    RAISE NOTICE 'Mathisle_Growth_2045: % tree rows', v_2045;
END $$;
