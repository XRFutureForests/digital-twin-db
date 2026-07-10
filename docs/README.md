# Digital Forest Twin Database Documentation

Self-hosted Supabase/PostgreSQL backend for XR Future Forests digital twin research. University of Freiburg, funded by Eva Mayr-Stihl Stiftung.

> **New here?** Start with the **[Database Overview](database-overview.md)** — the schema architecture diagram, the six schemas and their tables, how they connect, and the key design patterns (variant lineage, audit trail, PostGIS, auto-generated REST API).

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

Scenarios are **location-scoped management regimes** in a strict Location → Scenario → Variant hierarchy: each site (`ecosense`, `mathisle`) owns its scenarios, and each scenario owns its baseline. They are **created per-site by the growth-variant seed scripts**, not loaded from a global CSV. VariantTypes (original, simulated_growth, …) are loaded from `data/lookups/variant_types.csv` on init.

To **add a scenario + its variants**: copy the pattern in `scripts/seed/ecosense_growth_variants.sql` — it creates the location-scoped scenario, assigns the baseline trees to `baseline_2025`, and chains growth variants (`growth_2035`, `growth_2045`) with `parent_variant_id` lineage. See [variant-scenario-model.md](variant-scenario-model.md).

Full model explanation and API query patterns: [variant-scenario-model.md](variant-scenario-model.md)

---

### Connect Unreal Engine

Set the API Base URL to `http://<HOST>:8000/rest/v1` and the ANON_KEY from `docker/.env`. The primary endpoint for tree placement is `/rest/v1/ue_trees` — a flat, pre-joined view that includes lat/lon, species name, height, DBH, and scenario info in a single query.

Step-by-step Blueprint setup, flat SQL view contracts, and PCG integration live in the XR Future Forests Lab knowledge hub → `05-PRESENTATION-TIER/data-fetcher-guide` (Unreal ↔ Digital Twin DB Integration Guide).

---

### Run a SILVA growth simulation and write results back

1. Export the input view to R: `SELECT * FROM silva_input WHERE location_id = <N>` (or download as CSV from Studio)
2. Run SILVA in R — produces per-tree projections at discrete time steps
3. Write results back: `python scripts/silva/silva_writeback.py --input silva_output.csv --location-id <N>`
4. Query results in UE via `/rest/v1/growth_simulations?run_id=eq.<UUID>&projection_year=eq.2035`

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
Full operations runbook: [runbook.md](runbook.md)

---

## Canonical Documentation

| Document | What it covers |
|---|---|
| [database-overview.md](database-overview.md) | **Start here** — schema architecture, the six schemas, tables, design patterns, audit trail, access patterns |
| [architecture.md](architecture.md) | System architecture (arc42) with C4 diagrams and runtime scenarios |
| [database_schema.md](database_schema.md) | Full schema, data dictionary, constraints, indexes |
| [api_spec.md](api_spec.md) | Complete PostgREST endpoint reference |
| [database-erd.dbml](database-erd.dbml) | Entity-relationship model (dbdiagram.io source) |
| [local-deployment-guide.md](local-deployment-guide.md) | Spin up a local stack in <30 min; step-by-step onboarding |
| [data-access-guide.md](data-access-guide.md) | Read/write access, user accounts, permissions model |
| [variant-scenario-model.md](variant-scenario-model.md) | Scenarios, VariantTypes, Variants — data model and API patterns |
| [silva-coupling.md](silva-coupling.md) | SILVA R model workflow — export, run, write-back |
| [growth-simulation-schema.md](growth-simulation-schema.md) | GrowthSimulations table and API views |
| [species-naming-audit.md](species-naming-audit.md) | Species naming conventions and audit notes |
| [runbook.md](runbook.md) | Operations: start/stop, reset, backups, health checks |
| [deployment-guide.md](deployment-guide.md) | Production deployment guidance |
| [troubleshooting.md](troubleshooting.md) | Common issues and resolutions |
| [docker/README.md](docker/README.md) | Docker stack: services, ports, environment variables |