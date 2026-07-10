# Growth Simulation Schema

**Issue:** XRFF-243  
**Schema file:** `docker/volumes/db/init/26-growth-simulations-schema.sql`

---

## Purpose

`trees.GrowthSimulations` is the write target for all forest growth simulator output. It stores per-tree dimensional projections at discrete future time steps, produced by simulators such as SILVA, FVS, or iLand, then served to UE via PostgREST for the Time Machine feature.

---

## Key concepts

### run_id

A UUID that groups every row produced by a single simulator execution. All rows sharing a `run_id` represent a complete, internally consistent forest state trajectory. UE uses `run_id` when it needs to compare two simulation runs side by side.

### tree_entity_id

The stable UUID for a physical tree, shared across all `trees.Trees` variant rows and all `trees.GrowthSimulations` rows. This is the join key between the measured baseline state and the projected future states.

### projection_year

The calendar year the row describes. A typical SILVA run might output years 2025, 2030, 2035, …, 2100 — one row per tree per year step.

### base_tree_id

The `trees.Trees.tree_id` row used as the simulation starting point (e.g. the 2024 field inventory row). Allows tracing which baseline measurement the projection was derived from.

---

## Table structure

```
trees.GrowthSimulations
├── growth_simulation_id BIGSERIAL PK
├── run_id             UUID (groups one complete run)
├── tree_entity_id      UUID (FK: stable tree identity)
├── base_tree_id        → trees.Trees.tree_id (input measurement)
├── location_id        → shared.Locations
├── plot_id            → shared.Plots
├── scenario_id        → shared.Scenarios (e.g. Climate_Change_2050)
├── species_id         → shared.Species
├── simulator_name     SILVA | FVS | iLand | manual | other
├── simulator_version  free text
├── projection_year    integer (1900–2300)
├── time_delta_yrs     years since BaseVariant measurement date
│
├── Per-tree dimensions
│   ├── Height_m, DBH_cm, basal_area_m2
│   ├── crown_width_m, crown_base_height_m
│   ├── Volume_m3, Biomass_kg, carbon_content_kg
│   ├── health_score (0–1)
│   └── Mortality (boolean)
│
└── Stand-level aggregates (repeated across all trees in a run_id+Year)
    ├── stand_basal_area_m2ha
    ├── stand_volume_m3ha
    ├── stand_biomass_tha
    └── stand_stem_count_ha
```

---

## Public API views

### `public.growth_simulations`

Flat view with `scenario_name` and `species_name` pre-resolved. Primary UE query target.

```
# Get all trees in a scenario at a projected year
GET /growth_simulations?scenario_name=eq.Climate_Change_2050&projection_year=eq.2050

# Time series for one tree
GET /growth_simulations?tree_entity_id=eq.{uuid}&simulator_name=eq.SILVA&order=projection_year

# All trees at a location in year 2075
GET /growth_simulations?location_id=eq.1&projection_year=eq.2075
```

### `public.simulation_runs`

One row per `run_id` — summary of the run (simulator, scenario, year range, tree count). Use to populate a simulation run selector in UE before loading detailed data.

```
GET /simulation_runs
GET /simulation_runs?scenario_name=eq.Climate_Change_2050
```

---

## Permissions

| Role             | GrowthSimulations | simulation_runs |
|------------------|-------------------|-----------------|
| `anon`           | SELECT            | SELECT          |
| `authenticated`  | SELECT + INSERT   | SELECT          |
| `service_role`   | ALL               | ALL             |

`authenticated` INSERT is the write path for SILVA write-back (XRFF-245). The SILVA coupling script authenticates as `authenticated` and bulk-inserts rows after each simulator run.

---

## Adding a new simulator

1. Confirm `simulator_name` is one of `SILVA | FVS | iLand | manual | other`. If adding a new name, update the CHECK constraint in the schema migration and add an `ALTER TABLE` migration.
2. Map simulator output columns to the table columns (see XRFF-244 for the SILVA input view).
3. Set `run_id = gen_random_uuid()` at the start of the write-back script; use the same value for all rows in that run.
4. Always set `base_tree_id` to the `trees.Trees.tree_id` row that was used as the simulation starting point.
5. Populate `species_id` via `SELECT species_id FROM shared.Species WHERE scientific_name = '...'`.

---

## Relationship to `trees.Trees`

`trees.Trees` holds **snapshot variants** — discrete measured or estimated states of a tree at a point in time. `trees.GrowthSimulations` holds **trajectory projections** — the output of a mathematical model predicting how those trees will develop over decades.

The two tables are complementary: `trees.Trees` is the source of truth for what was measured; `trees.GrowthSimulations` is where simulator output lands before potentially being promoted back into `trees.Trees` as `simulated_growth` variants (see XRFF-245).

---

## Downstream tasks

- **XRFF-244** — SILVA coupling: input view that formats current inventory as SILVA input format
- **XRFF-245** — SILVA coupling: write-back workflow that populates this table after a SILVA run
- **XRFF-242** — HTTPS blueprint: Time Machine slider reads `growth_simulations` by year
