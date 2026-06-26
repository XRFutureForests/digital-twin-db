"""
XRFF-245 — SILVA output write-back to trees.GrowthSimulations.

Reads the CSV that the SILVA R script exports, maps columns to our schema,
and bulk-inserts rows into trees.GrowthSimulations via the Supabase REST API.

Usage
-----
    python scripts/silva/silva_writeback.py \\
        --input silva_output.csv \\
        --scenario Climate_Change_2050 \\
        --simulator SILVA \\
        --version 4.5 \\
        --location Ecosense_MixedPlot

Prerequisites
-------------
    pip install httpx pandas python-dotenv

Environment (.env in repo root or docker/)
-------------------------------------------
    SUPABASE_URL=http://localhost:8000          # or production URL
    SUPABASE_SERVICE_KEY=<service_role_key>     # write access required

⚠ DRAFT — column mapping (SILVA_TO_DB below) must be verified against
  the actual CSV the Freiburg R script produces. The SILVA column names
  here follow the standard SILVA 4.5 output specification.
"""

from __future__ import annotations

import argparse
import os
import sys
import uuid
from pathlib import Path

import httpx
import pandas as pd
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Column mapping: SILVA output CSV → trees.GrowthSimulations
# ⚠ VERIFY these against the actual R output before first use (XRFF-244)
# ---------------------------------------------------------------------------
SILVA_TO_DB: dict[str, str] = {
    # SILVA col      → DB column
    "year":          "projectionyear",       # projection calendar year
    "nr":            "_nr",                  # tree number (used for entity lookup)
    "bid":           "_bid",                 # stand/plot id (for location lookup)
    "bid2":          "_bid2",                # sub-plot id
    "h":             "height_m",             # total height (m)
    "d":             "dbh_cm",               # DBH at 1.3 m (cm)
    "hkb":           "crownbaseheight_m",    # crown base height (m)
    "kb":            "crownwidth_m",         # crown width (m)
    "ba_m2":         "basalarea_m2",         # basal area per tree (m²)  — may be absent
    "vol":           "volume_m3",            # stem volume (m³)  — may be absent
    "mort":          "mortality",            # mortality flag (0/1)
    # Stand-level columns (same value repeated across all trees in a step)
    "g_ha":          "standbasalarea_m2ha",  # stand basal area (m²/ha)
    "v_ha":          "standvolume_m3ha",     # stand volume (m³/ha)
    "n_ha":          "standstemcount_ha",    # stem count (stems/ha)
    # Carry-through columns from silva_input (added by R script for join-back)
    "tree_entity_id":  "treeentityid",
    "base_tree_id":    "basetreeid",
    "species_id":      "speciesid",
    "location_id":     "locationid",
    "plot_id":         "plotid",
}

ENDPOINT = "/rest/v1/rpc/insert_growth_simulations"   # or direct table endpoint below
TABLE_ENDPOINT = "/rest/v1/growth_simulations"


def load_silva_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    # Normalise column names to lowercase
    df.columns = [c.strip().lower() for c in df.columns]
    return df


def map_columns(df: pd.DataFrame, run_id: str, simulator: str, version: str,
                scenario_id: int) -> list[dict]:
    """Rename SILVA columns to DB column names and add run metadata."""
    # Rename known columns
    rename = {k: v for k, v in SILVA_TO_DB.items() if k in df.columns}
    df = df.rename(columns=rename)

    # Add run-level metadata (same for every row)
    df["runid"]           = run_id
    df["simulatorname"]   = simulator
    df["simulatorversion"] = version
    df["scenarioid"]      = scenario_id

    # Coerce types
    if "projectionyear" in df.columns:
        df["projectionyear"] = df["projectionyear"].astype(int)
    if "mortality" in df.columns:
        df["mortality"] = df["mortality"].astype(bool)

    # Drop internal join columns that are not DB columns
    df = df.drop(columns=[c for c in ["_nr", "_bid", "_bid2"] if c in df.columns],
                 errors="ignore")

    # Drop any column not in the DB schema (safety guard)
    known_db_cols = set(SILVA_TO_DB.values()) | {
        "runid", "simulatorname", "simulatorversion", "scenarioid",
        "treeentityid", "basetreeid", "locationid", "plotid", "speciesid",
        "projectionyear", "timedelta_yrs",
        "height_m", "dbh_cm", "basalarea_m2", "crownwidth_m", "crownbaseheight_m",
        "volume_m3", "biomass_kg", "carboncontent_kg", "healthscore", "mortality",
        "standbasalarea_m2ha", "standvolume_m3ha", "standbio_tha", "standstemcount_ha",
    }
    extra = [c for c in df.columns if c not in known_db_cols]
    if extra:
        print(f"[warn] Dropping unrecognised columns: {extra}")
        df = df.drop(columns=extra, errors="ignore")

    return df.where(pd.notnull(df), None).to_dict(orient="records")


