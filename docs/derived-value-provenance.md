# Derived-Value Provenance and Uncertainty

**Issues:** XRFF-401 (this decision), XRFF-400 (`height_source` default), XRFF-369 (the
`shared.AttributeProvenance` precedent this follows)
**Status:** Decision recorded 2026-09-03. Not yet implemented.

Most numbers in `trees.Trees` are not measurements. Volume, crown width, crown base
height, age, biomass and carbon are all model output, and each is stored as a bare
point value with no statement of which model produced it or how wrong it might be.
This page decides how that changes.

---

## What is actually true today

XRFF-401 was filed on the premise that ~26,800 NULLs were *about to* be filled, and
that the convention had to be settled first. That window has closed. The reference
database now holds:

| Column | NULL | Total |
|---|---|---|
| `trees.volume_m3` | 0 | 11,125 |
| `trees.crown_width_m` | 0 | 11,125 |
| `trees.crown_base_height_m` | 0 | 11,125 |
| `trees.stems.stem_volume_m3` | 0 | 11,126 |
| `trees.biomass_kg` | 40 | 11,125 |
| `trees.carbon_content_kg` | 40 | 11,125 |
| `trees.age_years` | 1,640 | 11,125 |

The volume and crown fills are done. What remains is 1,640 ages and 40
biomass/carbon rows, not 26,800 of anything. So this is no longer a decision taken
*ahead* of a bulk write — it is a decision about a backfill, and it should be judged
on whether the resulting capability is worth the backfill cost rather than on urgency.

It is still worth taking, because a second and more serious gap turned up while
checking the first.

---

## The real gap: provenance, not intervals

`shared.Processes` already holds good, distinct, well-cited rows for each fill:

```
 1 | Tree Age Estimation      | 0.3.0
 2 | Tree Biomass Estimation  | 0.3.0
 4 | Tree Allometry           | 2.2.0
```

`trees.Trees.process_id` only ever holds **3** (Forest Growth Simulation) or **4**
(Tree Allometry). Processes 1 and 2 are never referenced by the rows they produced.

This is not an oversight in the fill scripts. `process_id` is **one column for the
whole row**, and a single tree's values come from four different places at once — its
geometry from SILVA, its height from a pylometree H-D model, its biomass from
Forrester 2017, its age from a Chapman-Richards inversion. One FK cannot say four
things, so `fill_missing_biomass.py` correctly declines to overwrite it, and the
provenance is simply lost.

What is lost is specific and it matters:

* **Which equation.** `fill_missing_biomass.py` applies six species-specific
  equations drawn from two publications — `forrester2017_*_agb` for five species,
  `zianis2005_eq526_*` for *Pseudotsuga menziesii*. All six collapse into one
  unreferenced process row. Per tree, the equation is unrecoverable.
* **Whether the tree was extrapolated.** Each equation carries a fitted DBH range
  (*Abies alba* 5.7–57.7 cm, *Fagus sylvatica* 1.0–84.0 cm, and so on). The script
  computes which trees fall outside their equation's range and reports the count in
  the run summary — then discards it. A tree whose biomass was extrapolated well past
  the fitted domain is indistinguishable from one comfortably inside it.

An uncertainty column cannot be filled honestly without both of these. The interval
question is downstream of the identity question, which is why this document answers
the identity question first.

---

## Decision

### 1. Per-column provenance for trees, in the shape XRFF-369 already established

`shared.AttributeProvenance` (`location_id`, `column_name`, `process_id`,
`fetched_at`, `source_uri`, `license`) solved exactly this problem for
`shared.Locations` on 2026-09-02, and it solved it by **not** adding N `*_source`
columns. Trees get the same shape:

```
trees.AttributeProvenance
    tree_id      integer  NOT NULL  REFERENCES trees.Trees ON DELETE CASCADE
    column_name  varchar(64) NOT NULL
    process_id   integer  NOT NULL  REFERENCES shared.Processes ON DELETE RESTRICT
    UNIQUE (tree_id, column_name)
```

