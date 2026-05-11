# Infrastructure: Digital Forest Twin Database

<!-- SCOPE: Server inventory, network/DNS configuration, port allocation, deployed services, artifact management, CI/CD pipeline, host requirements ONLY. -->
<!-- DO NOT add here: Operational procedures → runbook.md, Architecture patterns → architecture.md, Tech stack versions → tech_stack.md, API contracts → api_spec.md -->
<!-- DOC_KIND: explanation -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need deployment topology, infrastructure inventory, or host-level constraints. -->
<!-- SKIP_WHEN: Skip when you only need operational procedures or feature-level system design. -->
<!-- PRIMARY_SOURCES: docker/docker-compose.yml, docker/.env.example, docs/project/runbook.md -->

> **Status:** Active
> **Last Updated:** 2026-05-11

## Quick Navigation

- [Docs Hub](../README.md)
- [Architecture](../ARCHITECTURE.md)
- [Runbook](runbook.md)
- [Docker Docs](../docker/README.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Explains deployed topology, hosts, networking, and environment inventory. |
| Read When | You need service ports, host requirements, or deployment configuration facts. |
| Skip When | You only need operator steps or business architecture rationale. |
| Canonical | Yes |
| Next Docs | [Runbook](runbook.md), [Architecture](../ARCHITECTURE.md) |
| Primary Sources | `docker/docker-compose.yml`, `docker/.env.example` |

## 1. Server Inventory

Single-node local deployment. All services run on the developer workstation via Docker Compose.

| Property | Value |
|----------|-------|
| **Role** | Local development host |
| **OS** | Developer workstation (Windows or Linux) |
| **Docker** | Docker Desktop 20.10+ with Compose plugin v2.0+ |
| **RAM** | 8 GB minimum, 16 GB recommended |
| **Disk** | 20 GB free minimum (images + DB volumes) |
| **CPU** | 4+ cores recommended |

## 2. Domain & DNS

Local development deployment only. No public domain or DNS records are configured. All services are accessed via `localhost`.

| Endpoint | URL | Purpose |
|----------|-----|---------|
| Supabase Studio | `http://localhost:54323` | Database management UI |
| API Gateway | `http://localhost:8000` | PostgREST + Auth + Storage |
| API Gateway (HTTPS) | `https://localhost:8443` | TLS variant |
| Analytics | `http://localhost:4000` | Logflare analytics UI |
| pg-meta | `http://localhost:8080` | Schema inspector (internal) |

## 3. Port Allocation

### Local Development Host

| Port | Service | Protocol | Notes |
|------|---------|----------|-------|
| 54323 | studio | TCP/HTTP | Supabase Studio UI |
| 8000 | kong | TCP/HTTP | API gateway (`KONG_HTTP_PORT`) |
| 8443 | kong | TCP/HTTPS | API gateway TLS (`KONG_HTTPS_PORT`) |
| 5432 | supavisor → db | TCP | PostgreSQL via connection pooler |
| 6543 | supavisor | TCP | Transaction pooling (`POOLER_PROXY_PORT_TRANSACTION`) |
| 4000 | analytics | TCP/HTTP | Logflare analytics |
| 2500 | mail | TCP/SMTP | Inbucket local mail (dev only) |
| 9000 | mail | TCP/HTTP | Inbucket web UI (dev only) |
| 1100 | mail | TCP/POP3 | Inbucket POP3 (dev only) |

> Ports 5432, 6543, 8000, 8443, and 54323 must be free on the host before starting the stack.

## 4. Deployed Services

All services defined in [`docker/docker-compose.yml`](../../docker/docker-compose.yml). Compose project name: `digital_forest_twin_db`.

| Container | Image | Port(s) | Role |
|-----------|-------|---------|------|
| `dftdb-studio` | `supabase/studio:2025.11.10-sha-5291fe3` | 54323 | Supabase Studio UI |
| `dftdb-kong` | `kong:2.8.1` | 8000, 8443 | API gateway |
| `dftdb-auth` | `supabase/gotrue:v2.182.1` | — | GoTrue authentication |
| `dftdb-rest` | `postgrest/postgrest:v13.0.7` | — | PostgREST REST API |
| `dftdb-realtime` | `supabase/realtime:v2.63.0` | — | WebSocket subscriptions |
| `dftdb-storage` | `supabase/storage-api:v1.29.0` | — | File storage API |
| `dftdb-imgproxy` | `darthsim/imgproxy:v3.8.0` | — | Image transformation proxy |
| `dftdb-meta` | `supabase/postgres-meta:v0.93.1` | 8080 | pg-meta schema inspector |
| `dftdb-edge-functions` | `supabase/edge-runtime:v1.69.23` | — | Deno edge functions |
| `dftdb-analytics` | `supabase/logflare:1.22.6` | 4000 | Logflare analytics |
| `dftdb-db` | Custom (`docker/Dockerfile.db`) | — | PostgreSQL 15 + PostGIS 3 |
| `dftdb-pooler` | `supabase/supavisor:2.7.4` | 5432, 6543 | Connection pooler |
| `dftdb-vector` | `timberio/vector:0.28.1-alpine` | — | Log aggregation |
| `dftdb-mail` | `inbucket/inbucket:3.0.3` | 2500, 9000, 1100 | Local mail (dev only) |

> The database image is built from `docker/Dockerfile.db`. SQL init scripts in `docker/volumes/db/init/` are baked into the image to avoid WSL bind-mount issues on Windows.

## 5. Artifact Repository

No external artifact repository is configured. Docker images are pulled from Docker Hub at runtime. The custom `db` image is built locally from `docker/Dockerfile.db`.

## 6. CI/CD Pipeline

No automated CI/CD pipeline is configured. Deployment is manual via Docker Compose on the developer workstation.

## 7. Host Requirements

| Resource | Minimum | Notes |
|----------|---------|-------|
| **RAM** | 8 GB | 16 GB recommended for comfortable operation |
| **Disk** | 20 GB free | Docker images (~2–4 GB) + named volumes for DB data |
| **CPU** | 4 cores | Recommended; fewer cores will work but with reduced performance |
| **Docker** | 20.10+ | Docker Desktop (Windows/macOS) or Docker Engine (Linux) with Compose plugin v2.0+ |
| **Python** | 3.12 | conda env `digital-twin` — see `environment.yml` |
| **Free ports** | 5432, 6543, 8000, 8443, 54323 | Must not be in use before stack start |

## Maintenance

**Update Triggers:**
- New service added to `docker-compose.yml`
- Port mapping changes
- Docker image version upgrades
- Host requirements change
- New environment variables added to `docker/.env.example`

**Verification:**
```bash
# Check all services running
cd docker && docker compose ps

# Check exposed ports
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Check disk usage (Docker volumes)
docker system df -v
```

---
