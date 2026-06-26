-- XR Future Forests Lab — Ecosense Growth Variants (synthetic)
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually:
--
--   docker exec -i dftdb-db psql -U postgres -d <POSTGRES_DB> -f - < scripts/seed/ecosense_growth_variants.sql
--
-- What this does
-- ==============
-- 1. Backfills ScenarioID = Current_Conditions on the real Ecosense_MixedPlot
--    baseline import (import_trees.py does not set ScenarioID — see
--    scripts/import/import_trees.py — so without this, the baseline is
--    invisible to `forest_state?scenarioname=eq.Current_Conditions`).
-- 2. Creates two chained growth variants from that baseline:
--      Ecosense_Growth_2035  (parent: Current_Conditions, +10y)
--      Ecosense_Growth_2045  (parent: Ecosense_Growth_2035, +10y)
--    Each variant: scales Height_m/CrownWidth_m/CrownBaseHeight_m/DBH_cm up by
--    a flat percentage, drops a random subset of trees (mortality — "missing"
--    in that variant), and adds a handful of new sapling trees (regeneration).
--
-- IMPORTANT: the growth/mortality/regeneration numbers below are simple
-- placeholders for exercising the schema and UE variant-switching end to end —
-- they are NOT a calibrated growth model (that is what the SILVA coupling in
-- docs/growth-simulation-schema.md is for). Treat this as synthetic test data.
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
--   - growth factors (1.12 = +12%, etc.) on Height_m/CrownWidth_m/
--     CrownBaseHeight_m/DBH_cm
--   - the interval added to MeasurementDate / Age_years
--   - the mortality fraction (the `r >= 0.03` cutoff — raise/lower 0.03)
--   - the regeneration fraction (the `r < 0.02` cutoff and the LIMIT)
-- Nothing else needs to change — TreeEntityID/ParentTreeID/lineage and the
-- Stems insert are handled generically from whatever baseline you select.

SET search_path TO shared, trees, extensions, public;

-- ============================================================
-- STEP 0: Backfill ScenarioID on the real Ecosense baseline import
-- ============================================================

