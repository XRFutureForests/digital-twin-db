#!/usr/bin/env python3
"""Emit a Process Run Crate (RO-Crate) for one recorded pipeline run.

XRFF-407. `shared.Processes` records that a process exists and
`trees.SimulationRuns` records that a run happened. What no artefact stated
until now is the full binding -- *this input state + this software version +
these parameters produced these rows* -- which is what makes a result
reproducible and citable by someone outside the lab.

Why one emitter reading the database, rather than one per connector
------------------------------------------------------------------
The obvious reading of XRFF-407 is "each connector writes its own crate". That
would mean five bespoke emitters, written against five different runtimes (the
SILVA connector is R, the rest are Python), all of which would be rewritten when
the XRFF-346 job runner lands and every run starts flowing through
`shared.ProcessingJobs`.

Every fact a crate needs is already in the database, so the crate is generated
*from* the database instead. Today that means `trees.SimulationRuns` (the only
table holding complete run records -- `shared.ProcessingJobs` exists but has
never held a row). When the runner lands, `--job-id` reads the same shape out of
`ProcessingJobs` and every connector is covered without touching any of them.

Which profile, and why not the one the issue names
--------------------------------------------------
Workflow Run RO-Crate is a family of three profiles. The issue says "Workflow
Run Crate"; that one describes a *workflow engine* orchestrating steps it did
not itself implement, and we have no workflow definition to point at. A SILVA
run is a single tool invocation, which is exactly Process Run Crate:

    https://w3id.org/ro/wfrun/process/0.5

Claiming the workflow profile without a workflow would be precisely the
self-declared conformance BioDT warns against, in the issue that exists to stop
us doing that. Revisit if a job ever fans out into steps.

The crate is *detached*: it has no payload files, because the outputs are
database rows, not files. Entities reference those rows by their PostgREST
collection URI and by the identifiers we already own -- Zenodo DOIs on the code
repos, an ORCID for the author.

Usage
-----
    python scripts/provenance/emit_ro_crate.py --list
    python scripts/provenance/emit_ro_crate.py --run-id <uuid> -o crates/
    python scripts/provenance/emit_ro_crate.py --all -o crates/
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection  # noqa: E402

# Versioned permalinks. Both are load-bearing: they are the conformance claim.
RO_CRATE_CONTEXT = "https://w3id.org/ro/crate/1.1/context"
WFRUN_CONTEXT = "https://w3id.org/ro/terms/workflow-run/context"
PROCESS_RUN_CRATE = "https://w3id.org/ro/wfrun/process/0.5"
RO_CRATE_SPEC = "https://w3id.org/ro/crate/1.1"

# The API a crate reader should follow to reach the rows themselves. Overridable
# for a deployment that publishes under a different origin.
DEFAULT_API_BASE = "https://dt.unr.uni-freiburg.de/db/rest/v1"

# Identifiers we already own, from the repos' CITATION.cff.
AUTHOR_ORCID = "https://orcid.org/0009-0003-6131-6244"
AUTHOR_NAME = "Maximilian Sperlich"
DB_DOI = "https://doi.org/10.5281/zenodo.21509858"
LICENSE = "https://spdx.org/licenses/AGPL-3.0-or-later"

# Software the database knows by name but has no DOI column for. Keyed on
# shared.Processes.process_name.
SOFTWARE_URLS = {
    "Forest Growth Simulation": "https://gitlab.uni-freiburg.de/xr-future-forests-lab/silva-connector",
    "Tree Age Estimation": "https://doi.org/10.5281/zenodo.21509863",
    "Tree Biomass Estimation": "https://doi.org/10.5281/zenodo.21509863",
    "Tree Model Generation": "https://doi.org/10.5281/zenodo.21509856",
}

RUN_QUERY = """
    SELECT r.run_id, r.location_id, r.scenario_id, r.base_variant_id,
           r.base_year, r.simulator_name, r.simulator_version, r.process_id,
           r.horizon_years, r.seed, r.mortality_enabled, r.promoted,
           r.run_params, r.created_at, r.created_by,
           p.process_name, p.algorithm_name, p.version AS process_version,
           p.description AS process_description, p.author, p.citation,
           l.location_name, s.scenario_name, bv.variant_name AS base_variant_name
    FROM trees.simulationruns r
    LEFT JOIN shared.processes p ON p.process_id = r.process_id
    LEFT JOIN shared.locations l ON l.location_id = r.location_id
    LEFT JOIN shared.scenarios s ON s.scenario_id = r.scenario_id
    LEFT JOIN shared.variants bv ON bv.variant_id = r.base_variant_id
