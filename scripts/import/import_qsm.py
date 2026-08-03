#!/usr/bin/env python3
"""
QSM cylinder import for Forest Digital Twin Database (XRFF-265)

Imports a Real Twig / rTwig standardised cylinder CSV
(https://aidanmorales.github.io/rTwig, "Dictionary" vignette; same column
semantics as the published BioDiv-3DTrees corrected QSM CSVs) into
trees.QSMs + trees.QSMCylinders. One CSV = one QSM reconstruction for one tree.

Usage:
    python import_qsm.py <csv_file> --tree-id <id> [options]

Examples:
    python import_qsm.py qsm_cylinders.csv --tree-id 34 --is-corrected
    python import_qsm.py qsm_cylinders.csv --tree-id 34 --process-id 5 --dry-run
"""

import argparse
import math
import sys
from pathlib import Path

import pandas as pd
from psycopg2.extras import execute_values

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection

# Required rTwig standardised columns (Dictionary vignette / BioDiv-3DTrees README).
REQUIRED_COLUMNS = [
    "id",
    "parent",
    "start_x",
    "start_y",
    "start_z",
    "axis_x",
    "axis_y",
    "axis_z",
    "length",
    "radius",
]

# Present in the standardised dictionary but not stored -- see the migration's
# header comment for why (derived metrics, recomputable from stored geometry).
OPTIONAL_COLUMNS = ["branch", "branch_order", "branch_position"]

CREATED_BY = "import_qsm"


def validate_csv(df):
    missing = [c for c in REQUIRED_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"CSV is missing required rTwig columns: {missing}")
    if df.empty:
        raise ValueError("CSV has no cylinder rows")


def cylinder_volume_m3(radius, length):
    return math.pi * (radius**2) * length


def assign_part_type(branch_order, radius_m, twig_radius_m, part_type_ids):
    """CityGML part_type_id from branch_order + a twig radius threshold.

    branch_order = 0                              -> trunk
    branch_order >= 1 and radius_m <= twig_radius  -> twig
    branch_order >= 1 and radius_m >  twig_radius  -> branch

    root/leaf/crown are never assigned here -- they have no per-cylinder QSM
    representation (see the XRFF-266 migration header). Returns None if
    branch_order or twig_radius_m is unavailable (can't classify).
    """
    if branch_order is None or twig_radius_m is None:
        return None
    if branch_order == 0:
        return part_type_ids["trunk"]
    return part_type_ids["twig"] if radius_m <= twig_radius_m else part_type_ids["branch"]


def insert_qsm(conn, tree_id, df, args):
    cur = conn.cursor()

    cur.execute("SELECT tree_entity_id FROM trees.trees WHERE tree_id = %s", (tree_id,))
    row = cur.fetchone()
    if row is None:
        raise ValueError(f"tree_id {tree_id} not found in trees.trees")
    tree_entity_id = row[0]

    twig_radius_m = args.twig_radius_mm / 1000 if args.twig_radius_mm is not None else None
    part_type_ids = {}
    if twig_radius_m is not None:
        cur.execute(
            "SELECT part_type_name, part_type_id FROM trees.treeparttypes WHERE part_type_name IN ('trunk', 'branch', 'twig')"
        )
        part_type_ids = dict(cur.fetchall())

    volumes = df.apply(lambda r: cylinder_volume_m3(r["radius"], r["length"]), axis=1)
    if "branch_order" in df.columns:
        trunk_volume = float(volumes[df["branch_order"] == 0].sum())
        branch_volume = float(volumes[df["branch_order"] > 0].sum())
    else:
        trunk_volume, branch_volume = None, None
    total_volume = float(volumes.sum())

    cur.execute(
        """
        INSERT INTO trees.qsms (
            tree_entity_id, tree_id, point_cloud_id, process_id,
            local_crs, cylinder_count, total_volume_m3, trunk_volume_m3,
            branch_volume_m3, is_corrected, created_by
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING qsm_id
        """,
        (
            tree_entity_id,
            tree_id,
            args.point_cloud_id,
            args.process_id,
            args.local_crs,
            len(df),
            total_volume,
            trunk_volume,
            branch_volume,
            args.is_corrected,
            CREATED_BY,
        ),
    )
    qsm_id = cur.fetchone()[0]

    rows = []
    for _, r in df.iterrows():
        branch_order = int(r["branch_order"]) if "branch_order" in df.columns else None
        radius_m = float(r["radius"])
        part_type_id = (
            assign_part_type(branch_order, radius_m, twig_radius_m, part_type_ids)
            if part_type_ids
            else None
        )
        rows.append(
            (
                qsm_id,
                int(r["id"]),
                int(r["parent"]),
                float(r["start_x"]),
                float(r["start_y"]),
                float(r["start_z"]),
                [float(r["axis_x"]), float(r["axis_y"]), float(r["axis_z"])],
                float(r["length"]),
                radius_m,
                int(r["branch"]) if "branch" in df.columns else None,
                branch_order,
                int(r["branch_position"]) if "branch_position" in df.columns else None,
                part_type_id,
            )
        )

    execute_values(
        cur,
        """
        INSERT INTO trees.qsmcylinders (
            qsm_id, cylinder_index, parent_cylinder_index,
            start_point, axis, length_m, radius_m,
            branch_index, branch_order, branch_position, part_type_id
        )
        VALUES %s
        """,
        rows,
        template="(%s, %s, %s, ST_MakePoint(%s, %s, %s), %s, %s, %s, %s, %s, %s, %s)",
    )

    return qsm_id, len(rows), total_volume


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_file", help="rTwig-format QSM cylinder CSV")
    parser.add_argument("--tree-id", type=int, required=True, help="trees.trees.tree_id this QSM was derived from")
    parser.add_argument("--point-cloud-id", type=int, default=None)
    parser.add_argument("--process-id", type=int, default=None)
    parser.add_argument("--local-crs", default="local")
    parser.add_argument(
        "--twig-radius-mm",
        type=float,
        default=None,
        help="Species twig radius in mm (rTwig's own twigs/twigs_index database) -- "
        "enables trunk/branch/twig part_type_id assignment. Omit to leave part_type_id NULL.",
    )
    parser.add_argument("--is-corrected", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    df = pd.read_csv(args.csv_file)
    validate_csv(df)

    conn = get_db_connection()
    try:
        if args.dry_run:
            print(f"Would import {len(df)} cylinders for tree_id {args.tree_id} (dry run, no changes made)")
            return
        qsm_id, count, total_volume = insert_qsm(conn, args.tree_id, df, args)
        conn.commit()
        print(f"Imported QSM {qsm_id}: {count} cylinders, total_volume_m3={total_volume:.6f}")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
