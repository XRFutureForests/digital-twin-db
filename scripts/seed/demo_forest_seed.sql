-- XR Future Forests Lab — Demo Forest Seed Data
-- XRFF-241: Small 4-species inventory with 3 scenario variants + sensor readings
--
-- OPTIONAL — not part of docker/volumes/db/init/. A fresh build must produce a
-- clean, empty database ready for real forest data; this seed is applied manually
-- when demo/test data is actually wanted:
--
--   docker exec -i dftdb-db psql -U postgres -d <POSTGRES_DB> -f - < scripts/seed/demo_forest_seed.sql
--
-- Requires the schema from 30-load-lookup-tables.sql / 31-refresh-lookup-functions.sql
-- to already exist (i.e. run after a normal `docker compose up`).
--
-- Creates:
--   • 1 field inventory campaign at Ecosense_MixedPlot
--   • 12 tree entities (4 species × 3 trees) across 3 scenarios = 36 tree rows
--   • 4 sensors (2 × Sap_Flow, 2 × Soil_Moisture)
--   • ~168 hourly readings per sensor (7 days) for Current_Conditions and Climate_Change_2050
--
-- Idempotent: guarded by NOT EXISTS checks on campaign_name and tree_entity_id/scenario_id.
-- Scenarios used: Current_Conditions (field), Climate_Change_2050 (simulated), Management_Thinning (model)

SET search_path TO shared, trees, sensor, public;

-- ============================================================
-- CAMPAIGN
-- ============================================================

INSERT INTO shared.Campaigns (
    campaign_name, campaign_type, location_id, start_date, end_date, Description, created_by
)
SELECT
    'Ecosense_Field_Inventory_2024',
    'field_inventory',
    (SELECT location_id FROM shared.Locations WHERE location_name = 'Ecosense_MixedPlot'),
    '2024-09-15',
    '2024-09-17',
    'Manual field inventory: height, DBH, crown dimensions at Ecosense mixed plot',
    'demo_seed'
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Campaigns WHERE campaign_name = 'Ecosense_Field_Inventory_2024'
);

-- ============================================================
-- TREE BASE DATA (temp table — 12 entities, stable UUIDs per session)
-- ============================================================

CREATE TEMP TABLE IF NOT EXISTS _demo_tree_bases (
    entity_uuid      UUID,
    species_sci      VARCHAR(200),
    lon              DOUBLE PRECISION,
    lat              DOUBLE PRECISION,
    height_m         NUMERIC(6,2),
    crown_m          NUMERIC(6,2),
    crown_base_m     NUMERIC(6,2),
    age_years        INTEGER,
    health           NUMERIC(3,2),
    thin             BOOLEAN     -- removed in Management_Thinning scenario
);

