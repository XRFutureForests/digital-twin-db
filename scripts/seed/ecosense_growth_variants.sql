-- XR Future Forests Lab — Ecosense Growth Variants (synthetic)
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually after
-- the baseline import:
--
--   docker exec -i dftdb-db psql -U postgres -d postgres < scripts/seed/ecosense_growth_variants.sql
--
-- What this does
-- ==============
-- 1. Creates a Current_Conditions variant in shared.Variants and assigns all
--    Ecosense_MixedPlot baseline trees to it (import_trees.py sets ScenarioID
--    but not VariantID, so without this the baseline trees have no variant and
--    are invisible to ?variantid= queries in UE).
-- 2. Creates two chained growth variants from that baseline:
--      Ecosense_Growth_2035  (parent: Current_Conditions, +10y)
--      Ecosense_Growth_2045  (parent: Ecosense_Growth_2035, +10y)
--    Each variant: scales Height_m/CrownWidth_m/CrownBaseHeight_m/DBH_cm up by
--    a flat percentage, drops ~3-5% of trees (mortality), adds ~2% new saplings
--    (regeneration). ParentTreeID links each grown row back to its source.
--
-- Schema contract
-- ===============
-- trees.Trees PK = TreeID (serial)
-- trees.Trees.VariantID  FK → shared.Variants.VariantID   (filter attribute)
-- trees.Trees.ParentTreeID FK → trees.Trees.TreeID         (lineage)
-- trees.Trees.DataSourceTypeID FK → trees.DataSourceTypes.DataSourceTypeID
-- shared.Variants.VariantTypeID FK → shared.VariantTypes.VariantTypeID
--
-- IMPORTANT: growth/mortality/regeneration numbers are simple placeholders for
-- exercising the schema and UE variant-switching end to end — NOT a calibrated
-- growth model. Treat this as synthetic test data.
--
-- Idempotent: each block is guarded by NOT EXISTS so re-running is a no-op.

SET search_path TO shared, trees, extensions, public;

-- ============================================================
-- STEP 0: Create the natural_growth scenario + baseline variant, assign trees
-- ============================================================

-- Scenarios are location-scoped (Location -> Scenario -> Variant). The ecosense
-- growth trajectory is ONE scenario ('natural_growth') that owns the baseline;
-- baseline_2025 / growth_2035 / growth_2045 are its successive variants.
INSERT INTO shared.Scenarios (LocationID, ScenarioName, Description)
SELECT
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'ecosense'),
    'natural_growth',
    'Baseline field inventory developing under no active management (growth only).'
ON CONFLICT (LocationID, ScenarioName) DO NOTHING;

-- Create the baseline variant (original field measurements, year 2025)
INSERT INTO shared.Variants (LocationID, ScenarioID, VariantTypeID, VariantName, SimulationYear, TimeDelta_yrs, SortOrder, Description)
SELECT
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'ecosense'),
    (SELECT s.ScenarioID FROM shared.Scenarios s JOIN shared.Locations l ON s.LocationID = l.LocationID WHERE l.LocationName = 'ecosense' AND s.ScenarioName = 'natural_growth'),
    (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original'),
    'baseline_2025',
    2025,
    0,
    0,
    'Ecosense_MixedPlot field measurements, September 2025'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'baseline_2025'
);

