# Documentation vs Implementation Audit & Implementation Plan

**Date:** 2026-03-11  
**Auditor:** Automated review of running Docker stack against project documentation

---

## Audit Summary

### Infrastructure Status

| Component | Status | Details |
|-----------|--------|---------|
| Docker containers | **14/14 running, all healthy** | All services operational |
| Database (PostgreSQL 15 + PostGIS) | **Healthy** | Initialized 2026-03-10 |
| API Gateway (Kong) | **Healthy** | Ports 8000/8443 exposed |
| PostgREST | **Healthy** | REST API functional |
| Edge Functions (Deno) | **Running** | hello + ecosense-ingest deployed |
| Studio | **Healthy** | Port 54323 |
| Auth, Realtime, Storage | **Healthy** | All operational |

### Data Status

| Table/Category | Count | Notes |
|----------------|-------|-------|
| Trees | 1,504 | With height: 1,204 (80%) |
| Stems | 1,504 | One stem per tree |
| Sensors | 1,367 | From Aquarius integration |
| Sensor Readings | 4,203,438 | ~4.2M readings |
| Species (lookup) | 12 | Seeded |
| Locations | 15 | Seeded |
| Plots | 18 | Seeded |
| Morphology lookups | **0 across all 9 tables** | CSV data exists, not loaded |

---

## Discrepancies Found

### CRITICAL: Database Drift from Init Scripts

**Root cause:** The database was initialized once, then init SQL files were updated. PostgreSQL's Docker entrypoint skips `/docker-entrypoint-initdb.d/` when data already exists ("Skipping initialization"). Three categories of changes were never applied:

---

### D1. Morphology Lookup Tables Empty (9 tables, 0 rows)

**What happened:** Morphology lookup data was added to `30-load-lookup-tables.sql` after the database was first created. The CSV files are correctly mounted at `/var/lib/postgresql/lookups/` inside the container, but the INSERT statements were never executed.

**Affected tables:**

- `trees.axisstructures` (CSV: 2 rows)
- `trees.branchelongationhabits` (CSV: 2 rows)
- `trees.crownarchitectures` (CSV: 5 rows)
- `trees.crownshapes` (CSV: 12 rows)
- `trees.geometriccrownsolids` (CSV: 10 rows)
- `trees.growthforms` (CSV: 4 rows)
- `trees.growthorientations` (CSV: 2 rows)
- `trees.phanerophyteheightclasses` (CSV: 5 rows)
- `trees.shootelongationtypes` (CSV: 4 rows)

**Fix needed:** Implementation (load the data into the running database)  
**Documentation:** Correct (data/lookups CSVs and seed SQL are accurate)

---

### D2. Refresh Lookup Functions Not Loaded

**What happened:** `31-refresh-lookup-functions.sql` defines `shared.refresh_lookup()` and `shared.refresh_all_lookups()` (supporting 21+ tables), but these functions were never applied to the running database.

**Verified:** `SELECT shared.refresh_lookup('crown_architectures')` returns: `ERROR: function shared.refresh_lookup(unknown) does not exist`

**Fix needed:** Implementation (execute `31-refresh-lookup-functions.sql` against the running database)  
**Documentation:** Correct

---

### D3. Morphology Tables Missing RLS Policies

**What happened:** The 9 morphology lookup tables have `relrowsecurity = false`. The existing lookup tables (treestatus, tapertypes, etc.) have RLS enabled with "viewable by everyone" SELECT policies. The morphology tables were added in `18-tree-morphology-schema.sql` but corresponding RLS policies were not added to `20-rls-policies.sql`.

**Impact:** Without RLS, these tables are accessible to the DB superuser but behavior through PostgREST may be inconsistent.

**Fix needed:** Implementation (add RLS policies) + Documentation (update `20-rls-policies.sql`)

---

### D4. Morphology Tables Missing Public API Views

**What happened:** All database tables are exposed to the REST API via public views in `24-public-api-views.sql`. The morphology lookup tables have no corresponding public views, so they return PGRST205 errors via the API.

**Verified:** `GET /rest/v1/axisstructures` returns `{"code":"PGRST205","message":"Could not find the table"}`

**Fix needed:** Implementation (add public views) + Documentation (update `24-public-api-views.sql`)

---

### D5. HeightClassID Not Populated

**What happened:** `18-tree-morphology-schema.sql` creates a trigger `trg_trees_assign_height_class` that auto-assigns `HeightClassID` based on tree height. However, since the `phanerophyteheightclasses` lookup table is empty (D1), the trigger cannot assign any values. Additionally, existing trees (inserted before the trigger existed) were never retroactively updated.

**Verified:** 0 out of 1,504 trees have a HeightClassID despite 1,204 having height_m values.

**Fix needed:** Implementation (load lookup data first, then run retroactive update)

---

### D6. `refresh_lookups.py` Missing Morphology Support

