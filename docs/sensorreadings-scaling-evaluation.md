# `sensor.sensorreadings` Scaling Evaluation

<!-- SCOPE: Partitioning/index/performance evaluation for sensor.sensorreadings ONLY. -->
<!-- DOC_KIND: reference -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read before changing sensor.sensorreadings indexes or considering partitioning. -->
<!-- SKIP_WHEN: Skip for schema questions unrelated to this table's storage/performance. -->
<!-- PRIMARY_SOURCES: live `dftdb-db` instance (EXPLAIN ANALYZE, pg_stat_user_indexes, pg_stat_user_tables) -->

**Date:** 2026-07-17
**Requested by:** XRFF-259 (repo evaluation follow-up)
**Verdict up front:** partitioning is not warranted yet, and may not be for years at the observed growth rate. Two unrelated, low-risk fixes are warranted now: drop a duplicate index, and run `ANALYZE`.

## 1. What actually queries this table

The only production consumer is the Unreal Engine VR client, via `public.ue_sensorreadings`
(`docker/volumes/db/init/10-baseline-schema.sql`):

```
GET /ue_sensorreadings?sensor_id=eq.<id>&order=timestamp.desc&limit=96
```

Which resolves to:

```sql
SELECT sr.sensor_reading_id, sr.sensor_id, st.sensor_type_name, s.unit,
       sr.timestamp, sr.value, sr.quality
FROM sensor.sensorreadings sr
JOIN sensor.sensors s ON sr.sensor_id = s.sensor_id
JOIN sensor.sensortypes st ON s.sensor_type_id = st.sensor_type_id
WHERE sr.sensor_id = <id>
ORDER BY sr.timestamp DESC
LIMIT 96
```

A single-sensor "most recent N readings" lookup (96 ≈ 24h at a 15-minute
sampling interval). There is no cross-sensor time-range query in the current
API surface — every read is scoped to one `sensor_id`.

## 2. Current performance (measured against the live instance)

`EXPLAIN (ANALYZE, BUFFERS)` on the exact query above, run against the
highest-volume sensor in the live dataset (sensor 1109, 64,625 readings):

```
Limit (actual time=0.835..1.096 rows=96 loops=1)
  -> Nested Loop (actual time=0.834..1.091 rows=96 loops=1)
      -> Index Scan Backward using sensorreadings_sensorid_timestamp_unique
         Index Cond: (sensor_id = 1109)
      -> Materialize
          -> Nested Loop (sensors + sensortypes lookups, index scans)
Planning Time: 0.746 ms
Execution Time: 1.148 ms
```

**~1.1ms end-to-end**, entirely via index scans, no sequential scans. This is
not a query that has a performance problem today, at 2.1M total rows.

## 3. Table size and growth

| Metric | Value |
|---|---|
| Row count | 2,100,805 |
| Date range | 2026-05-26 to 2026-07-10 (~45 days) |
| Table (heap) size | 169 MB |
| All indexes size | 278 MB |
| Total relation size | 447 MB |

