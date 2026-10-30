# Deployment — dt.unr.uni-freiburg.de

How the stack runs on the lab server. Local setup and day-to-day operation are in
[RUNBOOK.md](../RUNBOOK.md); this page covers only what differs on the server. First deployed
this way 2026-09-02 (XRFF-238).

## Public surface

The campus ACL blocks every inbound port except 22 and 443 from the client subnets (where the
headsets sit), so everything public goes through the dashboard's nginx on 443.

| Path | Serves |
|---|---|
| `https://dt.unr.uni-freiburg.de/db/rest/v1/...` | PostgREST |
| `https://dt.unr.uni-freiburg.de/db/auth/v1/...` | GoTrue |
| `https://dt.unr.uni-freiburg.de/db/storage/v1/...` | Storage |
| anything else under `/db/` | 404 — no Studio, Realtime, Edge Functions, pg-meta or analytics |
| `/portal/` | the portal (`web/portal/`); `/` redirects here |
| `/jobs/` | the job trigger page (`web/jobs/`) |

Host ports, reachable only on the host itself:

| Service | Server | Dev |
|---|---|---|
| Kong (`KONG_HTTP_PORT`) | 8001 | 8000 |
| Postgres via Supavisor (`POSTGRES_PORT`) | 5433 | 5432 |
| Studio | 54323 | 54323 |

Studio is reached only through an SSH tunnel:

```bash
ssh -L 54323:localhost:54323 <user>@dt.unr.uni-freiburg.de    # then http://localhost:54323
```

The `/db/` proxy lives in `digital-twin-dashboard/docker/nginx/nginx.conf`; its nginx service
joins the `digital_forest_twin_db_default` network to resolve `dftdb-kong`. **Start this stack
before the dashboard's nginx** — the network is created here. `nginx.conf` is a single-file
bind mount: a reload does not pick up edits, force-recreate the container.

Kong still returns 401 without an `apikey` header, and row-level security still applies.

## Server-specific `docker/.env`

| Variable | Server value |
|---|---|
| `SITE_URL`, `API_EXTERNAL_URL`, `SUPABASE_PUBLIC_URL` | `https://dt.unr.uni-freiburg.de/db` |
| `KONG_HTTP_PORT` | `8001` |
| `POSTGRES_PORT` | `5433` |
| `PGDATA_PATH` | `/media/data/dftdb/pgdata` |
| `STORAGE_PATH` | `/media/data/dftdb/storage` |
| `POSTGRES_SHARED_BUFFERS` | `2GB` |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | `8GB` |
| `POSTGRES_WORK_MEM` | `16MB` |
| `DISABLE_SIGNUP` | `true` (since 2026-10-30, XRFF-435) |

