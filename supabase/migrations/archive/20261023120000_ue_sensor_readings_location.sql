-- =============================================================================
-- ue_sensor_readings: location_id, so a site fetches only its own readings
-- =============================================================================
-- Unreal's readings fetcher asks for the newest 100,000 readings of all sites,
-- so every site's cache and table carries the other sites' readings (about
-- 20 MB per site) and the per-site lookups are built from rows that never
-- match a sensor of the site. The sensor already knows its location
-- (sensor.sensors.location_id); the view now passes it on, and the fetcher
-- filters with location_id=eq.<site>.
--
-- location_id is the LAST column (CREATE OR REPLACE VIEW can only append); the
-- view body is otherwise unchanged. Unreal: the readings struct ST_SensorReading
-- does not need the field (the JSON parser ignores unknown keys); the fetcher
-- adds the filter.
--
-- Mirrored to init 64-ue-sensor-readings-location.sql.
-- =============================================================================

CREATE OR REPLACE VIEW public.ue_sensor_readings
WITH (security_invoker = on) AS
 SELECT sr.sensor_reading_id,
    sr.sensor_id,
    st.sensor_type_name,
    s.unit,
    sr."timestamp",
    sr.value,
    sr.quality,
    EXTRACT(epoch FROM sr."timestamp")::bigint AS timestamp_unix,
    s.location_id
   FROM sensor.sensor_readings sr
     JOIN sensor.sensors s ON sr.sensor_id = s.sensor_id
     JOIN sensor.sensor_types st ON s.sensor_type_id = st.sensor_type_id;

COMMENT ON VIEW public.ue_sensor_readings IS 'Enriched sensor time-series for UE Blueprint. Includes sensor type, unit, timestamp_unix (epoch seconds) and the sensor''s location_id, keyed by sensor_id. Look up the linked tree once via ue_sensors, not per reading. GET /ue_sensor_readings?location_id=eq.<site>&order=timestamp.desc&limit=100000 (one site), or ?sensor_id=eq.<id>&order=timestamp.desc&limit=96 (one sensor).';
