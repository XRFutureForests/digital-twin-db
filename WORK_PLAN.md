# digital-twin-db — Work Plan

Linear: [XRFF team](https://linear.app/geosense-ufr/team/XRFF/all)

## Issue Sequence

```
XRFF-72  (fix DateTime timezone — quick win)
    └─► XRFF-100 (run sensor data import into prod DB)
            └─► XRFF-106 (real-time sensor pipeline to Unreal)
                XRFF-107 (sensor data on tree objects in VR)
                dashboard sensor display

XRFF-39  (fill missing tree heights — parallel, uses pylometree)
    └─► full inventory spawn without gaps

XRFF-133 (add GBIF taxon key to shared.species)  ← parallel track
    └─► XRFF-36 (inventory-driven growpy generation — requires GBIF keys synced)
```

---

## XRFF-72 — Fix DateTime timezone handling (Medium, assignee: Paul)

**Context**: Aquarius exports timestamps. `import_sensor_data.py` inserts them into `sensor.SensorReadings`. The issue: UE DataTable imports sap flow CSV and shifts timestamps by +0200 (local timezone applied twice, or UTC offset not stripped).

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

**Context**: ~20% of Ecosense inventory records have `Height_m IS NULL`. PCG graph selects the wrong growth-stage asset variant for these trees. `pylometree` H-D models can predict height from species + DBH.

**Prerequisite**: pylometree installed in the active environment.

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

## XRFF-100 — Run sensor data import to populate prod DB (Backlog → next after XRFF-72)

**Context**: `scripts/import/import_sensor_data.py` exists and handles Sap_Flow, Soil_Moisture, Stem_Radial_Variation, Barometric_Pressure, Soil_Temperature from Aquarius. Not yet run in production. Blocked by XRFF-72 timezone fix.

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

## See Also

- `scripts/import/import_sensor_data.py` — Aquarius → DB pipeline
- `scripts/import/sync_aquarius.py` — wrapper with Docker checks
- `scripts/utils/test_aquarius.py` — connectivity test
- [XRFF-72](https://linear.app/geosense-ufr/issue/XRFF-72) — timezone fix (blocks XRFF-100)
- [XRFF-39](https://linear.app/geosense-ufr/issue/XRFF-39) — height gap-fill
- [XRFF-100](https://linear.app/geosense-ufr/issue/XRFF-100) — sensor import run
