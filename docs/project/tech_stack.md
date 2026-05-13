# Technology Stack: Digital Forest Twin Database

**Document Version:** 1.0
**Date:** 2026-05-11
**Status:** Active

<!-- SCOPE: Technology stack (specific versions, libraries, frameworks), Docker configuration summary, development tools, naming conventions ONLY. -->
<!-- DOC_KIND: reference -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need exact technologies, versions, tooling, or external service choices. -->
<!-- SKIP_WHEN: Skip when you only need business scope or runtime procedures. -->
<!-- PRIMARY_SOURCES: docker/docker-compose.yml, docker/.env.example, environment.yml, docker/volumes/functions/deno.json -->

<!-- DO NOT add here: API endpoints → docs/api-quick-reference.md, Database schema → docs/database-schema.md, Architecture patterns → architecture.md, Requirements → requirements.md, Deployment procedures → docs/project/deployment-guide.md -->

## Quick Navigation

- [Docs Hub](../README.md)
- [Requirements](requirements.md)
- [Architecture](architecture.md)
- [Deployment Guide](deployment-guide.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Lists the actual stack, versions, tooling, and rationale for all selected technologies. |
| Read When | You need exact framework, library, runtime, or tool choices and their versions. |
| Skip When | You only need workflow instructions or feature scope. |
| Canonical | Yes |
| Next Docs | [Architecture](architecture.md), [Deployment Guide](deployment-guide.md) |
| Primary Sources | `docker/docker-compose.yml`, `docker/.env.example`, `environment.yml` |

---

## 1. Introduction

### 1.1 Purpose

This document specifies the technology stack, service versions, client libraries, and development tools used in the Digital Forest Twin Database — a self-hosted Supabase/PostgreSQL infrastructure for forest research data management.

### 1.2 Scope

**In Scope:** All Docker services, PostgreSQL extensions, Python/R client libraries, development tools, and naming conventions.

**Out of Scope:** Infrastructure provisioning (see `docs/project/deployment-guide.md`), API contracts (see `docs/api-quick-reference.md`), database schema (see `docs/database-schema.md`).

---

## 2. Technology Stack

### 2.1 Core Services Overview

| Layer | Technology | Version | Rationale |
|-------|------------|---------|-----------|
| **Database** | PostgreSQL + PostGIS | 15 + PostGIS 3 | ACID compliance, native spatial types, mature ecosystem |
| **API Gateway** | Kong | 2.8.1 | JWT auth, CORS, routing, rate limiting — no custom middleware needed |
| **REST API** | PostgREST | v13.0.7 | Auto-generated REST from PostgreSQL schema; zero API maintenance |
| **Authentication** | GoTrue (Supabase Auth) | v2.182.1 | JWT issuance/verification, RLS integration, standard OAuth2 |
| **Realtime** | Supabase Realtime | latest (stack) | WebSocket subscriptions on DB changes via WAL |
| **Admin UI** | Supabase Studio | 2025.11.10 | Schema editor, data browser, SQL editor, auth management |
| **Connection Pooler** | Supavisor | latest (stack) | PostgreSQL connection pooling, port 6543 (transaction mode) |
| **Edge Functions** | Deno (TypeScript) | runtime in stack | Serverless sensor ingestion logic (ecosense-ingest) |
| **Containerization** | Docker Compose | v2+ | Single-host orchestration; Supabase official self-hosting method |

### 2.2 Python Client Libraries

Used by `scripts/import/`, `scripts/admin/`, and `scripts/utils/`:

| Library | Version | Purpose |
|---------|---------|---------|
| `supabase-py` | >=2.26 | Supabase REST and Auth client |
| `psycopg2` | >=2.9.9 | Direct PostgreSQL connection for bulk imports and admin ops |
| `SQLAlchemy` | >=2.0 | ORM/query builder for complex import logic |
| `pyproj` | latest | Coordinate reference system transformations (CRS reprojection) |
| `pygbif` | latest | GBIF API client for species name validation |
| `python-dotenv` | latest | `.env` file loading in scripts |
| `requests` | latest | HTTP client for Aquarius API calls |

**Runtime:** Python 3.12, conda environment `digital-twin` (see `environment.yml`)

### 2.3 R Client Libraries

Used by the `digital-twin-dashboard` project and ad-hoc analysis:

| Library | Version | Purpose |
|---------|---------|---------|
| `DBI` | R 4.3 | Database interface abstraction |
| `RPostgres` | latest | PostgreSQL driver for DBI |
| `dplyr` | latest | Data manipulation |
| `jsonlite` | latest | JSON parsing for REST API responses |

**Runtime:** R 4.3

### 2.4 Edge Function Dependencies

Located in `docker/volumes/functions/`:

| Module | File | Purpose |
|--------|------|---------|
| Retry logic | `_shared/retry.ts` | Exponential backoff with jitter for Aquarius API calls |
| Database client | `_shared/database.ts` | Supabase Deno client wrapper |
| Aquarius client | `_shared/aquarius.ts` | Aquarius API HTTP client |
| Validators | `_shared/validators.ts` | Input validation for sensor data |

**Runtime:** Deno (version managed by Supabase Functions container)

---

## 3. Docker Environment

### 3.1 Service Ports

| Service | Container Name | Port | Protocol |
|---------|---------------|------|---------|
| Kong API Gateway | dftdb-kong | 8000 (HTTP), 8443 (HTTPS) | TCP |
| Supabase Studio | dftdb-studio | 54323 | HTTP |
| PostgreSQL (direct) | dftdb-db | 5432 | TCP |
| Supavisor (pooled) | dftdb-supavisor | 6543 | TCP |

### 3.2 Docker Compose Configuration

Configuration file: `docker/docker-compose.yml`

Environment variables: `docker/.env` (git-ignored; template: `docker/.env.example`)

Key compose services: `studio`, `kong`, `auth` (GoTrue), `rest` (PostgREST), `realtime`, `meta`, `functions`, `db`, `supavisor`, `analytics`, `vector`

See `docker/docker-compose.yml` for full service definitions and health checks.

### 3.3 Volume Structure

| Volume Path | Purpose |
|-------------|---------|
| `docker/volumes/db/init/` | Numbered SQL migration files (10- to 31-) |
| `docker/volumes/api/kong.yml` | Kong declarative configuration |
| `docker/volumes/functions/` | Deno Edge Function source files |
| `docker/volumes/logs/vector.yml` | Log aggregation (Vector) |
| `docker/volumes/pooler/pooler.exs` | Supavisor configuration |

---

## 4. Development Tools

### 4.1 Required Tools

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| Docker Desktop | 24.0+ | Container runtime | https://docs.docker.com/get-docker/ |
| Docker Compose | v2+ | Compose orchestration | Included with Docker Desktop |
| Python | 3.12 | Script runtime | https://www.anaconda.com/ (via conda) |
| conda | latest | Environment management | https://docs.conda.io/ |
| Git | 2.40+ | Version control | https://git-scm.com/ |
| psql | 15+ | PostgreSQL CLI (optional, for direct admin) | https://www.postgresql.org/download/ |

### 4.2 Conda Environment Setup

Environment definition: `environment.yml` (project root)

```bash
conda env create -f environment.yml
conda activate digital-twin
```

### 4.3 Linters and Code Quality

| Tool | Language | Purpose | Config |
|------|----------|---------|--------|
| ruff | Python | Linting and formatting | `pyproject.toml` (if present) |
| EditorConfig | All | Consistent indentation/encoding | `.editorconfig` |

---

## 5. Naming Conventions

### 5.1 Database Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Schema names | snake_case | `shared`, `pointclouds`, `trees` |
| Table names | PascalCase (quoted in SQL) | `"Trees"`, `"SensorReadings"` |
| Column names | PascalCase (quoted in SQL) | `"TreeEntityID"`, `"SourceCRS"` |
| Primary keys | `<Entity>ID` SERIAL or UUID | `TreeID`, `SensorID`, `VariantID` |
| Foreign keys | `<Entity>ID` matching primary key | `SpeciesID`, `LocationID` |
| Geometry columns | `Position` (WGS84), `PositionOriginal` (source CRS) | `"Position"` geography type |
| Indexes | `idx_<table>_<column>` | `idx_trees_location` |
| Migration files | `NN-description.sql` (two-digit prefix) | `13-trees-schema.sql` |

### 5.2 Python Script Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Script files | `snake_case.py` | `sync_aquarius.py`, `import_trees.py` |
| Directory grouping | by function: `import/`, `admin/`, `utils/` | `scripts/import/` |

### 5.3 File/Directory Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Lookup CSVs | `snake_case.csv` | `species.csv`, `variant_types.csv` |
| Import data | descriptive + date | `ecosense_250911.csv` |
| Documentation | `kebab-case.md` or `UPPER_CASE.md` | `database-schema.md`, `ARCHITECTURE.md` |

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- Docker service version upgrade (update Section 2.1)
- New Python/R library added to `environment.yml` or import scripts
- New Deno Edge Function dependency added
- Port configuration changes in `docker-compose.yml`
- New development tool requirement

**Verification:**
- [x] Service versions match `docker/docker-compose.yml` image tags
- [x] Python library versions match `environment.yml`
- [x] Port table matches `docker/.env.example` and `docker-compose.yml`
- [x] All development tools have installation links
- [x] No placeholder values remain

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05-11 | ln-112-project-core-creator | Initial version |
