# Variant & Scenario Data Model

> **XRFF-240** — How forest states are stored in the DB and queried from Unreal Engine.

---

## Concept

The digital twin DB stores multiple **forest states** in a strict three-level hierarchy: Location → Scenario → Variant.

| Term | Meaning | Example |
|------|---------|---------|
| **Location** | A physical forest site | `ecosense`, `mathisle` |
| **Scenario** | A `(management regime, climate pathway)` pair **at one site** that owns its baseline/initial conditions; `scenario_code = regime*10 + pathway` | `natural_growth` (10), `crop_tree_thinning_ssp370` (22) |
| **Variant** | A snapshot in that regime's timeline (baseline → growth → intervention) | `baseline_2025`, `silva_2035` |
| **VariantType** | How the data was produced | `original`, `simulated_growth`, `model_output` |
| **Tree row** | One tree's state at one time step | Tree #42 at height 22.5m in year 2035 |

### Three-level hierarchy

```
shared.locations   (which forest site: ecosense, mathisle)
  └── shared.scenarios   (a management regime AT that site; owns its baseline)
        └── shared.variants   (a state in the regime's timeline; parent_variant_id lineage)
              └── trees.trees  (all trees at that state, joined by variant_id)
```

**Scenarios are location-scoped** — `shared.scenarios.location_id NOT NULL` and `UNIQUE(location_id, scenario_name)`. So a site like `ecosense` holds several scenarios (`natural_growth`, `crop_tree_thinning_ssp370`, …), each developing through its own variants. A scenario is *not* a single time step — the successive years are **variants** (snapshots) of it.

**A scenario is a point on two axes (since 2026-09-14).** `shared.scenarios` carries `management_regime_id` → `shared.management_regimes` and `climate_pathway_id` → `shared.climate_pathways`, both small-integer lookups with a name, and a generated `scenario_code = management_regime_id * 10 + climate_pathway_id`. That is what Unreal sorts on: the tens digit groups by regime, the units digit by pathway, and every id comes with its text.

| | id | name | |
|---|---|---|---|
| regime | 0 | `none` | holds acquired data only, never trees |
| regime | 1 | `natural_growth` | no intervention |
| regime | 2 | `crop_tree_thinning` | Z-Baum thinning + target-diameter harvest (even-aged stands) |
| regime | 3 | `target_diameter_harvest` | single-tree selection (two-storied stands) |
| pathway | 0 | `historical` | observed 1981–2010 climatology held constant |
| pathway | 1–3 | `ssp126`, `ssp370`, `ssp585` | CMIP6 pathways the open-data connector acquires |

The scenario **name follows one grammar** — `<pathway>` (a climate bucket, regime 0), `<regime>` (that regime under historical climate) or `<regime>_<pathway>` — and a `BEFORE INSERT` trigger derives the two ids from the name when the inserter does not set them, refusing a name that fits no form. So `natural_growth` is code 10, `natural_growth_ssp585` is 13, `target_diameter_harvest_ssp370` is 32, and the open-data connector's `ssp370` bucket is 2. One scenario per `(location, regime, pathway)`. A regime row also carries the SILVA thinning preset it stands for (`silva_rules`), which is how silva-connector knows what "managed" means — see its RUNBOOK.

