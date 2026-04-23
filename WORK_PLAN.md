# digital-twin-db — Work Plan

Linear: [XRFF team](https://linear.app/geosense-ufr/team/XRFF/all)

**Last updated:** 2026-04-23

---

## Phase 1 — Foundation (NOW — Days 1-2)

| Priority | Issue | Status | Owner | Effort |
|---|---|---|---|---|
| 🔴 | [XRFF-72](https://linear.app/geosense-ufr/issue/XRFF-72) Fix sensor DateTime timezone | ✅ DONE | Max | 1-2h |
| 🔴 | [XRFF-133](https://linear.app/geosense-ufr/issue/XRFF-133) Add GBIF taxon key to shared.species | ✅ DONE | Max | 1-2h |
| 🟡 | [XRFF-100](https://linear.app/geosense-ufr/issue/XRFF-100) Run sensor import to prod DB | ✅ DONE | Max | 2h |
| 🟡 | [XRFF-39](https://linear.app/geosense-ufr/issue/XRFF-39) Fill missing tree heights via allometry | ✅ DONE (blocked by XRFF-131) | Max | 3-4h |

---

## Phase 2 — Sensor Pipeline + DB Enhancements (Days 3-5)

Depends on Phase 1 complete.

| Issue | Status | Description | Depends On |
|---|---|---|---|
| [XRFF-100](https://linear.app/geosense-ufr/issue/XRFF-100) | ⬜ TODO | Run sensor data import to prod DB | XRFF-72 |
| [XRFF-106](https://linear.app/geosense-ufr/issue/XRFF-106) | ⬜ TODO | Real-time sensor pipeline to Unreal | XRFF-100 |
| [XRFF-107](https://linear.app/geosense-ufr/issue/XRFF-107) | ⬜ TODO | Sensor data on tree objects in VR | XRFF-106 |
| [XRFF-36](https://linear.app/geosense-ufr/issue/XRFF-36) | ⬜ TODO | Inventory-driven growpy generation | XRFF-133 |

---

## Issue Sequence

```
XRFF-72  (fix DateTime timezone — 🔴 HIGH, Day 1)
    └─► XRFF-100 (run sensor data import into prod DB — 🔴 HIGH, Day 2)
            └─► XRFF-106 (real-time sensor pipeline to Unreal — 🟡 MEDIUM, Day 3-5)
                XRFF-107 (sensor data on tree objects in VR)
                dashboard sensor display

XRFF-39  (fill missing tree heights — 🔴 HIGH, Day 2, parallel track)
    └─► full inventory spawn without gaps

XRFF-133 (add GBIF taxon key to shared.species — 🔴 HIGH, Day 1, parallel track)
    └─► XRFF-36 (inventory-driven growpy generation — 🟡 MEDIUM, Day 3-5)
```

---

## XRFF-72 — Fix DateTime timezone handling (Medium, assignee: Max)

**Status:** ✅ DONE — fixed in `scripts/import/import_sensor_data.py`

**Context:** Aquarius exports timestamps. `import_sensor_data.py` inserts them into `sensor.SensorReadings`. The issue: UE DataTable imports sap flow CSV and shifts timestamps by +0200 (local timezone applied twice, or UTC offset not stripped).

**Two aspects to fix:**

### A) Python import script (digital-twin-db side)

In `scripts/import/import_sensor_data.py`, when parsing Aquarius timestamps before DB insertion, ensure all datetimes are explicitly UTC:

```python
from datetime import timezone
import dateutil.parser

# When parsing Aquarius timestamps:
ts = dateutil.parser.parse(raw_timestamp)
if ts.tzinfo is None:
    ts = ts.replace(tzinfo=timezone.utc)
else:
    ts = ts.astimezone(timezone.utc)
```

Verify: after import, run `SELECT MIN(timestamp), MAX(timestamp) FROM sensor.sensor_readings;` — timestamps should be in UTC (no +0200 offset).

### B) UE DataTable import (Unreal side — Paul)

In UE Editor: **Edit → Editor Preferences → Region & Language → Display Timezone → set to UTC**. Applies globally to all CSV DateTime imports. Without this, UE shifts imported timestamps by the local timezone offset.

---

## XRFF-39 — Fill missing tree heights (High, assignee: Max)

**Status:** ✅ DONE — `scripts/import/fill_missing_heights.py` written; blocked by XRFF-131 (pylometree on PyPI)

**Context:** ~20% of Ecosense inventory records have `Height_m IS NULL`. PCG graph selects the wrong growth-stage asset variant for these trees. `pylometree` H-D models can predict height from species + DBH.

**Prerequisite:** XRFF-131 (pylometree published to PyPI) complete.

### Steps

**1. Write `scripts/import/fill_missing_heights.py`**

```python
#!/usr/bin/env python3
"""Fill NULL Height_m values in trees.Trees using pylometree H-D allometric models."""

import psycopg2
from pylometree.models.hd import fit_hd_model, predict_height
from pylometree.yield_tables import get_yield_table

# Connect to DB
conn = psycopg2.connect(...)

# Fetch trees with missing heights (include DBH + species for allometric prediction)
cur = conn.cursor()
cur.execute("""
    SELECT t.VariantID, s.CommonName, st.DBH_cm
    FROM trees.Trees t
    JOIN trees.Species s ON t.SpeciesID = s.SpeciesID
    JOIN trees.Stems st ON st.TreeVariantID = t.VariantID
    WHERE t.Height_m IS NULL AND st.DBH_cm IS NOT NULL
""")
rows = cur.fetchall()

# For each species, fit/load H-D model and predict
# Group by species for efficiency
species_models = {}
updates = []

for variant_id, species, dbh_cm in rows:
    if species not in species_models:
        yt = get_yield_table(species)
        species_models[species] = fit_hd_model(yt)
    
    predicted_h = species_models[species].predict(dbh_cm)
    updates.append((predicted_h, 'allometric_pylometree', variant_id))

# Batch update
cur.executemany("""
    UPDATE trees.Trees 
    SET Height_m = %s, HeightSource = %s
    WHERE VariantID = %s
""", updates)
conn.commit()
print(f"Updated {len(updates)} records")
```

**2. Add `HeightSource` column if not present**

```sql
ALTER TABLE trees.Trees 
ADD COLUMN IF NOT EXISTS HeightSource VARCHAR(50) DEFAULT 'measured';
```

**3. Dry-run first**

```bash
python scripts/import/fill_missing_heights.py --dry-run
```

Review predicted values — spot-check a few species against known averages.

**4. Run and verify**

```bash
python scripts/import/fill_missing_heights.py
# Verify:
# SELECT COUNT(*) FROM trees.Trees WHERE Height_m IS NULL;  -- should be 0
# SELECT HeightSource, COUNT(*) FROM trees.Trees GROUP BY HeightSource;
```

---

## XRFF-100 — Run sensor data import to populate prod DB (Backlog → Day 2)

**Status:** ⬜ TODO — **Day 2, blocked by XRFF-72**

**Context:** `scripts/import/import_sensor_data.py` exists and handles Sap_Flow, Soil_Moisture, Stem_Radial_Variation, Barometric_Pressure, Soil_Temperature from Aquarius. Not yet run in production.

### Steps

**1. Prerequisites**

- VPN connected to University of Freiburg network (Aquarius requires this)
- Docker stack running: `docker compose -f docker/docker-compose.yml up -d`
- `.env` file has `AQUARIUS_HOSTNAME`, `AQUARIUS_USERNAME`, `AQUARIUS_PASSWORD`

**2. Test connectivity**

```bash
python scripts/utils/test_aquarius.py
```

**3. Run import**

```bash
python scripts/import/import_sensor_data.py
# Or the wrapper:
python scripts/import/sync_aquarius.py
```

**4. Verify data**

```sql
SELECT sensor_type, COUNT(*), MIN(timestamp), MAX(timestamp)
FROM sensor.sensor_readings
GROUP BY sensor_type;
```

Expect: Sap_Flow, Soil_Moisture rows covering the last 30 days (DAYS_BACK = 30 in script).

**5. Set up recurring sync**

Once confirmed working, schedule via cron or extend `sync_aquarius.py` to run on a timer. Target: daily sync at 03:00 UTC.

```cron
0 3 * * * cd /path/to/digital-twin-db && python scripts/import/sync_aquarius.py >> logs/sync.log 2>&1
```

**6. Update PostgREST API view** (if not already exposed)

Verify `sensor.sensor_readings` is accessible via PostgREST for Unreal Engine:

```bash
curl "http://localhost:3000/sensor_readings?sensor_type=eq.Sap_Flow&limit=5" \
  -H "apikey: <anon-key>"
```

---

## XRFF-133 — Add GBIF taxon key to shared.species (High, assignee: Max)

**Status:** ✅ DONE — schema + load SQL + refresh function updated; CSV already had GBIFKey/GBIFAcceptedName

**Goal:** Add `gbif_taxon_key` column to `shared.species` table and populate with GBIF Species Match API lookups. Required for cross-system species matching between digital-twin-db and growpy.

### Steps

**1. Add column to species table**

```sql
ALTER TABLE shared.species 
ADD COLUMN IF NOT EXISTS gbif_taxon_key INTEGER;
```

**2. Populate via GBIF Species Match API**

```bash
# For each species in shared.species:
curl "https://api.gbif.org/v1/species/match?name=<species_name>"
# Extract: usageKey from response
```

**3. Verify**

```sql
SELECT species_id, scientific_name, gbif_taxon_key 
FROM shared.species 
WHERE gbif_taxon_key IS NULL;
-- Should return 0 rows
```

---

## See Also

- `scripts/import/import_sensor_data.py` — Aquarius → DB pipeline
- `scripts/import/sync_aquarius.py` — wrapper with Docker checks
- `scripts/utils/test_aquarius.py` — connectivity test
- [XRFF-72](https://linear.app/geosense-ufr/issue/XRFF-72) — timezone fix (blocks XRFF-100)
- [XRFF-39](https://linear.app/geosense-ufr/issue/XRFF-39) — height gap-fill
- [XRFF-100](https://linear.app/geosense-ufr/issue/XRFF-100) — sensor import run
- [XRFF-133](https://linear.app/geosense-ufr/issue/XRFF-133) — GBIF taxon key
- [20260423-current-state-assessment](../../xr-future-forests-lab/obsidian/xr-future-forests-lab/07-UPDATES/20260423-current-state-assessment.md) — full project assessment
