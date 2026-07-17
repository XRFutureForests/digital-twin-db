# Handover: DB Evaluation Findings → Linear Issues

**Date:** 2026-07-17
**From:** Claude Code session in WSL (`/home/max/git/digital-twin-db`)
**To:** Claude Code session on Windows (different workspace, same repo)
**Why the handover:** The Linear MCP server (`https://mcp.linear.app/sse`) fails to
connect from WSL. Max has Linear access on Windows. The database itself runs in
Docker **inside WSL** — anything requiring a live DB query must be done in a WSL
session, but everything below has already been verified against the live DB, so
the Windows session only needs Linear + file edits.

## Task state

A repo evaluation (docs vs. implementation consistency + design review) is
**complete** — findings below. Remaining work:

1. **Reconnect Linear MCP** (should work on Windows; run `/mcp` to check).
2. **Dedupe** the proposed issues against the existing Linear backlog
   (AGENTS.md rule: check for existing issues before creating new ones).
3. **File the issues** listed under "Proposed Linear issues" below.
4. Optionally start on the quick doc fixes (issues 1, 2, 7) — no DB access needed.
5. Delete this file once the issues are filed.

## Verified findings

### Ground vegetation: still in the schema, contrary to expectation

Max suspected `GroundVegetation` had been removed from the trees schema; it has
**not**. Verified present in both init SQL and the live database (0 rows):

- Table: `docker/volumes/db/init/13-trees-schema.sql:412` (`trees.GroundVegetation`)
- RLS: `docker/volumes/db/init/20-rls-policies.sql:627`
- Public API view + INSTEAD OF trigger: `docker/volumes/db/init/24-public-api-views.sql:95`
- Role-tier policies: `docker/volumes/db/init/29-role-tiers.sql:237`