The full variable list is [RUNBOOK.md §9](../RUNBOOK.md#9-reference).

## Data on the NFS export

The root logical volume is 28 GB; `/media/data` is a 100 GB NFS export from `ufr-dyn.isi1`.
PGDATA, the object store and the backups live there:

```bash
# Create the directories owned by the container UIDs (postgres 105:106, storage root).
# Needs root; the Docker daemon's root will do where host sudo is unavailable:
cd ~/dev/digital-twin-db
docker run --rm -v /media/data:/media/data \
    -v "$PWD/scripts/server:/s:ro" python:3.12-alpine \
    python3 /s/setup_data_dirs.py
```

Then set `PGDATA_PATH` and `STORAGE_PATH` in `docker/.env` (table above).

- **Hard mount only.** `setup_data_dirs.py` refuses a soft NFS mount: a soft mount can return an
  I/O error mid-fsync and corrupt the cluster. `/media/data` is mounted
  `hard,vers=4.2,proto=tcp,local_lock=none`; re-check with `findmnt -no OPTIONS /media/data`
  after any remount.
- **The pgsodium key volume (`db-config`) stays a named volume** on the root disk. Bind-mounting
  an empty directory over it hides the `.conf` files `postgresql.conf` includes, and the
  postmaster dies with only "configuration file contains errors".
- **Docker must wait for the mount.** Without it, dockerd can start before NFS, Postgres runs
  `initdb` on the empty local mountpoint, and NFS then mounts over a second, divergent cluster.
  Drop-in, installed 2026-09-02:

  ```ini
  # /etc/systemd/system/docker.service.d/nfs-data-mount.conf
  [Unit]
  RequiresMountsFor=/media/data
  ```

  An NFS outage therefore stops Docker entirely.
- **Watch the root disk.** Images still land in `/var/lib/docker` (~5 GB); check `df -h /` after
  image updates. Container logs are capped at 50 MB × 3 in `/etc/docker/daemon.json`.

## Accounts

Signup is closed. Curators create accounts in the portal at `/portal/account/`
([data-access-guide.md](data-access-guide.md#user-management)); from a shell,
`scripts/server/create-user.sh`. Mail does not leave the host (the `mail` service is an inbucket
catch-all), so passwords are handed over, not mailed.

## Deploying

Nothing is edited on the server; the checkouts are disposable. Deploy by pushing and pulling.

- `digital-twin-db` on the server tracks `dev` (it is a test host; `main` moves only at a
  Zenodo release). `digital-twin-dashboard` tracks `main`.
- **Schema changes are applied by hand.** The running cluster is never re-initialised, so the
  baked init files do not reach it:

  ```bash
  cd ~/dev/digital-twin-db && git pull
  docker exec -i dftdb-db psql -U supabase_admin -d postgres < supabase/migrations/<file>.sql
  docker exec dftdb-db psql -U supabase_admin -d postgres -c "NOTIFY pgrst, 'reload schema'"
  ```

- **Env changes need a recreate**, not a restart: `cd docker && docker compose up -d --force-recreate`.

Files on the host that are not in any repository; a re-clone must restore them:

| File | Holds |
|---|---|
| `digital-twin-db/docker/.env` | stack secrets and the server values above |
| `digital-twin-db/web/jobs/config.js` | anon key for the job page |
| `digital-twin-db/web/portal/config.js` | anon key and contact for the portal |
| `digital-twin-dashboard/docker/.env` | dashboard secrets |
| `digital-twin-dashboard/apps/*/.Renviron` (two files) | Shiny app settings |
| `digital-twin-dashboard/docker/nginx/ssl/*.pem` | TLS certificate and key |

## Scheduled work: systemd timers, no cron

The crontab is empty. Everything scheduled is a systemd timer whose unit files live in a
repository.

| Timer | Does | Units |
|---|---|---|
| `dt-renew-ssl.timer` | certbot renewal + nginx recreate; verify it actually renewed before **2026-12-01** (XRFF-421) | `digital-twin-dashboard/scripts/` |
| `dt-job-runner.timer`, `dt-job-runner-reap.timer` | claim `shared.processing_jobs` rows (SILVA, open data) and reap stale ones; growpy and Aquarius jobs run from a workstation | `scripts/runner/` — install steps in [scripts/runner/README.md](../scripts/runner/README.md) |
| `dt-db-backup.timer` | nightly dump to the NFS export | `scripts/server/` |

Install the backup timer:

```bash
sudo cp scripts/server/dt-db-backup.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dt-db-backup.timer
systemctl list-timers dt-db-backup.timer
```

`scripts/server/backup-db.sh` dumps as `supabase_admin`, excludes the *data* of
`sensor.sensor_readings` (re-fetchable through aquarius-connector), writes
`/media/data/dftdb/backups/dftdb_<stamp>.sql.gz`, verifies the gzip and the dump's completion
trailer before renaming, and keeps 30 days. Restore: [RUNBOOK.md §7](../RUNBOOK.md#restore).

Scheduled data ingestion does not run here. Aquarius is request-only: the connector runs from a
workstation against `https://dt.unr.uni-freiburg.de/db`, or as a requested job.

## Checks

```bash
# certificate expiry, from anywhere
openssl s_client -connect dt.unr.uni-freiburg.de:443 \
    -servername dt.unr.uni-freiburg.de </dev/null 2>/dev/null \
    | openssl x509 -noout -enddate

findmnt -no OPTIONS /media/data        # must include "hard"
df -h /                                # root LV headroom
systemctl list-timers 'dt-*'
```

Manual certificate renewal: `digital-twin-dashboard/scripts/renew-ssl.sh` (seconds, no
downtime).
