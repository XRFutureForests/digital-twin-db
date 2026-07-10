# Local Deployment Guide

> **Goal:** Spin up a local Digital Forest Twin database in under 30 minutes.  
> **Audience:** Team members and external collaborators (e.g., Lukas) who need a local DB for UE development.

---

## Prerequisites

Install these before starting:

| Tool | Version | Download |
|------|---------|---------|
| Docker Desktop | Latest stable | https://www.docker.com/products/docker-desktop |
| Git | Any | https://git-scm.com |

Ensure Docker Desktop is **running** before proceeding (check the system tray icon).

---

## Step 1 — Clone the repository

```bash
git clone https://github.com/XRFutureForests/digital-twin-db.git
cd digital-twin-db
```

---

## Step 2 — Get the `.env` file

The `.env` file contains database passwords and API keys. It is **not committed to git** — get it from Max directly (shared via password manager or secure message).

Place it here:

```
digital-twin-db/
└── docker/
    └── .env        ← put the file here
```

You can verify it is in the right place:

```bash
ls docker/.env
```

> **Note:** If you only have `.env.example`, that file contains placeholder values and will not work. You need the real `.env` from Max.

---

## Step 3 — Start the database

```bash
cd docker
docker compose up -d
```

This pulls ~800 MB of Docker images on first run — takes 3–5 minutes. Subsequent starts take ~15 seconds.

Wait ~60 seconds, then check that all services are healthy:

```bash
docker compose ps
```

All containers should show `healthy` in the Status column. If any show `Exit` or `Restarting`, see [Troubleshooting](#troubleshooting) below.

---

## Step 4 — Verify the database is running

### Option A: Supabase Studio (browser UI)

Open: **http://localhost:54323**

Log in with:
- **Username:** `supabase`
- **Password:** see `DASHBOARD_PASSWORD` in your `.env` file

You should see the Digital Forest Twin project with 6 schemas (shared, trees, sensor, environments, imagery, pointclouds).

### Option B: Quick API check (terminal)

```bash
# Should return [] (empty array) if no data loaded yet
curl "http://localhost:8000/rest/v1/trees?limit=5" \
  -H "apikey: $(grep ANON_KEY docker/.env | cut -d= -f2)"
```

A `[]` response (not an error) confirms the API is working.

---

## Step 5 — Load tree data

The database starts **empty** — schema only. Load the Ecosense demo dataset:

```bash
# Activate the Python environment
conda activate digital-twin

# Import tree inventory
python scripts/import/import_trees.py data/imports/ecosense_trees_import.csv

# Import sensor metadata
python scripts/import/sync_aquarius_direct.py 45

# Link sensors to trees
python scripts/import/link_sensors_to_trees.py
```

After import, the API check from Step 4 Option B should return tree records.

> **No conda?** Install the environment first:
> ```bash
> conda env create -f environment.yml
> ```

---

## Step 6 — Connect Unreal Engine

Use these values in your UE Blueprint (`BP_DigitalTwinFetcher` or equivalent):

| Setting | Value |
|---------|-------|
| **API Base URL** | `http://localhost:8000/rest/v1` |
| **ANON_KEY** | from `ANON_KEY=` line in `docker/.env` |

Set these as Blueprint variables or in a `DT_Config` DataTable. See the XR Future Forests Lab knowledge hub note `05-PRESENTATION-TIER/data-fetcher-guide` (Unreal ↔ Digital Twin DB Integration Guide) for the full Blueprint setup.

**Quick test query (paste in browser):**
```
http://localhost:8000/rest/v1/trees?select=variant_id,height_m,position,species(common_name),stems(dbh_cm)&limit=5&apikey=<YOUR_ANON_KEY>
```

Replace `<YOUR_ANON_KEY>` with the value from your `.env`.

---

## Daily workflow

```bash
# Start (after reboot or if containers stopped)
cd docker && docker compose up -d

# Stop (free up resources when not needed)
cd docker && docker compose stop

# Full reset (wipes all data — use with caution)
cd docker && docker compose down -v --remove-orphans
```

---

## Troubleshooting

### Container shows `Exit` or `Restarting`

```bash
# Check logs for the failing container
docker compose logs <container-name>

# Common containers: dftdb-studio, dftdb-kong, dftdb-db, dftdb-auth
```

### `curl` returns 401 Unauthorized

The ANON_KEY in your request does not match the JWT_SECRET in `.env`. Ensure you are using the ANON_KEY value from **the same** `.env` file the stack is running with.

### Port conflict: address already in use

Another service is using port 8000 or 54323. Either stop the conflicting service, or edit the port mappings in `docker/docker-compose.yml`:

```yaml
ports:
  - "8001:8000"   # change 8001 to any free port
```

Then update the API Base URL in UE accordingly.

### Studio not loading (blank page or spinner)

The studio container depends on the analytics container being healthy first. Wait an extra 30–60 seconds, then refresh. If it still fails:

```bash
docker compose restart studio
```

### Docker Desktop not starting on Windows

Ensure WSL2 is enabled:
```powershell
wsl --install
```
Then restart Docker Desktop.

---

## What's in the stack

| Service | URL | Purpose |
|---------|-----|---------|
| Supabase Studio | http://localhost:54323 | Visual DB management |
| REST API (Kong) | http://localhost:8000/rest/v1 | UE connects here |
| PostgreSQL | localhost:5432 | Direct DB access if needed |

The REST API is what Unreal Engine talks to. Studio is for manual inspection and data management.
