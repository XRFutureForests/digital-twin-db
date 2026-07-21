# Operations Runbook: Digital Forest Twin Database

**Document Version:** 1.0
**Date:** 2026-05-11
**Status:** Active

<!-- DOC_KIND: how-to -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need setup, deploy, restart, troubleshoot, or recovery procedures. -->
<!-- SKIP_WHEN: Skip when you only need static infrastructure inventory or architectural rationale. -->
<!-- PRIMARY_SOURCES: docker/docker-compose.yml, docker/.env.example, scripts/, docs/project/infrastructure.md -->

<!-- SCOPE: ALL operational procedures (local development setup, Docker commands, environment variables, testing commands, build/deployment, production operations, troubleshooting, logs, restart procedures) ONLY. -->
<!-- DO NOT add here: Infrastructure inventory → infrastructure.md, Architecture patterns → architecture.md, Tech stack versions → tech_stack.md, Database schema → database-schema.md, API endpoints → api-spec.md -->

## Quick Navigation

- [Docs Hub](README.md)
- [Architecture](architecture.md)
- [Docker Troubleshooting](docker/TROUBLESHOOTING.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Provides executable operational procedures for local development work. |
| Read When | You need commands, setup steps, troubleshooting, or recovery actions. |
| Skip When | You only need static topology or design rationale. |
| Canonical | Yes |
| Next Docs | [Architecture](architecture.md), [Docker Troubleshooting](docker/TROUBLESHOOTING.md) |
| Primary Sources | `docker/docker-compose.yml`, `docker/.env.example`, `scripts/` |

---

## 1. Overview

### 1.1 Purpose

This runbook provides step-by-step operational procedures for the Digital Forest Twin Database — a self-hosted Supabase stack (PostgreSQL 15 + PostGIS 3) that serves as the data backend for the XR Future Forests Lab digital twin pipeline.

### 1.2 Quick Links

- Architecture overview: [architecture.md](architecture.md)
- Database schema: [database-schema.md](database-schema.md)
- Docker changelog: [docker/CHANGELOG.md](docker/CHANGELOG.md)

### 1.3 Key Contacts

No contacts are defined in CODEOWNERS or package.json. See the University of Freiburg XR Future Forests Lab (funded by Eva Mayr-Stihl Stiftung) for ownership information.

---

## 2. Prerequisites

### 2.1 Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| Docker | 20.10+ | https://docs.docker.com/get-docker/ |
| Docker Compose | v2.0+ | Included with Docker Desktop |
| conda | Any | https://docs.conda.io/en/latest/miniconda.html |
| Python | 3.12 | via conda env `digital-twin` (`environment.yml`) |
| Git | 2.40+ | https://git-scm.com/ |

### 2.2 Access Requirements

- Repository read access (`d:\Git\digital-twin-db` or GitHub org `XRFutureForests`)
- Aquarius sensor API credentials (University of Freiburg VPN required) — stored in `docker/.env` under `AQUARIUS_*`

### 2.3 Environment Variables

See [Appendix A: Environment Variables Reference](#appendix-a-environment-variables-reference) for the full reference.

---

## 3. Local Development

### 3.1 Initial Setup

```bash
# 1. Create and activate conda environment
conda env create -f environment.yml
conda activate digital-twin

# 2. Navigate to docker directory
cd docker

# 3. Copy environment template
cp .env.example .env

# 4. Edit .env — fill in all CHANGE_ME values
# Required secrets: POSTGRES_PASSWORD, JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY,
# DASHBOARD_PASSWORD, SECRET_KEY_BASE, VAULT_ENC_KEY, PG_META_CRYPTO_KEY,
# LOGFLARE_PUBLIC_ACCESS_TOKEN, LOGFLARE_PRIVATE_ACCESS_TOKEN
# See scripts/utils/generate_jwt.py to generate ANON_KEY and SERVICE_ROLE_KEY.

# 5. Start all services
docker compose up -d

# 6. Verify services are healthy
docker compose ps
```

**Expected result:** All containers show `Up` or `healthy` status. Supabase Studio available at http://localhost:54323.

### 3.2 Docker Commands

**Start all services:**
```bash
cd docker && docker compose up -d
```

**Stop all services (keep volumes):**
```bash
docker compose down
```

**Destroy everything including volumes (destructive):**
```bash
docker compose down -v --remove-orphans
```

**View logs:**
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f db
docker compose logs -f studio

# Last 100 lines
docker compose logs --tail 100 kong
```

**Restart a specific service:**
```bash
docker compose restart studio
docker compose restart db
```

**Check service health:**
```bash
docker compose ps
```

### 3.3 Database Operations

**Open a database shell:**
```bash
docker compose exec db psql -U postgres -d postgres
```

**Reset database (destructive — drops and recreates all schemas):**
```bash
python scripts/admin/reset_database.py
```

**Refresh lookup tables (species, soil types, etc.):**
```bash
python scripts/admin/refresh_lookups.py
```

**Verify schema structure:**
```bash
python scripts/utils/check_db_schema.py
```

**Generate JWT tokens (ANON_KEY / SERVICE_ROLE_KEY):**
```bash
python scripts/utils/generate_jwt.py
```

### 3.4 Data Import

Individual steps (run from the repo root, `conda activate digital-twin`):

**Import tree measurements** (one CSV per site):
```bash
python scripts/import/import_trees.py data/imports/ecosense_trees_import.csv
python scripts/import/import_trees.py data/imports/mathisle_trees_import.csv
```

**Sync sensors + readings (any provider):**
```bash
python scripts/import/ingest_sensor_data.py sensors data/imports/my_sensors.csv
python scripts/import/ingest_sensor_data.py readings data/imports/my_readings.json
```
For Aquarius specifically (requires university VPN), see the [aquarius-connector](../../aquarius-connector) repo.

**Link sensors to trees:**
```bash
python scripts/import/link_sensors_to_trees.py      # backfills trees.sensor_ref + sensor_tree_links
```

### 3.4.1 Full rebuild from scratch (reproducible)

Wipes the DB and rebuilds everything from committed sources. The DB image
**bakes** `docker/volumes/db/init/`, so the image must be rebuilt to pick up any
schema change — a bare `up -d` reuses the old baked SQL.

```bash
# 0. (optional but recommended) back up first
docker exec dftdb-db pg_dump -U postgres -d postgres -Fc -f /tmp/backup.dump
docker cp dftdb-db:/tmp/backup.dump ./backup.dump

# 1. Wipe volumes, rebuild the baked image, boot (init scripts 10, 30, 31 run on first boot)
cd docker
docker compose down -v --remove-orphans
docker compose build db
docker compose up -d
cd ..

# 2. Trees (measured inventory)
python scripts/import/import_trees.py data/imports/ecosense_trees_import.csv
python scripts/import/import_trees.py data/imports/mathisle_trees_import.csv

# 3. Growth variants (simulated_growth trees, cloned from the baseline)
docker exec -i dftdb-db psql -U supabase_admin -d postgres < scripts/seed/ecosense_growth_variants.sql
docker exec -i dftdb-db psql -U supabase_admin -d postgres < scripts/seed/mathisle_growth_variants.sql

# 4. Sensors + readings (any provider; for Aquarius see the aquarius-connector repo), then link
python scripts/import/ingest_sensor_data.py sensors data/imports/my_sensors.csv
python scripts/import/ingest_sensor_data.py readings data/imports/my_readings.json
python scripts/import/link_sensors_to_trees.py
```

> Schema-owning DDL must run as `supabase_admin` (the `postgres` role is not the
> table owner); the seed `psql` commands above use it. The Python importers
> connect as `postgres` for DML, which is fine.

---

## 4. Build

The database image is custom-built to bake SQL init scripts directly into the image, avoiding WSL bind-mount path issues on Windows.

**Rebuild the database image after schema changes:**
```bash
cd docker && docker compose build db
docker compose up -d db
```

**Force full rebuild of all images:**
```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

---

## 5. Production Operations

This stack is currently deployed for local development only. For production deployment guidance see [`docs/deployment-guide.md`](deployment-guide.md).

### 5.1 Health Checks

**Studio UI:**
```
http://localhost:54323
```

**API gateway:**
```bash
curl http://localhost:8000/rest/v1/ -H "apikey: <ANON_KEY>"
```

**Database direct:**
```bash
docker compose exec db pg_isready -U postgres
```

**All service status:**
```bash
docker compose ps
```

### 5.2 Monitoring & Logs

**View real-time logs (all services):**
```bash
docker compose logs -f
```

**Filter for errors:**
```bash
docker compose logs --tail 500 db | grep -i error
docker compose logs --tail 500 kong | grep -i error
```

**Save logs to file:**
```bash
docker compose logs --no-color > logs-$(date +%Y%m%d).log
```

**Resource usage:**
```bash
docker stats
```

### 5.3 Database Backup

**Manual backup via pg_dump:**
```bash
docker compose exec db pg_dump -U postgres postgres > backup-$(date +%Y%m%d-%H%M%S).sql
```

**Restore from backup:**
```bash
cat backup-20260101-120000.sql | docker compose exec -T db psql -U postgres postgres
```

---

## 6. Troubleshooting

### 6.1 Common Issues

#### Studio / Kong not reachable

**Symptoms:** Browser cannot connect to http://localhost:54323 or http://localhost:8000.

**Diagnosis:**
```bash
docker compose ps
docker compose logs --tail 50 analytics  # studio/kong depend on analytics
docker compose logs --tail 50 kong
```

**Resolution:**
```bash
# analytics must be healthy before studio/kong start
docker compose restart analytics
# wait ~15 seconds, then:
docker compose restart studio kong
```

---

#### Port already in use

**Symptoms:** `Error starting userland proxy: listen tcp 0.0.0.0:5432: bind: address already in use`

**Diagnosis:**
```bash
# Windows
netstat -ano | findstr :5432
# Linux
ss -tlnp | grep 5432
```

**Resolution:** Stop the conflicting process or change the port mapping in `docker/.env` (`POSTGRES_PORT`, `KONG_HTTP_PORT`, etc.) before restarting.

---

#### Database init scripts not applied

**Symptoms:** Missing tables or schemas after fresh start.

**Cause:** The `db` image uses baked-in init scripts. If scripts changed, the image must be rebuilt.

**Resolution:**
```bash
docker compose down -v --remove-orphans
docker compose build --no-cache db
docker compose up -d
```

---

#### WSL bind-mount path errors (Windows)

**Symptoms:** Volumes fail after Docker Desktop restart; paths like `/run/desktop/mnt/host/wsl/...` appear stale.

**Resolution:** Named volumes (`db-data`, `db-config`) are used for all persistent DB state. File mounts (`kong.yml`, `vector.yml`, `pooler.exs`) use directory mounts to avoid stale path resolution. Restart Docker Desktop and run `docker compose up -d`.

---

#### Out of disk space

**Symptoms:** `Error: no space left on device` in container logs.

**Diagnosis:**
```bash
docker system df
df -h
```

**Resolution:**
```bash
# Remove unused images, containers, networks
docker system prune -a

# Remove all volumes (destructive — loses DB data)
docker compose down -v --remove-orphans
```

---

#### Aquarius sync fails

**Symptoms:** the [aquarius-connector](../../aquarius-connector) repo's sync reports connection errors.

**Cause:** University of Freiburg VPN is not connected, or `AQUARIUS_*` variables in that repo's `.env` are not set.

**Resolution:** Connect to the university VPN, verify `AQUARIUS_HOSTNAME`, `AQUARIUS_USERNAME`, `AQUARIUS_PASSWORD` in the aquarius-connector repo's `.env`.

---

### 6.2 Emergency Procedures

**Full stack restart:**
```bash
cd docker
docker compose down
docker compose up -d
```

**Rollback database to last backup:**
```bash
# 1. Stop application services (keep db running)
docker compose stop studio kong auth rest realtime storage

# 2. Restore backup
cat <backup_file>.sql | docker compose exec -T db psql -U postgres postgres

# 3. Restart services
docker compose up -d
```

---

## 7. Appendices

### Appendix A: Environment Variables Reference

All variables are set in `docker/.env` (copy from `docker/.env.example`).

**Secrets — must be changed before use:**

| Variable | Generation | Description |
|----------|------------|-------------|
| `POSTGRES_PASSWORD` | `openssl rand -base64 32` | PostgreSQL superuser password |
| `JWT_SECRET` | `openssl rand -base64 32` | JWT signing secret |
| `ANON_KEY` | `python scripts/utils/generate_jwt.py` | Supabase anonymous role JWT |
| `SERVICE_ROLE_KEY` | `python scripts/utils/generate_jwt.py` | Supabase service role JWT |
| `DASHBOARD_PASSWORD` | `openssl rand -base64 32` | Supabase Studio login password |
| `SECRET_KEY_BASE` | `openssl rand -base64 48` | Realtime / Supavisor session key (≥64 chars) |
| `VAULT_ENC_KEY` | `openssl rand -hex 16` | Supavisor vault encryption key (32 hex chars) |
| `PG_META_CRYPTO_KEY` | `openssl rand -base64 32` | pg-meta crypto key |
| `LOGFLARE_PUBLIC_ACCESS_TOKEN` | random string ≥20 chars | Logflare public token |
| `LOGFLARE_PRIVATE_ACCESS_TOKEN` | random string ≥20 chars (different) | Logflare private token |

**Database configuration:**

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_HOST` | `db` | Postgres hostname (Docker service name) |
| `POSTGRES_PORT` | `5432` | Postgres port |
| `POSTGRES_DB` | `postgres` | Database name |
| `DASHBOARD_USERNAME` | `supabase` | Studio login username |

**Network / ports:**

| Variable | Default | Description |
|----------|---------|-------------|
| `KONG_HTTP_PORT` | `8000` | Kong API gateway HTTP port |
| `KONG_HTTPS_PORT` | `8443` | Kong API gateway HTTPS port |
| `POOLER_PROXY_PORT_TRANSACTION` | `6543` | Supavisor transaction pooling port |
| `POOLER_TENANT_ID` | `digital-forest-twin-local` | Supavisor tenant identifier |
| `POOLER_DEFAULT_POOL_SIZE` | `20` | Max PostgreSQL connections per pool |
| `POOLER_MAX_CLIENT_CONN` | `100` | Max client connections per pool |

**External integrations:** none configured in this repo's `docker/.env` — provider connectors (e.g. [aquarius-connector](../../aquarius-connector)) hold their own credentials and talk to this stack only via its REST API.

---

### Appendix B: Service Dependencies

Startup dependency order derived from `docker/docker-compose.yml`:

```
vector (no deps)
  └─ db (depends on: vector healthy)
       ├─ analytics (depends on: db healthy)
       │    ├─ studio (depends on: analytics healthy)
       │    ├─ kong (depends on: analytics healthy)
       │    ├─ auth (depends on: db healthy, analytics healthy)
       │    ├─ rest (depends on: db healthy, analytics healthy)
       │    ├─ realtime (depends on: db healthy, analytics healthy)
       │    ├─ meta (depends on: db healthy, analytics healthy)
       │    ├─ edge-functions (depends on: analytics healthy)
       │    └─ supavisor (depends on: db healthy, analytics healthy)
       └─ storage (depends on: db healthy, rest started, imgproxy started)
            └─ imgproxy (no deps)
```

> If studio or kong fail to start, check `analytics` health first.

---

### Appendix C: Port Mapping

| Service | Host port | Container port | Purpose |
|---|---|---|---|
| Studio | 54323 | 3000 | Supabase Studio UI |
| Kong | `${KONG_HTTP_PORT}` (8000) | 8000 | API gateway (REST, Auth, Storage, Realtime) |
| Kong | `${KONG_HTTPS_PORT}` (8443) | 8443 | API gateway (HTTPS) |
| Postgres (via Supavisor) | `${POSTGRES_PORT}` (5432) | 5432 | Direct database connection |
| Supavisor pooler | `${POOLER_PROXY_PORT_TRANSACTION}` (6543) | 6543 | Transaction-mode connection pooling |
| Mail (dev SMTP) | 2500 | 2500 | Local email testing |
| Analytics (Logflare) | 4000 | 4000 | Log ingestion/query API |

Source of truth: `docker/docker-compose.yml` `ports:` blocks; defaults shown are from `docker/.env.example`.

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- New Docker services or port changes
- New admin or import scripts
- New environment variables
- Troubleshooting scenarios discovered in operation
- Aquarius integration changes

**Verification:**
- [ ] `docker compose up -d` completes without errors
- [ ] All containers show healthy in `docker compose ps`
- [ ] Studio UI loads at http://localhost:54323
- [ ] API responds at http://localhost:8000/rest/v1/
- [ ] `python scripts/utils/check_db_schema.py` passes

---
