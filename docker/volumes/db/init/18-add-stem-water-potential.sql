-- =============================================================================
-- Add stem_water_potential and reclassify the sensors misfiled as barometric
-- =============================================================================
-- Every one of the 40 sensors typed `barometric_pressure` is in fact a stem
-- water potential probe. None of them measures atmospheric pressure:
--
--   serial_number         Beech_Mixed_1_StemWaterPotential
--                         Beech_Mixed_1_StemWaterPotential_in_MPa
--   unit                  bar (22 sensors) / MPa (18 sensors), never hPa
--   observed values       -31.19 .. 0.67 bar, -3.12 .. 0.07 MPa
--   typical_range on type 900 .. 1100 hPa
--
-- The misclassification comes from aquarius-connector's PARAM_MAPPING, which
-- keyed on the Aquarius `Parameter` field alone. Aquarius reports these series
-- as Parameter "BarPressure" because they are read through a pressure
-- transducer, while the Label and Unit carry the actual quantity. The connector
-- has been changed to disambiguate on the Label, so a re-sync will no longer
-- reintroduce this.
--
-- Water potential is negative by definition (xylem tension), so the range below
-- is signed. It is recorded in MPa, the conventional unit; the 22 series logged
-- in bar keep `bar` in sensor.Sensors.unit, which is where the per-sensor unit
-- belongs. 1 MPa = 10 bar.
--
-- Idempotent: safe to re-run, and it will not touch a genuine barometric
-- pressure sensor should one ever be registered.
-- =============================================================================

-- 1. The lookup row. Mirrors data/lookups/sensor_types.csv, which
--    docker/volumes/db/init/30-load-lookup-tables.sql loads on a clean build.
INSERT INTO sensor.SensorTypes
    (sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max)
VALUES
    ('stem_water_potential',
     'Stem xylem water potential, read through a pressure transducer. Negative under tension.',
     'MPa', -10, 1)
ON CONFLICT (sensor_type_name) DO UPDATE SET
    Description       = EXCLUDED.Description,
    typical_unit      = EXCLUDED.typical_unit,
    typical_range_min = EXCLUDED.typical_range_min,
    typical_range_max = EXCLUDED.typical_range_max;

-- 2. Reclassify. Matched on the serial number rather than on unit or value
--    range so the intent is legible and a genuine hPa sensor is never caught.
UPDATE sensor.Sensors s
SET    sensor_type_id = (SELECT sensor_type_id FROM sensor.SensorTypes
                         WHERE sensor_type_name = 'stem_water_potential'),
       updated_at     = now(),
       updated_by     = 'migration 20260901140000'
WHERE  s.sensor_type_id = (SELECT sensor_type_id FROM sensor.SensorTypes
                           WHERE sensor_type_name = 'barometric_pressure')
  AND  s.serial_number ILIKE '%StemWaterPotential%';

-- 3. Report, so a rebuild log shows what moved.
DO $$
DECLARE
    moved     INT;
    remaining INT;
BEGIN
    SELECT count(*) INTO moved
    FROM sensor.Sensors s
    JOIN sensor.SensorTypes st USING (sensor_type_id)
    WHERE st.sensor_type_name = 'stem_water_potential';

    SELECT count(*) INTO remaining
    FROM sensor.Sensors s
    JOIN sensor.SensorTypes st USING (sensor_type_id)
    WHERE st.sensor_type_name = 'barometric_pressure';

    RAISE NOTICE 'stem_water_potential sensors: %; still typed barometric_pressure: %',
                 moved, remaining;
END $$;
