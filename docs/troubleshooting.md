# Troubleshooting

Symptoms specific to this stack, local first. Run compose commands from `docker/`. Server-only
failures (NFS mount ordering, campus DNS on short service names, the single-file nginx bind
mount) are in [deployment-guide.md](deployment-guide.md) and [RUNBOOK.md §8](../RUNBOOK.md#8-production).

> **Data-loss warnings.** `docker compose down -v` deletes both named volumes — every row in
> the database. `docker system prune --volumes` deletes unused volumes of *every* project on the
> machine. Back up first ([RUNBOOK.md §7](../RUNBOOK.md#backup)).

## First look

```bash
docker compose ps                       # every service "healthy"
docker compose logs --tail 100 <service>
docker inspect dftdb-db --format '{{.State.Health.Status}}'
```

Service names: `db`, `vector`, `analytics`, `studio`, `kong`, `auth`, `rest`, `realtime`,
`storage`, `imgproxy`, `meta`, `functions`, `supavisor`, `mail`. Containers are `dftdb-<name>`,
except `functions` → `dftdb-edge-functions` and `supavisor` → `dftdb-pooler`.

## Startup

| Symptom | Cause | Fix |
|---|---|---|
| Studio or Kong never start | both wait for `analytics` to be healthy | `docker compose restart analytics`, wait ~15 s, `docker compose restart studio kong` |
| `dftdb-analytics` unhealthy, log says `database "_supabase" does not exist` | the cluster was initialised incompletely | rebuild from scratch (Reset, below) |
| `auth`, `realtime`, `storage` restart a few times on first start (`must be owner of function uid`) | they race the first init | wait 2–3 min; if it persists, `docker compose restart auth realtime storage` |
| db log: `Database directory appears to contain a database; Skipping initialization` | the `db-data` volume holds an older cluster, so init files do not run | expected on every start after the first; to re-init, see Reset |
| `password authentication failed for user supabase_admin` | `POSTGRES_PASSWORD` changed after the cluster was initialised; init sets role passwords once | restore the old password in `docker/.env`, or `ALTER ROLE … PASSWORD` for each role inside the container; a Reset also works but deletes the data |
| `Bind for 0.0.0.0:8000 failed: port is already allocated` | another process holds the port | find it (`netstat -ano \| findstr :8000`, `ss -tlnp \| grep 8000`); or move `KONG_HTTP_PORT` in `docker/.env`. Studio's 54323 is fixed in `docker-compose.yml` |
| volumes fail after a Docker Desktop restart on Windows | stale WSL bind-mount paths | restart Docker Desktop, `docker compose up -d`; persistent state is on named volumes |

`POSTGRES_PORT` is not just a host mapping: it is also the port Postgres listens on inside the
network and the port every service connects to. Changing it is fine, but it changes all of them.

## Schema and data

| Symptom | Cause | Fix |
|---|---|---|
| tables or views missing after a fresh start | the `db` image was not rebuilt after `docker/volumes/db/init/` changed | `docker compose build db`, then Reset |
| a migration applied but the API does not see it | PostgREST caches the schema | `docker exec dftdb-db psql -U supabase_admin -d postgres -c "NOTIFY pgrst, 'reload schema'"` |
| `must be owner of …` when running DDL or a seed | you ran it as `postgres`, which is not a superuser; `supabase_admin` owns the custom schemas | run it with `-U supabase_admin` |
| lookup tables empty | `30-load-lookup-tables.sql` did not load the CSVs | `python scripts/admin/refresh_lookups.py` |
| `generate_schema_docs.py --check` exits 1 | the schema changed without regenerating the docs | `python scripts/utils/generate_schema_docs.py`, commit both files |

Expected after init: schemas `shared`, `trees`, `sensor`, `pointclouds`, `environments`,
`imagery`, `forest_floor`; databases `postgres` and `_supabase` (with schemas `_analytics`,
`_supavisor`); `SELECT count(*) FROM shared.species` returns 14.

```bash
docker exec dftdb-db psql -U postgres -c "\dn"
docker exec dftdb-db psql -U postgres -d _supabase -c "\dn"
```

## API

| Symptom | Cause | Fix |
|---|---|---|
| 401 from `/rest/v1/` | no `apikey` header, or a key signed with a different `JWT_SECRET` | send `-H "apikey: $ANON_KEY"` using the `ANON_KEY` from the `.env` the stack runs with |
| 401 everywhere after changing `JWT_SECRET` | the API keys are JWTs signed with the old secret | regenerate both with `python scripts/utils/generate_jwt.py`, then `docker compose up -d --force-recreate` (a `restart` keeps the old env) |
| a custom schema not reachable over REST | not in `PGRST_DB_SCHEMAS` | add it in `docker/.env`, `docker compose up -d --force-recreate rest` |
| `/realtime/v1/` fails | Realtime is not used; its Kong upstream `realtime-dev.supabase-realtime` does not resolve on dev | none needed |

From inside the network: `docker exec dftdb-kong wget -qO- http://rest:3000/` (Kong has
`wget`, not `curl`; Studio has neither).

## Connecting with psql or a database tool

| From | Host / port | User |
|---|---|---|
| inside the container | `docker exec -it dftdb-db psql -U postgres` (or `-U supabase_admin` for DDL) | — |
| the host, via Supavisor | `localhost:5432` (session) or `:6543` (transaction) | `postgres.<POOLER_TENANT_ID>`, e.g. `postgres.digital-forest-twin-local`; password `POSTGRES_PASSWORD` |

Plain `postgres` as the username through the pooler fails: Supavisor needs the tenant suffix.

## Studio

`http://localhost:54323` opens Studio directly with no login. If it does not load, check
`docker compose ps analytics meta studio` and restart `studio` once `analytics` is healthy.

## Reset

The schema is baked into the `db` image, so a reset needs the rebuild:

```bash
docker compose down -v --remove-orphans   # DELETES ALL DATA (db-data and db-config)
docker compose build db
docker compose up -d
```

Then reload data: [RUNBOOK.md §6](../RUNBOOK.md#full-rebuild).
