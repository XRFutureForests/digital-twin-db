"""
Sampling designs and the per-tree expansion factor (migration 20261102130000, XRFF-626).

Builds one plot per design inside a transaction that is rolled back, and checks
shared.expansion_factor_ha against textbook values:

* fixed radius 12.62 m (about 500 m²)  -> 10000 / (pi r²) = 19.986 trees/ha
* nested circles 1.75 / 6 / 12 m       -> 1039.379 / 88.419 / 22.105 trees/ha
* angle count, basal-area factor 4      -> every counted tree adds exactly 4 m²/ha
* fixed area 2500 m², no rules         -> 4 trees/ha
* below the design's minimum DBH       -> NULL

and that the guards hold: overlapping DBH ranges, a stratum from another design,
and a rule with both a radius and a basal-area factor are rejected.

Needs the local stack running (`docker compose up -d`).
"""

import math
import sys
from pathlib import Path

import psycopg2
import pytest

REPO_ROOT = Path(__file__).parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
from utils.db import get_db_connection  # noqa: E402


@pytest.fixture
def cur():
    connection = get_db_connection()
    cursor = connection.cursor()
    cursor.execute("SELECT location_id FROM shared.locations ORDER BY location_id LIMIT 1")
    location_id = cursor.fetchone()[0]
    yield cursor, location_id
    connection.rollback()
    connection.close()


def make_design(cursor, location_id, name, strategy="systematic", min_dbh=None, rules=(), area_m2=None):
    cursor.execute(
        "INSERT INTO shared.sampling_designs (design_name, strategy, min_dbh_cm) "
        "VALUES (%s, %s, %s) RETURNING sampling_design_id",
        (name, strategy, min_dbh),
    )
    design_id = cursor.fetchone()[0]
    for min_dbh_cm, max_dbh_cm, rule_type, radius_m, baf in rules:
        cursor.execute(
            "INSERT INTO shared.inclusion_rules "
            "(sampling_design_id, min_dbh_cm, max_dbh_cm, rule_type, radius_m, basal_area_factor_m2ha) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (design_id, min_dbh_cm, max_dbh_cm, rule_type, radius_m, baf),
        )
    cursor.execute(
        "INSERT INTO shared.plots (location_id, plot_name, sampling_design_id, area_m2) "
        "VALUES (%s, %s, %s, %s) RETURNING plot_id",
        (location_id, f"test_plot_{name}", design_id, area_m2),
    )
    return design_id, cursor.fetchone()[0]


def ef(cursor, plot_id, dbh_cm):
    cursor.execute("SELECT shared.expansion_factor_ha(%s, %s)", (plot_id, dbh_cm))
    value = cursor.fetchone()[0]
    return None if value is None else float(value)


def test_fixed_radius(cur):
    cursor, loc = cur
    _, plot = make_design(cursor, loc, "t_fixed", rules=[(0, None, "fixed_radius", 12.62, None)])
    for dbh in (8, 20, 40):
        assert ef(cursor, plot, dbh) == pytest.approx(10000 / (math.pi * 12.62**2), rel=1e-6)


def test_nested_circles(cur):
    cursor, loc = cur
    _, plot = make_design(
        cursor, loc, "t_nested",
        rules=[(7, 10, "fixed_radius", 1.75, None), (10, 30, "fixed_radius", 6, None),
               (30, None, "fixed_radius", 12, None)],
    )
    assert ef(cursor, plot, 5) is None  # below every ring
    assert ef(cursor, plot, 8) == pytest.approx(1039.379, abs=1e-3)
    assert ef(cursor, plot, 20) == pytest.approx(88.419, abs=1e-3)
    assert ef(cursor, plot, 40) == pytest.approx(22.105, abs=1e-3)


def test_angle_count_gives_baf_per_tree(cur):
    cursor, loc = cur
    _, plot = make_design(cursor, loc, "t_angle", rules=[(0, None, "angle_count", None, 4)])
    for dbh in (8, 20, 40, 75):
        basal_area_m2 = math.pi * (dbh / 200) ** 2
        assert ef(cursor, plot, dbh) * basal_area_m2 == pytest.approx(4, rel=1e-6)


def test_fixed_area_and_threshold(cur):
    cursor, loc = cur
    _, plot = make_design(cursor, loc, "t_area", strategy="census", min_dbh=7, area_m2=2500)
    assert ef(cursor, plot, 20) == pytest.approx(4)
    assert ef(cursor, plot, 5) is None
    assert ef(cursor, -1, 20) is None


def test_overlapping_rules_rejected(cur):
    cursor, loc = cur
    design, _ = make_design(cursor, loc, "t_overlap", rules=[(10, 30, "fixed_radius", 6, None)])
    cursor.execute("SAVEPOINT s")
    with pytest.raises(psycopg2.errors.RaiseException):
        cursor.execute(
            "INSERT INTO shared.inclusion_rules (sampling_design_id, min_dbh_cm, max_dbh_cm, rule_type, radius_m) "
            "VALUES (%s, 25, 35, 'fixed_radius', 3)",
            (design,),
        )
    cursor.execute("ROLLBACK TO SAVEPOINT s")


def test_rule_needs_exactly_one_parameter(cur):
    cursor, loc = cur
    design, _ = make_design(cursor, loc, "t_both")
    cursor.execute("SAVEPOINT s")
    with pytest.raises(psycopg2.errors.CheckViolation):
        cursor.execute(
            "INSERT INTO shared.inclusion_rules (sampling_design_id, rule_type, radius_m, basal_area_factor_m2ha) "
            "VALUES (%s, 'fixed_radius', 3, 4)",
            (design,),
        )
    cursor.execute("ROLLBACK TO SAVEPOINT s")


def test_stratum_must_belong_to_plot_design(cur):
    cursor, loc = cur
    design_a, _ = make_design(cursor, loc, "t_a")
    _, plot_b = make_design(cursor, loc, "t_b")
    cursor.execute(
        "INSERT INTO shared.strata (sampling_design_id, stratum_name, area_ha) VALUES (%s, 'A', 100) "
        "RETURNING stratum_id",
        (design_a,),
    )
    stratum_a = cursor.fetchone()[0]
    cursor.execute("SAVEPOINT s")
    with pytest.raises(psycopg2.errors.ForeignKeyViolation):
        cursor.execute("UPDATE shared.plots SET stratum_id = %s WHERE plot_id = %s", (stratum_a, plot_b))
    cursor.execute("ROLLBACK TO SAVEPOINT s")


def test_area_and_design_inherited_from_enclosing_plot(cur):
    """A fully mapped site: the site plot carries the area, the plots inside it are labels."""
    cursor, loc = cur
    design, site = make_design(cursor, loc, "t_site", strategy="census", area_m2=28910)
    cursor.execute(
        "INSERT INTO shared.plots (location_id, plot_name, parent_plot_id) VALUES (%s, 'test_label_plot', %s) "
        "RETURNING plot_id",
        (loc, site),
    )
    label = cursor.fetchone()[0]
    assert ef(cursor, label, 30) == pytest.approx(10000 / 28910)
    # a child with its own area uses that one
    cursor.execute("UPDATE shared.plots SET area_m2 = 400 WHERE plot_id = %s", (label,))
    assert ef(cursor, label, 30) == pytest.approx(25)
    # a parent cycle does not loop
    cursor.execute("UPDATE shared.plots SET area_m2 = NULL WHERE plot_id = %s", (label,))
    cursor.execute("UPDATE shared.plots SET area_m2 = NULL, parent_plot_id = %s WHERE plot_id = %s", (label, site))
    assert ef(cursor, label, 30) is None
