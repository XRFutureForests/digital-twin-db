-- Thin every sub-15-minute series in sensor.sensorreadings to one reading per
-- hour: the raw point nearest each hour boundary, ties to the earlier point.
--
-- Four Ecosense soil-temperature profile probes (13 depths each) and three
-- ground probes log every 10 or 60 seconds. Their 55 series were 24.4 M of
-- dev's 35.8 M readings (68 %) and 20.7 M of dt.unr's 39.1 M when this was
-- written (2026-09-16), none of them linked to a tree, and Aquarius publishes
-- no hourly derivative of them. Loading the rest of 2025 at that cadence
-- would have put another 60 M rows behind three probes.
--
-- From the same day the aquarius connector stores such series hourly on the
-- way in (aquarius_connector.sync.nearest_hour_samples). The point kept is a
-- measurement the logger took, not a mean, so no derived-value provenance is
-- needed and `quality` keeps its meaning; the timestamp is kept as measured,
-- not snapped to the hour. This migration applies exactly the same rule to
-- what was loaded before it existed -- bucket = the hour nearest the reading
-- (floor of timestamp + 30 min), keep the reading with the smallest distance
-- to that hour, earlier wins a tie -- so a re-sync of a thinned month inserts
-- nothing. Change one and the other must follow.
--
-- Which series count as fast is decided from the data (median gap between
-- consecutive readings under 900 s), not from names: a fourth probe,
-- Test_Profile at Ecosense_University, only reported January to May and was
-- missed by every name-based list. The thinned sensors get
-- sampling_interval_seconds = 3600 and their native cadence in
-- external_metadata.native_interval_seconds, which is what the connector
-- writes too; sensor.check_sensor_health divides by that column, so it has to
-- describe the stored cadence.
--
-- Re-runnable, and meant to be re-run once after a backfill. The first pass
-- can only judge the hours it has: at the edge of a loaded window it keeps
-- 00:00:07 because it has never seen 23:59:57 the evening before, and the
-- backfill then brings that closer point in, leaving two readings for one
-- hour. A sensor already marked thinned (sampling_interval_seconds = 3600 with
-- a native_interval_seconds) is therefore included even though its stored
-- median gap is now an hour, and the second pass removes those duplicates.
-- First pass (2026-09-16): 55 series, 24.3 M rows removed on dev, 27.3 M on
-- dt.unr; the pass after the 2025 backfill removed edge rows only (XRFF-469).
--
-- Bucketing is done in UTC explicitly rather than in the session time zone so
-- the result does not depend on who applies it. On a fresh init the table is
-- empty and this is a no-op. It removes tens of millions of rows on a loaded
-- database; run `VACUUM (ANALYZE, PARALLEL 0) sensor.sensorreadings` afterwards
-- (not here -- VACUUM cannot run inside a transaction block; PARALLEL 0 because
-- the container's 64 MB /dev/shm cannot hold the parallel workers' segments).

SET statement_timeout = 0;

DO $$
DECLARE
    fast_count integer;
    removed bigint;
BEGIN
    CREATE TEMP TABLE fast_sensors ON COMMIT DROP AS
    WITH gaps AS (
        SELECT sensor_id,
               extract(epoch FROM "timestamp" - lag("timestamp") OVER (
                   PARTITION BY sensor_id ORDER BY "timestamp")) AS gap
        FROM sensor.sensorreadings
    ),
    detected AS (
        SELECT sensor_id,
               percentile_cont(0.5) WITHIN GROUP (ORDER BY gap) AS native_seconds
        FROM gaps
        WHERE gap IS NOT NULL
        GROUP BY sensor_id
        HAVING percentile_cont(0.5) WITHIN GROUP (ORDER BY gap) < 900
    )
    SELECT sensor_id, native_seconds FROM detected
    UNION ALL
    SELECT s.sensor_id, (s.external_metadata->>'native_interval_seconds')::numeric
    FROM sensor.sensors s
    WHERE s.sampling_interval_seconds = 3600
      AND s.external_metadata ? 'native_interval_seconds'
      AND NOT EXISTS (SELECT 1 FROM detected d WHERE d.sensor_id = s.sensor_id);

    SELECT count(*) INTO fast_count FROM fast_sensors;

    DELETE FROM sensor.sensorreadings r
    USING (
        SELECT sensor_reading_id,
               row_number() OVER (
                   PARTITION BY sensor_id,
                                date_trunc('hour', "timestamp" + interval '30 minutes', 'UTC')
                   ORDER BY abs(extract(epoch FROM "timestamp"
                                - date_trunc('hour', "timestamp" + interval '30 minutes', 'UTC'))),
                            "timestamp"
               ) AS rn
        FROM sensor.sensorreadings
        WHERE sensor_id IN (SELECT sensor_id FROM fast_sensors)
    ) k
    WHERE r.sensor_reading_id = k.sensor_reading_id
      AND k.rn > 1;
    GET DIAGNOSTICS removed = ROW_COUNT;

    UPDATE sensor.sensors s
    SET sampling_interval_seconds = 3600,
        external_metadata = coalesce(s.external_metadata, '{}'::jsonb)
                            || jsonb_build_object('native_interval_seconds',
                                                  round(f.native_seconds)::integer)
    FROM fast_sensors f
    WHERE s.sensor_id = f.sensor_id;

    RAISE NOTICE 'thinned % series to hourly, removed % readings', fast_count, removed;
END
$$;
