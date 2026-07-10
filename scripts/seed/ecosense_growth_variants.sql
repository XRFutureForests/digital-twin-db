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
--    Ecosense_MixedPlot baseline trees to it (import_trees.py sets scenario_id
--    but not variant_id, so without this the baseline trees have no variant and
--    are invisible to ?variant_id= queries in UE).
-- 2. Creates two chained growth variants from that baseline:
--      Ecosense_Growth_2035  (parent: Current_Conditions, +10y)
--      Ecosense_Growth_2045  (parent: Ecosense_Growth_2035, +10y)
--    Each variant: scales Height_m/crown_width_m/crown_base_height_m/DBH_cm up by
--    a flat percentage, drops ~3-5% of trees (mortality), adds ~2% new saplings
--    (regeneration). parent_tree_id links each grown row back to its source.
--
-- Schema contract
-- ===============
-- trees.Trees PK = tree_id (serial)
-- trees.Trees.variant_id  FK → shared.Variants.variant_id   (filter attribute)
-- trees.Trees.parent_tree_id FK → trees.Trees.tree_id         (lineage)
-- trees.Trees.data_source_type_id FK → trees.DataSourceTypes.data_source_type_id
-- shared.Variants.variant_type_id FK → shared.VariantTypes.variant_type_id
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
    'Ecosense_MixedPlot field measurements, September 2025'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'baseline_2025'
);

-- Assign all Ecosense baseline trees to this variant
UPDATE trees.Trees t
SET variant_id = (
    SELECT v.variant_id FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'baseline_2025'
)
FROM shared.Locations l
WHERE t.location_id = l.location_id
  AND l.location_name = 'ecosense'
  AND t.variant_type_id = (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'original')
  AND t.variant_id IS NULL;

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

INSERT INTO shared.Variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'ecosense'),
    (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
    'growth_2035',
    2035, 10, 0,
    'Synthetic +10y growth from Current_Conditions baseline'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'growth_2035'
);

INSERT INTO shared.Variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, Description)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'ecosense'),
    (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
    'growth_2045',
    2045, 20, 0,
    'Synthetic +20y growth from Ecosense_Growth_2035'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'growth_2045'
);

-- ============================================================
-- VARIANT 1: Ecosense_Growth_2035  (+10 years from baseline)
-- ============================================================