-- Only populate if we're actually going to insert trees
INSERT INTO _demo_tree_bases
SELECT * FROM (VALUES
    -- European Beech (3 trees) — dominant, retained in all scenarios
    (gen_random_uuid(), 'Fagus sylvatica',   7.8730, 47.9920,  28.5, 12.0, 10.5,  95, 0.92, false),
    (gen_random_uuid(), 'Fagus sylvatica',   7.8733, 47.9922,  31.2, 14.5, 12.0, 115, 0.95, false),
    (gen_random_uuid(), 'Fagus sylvatica',   7.8728, 47.9923,  25.8, 10.8,  9.2,  80, 0.88, false),
    -- Norway Spruce (3 trees) — 1 thinned in management scenario
    (gen_random_uuid(), 'Picea abies',       7.8735, 47.9921,  32.0,  8.5, 14.0,  70, 0.90, false),
    (gen_random_uuid(), 'Picea abies',       7.8737, 47.9919,  28.5,  7.2, 12.5,  58, 0.85, true),
    (gen_random_uuid(), 'Picea abies',       7.8731, 47.9918,  35.5,  9.8, 15.5,  85, 0.91, false),
    -- European Oak (3 trees) — retained in all scenarios
    (gen_random_uuid(), 'Quercus robur',     7.8729, 47.9924,  22.0, 15.2,  8.0, 130, 0.93, false),
    (gen_random_uuid(), 'Quercus robur',     7.8734, 47.9925,  24.5, 18.0,  9.5, 160, 0.96, false),
    (gen_random_uuid(), 'Quercus robur',     7.8726, 47.9922,  19.8, 13.5,  7.2, 105, 0.89, false),
    -- Silver Birch (3 trees) — all thinned (pioneer species removed in management)
    (gen_random_uuid(), 'Betula pendula',    7.8732, 47.9919,  18.5,  8.5,  6.5,  35, 0.94, true),
    (gen_random_uuid(), 'Betula pendula',    7.8736, 47.9923,  21.0,  9.8,  7.8,  45, 0.92, true),
    (gen_random_uuid(), 'Betula pendula',    7.8727, 47.9921,  16.2,  7.2,  5.5,  28, 0.90, true)
) v(entity_uuid, species_sci, lon, lat, height_m, crown_m, crown_base_m, age_years, health, thin)
WHERE NOT EXISTS (
    SELECT 1 FROM shared.Campaigns WHERE campaign_name = 'Ecosense_Field_Inventory_2024'
        AND (SELECT COUNT(*) FROM trees.Trees
             WHERE campaign_id = (SELECT campaign_id FROM shared.Campaigns
                                 WHERE campaign_name = 'Ecosense_Field_Inventory_2024')) > 0
);

-- ============================================================
-- VARIANT 1: Current_Conditions — field measurements (original)
-- ============================================================

INSERT INTO trees.Trees (
    tree_entity_id, location_id, species_id, scenario_id, variant_type_id, campaign_id,
    Position, Height_m, crown_width_m, crown_base_height_m, Age_years, health_score,
    measurement_date, data_source_type_id
)
SELECT
    b.entity_uuid,
    (SELECT location_id FROM shared.Locations WHERE location_name = 'Ecosense_MixedPlot'),
    (SELECT species_id FROM shared.Species WHERE scientific_name = b.species_sci),
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'original'),
    (SELECT campaign_id FROM shared.Campaigns WHERE campaign_name = 'Ecosense_Field_Inventory_2024'),
    extensions.ST_SetSRID(extensions.ST_MakePoint(b.lon, b.lat), 4326),
    b.height_m, b.crown_m, b.crown_base_m, b.age_years, b.health,
    '2024-09-15', (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'field')
FROM _demo_tree_bases b;

-- ============================================================
-- VARIANT 2: Climate_Change_2050 — SILVA/IPCC projections
-- Heights +20 %, crowns +15 %, conifers stressed (health −0.25)
-- ============================================================