def get_scenario_id(base_url: str, headers: dict, scenario_name: str) -> int:
    r = httpx.get(f"{base_url}/rest/v1/scenarios",
                  params={"scenarioname": f"eq.{scenario_name}", "select": "scenarioid"},
                  headers=headers)
    r.raise_for_status()
    rows = r.json()
    if not rows:
        raise ValueError(f"Scenario '{scenario_name}' not found in DB")
    return rows[0]["scenarioid"]


def insert_rows(base_url: str, headers: dict, rows: list[dict],
                batch_size: int = 500) -> int:
    """POST rows to the PostgREST table endpoint in batches."""
    total = 0
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        r = httpx.post(
            f"{base_url}{TABLE_ENDPOINT}",
            json=batch,
            headers={**headers, "Prefer": "return=minimal"},
            timeout=30,
        )
        r.raise_for_status()
        total += len(batch)
        print(f"  inserted rows {i + 1}–{total}")
    return total


def main() -> None:
    load_dotenv(Path(__file__).parent.parent.parent / "docker" / ".env")
    load_dotenv(Path(__file__).parent.parent.parent / ".env")   # fallback

    parser = argparse.ArgumentParser(description="Write SILVA output to trees.GrowthSimulations")
    parser.add_argument("--input",      required=True, help="Path to SILVA output CSV")
    parser.add_argument("--scenario",   required=True, help="Scenario name (e.g. Climate_Change_2050)")
    parser.add_argument("--simulator",  default="SILVA", choices=["SILVA", "FVS", "iLand", "manual", "other"])
    parser.add_argument("--version",    default="4.5",   help="Simulator version string")
    parser.add_argument("--location",   default=None,    help="Location name (informational only)")
    parser.add_argument("--run-id",     default=None,    help="UUID for this run (auto-generated if omitted)")
    parser.add_argument("--dry-run",    action="store_true", help="Parse and map columns; do not insert")
    args = parser.parse_args()

    base_url = os.environ.get("SUPABASE_URL", "http://localhost:8000")
    service_key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ.get("SERVICE_ROLE_KEY")
    if not service_key:
        sys.exit("Error: SUPABASE_SERVICE_KEY not set")

    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }

    run_id = args.run_id or str(uuid.uuid4())
    print(f"Run ID : {run_id}")
    print(f"Input  : {args.input}")
    print(f"Scenario: {args.scenario}  Simulator: {args.simulator} {args.version}")

    # Resolve scenario ID
    scenario_id = get_scenario_id(base_url, headers, args.scenario)
    print(f"Scenario ID: {scenario_id}")

    # Load and map
    df = load_silva_csv(Path(args.input))
    print(f"Loaded {len(df)} rows, columns: {list(df.columns)}")

    rows = map_columns(df, run_id, args.simulator, args.version, scenario_id)
    print(f"Mapped to {len(rows)} DB rows")

    if args.dry_run:
        print("[dry-run] First row sample:")
        import json
        print(json.dumps(rows[0] if rows else {}, indent=2, default=str))
        return

    # Insert
    n = insert_rows(base_url, headers, rows)
    print(f"✓ Inserted {n} rows into trees.GrowthSimulations (RunID: {run_id})")
    print(f"  Query: GET /growth_simulations?runid=eq.{run_id}&order=treeentityid,projectionyear")


if __name__ == "__main__":
    main()