**What happened:** The Python admin script only supports 6 lookup tables (species, locations, sensor_types, tree_status, soil_types, climate_zones). The 9 morphology tables and several other lookups (scenarios, variant_types, bark_characteristics, branching_patterns, straightness_types, taper_types) are not supported.

**Fix needed:** Implementation (update the Python script)  
**Documentation:** The `scripts/README.md` should be updated

---

### D7. `deployment-guide.md` Missing Init File References

**What happened:** The deployment guide lists init SQL files 10-17 and 20+, but does not mention `18-tree-morphology-schema.sql` (added later). The guide also references old file names (e.g., `18a-seed-lookup-data.sql`) that no longer exist.

**Fix needed:** Documentation (update the deployment guide)

---

### D8. Ecosense-Ingest Edge Function: "Too Many Open Files"

**What happened:** The edge function processes 1,367 sensors in batches of 10 concurrent API requests. Despite the batching, the Deno runtime inside Docker hits OS file descriptor limits. The function succeeds partially (returns `{"success":true,"count":0}`) but produces errors for many sensors.

**Error:** `error sending request: client error (Connect): dns error: Too many open files (os error 24)`

**Fix needed:** Implementation (reduce concurrency or increase ulimits in docker-compose.yml)

---

### D9. Implementation Plan Has Incorrect Table/Column References

**What happened:** `implementation-plan.md` references non-existent table/column names:

- `trees.tree_variants` (actual: `trees.Trees`)
- `stem_id` (actual: `StemID`)
- `species_id` (actual: `SpeciesID`)
- Lowercase table names throughout (actual: PascalCase)

**Fix needed:** Documentation (update implementation-plan.md to match actual schema)

---

### D10. Species Table Missing Allometric Parameters

**What happened:** `implementation-plan.md` Phase 1 specifies adding allometric columns to `shared.species` (height_equation_type, height_param_a/b/c, biomass_param_a/b/c, carbon_fraction, wood_density). These columns do not exist in the running database.

**Current species columns:** SpeciesID, CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance, IsDeciduous, CreatedAt, UpdatedAt

**Decision needed:** Is this a planned future enhancement or should it be implemented now?

**Fix needed:** Dependent on project priorities (documented as Phase 1 in implementation plan)

---

### D11. Calculation Functions Not Implemented

**What happened:** `implementation-plan.md` documents SQL code for `calculate_height()`, `calculate_biomass()`, `calculate_carbon()`, and `assess_wood_quality()`. None of these exist in the database. Additionally, `biomass_kg` and `carboncontent_kg` columns in `trees.trees` are all NULL (0/1,504).

**Decision needed:** Same as D10 - planned Phase 1 work, not a bug.

---

### VERIFIED CORRECT (No Action Needed)

| Area | Status |
|------|--------|
| 6 database schemas (shared, pointclouds, trees, sensor, environments, imagery) | Matches docs |
| Variant-based temporal lineage (TreeEntityID + VariantID) | Working correctly |
| Dual geometry (Position WGS84 + PositionOriginal) | Implemented |
| Audit trail (CreatedBy, UpdatedBy, timestamps + AuditLog) | Working |
| PostGIS geometry columns | Functional |
| RLS policies on existing tables (96 policies across schemas) | Correct |
| Public API views for existing tables (20 views) | All accessible |
| Sensor-tree linking | Schema exists, data importable |
| Edge function: hello | Returns `{"message":"Hello from Edge Functions!"}` |
| PGRST_DB_SCHEMAS includes all needed schemas | Correct (imagery via public views) |
| Kong API gateway routing | Correct for REST, auth, graphql, realtime |
| Docker volume mounts for init SQL, lookups, functions | All correct |

---

## Implementation Plan

### Phase A: Fix Database Drift (Priority: CRITICAL, Effort: Low)

These are initialization gaps that prevent the system from functioning as designed.

#### A1. Load Refresh Functions into Database

```bash
# Execute 31-refresh-lookup-functions.sql against running DB
docker compose exec db psql -U supabase_admin -d postgres \
  -f /docker-entrypoint-initdb.d/31-refresh-lookup-functions.sql
```

#### A2. Load Morphology Lookup Data

```bash
# Execute the morphology sections of 30-load-lookup-tables.sql
# Or after A1, use the refresh functions:
docker compose exec db psql -U supabase_admin -d postgres -c "
  SELECT shared.refresh_all_lookups();
"
```

#### A3. Add RLS Policies for Morphology Tables

Add to `20-rls-policies.sql` and execute:

```sql
-- For each morphology lookup table:
ALTER TABLE trees.axisstructures ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.branchelongationhabits ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.crownarchitectures ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.crownshapes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.geometriccrownsolids ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.growthforms ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.growthorientations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.phanerophyteheightclasses ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.shootelongationtypes ENABLE ROW LEVEL SECURITY;

-- SELECT policy for each (same pattern as treestatus, tapertypes):
CREATE POLICY "Morphology lookup tables are viewable by everyone"
  ON trees.axisstructures FOR SELECT USING (true);
-- ... repeat for all 9 tables
```

