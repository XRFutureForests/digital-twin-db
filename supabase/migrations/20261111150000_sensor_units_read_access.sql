-- =============================================================================
-- sensor.units: readable like every other sensor lookup table
-- =============================================================================
-- sensor.units carries the display symbol for sensor.sensor_types.typical_unit
-- and sensor.sensors.unit, but was created without row-level security, a read
-- policy or any grants. The dashboard joins it in its sensor-type query and
-- reads as dashboard_reader (a member of anon), so the query failed with
-- "permission denied for table units" and the EcoSense sensor tab showed "No
-- sensors linked to trees at this site" for every tree (2026-11-11).
--
-- Same shape as sensor.sensor_types: RLS on, everyone may read, writes stay
-- with the service role.
-- =============================================================================

ALTER TABLE sensor.units ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Units are viewable by everyone" ON sensor.units;
CREATE POLICY "Units are viewable by everyone" ON sensor.units FOR SELECT USING (true);

GRANT SELECT ON TABLE sensor.units TO anon;
GRANT SELECT ON TABLE sensor.units TO authenticated;
GRANT ALL ON TABLE sensor.units TO service_role;
