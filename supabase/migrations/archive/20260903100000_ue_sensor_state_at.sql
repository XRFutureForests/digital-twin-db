-- =============================================================================
-- A scene-wide "sensor state at time T" call for the VR time slider
-- =============================================================================
-- XRFF-72 drives sensor values from a project-level DateTime variable: move the
-- slider, and every sensorised asset in the scene shows its reading for that
-- moment. That is a different question from the one public.ue_sensorreadings
-- answers. That view is a per-sensor time series -- its own COMMENT says
-- "?sensor_id=eq.<id>&order=timestamp.desc&limit=96" -- and asking it for the
-- whole scene means either 1,404 requests per slider tick or a client-side
-- reduction over every reading in the window.
--
-- The natural single query is "the latest reading per sensor at or before T",
-- which PostgREST cannot express: there is no DISTINCT ON and no LATERAL in the
-- URL grammar. Hence a function.
--
-- ## Why the shape below, and not the obvious one
--
-- Measured on the server 2026-09-03 against 38,977,388 readings, PGDATA on the
-- NFS export:
--
--   DISTINCT ON (sensor_id) ... WHERE timestamp <= T
--     -> 17,819 ms. Parallel seq scan over 29M rows, then a 315 MB external
--        merge sort spilling to the network filesystem. 89x the entire 200 ms
--        budget for a VR level load, and it gets worse as readings accumulate.
--
--   the LATERAL below, 1 hour lookback
--     -> 1,166 ms cold, 10 ms warm. 1,404 index seeks on
--        idx_sensor_readings_sensor_timestamp, one per sensor, each returning a
--        single row.
--
-- The cold number is almost entirely NFS round trips on a cold shared_buffers;
-- see the memory settings in docker/docker-compose.yml, tuned in the same
-- change. The warm number is the one the slider will actually see, because a
-- user dragging a slider re-reads the same neighbourhood of the index.
--
-- ## Why the lookback is required, not a tuning knob
--
-- An unbounded "latest reading at or before T" is wrong for this database, not
-- merely slow. Readings were loaded as four 30-day windows, one per season of
-- 2025 (XRFF-238), so March, June, August, September and November are empty. A
-- slider at 15 June would be handed each sensor's last reading from 1 May and
-- present it as the state of the forest in June. Bounding the lookback makes the
-- gap visible as an absent row, which is the truthful answer.
--
-- The default of one hour is four times the 900 s sampling interval the Ecosense
-- nodes report, so a sensor that missed three consecutive readings still shows.
-- Callers wanting sparser data can pass a longer interval deliberately.
--
-- linked_tree_id rides along because "apply the reading to the relevant in-scene
-- asset" is the whole point, and resolving it here costs one join against 1,404
-- rows rather than a second round trip from the headset.
-- =============================================================================

SET search_path TO public, sensor, trees;

CREATE OR REPLACE FUNCTION public.ue_sensor_state_at(
    p_timestamp timestamptz,
    p_lookback  interval DEFAULT '1 hour'
)
RETURNS TABLE (
    sensor_id       integer,
    sensor_type     character varying,
    unit            character varying,
    "timestamp"     timestamptz,
    value           numeric,
    quality         character varying,
    linked_tree_id  integer
)
LANGUAGE sql
STABLE
-- SECURITY INVOKER (the default) on purpose: row-level security on
-- sensor.SensorReadings must apply to the caller, exactly as it does for the
-- ue_sensorreadings view, which is declared security_invoker='on'.
AS $$
    SELECT s.sensor_id,
           st.sensor_type_name AS sensor_type,
           s.unit,
           r."timestamp",
           r.value,
           r.quality,
           stl.tree_id AS linked_tree_id
      FROM sensor.sensors s
      JOIN sensor.sensortypes st
        ON st.sensor_type_id = s.sensor_type_id
      LEFT JOIN sensor.sensor_tree_links stl
        ON stl.sensor_id = s.sensor_id
     CROSS JOIN LATERAL (
            -- One index seek per sensor. Both bounds are needed: the upper one
            -- is the question being asked, the lower one is what keeps this an
            -- index range scan instead of a walk back through every reading the
            -- sensor has ever produced.
            SELECT sr."timestamp", sr.value, sr.quality
              FROM sensor.sensorreadings sr
             WHERE sr.sensor_id = s.sensor_id
               AND sr."timestamp" <= p_timestamp
               AND sr."timestamp" >  p_timestamp - p_lookback
             ORDER BY sr."timestamp" DESC
             LIMIT 1
     ) r;
$$;

COMMENT ON FUNCTION public.ue_sensor_state_at(timestamptz, interval) IS
'Latest reading per sensor at or before p_timestamp, within p_lookback (default 1 hour). '
'The scene-wide counterpart to ue_sensorreadings, for driving a VR time slider from one request. '
'Sensors with no reading in the window are absent from the result -- that is deliberate, the '
'2025 data has seasonal gaps and a stale value would misrepresent them. '
'POST /rest/v1/rpc/ue_sensor_state_at  {"p_timestamp":"2025-07-15T12:00:00Z"}';

GRANT EXECUTE ON FUNCTION public.ue_sensor_state_at(timestamptz, interval) TO anon, authenticated, service_role;
