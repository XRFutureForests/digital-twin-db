# Forest Digital Twin Database

Self-hosted Supabase PostgreSQL database for digital forest twin research. 7 custom schemas (shared, pointclouds, trees, sensor, environments, imagery, forest_floor), PostGIS spatial extensions, REST API via PostgREST/Kong, auth via GoTrue. University of Freiburg XR Future Forests Lab (funded by Eva Mayr-Stihl Stiftung).


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
| Schema changes | Add a new file under `supabase/migrations/`; never edit the baseline or old numbered init files | Before schema edits |
| Docker | Run `docker compose up -d` from `docker/` (there is no compose file at the repo root) | Before all local dev |
| Task tracking | Check Linear for existing issues before creating new ones | Always |
| Language | Keep code and documentation in English | For all written artifacts |

## Project Structure

| Path | Purpose |
|------|---------|
| `docker/` | Docker Compose + all service configs (`.env` managed locally) |
| `supabase/migrations/` | Schema change history (Supabase CLI) — source of truth for schema evolution |
| `scripts/import/` | CSV/JSON data importers (trees, provider-agnostic sensor ingestion) |
| `scripts/admin/` | DB admin utilities: reset, refresh lookups, GBIF species validation |
| `scripts/runner/` | The job runner that drains `shared.processing_jobs`, with its systemd units |
| `scripts/server/` | dt.unr-only: NFS data dirs, nightly backup unit, account creation |
| `scripts/seed/` | Baseline-variant and default-row SQL applied after import |
| `scripts/provenance/` | Process Run Crate emitter (XRFF-407) |
| `scripts/utils/` | `db.py` connection helper, schema inspection, JWT generation, import-file tests |
| `docs/` | Reference: schema dictionary, API spec, deployment, troubleshooting (index in `docs/README.md`) |
| `CHANGELOG.md`, `CONTRIBUTING.md` | Kept because this repo releases to Zenodo (workspace decision 2026-09-15: only growpy, pylometree, digital-twin-db and dtm-to-unreal carry them) |
| `web/jobs/` | The job trigger page — one static file, served by the dashboard's nginx at `/jobs/` (`config.js` managed locally) |
| `web/portal/` | The portal — landing page, data entry, account management, API quick start; static, served by the dashboard's nginx at `/portal/` (`config.js` managed locally) |

## Schema Migrations

Schema history lives in `supabase/migrations/` (Supabase CLI). Every migration is also mirrored, additively, into the next numbered file under `docker/volumes/db/init/` (currently `11-` to `70-`), because the `db` image bakes that directory and a fresh init must produce today's schema. That directory's `10-baseline-schema.sql` is a point-in-time snapshot (2026-07-17) consolidating the former 10-29 and 32-37 init files, which had accreted into a replay-history problem — later files restructured objects earlier files created, so a fresh init replayed the project's history instead of producing today's schema directly. `30-load-lookup-tables.sql` and `31-refresh-lookup-functions.sql` are unchanged (CSV data loading, not schema).

**Adding a schema change:**
1. `npx supabase migration new <description>` — creates a new timestamped file under `supabase/migrations/`
2. Write the DDL (use `IF NOT EXISTS` / `IF EXISTS` guards for idempotency)
3. Mirror it into the next numbered file under `docker/volumes/db/init/` (e.g. `71-<description>.sql`) — additive only, never restructuring `10-baseline-schema.sql`'s objects
4. Apply it to the dev database as `supabase_admin`, then `NOTIFY pgrst, 'reload schema'` ([RUNBOOK.md §6](RUNBOOK.md#6-schema-changes-reset-and-rebuild)); before committing, check that a fresh init from the rebuilt image (`docker compose build db`) produces the same schema
5. Regenerate the generated schema docs and commit them with the migration: `python scripts/utils/generate_schema_docs.py` rewrites `docs/database-dictionary.md` and `docs/database-erd.dbml`; `--check` exits 1 when either is stale

When `supabase/migrations/` accumulates enough changes that the two sources drift, re-snapshot: `pg_dump --schema-only` the live DB (scoped to `shared`, `trees`, `sensor`, `pointclouds`, `environments`, `imagery`, `forest_floor`, `public` — not `extensions`/`storage`, which the base `supabase/postgres` image already owns), verify it structurally matches the live DB (table/view/function/policy counts, lookup row counts) via a throwaway container, then replace the baseline file with the new snapshot. Keep this schema list in sync with the `CREATE SCHEMA` statements in the init files — omitting one silently drops it from the new baseline.

## Consumers that read base tables directly

Two repos deliberately reach past the published `public.*` API into the base
schemas. This is a decision, not drift.

| Repo | Reach | Why |
|---|---|---|
| [silva-connector](https://gitlab.uni-freiburg.de/xr-future-forests-lab/silva-connector) | 8 tables in `shared` / `trees`, **writes 4** | libpq in one transaction. The published views cannot express a variant-scoped read, and a half-written variant would read as a real forest state, so it needs the base tables and a transaction |
| [digital-twin-dashboard](https://gitlab.uni-freiburg.de/xr-future-forests-lab/digital-twin-dashboard) | 12 tables, **read-only** via RPostgres | Aggregates across schemas that no single view exposes |

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
| Reset and rebuild the database | the procedure in [RUNBOOK.md §6](RUNBOOK.md#6-schema-changes-reset-and-rebuild) (`scripts/admin/reset_database.py` skips the image rebuild — do not use it) |
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

**Last Updated:** 2026-10-30
