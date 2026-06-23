# Digital Forest Twin Database Documentation

Self-hosted Supabase/PostgreSQL backend for XR Future Forests digital twin research. University of Freiburg, funded by Eva Mayr-Stihl Stiftung.

---

## Quick Start Paths

### Get the database running locally

1. Install Docker Desktop and Git
2. Clone the repo and get `docker/.env` from Max (contains DB passwords and API keys)
3. `cd docker && docker compose up -d` — wait ~60 s for all containers to become healthy
4. Verify: open **http://localhost:54323** (Studio) or run `curl "http://localhost:8000/rest/v1/species" -H "apikey: <ANON_KEY>"`

Full instructions: [local-deployment-guide.md](local-deployment-guide.md)

---

### Load tree inventory data

Prepare a CSV using the 23-column template, then import:

```bash
conda activate digital-twin
python scripts/import/import_trees.py data/imports/your_trees.csv
```

The importer validates, deduplicates, and upserts to `trees.Trees` + `trees.Stems`. See [data/templates/DATA_PREPARATION_GUIDE.md](../data/templates/DATA_PREPARATION_GUIDE.md) for column specs and the coordinate transform steps.

---

### Add scenarios and growth variants

Scenarios (Current_Conditions, Forest_Fire, Thinning_2035, …) and VariantTypes (original, growth, post-disturbance) are defined in `data/lookups/` CSVs and loaded automatically on DB init.

To **add a new scenario**: insert a row in `data/lookups/scenarios.csv`, then run `python scripts/admin/reset_database.py` (wipes and reinitializes) or use the `refresh_lookup_functions` SQL functions to add it without a full reset.

To **create growth variants** from an existing baseline: copy the pattern in `scripts/seed/ecosense_growth_variants.sql` — it clones all trees from a baseline VariantType and assigns the new VariantTypeID.

Full model explanation and API query patterns: [variant-scenario-model.md](variant-scenario-model.md)

---

### Connect Unreal Engine

Set the API Base URL to `http://<HOST>:8000/rest/v1` and the ANON_KEY from `docker/.env`. The primary endpoint for tree placement is `/rest/v1/forest_state` — a flat, pre-joined view that includes lat/lon, species name, height, DBH, and scenario info in a single query.

Step-by-step Blueprint setup and PCG integration: [unreal-engine-integration.md](unreal-engine-integration.md)

---

### Run a SILVA growth simulation and write results back

1. Export the input view to R: `SELECT * FROM silva_input WHERE locationid = <N>` (or download as CSV from Studio)
2. Run SILVA in R — produces per-tree projections at discrete time steps
3. Write results back: `python scripts/silva/silva_writeback.py --input silva_output.csv --location-id <N>`
4. Query results in UE via `/rest/v1/growth_simulations?runid=eq.<UUID>&projectionyear=eq.2035`

Workflow detail, column mapping, and species codes: [silva-coupling.md](silva-coupling.md)
Growth simulations schema and API views: [growth-simulation-schema.md](growth-simulation-schema.md)

---

### Manage users and access

| Need | How |
|------|-----|
| Give a colleague read access | Share the `ANON_KEY` from `docker/.env` — no account needed |
| Give a colleague write access | Create a Studio account for them (see [data-access-guide.md](data-access-guide.md)) |
| Run import scripts as a collaborator | Share the `SERVICE_ROLE_KEY` — for trusted team members only |
| Log in programmatically | POST to `/auth/v1/token?grant_type=password` — see [data-access-guide.md](data-access-guide.md) |

Full permissions model and user creation steps: [data-access-guide.md](data-access-guide.md)

---

### Troubleshoot a broken stack

```bash
docker compose ps                    # see which containers are unhealthy
docker compose logs <container>      # inspect a specific container
python scripts/admin/reset_database.py  # full schema wipe + reinit (destroys data)
```

Common issues: [docs/docker/TROUBLESHOOTING.md](docker/TROUBLESHOOTING.md)
Full operations runbook: [project/runbook.md](project/runbook.md)

---

## Canonical Documentation

| Document | What it covers |
|---|---|
| [local-deployment-guide.md](local-deployment-guide.md) | Spin up a local stack in <30 min; step-by-step onboarding |
| [data-access-guide.md](data-access-guide.md) | Read/write access, user accounts, permissions model |
| [variant-scenario-model.md](variant-scenario-model.md) | Scenarios, VariantTypes, Variants — data model and API patterns |
| [unreal-engine-integration.md](unreal-engine-integration.md) | UE Blueprint setup, PCG, coordinate transform |
| [silva-coupling.md](silva-coupling.md) | SILVA R model workflow — export, run, write-back |
| [growth-simulation-schema.md](growth-simulation-schema.md) | GrowthSimulations table and API views |
| [project/api_spec.md](project/api_spec.md) | Complete PostgREST endpoint reference |
| [project/database_schema.md](project/database_schema.md) | Full schema, data dictionary, constraints, indexes |
| [project/runbook.md](project/runbook.md) | Operations: start/stop, reset, backups, health checks |
| [project/architecture.md](project/architecture.md) | arc42 architecture with C4 diagrams |
| [project/infrastructure.md](project/infrastructure.md) | Docker services, ports, environment variables |
| [project/tech_stack.md](project/tech_stack.md) | Technology versions and service inventory |
| [project/requirements.md](project/requirements.md) | Functional requirements (FR-XXX-NNN) with MoSCoW |
| [principles.md](principles.md) | Development principles and anti-patterns |
| [documentation_standards.md](documentation_standards.md) | Documentation rules for contributors |

---

## ADRs and Guides

| Document | What it covers |
|---|---|
| [reference/README.md](reference/README.md) | Reference hub: ADRs, guides |
| [reference/adrs/adr-001-postgresql-postgis.md](reference/adrs/adr-001-postgresql-postgis.md) | PostgreSQL+PostGIS selection |
| [reference/adrs/adr-002-supabase-auth.md](reference/adrs/adr-002-supabase-auth.md) | GoTrue JWT auth design |
| [reference/adrs/adr-003-self-hosted-supabase.md](reference/adrs/adr-003-self-hosted-supabase.md) | Self-hosted Supabase rationale |
| [reference/adrs/adr-004-kong-api-gateway.md](reference/adrs/adr-004-kong-api-gateway.md) | Kong declarative gateway routing |
| [reference/adrs/adr-005-supavisor-pooler.md](reference/adrs/adr-005-supavisor-pooler.md) | Supavisor connection pooler |
| [reference/guides/01-postgrest-schema-exposure-pattern.md](reference/guides/01-postgrest-schema-exposure-pattern.md) | PostgREST schema exposure patterns |

---

## Task Management

| Document | What it covers |
|---|---|
| [tasks/README.md](tasks/README.md) | Task workflow, Linear XRFF team integration |
| [tasks/kanban_board.md](tasks/kanban_board.md) | Live kanban board |
