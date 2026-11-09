"""
A tree row's location, scenario and variant type are its variant's (XRFF-661).

trees.trees repeats three facts of its variant so clients can filter without a
join. A composite foreign key keeps the copies equal, a trigger fills them when
a writer gives only variant_id, and deleting a variant removes its trees.

Inside a transaction that is rolled back. Needs the local stack running.
"""

import sys
from pathlib import Path

import psycopg2
import pytest

REPO_ROOT = Path(__file__).parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
from utils.db import get_db_connection  # noqa: E402

POINT = "extensions.ST_SetSRID(extensions.ST_MakePoint(8, 48), 4326)"


@pytest.fixture
def db():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT v.variant_id, v.location_id, v.scenario_id, v.variant_type_id FROM shared.variants v "
        "WHERE EXISTS (SELECT 1 FROM shared.variant_types t WHERE t.variant_type_id <> v.variant_type_id) "
        "ORDER BY v.variant_id LIMIT 1"
    )
    variant = cur.fetchone()
    yield cur, variant
    conn.rollback()
    conn.close()


def test_variant_id_alone_fills_the_copies(db):
    cur, (variant_id, location_id, scenario_id, variant_type_id) = db
    cur.execute(
        f"INSERT INTO trees.trees (variant_id, position) VALUES (%s, {POINT}) "
        "RETURNING location_id, scenario_id, variant_type_id",
        (variant_id,),
    )
    assert cur.fetchone() == (location_id, scenario_id, variant_type_id)


def test_a_copy_that_disagrees_is_refused(db):
    cur, (variant_id, _, _, variant_type_id) = db
    cur.execute("SELECT variant_type_id FROM shared.variant_types WHERE variant_type_id <> %s LIMIT 1",
                (variant_type_id,))
    other_type = cur.fetchone()[0]
    with pytest.raises(psycopg2.errors.ForeignKeyViolation):
        cur.execute(
            f"INSERT INTO trees.trees (variant_id, variant_type_id, position) VALUES (%s, %s, {POINT})",
            (variant_id, other_type),
        )


def test_a_tree_needs_a_variant(db):
    cur, (_, location_id, _, variant_type_id) = db
    with pytest.raises(psycopg2.errors.NotNullViolation):
        cur.execute(
            f"INSERT INTO trees.trees (location_id, variant_type_id, position) VALUES (%s, %s, {POINT})",
            (location_id, variant_type_id),
        )


def test_deleting_a_variant_deletes_its_trees(db):
    cur, (variant_id, location_id, scenario_id, variant_type_id) = db
    cur.execute(
        "INSERT INTO shared.variants (location_id, scenario_id, variant_type_id, variant_name, sort_order) "
        "VALUES (%s, %s, %s, 'xrff661_probe', 999) RETURNING variant_id",
        (location_id, scenario_id, variant_type_id),
    )
    probe = cur.fetchone()[0]
    cur.execute(f"INSERT INTO trees.trees (variant_id, position) VALUES (%s, {POINT}) RETURNING tree_id", (probe,))
    tree_id = cur.fetchone()[0]
    cur.execute("DELETE FROM shared.variants WHERE variant_id = %s", (probe,))
    cur.execute("SELECT count(*) FROM trees.trees WHERE tree_id = %s", (tree_id,))
    assert cur.fetchone()[0] == 0