INSERT INTO trees.Trees (
    tree_entity_id, location_id, species_id, scenario_id, variant_type_id,
    Position, Height_m, crown_width_m, crown_base_height_m, Age_years, health_score,
    measurement_date, data_source_type_id
)
SELECT
    b.entity_uuid,
    (SELECT location_id FROM shared.Locations WHERE location_name = 'Ecosense_MixedPlot'),
    (SELECT species_id FROM shared.Species WHERE scientific_name = b.species_sci),
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'simulated_growth'),
    extensions.ST_SetSRID(extensions.ST_MakePoint(b.lon, b.lat), 4326),
    ROUND(b.height_m * 1.20, 2),
    ROUND(b.crown_m  * 1.15, 2),
    ROUND(b.crown_base_m * 1.10, 2),
    b.age_years + 26,
    CASE
        WHEN b.species_sci = 'Picea abies'   THEN GREATEST(b.health - 0.25, 0.30)
        WHEN b.species_sci = 'Betula pendula' THEN GREATEST(b.health - 0.12, 0.50)
        ELSE GREATEST(b.health - 0.05, 0.60)
    END,
    '2050-06-01', (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated')
FROM _demo_tree_bases b;

-- ============================================================
-- VARIANT 3: Management_Thinning — selective removal of pioneers + excess conifers
-- 4 trees absent (3 birch + 1 spruce); remaining trees retain baseline dimensions
-- ============================================================

INSERT INTO trees.Trees (
    tree_entity_id, location_id, species_id, scenario_id, variant_type_id,
    Position, Height_m, crown_width_m, crown_base_height_m, Age_years, health_score,
    measurement_date, data_source_type_id
)
SELECT
    b.entity_uuid,
    (SELECT location_id FROM shared.Locations WHERE location_name = 'Ecosense_MixedPlot'),
    (SELECT species_id FROM shared.Species WHERE scientific_name = b.species_sci),
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Management_Thinning'),
    (SELECT variant_type_id FROM shared.VariantTypes WHERE variant_type_name = 'model_output'),
    extensions.ST_SetSRID(extensions.ST_MakePoint(b.lon, b.lat), 4326),
    b.height_m, b.crown_m, b.crown_base_m, b.age_years, b.health,
    '2024-09-15', (SELECT data_source_type_id FROM trees.DataSourceTypes WHERE data_source_type_name = 'simulated')
FROM _demo_tree_bases b
WHERE b.thin = false;    -- thinned trees are absent from this scenario entirely

-- ============================================================
-- SENSORS (4 units at Ecosense plot)
-- ============================================================

INSERT INTO sensor.Sensors (
    location_id, sensor_type_id, sensor_model, serial_number,
    Position, installation_date, installation_height_m,
    sampling_interval_seconds, Unit, is_active, created_by
)
SELECT
    (SELECT location_id FROM shared.Locations WHERE location_name = 'Ecosense_MixedPlot'),
    (SELECT sensor_type_id FROM sensor.SensorTypes WHERE sensor_type_name = s.type_name),
    s.model, s.serial,
    extensions.ST_SetSRID(extensions.ST_MakePoint(s.lon, s.lat), 4326),
    '2024-04-01'::timestamptz,
    s.install_h,
    3600,        -- hourly
    s.unit,
    true,
    'demo_seed'
FROM (VALUES
    ('Sap_Flow',     'Ecomatik SF-4',  'SF-001', 7.8730, 47.9920, 1.3, 'g/h'),
    ('Sap_Flow',     'Ecomatik SF-4',  'SF-002', 7.8735, 47.9921, 1.3, 'g/h'),
    ('Soil_Moisture','Decagon 5TM',    'SM-001', 7.8731, 47.9920, 0.0, '%'),
    ('Soil_Moisture','Decagon 5TM',    'SM-002', 7.8736, 47.9921, 0.0, '%')
) s(type_name, model, serial, lon, lat, install_h, unit)
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.Sensors WHERE serial_number = s.serial
);

-- ============================================================
-- SENSOR READINGS — Current_Conditions (7 days, hourly)
-- Sap flow: diurnal sine wave peaking midday (~750 g/h)
-- Soil moisture: slow weekly cycle (~30–38 %)
-- ============================================================

-- SF-001 (Beech 1) — Current_Conditions
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-001'),
    ts,
    GREATEST(0, ROUND(CAST(
        480 + 360 * sin((extract(hour from ts at time zone 'Europe/Berlin') - 6) * pi() / 12)
        + (random() - 0.5) * 60
    AS NUMERIC), 2)),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
FROM generate_series(
    '2024-09-15 00:00:00+02'::timestamptz,
    '2024-09-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-001')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
);

-- SF-002 (Spruce 1) — Current_Conditions (lower baseline, shallower diurnal swing)
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-002'),
    ts,
    GREATEST(0, ROUND(CAST(
        310 + 220 * sin((extract(hour from ts at time zone 'Europe/Berlin') - 7) * pi() / 12)
        + (random() - 0.5) * 40
    AS NUMERIC), 2)),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
FROM generate_series(
    '2024-09-15 00:00:00+02'::timestamptz,
    '2024-09-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-002')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
);

-- SM-001 — Current_Conditions (steady 30–38 %, minor weekly variation)
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-001'),
    ts,
    ROUND(CAST(
        34.0 + 4.0 * sin(extract(epoch from ts) / 604800.0 * 2 * pi())
        + (random() - 0.5) * 1.5
    AS NUMERIC), 2),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
