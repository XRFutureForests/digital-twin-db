"""
Round-trip test for XRFF-265 (trees.QSMs / trees.QSMCylinders).

Loads a Real Twig / rTwig standardised cylinder CSV, ingests it via
scripts/import/import_qsm.py, reads it back from the database, and compares
cylinder count and total volume against values computed directly from the CSV.

fixtures/sample_qsm_cylinders.csv is a small synthetic fixture (5 cylinders:
a 3-segment trunk + a 2-segment branch) using the verified rTwig column names
confirmed against the package's Dictionary vignette and the published
BioDiv-3DTrees README -- not an actual downloaded BioDiv-3DTrees file, since
that dataset is only distributed as ~100 GB per-datatype archives with no
single-tree sample available for direct download.
"""

import math
import sys
from pathlib import Path

import pandas as pd
import pytest

REPO_ROOT = Path(__file__).parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "import"))
from import_qsm import insert_qsm
from utils.db import get_db_connection

FIXTURE = Path(__file__).parent / "fixtures" / "sample_qsm_cylinders.csv"


class Args:
    point_cloud_id = None
    process_id = None
    local_crs = "local"
    is_corrected = True
    # 40mm: fixture's branch_order=1 cylinders are 50mm (-> branch) and 30mm (-> twig).
    twig_radius_mm = 40.0


@pytest.fixture
def conn():
    connection = get_db_connection()
    yield connection
    connection.rollback()
    connection.close()


@pytest.fixture
def existing_tree_id(conn):
    cur = conn.cursor()
    cur.execute("SELECT tree_id FROM trees.trees LIMIT 1")
    row = cur.fetchone()
    assert row is not None, "no rows in trees.trees to attach a test QSM to"
    return row[0]


def test_qsm_round_trip(conn, existing_tree_id):
    df = pd.read_csv(FIXTURE)
    expected_count = len(df)
    expected_volume = sum(
        math.pi * (r["radius"] ** 2) * r["length"] for _, r in df.iterrows()
    )

    qsm_id, inserted_count, computed_volume = insert_qsm(conn, existing_tree_id, df, Args())

    assert inserted_count == expected_count
    assert computed_volume == pytest.approx(expected_volume, rel=1e-9)

    cur = conn.cursor()
    cur.execute(
        "SELECT cylinder_count, total_volume_m3 FROM trees.qsms WHERE qsm_id = %s",
        (qsm_id,),
    )
    db_count, db_volume = cur.fetchone()
    assert db_count == expected_count
    # trees.qsms.total_volume_m3 is numeric(10,3) -- 1-liter precision, matching
    # trees.trees.volume_m3's own precision. Compare with that column's rounding
    # tolerance rather than the full-precision cylinder-geometry sum below.
    assert float(db_volume) == pytest.approx(expected_volume, abs=5e-4)

    cur.execute(
        "SELECT count(*), sum(pi() * radius_m^2 * length_m) FROM trees.qsmcylinders WHERE qsm_id = %s",
        (qsm_id,),
    )
    cyl_count, cyl_volume = cur.fetchone()
    assert cyl_count == expected_count
    assert float(cyl_volume) == pytest.approx(expected_volume, rel=1e-6)

    cur.execute(
        """
        SELECT cylinder_index, parent_cylinder_index, radius_m, length_m, branch_order
        FROM trees.qsmcylinders WHERE qsm_id = %s ORDER BY cylinder_index
        """,
        (qsm_id,),
    )
    rows = cur.fetchall()
    for (cyl_index, parent_index, radius_m, length_m, branch_order), (_, r) in zip(
        rows, df.iterrows()
    ):
        assert cyl_index == r["id"]
        assert parent_index == r["parent"]
        assert float(radius_m) == pytest.approx(r["radius"])
        assert float(length_m) == pytest.approx(r["length"])
        assert branch_order == r["branch_order"]

    cur.execute(
        """
        SELECT c.cylinder_index, pt.part_type_name
        FROM trees.qsmcylinders c
        JOIN trees.treeparttypes pt ON pt.part_type_id = c.part_type_id
        WHERE c.qsm_id = %s ORDER BY c.cylinder_index
        """,
        (qsm_id,),
    )
    part_types = dict(cur.fetchall())
    assert part_types == {
        1: "trunk",
        2: "trunk",
        3: "trunk",
        4: "branch",  # 50mm radius > 40mm twig threshold
        5: "twig",  # 30mm radius <= 40mm twig threshold
    }