UPDATE trees.Trees t
SET ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Current_Conditions')
FROM shared.Locations l
WHERE t.LocationID = l.LocationID
  AND l.LocationName = 'Ecosense_MixedPlot'
  AND t.VariantTypeID = (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original')
  AND t.ScenarioID IS NULL;

-- Reproducible randomness for mortality/regeneration sampling below
SELECT setseed(0.42);

-- ============================================================
-- SCENARIOS
-- ============================================================

INSERT INTO shared.Scenarios (ScenarioName, Description)
SELECT v.name, v.description
FROM (VALUES
    ('Ecosense_Growth_2035', '+10y synthetic growth projection from Ecosense_MixedPlot Current_Conditions baseline. Placeholder percentages, not a calibrated growth model.'),
    ('Ecosense_Growth_2045', '+20y synthetic growth projection, chained from Ecosense_Growth_2035.')
) v(name, description)
WHERE NOT EXISTS (SELECT 1 FROM shared.Scenarios s WHERE s.ScenarioName = v.name);

-- ============================================================
-- VARIANTS (one per scenario time step — all trees sharing the same
-- VariantID represent the complete forest at that point in time)
-- ============================================================

INSERT INTO shared.Variants (ScenarioID, VariantName, SimulationYear, TimeDelta_yrs, SortOrder, Description)
SELECT
    (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2035'),
    'Ecosense_2035_Baseline',
    2035,
    10,
    0,
    'Synthetic +10y growth from Current_Conditions baseline'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants
    WHERE VariantName = 'Ecosense_2035_Baseline'
);

INSERT INTO shared.Variants (ScenarioID, VariantName, SimulationYear, TimeDelta_yrs, SortOrder, Description)
SELECT
    (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2045'),
    'Ecosense_2045_Baseline',
    2045,
    20,
    0,
    'Synthetic +20y growth from Ecosense_Growth_2035'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants
    WHERE VariantName = 'Ecosense_2045_Baseline'
);

-- ============================================================
-- VARIANT 1: Ecosense_Growth_2035 (from Current_Conditions, +10 years)
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM trees.Trees t
        WHERE t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2035')
    ) THEN

        CREATE TEMP TABLE _g2035_base AS
        SELECT
            t.TreeID AS base_tree_id, t.TreeEntityID, t.LocationID, t.PlotID, t.CampaignID,
            t.SpeciesID, t.TreeStatusID, t.BranchingPatternID, t.BarkCharacteristicID,
            t.Height_m, t.CrownWidth_m, t.CrownBaseHeight_m, t.Position, t.PositionOriginal, t.SourceCRS,
            t.Age_years, t.HealthScore, t.MeasurementDate,
            st.DBH_cm, st.TaperTypeID, st.StraightnessTypeID,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Locations l ON t.LocationID = l.LocationID
        LEFT JOIN trees.Stems st ON st.TreeID = t.TreeID AND st.StemNumber = 1
        WHERE l.LocationName = 'Ecosense_MixedPlot'
          AND t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Current_Conditions')
          AND t.VariantTypeID = (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original');

        -- ~3% mortality: these trees are simply absent from the new variant
        CREATE TEMP TABLE _g2035_survivors AS
        SELECT * FROM _g2035_base WHERE r >= 0.03;

        -- Grow survivors forward 10 years; insert new tree rows + scaled stems
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
                (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Ecosense_2035_Baseline'),
                b.LocationID, b.PlotID, b.CampaignID,
                (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2035'),
                (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
                b.SpeciesID, b.TreeStatusID, b.BranchingPatternID, b.BarkCharacteristicID,
                b.MeasurementDate + INTERVAL '10 years', (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
                ROUND(b.Height_m * 1.12, 2),
                ROUND(b.CrownWidth_m * 1.08, 2),
                ROUND(b.CrownBaseHeight_m * 1.05, 2),
                b.Position, b.PositionOriginal, b.SourceCRS,
                10, b.Age_years + 10, b.HealthScore, 'growth_variant_seed'
            FROM _g2035_survivors b
            RETURNING TreeID, TreeEntityID
        )
        INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm, TaperTypeID, StraightnessTypeID)
        SELECT ins.TreeID, 1, ROUND(s.DBH_cm * 1.15, 2), s.TaperTypeID, s.StraightnessTypeID
        FROM ins
        JOIN _g2035_survivors s ON s.TreeEntityID = ins.TreeEntityID
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
            (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Ecosense_2035_Baseline'),
            b.LocationID, b.PlotID, b.CampaignID,
            (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2035'),
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
        FROM _g2035_base b
        WHERE b.r < 0.02
        LIMIT 30;

        DROP TABLE _g2035_base;
        DROP TABLE _g2035_survivors;
    END IF;
END $$;

-- ============================================================
-- VARIANT 2: Ecosense_Growth_2045 (from Ecosense_Growth_2035, +10 more years)
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM trees.Trees t
        WHERE t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2045')
    ) THEN

        CREATE TEMP TABLE _g2045_base AS
        SELECT
            t.TreeID AS base_tree_id, t.TreeEntityID, t.LocationID, t.PlotID, t.CampaignID,
            t.SpeciesID, t.TreeStatusID, t.BranchingPatternID, t.BarkCharacteristicID,
            t.Height_m, t.CrownWidth_m, t.CrownBaseHeight_m, t.Position, t.PositionOriginal, t.SourceCRS,
            t.Age_years, t.HealthScore, t.MeasurementDate,
            st.DBH_cm, st.TaperTypeID, st.StraightnessTypeID,
            random() AS r
        FROM trees.Trees t
        LEFT JOIN trees.Stems st ON st.TreeID = t.TreeID AND st.StemNumber = 1
        WHERE t.ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2035');

        -- ~5% mortality over the second decade
        CREATE TEMP TABLE _g2045_survivors AS
        SELECT * FROM _g2045_base WHERE r >= 0.05;

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
                (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Ecosense_2045_Baseline'),
                b.LocationID, b.PlotID, b.CampaignID,
                (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2045'),
                (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
                b.SpeciesID, b.TreeStatusID, b.BranchingPatternID, b.BarkCharacteristicID,
                b.MeasurementDate + INTERVAL '10 years', (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
                ROUND(b.Height_m * 1.10, 2),
                ROUND(b.CrownWidth_m * 1.07, 2),
                ROUND(b.CrownBaseHeight_m * 1.05, 2),
                b.Position, b.PositionOriginal, b.SourceCRS,
                10, b.Age_years + 10, b.HealthScore, 'growth_variant_seed'
            FROM _g2045_survivors b
            RETURNING TreeID, TreeEntityID
        )
        INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm, TaperTypeID, StraightnessTypeID)
        SELECT ins.TreeID, 1, ROUND(s.DBH_cm * 1.12, 2), s.TaperTypeID, s.StraightnessTypeID
        FROM ins
        JOIN _g2045_survivors s ON s.TreeEntityID = ins.TreeEntityID
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
            (SELECT VariantID FROM shared.Variants WHERE VariantName = 'Ecosense_2045_Baseline'),
            b.LocationID, b.PlotID, b.CampaignID,
            (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2045'),
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
        FROM _g2045_base b
        WHERE b.r < 0.02
        LIMIT 30;

        DROP TABLE _g2045_base;
        DROP TABLE _g2045_survivors;
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
    WHERE ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2035');
    SELECT COUNT(*) INTO v_2045 FROM trees.Trees
    WHERE ScenarioID = (SELECT ScenarioID FROM shared.Scenarios WHERE ScenarioName = 'Ecosense_Growth_2045');

    RAISE NOTICE 'Ecosense_Growth_2035: % tree rows', v_2035;
    RAISE NOTICE 'Ecosense_Growth_2045: % tree rows', v_2045;
END $$;
