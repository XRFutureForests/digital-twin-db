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

Read access covers every public view: `species`, `locations`, `trees`, `ue_trees`, `scenarios`, `variant_types`, `sensors`, `sensor_readings`, `growth_simulations`, `simulation_runs`, and all morphology lookups.

---

## Write access — requires an account

Writing data (INSERT / UPDATE / DELETE) requires an authenticated JWT. Three paths:

### Option A — the portal (easiest; no tools needed)

1. Ask the curator of your team for an account (see [User management](#user-management) below).
2. Sign in at **<https://dt.unr.uni-freiburg.de/portal/account/>** and choose your own password.
3. Use **<https://dt.unr.uni-freiburg.de/portal/data/>**: pick a table, add a row through the
   form or paste a CSV (all rows in one transaction), or click a row to correct it.

The forms are generated from the API's own OpenAPI description, so every public view is
there. The database decides what your role may do; an update it refuses comes back as
"nothing was saved", not as a fake success.

Supabase Studio is **not** a write path for colleagues: it logs in with the shared
`DASHBOARD_PASSWORD`, acts as `supabase_admin`, and is reachable only through an SSH
tunnel on the server.

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
| `scripts/import/ingest_sensor_data.py` | Sync sensors + readings from any provider (see [aquarius-connector](https://gitlab.uni-freiburg.de/xr-future-forests-lab/aquarius-connector) for Aquarius) |
| `scripts/import/link_sensors_to_trees.py` | Link sensors to their nearest tree |
| [silva-connector](../../silva-connector) (separate repo, R) | Run SILVA and write `trees.simulation_runs` + `trees.growth_simulations` + the variant chain, over libpq |
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

### Creating accounts — curators, in the portal

Since 2026-10-30 (migration `20261030100000`) team leads manage their own people. On
**<https://dt.unr.uni-freiburg.de/portal/account/>** a `curator` can create an account,
switch accounts between read-only and `contributor`, and reset passwords; an `admin` can
also grant `curator` and `admin`. Nobody changes their own role.

The page calls four `SECURITY DEFINER` functions that check the caller's role claim
themselves — `public.list_accounts()`, `create_account(p_email, p_role)`,
`set_account_role(p_email, p_role)`, `reset_account_password(p_email)` — so the browser
holds only the signed-in user's token. Each create, role change and reset is written to
`shared.account_events`, which curators and admins can read (the page shows the last 20).

Passwords are generated and shown **once** to the curator, who hands them over personally,
because mail from dt.unr does not leave the host (outbound SMTP to the university relays is
closed). The account is flagged `must_change_password`; the portal asks the holder to change
it, which they can do themselves (`PUT /auth/v1/user` with their own token). A reset ends
every session of that account. A role change applies at the next sign-in or token refresh
(at most `JWT_EXPIRY`, an hour).

Self-signup is closed: `DISABLE_SIGNUP=true` in `docker/.env`.

### Creating a user account (admin, from a shell)

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
| `authenticated`, no role claim (**read-only**) | A new account until a curator grants a role | SELECT; its own job history; no writes (since 2026-10-30 — before, it could write the metadata tables) |
| `authenticated` + `role: contributor` (**Contributor**) | Field data collectors | Everything above, plus full CRUD on metadata tables (species, scenarios, locations, plots, sensors, scanners, management/disturbance events, campaigns, processes, …), INSERT on field-data tables, `request_job()` |
| `authenticated` + `role: curator` (**Curator**) | Team leads, trusted data managers | Everything above, plus UPDATE/DELETE on field-data tables, every job, and managing read-only/contributor accounts |
| `authenticated` + `role: admin` (**Administrator**) | Lab administrators | Everything above, plus granting `curator` and `admin` |
| `service_role` | Max / import scripts | Full access, bypasses RLS; never share externally |

Field-data tables are the ones where a bad edit or delete actually costs something (cited measurements, growth-sim inputs): `Trees`, `Stems`, `PointClouds`, `Environments`, `Images`, `sensor_readings`, `phenology_observations`, `Deadwood`, `ground_vegetation`. Everything else stays full-CRUD for any `authenticated` user regardless of role claim — see the `is_admin()` / `is_contributor()` / `is_curator()` helpers and their policies in `docker/volumes/db/init/10-baseline-schema.sql`.

**Never share `SERVICE_ROLE_KEY` with external collaborators.** Give them an account (a curator creates it in the portal) for write access instead.

Read-only views (`ue_trees`, `growth_simulations`, `simulation_runs`, morphology lookups) are SELECT-only even for authenticated users. Writes to those domains go through the underlying tables via the import scripts and silva-connector.

### Assigning a role tier

An account without a `role` claim is read-only. The normal route is the portal's account page
(curators: read-only ↔ contributor; admins: any tier) or `public.set_account_role()`. From a
shell, `create-user.sh --set-role`, or directly (run as `service_role`, e.g. in Studio → SQL Editor):

```sql
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "curator"}'::jsonb
WHERE email = 'someone@example.com';
```

Valid values: `admin`, `curator`, `contributor`. No claim = read-only.

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

**Automatic audit logging:** AFTER UPDATE triggers on `trees.trees`, `trees.stems`, `trees.phenology_observations`, `environments.environments`, and `pointclouds.point_clouds` log every change to `shared.audit_log`. The log records the field name, old value, new value, timestamp, and the GoTrue user ID of whoever made the change. No manual action is required. `forest_floor.deadwood` and `forest_floor.ground_vegetation` moved to their own `forest_floor` schema and are not audited (site/plot-level surveys, not per-tree records).

Audited fields:

| Table | Fields automatically logged |
|-------|----------------------------|
| `trees.trees` | `Height_m`, `crown_width_m`, `health_score`, `tree_status_id` |
| `trees.stems` | `DBH_cm`, `stem_height_m` |
| `environments.environments` | `avg_temperature_c`, `stress_factor` |
| `pointclouds.point_clouds` | `processing_status` |
| `trees.phenology_observations` | `phenophase_status`, `intensity_percent` |

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
SELECT shared.revert_field_change(<audit_log_id>, 'Corrected data entry error');
```
