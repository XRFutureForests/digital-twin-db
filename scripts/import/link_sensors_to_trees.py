#!/usr/bin/env python3
"""
Link Ecosense sensors to their inventory trees via the Aquarius name map.

Aquarius names each sensor time-series with a per-species, per-plot-type
sequence number (e.g. "Beech_Mixed_8", "DouglasFir_Pure_10"). That number is
independent of our inventory tree numbering (plot x TreeNumber, e.g. tree 8_16)
and Aquarius does not carry the inventory ID, so the two systems cannot be
joined from Aquarius data alone.

data/reference/ecosense_sensor_tree_map.csv is the field-surveyed decoder ring
mapping each Aquarius name to a tree's full_id (plot_id x tree_id). This script:

  1. Backfills trees.Trees.AquariusName for the mapped trees (resolved by
     plot_id + tree_number at the Ecosense location).
  2. Links every sensor whose serialnumber prefix equals a tree's AquariusName
     to that tree in sensor.sensor_tree_links — the whole monitoring cluster
     (dendrometer, sap flow, stem water potential, and the surrounding soil
     moisture / soil temperature probes share the same Aquarius prefix).

Idempotent: re-running only adds missing links and refreshes AquariusName.

    python scripts/import/link_sensors_to_trees.py
"""

import csv
import os
import re
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values

REPO_ROOT = Path(__file__).parent.parent.parent
REFERENCE_CSV = REPO_ROOT / "data" / "reference" / "ecosense_sensor_tree_map.csv"

# Load environment
load_dotenv(REPO_ROOT / "docker" / ".env")

# Database configuration
POSTGRES_HOST = "localhost"
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DATABASE = os.getenv("POSTGRES_DB", "postgres")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POOLER_TENANT_ID = os.getenv("POOLER_TENANT_ID", "")

if POOLER_TENANT_ID:
    POSTGRES_USER_POOLER = f"{POSTGRES_USER}.{POOLER_TENANT_ID}"
else:
    POSTGRES_USER_POOLER = POSTGRES_USER

CREATED_BY = "link_sensors_trees_script"

# Aquarius serialnumber prefix: {Species}_{PlotType}_{Seq}, e.g. Beech_Mixed_8.
# The remainder of the serialnumber is the sensor role (e.g. _Dendrometer,
# _Total_SapFlow, _stem_N). Requires alphabetic species + plot type so that
# non-matching labels like "Beech_18_Dendrometer" are ignored.
PREFIX_RE = re.compile(r"^([A-Za-z]+_[A-Za-z]+_\d+)")


def get_db_connection():
    """Create database connection"""
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER_POOLER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )


def load_reference_map():
    """Load the Aquarius-name -> tree mapping from the reference CSV."""
    if not REFERENCE_CSV.exists():
        raise FileNotFoundError(f"Reference map not found: {REFERENCE_CSV}")

    rows = []
    with open(REFERENCE_CSV, newline="") as f:
        for r in csv.DictReader(f):
            rows.append(
                {
                    "aquarius_name": r["aquarius_name"].strip(),
                    "full_id": r["full_id"].strip(),
                    "plot_id": int(r["plot_id"]),
                    "tree_number": int(r["tree_id"]),
                }
            )
    print(f"📄 Loaded {len(rows)} Aquarius→tree mappings from reference CSV")
    return rows


def backfill_aquarius_names(conn, mappings):
    """
    Set trees.Trees.AquariusName for each mapped tree, resolved by
    (plot_id, tree_number) at an Ecosense location. Returns
    {aquarius_name: (tree_id, full_id)} for the trees that were resolved.
    """
    print("\n🌲 Backfilling trees.AquariusName...")
    cur = conn.cursor()
    resolved = {}
    unresolved = []
    ambiguous = []

    for m in mappings:
        cur.execute(
            """
            SELECT t.treeid
            FROM trees.trees t
            JOIN shared.locations l ON t.locationid = l.locationid
            WHERE l.locationname LIKE 'Ecosense_%%'
              AND t.plotid = %s
              AND t.treenumber = %s
            """,
            (m["plot_id"], m["tree_number"]),
        )
        tree_ids = [row[0] for row in cur.fetchall()]

        if len(tree_ids) == 1:
            tree_id = tree_ids[0]
            cur.execute(
                "UPDATE trees.trees SET aquariusname = %s WHERE treeid = %s",
                (m["aquarius_name"], tree_id),
            )
            resolved[m["aquarius_name"]] = (tree_id, m["full_id"])
        elif len(tree_ids) > 1:
            ambiguous.append((m["full_id"], m["aquarius_name"], tree_ids))
        else:
            unresolved.append((m["full_id"], m["aquarius_name"]))

    conn.commit()
    print(f"✓ Set AquariusName on {len(resolved)} trees")
    if ambiguous:
        print(f"⚠️  {len(ambiguous)} mappings matched multiple trees (skipped):")
        for full_id, aq, ids in ambiguous:
            print(f"     {full_id} ({aq}) → treeids {ids}")
    if unresolved:
        print(f"⚠️  {len(unresolved)} mappings had no matching tree (not imported yet):")
        for full_id, aq in unresolved:
            print(f"     {full_id} ({aq})")

    return resolved


