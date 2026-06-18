# Data Access Guide

> For team members and external collaborators who need to read or upload data.

---

## Read access (UE, scripts, browser)

Anyone with the `ANON_KEY` can query the REST API with no login required.

**Get the key from Max.** Then:

```bash
# Test read access
curl "http://<SERVER_OR_LOCALHOST>:8000/rest/v1/species" \
  -H "apikey: <ANON_KEY>"
```

Read access covers: species, locations, trees, forest_state, sensors, sensor readings, scenarios, and all other public views.

---

## Upload / write access

Writing data requires an **authenticated user account**. Two options:

### Option A — Supabase Studio (easiest for one-off uploads)

1. Ask Max to create an account for you (see below).
2. Go to **http://localhost:54323** (local) or the server Studio URL.
3. Log in with your credentials.
4. Use **Table Editor** → navigate to the relevant table → paste or import rows.

Good for: small data fixes, adding a few tree records, checking what's in the DB.

### Option B — Python import scripts (for batch uploads)

The repo provides ready-made scripts under `scripts/import/`:

```bash
conda activate digital-twin

# Import a tree inventory CSV
python scripts/import/import_trees.py data/imports/your_trees.csv

# Import sensor readings
python scripts/import/import_sensor_data.py
```

Scripts use the `service_role` key from the `.env` file — ask Max for this if running against the server.

### Option C — Direct API (authenticated)

After logging in and receiving a JWT token:

```bash
curl -X POST "http://<SERVER>:8000/rest/v1/trees" \
  -H "apikey: <ANON_KEY>" \
  -H "Authorization: Bearer <YOUR_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"locationid": 5, "speciesid": 1, "varianttypeid": 1, "height_m": 20.0, ...}'
```

---

## How Max creates a user account

In Supabase Studio (http://localhost:54323 or server URL):

1. Go to **Authentication → Users**
2. Click **Invite user** → enter the collaborator's email
3. They receive a magic link to set their password
4. Their account gets the `authenticated` role automatically — write access to trees, sensors, campaigns, plots

No SQL or CLI needed.

---

## Permissions summary

| Role | Who | What they can do |
|------|-----|-----------------|
| `anon` | Anyone with ANON_KEY | SELECT on all public views |
| `authenticated` | Users with a Studio account | SELECT + INSERT/UPDATE on data tables |
| `service_role` | Max / scripts | Full access, including schema changes |

**Never share the `service_role` key with external collaborators.** Give them a Studio account (authenticated role) instead.

---

## What each table requires for a valid tree row

Minimum required fields when inserting into `trees` (via `forest_state` or direct):

| Field | Type | Example |
|-------|------|---------|
| `locationid` | integer | `5` (Ecosense site) |
| `varianttypeid` | integer | `1` (original) |
| `position` | geometry | `ST_GeomFromText('POINT(7.877 48.268)', 4326)` |

Optional but important for UE:

| Field | Notes |
|-------|-------|
| `speciesid` | Links to species for asset lookup |
| `scenarioid` | Required for variant switching |
| `height_m` | Used for PCG tree scaling |
| `age_years` | Used for Time Machine |
