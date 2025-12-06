# Aquarius Data Sync Testing Guide

## Prerequisites

✅ VPN connected to University network (required to access Aquarius API)
✅ Supabase stack running: `cd docker && docker compose up -d`
✅ All services healthy: `docker compose ps`

## Test 1: Manual Aquarius Sync (Basic Test)

### Step 1: Verify Aquarius Connectivity

Test direct connection to Aquarius API:

```bash
curl -X POST "http://fuhys006.public.ads.uni-freiburg.de/AQUARIUS/Publish/v2/session" \
  -H "Content-Type: application/json" \
  -d '{
    "Username": "Ecosense",
    "EncryptedPassword": "***REMOVED-SECRET***"
  }'
```

Expected response: A token string (wrapped in quotes)
```json
"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
```

If you get connection refused or timeout, VPN is not connected properly.

---

### Step 2: Trigger ecosense-ingest Function

Get your SERVICE_ROLE_KEY:

```bash
cd docker
grep SERVICE_ROLE_KEY .env
```

Then trigger the function:

```bash
export SERVICE_ROLE_KEY="<your_key_from_.env>"

curl -X POST "http://localhost:54321/functions/v1/ecosense-ingest?days_back=7" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json"
```

### Expected Successful Response

```json
{
  "success": true,
  "count": 1523,
  "sensors": 4,
  "message": "Aquarius data sync completed"
}
```

The `count` field shows total sensor readings inserted.

---

### Step 3: Verify Data Was Imported

Check that sensors were created:

```bash
docker exec -it dftdb-db psql -U postgres -c \
  "SELECT SensorID, SerialNumber, SensorModel, IsActive FROM sensor.sensors LIMIT 5;"
```

Expected output:
```
 sensorid |                        serialnumber                        |  sensormodel  | isactive
----------+-------------------------------------------------------------+---------------+----------
        1 | DouglasFir_Mixed_5_Total_SapFlow@Ecosense_MixedPlot       | Ecosense Node | t
        2 | DouglasFir_Mixed_5_edge_E@Ecosense_MixedPlot              | Ecosense Node | t
        3 | DouglasFir_Mixed_5_Dendrometer@Ecosense_MixedPlot         | Ecosense Node | t
```

Check that readings were inserted:

```bash
docker exec -it dftdb-db psql -U postgres -c \
  "SELECT COUNT(*) as reading_count FROM sensor.sensorreadings WHERE CreatedBy = 'ecosense-ingest-function';"
```

Expected output: `reading_count` should be > 0 (e.g., 1500+)

---

## Test 2: Verify Improvements

### Test 2.1: Error Handling - Bad Authentication

```bash
curl -X POST "http://localhost:54321/functions/v1/ecosense-ingest?days_back=7" \
  -H "Authorization: Bearer invalid_token" \
  -H "Content-Type: application/json"
```

Expected response (401):
```json
{
  "error": "Unauthorized",
  "code": "INVALID_AUTH"
}
```

Status should be **401** (not 500).

---

### Test 2.2: Input Validation - Invalid days_back

```bash
export SERVICE_ROLE_KEY="<your_key>"

# Test with days_back > 365 (should be clamped to 365)
curl -X POST "http://localhost:54321/functions/v1/ecosense-ingest?days_back=400" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"

# Test with days_back < 1 (should be clamped to 1)
curl -X POST "http://localhost:54321/functions/v1/ecosense-ingest?days_back=0" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

Both should work and clamp the value (logs will show `days_back=365` and `days_back=1` respectively).

---

### Test 2.3: Parallel API Calls (Performance)

Run a sync and observe logs to see concurrency:

```bash
docker logs -f dftdb-edge-functions 2>&1 | grep "ecosense-ingest\|Fetched\|Upserting"
```

You should see:
```
ecosense-ingest function started
Starting ecosense data sync (days_back=7)
Connected to Aquarius API
Fetched 4 time series descriptions
Filtered to 4 relevant sensors
Upserting 4 sensors
Import complete: 1523 points inserted from 4 sensors
```

The improved version fetches all sensor metadata in parallel (vs sequential), so it completes faster.

---

### Test 2.4: Timeout Handling

The system has a 30-second timeout. If Aquarius API is slow:

```bash
docker logs dftdb-edge-functions 2>&1 | grep -i timeout
```

If timeout occurs, you should see:
```json
{
  "error": "Import failed",
  "code": "TIMEOUT",
  "message": "Aquarius connection timeout (30000ms)"
}
```

Status code should be **408** (Request Timeout), not 500.

---

## Test 3: CSV Importer with Cached Data

Now that you have sensors in the database, test the improved CSV importer with real data.

### Step 1: Prepare a Test CSV

Create a simple test file at `data/test_trees.csv`:

```csv
species_name,gps_latitude,gps_longitude
Beech,47.8851,8.0881
Oak,47.8852,8.0882
Spruce,47.8850,8.0880
```

### Step 2: Run the Importer with Caching

```bash
cd scripts/import-data

