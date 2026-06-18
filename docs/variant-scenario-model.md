# Variant & Scenario Data Model

> **XRFF-240** — How forest states are stored in the DB and queried from Unreal Engine.

---

## Concept

The digital twin DB stores multiple **variants** of a forest, not just one snapshot.

| Term | Meaning | Example |
|------|---------|---------|
| **Scenario** | A named set of assumptions | `Current_Conditions`, `Climate_Change_2050` |
| **VariantType** | How the data was produced | `original`, `simulated_growth`, `model_output` |
| **Variant (row)** | A single tree state under a scenario | Tree #42 at height 18.3m in year 2060 |

One physical tree (identified by `TreeEntityID`) can have many rows in `trees.Trees` — one per scenario/time-step. This is how time-machine switching works in UR: swap the `ScenarioID` filter and get a completely different forest.

---

## Schema (already in place)

```
shared.Scenarios         ← named scenarios (lookup table)
  ScenarioID
  ScenarioName           ← "Current_Conditions", "Climate_Change_2050", etc.

shared.VariantTypes      ← how data was generated
  VariantTypeName        ← "original", "simulated_growth", "model_output", etc.

trees.Trees              ← one row per tree-variant (the main data table)
  VariantID   PK
  TreeEntityID UUID      ← same UUID across all variants of the same tree
  ScenarioID  FK → shared.Scenarios
  VariantTypeID FK → shared.VariantTypes
  Height_m, Position, SpeciesID, Age_years, ...
```

`VariantID` is a surrogate key. `TreeEntityID` is the stable identity — use it to track one tree across scenarios.

---

## API query patterns for UE

### List available scenarios (populate selector UI)

```
GET /scenarios
→ [{"scenarioid": 1, "scenarioname": "Current_Conditions", "description": "..."},
   {"scenarioid": 2, "scenarioname": "Climate_Change_2050", ...}]
```

### Load a forest state by scenario name

```
GET /forest_state?scenarioname=eq.Current_Conditions
```

Response fields:
```json
{
  "variantid": 1042,
  "treeentityid": "uuid...",
  "scenarioname": "Current_Conditions",
  "varianttypename": "original",
  "speciesname": "European Beech",
  "scientificname": "Fagus sylvatica",
  "height_m": 22.5,
  "crownwidth_m": 8.2,
  "age_years": 95,
  "healthscore": 0.85,
  "latitude": 48.2684,
  "longitude": 7.8779
}
```

### Filter by location + scenario

```
GET /forest_state?locationid=eq.5&scenarioname=eq.Climate_Change_2050
```

### Load tree stems (DBH) alongside

Stems are in a separate table — query in parallel or join in UE:

```
GET /stems?variantid=in.(1042,1043,1044,...)
```

Or use the existing `trees` view with embedded select:

```
GET /trees?scenarioid=eq.2&select=variantid,height_m,position,species(commonname),stems(dbh_cm)
```

---

## Pre-loaded scenarios

The following are loaded from `data/lookups/scenarios.csv` on DB init:

| ScenarioName | Purpose |
|---|---|
| `Current_Conditions` | Baseline — actual field measurements |
| `Climate_Change_2050` | IPCC 2050 projection |
| `Climate_Change_2100` | IPCC 2100 projection |
| `Drought_Test` | Extreme drought stress |
| `Heat_Wave` | Extended heat wave |
| `Increased_CO2` | Elevated CO2 |
| `Management_Thinning` | Post-thinning state |
| `No_Management` | Natural development |

For the **Sept 2026 demo**, use `Current_Conditions` plus 2–3 contrasting variants loaded as demo data (see XRFF-241).

---

## Adding a new scenario (e.g. SILVA output)

```bash
# Via API (authenticated)
curl -X POST "http://localhost:8000/rest/v1/scenarios" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"scenarioname": "SILVA_2060_RCP45", "description": "SILVA growth simulation, RCP4.5, year 2060"}'
```

Then insert tree rows with the new `ScenarioID`:

```python
# scripts/import/import_trees.py data/imports/silva_2060_trees.csv
```

---

## UE variant switching — implementation notes

In the HTTPS Blueprint:
1. On level load, call `GET /scenarios` → populate a DataTable `DT_Scenarios`.
2. When user selects a scenario, call `GET /forest_state?scenarioname=eq.<selected>` → repopulate `DT_Trees`.
3. PCG graph re-runs → trees respawn at new heights/positions.

The `forest_state` view includes pre-flattened `latitude`/`longitude` — no PostGIS geometry parsing needed in Blueprint. See XRFF-242 for the blueprint implementation.
