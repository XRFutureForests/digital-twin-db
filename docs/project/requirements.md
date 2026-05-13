# Requirements Specification: Digital Forest Twin Database

**Document Version:** 1.0
**Date:** 2026-05-11
**Status:** Active
**Standard Compliance:** ISO/IEC/IEEE 29148:2018

<!-- SCOPE: Functional requirements (FR-XXX-NNN format) with MoSCoW prioritization, acceptance criteria, constraints, assumptions, traceability ONLY. -->
<!-- DOC_KIND: explanation -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need product scope, functional requirements, or acceptance boundaries. -->
<!-- SKIP_WHEN: Skip when you only need implementation details, operations, or low-level schema facts. -->
<!-- PRIMARY_SOURCES: docs/README.md, docs/project/architecture.md, docs/project/tech_stack.md -->

<!-- DO NOT add here: Tech stack → tech_stack.md, Database schema → docs/database-schema.md, API → docs/api-quick-reference.md, Architecture → architecture.md -->

## Quick Navigation

- [Docs Hub](../README.md)
- [Architecture](architecture.md)
- [Tech Stack](tech_stack.md)
- [Database Schema](../database-schema.md)
- [API Reference](../api-quick-reference.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Defines functional scope, business expectations, and acceptance boundaries for the Digital Forest Twin Database. |
| Read When | You need feature scope, priorities, or requirement traceability. |
| Skip When | You only need implementation details, runtime procedures, or schema specifics. |
| Canonical | Yes |
| Next Docs | [Architecture](architecture.md), [Tech Stack](tech_stack.md) |
| Primary Sources | `docs/README.md`, `docs/project/architecture.md`, `docs/project/tech_stack.md` |

---

## 1. Introduction

### 1.1 Purpose

This document specifies the functional requirements for the Digital Forest Twin Database — a self-hosted Supabase/PostgreSQL infrastructure for forest research data management at the University of Freiburg (Eva Mayr-Stihl Stiftung funded).

### 1.2 Scope

**In Scope:** Multi-schema PostgreSQL database for spatial forest data (trees, LiDAR, sensors, environments, imagery), REST API access, GoTrue authentication, automated sensor data ingestion (Aquarius API), and Python/R client tooling.

**Out of Scope:** Unreal Engine VR rendering, R Shiny dashboard logic, field measurement instrumentation, upstream LiDAR processing pipelines (see `lidar-to-unreal`), and tree growth simulation (see `growpy`).

### 1.3 Intended Audience

- Forest data scientists and researchers (Uni Freiburg XR Future Forests Lab)
- Database administrators and DevOps engineers
- Python and R client developers
- System architects working on the broader XR Future Forests pipeline

### 1.4 References

- Architecture Document: [docs/project/architecture.md](architecture.md)
- Existing Architecture Overview: [docs/ARCHITECTURE.md](../ARCHITECTURE.md)
- Database Schema: [docs/database-schema.md](../database-schema.md)
- API Reference: [docs/api-quick-reference.md](../api-quick-reference.md)

---

## 2. Overall Description

### 2.1 Product Perspective

The Digital Forest Twin Database is the central data tier in a three-layer pipeline:

1. **Data collection** — LiDAR scanners, field measurements, Ecosense/Aquarius sensor networks
2. **This system** — stores, versions, and exposes forest data via REST API
3. **Consumers** — Unreal Engine VR (digital twin rendering), R Shiny dashboards, Python processing scripts

It is a self-hosted Supabase stack (Docker Compose, single host) with PostgreSQL 15 + PostGIS as the core. External integrations: Aquarius API (Uni Freiburg sensor data, VPN-gated), GBIF species validation API.

### 2.2 User Classes and Characteristics

| User Class | Description | Access Mode |
|------------|-------------|-------------|
| Researcher | Forest scientists reading and querying data | REST API (ANON_KEY), Supabase Studio |
| Data Engineer | Imports field data and runs processing scripts | Python scripts, SERVICE_ROLE_KEY |
| System Admin | Manages database, roles, schema migrations | psql, Supabase Studio, Docker |
| Downstream Client | Unreal Engine and R dashboard consuming processed data | REST API (ANON_KEY) |
| Automated Agent | Supabase Edge Functions ingesting sensor data | Edge Function (AQUARIUS_* credentials) |

### 2.3 Operating Environment

- **Server:** Single Docker host (Windows/Linux), conda environment `digital-twin`
- **Database:** PostgreSQL 15 + PostGIS 3, port 5432 (internal), 6543 (pooled via Supavisor)
- **API:** Kong gateway on ports 8000 (HTTP) / 8443 (HTTPS), PostgREST auto-generated REST
- **UI:** Supabase Studio at `http://localhost:54323`
- **Network dependency:** Aquarius API requires University of Freiburg VPN

---

## 3. Functional Requirements

### 3.1 Data Storage and Schema Management

| ID | Priority | Requirement | Acceptance Criteria |
|----|----------|-------------|---------------------|
| FR-DSM-001 | MUST | The system shall persist forest data in 6 domain schemas: `shared`, `pointclouds`, `trees`, `sensor`, `environments`, `imagery`. | All schemas created and accessible via PostgREST after `docker compose up`. |
| FR-DSM-002 | MUST | The system shall store all spatial data (tree positions, plot boundaries, sensor locations, point cloud extents) as PostGIS geometry types with CRS tracking. | Spatial columns use `geometry` type; `SourceCRS` column present on all spatial tables. |
| FR-DSM-003 | MUST | The system shall implement variant-based lineage tracking on point clouds, trees, and environments via `VariantID`, `ParentVariantID`, `VariantTypeID`, and `ScenarioID`. | Variant chain traversal query returns correct parent-child lineage. |
| FR-DSM-004 | MUST | The system shall maintain a field-level audit log (`shared.AuditLog_*` junction tables) recording changes with user and IP tracking. | Write operations produce audit log rows with `CreatedBy`, `CreatedAt`, and IP metadata. |
| FR-DSM-005 | MUST | The system shall support lookup/reference tables for species (GBIF-validated), soil types, climate zones, scenarios, and variant types loaded from CSV seed data. | Lookup tables populated after fresh `reset_database.py`; species validated against GBIF API. |
| FR-DSM-006 | SHOULD | The system shall store Deno Edge Function definitions for sensor ingestion within the Docker volume (`docker/volumes/functions/`). | `ecosense-ingest` function deploys and upserts sensor readings. |

### 3.2 REST API Access

| ID | Priority | Requirement | Acceptance Criteria |
|----|----------|-------------|---------------------|
| FR-API-001 | MUST | The system shall expose all 6 custom schemas via auto-generated PostgREST REST endpoints authenticated by JWT. | `GET http://localhost:8000/rest/v1/<schema>.<Table>` returns rows for valid JWT. |
| FR-API-002 | MUST | The system shall route all API traffic through Kong gateway with key-auth and CORS configured. | Unauthenticated requests return 401; CORS headers present on responses. |
| FR-API-003 | MUST | The system shall provide row-level security (RLS) policies so that `anon` role reads permitted public views and `service_role` has unrestricted access. | RLS policies verified via `scripts/utils/check_db_schema.py`. |
| FR-API-004 | SHOULD | The system shall expose public read-only views in the `public` schema for downstream consumers (Unreal Engine, R dashboard). | Views defined in `docker/volumes/db/init/24-public-api-views.sql` return data without `service_role` key. |
| FR-API-005 | COULD | The system shall support Supabase Realtime subscriptions on key tables for live dashboard updates. | Realtime container healthy; subscription test resolves. |

### 3.3 Authentication and Security

| ID | Priority | Requirement | Acceptance Criteria |
|----|----------|-------------|---------------------|
| FR-SEC-001 | MUST | The system shall authenticate all API consumers via JWT tokens signed with `JWT_SECRET`. | Invalid JWT returns 401; valid ANON_KEY and SERVICE_ROLE_KEY accepted. |
| FR-SEC-002 | MUST | The system shall store all secrets (passwords, JWT keys, API credentials) exclusively in `.env` (never committed to Git). | `.env` is git-ignored; `docker/.env.example` contains no real secret values. |
| FR-SEC-003 | MUST | The system shall provide a `generate_jwt.py` utility to create signed JWT tokens for client configuration. | `scripts/utils/generate_jwt.py` produces verifiable JWTs. |
| FR-SEC-004 | SHOULD | The system shall disable anonymous user signup by default (`ENABLE_ANONYMOUS_USERS=false`). | GoTrue config reflects anonymous users disabled. |

### 3.4 Sensor Data Ingestion

| ID | Priority | Requirement | Acceptance Criteria |
|----|----------|-------------|---------------------|
| FR-SDI-001 | MUST | The system shall import sensor readings from the Aquarius API (Uni Freiburg) via `sync_aquarius.py` and `sync_aquarius_direct.py`. | Script imports readings into `sensor.SensorReadings` without duplication on re-run. |
| FR-SDI-002 | MUST | The system shall link sensors to individual trees via `sensor.SensorTreeLinks` with `StartDate`/`EndDate` validity periods. | Link records persisted; queries joining `SensorTreeLinks` to `Trees` return correct results. |
| FR-SDI-003 | SHOULD | The system shall implement exponential-backoff retry for Aquarius API calls to handle transient failures. | `docker/volumes/functions/_shared/retry.ts` `withRetry` used in `ecosense-ingest`. |
| FR-SDI-004 | SHOULD | The system shall discover active sensors via `find_active_sensors.py` before sync. | Script returns sensor list matching `IsActive=true` rows in database. |

### 3.5 Tree Inventory Management

| ID | Priority | Requirement | Acceptance Criteria |
|----|----------|-------------|---------------------|
| FR-TIM-001 | MUST | The system shall store individual tree records with `TreeEntityID` (persistent UUID) to link the same physical tree across measurement campaigns. | Tree records with same `TreeEntityID` are queryable across multiple `CampaignID` values. |
| FR-TIM-002 | MUST | The system shall support multi-stem trees via the `trees.Stems` table with a foreign key to `trees.Trees`. | Multi-stem query returns all stems for a given `TreeID`. |
| FR-TIM-003 | MUST | The system shall import tree inventory from CSV files (Ecosense, Mathisle formats) via `scripts/import/import_trees.py`. | Import script upserts rows to `trees.Trees`; existing records updated, not duplicated. |
| FR-TIM-004 | SHOULD | The system shall track phenology observations, deadwood inventory, and ground vegetation per location and campaign. | Tables `PhenologyObservations`, `Deadwood`, `GroundVegetation` populated via import scripts. |
| FR-TIM-005 | SHOULD | The system shall validate species assignments against the GBIF API during import (`validate_species_gbif.py`). | Script flags unmatched species names with GBIF lookup results written to `species_gbif_validation.csv`. |

### 3.6 Administration and Operations

| ID | Priority | Requirement | Acceptance Criteria |
|----|----------|-------------|---------------------|
| FR-ADM-001 | MUST | The system shall provide a `reset_database.py` script that drops and recreates all schemas, runs migrations in order, and reloads seed data. | Fresh reset produces a fully functional empty database with all lookups loaded. |
| FR-ADM-002 | MUST | The system shall provide a `refresh_lookups.py` script to reload lookup tables from CSV without a full reset. | Lookup tables updated from `data/lookups/*.csv` without loss of non-lookup data. |
| FR-ADM-003 | MUST | The system shall be startable with `docker compose up -d` from the `docker/` directory. | All containers healthy within 60 seconds; Studio reachable at `http://localhost:54323`. |
| FR-ADM-004 | SHOULD | The system shall provide a `check_db_schema.py` utility to verify schema integrity post-migration. | Script exits 0 on healthy schema; non-zero with descriptive errors on mismatch. |

---

## 4. Acceptance Criteria (High-Level)

1. All MUST functional requirements implemented and passing verification steps listed above.
2. `docker compose up -d` brings all containers to healthy state within 60 seconds.
3. REST API accessible at `http://localhost:8000/rest/v1/` with valid JWT.
4. All 6 custom schemas present and exposed via PostgREST after fresh database reset.
5. Aquarius sync script imports sensor data without duplicates (idempotent re-run).
6. Traceability matrix links each requirement to a source migration file or script.

---

## 5. Constraints

### 5.1 Technical Constraints

| Constraint | Detail |
|------------|--------|
| PostgreSQL 15 | Migration SQL targets PG 15 features and syntax |
| PostGIS 3 | All spatial operations require PostGIS extension (`10-enable-postgis.sql`) |
| Single-host deployment | No horizontal scaling; single Docker Compose stack |
| Aquarius API requires VPN | Sensor sync only possible on University of Freiburg network |
| Supabase self-hosted | No Supabase Cloud — all services run locally via Docker |
| PascalCase table naming | SQL schema uses PascalCase identifiers (double-quoted in queries) |

### 5.2 Regulatory Constraints

- Research data must remain on Uni Freiburg infrastructure (no cloud egress of raw sensor or LiDAR data).
- GDPR applies to any personally identifiable researcher data stored in GoTrue auth tables.

---

## 6. Assumptions and Dependencies

### 6.1 Assumptions

1. Docker and Docker Compose are installed and operational on the host machine.
2. The operator has generated a valid `JWT_SECRET` and derived `ANON_KEY`/`SERVICE_ROLE_KEY` before first start.
3. Aquarius API credentials are obtained from the Ecosense project administrator.
4. University VPN is available when running sensor sync scripts.
5. Python 3.12 environment (`digital-twin` conda env) is activated before running scripts.

### 6.2 Dependencies

| Dependency | Purpose | Required |
|------------|---------|----------|
| Aquarius API (Uni Freiburg) | Sensor time-series ingestion | Yes (for sync scripts) |
| GBIF API | Species name validation | Yes (for import validation) |
| Docker Hub | Supabase service images on first pull | Yes |
| `data/lookups/*.csv` | Seed data for reference tables | Yes (for reset/refresh) |

---

## 7. Requirements Traceability

| Requirement ID | Source File | Notes |
|---------------|-------------|-------|
| FR-DSM-001 | `docker/volumes/db/init/11-17-*-schema.sql` | Schema creation migrations |
| FR-DSM-002 | `docker/volumes/db/init/10-enable-postgis.sql` | PostGIS extension enable |
| FR-DSM-003 | `docker/volumes/db/init/11-shared-schema.sql` | VariantID/ParentVariantID columns |
| FR-DSM-004 | `docker/volumes/db/init/21-audit-functions.sql` | Audit log trigger functions |
| FR-DSM-005 | `docker/volumes/db/init/30-load-lookup-tables.sql` | Lookup seed load |
| FR-DSM-006 | `docker/volumes/functions/ecosense-ingest/index.ts` | Edge Function definition |
| FR-API-001 | `docker/.env.example` (PGRST_DB_SCHEMAS) | PostgREST schema exposure |
| FR-API-002 | `docker/volumes/api/kong.yml` | Kong gateway configuration |
| FR-API-003 | `docker/volumes/db/init/20-rls-policies.sql` | RLS policy definitions |
| FR-API-004 | `docker/volumes/db/init/24-public-api-views.sql` | Public read-only views |
| FR-SEC-002 | `docker/.gitignore`, `docker/.env.example` | Secret hygiene |
| FR-SEC-003 | `scripts/utils/generate_jwt.py` | JWT generation utility |
| FR-SDI-001 | `scripts/import/sync_aquarius.py` | Aquarius sync (Python) |
| FR-SDI-003 | `docker/volumes/functions/_shared/retry.ts` | Exponential backoff retry |
| FR-TIM-001 | `docker/volumes/db/init/13-trees-schema.sql` | TreeEntityID column |
| FR-TIM-003 | `scripts/import/import_trees.py` | Tree CSV import |
| FR-ADM-001 | `scripts/admin/reset_database.py` | Full database reset |
| FR-ADM-002 | `scripts/admin/refresh_lookups.py` | Lookup table refresh |

---

## 8. Glossary

| Term | Definition |
|------|------------|
| Variant | A versioned copy of a data record (point cloud, tree, environment), linked to its parent via `ParentVariantID` |
| Campaign | A named data collection event (LiDAR flight, field inventory, sensor deployment) |
| EPSG | European Petroleum Survey Group — coordinate reference system identifier |
| PostGIS | PostgreSQL extension for spatial/geographic data types and functions |
| PostgREST | Middleware that auto-generates a REST API from a PostgreSQL schema |
| GoTrue | Supabase authentication service (JWT-based, also called Supabase Auth) |
| Kong | API gateway routing and authenticating all REST requests |
| Supavisor | Connection pooler for PostgreSQL (port 6543), replaces PgBouncer in Supabase stack |
| ANON_KEY | JWT signed for anonymous/read-only API access |
| SERVICE_ROLE_KEY | JWT with full superuser API access — must be kept secret |
| TreeEntityID | Persistent UUID identifying a physical tree across all measurement campaigns |
| Aquarius | University of Freiburg environmental sensor data API |

---

## 9. Appendices

### Appendix A: MoSCoW Prioritization Summary

- **MUST have:** 16 requirements
- **SHOULD have:** 9 requirements
- **COULD have:** 1 requirement
- **WON'T have (this release):** Horizontal scaling, multi-tenant auth, GraphQL API

### Appendix B: References

1. ISO/IEC/IEEE 29148:2018 — Systems and software engineering requirements
2. Supabase Self-Hosting Docs — https://supabase.com/docs/guides/self-hosting/docker
3. PostgREST Documentation — https://postgrest.org/
4. PostGIS Reference — https://postgis.net/documentation/
5. GBIF API — https://www.gbif.org/developer/summary

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- New functional requirements identified during development
- New schema migrations added
- New external integrations beyond Aquarius/GBIF
- Stakeholder feedback on requirement scope

**Verification:**
- [x] All FR-XXX-NNN requirements have acceptance criteria
- [x] All FR-XXX-NNN requirements have MoSCoW priority
- [x] Traceability matrix links requirements to source migrations and scripts
- [x] No placeholder values remain in this document

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-11 | ln-112-project-core-creator | Initial version |
