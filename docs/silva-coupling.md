# SILVA Coupling

**Issues:** XRFF-244 (input view), XRFF-245 (write-back)  
**Status:** Draft — pending verification against Freiburg colleagues' R implementation

---

## Overview

The coupling pipeline is:

```
shared.silva_input view
       ↓  (R: dbGetQuery)
   SILVA 4.5 R model
       ↓  (R: write.csv)
    silva_output.csv
       ↓  (Python: silva_writeback.py)
trees.GrowthSimulations
       ↓  (PostgREST)
   public.growth_simulations view
       ↓  (HTTPS Blueprint)
   Unreal Engine Time Machine
```

---

## Step 1 — Export current inventory as SILVA input

From R (or psql):

```r
library(DBI)
library(RPostgres)

con <- dbConnect(Postgres(),
  host     = "localhost",
  port     = 5432,
  dbname   = "postgres",
  user     = "postgres",
  password = Sys.getenv("DB_PASSWORD")
)

silva_trees <- dbGetQuery(con,
  "SELECT * FROM silva_input
   WHERE scenario_name = 'Current_Conditions'
   AND   location_name = 'Ecosense_MixedPlot'"
)
```

The view returns SILVA-standard columns plus `tree_entity_id` and `base_variant_id` for write-back join. **The R script must carry these two columns through to the output CSV** — they are how `silva_writeback.py` links projected rows back to DB entities.

⚠ **Verify before first run:**
- Are the column aliases (`h`, `d`, `hkb`, `kb`, `bid`, `ba`) exactly what the in-house R implementation expects?
- Is the coordinate system correct? The view produces UTM 32N (EPSG:32632) metres relative to plot centre.
- Are the species codes (`ba`) consistent with the in-house lookup?

---

## Step 2 — Run SILVA

Run SILVA in R as usual. SILVA will project tree dimensions at 5-year (or custom) time steps.

Ensure the output CSV includes at minimum:
- `year` — projection calendar year
- `nr`, `bid` — tree/stand identifiers (from input)
- `h`, `d`, `hkb`, `kb` — projected dimensions
- `mort` — mortality flag (0/1)
- `tree_entity_id`, `base_variant_id` — pass-through from input

Optional but useful:
- `ba_m2`, `vol` — per-tree basal area and volume
- `g_ha`, `v_ha`, `n_ha` — stand-level aggregates

---

## Step 3 — Write back to DB

```bash
python scripts/silva/silva_writeback.py \
    --input   silva_output.csv \
    --scenario Climate_Change_2050 \
    --simulator SILVA \
    --version 4.5 \
    --location Ecosense_MixedPlot
```

This generates a new `run_id` UUID and bulk-inserts all rows into `trees.GrowthSimulations`.

Dry-run (no insert, just inspect mapped columns):
```bash
python scripts/silva/silva_writeback.py --input silva_output.csv --scenario Climate_Change_2050 --dry-run
```

---

## Step 4 — Query from UE

```
# All trees projected to 2050 under climate scenario
GET /growth_simulations?scenario_name=eq.Climate_Change_2050&projection_year=eq.2050

# Time series for one tree entity
GET /growth_simulations?tree_entity_id=eq.{uuid}&simulator_name=eq.SILVA&order=projection_year

# List available simulation runs
GET /simulation_runs
GET /simulation_runs?scenario_name=eq.Climate_Change_2050
```

---

## Column mapping reference

| SILVA output col | DB column                     | Unit     | Notes |
|-----------------|-------------------------------|----------|-------|
| `year`          | `projection_year`              | year     | calendar year |
| `h`             | `height_m`                    | m        | total height |
| `d`             | `dbh_cm`                      | cm       | DBH at 1.3 m |
| `hkb`           | `crown_base_height_m`           | m        | Kronenbasis |
| `kb`            | `crown_width_m`                | m        | Kronenbreite |
| `ba_m2`         | `basal_area_m2`                | m²       | per tree |
| `vol`           | `volume_m3`                   | m³       | per tree |
| `mort`          | `mortality`                   | bool     | 1 = dies this step |
| `g_ha`          | `stand_basal_area_m2ha`         | m²/ha    | stand aggregate |
| `v_ha`          | `stand_volume_m3ha`            | m³/ha    | stand aggregate |
| `n_ha`          | `stand_stem_count_ha`           | /ha      | stand aggregate |
| `tree_entity_id`| `tree_entity_id`                | UUID     | DB join key |
| `base_variant_id`| `basevariantid`              | integer  | DB join key |

---

## SILVA species codes (ba)

Defined in `27-silva-input-view.sql`. Verify these match the in-house lookup:

| ba | scientific_name         | German name  |
|----|------------------------|--------------|
|  1 | Picea abies            | Fichte       |
|  2 | Abies alba             | Weißtanne    |
|  3 | Pinus sylvestris       | Kiefer       |
|  4 | Pseudotsuga menziesii  | Douglasie    |
|  5 | Larix decidua          | Lärche       |
| 11 | Fagus sylvatica        | Buche        |
| 15 | Quercus robur          | Stieleiche   |
| 20 | Betula pendula         | Birke        |
| 22 | Fraxinus excelsior     | Esche        |
| 24 | Acer pseudoplatanus    | Bergahorn    |
| 25 | Tilia cordata          | Winterlinde  |
| 30 | Prunus avium           | Vogelkirsche |
| 33 | Torminalis glaberrima  | Elsbeere     |

---

## What colleagues need to confirm

- [ ] Column aliases in their R script match the `silva_input` view column names
- [ ] Species code (`ba`) lookup is consistent
- [ ] Coordinate system: do they expect UTM 32N local metres, or something else?
- [ ] Which stand-level output columns their SILVA version produces (`g_ha`, `v_ha`, `n_ha`?)
- [ ] Whether `tree_entity_id` / `base_variant_id` pass-through is feasible in their workflow

---

## Files

| File | Purpose |
|------|---------|
| `docker/volumes/db/init/27-silva-input-view.sql` | `public.silva_input` view |
| `docker/volumes/db/init/26-growth-simulations-schema.sql` | Output table + public views |
| `scripts/silva/silva_writeback.py` | Python write-back script |
| `docs/silva-coupling.md` | This document |