DO $$
DECLARE v_variant_id INTEGER;
BEGIN
    SELECT v.variant_id INTO v_variant_id FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'growth_2035';

    IF NOT EXISTS (SELECT 1 FROM trees.Trees WHERE variant_id = v_variant_id) THEN

        CREATE TEMP TABLE _g2035_base AS
        SELECT
            t.tree_id        AS base_tree_id,
            t.tree_entity_id,
            t.location_id, t.plot_id, t.campaign_id,
            t.species_id, t.tree_status_id, t.branching_pattern_id, t.bark_characteristic_id,
            t.Height_m, t.crown_width_m, t.crown_base_height_m,
            t.Position, t.position_original, t.source_crs,
            t.Age_years, t.health_score, t.measurement_date,
            st.DBH_cm, st.taper_type_id, st.straightness_type_id,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Variants bv ON t.variant_id = bv.variant_id
        LEFT JOIN trees.Stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
        WHERE bv.variant_name = 'baseline_2025'
          AND bv.location_id = (SELECT location_id FROM shared.Locations WHERE location_name = 'ecosense');

        -- ~3% mortality: absent from the new variant
        CREATE TEMP TABLE _g2035_survivors AS
        SELECT * FROM _g2035_base WHERE r >= 0.03;

        -- Grow survivors +10 years
        WITH ins AS (
            INSERT INTO trees.Trees (
                tree_entity_id, parent_tree_id,
                variant_id,
                location_id, plot_id, campaign_id,
                scenario_id, variant_type_id,
                species_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
                measurement_date, data_source_type_id,
                Height_m, crown_width_m, crown_base_height_m,
                Position, position_original, source_crs,
                time_delta_yrs, Age_years, health_score, created_by
            )
            SELECT
                b.tree_entity_id, b.base_tree_id,
                v_variant_id,
                b.location_id, b.plot_id, b.campaign_id,
                (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth'),
                (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
                b.species_id, b.tree_status_id, b.branching_pattern_id, b.bark_characteristic_id,
                b.measurement_date + INTERVAL '10 years',
                (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
                ROUND(b.Height_m       * 1.12, 2),
                ROUND(b.crown_width_m   * 1.08, 2),
                ROUND(b.crown_base_height_m * 1.05, 2),
                b.Position, b.position_original, b.source_crs,
                10, b.Age_years + 10, b.health_score,
                'growth_variant_seed'
            FROM _g2035_survivors b
            RETURNING tree_id, tree_entity_id
        )
        INSERT INTO trees.Stems (tree_id, stem_number, DBH_cm, taper_type_id, straightness_type_id)
        SELECT ins.tree_id, 1, ROUND(s.DBH_cm * 1.15, 2), s.taper_type_id, s.straightness_type_id
        FROM ins
        JOIN _g2035_survivors s ON s.tree_entity_id = ins.tree_entity_id
        WHERE s.DBH_cm IS NOT NULL;

        -- ~2% regeneration: new saplings jittered near existing trees
        INSERT INTO trees.Trees (
            tree_entity_id, variant_id,
            location_id, plot_id, campaign_id,
            scenario_id, variant_type_id,
            species_id, measurement_date, data_source_type_id,
            Height_m, crown_width_m, crown_base_height_m,
            Position, Age_years, health_score, created_by
        )
        SELECT
            gen_random_uuid(), v_variant_id,
            b.location_id, b.plot_id, b.campaign_id,
            (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth'),
            (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
            b.species_id, b.measurement_date + INTERVAL '10 years',
            (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
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
    SELECT v.variant_id INTO v_variant_id FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'growth_2045';

    IF NOT EXISTS (SELECT 1 FROM trees.Trees WHERE variant_id = v_variant_id) THEN

        CREATE TEMP TABLE _g2045_base AS
        SELECT
            t.tree_id        AS base_tree_id,
            t.tree_entity_id,
            t.location_id, t.plot_id, t.campaign_id,
            t.species_id, t.tree_status_id, t.branching_pattern_id, t.bark_characteristic_id,
            t.Height_m, t.crown_width_m, t.crown_base_height_m,
            t.Position, t.position_original, t.source_crs,
            t.Age_years, t.health_score, t.measurement_date,
            st.DBH_cm, st.taper_type_id, st.straightness_type_id,
            random() AS r
        FROM trees.Trees t
        JOIN shared.Variants bv ON t.variant_id = bv.variant_id
        JOIN shared.Locations bl ON bv.location_id = bl.location_id
        LEFT JOIN trees.Stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
        WHERE bl.location_name = 'ecosense' AND bv.variant_name = 'growth_2035';

        -- ~5% mortality over the second decade
        CREATE TEMP TABLE _g2045_survivors AS
        SELECT * FROM _g2045_base WHERE r >= 0.05;

        WITH ins AS (
            INSERT INTO trees.Trees (
                tree_entity_id, parent_tree_id,
                variant_id,
                location_id, plot_id, campaign_id,
                scenario_id, variant_type_id,
                species_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
                measurement_date, data_source_type_id,
                Height_m, crown_width_m, crown_base_height_m,
                Position, position_original, source_crs,
                time_delta_yrs, Age_years, health_score, created_by
            )
            SELECT
                b.tree_entity_id, b.base_tree_id,
                v_variant_id,
                b.location_id, b.plot_id, b.campaign_id,
                (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth'),
                (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
                b.species_id, b.tree_status_id, b.branching_pattern_id, b.bark_characteristic_id,
                b.measurement_date + INTERVAL '10 years',
                (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
                ROUND(b.Height_m          * 1.10, 2),
                ROUND(b.crown_width_m      * 1.07, 2),
                ROUND(b.crown_base_height_m * 1.05, 2),
                b.Position, b.position_original, b.source_crs,
                10, b.Age_years + 10, b.health_score,
                'growth_variant_seed'
            FROM _g2045_survivors b
            RETURNING tree_id, tree_entity_id
        )
        INSERT INTO trees.Stems (tree_id, stem_number, DBH_cm, taper_type_id, straightness_type_id)
        SELECT ins.tree_id, 1, ROUND(s.DBH_cm * 1.12, 2), s.taper_type_id, s.straightness_type_id
        FROM ins
        JOIN _g2045_survivors s ON s.tree_entity_id = ins.tree_entity_id
        WHERE s.DBH_cm IS NOT NULL;

        -- ~2% further regeneration
        INSERT INTO trees.Trees (
            tree_entity_id, variant_id,
            location_id, plot_id, campaign_id,
            scenario_id, variant_type_id,
            species_id, measurement_date, data_source_type_id,
            Height_m, crown_width_m, crown_base_height_m,
            Position, Age_years, health_score, created_by
        )
        SELECT
            gen_random_uuid(), v_variant_id,
            b.location_id, b.plot_id, b.campaign_id,
            (SELECT s.scenario_id FROM shared.Scenarios s JOIN shared.Locations l ON s.location_id = l.location_id WHERE l.location_name = 'ecosense' AND s.scenario_name = 'natural_growth'),
            (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
            b.species_id, b.measurement_date + INTERVAL '10 years',
            (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated'),
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
-- Timeline order + lineage within natural_growth; resync trees.scenario_id
-- ============================================================
WITH ordered AS (
    SELECT v.variant_id,
           row_number() OVER (PARTITION BY v.scenario_id ORDER BY v.simulation_year, v.variant_id) - 1 AS so,
           lag(v.variant_id) OVER (PARTITION BY v.scenario_id ORDER BY v.simulation_year, v.variant_id) AS parent
    FROM shared.Variants v
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense'
)
UPDATE shared.Variants v
SET sort_order = o.so, parent_variant_id = o.parent
FROM ordered o WHERE v.variant_id = o.variant_id;

UPDATE trees.Trees t
SET scenario_id = v.scenario_id
FROM shared.Variants v
WHERE t.variant_id = v.variant_id
  AND t.scenario_id IS DISTINCT FROM v.scenario_id
  AND t.location_id = (SELECT location_id FROM shared.Locations WHERE location_name = 'ecosense');

DO $$
DECLARE
    v_baseline INTEGER;
    v_2035     INTEGER;
    v_2045     INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_baseline FROM trees.Trees t
    JOIN shared.Variants v ON t.variant_id = v.variant_id
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'baseline_2025';

    SELECT COUNT(*) INTO v_2035 FROM trees.Trees t
    JOIN shared.Variants v ON t.variant_id = v.variant_id
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'growth_2035';

    SELECT COUNT(*) INTO v_2045 FROM trees.Trees t
    JOIN shared.Variants v ON t.variant_id = v.variant_id
    JOIN shared.Locations l ON v.location_id = l.location_id
    WHERE l.location_name = 'ecosense' AND v.variant_name = 'growth_2045';

    RAISE NOTICE 'Ecosense Baseline_2025 : % trees', v_baseline;
    RAISE NOTICE 'Ecosense Growth_2035   : % trees', v_2035;
    RAISE NOTICE 'Ecosense Growth_2045   : % trees', v_2045;
END $$;