One row per derived value, naming the process that produced it. `process_id` on
`trees.Trees` keeps its current meaning — how the tree record as a whole was produced
— and stops being asked to do a job it cannot do.

### 2. Uncertainty attaches to the provenance row, not to `trees.Trees`

The literal question in XRFF-401 was `*_uncertainty` versus `*_ci_low`/`*_ci_high`.
The answer is **neither, as columns on `trees.Trees`**. Six derived values times two
or three interval columns is twelve to eighteen new columns on an already wide table,
each meaningful for exactly one other column — the same design `shared.AttributeProvenance`
was created to avoid. They go on the provenance row:

```
    value_sd       numeric        -- 1 SD of the prediction, where the model gives one
    ci_low         numeric        -- interval bounds, where the model gives them
    ci_high        numeric
    ci_coverage    numeric(4,3)   -- e.g. 0.950; NOT NULL whenever ci_low is set
    extrapolated   boolean        -- covariate outside the model's fitted domain
```

Three properties this buys that columns on `trees.Trees` would not:

* A value with no interval is a **missing row or NULL bounds**, never an implied
  certainty — the XRFF-400 lesson applied to uncertainty.
* `ci_coverage` is stored beside the bounds, so an 80% and a 95% interval cannot be
  compared by accident. Kondratev et al. 2025 argue the useful validation question is
  whether a stated 80% interval contains the truth 80% of the time; that is only
  answerable if the coverage level travels with the bounds.
* `extrapolated` is recorded rather than printed and thrown away.

### 3. Model-level statistics live on `shared.Processes`, one row per model

A per-prediction interval is not available today. `pylometree`'s registry
`predict()` returns a bare `float`, and the fit statistics that do exist are free
text in the entry's `notes` field:

```
"n=20, r2=0.974, D 5.7-62.1 cm, Czech Republic. Widest fitted DBH range ..."
```

So the cheap first step is not per-row intervals at all — it is splitting
`Tree Allometry` and `Tree Biomass Estimation` into **one `shared.Processes` row per
model and coefficient set**, and putting `n`, `r²`, RMSE and the valid covariate
domain into `param_schema` (jsonb, already on the table) as parsed fields rather than
prose. That alone makes "which equation, fitted on what, valid over what range"
answerable for every derived value, with no new interval mathematics.

`value_sd` / `ci_*` then fill in per row later, for whichever models grow the ability
to produce them, without a further schema change.

---

## Consequences

**In `digital-twin-db`:**

* New `trees.AttributeProvenance` table, plus a write helper mirroring
  `public.set_location_attributes`.
* Backfill for the values already written: every one is attributable at the
  *column × fill-run* level from the existing scripts, so the backfill is a set of
  `INSERT ... SELECT` statements, not a re-run of the models.
* `fill_missing_ages.py`, `fill_missing_biomass.py`, `fill_missing_heights.py` and
  `silva-connector`'s fill each record a provenance row per value they write.

**In `pylometree`:**

* Structure the registry `notes` string into real fields (`n`, `r2`, `rmse`,
  covariate domain). This is a prerequisite for step 3 and is useful on its own.
* Give `predict()` an optional interval return, model by model, as the underlying
  fits allow. Not required for steps 1–3.

**Deliberately not decided here:** whether `height_source` folds into
`trees.AttributeProvenance`. It is the one derived value that already has a working
per-column marker (XRFF-400), it is read by `public.trees` and
`trees.trees_with_metrics`, and collapsing it is a migration with consumers attached.
Revisit once the table exists and has earned its keep.

---

## References

* Kondratev et al. 2025 — empirical interval coverage as the validation target.
  See `08-LITERATURE/digital-forest-twin-inventory-uncertainty.md` in the vault.
* Forrester DI et al. (2017) *Forest Ecology and Management* 396:160–175.
  doi:10.1016/j.foreco.2017.04.011
* Zianis D et al. (2005) *Silva Fennica Monographs* 4. doi:10.14214/sf.sfm4
* XRFF-369 / migration `20260902140000_open_data_landing_zones.sql` — the
  `shared.AttributeProvenance` precedent.
