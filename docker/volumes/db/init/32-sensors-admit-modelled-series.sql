-- Mirrored from supabase/migrations/20260903120000_sensors_admit_modelled_series.sql.
-- Fresh builds get the function and comments here; existing databases get them
-- from the migration. Keep the two identical.
-- =============================================================================
-- sensor.Sensors admits modelled series, and the scene feed says which is which
-- =============================================================================
-- XRFF-371 lands weather reanalysis in the sensor tables as virtual sensors:
-- one per (location, quantity), `source = 'open-meteo'`, no hardware behind it.
-- Two things have to change before the first such row exists, both found by the
-- consumer audit recorded on that issue.
--
-- ## 1. The scene feed could not tell them apart
--
-- public.ue_sensor_state_at is the whole-scene "reading at time T" call behind
-- the XRFF-72 VR time slider. It returned sensor_id, sensor_type, unit,
-- timestamp, value, quality and linked_tree_id -- and **not** source. So a
-- Blueprint asking for "temperature" would receive a modelled air temperature
-- and a measured soil probe in the same result set with nothing to separate
-- them. `linked_tree_id` does not help: 735 of the 1,404 sensors that exist
-- today are unlinked physical station probes, so NULL there already means
-- "not on a tree", not "not real".
--
-- Adding a column to a RETURNS TABLE needs a DROP, not a CREATE OR REPLACE.
-- Everything else about the function is unchanged -- same LATERAL, same
-- lookback, same SECURITY INVOKER, same grants -- and it has existed for less
-- than a day, so nothing depends on the old shape.
--
-- ## 2. The table comment was about to become false
--
-- "Physical sensor installations with metadata and configuration" stops being
-- true the moment a reanalysis series is a row here. That comment was left
-- deliberately unchanged when the open-data connector was designed, as a
-- forcing function: whoever had to edit it would have to find the consumers
-- that assume it. That audit is now done and recorded on XRFF-371, so the
-- comment can go.
--
-- What deliberately does NOT change: no virtual `sensortypes` family. The 15
-- rows there are *quantities* -- temperature, humidity, wind_speed -- not
-- hardware families, and 10 of them are unused and are exactly what weather
-- data needs. A parallel `virtual_temperature` would assert that a modelled
-- temperature is a different kind of measurement from a measured one, and
-- would silently break every `sensor_type_name IN (...)` filter in the
-- dashboard. `source` is the discriminator, and it already exists.

DROP FUNCTION IF EXISTS public.ue_sensor_state_at(timestamptz, interval);

CREATE FUNCTION public.ue_sensor_state_at(
    p_timestamp timestamptz,
    p_lookback  interval DEFAULT '1 hour'
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
'`source` names the provider: an instrument network such as ''aquarius'', or a model such as '
'''open-meteo'' whose readings are computed rather than measured. Filter on it before showing a '
'value as an observation. '
'POST /rest/v1/rpc/ue_sensor_state_at  {"p_timestamp":"2025-07-15T12:00:00Z"}';

GRANT EXECUTE ON FUNCTION public.ue_sensor_state_at(timestamptz, interval) TO anon, authenticated, service_role;

COMMENT ON TABLE sensor.sensors IS
'Sensors and the series they produce, physical or modelled. Most rows are physical installations '
'with an instrument, a serial number and a position. Rows whose `source` names a model or '
'reanalysis (e.g. ''open-meteo'') are virtual: one series per location and quantity, no hardware, '
'`serial_number` NULL and no entry in sensor.sensor_tree_links. Discriminate on `source`, never on '
'`sensor_type_id` -- the types are quantities, shared by both kinds.';
