#!/usr/bin/env python3
"""
Generic, provider-agnostic sensor data ingestion CLI.

Loads sensors and/or readings from CSV or JSON into the database via the two
bulk RPCs (`public.bulk_upsert_sensors`, `public.bulk_insert_readings`) --
the source-agnostic ingestion contract defined in the schema baseline
(formerly `22-aquarius-integration.sql`). Any provider's export (Aquarius,
a datalogger, a colleague's spreadsheet) can be loaded through this one path
by supplying a column mapping; no code changes needed per provider.

Both RPCs are idempotent (`bulk_upsert_sensors` upserts on `external_id`,
`bulk_insert_readings` skips on `(sensor_id, timestamp)` conflict), so
re-running this script against the same export is always safe.

Usage:
    python ingest_sensor_data.py sensors <file.csv|file.json> [options]
    python ingest_sensor_data.py readings <file.csv|file.json> [options]

Options:
    --mapping <file.json>   Map source column names -> RPC field names.
                            Default: identity mapping (source columns must
                            already be named like the RPC fields below).
    --dry-run               Validate and report without writing.
    --batch-size N          Rows per RPC call (default 500).

Sensor RPC fields (see docker/volumes/db/init/10-baseline-schema.sql):
    location_id, plot_id, source, sensor_type_id, sensor_model,
    serial_number, position (WKT, e.g. "POINT(7.8 47.9)"), latitude,
    longitude (used to build `position` if no WKT column is present),
    sampling_interval_seconds, unit, external_id, external_metadata (dict),
    is_active, created_by

Reading RPC fields:
    sensor_id (or external_id, resolved via a lookup against
    sensor.Sensors.external_id), timestamp, value, quality

Examples:
    python ingest_sensor_data.py sensors data/imports/my_sensors.csv --dry-run
    python ingest_sensor_data.py sensors data/imports/my_sensors.csv --mapping data/imports/my_sensor_mapping.json
    python ingest_sensor_data.py readings data/imports/my_readings.json
"""

import argparse
import json
import os
import sys
from pathlib import Path

import pandas as pd
import requests
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).parent.parent.parent
load_dotenv(PROJECT_ROOT / "docker" / ".env")

SERVICE_ROLE_KEY = os.getenv("SERVICE_ROLE_KEY", "")
SUPABASE_URL = os.getenv("SUPABASE_URL", "http://localhost:8000")
API_TIMEOUT = 60

SENSOR_REQUIRED = {"location_id", "sensor_type_id", "sensor_model", "sampling_interval_seconds"}
SENSOR_FIELDS = SENSOR_REQUIRED | {
    "plot_id", "source", "serial_number", "position", "latitude", "longitude",
    "unit", "external_id", "external_metadata", "is_active", "created_by",
}
READING_REQUIRED = {"timestamp", "value"}
READING_FIELDS = READING_REQUIRED | {"sensor_id", "external_id", "quality"}
VALID_QUALITY = {"good", "suspect", "bad", "missing", "calibration"}