# Make sure the script is executable
chmod +x import-docker.sh

# Run the importer (will show cache loading)
./import-docker.sh --csv /data/test_trees.csv --table Trees --created-by "test_user_$(date +%s)" --interactive
```

When prompted for column mapping:
```
Column: 'species_name'
Sample values: ['Beech', 'Beech', 'Beech']
Map to: SpeciesID

Column: 'gps_latitude'
Sample values: [47.8851, 47.8852, 47.8850]
Map to: lat

Column: 'gps_longitude'
Sample values: [8.0881, 8.0882, 8.0880]
Map to: lon
```

### Expected Output

The improved importer should show:

```
📦 Pre-loading reference data...
  ✓ Cached 5 species names
  ✓ Cached 3 locations
  ✓ Cached 13 sensor types

📋 Column Mapping Summary:
  species_name                       → SpeciesID
  gps_latitude                       → lat
  gps_longitude                      → lon

⚠️  Proceed with import to 'Trees'? (yes/no): yes

📥 Importing 3 rows...
  ✓ Inserted 10 rows...

============================================================
📊 Import Summary
============================================================
✅ Successfully inserted: 3
⏭️  Skipped: 0
❌ Errors: 0
============================================================
```

Notice the **"Pre-loading reference data"** section - this is the new caching feature that avoids N+1 queries.

---

### Step 3: Verify Trees Were Inserted

```bash
docker exec -it dftdb-db psql -U postgres -c \
  "SELECT TreeID, Height_m, SpeciesID, LocationID FROM trees.trees WHERE CreatedBy LIKE 'test_user_%' LIMIT 5;"
```

Expected output: Your test trees with proper SpeciesID and LocationID values.

---

## Test 4: Docker Network Detection

Test the improved import-docker.sh script:

```bash
cd scripts/import-data

# Should detect the network automatically and show:
./import-docker.sh --help 2>&1 | head -5
```

Should show:
```
Detected Docker network: digital_forest_twin_db_default
```

Try stopping docker and running the script - it should show helpful error:

```bash
cd docker
docker compose down

# Then try to import
cd ../scripts/import-data
./import-docker.sh --csv /data/test.csv --table Trees --created-by test 2>&1 | head -5
```

Should show:
```
❌ Error: Supabase stack is not running
   Start it with: cd /home/maximilian_sperlich/git/digital_twin_db/docker && docker compose up -d
```

---

## Test 5: Dry-Run Validation

Test the improved dry-run functionality:

```bash
cd scripts/import-data

./import-docker.sh \
  --csv /data/test_trees.csv \
  --table Trees \
  --created-by "test_dry_run" \
  --dry-run \
  --interactive
```

Should show:
```
🔍 DRY RUN MODE - Validating all rows without inserting...
  ✓ Successfully validated 3 rows
  ✗ Would skip 0 rows
```

And verify NO data was inserted:

```bash
docker exec -it dftdb-db psql -U postgres -c \
  "SELECT COUNT(*) FROM trees.trees WHERE CreatedBy = 'test_dry_run';"
```

Should return: `0`

---

## Test 6: Error Scenarios

### Test 6.1: Invalid Species Name

Create `data/bad_trees.csv`:

```csv
species_name,gps_latitude,gps_longitude
InvalidSpecies,47.8851,8.0881
Beech,47.8852,8.0882
```

Run importer:

```bash
./import-docker.sh --csv /data/bad_trees.csv --table Trees --created-by "test_errors" --interactive
```

When prompted, map columns same as before. Expected output:

```
📊 Import Summary
============================================================
✅ Successfully inserted: 1
⏭️  Skipped: 1
❌ Errors: 0

