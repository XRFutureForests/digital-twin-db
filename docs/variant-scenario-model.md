# Variant & Scenario Data Model

> **XRFF-240** — How forest states are stored in the DB and queried from Unreal Engine.

---

## Concept

The digital twin DB stores multiple **forest states** in a strict three-level hierarchy: Location → Scenario → Variant.

| Term | Meaning | Example |
|------|---------|---------|
| **Location** | A physical forest site | `ecosense`, `mathisle` |
| **Scenario** | A management regime **at one site** that owns its baseline/initial conditions | `natural_growth` (per site) |
| **Variant** | A state in that regime's timeline (baseline → growth → intervention) | `baseline_2025`, `growth_2035` |
| **VariantType** | How the data was produced | `original`, `simulated_growth`, `model_output` |
| **Tree row** | One tree's state at one time step | Tree #42 at height 22.5m in year 2035 |

### Three-level hierarchy

```
shared.Locations   (which forest site: ecosense, mathisle)
  └── shared.Scenarios   (a management regime AT that site; owns its baseline)
        └── shared.Variants   (a state in the regime's timeline; ParentVariantID lineage)
              └── trees.Trees  (all trees at that state, joined by VariantID)
```

**Scenarios are location-scoped** — `shared.Scenarios.LocationID NOT NULL` and `UNIQUE(LocationID, ScenarioName)`. So a site like `ecosense` can hold several management regimes (`natural_growth`, and later e.g. `intensive_management`, `extensive_management`), each defining its own initial conditions and developing through its own variants. A scenario is *not* a single time step — the successive years are **variants** of it.

**Variants form a timeline** — `shared.Variants.ParentVariantID` links each state to the one it developed from (`baseline_2025` → `growth_2035` → `growth_2045`), with `SortOrder` giving the display order. The same variant name (`baseline_2025`) exists once per (location, scenario), disambiguated by the hierarchy rather than embedded in the name.

> The old model conflated the levels — each simulated year was its own "scenario" (`Ecosense_Growth_2035`, `Mathisle_Growth_2045`), so one trajectory was scattered across several scenarios. Consolidated to one `natural_growth` scenario per site.

One physical tree (identified by `TreeEntityID`) can appear in many rows in `trees.Trees` — one per variant. All trees at the same time step share the same `VariantID`. This is what enables UE "time travel": query by `VariantID` to load the complete forest at one point in time.