def supabase_headers() -> dict:
    return {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def supabase_get(table: str, select: str = "*", filters: dict | None = None) -> list:
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    params = {"select": select}
    if filters:
        params.update(filters)
    response = requests.get(url, headers=supabase_headers(), params=params, timeout=30)
    response.raise_for_status()
    return response.json()


def supabase_rpc(function: str, params: dict) -> list:
    url = f"{SUPABASE_URL}/rest/v1/rpc/{function}"
    response = requests.post(url, headers=supabase_headers(), json=params, timeout=120)
    response.raise_for_status()
    return response.json()


def load_records(path: Path) -> list[dict]:
    """Load rows from CSV or JSON as a list of plain dicts."""
    if path.suffix.lower() == ".json":
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            data = data.get("records", data.get("data", [data]))
        return list(data)
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    return df.to_dict(orient="records")


def apply_mapping(records: list[dict], mapping: dict[str, str] | None) -> list[dict]:
    """Rename source columns to RPC field names. Unmapped columns pass through unchanged."""
    if not mapping:
        return records
    return [
        {mapping.get(k, k): v for k, v in row.items() if v not in (None, "")}
        for row in records
    ]


def load_mapping(path: str | None) -> dict[str, str] | None:
    if not path:
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def coerce_sensor(row: dict, row_num: int) -> tuple[dict | None, str | None]:
    """Validate and coerce one sensor row. Returns (payload, error) -- exactly one is None."""
    missing = SENSOR_REQUIRED - {k for k, v in row.items() if v not in (None, "")}
    if missing:
        return None, f"row {row_num}: missing required field(s) {sorted(missing)}"

    out: dict = {}
    try:
        out["location_id"] = int(row["location_id"])
        out["sensor_type_id"] = int(row["sensor_type_id"])
        out["sampling_interval_seconds"] = int(row["sampling_interval_seconds"])
    except (ValueError, TypeError) as e:
        return None, f"row {row_num}: {e}"

    if out["sampling_interval_seconds"] <= 0:
        return None, f"row {row_num}: sampling_interval_seconds must be > 0"

    out["sensor_model"] = str(row["sensor_model"])

    if row.get("plot_id") not in (None, ""):
        out["plot_id"] = int(row["plot_id"])
    out["source"] = row.get("source") or None
    out["serial_number"] = row.get("serial_number") or None
    out["unit"] = row.get("unit") or None
    out["external_id"] = row.get("external_id") or None
    out["is_active"] = str(row.get("is_active", "true")).lower() not in ("false", "0", "")
    out["created_by"] = row.get("created_by") or "ingest_sensor_data"

    if row.get("position"):
        out["position"] = row["position"]
    elif row.get("latitude") not in (None, "") and row.get("longitude") not in (None, ""):
        try:
            lat, lon = float(row["latitude"]), float(row["longitude"])
        except ValueError as e:
            return None, f"row {row_num}: invalid latitude/longitude: {e}"
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return None, f"row {row_num}: latitude/longitude out of range"
        out["position"] = f"POINT({lon} {lat})"
    else:
        return None, f"row {row_num}: no 'position' and no latitude/longitude pair"

    metadata = row.get("external_metadata")
    if metadata:
        out["external_metadata"] = metadata if isinstance(metadata, dict) else json.loads(metadata)

    return out, None


def coerce_reading(row: dict, row_num: int, sensor_id_by_external: dict[str, int]) -> tuple[dict | None, str | None]:
    missing = READING_REQUIRED - {k for k, v in row.items() if v not in (None, "")}
    if missing:
        return None, f"row {row_num}: missing required field(s) {sorted(missing)}"
    if not row.get("sensor_id") and not row.get("external_id"):
        return None, f"row {row_num}: needs 'sensor_id' or 'external_id'"

    out: dict = {}
    if row.get("sensor_id"):
        try:
            out["sensor_id"] = int(row["sensor_id"])
        except ValueError as e:
            return None, f"row {row_num}: invalid sensor_id: {e}"
    else:
        sensor_id = sensor_id_by_external.get(row["external_id"])
        if sensor_id is None:
            return None, f"row {row_num}: external_id '{row['external_id']}' has no matching sensor"
        out["sensor_id"] = sensor_id

    try:
        out["value"] = float(row["value"])
    except ValueError as e:
        return None, f"row {row_num}: invalid value: {e}"

    out["timestamp"] = row["timestamp"]

    quality = row.get("quality") or "good"
    if quality not in VALID_QUALITY:
        return None, f"row {row_num}: quality '{quality}' not in {sorted(VALID_QUALITY)}"
    out["quality"] = quality

    return out, None


def resolve_sensor_ids(external_ids: list[str]) -> dict[str, int]:
    """Look up sensor_id for each external_id, batching to avoid URL length limits."""
    mapping: dict[str, int] = {}
    batch_size = 50
    unique_ids = sorted(set(external_ids))
    for i in range(0, len(unique_ids), batch_size):
        batch = unique_ids[i : i + batch_size]
        filter_str = ",".join(f'"{eid}"' for eid in batch)
        rows = supabase_get("sensors", "sensor_id,external_id", {"external_id": f"in.({filter_str})"})
        for r in rows:
            mapping[r["external_id"]] = r["sensor_id"]
    return mapping


def ingest_sensors(records: list[dict], dry_run: bool, batch_size: int) -> None:
    valid, errors = [], []
    for i, row in enumerate(records, 1):
        payload, error = coerce_sensor(row, i)
        if error:
            errors.append(error)
        else:
            valid.append(payload)

    print(f"Read {len(records)} rows: {len(valid)} valid, {len(errors)} invalid")
    for e in errors[:20]:
        print(f"  - {e}")
    if len(errors) > 20:
        print(f"  ... and {len(errors) - 20} more")

    if dry_run:
        print(f"[dry-run] Would upsert {len(valid)} sensors (no rows written)")
        return

    written = 0
    for i in range(0, len(valid), batch_size):
        batch = valid[i : i + batch_size]
        result = supabase_rpc("bulk_upsert_sensors", {"p_sensors": batch})
        written += len(result) if isinstance(result, list) else 0

    print("=" * 60)
    print(f"Sensors read: {len(records)} | written: {written} | skipped/failed: {len(errors)}")
    print("=" * 60)


def ingest_readings(records: list[dict], dry_run: bool, batch_size: int) -> None:
    needs_lookup = [row.get("external_id") for row in records if not row.get("sensor_id") and row.get("external_id")]
    sensor_id_by_external = resolve_sensor_ids(needs_lookup) if needs_lookup else {}

    valid, errors = [], []
    for i, row in enumerate(records, 1):
        payload, error = coerce_reading(row, i, sensor_id_by_external)
        if error:
            errors.append(error)
        else:
            valid.append(payload)

    print(f"Read {len(records)} rows: {len(valid)} valid, {len(errors)} invalid")
    for e in errors[:20]:
        print(f"  - {e}")
    if len(errors) > 20:
        print(f"  ... and {len(errors) - 20} more")

    if dry_run:
        print(f"[dry-run] Would insert up to {len(valid)} readings (no rows written; some may already exist)")
        return

    inserted = 0
    for i in range(0, len(valid), batch_size):
        batch = valid[i : i + batch_size]
        result = supabase_rpc("bulk_insert_readings", {"readings": batch})
        if result:
            inserted += result[0].get("out_inserted_count", 0)

    skipped_existing = len(valid) - inserted
    print("=" * 60)
    print(
        f"Readings read: {len(records)} | inserted: {inserted} | "
        f"already present: {skipped_existing} | invalid: {len(errors)}"
    )
    print("=" * 60)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("kind", choices=["sensors", "readings"], help="What the file contains")
    parser.add_argument("file", type=Path, help="CSV or JSON source file")
    parser.add_argument("--mapping", help="JSON file mapping source column names -> RPC field names")
    parser.add_argument("--dry-run", action="store_true", help="Validate and report without writing")
    parser.add_argument("--batch-size", type=int, default=500, help="Rows per RPC call (default: 500)")
    args = parser.parse_args()

    if not args.file.exists():
        print(f"File not found: {args.file}")
        sys.exit(1)

    mapping = load_mapping(args.mapping)
    records = apply_mapping(load_records(args.file), mapping)

    if args.kind == "sensors":
        ingest_sensors(records, args.dry_run, args.batch_size)
    else:
        ingest_readings(records, args.dry_run, args.batch_size)


if __name__ == "__main__":
    main()