-- Assign all Ecosense baseline trees to this variant
UPDATE trees.Trees t
SET VariantID = (
    SELECT v.VariantID FROM shared.Variants v
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'baseline_2025'
)
FROM shared.Locations l
WHERE t.LocationID = l.LocationID
  AND l.LocationName = 'ecosense'
  AND t.VariantTypeID = (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original')
  AND t.VariantID IS NULL;

-- Reproducible randomness for mortality/regeneration sampling
SELECT setseed(0.42);

-- ============================================================
-- SCENARIOS for growth variants
-- ============================================================

-- (Growth states are variants of the single natural_growth scenario, not
--  separate scenarios — see STEP 0.)

-- ============================================================
-- VARIANTS for growth scenarios
-- ============================================================

INSERT INTO shared.Variants (LocationID, ScenarioID, VariantTypeID, VariantName, SimulationYear, TimeDelta_yrs, SortOrder, Description)
SELECT
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'ecosense'),
    (SELECT s.ScenarioID FROM shared.Scenarios s JOIN shared.Locations l ON s.LocationID = l.LocationID WHERE l.LocationName = 'ecosense' AND s.ScenarioName = 'natural_growth'),
    (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
    'growth_2035',
    2035, 10, 0,
    'Synthetic +10y growth from Current_Conditions baseline'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'growth_2035'
);

INSERT INTO shared.Variants (LocationID, ScenarioID, VariantTypeID, VariantName, SimulationYear, TimeDelta_yrs, SortOrder, Description)
SELECT
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'ecosense'),
    (SELECT s.ScenarioID FROM shared.Scenarios s JOIN shared.Locations l ON s.LocationID = l.LocationID WHERE l.LocationName = 'ecosense' AND s.ScenarioName = 'natural_growth'),
    (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
    'growth_2045',
    2045, 20, 0,
    'Synthetic +20y growth from Ecosense_Growth_2035'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'growth_2045'
);

-- ============================================================
-- VARIANT 1: Ecosense_Growth_2035  (+10 years from baseline)
-- ============================================================