**Variants form a timeline** — `shared.variants.parent_variant_id` links each state to the one it developed from (`baseline_2025` → `silva_2030` → `silva_2035`), with `sort_order` giving the display order. A variant name is unique per (location, scenario) — `silva_2035` exists once in every projection scenario, disambiguated by the hierarchy rather than embedded in the name. The measured `baseline_2025` exists only in `natural_growth`; the other chains start from it (see [Scenarios in the DB](#scenarios-in-the-db)).

> The old model conflated the levels — each simulated year was its own "scenario" (`Ecosense_Growth_2035`, `Mathisle_Growth_2045`), so one trajectory was scattered across several scenarios. Consolidated to one `natural_growth` scenario per site.

One physical tree (identified by `tree_entity_id`) can appear in many rows in `trees.trees` — one per variant. All trees at the same time step share the same `variant_id`. This is what enables UE "time travel": query by `variant_id` to load the complete forest at one point in time.

**Variants vs. data corrections:** A new Variant is for a distinct forest state. If you find a typo or missed measurement in an existing record, fix it with a plain UPDATE — not a new variant. The DB has AFTER UPDATE audit triggers that log the change automatically. See [data-access-guide.md](data-access-guide.md#correcting-data--field-updates-vs-new-variants).

---

## Schema

```
shared.locations              ← forest sites (top of hierarchy)
  location_id  PK
  location_name                ← "ecosense", "mathisle"

shared.scenarios              ← (management regime, climate pathway) pairs, one set per location
  scenario_id  PK
  location_id    FK → shared.locations    ← the site this scenario belongs to
  scenario_name                ← "natural_growth" (UNIQUE per location_id)
  management_regime_id  FK → shared.management_regimes
  climate_pathway_id    FK → shared.climate_pathways   ← UNIQUE (location_id, regime, pathway)
  scenario_code                ← generated: management_regime_id * 10 + climate_pathway_id

shared.variant_types           ← how data was generated (lookup)
  variant_type_id PK
  variant_type_name             ← "original", "simulated_growth", "model_output", etc.

shared.variants               ← one state in a scenario's timeline
  variant_id       PK
  location_id      FK → shared.locations    ← site (= the scenario's location)
  scenario_id      FK → shared.scenarios
  variant_type_id   FK → shared.variant_types ← type of this entire snapshot
  parent_variant_id FK → shared.variants     ← lineage: the state this developed from
  variant_name                 ← "baseline_2025", "silva_2035" (unique per location+scenario)
  simulation_year              ← calendar year this state represents
  time_delta_yrs               ← years since baseline
  sort_order                   ← display order in UE time-step selector (0 = baseline)

trees.trees                   ← one row per tree per time step
  tree_id        PK            ← unique row identifier
  tree_entity_id  UUID          ← stable identity across all variants of the same physical tree
  variant_id     FK → shared.variants     ← group selector: all trees at one time step
  parent_tree_id  FK → trees.trees         ← lineage: which row this was grown from
  scenario_id    FK → shared.scenarios    ← copy of the variant's scenario, set by the writers (no trigger)
  variant_type_id FK → shared.variant_types ← copy of the variant's type (NOT NULL)
  plot_id        FK → shared.plots        ← sub-plot within the site
  height_m, position, position_original, species_id, age_years, ...
```

`tree_id` is the row PK (auto-increment, changes each time a tree is inserted). `tree_entity_id` is the stable physical-tree UUID — use it to track one tree across all variants/time steps. `variant_id` is the group selector used by UE to load a complete forest state.

The **variant type** (original, simulated_growth, etc.) is a property of the *variant as a whole*: `shared.variants.variant_type_id` is authoritative. `trees.trees.variant_type_id` repeats it per row (NOT NULL, written by the importers and silva-connector). `ue_trees` takes it from the variant join, so UE sees it per tree without any extra query.

---

## API query patterns for UE

### Step 0: List the scenarios at a location (populate the scenario selector)

```
GET /ue_scenarios?location_name=eq.ecosense&has_trees=eq.true&order=scenario_code
→ [
    {"scenario_id": 2,  "scenario_name": "natural_growth",            "scenario_code": 10, "management_regime_name": "natural_growth",     "climate_pathway_name": "historical", "climate_pathway_label": "historical", "variant_count": 11, "first_year": 2025, "last_year": 2075, "baseline_variant_id": 2, ...},
    ...
    {"scenario_id": 22, "scenario_name": "natural_growth_ssp370",     "scenario_code": 12, "management_regime_name": "natural_growth",     "climate_pathway_name": "ssp370",     "climate_pathway_label": "SSP3-7.0",   "variant_count": 10, "first_year": 2030, "last_year": 2075, "baseline_variant_id": 2, ...},
    ...
    {"scenario_id": 23, "scenario_name": "crop_tree_thinning_ssp370", "scenario_code": 22, "management_regime_name": "crop_tree_thinning", "climate_pathway_name": "ssp370",     "climate_pathway_label": "SSP3-7.0",   "variant_count": 10, ...}
  ]
```

Ids above are from the dev database; ids differ between databases, so look scenarios up by name. `has_trees=false` rows are the climate-data buckets (regime 0); leave them out of the picker. Two dropdowns — regime and pathway — map onto `scenario_code` as `regime*10 + pathway`.

### Step 1: List available variants for a scenario (populate the time-step selector)

```
GET /ue_variants?scenario_id=eq.2&order=sort_order
→ [
    {"variant_id": 2,   "variant_name": "baseline_2025", "simulation_year": 2025, "time_delta_yrs": 0,  "sort_order": 0, "parent_variant_id": null, "variant_type_name": "original",         "scenario_code": 10, "tree_count": 1495, ...},
    {"variant_id": 255, "variant_name": "silva_2030",    "simulation_year": 2030, "time_delta_yrs": 5,  "sort_order": 1, "parent_variant_id": 2,    "variant_type_name": "simulated_growth", "scenario_code": 10, "tree_count": 1495, ...},
    {"variant_id": 256, "variant_name": "silva_2035",    "simulation_year": 2035, "time_delta_yrs": 10, "sort_order": 2, "parent_variant_id": 255,  ...}
  ]
```

`simulation_year` is the number, `variant_name` the text; `sort_order` orders them. To jump between scenarios at the same year, filter `ue_variants?location_id=eq.1&simulation_year=eq.2050` and switch on `scenario_code`. (`ue_variants` adds `location_name` and `tree_count`; `public.variants` has the variant's own columns plus resolved names and the regime/pathway ids, without `tree_count`.)

### Step 2: Load all trees at one time step

```
GET /ue_trees?variant_id=eq.2
```

Response fields (full `ue_trees` row, from the dev database):
```json
{
  "tree_id": 763,
  "tree_entity_id": "9684c247-df06-412d-a4de-5c8ac65b6654",
  "location_id": 1,
  "location_name": "ecosense",
  "scenario_id": 2,
  "scenario_name": "natural_growth",
  "variant_id": 2,
  "variant_name": "baseline_2025",
  "simulation_year": 2025,
  "variant_type_name": "original",
  "species_name": "Douglas Fir",
  "scientific_name": "Pseudotsuga menziesii",
  "height_m": 28.49,
  "crown_width_m": 9.14,
  "crown_base_height_m": 11.99,
  "dbh_cm": 59.84,
  "age_years": null,
  "health_score": null,
  "has_competition": false,
  "sensor_ref": "DouglasFir_Mixed_2",
  "has_sensors": true,
  "original_x": 416748.930375975,
  "original_y": 5346759.15983883,
  "source_crs": 32632,
  "latitude": 48.2685655954629,
  "longitude": 7.87812348464317,
  "sort_order": 0,
  "time_delta_yrs": 0.00,
  "variant_type_id": 1,
  "scenario_code": 10,
  "management_regime_id": 1,
  "management_regime_name": "natural_growth",
  "climate_pathway_id": 0,
  "climate_pathway_name": "historical",
  "tree_status_id": null,
  "tree_status_name": null,
  "leaf_type": "needleleaf"
}
```

`sensor_ref` / `has_sensors` are non-null/true only on the row a sensor is linked to — the instrumented tree's measured `baseline_2025` row; projected rows of the same tree carry `NULL` / `false` (follow `tree_entity_id`). See [api-spec.md](api-spec.md) for the tree ↔ sensor ↔ reading query chain.

### Filter by location + scenario name (when variant_id is unknown)

```
GET /ue_trees?location_name=eq.ecosense&scenario_name=eq.natural_growth
```

### Filter to one time step by variant name

A name like `silva_2035` exists in every projection scenario, so pair it with `scenario_name`:

```
GET /ue_trees?location_name=eq.ecosense&scenario_name=eq.natural_growth&variant_name=eq.silva_2035
```

### Load tree stems (DBH) alongside

Stems are in a separate table — query in parallel or join in UE:

```
GET /stems?tree_id=in.(1042,1043,1044,...)
```

Or use the `trees` view with embedded select:

```
GET /trees?variant_id=eq.2&select=tree_id,height_m,position,species(common_name),stems(dbh_cm)
```

---

## Scenarios in the DB

Scenarios are **location-scoped**. The `natural_growth` scenario of each site, with its `baseline_2025`, is created by the baseline seed scripts (`scripts/seed/<site>_baseline_variant.sql`); the `ssp*` climate buckets by the open-data connector; every other tree-holding scenario by silva-connector, named after the regime and pathway of the run that produced it (`--regime`, `--climate`). After the 2026-09-14 production run each site holds:

| scenario_code | scenario_name | holds |
|---|---|---|
| 1–3 | `ssp126`, `ssp370`, `ssp585` | acquired climate only (`environments.environments`) |
| 10 | `natural_growth` | measured baseline + unmanaged projection, historical climate |
| 11–13 | `natural_growth_ssp126` … `_ssp585` | unmanaged projection under each pathway |
| 20–23 (ecosense) | `crop_tree_thinning`, `crop_tree_thinning_ssp126` … | managed projection, even-aged regime |
| 30–33 (mathisle) | `target_diameter_harvest`, `target_diameter_harvest_ssp126` … | managed projection, single-tree selection |

Every projection chain hangs off the same measured `baseline_2025` in `natural_growth`: the first variant of a managed or climate chain has `parent_variant_id` pointing across scenarios at that baseline. The baseline variants come from the seed scripts; every projected variant (`silva_*`) from silva-connector.

---

## Adding a new scenario and variant

```bash
# Create a scenario through the public view. location_id is required. The name
# must follow <pathway> | <regime> | <regime>_<pathway> so the axis ids can be
# derived (or pass management_regime_id / climate_pathway_id explicitly); a name
# that fits no form is refused. New regimes/pathways go into their lookup first.
curl -X POST "http://localhost:8000/rest/v1/scenarios" \
  -H "apikey: <SERVICE_ROLE_KEY>" -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"location_id": <location_id>, "scenario_name": "crop_tree_thinning_ssp126", "description": "Thinning regime, SSP1-2.6"}'

# public.variants is a read-only join view, so create the variant in the base
# table: the shared schema is exposed to PostgREST, selected with Content-Profile.
# location_id and variant_type_id are required; parent_variant_id links the state
# it develops from.
curl -X POST "http://localhost:8000/rest/v1/variants" \
  -H "apikey: <SERVICE_ROLE_KEY>" -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "Content-Profile: shared" -H "Content-Type: application/json" \
  -d '{"location_id": <location_id>, "scenario_id": <new_id>, "variant_type_id": 4, "variant_name": "silva_2060", "simulation_year": 2060, "time_delta_yrs": 35, "sort_order": 7, "parent_variant_id": <prev_id>}'
```

Tree rows for a new variant must carry its `variant_id`, `scenario_id` and `variant_type_id`.
SILVA projections are written this way by silva-connector ([silva-coupling.md](silva-coupling.md)).
`scripts/import/import_trees.py` does **not** set them — it writes `scenario_id = NULL` and no
`variant_id` — so a CSV import is assigned to its variant afterwards by a seed script such as
`scripts/seed/ecosense_baseline_variant.sql`, which creates `natural_growth` and
`baseline_2025` and attaches the imported trees.

---

## UE variant switching — implementation notes

In the HTTPS Blueprint:
1. On level load, call `GET /ue_scenarios?location_id=eq.<id>&has_trees=eq.true&order=scenario_code` → populate a DataTable `DT_Scenarios` (keyed on `scenario_code`; `management_regime_name` and `climate_pathway_name` are the two dropdowns).
2. When user selects a scenario, call `GET /ue_variants?scenario_id=eq.<id>&order=sort_order` → populate a `DT_Variants` time-step selector (`simulation_year` for the slider, `variant_name` for the label).
3. When user selects a time step, call `GET /ue_trees?variant_id=eq.<variant_id>` → repopulate `DT_Trees`. Skip rows with `tree_status_id = 5` (harvested) or `6` (missing) — the tree is gone; render `4` (dead) as a snag and `7` (downed) / `8` (broken) as lying or broken dead wood; `1`–`3` (healthy, stressed, declining) are standing live trees; `NULL` means not recorded, treat as healthy.
4. PCG graph re-runs → trees respawn at new heights/positions.

The `ue_trees` view includes pre-flattened `latitude`/`longitude` — no PostGIS geometry parsing needed in Blueprint. It also carries projected coordinates `original_x`/`original_y` — the tree's `position_original`, or its position transformed to the site's `shared.locations.crs_epsg` (EPSG:32632 / UTM 32N for both sites) — which UE places more reliably than WGS84 lat/lon. It also exposes `has_competition` (boolean), derived as `crown_base_height_m / height_m > 0.6` — trees where the live crown starts in the upper 40% are considered under competition pressure. See XRFF-242 for the blueprint implementation.
