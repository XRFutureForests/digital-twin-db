#!/usr/bin/env python3
"""
Enrich sensor metadata from an Aquarius "Insitu DataUpload" .xlsx export.

Aquarius sensor time-series carry hardware/ownership metadata that the API sync
does not populate: the actual instrument model (e.g. SMT100, Implexx Sap Flow
Sensor, FloraPulse_Tensiometer) and the responsible data owner. The DB stores a
generic "Ecosense Node" placeholder in sensor.Sensors.SensorModel instead.

The upload form's SensorData / deadSensors / sapflow sheets key each series by
`TimeSeriesUniqueID`, which equals our sensor.Sensors.ExternalID. This script
matches on that ID and, for each match:

  - sets SensorModel to the real Instrument (when present)
  - merges Instrument / DataOwner / TypeOfMeasurement / GapTolerance into
    ExternalMetadata (existing keys are preserved unless re-supplied)

Idempotent. Only touches sensors whose ExternalID appears in the export.

IMPORTANT: run this AFTER an Aquarius sync (import_sensor_data.py /
sync_aquarius_direct.py). Those scripts upsert sensors and overwrite SensorModel
with the generic "Ecosense Node" placeholder and reset ExternalMetadata, so this
enrichment must be re-applied each time sensors are re-synced.

    python scripts/import/enrich_sensor_metadata.py [path/to/form.xlsx]
"""

import json
import os
import sys
from pathlib import Path

import openpyxl
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values

REPO_ROOT = Path(__file__).parent.parent.parent
DEFAULT_XLSX = REPO_ROOT / "tmp" / "Insitu_DataUpload_Form.xlsx"
SHEETS = ["SensorData", "deadSensors", "sapflow"]

load_dotenv(REPO_ROOT / "docker" / ".env")

POSTGRES_HOST = "localhost"
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DATABASE = os.getenv("POSTGRES_DB", "postgres")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POOLER_TENANT_ID = os.getenv("POOLER_TENANT_ID", "")
POSTGRES_USER_POOLER = (
    f"{POSTGRES_USER}.{POOLER_TENANT_ID}" if POOLER_TENANT_ID else POSTGRES_USER
)


def get_db_connection():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER_POOLER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )


def parse_metadata(xlsx_path):
    """externalid -> {Instrument, DataOwner, TypeOfMeasurement, GapTolerance}."""
    wb = openpyxl.load_workbook(xlsx_path, data_only=True, read_only=True)
    meta = {}
    for sheet in SHEETS:
        if sheet not in wb.sheetnames:
            continue
        header = None
        for row in wb[sheet].iter_rows(values_only=True):
            if header is None:
                labels = [str(c) if c is not None else "" for c in row]
                if "TimeSeriesUniqueID" in labels:
                    header = {c: i for i, c in enumerate(labels)}
                continue

            def cell(col):
                i = header.get(col)
                return row[i] if i is not None and i < len(row) else None

            guid = cell("TimeSeriesUniqueID")
            if not guid:
                continue
            fields = {
                "Instrument": cell("Instrument"),
                "DataOwner": cell("DataOwner"),
                "TypeOfMeasurement": cell("Type of measurement"),
                "GapTolerance": cell("GapTolerance"),
            }
            # Keep only non-empty values; last sheet wins on collision.
            meta[str(guid).strip()] = {
                k: str(v).strip() for k, v in fields.items() if v not in (None, "")
            }
    print(f"📄 Parsed {len(meta)} sensor metadata entries from {xlsx_path.name}")
    return meta


def enrich(conn, meta):
    cur = conn.cursor()
    cur.execute(
        "SELECT externalid FROM sensor.sensors WHERE externalid IS NOT NULL"
    )
    db_ids = {r[0] for r in cur.fetchall()}
    matched = [eid for eid in db_ids if eid in meta]
    print(f"🔎 {len(db_ids)} sensors with ExternalID; {len(matched)} matched in export")
    if not matched:
        return 0

    rows = []
    for eid in matched:
        m = meta[eid]
        rows.append((eid, m.get("Instrument"), json.dumps(m)))

    # fetch=True aggregates RETURNING rows across all internal pages; cur.rowcount
    # would only reflect the last batch that execute_values sends.
    returned = execute_values(
        cur,
        """
        UPDATE sensor.sensors s SET
            sensormodel = COALESCE(NULLIF(v.instrument, ''), s.sensormodel),
            externalmetadata = COALESCE(s.externalmetadata, '{}'::jsonb) || v.meta::jsonb,
            updatedby = 'enrich_sensor_metadata_script'
        FROM (VALUES %s) AS v(externalid, instrument, meta)
        WHERE s.externalid = v.externalid
        RETURNING s.sensorid
        """,
        rows,
        template="(%s, %s, %s::jsonb)",
        fetch=True,
    )
    updated = len(returned)
    conn.commit()
    print(f"✓ Enriched {updated} sensors")
    return updated


def verify(conn):
    cur = conn.cursor()
    cur.execute(
        """
        SELECT sensormodel, COUNT(*)
        FROM sensor.sensors
        WHERE externalmetadata ? 'Instrument'
        GROUP BY sensormodel ORDER BY COUNT(*) DESC
        """
    )
    print("\n📊 SensorModel distribution (enriched sensors):")
    for model, count in cur.fetchall():
        print(f"  {model}: {count}")


def main():
    xlsx_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_XLSX
    print("=" * 80)
    print("SENSOR METADATA ENRICHMENT")
    print("=" * 80)
    if not xlsx_path.exists():
        print(f"❌ Export not found: {xlsx_path}")
        return 1

    conn = get_db_connection()
    try:
        meta = parse_metadata(xlsx_path)
        updated = enrich(conn, meta)
        if updated:
            verify(conn)
        print("\n✅ DONE")
        return 0
    except Exception as e:
        conn.rollback()
        print(f"\n❌ Enrichment failed: {e}")
        import traceback

        traceback.print_exc()
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
