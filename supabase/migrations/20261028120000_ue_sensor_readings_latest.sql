-- =============================================================================
-- ue_sensor_readings_latest: the newest N readings, sorted by sensor, then time
-- =============================================================================
-- Unreal's readings fetcher asks for GET /ue_sensor_readings?order=timestamp.desc
-- &limit=100000 and fills DT_SensorReadings in reply order, so the table comes
-- out sorted by time across all sensors. Browsing one sensor's series means
-- scrolling through every other sensor. Wanted: sensor_id, then timestamp_unix.
--
-- A query string cannot do it: PostgREST sorts before it limits, so
-- order=sensor_id.asc,timestamp_unix.asc&limit=100000 returns the OLDEST
-- readings of the first ~85 sensors instead of the newest 100,000. An ORDER BY
-- in the view itself is no option either: the planner keeps it under the
-- caller's ORDER BY and sorts all 33 M rows first (all-sites fetch measured
-- 24.4 s instead of 136 ms on dev, 2026-10-28).
--
-- This function picks the newest p_limit readings over the timestamp index and
-- sorts only those. p_location_id (optional) restricts to one site; filter with
-- it, not with ?location_id=eq. on the call -- a PostgREST filter on an RPC
-- applies after the limit.
--   GET /rpc/ue_sensor_readings_latest?p_limit=100000
--   GET /rpc/ue_sensor_readings_latest?p_limit=100000&p_location_id=2
--
-- Mirrored to init 65-ue-sensor-readings-latest.sql.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.ue_sensor_readings_latest(
    p_limit integer DEFAULT 100000,
    p_location_id integer DEFAULT NULL
)
RETURNS SETOF public.ue_sensor_readings
LANGUAGE sql
STABLE
AS $$
    SELECT newest.*
      FROM (SELECT r.*
              FROM public.ue_sensor_readings r
             WHERE p_location_id IS NULL OR r.location_id = p_location_id
             ORDER BY r."timestamp" DESC
             LIMIT p_limit) newest
     ORDER BY newest.sensor_id, newest.timestamp_unix;
$$;

COMMENT ON FUNCTION public.ue_sensor_readings_latest(integer, integer) IS 'The newest p_limit rows of ue_sensor_readings (optionally of one site, p_location_id), returned sorted by sensor_id, then timestamp_unix -- the order Unreal''s DT_SensorReadings wants. Filter by site with p_location_id, not with a PostgREST filter (that applies after the limit). GET /rest/v1/rpc/ue_sensor_readings_latest?p_limit=100000';

GRANT EXECUTE ON FUNCTION public.ue_sensor_readings_latest(integer, integer) TO PUBLIC, postgres, anon, authenticated, service_role;
