# Container stack — `docker/`

Reference for what is in `docker/` and how it differs from the upstream Supabase self-hosting
setup. Starting, loading, querying, backing up and resetting the stack are in
[RUNBOOK.md](../../RUNBOOK.md); symptoms in [troubleshooting.md](../troubleshooting.md); image
versions in [versions.md](versions.md).

## Files

| Path | What it is |
|---|---|
| `docker/docker-compose.yml` | the stack; compose project `digital_forest_twin_db`, network `digital_forest_twin_db_default`, named volumes `db-data` (PGDATA) and `db-config` (pgsodium key) |
| `docker/Dockerfile.db` | the `db` image: `supabase/postgres:15.8.1.085` with `supabase/migrations/` (the schema chain) and `data/lookups/` baked in |
| `docker/.env.example` | template for the gitignored `docker/.env` ([RUNBOOK.md §9](../../RUNBOOK.md#9-reference)) |
| `docker/volumes/api/kong.yml` | Kong declarative config (routes below) |
| `docker/volumes/db/*.sql` | Supabase platform init (`_supabase` database, analytics, pooler, webhooks, roles), and `refresh-lookups.sql`, which reloads the lookups at the end of a fresh init |
| `docker/volumes/logs/vector.yml` | Vector log shipping to Logflare |
| `docker/volumes/pooler/pooler.exs` | Supavisor tenant setup |
| `docker/volumes/storage/` | default object store (`STORAGE_PATH` overrides it) |

Config files are mounted as directories, not single files, because single-file bind mounts go
stale under WSL after a reboot; the `db` init scripts are baked into the image for the same
reason.

## Database initialisation

On first boot of an empty `db-data` volume the image runs `supabase/migrations/*.sql` in name
order, after the image's own platform migrations:

| Files | Content |
|---|---|
| `10000000000001_extensions.sql` | PostGIS and the grants on `extensions` (sorts before the platform migrations) |
| `20261109120000_baseline_snapshot.sql`, `20261109120001_reference_data.sql` | snapshot (2026-11-09) of every custom schema, table, view, function, RLS policy, grant and role, and the reference rows |
| later timestamped files | changes since the snapshot |
| `zz-refresh-lookups.sql` (from `docker/volumes/db/refresh-lookups.sql`) | reloads the lookups from `data/lookups/*.csv` |

`supabase/migrations/archive/` (the history before the snapshot) is excluded from the image.
A new migration reaches a fresh database only through `docker compose build db` plus a fresh
init; a running one takes it by hand. The workflow is in [AGENTS.md](../../AGENTS.md#schema-migrations).

## Kong routes

| Path | Upstream | Auth at Kong |
|---|---|---|
| `/rest/v1/` | `rest:3000` | `key-auth` + `acl` |
| `/auth/v1/` (`/verify`, `/callback`, `/authorize` open) | `dftdb-auth:9999` | `key-auth` + `acl` |
| `/graphql/v1` | `rest:3000/rpc/graphql` | `key-auth` + `acl` |
| `/storage/v1/` | `storage:5000` | none (Storage checks the JWT) |
| `/pg/` | `meta:8080` | `key-auth`, admin only |
| `/analytics/v1/` | `analytics:4000` | none |
| `/` | `studio:3000` | `basic-auth` (`DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`) |

The auth upstream uses the container name `dftdb-auth`, not the service name `auth`: on the
campus network the short name `auth` resolves to a university host.

Port 54323 publishes Studio directly, bypassing Kong and its basic-auth, so it (and the
logflare 4000 and inbucket 2500/9000/1100 ports) is bound to `127.0.0.1` only. Kong and the
pooler are bound to both loopbacks (127.0.0.1 and ::1) since 2026-11-09: the server's nginx and
the dashboard reach them over the Docker network.

## Differences from upstream Supabase

1. Forest schemas added to `PGRST_DB_SCHEMAS`
   (`shared,point_clouds,trees,sensor,environments,imagery`; `forest_floor` is reached through
   `public` views).
2. `db` built from `Dockerfile.db` with the schema chain baked in, instead of init-file bind mounts.
3. `PGDATA_PATH`, `STORAGE_PATH` and the `POSTGRES_*` memory variables, for the server's NFS
   layout ([deployment-guide.md](../deployment-guide.md)).
4. Studio published on 54323 (loopback only).
5. Job queue `shared.processing_jobs` + `request_job()` RPC instead of Edge Functions
   (XRFF-257; [requesting-a-job.md](../requesting-a-job.md)). The Edge Runtime and Realtime
   services are removed (2026-11-09, XRFF-661): nothing used them.
6. Signup closed by default (`DISABLE_SIGNUP=true`).
7. No `jwt.sql`: the upstream template stored the JWT secret as a database setting every role
   could read (removed 2026-11-09, XRFF-661).

## Updating images

Change the tag in `docker-compose.yml` (or the `FROM` line in `Dockerfile.db`), record it in
[versions.md](versions.md), then:

```bash
cd docker
docker compose pull                 # every service except db
docker compose build db             # only if Dockerfile.db changed
docker compose up -d
```

Upstream references: [Supabase self-hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker),
[supabase/docker on GitHub](https://github.com/supabase/supabase/tree/master/docker).
