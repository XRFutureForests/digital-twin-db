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
        └── shared.Variants   (a state in the regime's timeline; parent_variant_id lineage)
              └── trees.Trees  (all trees at that state, joined by variant_id)
```

**Scenarios are location-scoped** — `shared.Scenarios.location_id NOT NULL` and `UNIQUE(location_id, scenario_name)`. So a site like `ecosense` can hold several management regimes (`natural_growth`, and later e.g. `intensive_management`, `extensive_management`), each defining its own initial conditions and developing through its own variants. A scenario is *not* a single time step — the successive years are **variants** of it.

**Variants form a timeline** — `shared.Variants.parent_variant_id` links each state to the one it developed from (`baseline_2025` → `growth_2035` → `growth_2045`), with `sort_order` giving the display order. The same variant name (`baseline_2025`) exists once per (location, scenario), disambiguated by the hierarchy rather than embedded in the name.

> The old model conflated the levels — each simulated year was its own "scenario" (`Ecosense_Growth_2035`, `Mathisle_Growth_2045`), so one trajectory was scattered across several scenarios. Consolidated to one `natural_growth` scenario per site.

One physical tree (identified by `tree_entity_id`) can appear in many rows in `trees.Trees` — one per variant. All trees at the same time step share the same `variant_id`. This is what enables UE "time travel": query by `variant_id` to load the complete forest at one point in time.

**Variants vs. data corrections:** A new Variant is for a distinct forest state. If you find a typo or missed measurement in an existing record, fix it with a plain UPDATE — not a new variant. The DB has AFTER UPDATE audit triggers that log the change automatically. See [data-access-guide.md](data-access-guide.md#correcting-data--field-updates-vs-new-variants).

---

## Schema

```
shared.Locations              ← forest sites (top of hierarchy)
  location_id  PK
  location_name                ← "ecosense", "mathisle"

shared.Scenarios              ← management regimes, ONE set per location
  scenario_id  PK
  location_id    FK → shared.Locations    ← the site this regime belongs to
  scenario_name                ← "natural_growth" (UNIQUE per location_id)

shared.VariantTypes           ← how data was generated (lookup)
  variant_type_id PK
  variant_type_name             ← "original", "simulated_growth", "model_output", etc.

shared.Variants               ← one state in a scenario's timeline
  variant_id       PK
  location_id      FK → shared.Locations    ← site (= the scenario's location)
  scenario_id      FK → shared.Scenarios
  variant_type_id   FK → shared.VariantTypes ← type of this entire snapshot
  parent_variant_id FK → shared.Variants     ← lineage: the state this developed from
  variant_name                 ← "baseline_2025", "growth_2035" (unique per location+scenario)
  simulation_year              ← calendar year this state represents
  time_delta_yrs               ← years since baseline
  sort_order                   ← display order in UE time-step selector (0 = baseline)

trees.Trees                   ← one row per tree per time step
  tree_id        PK            ← unique row identifier
  tree_entity_id  UUID          ← stable identity across all variants of the same physical tree
  variant_id     FK → shared.Variants     ← group selector: all trees at one time step
  parent_tree_id  FK → trees.Trees         ← lineage: which row this was grown from
  scenario_id    FK → shared.Scenarios    ← convenience FK, resynced from the variant
  plot_id        FK → shared.Plots        ← sub-plot within the site
  Height_m, Position, position_original, species_id, Age_years, ...
```

`tree_id` is the row PK (auto-increment, changes each time a tree is inserted). `tree_entity_id` is the stable physical-tree UUID — use it to track one tree across all variants/time steps. `variant_id` is the group selector used by UE to load a complete forest state.

The **VariantType** (original, simulated_growth, etc.) is a property of the *variant as a whole* and lives on `shared.Variants.variant_type_id`, not on individual tree rows. `ue_trees` surfaces it via the variant join, so UE sees it per tree without any extra query.

---

## API query patterns for UE

### Step 1: List available variants for a location + scenario (populate time-step selector UI)

```
GET /variants?location_name=eq.ecosense&scenario_name=eq.natural_growth&order=sort_order
→ [
    {"variant_id": 1, "location_name": "ecosense", "scenario_name": "natural_growth", "variant_name": "baseline_2025", "simulation_year": 2025, "sort_order": 0, "parent_variant_id": null, ...},
    {"variant_id": 2, "location_name": "ecosense", "scenario_name": "natural_growth", "variant_name": "growth_2035",   "simulation_year": 2035, "sort_order": 1, "parent_variant_id": 1, ...},
    {"variant_id": 3, "location_name": "ecosense", "scenario_name": "natural_growth", "variant_name": "growth_2045",   "simulation_year": 2045, "sort_order": 2, "parent_variant_id": 2, ...}
  ]
```

The `public.variants` view joins `location_name`, `scenario_name`, `variant_type_name`, so you can filter by name instead of id.

### Step 2: Load all trees at one time step

```
GET /ue_trees?variant_id=eq.3
```

Response fields (full `ue_trees` struct):
```json
{
  "tree_id": 1042,
  "tree_entity_id": "uuid...",
  "location_id": 1,
  "location_name": "ecosense",
  "scenario_id": 1,
  "scenario_name": "natural_growth",
  "variant_id": 3,
  "variant_name": "growth_2035",
  "simulation_year": 2035,
  "variant_type_name": "simulated_growth",
  "species_name": "European Beech",
  "scientific_name": "Fagus sylvatica",
  "height_m": 22.5,
  "crown_width_m": 8.2,
  "crown_base_height_m": 9.1,
  "dbh_cm": 34.1,
  "age_years": 95,
  "health_score": 0.85,
  "competition": false,
  "sensor_ref": "Beech_Mixed_8",
  "has_sensors": true,
  "original_x": 416747.2247,
  "original_y": 5346758.6,
  "source_crs": 32632,
  "latitude": 48.2684,
  "longitude": 7.8779
}
```

`sensor_ref` / `has_sensors` are non-null/true only for instrumented trees — see [api_spec.md](api_spec.md) for the tree ↔ sensor ↔ reading query chain.

### Filter by location + scenario name (when variant_id is unknown)

```
GET /ue_trees?location_name=eq.ecosense&scenario_name=eq.natural_growth
```

### Filter to one time step by variant name

```
GET /ue_trees?location_name=eq.ecosense&variant_name=eq.growth_2035
```

### Load tree stems (DBH) alongside

Stems are in a separate table — query in parallel or join in UE:

```
GET /stems?tree_id=in.(1042,1043,1044,...)
```

Or use the `trees` view with embedded select:

```
GET /trees?variant_id=eq.3&select=tree_id,height_m,position,species(common_name),stems(dbh_cm)
```

---

## Scenarios in the DB

Scenarios are **location-scoped and created by the growth-variant seed scripts**, not pre-loaded from a lookup CSV (a global scenario list no longer fits the per-site model). After the standard rebuild there is one regime per site:

| Location | scenario_name | Purpose |
|---|---|---|
| `ecosense` | `natural_growth` | Baseline field inventory developing under no active management |
| `mathisle` | `natural_growth` | Same, for the Mathisle site |

Additional regimes (e.g. `intensive_management`, `extensive_management`, a climate-stress scenario) are added per location, each owning its own baseline variant and trajectory. Variants (time steps) are created by the seed scripts or SILVA write-back when growth simulations are run.

---

## Adding a new scenario and variant

```bash
# Create scenario (via API) — location-scoped: location_id is required
curl -X POST "http://localhost:8000/rest/v1/scenarios" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"location_id": <location_id>, "scenario_name": "intensive_management", "description": "Thinning regime, RCP4.5"}'

# Create variant for that scenario (location_id and variant_type_id are both required;
# parent_variant_id links it to the state it develops from)
curl -X POST "http://localhost:8000/rest/v1/variants" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"location_id": <location_id>, "scenario_id": <new_id>, "variant_type_id": 4, "variant_name": "growth_2060", "simulation_year": 2060, "time_delta_yrs": 40, "sort_order": 0, "parent_variant_id": <prev_id>}'
```

Then insert tree rows with the new `scenario_id` and `variant_id`:

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
`baseline_2025` → `growth_2035` → `growth_2045` (each `parent_variant_id` pointing
at the prior state).

Each variant block:

1. **Creates a Variant row** in `shared.Variants` under the scenario, with `parent_variant_id` set to the state it grows from.
2. **Grows survivors** — selects baseline trees (joined to `trees.Stems` for DBH),
   randomly drops a small fraction (simulated mortality), scales measurements up,
   and inserts new `trees.Trees` rows with `variant_id` set to the new Variant,
   `tree_entity_id` carried over (same physical tree), and `parent_tree_id` pointing
   at the baseline row (lineage chain).
3. **Regenerates** — inserts new sapling rows with fresh `tree_entity_id` and no
   `parent_tree_id`, assigned to the same `variant_id`.

Both inserts use `variant_type_id = simulated_growth` and `DataSourceType = 'simulated'`.

**This is a simple placeholder model** — flat percentage growth, not a calibrated
forestry model. For scientifically calibrated projections, use the SILVA coupling
instead (`docs/silva-coupling.md`, `docs/growth-simulation-schema.md`).

---

## UE variant switching — implementation notes

In the HTTPS Blueprint:
1. On level load, call `GET /scenarios` → populate a DataTable `DT_Scenarios`.
2. When user selects a scenario, call `GET /variants?scenario_id=eq.<id>&order=sort_order` → populate a `DT_Variants` time-step selector.
3. When user selects a time step, call `GET /ue_trees?variant_id=eq.<variant_id>` → repopulate `DT_Trees`.
4. PCG graph re-runs → trees respawn at new heights/positions.

The `ue_trees` view includes pre-flattened `latitude`/`longitude` — no PostGIS geometry parsing needed in Blueprint. It also carries the tree's projected source coordinates `original_x`/`original_y` (in `source_crs`, EPSG:32632 / UTM 32N), which UE places more reliably than WGS84 lat/lon. It also exposes `competition` (boolean), derived as `crown_base_height_m / height_m > 0.6` — trees where the live crown starts in the upper 40% are considered under competition pressure. See XRFF-242 for the blueprint implementation.
