-- Two indexes on sensor.sensorreadings duplicate the table's unique key.
--
-- sensorreadings_sensorid_timestamp_unique (sensor_id, timestamp) is what
-- bulk_insert_readings' ON CONFLICT relies on, and a btree is read in either
-- direction, so idx_sensor_readings_sensor_timestamp (sensor_id, timestamp
-- DESC) answers no query the unique index does not -- including the UE views'
-- `?sensor_id=eq.N&order=timestamp.desc`, which becomes a backward scan of the
-- same index. idx_sensor_readings_sensor_id (sensor_id) is that index's
-- leading column, so it is a prefix of it.
--
-- Measured 2026-09-16, before the 2025 backfill: the two were 2,144 MB of the
-- table's 7,682 MB on dev (35.8 M readings) and 2,345 MB of 8,391 MB on dt.unr
-- (39.1 M) -- 28 % of the table, growing with every reading, and the DESC copy
-- had bloated to nearly twice the size of the unique index it duplicates.
--
-- 10-baseline-schema.sql still creates both, so on a fresh init this drops
-- what the baseline just built. That is the documented shape of this history:
-- additive files, the baseline is never edited.

DROP INDEX IF EXISTS sensor.idx_sensor_readings_sensor_timestamp;
DROP INDEX IF EXISTS sensor.idx_sensor_readings_sensor_id;