Growth is **bursty, not steady** — it tracks manual sync runs
(`aquarius-connector`'s sync script), not a constant drip. Two known data
points:

- XRFF-100 (2026-02-15 to 2026-04-23, ~2 months): ~572,000 rows
- This evaluation (2026-05-26 to 2026-07-10, ~45 days): 2,100,805 rows total

The gap between 2026-04-23 and 2026-05-26, and the fact that the latest
timestamp (2026-07-10) is a week behind today (2026-07-17), both point to
syncs running on an ad-hoc manual cadence rather than a schedule. **Any
growth projection here is a rough order of magnitude, not a forecast** —
extrapolating the most recent burst (~47k rows/day) linearly would reach
20M rows in roughly a year, but the actual rate depends entirely on how
often someone runs a sync, which isn't currently automated.

## 4. A concrete finding: redundant index, stale statistics

Two things unrelated to partitioning are worth fixing regardless of the
partitioning decision, found while profiling this table:

**`idx_sensor_readings_sensor_timestamp` is a 108 MB dead index.** It's a
plain btree on `(sensor_id, timestamp DESC)` — functionally a duplicate of
`sensorreadings_sensorid_timestamp_unique` (the unique constraint backing
`(sensor_id, timestamp)`, which the planner already uses for backward scans
to satisfy `ORDER BY timestamp DESC`, as shown in the EXPLAIN output above).
`pg_stat_user_indexes` confirms **zero scans** since the stats were last
reset:

```
indexrelname                             | size   | idx_scan
idx_sensor_readings_sensor_timestamp     | 108 MB | 0
sensorreadings_sensorid_timestamp_unique | 64 MB  | 7
sensorreadings_pkey                      | 45 MB  | 0
idx_sensor_readings_timestamp            | 19 MB  | 2
idx_sensor_readings_sensor_id            | 16 MB  | 6
idx_sensor_readings_quality              | 13 MB  | 3
idx_sensor_readings_scenario             | 13 MB  | 3
```

Dropping `idx_sensor_readings_sensor_timestamp` frees 108 MB and removes one
of seven indexes maintained on every insert, with no read-path regression
(confirmed zero scans). `idx_sensor_readings_sensor_id` (single-column) is
also likely redundant with the composite unique index via the leftmost-prefix
rule, but it has nonzero scans — worth a closer look before dropping, not
an immediate call.

**`sensor.sensorreadings` has never been `ANALYZE`d.**
`last_analyze` / `last_autoanalyze` are both null. The planner is choosing
correctly right now mostly because the query shape (equality filter on the
leading column of a unique index) leaves little room to go wrong, not
because it has real statistics. Run `ANALYZE sensor.sensorreadings;` (or let
autovacuum's analyze threshold trigger it) so the planner has real
selectivity estimates as data volume grows.

Neither of these is part of the schema-migrations workflow (`supabase/migrations/`)
since they're operational maintenance, not schema changes — a `REINDEX`/`DROP INDEX`
and a manual/scheduled `ANALYZE` are enough.

## 5. Partitioning options (for when growth actually warrants it)

| Option | Cost | When it wins |
|---|---|---|
| **Do nothing** | None | Current query pattern (single-sensor, index-scan, LIMIT 96) doesn't care how big the table is in aggregate — partitioning only helps queries that can exclude whole partitions, and this one already excludes everything except one sensor's rows via the index. Right choice today. |
| **Native declarative partitioning** (by month/quarter on `timestamp`) | No new dependency; adds partition-maintenance tooling (create-ahead, drop-old) | If a future query pattern needs to scan/aggregate across a time range for many sensors at once (e.g. a dashboard "last 30 days across all sensors"), or if `VACUUM`/backup times on the single table become a problem |
| **TimescaleDB** | New extension dependency, operational learning curve | If continuous aggregates, compression, or retention policies become a real requirement — none are needed by the current API surface |

**Recommendation:** do nothing to the storage model now. Fix the two items
in §4 (low effort, measurable benefit, zero risk). Revisit partitioning if
either trigger below is hit:

- **Row count exceeds ~20M**, or
- **The `ue_sensorreadings` query's execution time exceeds ~50ms** (a ~40x
  regression from today's measurement) for a typical sensor, or
- **A new query pattern appears** that scans across sensors/time ranges
  rather than one sensor's most-recent rows (e.g. a fleet-wide dashboard) —
  this is the one thing that would actually benefit from partition pruning,
  and none of today's consumers do it.

## Related

- Sync cadence (currently manual) is the actual growth driver — see the
  [aquarius-connector](../../aquarius-connector) repo and the generic
  `scripts/import/ingest_sensor_data.py` CLI. If sync gets automated
  (e.g. a cron/scheduled job), re-run this evaluation — the "bursty, not
  steady" growth assumption above would no longer hold.
- XRFF-91 (*DT DB: Spatial indexes and query performance*) covered GIST
  indexes on geometry columns — canceled, unrelated to this table (no
  geometry columns on `sensorreadings`).

**Last Updated:** 2026-07-17