⚠️  Error Details:
  - Row 2: Species 'InvalidSpecies' not found
```

Notice:
- Row with invalid species was **skipped** (not inserted with NULL FK)
- Error message is **specific** with row number
- No partial data left in database

---

### Test 6.2: Bad Coordinates

Create `data/bad_coords.csv`:

```csv
species_name,gps_latitude,gps_longitude
Beech,95.5,8.0881
Spruce,47.8850,999.9
```

Expected output:

```
📊 Import Summary
============================================================
✅ Successfully inserted: 0
⏭️  Skipped: 2
❌ Errors: 0

⚠️  Error Details:
  - Row 2: Coordinates out of bounds: lat=95.5, lon=8.0881
  - Row 3: Coordinates out of bounds: lat=47.8850, lon=999.9
```

---

## Performance Benchmarks

### Benchmark 1: Ecosense-Ingest

Test with real Aquarius data:

```bash
time curl -X POST "http://localhost:54321/functions/v1/ecosense-ingest?days_back=7" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -w "\nHTTP Status: %{http_code}\n"
```

**Before improvements**: ~30-60 seconds (N+1 queries, sequential API calls)
**After improvements**: ~5-15 seconds (batched queries, parallel API calls)

Expected time: **< 15 seconds**

---

### Benchmark 2: CSV Import

Prepare a larger test CSV with 100 rows, then:

```bash
time ./import-docker.sh \
  --csv /data/large_trees.csv \
  --table Trees \
  --created-by "benchmark_$(date +%s)" \
  --interactive
```

**Before improvements**: ~70 seconds (700+ database queries)
**After improvements**: ~10-20 seconds (3 initial queries + cache)

Expected time: **< 30 seconds for 100 rows**

---

## Troubleshooting

### Issue: Connection refused on Aquarius

```
Error: Failed to connect to Aquarius: connection refused
```

**Solution**: Check VPN is connected:

```bash
ping fuhys006.public.ads.uni-freiburg.de
```

If no response, connect to university VPN.

---

### Issue: "No Ecosense sensors found"

```json
{
  "success": true,
  "count": 0,
  "sensors": 0,
  "message": "No Ecosense sensors found matching filter criteria"
}
```

This means Aquarius API is reachable but has no matching sensors. Check:

1. Aquarius data is available (may be seasonal or offline)
2. Sensor names start with "Ecosense_"
3. Parameters match mapping (Sapflow, StemRadialVar_Volt, etc.)

---

### Issue: CSV import fails to connect to database

```
❌ Error: Supabase stack is not running
```

**Solution**:

```bash
cd docker
docker compose up -d
docker compose ps  # Verify all services are healthy
```

Wait 30 seconds for all services to initialize.

---

### Issue: Docker image build fails

```
ERROR: failed to solve with frontend dockerfile.v0
```

**Solution**: Rebuild the image:

```bash
cd scripts/import-data
docker rmi dftdb-csv-importer 2>/dev/null || true
./import-docker.sh --help  # Will rebuild automatically
```

---

## Summary Checklist

- [ ] VPN connected (ping Aquarius API succeeds)
- [ ] Supabase stack running (`docker compose ps` shows all healthy)
- [ ] Test 1: Aquarius sync completes successfully
- [ ] Test 2.1: Bad auth returns 401
- [ ] Test 2.2: Input validation works (days_back clamped)
- [ ] Test 2.3: Parallel API calls visible in logs
- [ ] Test 3: CSV importer shows "Pre-loading reference data"
- [ ] Test 3: Trees imported with correct SpeciesID/LocationID
- [ ] Test 4: Docker network detected automatically
- [ ] Test 5: Dry-run validates but doesn't insert
- [ ] Test 6.1: Invalid species skipped, not inserted
- [ ] Test 6.2: Bad coordinates caught with clear error
- [ ] Performance: Ecosense sync < 15 seconds
- [ ] Performance: CSV import 100 rows < 30 seconds

All tests passing ✅ = System is production-ready!
