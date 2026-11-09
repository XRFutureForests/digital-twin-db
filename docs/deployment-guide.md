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
| anything else under `/db/` | 404 — no Studio, pg-meta or analytics (Realtime and Edge Functions no longer run, since 2026-11-09) |
| `/portal/` | the portal (`web/portal/`); `/` redirects here |
| `/jobs/` | the job trigger page (`web/jobs/`) |

Host ports. Compose binds Kong and the pooler to the loopback addresses (127.0.0.1 and ::1)
since 2026-11-09 (XRFF-661), so they are reachable on the host itself only, whatever the host
firewall says; before, Docker published them on every interface and only a firewall rule kept
them off the network:

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

### Portal and API: campus only

Since 2026-11-03 (owner) the dashboard's nginx answers 403, with a one-line explanation, on
`/portal/` and every `/db/` path unless the client address is 132.230.0.0/16, 10.0.0.0/8, this
host (127.0.0.1) or one of its Docker bridges (172.16.0.0/12). People outside use the
university VPN. The dashboards and `/survey/` stay public (the QR codes on the trees are opened
over mobile data). The list is the `geo $dt_campus_only_ok` block in the dashboard's
`docker/nginx/nginx.conf`; remove the `if` lines there to open the portal again.

### The network header

Datasets can be visible to the university network only (XRFF-625). The dashboard's nginx maps
the client address to `X-DT-Network: campus` for 132.230.0.0/16 and 10.0.0.0/8 (campus
clients on the internal network arrive from 10.x addresses) and `internet` for everything else
on `/db/rest/v1/`, replacing any value the client sent; the database reads it in
`shared.request_network()`. That is safe because Kong and the database are reachable from this
host alone, as above: anyone who reaches Kong directly can claim to be on campus. The dashboard
reaches the pooler over the Docker network (`DB_HOST=dftdb-pooler`), not through a host port.
Check what the database sees with `POST /db/rest/v1/rpc/my_access`.

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
- **Schema changes are applied by hand**, one migration at a time: [Applying a
  migration](#applying-a-migration).

- **Env changes need a recreate**, not a restart: `cd docker && docker compose up -d --force-recreate`.
  A recreate restarts Postgres; with compose's old 10 s stop timeout it was killed mid-checkpoint
  and replayed its WAL for minutes on the NFS disk, and the dependent services gave up
  (2026-11-09). The `db` service now has `stop_grace_period: 120s`. If `up` still reports
  `dftdb-db is unhealthy`, wait until `docker exec dftdb-db pg_isready -U postgres -h localhost`
  succeeds, then run `docker compose up -d` again.
- **After Kong is recreated, restart the dashboard's nginx** (`docker restart dtdash-nginx`).
  Its `proxy_pass http://dftdb-kong:8000/...` names Kong literally, so nginx resolves it once at
  start (the `resolver` line applies only to variables) and keeps the old container's address:
  `/db/` answers 502 until the restart (2026-11-09).

Files on the host that are not in any repository; a re-clone must restore them:

| File | Holds |
|---|---|
| `digital-twin-db/docker/.env` | stack secrets and the server values above |
| `digital-twin-db/web/jobs/config.js` | anon key for the job page |
| `digital-twin-db/web/portal/config.js` | anon key and contact for the portal |
| `digital-twin-dashboard/docker/.env` | dashboard secrets |
| `digital-twin-dashboard/apps/*/.Renviron` (two files) | Shiny app settings |
| `digital-twin-dashboard/docker/nginx/ssl/*.pem` | TLS certificate and key |

## Applying a migration

Written from the deploy of 2026-11-02 (release 2.0.3, migrations `20261102100000` to
`20261102120000`). Afterwards a schema-only dump of `shared`, `trees`, `sensor`,
`point_clouds`, `environments`, `imagery`, `forest_floor` and `public`, grants included, was
identical on dev and dt.unr.

**Only migrations change the running database.** Postgres runs the chain in
`supabase/migrations/` only on an empty `PGDATA`, and `PGDATA` here is a long-lived
directory on the NFS export. `docker compose build db && docker compose up -d` rebuilds the
image and leaves the database as it was. The chain matters only for a new cluster.

**Never apply the snapshot to a running database.** `10000000000001_extensions.sql`,
`20261109120000_baseline_snapshot.sql` and `20261109120001_reference_data.sql` build an
empty cluster; the server already holds everything in them. A running database takes only
the migrations dated after them, and, on 2026-11-09, the last pre-snapshot migration
`archive/20261109100000_audit_security_and_integrity.sql`.

**The server checkout tracks `dev`**, so a migration reaches dt.unr when it is pulled and
applied, not at a Zenodo release.

### Where the server stands

dt.unr keeps no record of applied migrations: they are run with `psql`, not the Supabase CLI,
so there is no `supabase_migrations` table. Compare the server with dev instead. Dev has every
committed migration applied, and a fresh init from the rebuilt image reproduces it. From a
workstation with the dev stack running, in Git Bash:

```bash
ARGS="-U supabase_admin -d postgres --schema-only --no-owner \
      -n shared -n trees -n sensor -n point_clouds -n environments -n imagery -n forest_floor -n public"
docker exec dftdb-db pg_dump $ARGS | tr -d '\r' | sort > schema_dev.txt
ssh dt.unr.uni-freiburg.de "docker exec dftdb-db pg_dump $ARGS" | tr -d '\r' | sort > schema_unr.txt
diff schema_dev.txt schema_unr.txt && echo "dt.unr matches dev"
```

The dumps are sorted because the two databases can list the same `GRANT` lines in a different
order; to read a difference in context, dump again without `| sort`. `tr -d '\r'` drops carriage
returns: six account functions on dt.unr were created from a file with Windows line endings and
keep them in their bodies, which changes nothing about how they run.

An empty diff means dt.unr is at the newest migration. Otherwise, find the oldest migration
whose objects the diff shows missing and apply from that one on, from `archive/` for anything
dated before the 2026-11-09 snapshot. **Apply in file-name order and skip none:** later
migrations change objects that earlier ones create or rename.

### Steps

Run on the server, as `max` (in the `docker` group; no sudo needed).

1. **Pull.** The checkout must be clean: nothing is edited on the server.

   ```bash
   cd ~/dev/digital-twin-db && test -z "$(git status --porcelain)" && git pull --ff-only && git log --oneline -1
   ```

2. **Back up.** The nightly dump can be most of a day old. Take a fresh one (about 20 s,
   written to `/media/data/dftdb/backups/`):

   ```bash
   scripts/server/backup-db.sh
   ```

3. **Read each migration's header and the CHANGELOG entry** for a step outside SQL. Example: the
   schema rename `20261102100000` also needed `pointclouds` replaced with `point_clouds` in
   `PGRST_DB_SCHEMAS` in `docker/.env`.

4. **Apply each migration as one transaction:**

   ```bash
   cd docker
   docker compose exec -T db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -1 \
       < ../supabase/migrations/<file>.sql
   ```

   `-1` wraps the file in one transaction, and `ON_ERROR_STOP=1` makes the first error roll
   all of it back. Without both flags, psql reports the error, carries on and commits the rest,
   which leaves the migration half applied. A file containing a statement that cannot run in a
   transaction (`CREATE INDEX CONCURRENTLY`, `VACUUM`) must run without `-1`; none does so far.

5. **Change the environment if the migration needs it**, keeping a copy:

   ```bash
   cp .env .env.bak-$(date +%F)-<what>
   # edit .env
   docker compose up -d rest          # recreates PostgREST with the new env
   ```

   With no env change, reload PostgREST's schema cache instead:

   ```bash
   docker compose exec -T db psql -U supabase_admin -d postgres -c "NOTIFY pgrst, 'reload schema'"
   ```

6. **Verify.** The REST surface, PostgREST's log, then the comparison with dev above:

   ```bash
   K=$(grep '^ANON_KEY=' .env | cut -d= -f2-); B=https://dt.unr.uni-freiburg.de/db/rest/v1
   for p in point_clouds trees sensors ue_trees; do
       printf '%s ' $p; curl -s -o /dev/null -w '%{http_code}\n' -H "apikey: $K" "$B/$p?limit=1"
   done                                               # each 200
   docker compose logs --since 10m rest | grep -iE 'error|fail'    # nothing
   ```

   Then query whatever the migration changed: a column default, a function body, a renamed
   schema.

### When it fails

- **The migration stops with an error.** With `-1` and `ON_ERROR_STOP=1` nothing was changed.
  Fix the migration on dev, test it there, commit, pull on the server and apply again.
- **A migration ran without `-1` and stopped part-way.** Do not just re-run it: its `IF EXISTS`
  guards can skip the half that landed and hide the half that did not. Compare with dev to see
  what is in place, then either finish it with a follow-up migration or restore the dump from
  step 2 ([RUNBOOK.md §7](../RUNBOOK.md#restore)).
- **Every REST call fails after an env change.** PostgREST cannot build its schema cache,
  usually because `PGRST_DB_SCHEMAS` names a schema that does not exist. `docker compose logs
  rest` names it; correct `.env`, or restore the `.env.bak-*` copy, and `docker compose up -d
  rest` again.

### Traps

- **Send SQL to the server over stdin.** Inside `ssh host '...'` the single quotes of SQL string
  literals end the shell string, and the query arrives without them. Write the SQL to a file and
  run `ssh host 'cd ~/dev/digital-twin-db/docker && docker compose exec -T db psql -U
  supabase_admin -d postgres' < check.sql`.
- **The `db` container has 64 MB of `/dev/shm`.** A large parallel query, such as aggregating
  `shared.recent_changes` (about 2 million rows), fails with `could not resize shared memory
  segment ... No space left on device`. Run such checks after `SET
  max_parallel_workers_per_gather = 0;`.

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
