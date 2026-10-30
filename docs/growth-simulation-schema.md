# Growth Simulation Schema

Where growth-simulator output lands: `trees.simulation_runs` (one row per run) and
`trees.growth_simulations` (one row per tree per projected year). Columns, types and constraints:
[database-dictionary.md — trees.simulation_runs](database-dictionary.md#treessimulation_runs) and
[trees.growth_simulations](database-dictionary.md#treesgrowth_simulations). How a SILVA run is
started and what it writes: [silva-coupling.md](silva-coupling.md).

**Last Updated:** 2026-10-30

---

## The two tables

| Table | One row per | Key columns |
|---|---|---|
| `trees.simulation_runs` | simulator run | `simulation_run_id` (UUID PK), `location_id`, `scenario_id`, `base_variant_id` → `shared.variants`, `base_year`, `horizon_years`, `simulator_name`, `simulator_version`, `process_id`, `seed`, `is_mortality_enabled`, `is_promoted`, `run_params` (JSONB object) |
| `trees.growth_simulations` | tree × projected year of one run | `simulation_run_id` → `trees.simulation_runs`, `tree_entity_id`, `base_tree_id` → `trees.trees`, `location_id`, `plot_id`, `scenario_id`, `species_id`, `projection_year`, `time_delta_yrs`, per-tree dimensions, `is_mortality`, stand aggregates |

- `tree_entity_id` is the physical tree's UUID, the same one `trees.trees` uses across variants.
  It joins projections to measured rows; it has no foreign key.
- `base_tree_id` is the `trees.trees` row the run started from.
- Per-tree dimensions: `height_m`, `dbh_cm`, `basal_area_m2`, `crown_width_m`,
  `crown_base_height_m`, `volume_m3`, `biomass_kg`, `carbon_content_kg`, `health_score` (0–1).
- `is_mortality` (boolean, default false) marks a tree that died in that period.
- Stand aggregates repeat on every row of a run and year: `stand_basal_area_m2ha`,
  `stand_volume_m3ha`, `stand_biomass_tha`, `stand_stem_count_ha`.
- `simulator_name` is constrained to `SILVA`, `FVS`, `iLand`, `manual` or `other` on both tables;
  `projection_year` and `base_year` to 1900–2300.

## How rows get there

silva-connector is the only writer. It connects over libpq (`PGUSER`, default `postgres`) and
writes in one transaction:

1. one `trees.simulation_runs` row with the run's parameters,
2. the trajectory in `trees.growth_simulations`,
3. unless `--no-promote` is given, one `shared.variants` row plus its `trees.trees` and
   `trees.stems` rows per 5-year period (`silva_2030`, `silva_2035`, …), chained by
   `parent_variant_id`. `is_promoted` records whether this happened.

Promotion is the default. Unreal reads the promoted variants through `public.ue_trees` (see
[variant-scenario-model.md](variant-scenario-model.md)); `growth_simulations` keeps every run's
trajectory side by side for comparison.

## Reading

`public.growth_simulations` and `public.simulation_runs` are read-only views (not insertable)
that resolve names:

- `public.growth_simulations` adds `scenario_name`, `species_name`, `scientific_name`.
- `public.simulation_runs` adds `scenario_name`, `location_name`, `base_variant_name`,
  `first_year`, `last_year`, `year_steps`, `tree_count`.

```
# Runs for a scenario
GET /rest/v1/simulation_runs?scenario_name=eq.natural_growth

# All trees of one run in one projected year
GET /rest/v1/growth_simulations?simulation_run_id=eq.<uuid>&projection_year=eq.2050

# One tree's trajectory in one run
GET /rest/v1/growth_simulations?simulation_run_id=eq.<uuid>&tree_entity_id=eq.<uuid>&order=projection_year
```

Several runs can exist for the same scenario, so filter on `simulation_run_id` (or on `scenario_name`
and `location_id` together) to avoid mixing runs and sites.

## Permissions

| Object | anon | authenticated | service_role |
|---|---|---|---|
| `public.growth_simulations` (view) | SELECT | SELECT | SELECT |
| `public.simulation_runs` (view) | SELECT | SELECT | SELECT |
| `trees.growth_simulations` | — | — | — |
| `trees.simulation_runs` (RLS) | SELECT | SELECT; INSERT if contributor; UPDATE / DELETE if curator | ALL |

Both views run with their owner's rights, so they read the base tables for every caller.
`trees.growth_simulations` has RLS off and no grants to the API roles; reads go through the
view.

## Adding a simulator

1. If the name is not one of `SILVA | FVS | iLand | manual | other`, change the
   `simulator_name` CHECK constraint on both tables in a new migration.
2. Register the simulator as a `shared.processes` row and set `process_id` on the run.
3. Write one `trees.simulation_runs` row first, then the `trees.growth_simulations` rows with its
   `simulation_run_id` and `base_tree_id` / `tree_entity_id` from the starting variant, in one
   transaction.
