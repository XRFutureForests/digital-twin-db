# Digital Forest Twin Database

Self-hosted Supabase PostgreSQL database for digital forest twin research. 6 custom schemas (shared, pointclouds, trees, sensor, environments, imagery), PostGIS spatial extensions, REST API via PostgREST/Kong, auth via GoTrue. University of Freiburg XR Future Forests Lab (funded by Eva Mayr-Stihl Stiftung).

<!-- SCOPE: Canonical machine-facing entry point with repo map, critical rules, command overview, and links to detailed documentation ONLY. -->
<!-- DOC_KIND: index -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Start here when you need the project map, local rules, or the next canonical document. -->
<!-- SKIP_WHEN: Skip when you already know the exact target document or code area. -->
<!-- PRIMARY_SOURCES: AGENTS.md, docs/README.md -->

## Quick Navigation

| Need | Read |
|------|------|
| Architecture overview | [docs/architecture.md](docs/architecture.md) |
| Database schema | [docs/database-schema.md](docs/database-schema.md) |
| Deployment guide | [docs/deployment-guide.md](docs/deployment-guide.md) |
| Documentation map | [docs/README.md](docs/README.md) |
| Troubleshooting | [docs/troubleshooting.md](docs/troubleshooting.md) |

## Agent Entry

- Purpose: Canonical repo map and routing layer for agents.
- Read when: You need the project overview, local rules, or the next canonical doc.
- Skip when: You already know the exact file or document to inspect.
- Canonical: Yes.
- Read next: `docs/README.md`, then the relevant canonical doc for the task.
- Primary sources: `AGENTS.md`, `docs/README.md`.

## Critical Rules

| Category | Rule | When to Apply |
|----------|------|---------------|
| Confirmation | Never commit or push without explicit user confirmation | Always |
| Scope | Modify only what the request requires — no adjacent cleanup | Always |
| Secrets | Never commit `.env` or credentials; use `docker/.env` (gitignored) | Before any git operation |
| Schema changes | Add a new file under `supabase/migrations/`; never edit the baseline or old numbered init files | Before schema edits |
| Docker | Run `docker compose up -d` from `docker/` or the repo root | Before all local dev |
| Task tracking | Check Linear for existing issues before creating new ones | Always |
| Language | Keep code and documentation in English | For all written artifacts |

## Project Structure

| Path | Purpose |
|------|---------|
| `docker/` | Docker Compose + all service configs (`.env` managed locally) |
| `supabase/migrations/` | Schema change history (Supabase CLI) — source of truth for schema evolution |
| `scripts/import/` | CSV/JSON data importers (trees, provider-agnostic sensor ingestion) |
| `scripts/admin/` | DB admin utilities: reset, refresh lookups, JWT generation |
| `scripts/utils/` | DB schema inspection, import-file test utilities |
| `docs/` | Project documentation |

## Schema Migrations

Schema history lives in `supabase/migrations/` (Supabase CLI), not as numbered files under `docker/volumes/db/init/`. That directory's `10-baseline-schema.sql` is a point-in-time snapshot (2026-07-17) consolidating the former 10-29 and 32-37 init files, which had accreted into a replay-history problem — later files restructured objects earlier files created, so a fresh init replayed the project's history instead of producing today's schema directly. `30-load-lookup-tables.sql` and `31-refresh-lookup-functions.sql` are unchanged (CSV data loading, not schema).

**Adding a schema change:**
1. `npx supabase migration new <description>` — creates a new timestamped file under `supabase/migrations/`
2. Write the DDL (use `IF NOT EXISTS` / `IF EXISTS` guards for idempotency)
3. Apply and test against a local reset (see Critical Rules) before committing
4. If the change should also ship in the baked Docker image, mirror it into a new file under `docker/volumes/db/init/` (e.g. `11-<description>.sql`) — additive only, never restructuring `10-baseline-schema.sql`'s objects

When `supabase/migrations/` accumulates enough changes that the two sources drift, re-snapshot: `pg_dump --schema-only` the live DB (scoped to `shared`, `trees`, `sensor`, `pointclouds`, `environments`, `imagery`, `public` — not `extensions`/`storage`, which the base `supabase/postgres` image already owns), verify it structurally matches the live DB (table/view/function/policy counts, lookup row counts) via a throwaway container, then replace the baseline file with the new snapshot.

## Tech Stack

| Component | Version / Detail |
|-----------|-----------------|
| Database | PostgreSQL 15 + PostGIS 3 |
| API Gateway | Kong 2.8.1 |
| REST API | PostgREST v13.0.7 (auto-generated from schema) |
| Auth | GoTrue v2.182.1 (Supabase Auth) |
| Studio UI | Supabase Studio 2025.11.10 |
| Connection pooler | Supavisor (port 6543) |
| Python | 3.12 — supabase-py>=2.26, psycopg2>=2.9.9, SQLAlchemy>=2.0 |
| R | 4.3 — DBI, RPostgres |
| Infrastructure | Docker Compose (conda env: `digital-twin`) |

## Development Commands

| Task | Command |
|------|---------|
| Start all services | `docker compose up -d` |
| Stop all services | `docker compose down` |
| Open Studio UI | http://localhost:54323 |
| Query REST API | http://localhost:8000/rest/v1 |
| Reset database | `python scripts/admin/reset_database.py` |

## Environment Variables

Required in `docker/.env` (never commit):

| Variable | Purpose |
|----------|---------|
| `POSTGRES_PASSWORD` | PostgreSQL superuser password |
| `JWT_SECRET` | JWT signing secret (GoTrue + PostgREST) |
| `ANON_KEY` | Supabase anonymous access key |
| `SERVICE_ROLE_KEY` | Supabase service role key |
| `DASHBOARD_USERNAME` | Studio login username |
| `DASHBOARD_PASSWORD` | Studio login password |
| `POSTGRES_HOST` | PostgreSQL host (default: `localhost`) |
| `POSTGRES_PORT` | PostgreSQL port (default: `5432`) |
| `KONG_HTTP_PORT` | Kong API gateway port (default: `8000`) |

## Maintenance

**Update Triggers:**
- When root navigation or canonical document links change
- When core commands or ports change
- When critical project rules change
- When tech stack versions are updated

**Verification:**
- [ ] Links resolve to existing files
- [ ] Commands match current Docker Compose setup
- [ ] Environment variable list matches `docker/.env.example` or deployment guide

**Last Updated:** 2026-07-17
