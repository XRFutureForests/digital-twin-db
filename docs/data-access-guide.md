# Data Access Guide

> For team members and external collaborators who need to read or write data.

---

## Read access — no account needed

Anyone with the `ANON_KEY` can query the REST API without logging in.

**Get the key from Max.** Then:

```bash
curl "http://<SERVER_OR_LOCALHOST>:8000/rest/v1/species" \
  -H "apikey: <ANON_KEY>"
```

Read access covers every public view: `species`, `locations`, `trees`, `ue_trees`, `scenarios`, `varianttypes`, `sensors`, `sensorreadings`, `growth_simulations`, `simulation_runs`, and all morphology lookups.

---

## Write access — requires an account

Writing data (INSERT / UPDATE / DELETE) requires an authenticated JWT. Two paths:

### Option A — Supabase Studio (easiest for one-off changes)

1. Ask Max to create an account for you (see [User management](#user-management) below).
2. Go to **http://localhost:54323** (local) or the server Studio URL.
3. Log in with your email and password.
4. Use **Table Editor** → navigate to the relevant table → paste or import rows.

### Option B — Python import scripts (batch uploads)

```bash
conda activate digital-twin
python scripts/import/import_trees.py data/imports/your_trees.csv --dry-run  # validate first
python scripts/import/import_trees.py data/imports/your_trees.csv             # then import
```

Scripts use `SERVICE_ROLE_KEY` from `docker/.env` — ask Max for this when running against the server.

Available scripts:

| Script | Purpose |
|--------|---------|
| `scripts/import/import_trees.py` | Bulk upsert tree inventory CSV |
| `scripts/import/ingest_sensor_data.py` | Sync sensors + readings from any provider (see [aquarius-connector](../https://gitlab.uni-freiburg.de/xr-future-forests-lab/aquarius-connector) for Aquarius) |
| `scripts/import/link_sensors_to_trees.py` | Link sensors to their nearest tree |
| [silva-connector](../../silva-connector) (separate repo, R) | Run SILVA and write `trees.SimulationRuns` + `trees.GrowthSimulations` + the variant chain, over libpq |
| `scripts/admin/refresh_lookups.py` | Reload lookup CSVs without a full DB reset |

### Option C — Direct API with a user JWT

Log in first to get a session token, then use it as the `Authorization` header:

```bash
# 1. Log in (returns access_token + refresh_token)
curl -X POST "http://<SERVER>:8000/auth/v1/token?grant_type=password" \
  -H "apikey: <ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "password": "your-password"}'

# 2. Use the access_token for writes
curl -X POST "http://<SERVER>:8000/rest/v1/trees" \
  -H "apikey: <ANON_KEY>" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"location_id": 5, "species_id": 1, "variant_type_id": 1, "height_m": 20.0, ...}'
```

The `access_token` is a short-lived JWT (1 hour). Refresh it:

```bash
curl -X POST "http://<SERVER>:8000/auth/v1/token?grant_type=refresh_token" \
  -H "apikey: <ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "<REFRESH_TOKEN>"}'
```

---

## User management

### Creating a user account (admin)

**Use the script.** It is the whole job in one line, on either stack:

```bash
# on the server
ssh dt.unr.uni-freiburg.de dev/digital-twin-db/scripts/server/create-user.sh someone@uni-freiburg.de

# locally, from the repo root
scripts/server/create-user.sh someone@dev.xrff.local curator

scripts/server/create-user.sh --list
scripts/server/create-user.sh --set-role someone@uni-freiburg.de curator
```

It reads `SERVICE_ROLE_KEY` and `KONG_HTTP_PORT` from `docker/.env`, so it is
identical on both hosts and correct on both — **the ports differ**: Kong is
`8000` on dev and `8001` on the server, the same class of divergence as Postgres
on 5432 and 5433. It generates the password, sets `email_confirm`, sets the role
tier in the same call, refuses a duplicate address or an unknown role, and
prints the credentials once.

Roles are `admin`, `curator`, `contributor` — the three `shared.is_contributor()`
accepts. An account without one can read the workflow menu and its own job
history but cannot request a run.

#### Doing it through Studio instead

Possible, in **two** steps rather than one, because Studio's user form has no
field for `app_metadata`. Verified on the dev stack 2026-09-10.

1. **Authentication → Users → Add user → Create new user.** Tick *Auto Confirm
   User* — without it the account lands unconfirmed and the confirmation mail
   dies in inbucket (below), so it can never sign in and nothing says so.
2. **SQL Editor**, to give it a role tier:

   ```sql
   update auth.users
      set raw_app_meta_data = raw_app_meta_data || '{"role":"contributor"}'::jsonb
    where email = 'someone@uni-freiburg.de';
   ```

The claim appears in the **next** sign-in's JWT, not the current one — GoTrue
mints it at sign-in from `raw_app_meta_data`. Confirmed end to end: before the
update the token carried no role and `request_job()` refused it; after it, the
same account signed in and queued a job.

**Studio on the server is not exposed.** `dftdb-studio` publishes 54323, and the
campus client-subnet ACL blocks every inbound port but 22 and 443, so reach it
through an SSH tunnel:

```bash
ssh -L 54323:localhost:54323 dt.unr.uni-freiburg.de
# then open http://localhost:54323 — DASHBOARD_USERNAME / DASHBOARD_PASSWORD from docker/.env
```

#### Why *Invite user* is not the route

Mail from this deployment never leaves the machine. `SMTP_HOST` is
`supabase-mail`, the `dftdb-mail` container: [inbucket](https://inbucket.org/), a
catch-all test server. It accepts the message on 2500 and holds it in a web inbox
on 9000; it forwards nothing. So an invitation is generated, accepted, and never
delivered.

An operator *can* finish the flow by reading the link out of inbucket —
<http://localhost:9000> locally, or through the same kind of tunnel on the server
— but that is a workaround, not a process to hand to a colleague.

#### The call underneath

Both paths above are this, which is worth knowing when scripting something else:

```bash
curl -X POST "$SUPABASE_URL/auth/v1/admin/users"   -H "apikey: $SERVICE_ROLE_KEY"   -H "Authorization: Bearer $SERVICE_ROLE_KEY"   -H "Content-Type: application/json"   -d '{"email":"someone@example.com",
       "password":"<generated>",
       "email_confirm":true,
       "app_metadata":{"role":"contributor"}}'
```

`email_confirm: true` is the load-bearing field, and `app_metadata` is what saves
the follow-up `UPDATE`.

Hand the password over on a channel that is not this repository. **Note that the
person cannot then change it**: there is no password-change page, and a reset
mail would go to inbucket. Changing it means either an admin re-setting it, or
the account holder calling `PUT /auth/v1/user` with their own token. If a
password is lost, delete the account and make another.

### Removing a user

In Studio → **Authentication → Users** → click the user → **Delete user**.

### Resetting a password

In Studio → **Authentication → Users** → click the user → **Send password reset**. The user receives an email with a reset link.

If Studio email delivery is not configured (default for local dev), you can set the password directly via SQL:

```sql
-- Run in Studio → SQL Editor
UPDATE auth.users SET encrypted_password = crypt('new-password', gen_salt('bf'))
WHERE email = 'user@example.com';
```

### Checking who has access

```sql
-- List all GoTrue users
SELECT email, created_at, last_sign_in_at FROM auth.users ORDER BY created_at;
```

---

## Permissions summary

Four tiers, named after standard research-data-management vocabulary (RDA/DataCite-style):

| Role | Who | What they can do |
|------|-----|-----------------|
| `anon` (**Consumer**) | Anyone with ANON_KEY | SELECT on all public views |
| `authenticated`, no role claim | Any Studio account by default | SELECT everywhere; full CRUD on metadata/lookup tables (species, scenarios, locations, sensors, management/disturbance events, campaigns, processes, …); no write access to field-data tables |
| `authenticated` + `role: contributor` (**Contributor**) | Field data collectors | Everything above, plus INSERT on field-data tables |
| `authenticated` + `role: curator` (**Curator**) | Trusted data managers | Everything above, plus UPDATE/DELETE on field-data tables |
| `authenticated` + `role: admin` (**Administrator**) | Lab administrators | Everything above, plus can set other users' `role` claim |
| `service_role` | Max / import scripts | Full access, bypasses RLS; never share externally |

Field-data tables are the ones where a bad edit or delete actually costs something (cited measurements, growth-sim inputs): `Trees`, `Stems`, `PointClouds`, `Environments`, `Images`, `SensorReadings`, `PhenologyObservations`, `Deadwood`, `GroundVegetation`. Everything else stays full-CRUD for any `authenticated` user regardless of role claim — see `docker/volumes/db/init/29-role-tiers.sql`.

**Never share `SERVICE_ROLE_KEY` with external collaborators.** Create a Studio account for write access instead.

Read-only views (`ue_trees`, `growth_simulations`, `simulation_runs`, morphology lookups) are SELECT-only even for authenticated users. Writes to those domains go through the underlying tables via the import scripts and silva-connector.

### Assigning a role tier

New accounts have no `role` claim and can't write to field-data tables. An admin sets it directly (run as `service_role`, e.g. in Studio → SQL Editor):

```sql
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "curator"}'::jsonb
WHERE email = 'someone@example.com';
```

Valid values: `admin`, `curator`, `contributor`. No claim = base `authenticated` (metadata tables only, no field-data writes).

---

## What each table requires for a valid tree row

Minimum required fields when inserting into `trees`:

| Field | Type | Example |
|-------|------|---------|
| `location_id` | integer | `5` (Ecosense site) |
| `variant_type_id` | integer | `1` (original) |
| `position` | geometry | `ST_GeomFromText('POINT(7.877 48.268)', 4326)` |

Important for Unreal Engine:

| Field | Notes |
|-------|-------|
| `species_id` | Links to species for asset selection |
| `scenario_id` | Required for scenario/variant switching in UE |
| `height_m` | Used for PCG tree scaling |
| `age_years` | Used for Time Machine projection |

See [data/templates/DATA_PREPARATION_GUIDE.md](../data/templates/DATA_PREPARATION_GUIDE.md) for the full 23-column import template and field validation rules.

---

## Correcting data — field updates vs. new variants

**When NOT to create a new variant:** If you discover a typo, a missed measurement, or a data entry error on an existing record, fix it with a plain UPDATE — not a new variant. A new variant is for a distinct forest state (a scenario, a time step, a management intervention). A data correction is just a correction.

```sql
-- Example: fix a wrong height recorded in the field
UPDATE trees."Trees" SET "Height_m" = 22.5 WHERE "tree_id" = 1234;

-- Example: backfill a missing DBH on a stem
UPDATE trees."Stems" SET "DBH_cm" = 31.2 WHERE "stem_id" = 5678;
```

**Automatic audit logging:** AFTER UPDATE triggers on `trees.Trees`, `trees.Stems`, `trees.PhenologyObservations`, `environments.Environments`, and `pointclouds.PointClouds` log every change to `shared.AuditLog`. The log records the field name, old value, new value, timestamp, and the GoTrue user ID of whoever made the change. No manual action is required. `trees.Deadwood` and `trees.GroundVegetation` moved to their own `forest_floor` schema and are not audited (site/plot-level surveys, not per-tree records).

Audited fields:

| Table | Fields automatically logged |
|-------|----------------------------|
| `trees.Trees` | `Height_m`, `crown_width_m`, `health_score`, `tree_status_id` |
| `trees.Stems` | `DBH_cm`, `stem_height_m` |
| `environments.Environments` | `avg_temperature_c`, `stress_factor` |
| `pointclouds.PointClouds` | `processing_status` |
| `trees.PhenologyObservations` | `phenophase_status`, `intensity_percent` |

Changes to other fields (e.g., `species_id`, `measurement_date`) are not automatically audited by the trigger. To add a field, edit the `WHEN 'trees' THEN` block in `shared.audit_update_trigger()` (see `AGENTS.md` §"Schema Migrations" for how to ship the change) — follow the existing pattern:
```sql
IF OLD."YourField" IS DISTINCT FROM NEW."YourField" THEN
    PERFORM shared.create_audit_log(
        'Trees', record_id, 'YourField',
        OLD."YourField"::TEXT, NEW."YourField"::TEXT,
        NULL, 'field_update'
    );
END IF;
```

After editing the file, apply the change with `python scripts/admin/reset_database.py` (wipes data) or by running the updated function body directly in Studio → SQL Editor.

**Querying audit history:**

```sql
-- All changes to a specific tree variant
SELECT * FROM shared.get_audit_history('Trees', 1234);

-- Recent changes across all tables
SELECT * FROM shared.recent_changes ORDER BY "Timestamp" DESC LIMIT 50;
```

**Reverting a change:**

```sql
-- Revert a specific audit entry (creates a compensating log entry)
SELECT shared.revert_field_change(<audit_id>, 'Corrected data entry error');
```
