# SILVA Coupling

**Issues:** XRFF-245 (write-back), XRFF-374 (run parameters), XRFF-351 (this rewrite)
**Status:** Live. Two runs written 2026-09-01 (ecosense 1,495 trees, mathisle 730).

The SILVA single-tree growth model is coupled to this database by
[**silva-connector**](../../silva-connector), a separate repo. That repo's
`README.md` is the operator's guide; this page describes the coupling from the
database side — which tables are touched, what is written, and what a consumer
can read back.

> **Superseded.** Until 2026-09-02 this page described a CSV round-trip
> (`public.silva_input` → hand-run R → `silva_output.csv` →
> `scripts/silva/silva_writeback.py`). That pipeline was never implemented. The
> view, the script and the CSV format are gone; see
> [Retired: the CSV round-trip](#retired-the-csv-round-trip) at the end.

---

## How it actually runs

silva-connector is an R container that joins this stack's docker network and
talks to `dftdb-db` over libpq. There is no file interchange and no REST hop.

```
shared.Variants + trees.Trees      the baseline forest state
       ↓  (R: DBI::dbGetQuery, direct on the trees/shared schemas)
   silvaR (vendored TUM SILVA implementation)
       ↓  (one transaction over libpq)
trees.SimulationRuns   ── what was asked for
trees.GrowthSimulations ── the per-tree trajectory
shared.Variants + trees.Trees ── one new variant per 5-year period
       ↓  (PostgREST)
public.simulation_runs / public.growth_simulations / public.ue_trees
       ↓  (HTTPS Blueprint)
   Unreal Engine time machine
```

One invocation:

```bash
cd silva-connector
export PGPASSWORD=...          # digital-twin-db/docker/.env -> POSTGRES_PASSWORD

docker compose -f docker/docker-compose.yml run --rm silvar \
  Rscript /work/scripts/run_simulation.R \
    --location ecosense --scenario natural_growth \
    --base-variant baseline_2025 --years 20 --replace
```

Runtime is 32 s for ecosense (1,495 trees) and 9 s for mathisle (730), both over
a 20-year horizon.

Options: `--location` (required), `--scenario`, `--base-variant`, `--years`
(multiple of 5), `--competition` (`sf_polygon` | `rect_sum` | `legacy`),
`--mortality`, `--seed`, `--variant-prefix`, `--replace`, `--no-promote`,
`--dry-run`.

---

## What a run writes

Three targets, in one transaction. A partially written run would read as a real
forest state to every downstream consumer, so it is all or nothing.

| Target | Holds | On re-run |
|---|---|---|
| `trees.SimulationRuns` | one row: the run's parameters and identity | accumulates |
| `trees.GrowthSimulations` | every per-tree projection of the run, keyed by `run_id`, plus stand aggregates | accumulates |
| `shared.Variants` + `trees.Trees` (+ `trees.Stems`) | one complete forest **state** per 5-year period, chained by `parent_variant_id` | replaced — variant names are unique per (location, scenario), so `--replace` is required |

The split is what makes scenario comparison possible: only one run can hold the
variant chain UE reads, but any number of trajectories can sit side by side
under their own `run_id`. `--no-promote` writes the first two targets and leaves
the chain alone.

### Reading a run back

Every run records the parameters that produced it (XRFF-374) — without that,
two runs differing only by `--seed` would be indistinguishable.

```sql
SELECT run_id, location_name, scenario_name,
       base_variant, base_year, horizon_years,
       seed, mortality_enabled, promoted,
       run_params ->> 'competition' AS competition,
       first_year, last_year, tree_count
FROM   public.simulation_runs
ORDER  BY created_at DESC;
```

Simulator-agnostic parameters are columns; SILVA-specific ones
(`competition`, `variant_prefix`, `replace`) are keys in `run_params`. A key
absent on a run from before 2026-09-02 means it was not recorded, not that it
was unset.

`trees.GrowthSimulations.run_id` is a foreign key onto `trees.SimulationRuns`,
so a trajectory can no longer exist without a record of what produced it.

### Stand aggregates

Per hectare over the convex hull of the tree positions (ecosense 2.891 ha,
mathisle 1.173 ha), counting **living** stems only: a standing dead stem is
habitat, not growing stock. Per-tree `volume_m3` comes from
`ForestElementsR::v_gri()`, SILVA's own German volume function.

### Mortality

silvaR drops a dead tree from later snapshots and retro-tags its last living
row. The connector instead carries the tree forward into every later period with
its dimensions frozen at death and a `tree_status_id` of dead or harvested — a
tree that silently vanishes between two variants is indistinguishable from data
loss, and a snag is real forest structure UE has to render.

---

## Querying from Unreal

```
# One projected forest state — the time machine
GET /rest/v1/ue_trees?variant_id=eq.<id>

# Per-tree trajectory of one run
GET /rest/v1/growth_simulations?run_id=eq.<uuid>&order=tree_entity_id,projection_year

# Available runs
GET /rest/v1/simulation_runs?order=created_at.desc
```

---

## Species coding

silvaR works in ForestElementsR's `tum_wwk_short`, which has nine classes:

| code | species | code | species |
|---|---|---|---|
| 1 | *Picea abies* | 6 | *Quercus* spp. |
| 2 | *Abies alba* | 7 | *Pseudotsuga menziesii* |
| 3 | *Pinus sylvestris* | 8 | other broadleaf |
| 4 | *Larix decidua* | 9 | *Alnus glutinosa* |
| 5 | *Fagus sylvatica* | | |

The mapping is from `shared.Species.scientific_name`, in
`silva-connector/R/species.R`. It is deliberately **not** the legacy SILVA 4.5
coding (`4 = Douglasie, 5 = Laerche, 11 = Buche`) that the old `silva_input`
view emitted: the two collide on 4, 5 and 6, so mixing them silently turns
Douglas fir into larch and larch into beech.

There is no "other conifer" class on purpose — an unmapped conifer is an error
rather than a silent substitution into spruce.

---

## Site conditions

`shared.Locations` carries `forest_growth_region`, `soil_moistness` and
`soil_nutrient_supply` (added by migration `20260831120000`), which is what
silvaR's site model needs. `silva-connector/docs/site-conditions.md` and
`soil-classes.md` document the class definitions.

---

## Retired: the CSV round-trip

`public.silva_input`, `scripts/silva/silva_writeback.py` and the CSV column
mapping they implied were removed on 2026-09-02 (XRFF-351). They described a
workflow that never ran. Three things were wrong with the view beyond its being
unused, each verified against the running database before removal:

- its `ba` column emitted legacy SILVA 4.5 species codes, which collide with
  `tum_wwk_short` on 4, 5 and 6;
- its data-source filter (`field | lidar | photogrammetry`) returned 1,198 of
  the 2,225 measured trees and *zero* mathisle trees, all of which are typed
  `estimated`;
- it offered no way to select a base variant, so it could only ever describe the
  measured baseline.

The write-back script was a self-declared draft whose column mapping had never
been checked against any real SILVA output.

If an export surface is ever wanted again, it should be written fresh against
`scientific_name` and absolute coordinates — not restored from
`supabase/migrations/20260717093000_baseline_snapshot.sql`.
