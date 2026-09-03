"""Process Run Crate emission for recorded runs (XRFF-407).

Checks the emitter against every run in trees.SimulationRuns: the crate must
satisfy the Process Run Crate 0.5 MUSTs, resolve all of its own references, and
carry the parameters that make the run reproducible.

Structural rather than library-based: ro-crate-py is not a dependency of this
repo, and the profile's requirements are few and explicit enough to assert
directly. If ro-crate-py is ever added for other reasons, its validator is a
strictly better check than these assertions and should replace them.
"""

import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "provenance"))
from emit_ro_crate import (  # noqa: E402
    PROCESS_RUN_CRATE,
    RO_CRATE_CONTEXT,
    build_crate,
    fetch_outputs,
    fetch_runs,
)
from utils.db import get_db_connection  # noqa: E402

API_BASE = "https://example.org/rest/v1"


@pytest.fixture(scope="module")
def crates():
    conn = get_db_connection()
    cur = conn.cursor()
    runs = fetch_runs(cur)
    if not runs:
        pytest.skip("no runs in trees.SimulationRuns")
    out = [(r, build_crate(r, fetch_outputs(cur, r), API_BASE)) for r in runs]
    cur.close()
    conn.close()
    return out


def index(crate):
    return {e["@id"]: e for e in crate["@graph"]}


def test_context_and_profile(crates):
    for _, crate in crates:
        assert RO_CRATE_CONTEXT in crate["@context"]
        by_id = index(crate)
        assert by_id["./"]["conformsTo"]["@id"] == PROCESS_RUN_CRATE
        # The profile MUST itself be a defined CreativeWork entity.
        assert "CreativeWork" in str(by_id[PROCESS_RUN_CRATE]["@type"])


def test_metadata_descriptor(crates):
    for _, crate in crates:
        desc = index(crate)["ro-crate-metadata.json"]
        assert desc["@type"] == "CreativeWork"
        assert desc["about"]["@id"] == "./"


def test_single_action_with_required_properties(crates):
    for _, crate in crates:
        actions = [e for e in crate["@graph"] if e.get("@type") == "CreateAction"]
        assert len(actions) == 1
        act = actions[0]
        assert act["instrument"]["@id"]
        assert act["object"] and act["result"]
        assert act["agent"]["@id"].startswith("https://orcid.org/")
        # startTime, never a fabricated endTime: see build_crate.
        assert "startTime" in act
        assert "endTime" not in act


def test_instrument_is_software_with_version(crates):
    for _, crate in crates:
        by_id = index(crate)
        act = next(e for e in crate["@graph"] if e.get("@type") == "CreateAction")
        instr = by_id[act["instrument"]["@id"]]
        assert any(
            t in str(instr["@type"])
            for t in ("SoftwareApplication", "SoftwareSourceCode", "ComputationalWorkflow")
        )
        assert instr["softwareVersion"]


def test_no_dangling_references(crates):
    for _, crate in crates:
        by_id = index(crate)
        seen = set()
        for entity in crate["@graph"]:
            for value in entity.values():
                items = value if isinstance(value, list) else [value]
                for item in items:
                    if isinstance(item, dict) and "@id" in item:
                        seen.add(item["@id"])
        assert not (seen - by_id.keys())


def test_ids_unique(crates):
    for _, crate in crates:
        ids = [e["@id"] for e in crate["@graph"]]
        assert len(ids) == len(set(ids))


def test_reproducibility_parameters_present(crates):
    """Typed columns and run_params jsonb both have to survive into the crate."""
    for run, crate in crates:
        names = {
            e["name"] for e in crate["@graph"] if e.get("@type") == "PropertyValue"
        }
        assert {"seed", "horizon_years", "base_year"} <= names
        assert set(run["run_params"] or {}) <= names


def test_outputs_reference_the_run(crates):
    for run, crate in crates:
        act = next(e for e in crate["@graph"] if e.get("@type") == "CreateAction")
        results = {r["@id"] for r in act["result"]}
        assert any(str(run["run_id"]) in r for r in results), "trajectory not attributed"
        assert len(results) > 1, "projected variants missing from results"


def test_no_null_values(crates):
    for _, crate in crates:
        for entity in crate["@graph"]:
            assert all(v is not None for v in entity.values())


def test_serialises_as_json(crates):
    for _, crate in crates:
        assert json.loads(json.dumps(crate))