def get_ecosense_sensors(conn):
    """Fetch all Ecosense sensors with their serialnumber."""
    cur = conn.cursor()
    cur.execute(
        """
        SELECT s.sensorid, s.serialnumber
        FROM sensor.sensors s
        JOIN shared.locations l ON s.locationid = l.locationid
        WHERE l.locationname LIKE 'Ecosense_%'
          AND s.serialnumber IS NOT NULL
        """
    )
    sensors = [{"sensor_id": r[0], "label": r[1]} for r in cur.fetchall()]
    print(f"\n📡 Found {len(sensors)} Ecosense sensors")
    return sensors


def build_links(sensors, resolved):
    """
    Match each sensor's serialnumber prefix to a resolved AquariusName and
    build the whole-cluster links. Returns (links, unmatched_prefix_count).
    """
    print("\n🔗 Matching sensors to trees by Aquarius prefix...")
    links = []
    matched_prefixes = set()
    unmatched_prefixes = set()

    for s in sensors:
        m = PREFIX_RE.match(s["label"])
        if not m:
            continue
        prefix = m.group(1)
        hit = resolved.get(prefix)
        if not hit:
            unmatched_prefixes.add(prefix)
            continue
        tree_id, full_id = hit
        matched_prefixes.add(prefix)
        links.append(
            {
                "sensor_id": s["sensor_id"],
                "tree_id": tree_id,
                "description": (
                    f"Ecosense cluster sensor '{s['label']}' linked via "
                    f"AquariusName '{prefix}' → tree {full_id}"
                ),
            }
        )

    print(
        f"✓ {len(links)} sensor links across {len(matched_prefixes)} sensor-trees"
    )
    if unmatched_prefixes:
        print(
            f"ℹ️  {len(unmatched_prefixes)} sensor prefixes had no AquariusName "
            f"tree (meteo/soil-pit/experiment or tree not yet mapped): "
            f"{', '.join(sorted(unmatched_prefixes)[:10])}"
            + (" ..." if len(unmatched_prefixes) > 10 else "")
        )
    return links


def insert_links(conn, links):
    """Insert sensor-tree links; returns number of new rows."""
    if not links:
        print("\n⚠️  No links to insert")
        return 0

    print(f"\n💾 Inserting {len(links)} sensor-tree links...")
    cur = conn.cursor()
    values = [(l["sensor_id"], l["tree_id"], l["description"]) for l in links]
    # RETURNING + fetch=True gives the truly-inserted rows; ON CONFLICT rows are
    # not returned. cur.rowcount is unreliable here because execute_values pages
    # the INSERT into batches and only reports the last batch's count.
    returned = execute_values(
        cur,
        """
        INSERT INTO sensor.sensor_tree_links (sensor_id, tree_id, description)
        VALUES %s
        ON CONFLICT (sensor_id, tree_id) DO NOTHING
        RETURNING sensortreelinkid
        """,
        values,
        fetch=True,
    )
    inserted = len(returned)
    conn.commit()
    print(f"✓ Inserted {inserted} new links ({len(links) - inserted} already existed)")
    return inserted


def verify_links(conn):
    """Summarise links by sensor type and linked-tree count."""
    print("\n📊 Verifying links...")
    cur = conn.cursor()
    cur.execute(
        """
        SELECT st.sensortypename, COUNT(*)
        FROM sensor.sensor_tree_links stl
        JOIN sensor.sensors s ON stl.sensor_id = s.sensorid
        JOIN sensor.sensortypes st ON s.sensortypeid = st.sensortypeid
        GROUP BY st.sensortypename
        ORDER BY COUNT(*) DESC
        """
    )
    print("Links by sensor type:")
    for name, count in cur.fetchall():
        print(f"  {name}: {count}")

    cur.execute("SELECT COUNT(DISTINCT tree_id) FROM sensor.sensor_tree_links")
    print(f"\n✓ {cur.fetchone()[0]} trees linked to sensors")


def main():
    print("=" * 80)
    print("SENSOR-TREE LINKING (via Aquarius name map)")
    print("=" * 80)

    conn = get_db_connection()
    try:
        mappings = load_reference_map()
        resolved = backfill_aquarius_names(conn, mappings)
        if not resolved:
            print("\n❌ No trees resolved — import tree data first")
            return 1

        sensors = get_ecosense_sensors(conn)
        if not sensors:
            print("\n❌ No Ecosense sensors found — import sensor data first")
            return 1

        links = build_links(sensors, resolved)
        inserted = insert_links(conn, links)
        verify_links(conn)

        print("\n" + "=" * 80)
        print("✅ LINKING COMPLETE")
        print("=" * 80)
        print(f"Created {inserted} new sensor-tree links")
        print("\nQuery linked data:")
        print("  SELECT * FROM public.ue_sensors WHERE linked_tree_id IS NOT NULL;")
        return 0

    except Exception as e:
        conn.rollback()
        print(f"\n❌ Linking failed: {e}")
        import traceback

        traceback.print_exc()
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
