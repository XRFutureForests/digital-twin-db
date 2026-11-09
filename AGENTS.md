# Forest Digital Twin Database

Self-hosted Supabase PostgreSQL database for digital forest twin research. 7 custom schemas (shared, point_clouds, trees, sensor, environments, imagery, forest_floor), PostGIS spatial extensions, REST API via PostgREST/Kong, auth via GoTrue. University of Freiburg XR Future Forests Lab (funded by Eva Mayr-Stihl Stiftung).


## Documentation Map

| Need | Read |
|------|------|
| What the database is, the variant model, the seven schemas | [README.md](README.md) |
| Start the stack, import data, query it, reset it | [RUNBOOK.md](RUNBOOK.md) |
| Schema dictionary, API spec, data access, deployment, troubleshooting | [docs/](docs/README.md) |
| Why the variant model, the CityGML alignment, provenance and scaling decisions | XR Future Forests Lab knowledge hub (`03-DATA-TIER/`) — **not** in this repo |
| Tasks | Linear |

Deep-dive documentation is deliberately not duplicated here. If you need to explain *why* an
approach was chosen, write it in the knowledge hub and link to it.

## Critical Rules

| Category | Rule | When to Apply |
|----------|------|---------------|
| Confirmation | Never commit or push without explicit user confirmation | Always |
| Scope | Modify only what the request requires — no adjacent cleanup | Always |
| Exit codes | An ingestion or connector script must exit non-zero if any record failed to write — an unattended run's exit code is the only signal the job runner has | Always |
| Secrets | Never commit `.env` or credentials; use `docker/.env` (gitignored) | Before any git operation |
| Schema changes | Add a new timestamped file under `supabase/migrations/`; never edit the snapshot or anything in `supabase/migrations/archive/` | Before schema edits |
| Docker | Run `docker compose up -d` from `docker/` (there is no compose file at the repo root) | Before all local dev |
| Task tracking | Check Linear for existing issues before creating new ones | Always |
| Language | Keep code and documentation in English | For all written artifacts |

## Project Structure

| Path | Purpose |
|------|---------|
| `docker/` | Docker Compose + all service configs (`.env` managed locally) |
| `supabase/migrations/` | The schema, as one chain: the 2026-11-09 snapshot and every migration after it. The `db` image runs it on a fresh init; `archive/` holds the history before the snapshot |
| `scripts/import/` | CSV/JSON data importers (trees, provider-agnostic sensor ingestion) |
| `scripts/admin/` | DB admin utilities: reset, refresh lookups, GBIF species validation |
| `scripts/runner/` | The job runner that drains `shared.processing_jobs`, with its systemd units |
| `scripts/server/` | dt.unr-only: NFS data dirs, nightly backup unit, account creation |
| `scripts/seed/` | Baseline-variant SQL (before the tree import, which names the variant) and default-row SQL (after it) |
| `scripts/provenance/` | Process Run Crate emitter (XRFF-407) |
| `scripts/utils/` | `db.py` connection helper, schema inspection, JWT generation, import-file tests |
| `docs/` | Reference: schema dictionary, API spec, deployment, troubleshooting (index in `docs/README.md`) |
| `CHANGELOG.md`, `CONTRIBUTING.md` | Kept because this repo releases to Zenodo (workspace decision 2026-09-15: only growpy, pylometree, digital-twin-db and dtm-to-unreal carry them) |
| `web/jobs/` | The job trigger page — one static file, served by the dashboard's nginx at `/jobs/` (`config.js` managed locally) |
| `web/portal/` | The portal — landing page, data entry, account management, API quick start; static, served by the dashboard's nginx at `/portal/` (`config.js` managed locally) |

## Schema Migrations

`supabase/migrations/` is the only schema chain. The `db` image (`docker/Dockerfile.db`) copies it into the init directory and runs `*.sql` in name order, after the `supabase/postgres` image's own platform migrations (named 2021… to 2025…). It holds:

- `10000000000001_extensions.sql`: PostGIS and the grants on `extensions`. The name sorts it before the platform migrations, so their later grants reach PostGIS too.
- `20261109120000_baseline_snapshot.sql`: the whole application schema (`shared`, `trees`, `sensor`, `point_clouds`, `environments`, `imagery`, `forest_floor`, `public`) plus the `dashboard_reader` role, cut on 2026-11-09 (XRFF-661).
- `20261109120001_reference_data.sql`: the rows a fresh init held then: lookups and the rows earlier migrations seeded.
- every later migration.

After all of them, `docker/volumes/db/refresh-lookups.sql` reloads the lookups from `data/lookups/*.csv`, which stay the source of truth for reference data. `archive/` holds the history before the snapshot. It is not copied into the image: `.dockerignore` excludes it, and the image runs only top-level files anyway.