**Variants vs. data corrections:** A new Variant is for a distinct forest state. If you find a typo or missed measurement in an existing record, fix it with a plain UPDATE — not a new variant. The DB has AFTER UPDATE audit triggers that log the change automatically. See [data-access-guide.md](data-access-guide.md#correcting-data--field-updates-vs-new-variants).

---

## Schema

```
shared.Locations              ← forest sites (top of hierarchy)
  LocationID  PK
  LocationName                ← "ecosense", "mathisle"

shared.Scenarios              ← management regimes, ONE set per location
  ScenarioID  PK
  LocationID    FK → shared.Locations    ← the site this regime belongs to
  ScenarioName                ← "natural_growth" (UNIQUE per LocationID)

shared.VariantTypes           ← how data was generated (lookup)
  VariantTypeID PK
  VariantTypeName             ← "original", "simulated_growth", "model_output", etc.

shared.Variants               ← one state in a scenario's timeline
  VariantID       PK
  LocationID      FK → shared.Locations    ← site (= the scenario's location)
  ScenarioID      FK → shared.Scenarios
  VariantTypeID   FK → shared.VariantTypes ← type of this entire snapshot
  ParentVariantID FK → shared.Variants     ← lineage: the state this developed from
  VariantName                 ← "baseline_2025", "growth_2035" (unique per location+scenario)
  SimulationYear              ← calendar year this state represents
  TimeDelta_yrs               ← years since baseline
  SortOrder                   ← display order in UE time-step selector (0 = baseline)

trees.Trees                   ← one row per tree per time step
  TreeID        PK            ← unique row identifier
  TreeEntityID  UUID          ← stable identity across all variants of the same physical tree
  VariantID     FK → shared.Variants     ← group selector: all trees at one time step
  ParentTreeID  FK → trees.Trees         ← lineage: which row this was grown from
  ScenarioID    FK → shared.Scenarios    ← convenience FK, resynced from the variant
  PlotID        FK → shared.Plots        ← sub-plot within the site
  Height_m, Position, PositionOriginal, SpeciesID, Age_years, ...
```

`TreeID` is the row PK (auto-increment, changes each time a tree is inserted). `TreeEntityID` is the stable physical-tree UUID — use it to track one tree across all variants/time steps. `VariantID` is the group selector used by UE to load a complete forest state.

The **VariantType** (original, simulated_growth, etc.) is a property of the *variant as a whole* and lives on `shared.Variants.VariantTypeID`, not on individual tree rows. `ue_trees` surfaces it via the variant join, so UE sees it per tree without any extra query.

---

## API query patterns for UE

### Step 1: List available variants for a location + scenario (populate time-step selector UI)

```
GET /variants?locationname=eq.ecosense&scenarioname=eq.natural_growth&order=sortorder
→ [
    {"variantid": 1, "locationname": "ecosense", "scenarioname": "natural_growth", "variantname": "baseline_2025", "simulationyear": 2025, "sortorder": 0, "parentvariantid": null, ...},
    {"variantid": 2, "locationname": "ecosense", "scenarioname": "natural_growth", "variantname": "growth_2035",   "simulationyear": 2035, "sortorder": 1, "parentvariantid": 1, ...},
    {"variantid": 3, "locationname": "ecosense", "scenarioname": "natural_growth", "variantname": "growth_2045",   "simulationyear": 2045, "sortorder": 2, "parentvariantid": 2, ...}
  ]
```

The `public.variants` view joins `locationname`, `scenarioname`, `varianttypename`, so you can filter by name instead of id.

### Step 2: Load all trees at one time step

```
GET /ue_trees?variantid=eq.3
```

Response fields (full `ue_trees` struct):
```json
{
  "treeid": 1042,
  "treeentityid": "uuid...",
  "locationid": 1,
  "locationname": "ecosense",
  "scenarioid": 1,
  "scenarioname": "natural_growth",
  "variantid": 3,
  "variantname": "growth_2035",
  "simulationyear": 2035,
  "varianttypename": "simulated_growth",
  "speciesname": "European Beech",
  "scientificname": "Fagus sylvatica",
  "height_m": 22.5,
  "crownwidth_m": 8.2,
  "crownbaseheight_m": 9.1,
  "dbh_cm": 34.1,
  "age_years": 95,
  "healthscore": 0.85,
  "competition": false,
  "aquarius_name": "Beech_Mixed_8",
  "has_sensors": true,
  "original_x": 416747.2247,
  "original_y": 5346758.6,
  "source_crs": 32632,
  "latitude": 48.2684,
  "longitude": 7.8779
}
```

`aquarius_name` / `has_sensors` are non-null/true only for instrumented trees — see [api_spec.md](api_spec.md) for the tree ↔ sensor ↔ reading query chain.

### Filter by location + scenario name (when VariantID is unknown)

```
GET /ue_trees?locationname=eq.ecosense&scenarioname=eq.natural_growth
```

### Filter to one time step by variant name

```
GET /ue_trees?locationname=eq.ecosense&variantname=eq.growth_2035
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

## Scenarios in the DB

Scenarios are **location-scoped and created by the growth-variant seed scripts**, not pre-loaded from a lookup CSV (a global scenario list no longer fits the per-site model). After the standard rebuild there is one regime per site:

| Location | ScenarioName | Purpose |
|---|---|---|
| `ecosense` | `natural_growth` | Baseline field inventory developing under no active management |
| `mathisle` | `natural_growth` | Same, for the Mathisle site |

Additional regimes (e.g. `intensive_management`, `extensive_management`, a climate-stress scenario) are added per location, each owning its own baseline variant and trajectory. Variants (time steps) are created by the seed scripts or SILVA write-back when growth simulations are run.

---

## Adding a new scenario and variant

```bash
# Create scenario (via API) — location-scoped: locationid is required
curl -X POST "http://localhost:8000/rest/v1/scenarios" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"locationid": <location_id>, "scenarioname": "intensive_management", "description": "Thinning regime, RCP4.5"}'

# Create variant for that scenario (locationid and varianttypeid are both required;
# parentvariantid links it to the state it develops from)
curl -X POST "http://localhost:8000/rest/v1/variants" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"locationid": <location_id>, "scenarioid": <new_id>, "varianttypeid": 4, "variantname": "growth_2060", "simulationyear": 2060, "timedelta_yrs": 40, "sortorder": 0, "parentvariantid": <prev_id>}'
```

Then insert tree rows with the new `ScenarioID` and `VariantID`:

```python
# scripts/import/import_trees.py data/imports/silva_2060_trees.csv
```

---

## Generating growth variants from existing data

For "what would this same forest look like N years from now" variants — grow the
trees that already exist in the DB rather than hand-writing new rows — use a SQL
script that grows a baseline variant into a derived one. The reference
implementation is `scripts/seed/ecosense_growth_variants.sql`, which creates the
`natural_growth` scenario, then chains its variants:
`baseline_2025` → `growth_2035` → `growth_2045` (each `ParentVariantID` pointing
at the prior state).

Each variant block:

1. **Creates a Variant row** in `shared.Variants` under the scenario, with `ParentVariantID` set to the state it grows from.
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

The `ue_trees` view includes pre-flattened `latitude`/`longitude` — no PostGIS geometry parsing needed in Blueprint. It also carries the tree's projected source coordinates `original_x`/`original_y` (in `source_crs`, EPSG:32632 / UTM 32N), which UE places more reliably than WGS84 lat/lon. It also exposes `competition` (boolean), derived as `crownbaseheight_m / height_m > 0.6` — trees where the live crown starts in the upper 40% are considered under competition pressure. See XRFF-242 for the blueprint implementation.
