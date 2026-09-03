# Run Provenance — RO-Crate

**Issues:** XRFF-407
**Status:** Live for `trees.SimulationRuns`. Emits for both recorded SILVA runs.

`shared.Processes` says a process exists. `trees.SimulationRuns` says a run
happened. Neither states the binding that makes a result reproducible by someone
outside the lab: *this input state + this software version + these parameters
produced these rows*. `scripts/provenance/emit_ro_crate.py` writes that binding
as an RO-Crate.

```bash
python scripts/provenance/emit_ro_crate.py --list
python scripts/provenance/emit_ro_crate.py --run-id <uuid> -o crates/
python scripts/provenance/emit_ro_crate.py --all -o crates/
```

Output is one directory per run containing `ro-crate-metadata.json`. `crates/` is
gitignored — a crate is regenerable from the database at any time, so archive one
deliberately (with a paper, or beside a Zenodo deposit) rather than carrying it
in the repo.

---

## One emitter reading the database, not one per connector

The obvious reading of XRFF-407 is that each connector writes its own crate at
the end of its run. That would be five bespoke emitters across two runtimes —
silva-connector is R, the rest are Python — and all five would be rewritten when
the XRFF-346 job runner lands and every run starts flowing through
`shared.ProcessingJobs`.

Every fact a crate needs is already in the database, so the crate is generated
*from* the database. Today that means `trees.SimulationRuns`, which is the only
table holding complete run records: `shared.ProcessingJobs` exists, has the right
shape, and has never held a row. When the runner lands, a `--job-id` path reads
the same structure out of `ProcessingJobs` and every connector is covered without
any connector changing.

## Which profile

Workflow Run RO-Crate is a family of three profiles. XRFF-407 names "Workflow Run
Crate"; that profile describes a **workflow engine** orchestrating steps it did
not itself implement, and we have no workflow definition to point at. A SILVA run
is a single tool invocation, which is what **Process Run Crate** describes:

```
https://w3id.org/ro/wfrun/process/0.5
```

Claiming the workflow profile without a workflow would be exactly the
self-declared conformance BioDT warns against — in the issue that exists to stop
us doing that. Revisit if a job ever fans out into steps that are themselves
recorded.

The crates are **detached**: no payload files, because the outputs are database
rows. Entities reference those rows by PostgREST collection URI and reuse the
identifiers we already own — the Zenodo DOI on `digital-twin-db`, an ORCID for
the author, and the `citation` already stored on the `shared.Processes` row.

## What a crate asserts, and how strongly

| Element | Source | Strength |
|---|---|---|
| Software, version, citation, author | `shared.Processes` | recorded |
| Parameters | `SimulationRuns` typed columns + `run_params` jsonb | recorded |
| Input state | `base_variant_id` | recorded |
| Trajectory rows | `GrowthSimulations.run_id` | recorded, exact |
| Projected variants | walk of `parent_variant_id` | **derived** |
| Time | `created_at` | **approximate** |

The last two are stated as limitations inside the crate itself rather than
smoothed over:

* **Variants carry no `run_id`.** The output chain is recovered by walking
  `parent_variant_id` down from the base variant and keeping the
  `simulated_growth` ones. That is unambiguous only while a single promoted chain
  descends from a given baseline; two promoted runs from the same baseline would
  be indistinguishable. Adding `run_id` to `shared.Variants` would close this.
* **`created_at` is not the run's end.** The connector writes the
  `SimulationRuns` row *before* the trajectory, because `GrowthSimulations.run_id`
  is an FK onto it. So the timestamp follows the simulation and precedes every
  result row. It is emitted as `startTime`, which is the strongest true claim
  available; `endTime` is omitted rather than guessed. Recording real
  `started_at` / `completed_at` in silva-connector would close this, and
  `ProcessingJobs` already has both columns for when the runner lands.

## Tests

`tests/automated/e2e/provenance/test_ro_crate.py` asserts the profile's MUSTs
against every run in the database: profile conformance, a single `CreateAction`
with `instrument`/`object`/`result`/`agent`, a software entity with a version, no
dangling `@id` references, unique ids, and that both halves of the parameter set
(typed columns and `run_params`) survive into the crate.

The checks are structural because `ro-crate-py` is not a dependency of this repo.
If it is ever added for other reasons, its validator is a strictly better check
and should replace them.
