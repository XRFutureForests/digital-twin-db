# Variant & Scenario Data Model

> **XRFF-240** — How forest states are stored in the DB and queried from Unreal Engine.

---

## Concept

The digital twin DB stores multiple **forest states** across three levels: Location → Scenario → Variant.

| Term | Meaning | Example |
|------|---------|---------|
| **Location** | A physical forest site | `Ecosense_MixedPlot`, `Mathisle` |
| **Scenario** | A named set of assumptions (climate, management) | `Current_Conditions`, `Ecosense_Growth_2035` |
| **Variant** | A specific time step within a scenario at a site | `Baseline_2025`, `Growth_2035` |
| **VariantType** | How the data was produced | `original`, `simulated_growth`, `model_output` |
| **Tree row** | One tree's state at one time step | Tree #42 at height 22.5m in year 2035 |

### Three-level hierarchy

```
shared.Locations   (which forest site)
  └── shared.Scenarios   (which set of assumptions)
        └── shared.Variants   (which time step / growth age)
              └── trees.Trees  (all trees at that time step, joined by VariantID)
```

**Location** is the top-level differentiator — `shared.Variants.LocationID NOT NULL FK` ensures every variant is pinned to a site. This means the same name like `Baseline_2025` or `Growth_2035` can exist for both Ecosense and Mathisle as separate rows, disambiguated by location rather than embedded in the name.

One physical tree (identified by `TreeEntityID`) can appear in many rows in `trees.Trees` — one per variant. All trees at the same time step share the same `VariantID`. This is what enables UE "time travel": query by `VariantID` to load the complete forest at one point in time.

**Variants vs. data corrections:** A new Variant is for a distinct forest state. If you find a typo or missed measurement in an existing record, fix it with a plain UPDATE — not a new variant. The DB has AFTER UPDATE audit triggers that log the change automatically. See [data-access-guide.md](data-access-guide.md#correcting-data--field-updates-vs-new-variants).

---

## Schema

```
shared.Locations              ← forest sites (top of hierarchy)
  LocationID  PK
  LocationName                ← "Ecosense_MixedPlot", "Mathisle", etc.

shared.Scenarios              ← named scenarios (reusable across locations)
  ScenarioID  PK
  ScenarioName                ← "Current_Conditions", "Ecosense_Growth_2035", etc.

shared.VariantTypes           ← how data was generated (lookup)
  VariantTypeID PK
  VariantTypeName             ← "original", "simulated_growth", "model_output", etc.

shared.Variants               ← one time step at one site within one scenario
  VariantID     PK
  LocationID    FK → shared.Locations    ← site — top of hierarchy
  ScenarioID    FK → shared.Scenarios
  VariantTypeID FK → shared.VariantTypes ← type of this entire snapshot
  VariantName                 ← "Baseline_2025", "Growth_2035", etc. (unique per location+scenario)
  SimulationYear              ← calendar year this state represents
  TimeDelta_yrs               ← years since baseline
  SortOrder                   ← display order in UE time-step selector

trees.Trees                   ← one row per tree per time step
  TreeID        PK            ← unique row identifier
  TreeEntityID  UUID          ← stable identity across all variants of the same physical tree
  VariantID     FK → shared.Variants     ← group selector: all trees at one time step
  ParentTreeID  FK → trees.Trees         ← lineage: which row this was grown from
  ScenarioID    FK → shared.Scenarios    ← direct convenience FK (avoids join via Variants)
  Height_m, Position, SpeciesID, Age_years, ...
```

`TreeID` is the row PK (auto-increment, changes each time a tree is inserted). `TreeEntityID` is the stable physical-tree UUID — use it to track one tree across all variants/time steps. `VariantID` is the group selector used by UE to load a complete forest state.

The **VariantType** (original, simulated_growth, etc.) is a property of the *variant as a whole* and lives on `shared.Variants.VariantTypeID`, not on individual tree rows. `ue_trees` surfaces it via the variant join, so UE sees it per tree without any extra query.

---

## API query patterns for UE

### Step 1: List available variants for a location + scenario (populate time-step selector UI)

```
GET /variants?locationid=eq.5&scenarioid=eq.1&order=sortorder
→ [
    {"variantid": 3, "locationid": 5, "locationname": "Ecosense_MixedPlot", "scenarioid": 1, "variantname": "Baseline_2025", "simulationyear": 2025, ...},
    {"variantid": 4, "locationid": 5, "locationname": "Ecosense_MixedPlot", "scenarioid": 2, "variantname": "Growth_2035", "simulationyear": 2035, ...}
  ]
```

Or filter by name directly (via `public.variants` view which joins `locationname` and `scenarioname`):

```
GET /variants?locationname=eq.Ecosense_MixedPlot&order=sortorder
```

### Step 2: Load all trees at one time step

```
GET /ue_trees?variantid=eq.3
```

Response fields:
```json
{
  "treeid": 1042,
  "treeentityid": "uuid...",
  "variantid": 3,
  "variantname": "Ecosense_2035_Baseline",
  "simulationyear": 2035,
  "scenarioname": "Current_Conditions",
  "varianttypename": "simulated_growth",
  "speciesname": "European Beech",
  "scientificname": "Fagus sylvatica",
  "height_m": 22.5,
  "crownwidth_m": 8.2,
  "dbh_cm": 34.1,
  "age_years": 95,
  "healthscore": 0.85,
  "dbh_cm": 34.1,
  "competition": false,
  "latitude": 48.2684,
  "longitude": 7.8779
}
```

### Filter by location + scenario name (when VariantID is unknown)

```
GET /ue_trees?locationid=eq.5&scenarioname=eq.Current_Conditions
```

### Filter by scenario only (returns all time steps for that scenario)

```
GET /ue_trees?scenarioname=eq.Ecosense_Growth_2035
```

### Load tree stems (DBH) alongside

Stems are in a separate table — query in parallel or join in UE:

```
GET /stems?treeid=in.(1042,1043,1044,...)
```

Or use the `trees` view with embedded select:

```
GET /trees?variantid=eq.3&select=treeid,height_m,position,species(commonname),stems(dbh_cm)
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

Variants (time steps) are NOT pre-loaded — they are created by seed scripts or SILVA write-back when growth simulations are run.

---

## Adding a new scenario and variant

```bash
# Create scenario (via API)
curl -X POST "http://localhost:8000/rest/v1/scenarios" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"scenarioname": "SILVA_2060_RCP45", "description": "SILVA growth simulation, RCP4.5, year 2060"}'

