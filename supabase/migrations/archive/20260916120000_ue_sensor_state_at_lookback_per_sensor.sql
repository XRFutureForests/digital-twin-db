-- ue_sensor_state_at: the default lookback follows each sensor's own cadence.
--
-- The function's one-hour default was justified as "four times the 900 s
-- sampling interval the Ecosense nodes report" (20260903100000). That was true
-- of the 15-minute network and false of everything else: the open-meteo
-- weather series report hourly, and since 20260916110000 the sub-15-minute
-- profile probes are stored hourly too -- the raw point nearest each hour, so a
-- reading sits within a few seconds either side of the hour. A fixed one-hour
-- window ending at, say, 13:00:02 can contain neither the 12:59:57 sample nor
-- the 13:00:03 one, and the sensor silently drops out of the slider for that
-- tick. It reappears a moment later, which is the worst kind of absence to
-- debug from a headset.
--
-- sampling_interval_seconds now describes the stored cadence of every sensor
-- (the connector sets it from the observed points), so the same rule can be
-- applied per sensor: default lookback = 4 x sampling_interval_seconds. For the
-- 15-minute network that is exactly the old hour; for hourly series it is four
-- hours, so a series that missed three consecutive readings still shows, which
-- was the original intent. An explicit p_lookback still overrides it for every
-- sensor, as before.
--
-- The lower bound is still a constant per outer row, so the LATERAL stays one
-- backward index range scan per sensor on sensorreadings_sensorid_timestamp_unique
-- (the DESC duplicate the 20260903 note named was dropped in 20260916100000).
-- Body and result shape otherwise as 20260903120000 left them (that migration
-- added `source`); same signature, so CREATE OR REPLACE keeps the grants.

SET search_path TO public, sensor, trees;

CREATE OR REPLACE FUNCTION public.ue_sensor_state_at(
    p_timestamp timestamptz,
    p_lookback  interval DEFAULT NULL
)
RETURNS TABLE (
    sensor_id       integer,
    source          character varying,
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
           s.source,
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
            -- sensor has ever produced. Its width is the caller's, or four of
            -- this sensor's stored sampling intervals.
            SELECT sr."timestamp", sr.value, sr.quality
              FROM sensor.sensorreadings sr
             WHERE sr.sensor_id = s.sensor_id
               AND sr."timestamp" <= p_timestamp
               AND sr."timestamp" >  p_timestamp
                                     - coalesce(p_lookback,
                                                (4 * s.sampling_interval_seconds) * interval '1 second')
             ORDER BY sr."timestamp" DESC
             LIMIT 1
     ) r;
$$;

COMMENT ON FUNCTION public.ue_sensor_state_at(timestamptz, interval) IS
'Latest reading per sensor at or before p_timestamp, within p_lookback (default: 4 x the sensor''s '
'sampling_interval_seconds -- one hour for the 15-min network, four hours for hourly series). '
'The scene-wide counterpart to ue_sensorreadings, for driving a VR time slider from one request. '
'Sensors with no reading in the window are absent from the result -- that is deliberate, a gap in '
'the record must not be papered over with a stale value. '
'`source` names the provider: an instrument network such as ''aquarius'', or a model such as '
'''open-meteo'' whose readings are computed rather than measured. Filter on it before showing a '
'value as an observation. '
'POST /rest/v1/rpc/ue_sensor_state_at  {"p_timestamp":"2025-07-15T12:00:00Z"}';

NOTIFY pgrst, 'reload schema';