**Adding a schema change:**
1. `npx supabase migration new <description>` — creates a new timestamped file under `supabase/migrations/`
2. Write the DDL (use `IF NOT EXISTS` / `IF EXISTS` guards for idempotency)
3. Apply it to the dev database as `supabase_admin`, then `NOTIFY pgrst, 'reload schema'` ([RUNBOOK.md §6](RUNBOOK.md#6-schema-changes-reset-and-rebuild)). Before committing, check that a fresh init from the rebuilt image (`docker compose build db`) produces the same schema as dev: `pg_dump --schema-only` both and diff
4. Regenerate the generated schema docs and commit them with the migration: `python scripts/utils/generate_schema_docs.py` rewrites `docs/database-dictionary.md` and `docs/database-erd.dbml`; `--check` exits 1 when either is stale

**Re-snapshotting**, when the chain after the snapshot grows long:
1. Fresh-init a throwaway container from the current image.
2. `pg_dump --schema-only` the eight schemas, and `--data-only --disable-triggers` every non-empty table in them.
3. Write these as a new timestamped snapshot pair, and move the older files to `archive/`.
4. Fresh-init a second container from the new image and compare the two in a full `pg_dump --schema-only`, `pg_dumpall --globals-only` and the data dump.

Three things a schema-scoped dump does not carry, all handled in the 2026-11-09 snapshot's header and footer:
- roles (`dashboard_reader`);
- the global default `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`;
- the fact that `supabase_admin`'s default privileges in `public` would grant anon and authenticated everything on each re-created object. The snapshot switches those defaults off while it loads.

Order, CHECK-constraint spelling and sequence positions may differ; nothing else may.

## Consumers that read base tables directly

Two repos deliberately reach past the published `public.*` API into the base
schemas. This is a decision, not drift.

| Repo | Reach | Why |
|---|---|---|
| [silva-connector](https://gitlab.uni-freiburg.de/xr-future-forests-lab/silva-connector) | 8 tables in `shared` / `trees`, **writes 4** | libpq in one transaction. The published views cannot express a variant-scoped read, and a half-written variant would read as a real forest state, so it needs the base tables and a transaction |
| [digital-twin-dashboard](https://gitlab.uni-freiburg.de/xr-future-forests-lab/digital-twin-dashboard) | 12 tables, **read-only** via RPostgres as `dashboard_reader` (row-level security applies: public datasets only) | Aggregates across schemas that no single view exposes |

Both are site-specific consumers of this specific deployment, which is what makes
it defensible. [aquarius-connector](https://gitlab.uni-freiburg.de/xr-future-forests-lab/aquarius-connector) is the counter-example
and stays that way: it goes through PostgREST and two source-agnostic RPCs, so it
could be pointed at a different database or replaced by another provider's
connector.

**The rule this creates:** any migration touching `shared`, `trees` or `sensor`
requires a grep of both consumer repos before it lands.

```bash
grep -rn "<table_or_column>" ../silva-connector/R ../silva-connector/scripts
grep -rn "<table_or_column>" ../digital-twin-dashboard/shared ../digital-twin-dashboard/apps
```

CI was removed workspace-wide on 2026-09-01, so nothing else will signal a
break: a renamed column reaches those repos as a runtime error in front of a
user, not as a failed build.

Do not "fix" this coupling by pushing either consumer onto the public views
without being asked. The views would have to grow to match, which trades a
documented dependency for an undocumented one.

## Tech Stack

| Component | Version / Detail |
|-----------|-----------------|
| Database | PostgreSQL 15 + PostGIS 3 |
| API Gateway | Kong 2.8.1 |
| REST API | PostgREST v13.0.7 (auto-generated from schema) |
| Auth | GoTrue v2.182.1 (Supabase Auth) |
| Studio UI | Supabase Studio 2025.11.10 |
| Connection pooler | Supavisor 2.7.4 (5432 session, 6543 transaction; user `postgres.<POOLER_TENANT_ID>`) |
| Python | 3.12 — supabase-py>=2.26, psycopg2>=2.9.9, SQLAlchemy>=2.0 |
| R | 4.3 — DBI, RPostgres |
| Infrastructure | Docker Compose (conda env: `digital-twin`) |

## Development Commands

| Task | Command |
|------|---------|
| Start all services (from `docker/`) | `docker compose up -d` |
| Stop all services (from `docker/`) | `docker compose down` |
| Open Studio UI | http://localhost:54323 |
| Query REST API | http://localhost:8000/rest/v1 |
| Reset and rebuild the database | the procedure in [RUNBOOK.md §6](RUNBOOK.md#6-schema-changes-reset-and-rebuild) |
| Regenerate schema docs | `python scripts/utils/generate_schema_docs.py` (`--check` exits 1 when stale) |

## Environment Variables

`docker/.env` (never commit) is created from `docker/.env.example`. The full list — secrets,
how to generate them, defaults (`POSTGRES_HOST=db`, `POSTGRES_PORT=5432`, `KONG_HTTP_PORT=8000`)
and server overrides — is [RUNBOOK.md §9](RUNBOOK.md#9-reference).

## Maintenance

**Update Triggers:**
- When root navigation or canonical document links change
- When core commands or ports change
- When critical project rules change
- When tech stack versions are updated

**Verification:**
- [ ] Links resolve to existing files
- [ ] Commands match current Docker Compose setup
- [ ] RUNBOOK §9 environment variable list matches `docker/.env.example`

**Last Updated:** 2026-11-09