FROM generate_series(
    '2024-09-15 00:00:00+02'::timestamptz,
    '2024-09-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-001')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
);

-- SM-002 — Current_Conditions (slightly drier plot)
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-002'),
    ts,
    ROUND(CAST(
        28.0 + 3.5 * sin(extract(epoch from ts) / 604800.0 * 2 * pi())
        + (random() - 0.5) * 1.5
    AS NUMERIC), 2),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
FROM generate_series(
    '2024-09-15 00:00:00+02'::timestamptz,
    '2024-09-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-002')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Current_Conditions')
);

-- ============================================================
-- SENSOR READINGS — Climate_Change_2050 (projected: heat stress)
-- Sap flow: higher peak but steeper midday collapse; moisture: −25 %
-- ============================================================

-- SF-001 — Climate_Change_2050
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-001'),
    ts,
    GREATEST(0, ROUND(CAST(
        580 + 420 * sin((extract(hour from ts at time zone 'Europe/Berlin') - 6) * pi() / 12)
        - 150 * POWER(sin((extract(hour from ts at time zone 'Europe/Berlin') - 6) * pi() / 12), 4)
        + (random() - 0.5) * 70
    AS NUMERIC), 2)),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
FROM generate_series(
    '2050-06-15 00:00:00+02'::timestamptz,
    '2050-06-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-001')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
);

-- SF-002 — Climate_Change_2050 (spruce severely stressed)
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-002'),
    ts,
    GREATEST(0, ROUND(CAST(
        180 + 120 * sin((extract(hour from ts at time zone 'Europe/Berlin') - 7) * pi() / 12)
        + (random() - 0.5) * 30
    AS NUMERIC), 2)),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
FROM generate_series(
    '2050-06-15 00:00:00+02'::timestamptz,
    '2050-06-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SF-002')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
);

-- SM-001 — Climate_Change_2050 (drier: ~22–26 %)
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-001'),
    ts,
    ROUND(CAST(
        24.0 + 2.5 * sin(extract(epoch from ts) / 604800.0 * 2 * pi())
        + (random() - 0.5) * 1.0
    AS NUMERIC), 2),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
FROM generate_series(
    '2050-06-15 00:00:00+02'::timestamptz,
    '2050-06-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-001')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
);

-- SM-002 — Climate_Change_2050
INSERT INTO sensor.SensorReadings (sensor_id, Timestamp, Value, Quality, scenario_id)
SELECT
    (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-002'),
    ts,
    ROUND(CAST(
        19.5 + 2.0 * sin(extract(epoch from ts) / 604800.0 * 2 * pi())
        + (random() - 0.5) * 1.0
    AS NUMERIC), 2),
    'good',
    (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
FROM generate_series(
    '2050-06-15 00:00:00+02'::timestamptz,
    '2050-06-21 23:00:00+02'::timestamptz,
    '1 hour'::interval
) ts
WHERE NOT EXISTS (
    SELECT 1 FROM sensor.SensorReadings sr
    WHERE sr.sensor_id = (SELECT sensor_id FROM sensor.Sensors WHERE serial_number = 'SM-002')
    AND sr.scenario_id = (SELECT scenario_id FROM shared.Scenarios WHERE scenario_name = 'Climate_Change_2050')
);

-- ============================================================
-- CLEANUP
-- ============================================================

DROP TABLE IF EXISTS _demo_tree_bases;

DO $$
DECLARE
    v_trees  INTEGER;
    v_reads  INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_trees FROM trees.Trees t
    WHERE t.campaign_id = (SELECT campaign_id FROM shared.Campaigns
                          WHERE campaign_name = 'Ecosense_Field_Inventory_2024');
    SELECT COUNT(*) INTO v_reads FROM sensor.SensorReadings sr
    WHERE sr.sensor_id IN (SELECT sensor_id FROM sensor.Sensors WHERE serial_number IN ('SF-001','SF-002','SM-001','SM-002'));

    RAISE NOTICE 'XRFF-241 demo seed: % tree variant rows, % sensor readings', v_trees, v_reads;
END $$;