"""


def fetch_runs(cur, run_id=None):
    if run_id:
        cur.execute(RUN_QUERY + " WHERE r.run_id = %s", (run_id,))
    else:
        cur.execute(RUN_QUERY + " ORDER BY r.created_at")
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def fetch_outputs(cur, run):
    """What this run produced.

    Two different strengths of evidence, and the crate says which is which:

    * `trees.GrowthSimulations` rows carry `run_id`, so they are attributed
      exactly.
    * `shared.Variants` do not. The chain is recovered by walking
      `parent_variant_id` down from the base variant, which is correct as long
      as one promoted chain descends from a given baseline. Two promoted runs
      from the same baseline would be indistinguishable here -- recorded as a
      known limitation rather than papered over.
    """
    cur.execute(
        "SELECT COUNT(*), MIN(projection_year), MAX(projection_year) "
        "FROM trees.growthsimulations WHERE run_id = %s",
        (run["run_id"],),
    )
    n_traj, y0, y1 = cur.fetchone()

    cur.execute(
        """
        WITH RECURSIVE chain AS (
            SELECT variant_id, variant_name, simulation_year, variant_type_id
            FROM shared.variants WHERE variant_id = %s
            UNION ALL
            SELECT v.variant_id, v.variant_name, v.simulation_year, v.variant_type_id
            FROM shared.variants v JOIN chain c ON v.parent_variant_id = c.variant_id
        )
        SELECT variant_id, variant_name, simulation_year FROM chain
        WHERE variant_id <> %s AND variant_type_id = 4
        ORDER BY simulation_year
        """,
        (run["base_variant_id"], run["base_variant_id"]),
    )
    variants = [
        {"variant_id": v, "variant_name": n, "simulation_year": y}
        for v, n, y in cur.fetchall()
    ]

    cur.execute(
        "SELECT COUNT(*) FROM trees.trees WHERE variant_id = ANY(%s)",
        ([v["variant_id"] for v in variants] or [-1],),
    )
    n_trees = cur.fetchone()[0]
    return {
        "trajectory_rows": n_traj,
        "year_from": y0,
        "year_to": y1,
        "variants": variants,
        "tree_rows": n_trees,
    }


def parameter_entities(run):
    """Typed columns and run_params jsonb, flattened into PropertyValue entities.

    Both halves matter: the typed columns are the simulator-agnostic parameters
    and `run_params` the SILVA-specific ones (XRFF-374). A crate that carried
    only one half would not reproduce the run.
    """
    params = {
        "base_year": run["base_year"],
        "horizon_years": run["horizon_years"],
        "seed": run["seed"],
        "mortality_enabled": run["mortality_enabled"],
        "promoted": run["promoted"],
    }
    params.update(run["run_params"] or {})
    out = []
    for key, value in params.items():
        if value is None:
            continue
        out.append(
            {
                "@id": f"#{run['run_id']}-param-{key}",
                "@type": "PropertyValue",
                "name": key,
                "value": value if isinstance(value, (int, float, bool)) else str(value),
            }
        )
    return out


def build_crate(run, outputs, api_base):
    run_id = str(run["run_id"])
    action_id = f"#run-{run_id}"
    software_id = SOFTWARE_URLS.get(
        run["process_name"], f"#process-{run['process_id']}"
    )
    base_variant_id = f"{api_base}/variants?variant_id=eq.{run['base_variant_id']}"
    trajectory_id = f"{api_base}/growth_simulations?run_id=eq.{run_id}"

    params = parameter_entities(run)

    # created_at is written at the START of the write-back transaction, before
    # any result row, because GrowthSimulations.run_id is a FK onto this table.
    # So it is neither the moment SILVA began computing nor the moment the run
    # finished. It is recorded as startTime, which is the strongest true claim
    # available, and the description says so rather than implying a precision
    # the database does not have.
    started = run["created_at"].isoformat()

    entities = [
        {
            "@id": "ro-crate-metadata.json",
            "@type": "CreativeWork",
            "conformsTo": {"@id": RO_CRATE_SPEC},
            "about": {"@id": "./"},
        },
        {
            "@id": "./",
            "@type": "Dataset",
            "name": (
                f"{run['simulator_name']} run {run_id[:8]} — "
                f"{run['location_name'] or 'unknown location'}"
            ),
            "description": (
                f"Provenance record for one {run['simulator_name']} "
                f"{run['simulator_version']} run over "
                f"{run['horizon_years']} years from base year {run['base_year']}, "
                f"on location '{run['location_name']}' under scenario "
                f"'{run['scenario_name']}'. Detached crate: the outputs are rows "
                f"in the XR Future Forests digital twin database, referenced by "
                f"their API collection URIs, not files in this crate."
            ),
            "datePublished": started,
            "license": {"@id": LICENSE},
            "author": {"@id": AUTHOR_ORCID},
            "conformsTo": {"@id": PROCESS_RUN_CRATE},
            "mentions": {"@id": action_id},
            "isBasedOn": {"@id": DB_DOI},
        },
        {"@id": PROCESS_RUN_CRATE, "@type": "CreativeWork", "name": "Process Run Crate"},
        {"@id": RO_CRATE_SPEC, "@type": "CreativeWork", "name": "RO-Crate 1.1"},
        {"@id": LICENSE, "@type": "CreativeWork", "name": "AGPL-3.0-or-later"},
        {"@id": AUTHOR_ORCID, "@type": "Person", "name": AUTHOR_NAME},
        {
            "@id": DB_DOI,
            "@type": "Dataset",
            "name": "XR Future Forests digital twin database",
        },
        {
            "@id": action_id,
            "@type": "CreateAction",
            "name": f"{run['simulator_name']} projection {run['base_year']}–"
            f"{run['base_year'] + (run['horizon_years'] or 0)}",
            "description": (
                "startTime is trees.SimulationRuns.created_at, which the connector "
                "writes at the start of the write-back transaction (GrowthSimulations "
                "carries a FK onto it). It therefore precedes every result row and "
                "follows the simulation itself; true simulation start and end are not "
                "recorded upstream. endTime is omitted rather than guessed."
            ),
            "instrument": {"@id": software_id},
            "startTime": started,
            "agent": {"@id": AUTHOR_ORCID},
            "object": [{"@id": base_variant_id}] + [{"@id": p["@id"]} for p in params],
            "result": [{"@id": trajectory_id}]
            + [
                {"@id": f"{api_base}/trees?variant_id=eq.{v['variant_id']}"}
                for v in outputs["variants"]
            ],
        },
        {
            "@id": software_id,
            "@type": ["SoftwareApplication", "SoftwareSourceCode"],
            "name": run["algorithm_name"] or run["process_name"],
            "softwareVersion": run["process_version"] or run["simulator_version"],
            "url": software_id if software_id.startswith("http") else None,
            "description": run["process_description"],
            "author": run["author"],
            "citation": run["citation"],
        },
        {
            "@id": base_variant_id,
            "@type": "Dataset",
            "name": f"Base state: variant '{run['base_variant_name']}' "
            f"({run['base_year']})",
            "description": "The measured forest state this run projected forward.",
        },
        {
            "@id": trajectory_id,
            "@type": "Dataset",
            "name": f"Per-tree trajectory rows for run {run_id[:8]}",
            "description": (
                f"{outputs['trajectory_rows']} rows in trees.GrowthSimulations, "
                f"{outputs['year_from']}–{outputs['year_to']}. Attributed to this run "
                f"exactly, by run_id."
            ),
        },
    ]

    for variant in outputs["variants"]:
        entities.append(
            {
                "@id": f"{api_base}/trees?variant_id=eq.{variant['variant_id']}",
                "@type": "Dataset",
                "name": f"Projected forest state '{variant['variant_name']}' "
                f"({variant['simulation_year']})",
                "description": (
                    "Attributed by walking parent_variant_id from the base variant: "
                    "shared.Variants carries no run_id, so this link is derived, not "
                    "recorded. It is unambiguous only while one promoted chain "
                    "descends from a given baseline."
                ),
            }
        )

    entities.extend(params)

    # Drop keys we had no value for rather than emitting nulls.
    entities = [{k: v for k, v in e.items() if v is not None} for e in entities]
    return {"@context": [RO_CRATE_CONTEXT, WFRUN_CONTEXT], "@graph": entities}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--run-id", help="trees.SimulationRuns.run_id (uuid)")
    g.add_argument("--all", action="store_true", help="emit a crate per recorded run")
    g.add_argument("--list", action="store_true", help="list recorded runs and exit")
    ap.add_argument("-o", "--out-dir", default="crates", help="output directory")
    ap.add_argument("--api-base", default=DEFAULT_API_BASE)
    args = ap.parse_args()

    conn = get_db_connection()
    cur = conn.cursor()
    runs = fetch_runs(cur, args.run_id)

    if not runs:
        print("No matching runs in trees.SimulationRuns.", file=sys.stderr)
        return 1

    if args.list:
        for r in runs:
            print(
                f"{r['run_id']}  {r['simulator_name']} {r['simulator_version']:>12}  "
                f"{r['location_name']:<12} {r['base_year']}+{r['horizon_years']}y  "
                f"{r['created_at']:%Y-%m-%d}"
            )
        return 0

    out_root = Path(args.out_dir)
    for run in runs:
        outputs = fetch_outputs(cur, run)
        crate = build_crate(run, outputs, args.api_base.rstrip("/"))
        crate_dir = out_root / f"run-{run['run_id']}"
        crate_dir.mkdir(parents=True, exist_ok=True)
        target = crate_dir / "ro-crate-metadata.json"
        target.write_text(json.dumps(crate, indent=2) + "\n", encoding="utf-8")
        print(
            f"{target}  ({outputs['trajectory_rows']} trajectory rows, "
            f"{len(outputs['variants'])} variants, {outputs['tree_rows']} trees)"
        )

    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