#### A4. Add Public API Views for Morphology Tables

Add to `24-public-api-views.sql` and execute:

```sql
CREATE OR REPLACE VIEW public.axisstructures AS SELECT * FROM trees.axisstructures;
CREATE OR REPLACE VIEW public.branchelongationhabits AS SELECT * FROM trees.branchelongationhabits;
CREATE OR REPLACE VIEW public.crownarchitectures AS SELECT * FROM trees.crownarchitectures;
CREATE OR REPLACE VIEW public.crownshapes AS SELECT * FROM trees.crownshapes;
CREATE OR REPLACE VIEW public.geometriccrownsolids AS SELECT * FROM trees.geometriccrownsolids;
CREATE OR REPLACE VIEW public.growthforms AS SELECT * FROM trees.growthforms;
CREATE OR REPLACE VIEW public.growthorientations AS SELECT * FROM trees.growthorientations;
CREATE OR REPLACE VIEW public.phanerophyteheightclasses AS SELECT * FROM trees.phanerophyteheightclasses;
CREATE OR REPLACE VIEW public.shootelongationtypes AS SELECT * FROM trees.shootelongationtypes;

-- Grant access
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;
```

#### A5. Backfill HeightClassID for Existing Trees

After A2 (lookup data loaded):

```sql
-- Trigger the height class assignment for existing trees
UPDATE trees.trees SET heightclassid = (
  SELECT phc.heightclassid
  FROM trees.phanerophyteheightclasses phc
  WHERE trees.trees.height_m >= phc.minheight_m
    AND (phc.maxheight_m IS NULL OR trees.trees.height_m < phc.maxheight_m)
) WHERE height_m IS NOT NULL;
```

---

### Phase B: Fix Edge Function Issue (Priority: HIGH, Effort: Low)

#### B1. Fix ecosense-ingest "Too Many Open Files"

Options (pick one):

1. **Reduce API_CONCURRENCY_LIMIT** from 10 to 3-5 in `ecosense-ingest/index.ts`
2. **Add ulimits to docker-compose.yml** for the edge-functions service:

   ```yaml
   edge-functions:
     ulimits:
       nofile:
         soft: 65536
         hard: 65536
   ```

3. **Add connection reuse** - ensure the Deno HTTP client reuses connections

---

### Phase C: Update Documentation (Priority: MEDIUM, Effort: Low)

#### C1. Update `deployment-guide.md`

- Add `18-tree-morphology-schema.sql` to the init files table
- Remove references to old file names (`18a-seed-lookup-data.sql` etc.)
- Add section on handling database drift after init file updates

#### C2. Update `implementation-plan.md`

- Fix table/column name references to match actual PascalCase schema
- Mark Phase 1 status as "Planned" (not "Active")
- Add note that calculation functions require species parameter extension first

#### C3. Update `database-schema.md`

- Add morphology lookup tables section
- Document the new columns on trees.trees (heightclassid, crownarchitectureid, etc.)

#### C4. Update `api-quick-reference.md`

- Add morphology lookup table endpoints (after Phase A views are created)

---

### Phase D: Update `refresh_lookups.py` (Priority: MEDIUM, Effort: Low)

#### D1. Add Missing Lookup Tables to Python Script

Add support for all 21+ lookup tables that the SQL `refresh_lookup()` function handles:

- 9 morphology tables (axis_structures, crown_architectures, etc.)
- bark_characteristics, branching_patterns, straightness_types, taper_types
- scenarios, variant_types

---

### Phase E: Core Calculations (Priority: LOW now, as per implementation-plan.md Phase 1)

These are documented but not yet implemented. They are feature additions, not bugs.

#### E1. Extend Species Table with Allometric Parameters

#### E2. Implement `calculate_height()` Function

#### E3. Implement `calculate_biomass()` Function

#### E4. Implement `calculate_carbon()` Function

#### E5. Implement `assess_wood_quality()` Function

**Prerequisite:** E1 must be completed first. Implementation plan code samples need column name corrections before use.

---

## Recommended Execution Order

```
Phase A (A1 → A2 → A3 → A4 → A5)  ← Fix database drift, ~30 minutes
Phase B (B1)                        ← Fix edge function, ~15 minutes
Phase C (C1-C4)                     ← Update docs, ~1 hour
Phase D (D1)                        ← Update Python script, ~30 minutes
Phase E (E1-E5)                     ← New features, per implementation-plan.md timeline
```

---

## Decision Points for Project Owner

1. **Phase A execution:** Should we apply the fixes immediately, or wait for a scheduled maintenance window?
2. **Phase B approach:** Reduce concurrency (safest) vs increase ulimits (higher throughput)?
3. **Phase E priority:** Should calculation functions be implemented now or remain in planning?
4. **Database reset consideration:** Would a full `docker compose down -v && docker compose up -d` be acceptable? This would re-run all init scripts cleanly but would require re-importing tree and sensor data.
