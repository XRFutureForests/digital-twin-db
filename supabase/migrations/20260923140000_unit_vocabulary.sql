-- =============================================================================
-- Tier 5: one unit vocabulary, behind a lookup
-- =============================================================================
-- XRFF-489, part of XRFF-494. The last of the identifier/vocabulary work and the
-- only one that rewrites values in live measurement data rather than names.
--
-- THE ACTUAL DEFECT was never "these columns have no CHECK constraint". It is
-- that sensor.Sensors.unit and sensor.SensorTypes.typical_unit hold different
-- spellings of the same physical unit, both within and between the two columns:
--
--   %        507 rows  |  percent   2 rows     -- same unit, same column
--   degC     646 rows  |  °C        (types)    -- same unit, different columns
--   W/m2       2 rows  |  W/m²      (types)
--   degree     2 rows  |  degrees   (types)
--   units                (types)               -- a placeholder, not a unit
--
-- Two CHECK constraints would have frozen that divergence in place. A lookup
-- gives both columns one source, which is how this schema resolves every other
-- vocabulary, and gives the display string somewhere to live.
--
-- ASCII, WITH _ AS THE DIVISOR. No /, no °, no ². These strings travel through
-- JSON, CSV, R column names and Unreal DataTable cells, and the symbols survive
-- that round trip less reliably than they look. The underscore form also makes
-- the unit vocabulary and the column-suffix convention one system rather than
-- two: the column is stand_volume_m3ha and wood_density_kg_m3, so the unit is
-- m3_ha and kg_m3.
--
-- unit_display carries the symbol for rendering. It is deliberately NOT exposed
-- on the ue_* views yet -- those move with the Unreal cutover (XRFF-492), and
-- adding a column there now would mean the external developer touches the same
-- views twice.
--
-- Note for whoever reads the Unreal caches next: the VALUES in ue_sensors.unit
-- and ue_sensor_readings.unit change here (degC becomes deg_c, % becomes
-- percent). That is a visible string change, not a silent null -- the DataTable
-- import still succeeds, the label just reads differently until UE switches to
-- unit_display.
--
-- sensor.Sensors.reading_type is untouched. All 1,418 rows are NULL and nothing
-- writes it, but it is exposed on the writable public.Sensors view, so removing
-- it means rebuilding that view's three INSTEAD OF triggers. That is a
-- destructive change on its own terms and gets its own decision.
--
-- Mirrored to init 52-unit-vocabulary.sql.
-- =============================================================================

SET search_path TO sensor, public;

-- 1. The vocabulary.
CREATE TABLE IF NOT EXISTS sensor.units (
    unit_id      SERIAL PRIMARY KEY,
    unit_name    VARCHAR(32) NOT NULL UNIQUE,
    unit_display VARCHAR(32) NOT NULL,
    description  TEXT
);

COMMENT ON TABLE sensor.units IS
    'Canonical physical units for sensor.Sensors.unit and '
    'sensor.SensorTypes.typical_unit. unit_name is ASCII with _ as the divisor '
    'so it survives JSON, CSV, R and Unreal DataTable round trips; unit_display '
    'is the symbol to render.';

INSERT INTO sensor.units (unit_name, unit_display, description) VALUES
    ('deg_c',   '°C',      'degrees Celsius'),
    ('percent', '%',       'percent'),
    ('m3_m3',   'm³/m³',   'volumetric water content'),
    ('l_hr',    'l/hr',    'litres per hour'),
    ('g_h',     'g/h',     'grams per hour'),
    ('w_m2',    'W/m²',    'irradiance'),
    ('m_s',     'm/s',     'metres per second'),
    ('deg',     '°',       'degrees of arc'),
    ('mpa',     'MPa',     'megapascal'),
    ('hpa',     'hPa',     'hectopascal'),
    ('bar',     'bar',     'bar'),
    ('mv',      'mV',      'millivolt'),
    ('mm',      'mm',      'millimetre'),
    ('ppm',     'ppm',     'parts per million'),
    ('lux',     'lux',     'illuminance')
ON CONFLICT (unit_name) DO NOTHING;

-- 2. Normalise both columns onto it. Every spelling currently in the data is
--    mapped explicitly rather than by a rule, so an unmapped value fails the FK
--    below instead of being silently coerced.
UPDATE sensor.sensors SET unit = CASE unit
    WHEN 'degC'    THEN 'deg_c'
    WHEN '°C'      THEN 'deg_c'
    WHEN '%'       THEN 'percent'
    WHEN 'percent' THEN 'percent'
    WHEN 'm^3/m^3' THEN 'm3_m3'
    WHEN 'l/hr'    THEN 'l_hr'
    WHEN 'W/m2'    THEN 'w_m2'
    WHEN 'm/s'     THEN 'm_s'
    WHEN 'degree'  THEN 'deg'
    WHEN 'MPa'     THEN 'mpa'
    WHEN 'hPa'     THEN 'hpa'
    WHEN 'mV'      THEN 'mv'
    ELSE unit
END
WHERE unit IS NOT NULL;

UPDATE sensor.sensor_types SET typical_unit = CASE typical_unit
    WHEN '°C'      THEN 'deg_c'
    WHEN '%'       THEN 'percent'
    WHEN 'W/m²'    THEN 'w_m2'
    WHEN 'm/s'     THEN 'm_s'
    WHEN 'degrees' THEN 'deg'
    WHEN 'g/h'     THEN 'g_h'
    WHEN 'MPa'     THEN 'mpa'
    WHEN 'hPa'     THEN 'hpa'
    WHEN 'mV'      THEN 'mv'
    -- 'units' was a placeholder, not a unit. NULL says "unknown" honestly.
    WHEN 'units'   THEN NULL
    ELSE typical_unit
END
WHERE typical_unit IS NOT NULL;

-- 3. The FKs. These are what stop the two columns diverging again, which two
--    independent CHECK constraints would not have done.
ALTER TABLE sensor.sensors
    ADD CONSTRAINT sensors_unit_fkey
    FOREIGN KEY (unit) REFERENCES sensor.units(unit_name);

ALTER TABLE sensor.sensor_types
    ADD CONSTRAINT sensor_types_typical_unit_fkey
    FOREIGN KEY (typical_unit) REFERENCES sensor.units(unit_name);

COMMENT ON COLUMN sensor.sensors.unit IS
    'Canonical unit of this sensor''s readings, from sensor.Units. ASCII with _ '
    'as the divisor; render sensor.Units.unit_display instead of this value.';
COMMENT ON COLUMN sensor.sensor_types.typical_unit IS
    'Default unit for this sensor type, from sensor.Units. NULL where the type '
    'has no single natural unit.';

-- NOT here: aligning sensor.Sensors.source to TEXT. It is varchar here and text
-- in its three siblings, the only column name in the database with two types.
-- Changing it is refused while public.Sensors selects it ("cannot alter type of
-- a column used by a view or rule"), so it needs the same writable-view rebuild
-- as dropping reading_type, and belongs with that decision rather than here.
