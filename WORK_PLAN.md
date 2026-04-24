# digital-twin-db — Work Plan

Linear: [XRFF team](https://linear.app/geosense-ufr/team/XRFF/all)

**Last updated:** 2026-04-24

---

## Current State

🟢 **Foundation complete.** Sensor data + tree heights in prod DB. Real-time sensor pipeline next.

### Completed (2026-04-24)

| Issue | Status | Notes |
|---|---|---|
| [XRFF-72](https://linear.app/geosense-ufr/issue/XRFF-72) Fix DateTime timezone | ✅ DONE | `import_sensor_data.py` + UE Editor UTC setting |
| [XRFF-133](https://linear.app/geosense-ufr/issue/XRFF-133) Add GBIF taxon key | ✅ DONE | `GBIFKey INTEGER` + `GBIFAcceptedName` columns added |
| [XRFF-100](https://linear.app/geosense-ufr/issue/XRFF-100) Run sensor import to prod | ✅ DONE | 372K+ readings imported (Soil_Moisture, Soil_Temp, Stem_Radial, Sap_Flow) |
| [XRFF-39](https://linear.app/geosense-ufr/issue/XRFF-39) Fill missing tree heights | ✅ DONE | 299/299 predicted via Chapman-Richards; 1 NULL remains (no species/DBH data) |

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
✅ XRFF-39 (DONE — 299 heights filled)
    └─► fill_missing_heights.py + HeightSource column
    └─► full inventory spawn without gaps

✅ XRFF-133 → XRFF-136 (crown diameter for better catalog matching)
```

---

## XRFF-39 — Fill missing tree heights (High, assignee: Max)

**Status:** ✅ **DONE** — 299 trees filled, 1 skipped (no SpeciesID/DBH)

**Context:** ~20% of Ecosense inventory records have `Height_m IS NULL`. PCG graph selects wrong growth-stage asset variant. `pylometree` H-D models predict height from species + DBH.

### What's done

- `scripts/import/fill_missing_heights.py` written
- `HeightSource VARCHAR(50)` column added to `trees.Trees` schema (`13-trees-schema.sql`)
- Script auto-runs `ALTER TABLE ... ADD COLUMN IF NOT EXISTS HeightSource` on existing DBs
- pylometree installed locally from `/home/max/git/pylometree`
- Environment updated in `environment.yml` with all dependencies

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