`trees.Deadwood` and `trees.PhenologyObservations` are in the same state: defined,
exposed via API, **0 rows, no importer**, and none of the three have variant
tracking or audit logging (contradicting README's "All tables include variant
tracking, audit logging, RLS" claim). Decision needed: drop or implement.

### README/AGENTS.md inconsistencies (all verified against the file tree)

1. **Phantom script** `scripts/import/import_sensor_data.py` referenced at
   `README.md:197`, `README.md:223`, `data/README.md:162`. Real flow:
   `sync_aquarius.py` / `sync_aquarius_direct.py` → `enrich_sensor_metadata.py`
   → `link_sensors_to_trees.py`.
2. **10 broken doc links** in README.md and AGENTS.md:
   | Referenced (broken) | Actual |
   |---|---|
   | `docs/ARCHITECTURE.md` | `docs/architecture.md` |
   | `docs/database-schema.md` | `docs/database_schema.md` |
   | `docs/project/deployment-guide.md` | `docs/deployment-guide.md` |
   | `docs/project/troubleshooting.md` | `docs/troubleshooting.md` |
   | `docs/project/database-overview.md` | `docs/database-overview.md` |
   | `docs/documentation_standards.md` | (does not exist) |
   | `docs/principles.md` | (does not exist) |
   | `docs/supabase-introduction.md` | (does not exist) |
   | `docs/api-quick-reference.md` | (does not exist; closest: `docs/api_spec.md`) |
   | `docker/README.md` | `docs/docker/README.md` |
   Other files with stale refs: `docs/runbook.md`, `tests/README.md`,
   `data/templates/README.md`.
3. **Stale "Three-Layer Architecture" table** (README.md ~line 95): claims
   structure=10–16, functions=20–24, lookups=30–31. Actual init dir: structure
   10–19, functions 20–29, lookups 30–31, plus migrations 32–37 appended after.

### Aquarius coupling assessment

The **schema layer is already generic** — keep it. `22-aquarius-integration.sql`
(misleading filename, generic content) adds source-agnostic
`source`/`external_id`/`external_metadata` columns on `sensor.Sensors` plus two
provider-neutral RPCs: `public.bulk_upsert_sensors(jsonb)` and
`public.bulk_insert_readings(jsonb)`. These two RPCs are the clean ingestion
contract any external connector should use.

The coupling to extract lives in infrastructure/tooling:

- Edge function `docker/volumes/functions/ecosense-ingest/` +
  `docker/volumes/functions/_shared/aquarius.ts`, with
  `AQUARIUS_HOSTNAME/USERNAME/PASSWORD` wired into
  `docker/docker-compose.yml:316-318`. Ships a Freiburg-VPN-specific service
  with every deployment of a supposedly general DB.
- **Duplicate sync paths**: `scripts/import/sync_aquarius.py` (drives the edge
  function via Docker-network workarounds) and
  `scripts/import/sync_aquarius_direct.py` (431 lines reimplementing the same
  sync in Python for when the container can't reach the VPN). The direct Python
  path is the natural survivor; the edge function exists mainly to work around a
  networking problem it created.
- Further Aquarius/Ecosense-specific scripts: `scripts/import/find_active_sensors.py`,
  `scripts/import/enrich_sensor_metadata.py`, `scripts/utils/test_aquarius.py`,
  `scripts/utils/test_sensor_query.py`.

**Direction agreed with Max:** move Aquarius functionality to an external
connector module; this repo keeps only a generic sensor ingestion path
(CSV/JSON → the two bulk RPCs).

### Other design flaws (verified)

- **Migrations masquerading as init files**: `32-ecosense-sensor-tree-map.sql`
  through `37-scenario-variant-hierarchy.sql` rename/restructure objects created
  by files 11–19, so a fresh init replays history (file 36 even un-does location
  modeling that the Aquarius sync forced). Candidate fix: consolidate into a
  clean baseline or adopt Supabase CLI migrations.
- **`sensor.sensorreadings` at ~2.1M rows** (live count 2,100,805), plain table,
  unique `(sensor_id, timestamp)`. Partitioning/Timescale worth evaluating
  before it grows 10×.
- **Naming survived the snake_case restructure incompletely**: mixed-case
  columns `GroundVegetation.Layer`, `Height_cm`, `Notes`
  (`13-trees-schema.sql:412-424`); docs mix hyphens (`database-overview.md`)
  and underscores (`database_schema.md`).
- Live row counts for context: trees 6,526 · sensors 1,367 · readings 2.1M ·
  environments/imagery/pointclouds/groundvegetation/deadwood/phenology all 0.

## Proposed Linear issues

File these after deduping against the backlog. Suggested titles + bodies:

1. **docs: fix broken links in README.md and AGENTS.md** — bug, small.
   The 10 dead links in the table above, plus stale refs in `docs/runbook.md`,
   `tests/README.md`, `data/templates/README.md`. Decide hyphen-vs-underscore
   doc naming convention while at it.
2. **docs: fix sensor import instructions (phantom import_sensor_data.py)** —
   bug, small. `README.md:197,223`, `data/README.md:162`. Document the real
   script sequence.
3. **schema: decide fate of GroundVegetation / Deadwood / PhenologyObservations** —
   design decision. All empty, no importers, no variant/audit coverage. Either
   drop (table + RLS + API view + role tiers + docs) or bring up to standard.
4. **arch: extract Aquarius integration into external connector module** — large.
   Move `ecosense-ingest` edge function, `_shared/aquarius.ts`, and the Aquarius
   scripts out of this repo; remove `AQUARIUS_*` from `docker-compose.yml`;
   external module talks to the DB only via `bulk_upsert_sensors` /
   `bulk_insert_readings`. Depends on / supersedes issue 5's duplicate-path cleanup.
5. **feat: generic sensor data ingestion CLI** — feature. Provider-agnostic
   CSV/JSON → bulk RPCs, replacing the two duplicated Aquarius sync paths.
   Natural companion to issue 4.
6. **tech-debt: consolidate init files 32–37 into clean schema baseline** — or
   adopt Supabase CLI migration workflow so schema evolution stops accreting as
   numbered init files.
7. **docs: refresh README architecture claims** — layer table (10–16/20–24 is
   stale), the "all tables include variant tracking/audit" claim, and schema
   descriptions post-restructure (Location → Scenario → Variant hierarchy is
   absent from README).
8. **perf: evaluate partitioning for sensor.sensorreadings** — low priority,
   2.1M rows and growing.

## Environment notes for the Windows session

- The Docker stack (and thus the live DB) runs in WSL. From Windows, the REST
  API/Studio may still be reachable via localhost forwarding, but `docker exec`
  verification steps require a WSL shell.
- No working-tree changes were made in the WSL session besides this file.