DO $$
DECLARE v_variant_id INTEGER;
BEGIN
    SELECT v.VariantID INTO v_variant_id FROM shared.Variants v
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'growth_2035';

    IF NOT EXISTS (SELECT 1 FROM trees.Trees WHERE VariantID = v_variant_id) THEN

        CREATE TEMP TABLE _g2035_base AS
        SELECT
            t.TreeID        AS base_tree_id,
            t.TreeEntityID,
            t.LocationID, t.PlotID, t.CampaignID,
            t.SpeciesID, t.TreeStatusID, t.BranchingPatternID, t.BarkCharacteristicID,
            t.Height_m, t.CrownWidth_m, t.CrownBaseHeight_m,
            t.Position, t.PositionOriginal, t.SourceCRS,
            t.Age_years, t.HealthScore, t.MeasurementDate,
            st.DBH_cm, st.TaperTypeID, st.StraightnessTypeID,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Variants bv ON t.VariantID = bv.VariantID
        LEFT JOIN trees.Stems st ON st.TreeID = t.TreeID AND st.StemNumber = 1
        WHERE bv.VariantName = 'baseline_2025'
          AND bv.LocationID = (SELECT LocationID FROM shared.Locations WHERE LocationName = 'ecosense');

        -- ~3% mortality: absent from the new variant
        CREATE TEMP TABLE _g2035_survivors AS
        SELECT * FROM _g2035_base WHERE r >= 0.03;

        -- Grow survivors +10 years
        WITH ins AS (
            INSERT INTO trees.Trees (
                TreeEntityID, ParentTreeID,
                VariantID,
                LocationID, PlotID, CampaignID,
                ScenarioID, VariantTypeID,
                SpeciesID, TreeStatusID, BranchingPatternID, BarkCharacteristicID,
                MeasurementDate, DataSourceTypeID,
                Height_m, CrownWidth_m, CrownBaseHeight_m,
                Position, PositionOriginal, SourceCRS,
                TimeDelta_yrs, Age_years, HealthScore, CreatedBy
            )
            SELECT
                b.TreeEntityID, b.base_tree_id,
                v_variant_id,
                b.LocationID, b.PlotID, b.CampaignID,
                (SELECT s.ScenarioID FROM shared.Scenarios s JOIN shared.Locations l ON s.LocationID = l.LocationID WHERE l.LocationName = 'ecosense' AND s.ScenarioName = 'natural_growth'),
                (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
                b.SpeciesID, b.TreeStatusID, b.BranchingPatternID, b.BarkCharacteristicID,
                b.MeasurementDate + INTERVAL '10 years',
                (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
                ROUND(b.Height_m       * 1.12, 2),
                ROUND(b.CrownWidth_m   * 1.08, 2),
                ROUND(b.CrownBaseHeight_m * 1.05, 2),
                b.Position, b.PositionOriginal, b.SourceCRS,
                10, b.Age_years + 10, b.HealthScore,
                'growth_variant_seed'
            FROM _g2035_survivors b
            RETURNING TreeID, TreeEntityID
        )
        INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm, TaperTypeID, StraightnessTypeID)
        SELECT ins.TreeID, 1, ROUND(s.DBH_cm * 1.15, 2), s.TaperTypeID, s.StraightnessTypeID
        FROM ins
        JOIN _g2035_survivors s ON s.TreeEntityID = ins.TreeEntityID
        WHERE s.DBH_cm IS NOT NULL;

        -- ~2% regeneration: new saplings jittered near existing trees
        INSERT INTO trees.Trees (
            TreeEntityID, VariantID,
            LocationID, PlotID, CampaignID,
            ScenarioID, VariantTypeID,
            SpeciesID, MeasurementDate, DataSourceTypeID,
            Height_m, CrownWidth_m, CrownBaseHeight_m,
            Position, Age_years, HealthScore, CreatedBy
        )
        SELECT
            gen_random_uuid(), v_variant_id,
            b.LocationID, b.PlotID, b.CampaignID,
            (SELECT s.ScenarioID FROM shared.Scenarios s JOIN shared.Locations l ON s.LocationID = l.LocationID WHERE l.LocationName = 'ecosense' AND s.ScenarioName = 'natural_growth'),
            (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
            b.SpeciesID, b.MeasurementDate + INTERVAL '10 years',
            (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
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
-- VARIANT 2: Ecosense_Growth_2045  (+10 more years from 2035)
-- ============================================================

DO $$
DECLARE v_variant_id INTEGER;
BEGIN
    SELECT v.VariantID INTO v_variant_id FROM shared.Variants v
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'growth_2045';

    IF NOT EXISTS (SELECT 1 FROM trees.Trees WHERE VariantID = v_variant_id) THEN

        CREATE TEMP TABLE _g2045_base AS
        SELECT
            t.TreeID        AS base_tree_id,
            t.TreeEntityID,
            t.LocationID, t.PlotID, t.CampaignID,
            t.SpeciesID, t.TreeStatusID, t.BranchingPatternID, t.BarkCharacteristicID,
            t.Height_m, t.CrownWidth_m, t.CrownBaseHeight_m,
            t.Position, t.PositionOriginal, t.SourceCRS,
            t.Age_years, t.HealthScore, t.MeasurementDate,
            st.DBH_cm, st.TaperTypeID, st.StraightnessTypeID,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Variants bv ON t.VariantID = bv.VariantID
        JOIN shared.Locations bl ON bv.LocationID = bl.LocationID
        LEFT JOIN trees.Stems st ON st.TreeID = t.TreeID AND st.StemNumber = 1
        WHERE bl.LocationName = 'ecosense' AND bv.VariantName = 'growth_2035';

        -- ~5% mortality over the second decade
        CREATE TEMP TABLE _g2045_survivors AS
        SELECT * FROM _g2045_base WHERE r >= 0.05;

        WITH ins AS (
            INSERT INTO trees.Trees (
                TreeEntityID, ParentTreeID,
                VariantID,
                LocationID, PlotID, CampaignID,
                ScenarioID, VariantTypeID,
                SpeciesID, TreeStatusID, BranchingPatternID, BarkCharacteristicID,
                MeasurementDate, DataSourceTypeID,
                Height_m, CrownWidth_m, CrownBaseHeight_m,
                Position, PositionOriginal, SourceCRS,
                TimeDelta_yrs, Age_years, HealthScore, CreatedBy
            )
            SELECT
                b.TreeEntityID, b.base_tree_id,
                v_variant_id,
                b.LocationID, b.PlotID, b.CampaignID,
                (SELECT s.ScenarioID FROM shared.Scenarios s JOIN shared.Locations l ON s.LocationID = l.LocationID WHERE l.LocationName = 'ecosense' AND s.ScenarioName = 'natural_growth'),
                (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
                b.SpeciesID, b.TreeStatusID, b.BranchingPatternID, b.BarkCharacteristicID,
                b.MeasurementDate + INTERVAL '10 years',
                (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
                ROUND(b.Height_m          * 1.10, 2),
                ROUND(b.CrownWidth_m      * 1.07, 2),
                ROUND(b.CrownBaseHeight_m * 1.05, 2),
                b.Position, b.PositionOriginal, b.SourceCRS,
                10, b.Age_years + 10, b.HealthScore,
                'growth_variant_seed'
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
            TreeEntityID, VariantID,
            LocationID, PlotID, CampaignID,
            ScenarioID, VariantTypeID,
            SpeciesID, MeasurementDate, DataSourceTypeID,
            Height_m, CrownWidth_m, CrownBaseHeight_m,
            Position, Age_years, HealthScore, CreatedBy
        )
        SELECT
            gen_random_uuid(), v_variant_id,
            b.LocationID, b.PlotID, b.CampaignID,
            (SELECT s.ScenarioID FROM shared.Scenarios s JOIN shared.Locations l ON s.LocationID = l.LocationID WHERE l.LocationName = 'ecosense' AND s.ScenarioName = 'natural_growth'),
            (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'simulated_growth'),
            b.SpeciesID, b.MeasurementDate + INTERVAL '10 years',
            (SELECT DataSourceTypeID FROM trees.DataSourceTypes WHERE DataSourceTypeName = 'simulated'),
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

-- ============================================================
-- Timeline order + lineage within natural_growth; resync trees.ScenarioID
-- ============================================================
WITH ordered AS (
    SELECT v.VariantID,
           row_number() OVER (PARTITION BY v.ScenarioID ORDER BY v.SimulationYear, v.VariantID) - 1 AS so,
           lag(v.VariantID) OVER (PARTITION BY v.ScenarioID ORDER BY v.SimulationYear, v.VariantID) AS parent
    FROM shared.Variants v
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense'
)
UPDATE shared.Variants v
SET SortOrder = o.so, ParentVariantID = o.parent
FROM ordered o WHERE v.VariantID = o.VariantID;

UPDATE trees.Trees t
SET ScenarioID = v.ScenarioID
FROM shared.Variants v
WHERE t.VariantID = v.VariantID
  AND t.ScenarioID IS DISTINCT FROM v.ScenarioID
  AND t.LocationID = (SELECT LocationID FROM shared.Locations WHERE LocationName = 'ecosense');

DO $$
DECLARE
    v_baseline INTEGER;
    v_2035     INTEGER;
    v_2045     INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_baseline FROM trees.Trees t
    JOIN shared.Variants v ON t.VariantID = v.VariantID
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'baseline_2025';

    SELECT COUNT(*) INTO v_2035 FROM trees.Trees t
    JOIN shared.Variants v ON t.VariantID = v.VariantID
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'growth_2035';

    SELECT COUNT(*) INTO v_2045 FROM trees.Trees t
    JOIN shared.Variants v ON t.VariantID = v.VariantID
    JOIN shared.Locations l ON v.LocationID = l.LocationID
    WHERE l.LocationName = 'ecosense' AND v.VariantName = 'growth_2045';

    RAISE NOTICE 'Ecosense Baseline_2025 : % trees', v_baseline;
    RAISE NOTICE 'Ecosense Growth_2035   : % trees', v_2035;
    RAISE NOTICE 'Ecosense Growth_2045   : % trees', v_2045;
END $$;
