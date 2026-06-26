# Growth Simulation Schema

**Issue:** XRFF-243  
**Schema file:** `docker/volumes/db/init/26-growth-simulations-schema.sql`

---

## Purpose

`trees.GrowthSimulations` is the write target for all forest growth simulator output. It stores per-tree dimensional projections at discrete future time steps, produced by simulators such as SILVA, FVS, or iLand, then served to UE via PostgREST for the Time Machine feature.

---

## Key concepts

### RunID

A UUID that groups every row produced by a single simulator execution. All rows sharing a `RunID` represent a complete, internally consistent forest state trajectory. UE uses `RunID` when it needs to compare two simulation runs side by side.

### TreeEntityID

The stable UUID for a physical tree, shared across all `trees.Trees` variant rows and all `trees.GrowthSimulations` rows. This is the join key between the measured baseline state and the projected future states.

### ProjectionYear

The calendar year the row describes. A typical SILVA run might output years 2025, 2030, 2035, …, 2100 — one row per tree per year step.

### BaseTreeID

The `trees.Trees.TreeID` row used as the simulation starting point (e.g. the 2024 field inventory row). Allows tracing which baseline measurement the projection was derived from.

---

## Table structure

```
trees.GrowthSimulations
├── GrowthSimulationID BIGSERIAL PK
├── RunID             UUID (groups one complete run)
├── TreeEntityID      UUID (FK: stable tree identity)
├── BaseTreeID        → trees.Trees.TreeID (input measurement)
├── LocationID        → shared.Locations
├── PlotID            → shared.Plots
├── ScenarioID        → shared.Scenarios (e.g. Climate_Change_2050)
├── SpeciesID         → shared.Species
├── SimulatorName     SILVA | FVS | iLand | manual | other
├── SimulatorVersion  free text
├── ProjectionYear    integer (1900–2300)
├── TimeDelta_yrs     years since BaseVariant measurement date
│
├── Per-tree dimensions
│   ├── Height_m, DBH_cm, BasalArea_m2
│   ├── CrownWidth_m, CrownBaseHeight_m
│   ├── Volume_m3, Biomass_kg, CarbonContent_kg
│   ├── HealthScore (0–1)
│   └── Mortality (boolean)
│
└── Stand-level aggregates (repeated across all trees in a RunID+Year)
    ├── StandBasalArea_m2ha
    ├── StandVolume_m3ha
    ├── StandBiomass_tha
    └── StandStemCount_ha
```

---

## Public API views

### `public.growth_simulations`

Flat view with `scenarioname` and `speciesname` pre-resolved. Primary UE query target.

```
# Get all trees in a scenario at a projected year
GET /growth_simulations?scenarioname=eq.Climate_Change_2050&projectionyear=eq.2050

# Time series for one tree
GET /growth_simulations?treeentityid=eq.{uuid}&simulatorname=eq.SILVA&order=projectionyear

# All trees at a location in year 2075
GET /growth_simulations?locationid=eq.1&projectionyear=eq.2075
```

### `public.simulation_runs`

One row per `RunID` — summary of the run (simulator, scenario, year range, tree count). Use to populate a simulation run selector in UE before loading detailed data.

```
GET /simulation_runs
GET /simulation_runs?scenarioname=eq.Climate_Change_2050
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

1. Confirm `SimulatorName` is one of `SILVA | FVS | iLand | manual | other`. If adding a new name, update the CHECK constraint in the schema migration and add an `ALTER TABLE` migration.
2. Map simulator output columns to the table columns (see XRFF-244 for the SILVA input view).
3. Set `RunID = gen_random_uuid()` at the start of the write-back script; use the same value for all rows in that run.
4. Always set `BaseTreeID` to the `trees.Trees.TreeID` row that was used as the simulation starting point.
5. Populate `SpeciesID` via `SELECT SpeciesID FROM shared.Species WHERE ScientificName = '...'`.

---

## Relationship to `trees.Trees`

`trees.Trees` holds **snapshot variants** — discrete measured or estimated states of a tree at a point in time. `trees.GrowthSimulations` holds **trajectory projections** — the output of a mathematical model predicting how those trees will develop over decades.

The two tables are complementary: `trees.Trees` is the source of truth for what was measured; `trees.GrowthSimulations` is where simulator output lands before potentially being promoted back into `trees.Trees` as `simulated_growth` variants (see XRFF-245).

---

## Downstream tasks

- **XRFF-244** — SILVA coupling: input view that formats current inventory as SILVA input format
- **XRFF-245** — SILVA coupling: write-back workflow that populates this table after a SILVA run
- **XRFF-242** — HTTPS blueprint: Time Machine slider reads `growth_simulations` by year