# Create variant for that scenario (locationid and varianttypeid are both required)
curl -X POST "http://localhost:8000/rest/v1/variants" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"locationid": <location_id>, "scenarioid": <new_id>, "varianttypeid": 4, "variantname": "Growth_2060", "simulationyear": 2060, "timedelta_yrs": 40, "sortorder": 0}'
```

Then insert tree rows with the new `ScenarioID` and `VariantID`:

```python
# scripts/import/import_trees.py data/imports/silva_2060_trees.csv
```

---

## Generating growth variants from existing data

For "what would this same forest look like N years from now" variants — grow the
trees that already exist in the DB rather than hand-writing new rows — use a SQL
script that reads a baseline scenario and writes a derived one. The reference
implementation is `scripts/seed/ecosense_growth_variants.sql`, which derives
`Ecosense_Growth_2035` from the real Ecosense `Current_Conditions` import, then
chains `Ecosense_Growth_2045` from `Ecosense_Growth_2035`.

Each variant block:

1. **Creates a Variant row** in `shared.Variants` linking to the new scenario.
2. **Grows survivors** — selects baseline trees (joined to `trees.Stems` for DBH),
   randomly drops a small fraction (simulated mortality), scales measurements up,
   and inserts new `trees.Trees` rows with `VariantID` set to the new Variant,
   `TreeEntityID` carried over (same physical tree), and `ParentTreeID` pointing
   at the baseline row (lineage chain).
3. **Regenerates** — inserts new sapling rows with fresh `TreeEntityID` and no
   `ParentTreeID`, assigned to the same `VariantID`.

Both inserts use `VariantTypeID = simulated_growth` and `DataSourceType = 'simulated'`.

**This is a simple placeholder model** — flat percentage growth, not a calibrated
forestry model. For scientifically calibrated projections, use the SILVA coupling
instead (`docs/silva-coupling.md`, `docs/growth-simulation-schema.md`).

---

## UE variant switching — implementation notes

In the HTTPS Blueprint:
1. On level load, call `GET /scenarios` → populate a DataTable `DT_Scenarios`.
2. When user selects a scenario, call `GET /variants?scenarioid=eq.<id>&order=sortorder` → populate a `DT_Variants` time-step selector.
3. When user selects a time step, call `GET /ue_trees?variantid=eq.<variantid>` → repopulate `DT_Trees`.
4. PCG graph re-runs → trees respawn at new heights/positions.

The `ue_trees` view includes pre-flattened `latitude`/`longitude` — no PostGIS geometry parsing needed in Blueprint. It also exposes `competition` (boolean), derived as `crownbaseheight_m / height_m > 0.6` — trees where the live crown starts in the upper 40% are considered under competition pressure. See XRFF-242 for the blueprint implementation.
