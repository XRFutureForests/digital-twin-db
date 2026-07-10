"""
XRFF-245 — SILVA output write-back to trees.GrowthSimulations.

Reads the CSV that the SILVA R script exports, maps columns to our schema,
and bulk-inserts rows into trees.GrowthSimulations via the Supabase REST API.

Usage
-----
    python scripts/silva/silva_writeback.py \\
        --input silva_output.csv \\
        --scenario natural_growth \\
        --simulator SILVA \\
        --version 4.5 \\
        --location ecosense

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
    # SILVA col      → DB column (trees.GrowthSimulations, snake_case)
    "year":          "projection_year",       # projection calendar year
    "nr":            "_nr",                   # tree number (used for entity lookup)
    "bid":           "_bid",                  # stand/plot id (for location lookup)
    "bid2":          "_bid2",                 # sub-plot id
    "h":             "height_m",              # total height (m)
    "d":             "dbh_cm",                # DBH at 1.3 m (cm)
    "hkb":           "crown_base_height_m",   # crown base height (m)
    "kb":            "crown_width_m",         # crown width (m)
    "ba_m2":         "basal_area_m2",         # basal area per tree (m²)  — may be absent
    "vol":           "volume_m3",             # stem volume (m³)  — may be absent
    "mort":          "mortality",             # mortality flag (0/1)
    # Stand-level columns (same value repeated across all trees in a step)
    "g_ha":          "stand_basal_area_m2ha", # stand basal area (m²/ha)
    "v_ha":          "stand_volume_m3ha",     # stand volume (m³/ha)
    "n_ha":          "stand_stem_count_ha",   # stem count (stems/ha)
    # Carry-through columns from silva_input (added by R script for join-back)
    "tree_entity_id":  "tree_entity_id",
    "base_tree_id":    "base_tree_id",
    "species_id":      "species_id",
    "location_id":     "location_id",
    "plot_id":         "plot_id",
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
    df["run_id"]           = run_id
    df["simulator_name"]   = simulator
    df["simulator_version"] = version
    df["scenario_id"]      = scenario_id

    # Coerce types
    if "projection_year" in df.columns:
        df["projection_year"] = df["projection_year"].astype(int)
    if "mortality" in df.columns:
        df["mortality"] = df["mortality"].astype(bool)

    # Drop internal join columns that are not DB columns
    df = df.drop(columns=[c for c in ["_nr", "_bid", "_bid2"] if c in df.columns],
                 errors="ignore")

    # Drop any column not in the DB schema (safety guard)
    known_db_cols = set(SILVA_TO_DB.values()) | {
        "run_id", "simulator_name", "simulator_version", "scenario_id",
        "tree_entity_id", "base_tree_id", "location_id", "plot_id", "species_id",
        "projection_year", "time_delta_yrs",
        "height_m", "dbh_cm", "basal_area_m2", "crown_width_m", "crown_base_height_m",
        "volume_m3", "biomass_kg", "carbon_content_kg", "health_score", "mortality",
        "stand_basal_area_m2ha", "stand_volume_m3ha", "stand_biomass_tha", "stand_stem_count_ha",
    }
    extra = [c for c in df.columns if c not in known_db_cols]
    if extra:
        print(f"[warn] Dropping unrecognised columns: {extra}")
        df = df.drop(columns=extra, errors="ignore")

    return df.where(pd.notnull(df), None).to_dict(orient="records")


def get_scenario_id(base_url: str, headers: dict, scenario_name: str,
                    location_name: str | None = None) -> int:
    # Scenarios are location-scoped (unique per location), so a location is
    # needed to disambiguate. Resolve the location id first when provided.
    params = {"scenario_name": f"eq.{scenario_name}", "select": "scenario_id,location_id"}
    if location_name:
        loc = httpx.get(f"{base_url}/rest/v1/locations",
                        params={"location_name": f"eq.{location_name}", "select": "location_id"},
                        headers=headers)
        loc.raise_for_status()
        loc_rows = loc.json()
        if not loc_rows:
            raise ValueError(f"Location '{location_name}' not found in DB")
        params["location_id"] = f"eq.{loc_rows[0]['location_id']}"
    r = httpx.get(f"{base_url}/rest/v1/scenarios", params=params, headers=headers)
    r.raise_for_status()
    rows = r.json()
    if not rows:
        raise ValueError(f"Scenario '{scenario_name}' not found in DB")
    if len(rows) > 1:
        raise ValueError(
            f"Scenario '{scenario_name}' is ambiguous across locations; pass --location")
    return rows[0]["scenario_id"]


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
    parser.add_argument("--scenario",   required=True, help="Scenario name (e.g. natural_growth)")
    parser.add_argument("--simulator",  default="SILVA", choices=["SILVA", "FVS", "iLand", "manual", "other"])
    parser.add_argument("--version",    default="4.5",   help="Simulator version string")
    parser.add_argument("--location",   default=None,    help="Location name (e.g. ecosense) — disambiguates the location-scoped scenario")
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

    # Resolve scenario ID (location-scoped)
    scenario_id = get_scenario_id(base_url, headers, args.scenario, args.location)
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
