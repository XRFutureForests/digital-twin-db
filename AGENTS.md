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
| Architecture overview | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Database schema | [docs/database-schema.md](docs/database-schema.md) |
| Deployment guide | [docs/project/deployment-guide.md](docs/project/deployment-guide.md) |
| Documentation map | [docs/README.md](docs/README.md) |
| Documentation standards | [docs/documentation_standards.md](docs/documentation_standards.md) |
| Principles | [docs/principles.md](docs/principles.md) |
| Troubleshooting | [docs/project/troubleshooting.md](docs/project/troubleshooting.md) |

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
| Schema changes | Test migration scripts in a local reset before applying | Before schema edits |
| Docker | Run `docker compose up -d` from `docker/` or the repo root | Before all local dev |
| Task tracking | Check Linear for existing issues before creating new ones | Always |
| Language | Keep code and documentation in English | For all written artifacts |

## Project Structure

| Path | Purpose |
|------|---------|
| `docker/` | Docker Compose + all service configs (`.env` managed locally) |
| `scripts/import/` | CSV data importers, Aquarius API sync |
| `scripts/admin/` | DB admin utilities: reset, refresh lookups, JWT generation |
| `scripts/utils/` | DB inspection, sensor query, test utilities |
| `docs/` | Project documentation |

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

**Last Updated:** 2026-05-11
