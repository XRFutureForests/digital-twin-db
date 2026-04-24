# digital-twin-db — Work Plan

Linear: [XRFF team](https://linear.app/geosense-ufr/team/XRFF/all)

**Last updated:** 2026-04-23

---

## Current State

🟢 **Foundation complete.** Sensor data in prod DB. Tree height gap-fill ready to run.

### Completed (2026-04-23)

| Issue | Status | Notes |
|---|---|---|
| [XRFF-72](https://linear.app/geosense-ufr/issue/XRFF-72) Fix DateTime timezone | ✅ DONE | `import_sensor_data.py` + UE Editor UTC setting |
| [XRFF-133](https://linear.app/geosense-ufr/issue/XRFF-133) Add GBIF taxon key | ✅ DONE | `GBIFKey INTEGER` + `GBIFAcceptedName` columns added |
| [XRFF-100](https://linear.app/geosense-ufr/issue/XRFF-100) Run sensor import to prod | ✅ DONE | 372K+ readings imported (Soil_Moisture, Soil_Temp, Stem_Radial, Sap_Flow) |

### In Progress

| Issue | Status | Notes |
|---|---|---|
| [XRFF-39](https://linear.app/geosense-ufr/issue/XRFF-39) Fill missing tree heights | ⬜ READY TO RUN | Script written, HeightSource column added, pylometree git dep works — **unblocked** |

### Backlog

| Issue | Status | Notes |
|---|---|---|
| [XRFF-106](https://linear.app/geosense-ufr/issue/XRFF-106) Real-time sensor pipeline to Unreal | ⬜ TODO | Depends on XRFF-100 complete |
| [XRFF-107](https://linear.app/geosense-ufr/issue/XRFF-107) Sensor data on tree objects in VR | ⬜ TODO | Depends on XRFF-106 |
| [XRFF-136](https://linear.app/geosense-ufr/issue/XRFF-136) Crown diameter + structural params | ⬜ TODO | Better catalog matching for UE tree selection |

---

## Issue Sequence

```
✅ XRFF-72 → ✅ XRFF-133 → ✅ XRFF-100
                              │
                              ├─► 🟢 XRFF-106 (real-time sensor pipeline to Unreal)
                              │       └─► XRFF-107 (sensor data on tree objects in VR)
                              │
✅ XRFF-39 (READY TO RUN)
    └─► fill_missing_heights.py + HeightSource column
    └─► full inventory spawn without gaps

✅ XRFF-133 → XRFF-136 (crown diameter for better catalog matching)
```

---

## XRFF-39 — Fill missing tree heights (High, assignee: Max)

**Status:** ⬜ **READY TO RUN** — unblocked (pylometree git dep works, no PyPI needed)

**Context:** ~20% of Ecosense inventory records have `Height_m IS NULL`. PCG graph selects wrong growth-stage asset variant. `pylometree` H-D models predict height from species + DBH.

### What's done

- `scripts/import/fill_missing_heights.py` written
- `HeightSource VARCHAR(50)` column added to `trees.Trees` schema (`13-trees-schema.sql`)
- Script auto-runs `ALTER TABLE ... ADD COLUMN IF NOT EXISTS HeightSource` on existing DBs
- pylometree available via git dep in growpy (XRFF-131 decision: skip PyPI)

### Run it

```bash
# Dry-run first
python scripts/import/fill_missing_heights.py --dry-run

# Review predicted values — spot-check species against known averages

# Run
python scripts/import/fill_missing_heights.py

# Verify
# SELECT COUNT(*) FROM trees.Trees WHERE Height_m IS NULL;  -- should be 0
# SELECT HeightSource, COUNT(*) FROM trees.Trees GROUP BY HeightSource;
```

---

## XRFF-106 — Real-time sensor pipeline to Unreal (Medium, assignee: TBD)

**Status:** ⬜ TODO — **depends on XRFF-100 complete**

**Context:** Sensor data now in prod DB (`sensor.sensor_readings`). Need pipeline to stream readings to Unreal for VR visualization.

### Open questions

- Push (WebSocket/MQTT) vs pull (PostgREST polling) architecture?
- Update frequency? (Soil_Moisture ~hourly, Sap_Flow ~every 15min)
- UE side: DataTable refresh or direct DB connection?

---

## See Also

- [XRFF-100](https://linear.app/geosense-ufr/issue/XRFF-100) — sensor import results (372K+ readings)
- [XRFF-133](https://linear.app/geosense-ufr/issue/XRFF-133) — GBIF keys now in `shared.Species`
- `docs/database-schema.md` — current schema
- `docs/audit-and-implementation-plan.md` — full audit plan

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
