"""
Stand summaries and design-based estimates (migration 20261102140000, XRFF-627).

Builds sampling designs, plots and trees inside a transaction that is rolled
back, on an existing variant, and checks shared.estimate_stand against values
computed independently with R's survey package (svydesign + svymean/svytotal):

* simple random, 4 plots of r = 10 m with 3, 1, 2, 0 trees
    stems/ha 47.746, SE 20.547; t(3) = 3.182 at 95 %
* stratified, strata A (30 ha: 3, 1 trees) and B (10 ha: 2, 0 trees)
    stems/ha 55.704, SE 25.165, total 2228.169 over 40 ha; t(2) = 4.303
* census, one 2500 m² plot with 5 trees -> 20 stems/ha, no sampling error

Also: a plot without trees counts as zero, the per-species values add up to the
all-species value, and an unsupported confidence level is refused.

Needs the local stack running (`docker compose up -d`).
"""

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
    cursor.execute(
        "SELECT v.variant_id, v.location_id FROM shared.variants v ORDER BY v.variant_id LIMIT 1"
    )
    variant_id, location_id = cursor.fetchone()
    cursor.execute("SELECT min(species_id), max(species_id) FROM shared.species")
    species = cursor.fetchone()
    yield cursor, variant_id, location_id, species
    connection.rollback()
    connection.close()


def design(cursor, name, strategy, radius=None):
    cursor.execute(
        "INSERT INTO shared.sampling_designs (design_name, strategy) VALUES (%s, %s) RETURNING sampling_design_id",
        (name, strategy),
    )
    design_id = cursor.fetchone()[0]
    if radius:
        cursor.execute(
            "INSERT INTO shared.inclusion_rules (sampling_design_id, rule_type, radius_m) VALUES (%s, 'fixed_radius', %s)",
            (design_id, radius),
        )
    return design_id


def plot(cursor, location_id, name, design_id, stratum_id=None, area_m2=None):
    cursor.execute(
        "INSERT INTO shared.plots (location_id, plot_name, sampling_design_id, stratum_id, area_m2) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING plot_id",
        (location_id, name, design_id, stratum_id, area_m2),
    )
    return cursor.fetchone()[0]


def trees(cursor, variant_id, location_id, plot_id, n, species_id, dbh=30):
    for _ in range(n):
        cursor.execute(
            "INSERT INTO trees.trees (location_id, variant_type_id, variant_id, plot_id, species_id, position, "
            "volume_m3, biomass_kg, carbon_content_kg) "
            "VALUES (%s, 1, %s, %s, %s, ST_SetSRID(ST_MakePoint(8, 48), 4326), 1.0, 500, 250) RETURNING tree_id",
            (location_id, variant_id, plot_id, species_id),
        )
        tree_id = cursor.fetchone()[0]
        cursor.execute(
            "INSERT INTO trees.stems (tree_id, stem_number, dbh_cm) VALUES (%s, 1, %s)", (tree_id, dbh)
        )


def estimate(cursor, design_id, variant_id, by_species=False, confidence=0.95):
    cursor.execute(
        "SELECT * FROM shared.estimate_stand(%s, %s, %s, %s)", (design_id, variant_id, by_species, confidence)
    )
    cols = [c.name for c in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


def row(rows, variable, species_id=None):
    return next(r for r in rows if r["variable"] == variable and r["species_id"] == species_id)


def test_simple_random_matches_r_survey(cur):
    cursor, variant, loc, (sp_a, sp_b) = cur
    d = design(cursor, "t_srs", "simple_random", radius=10)
    for name, n in (("a", 3), ("b", 1), ("c", 2), ("d", 0)):
        trees(cursor, variant, loc, plot(cursor, loc, f"t_srs_{name}", d), n, sp_a)
    stems = row(estimate(cursor, d, variant), "stems_ha")
    assert float(stems["estimate"]) == pytest.approx(47.746, abs=1e-3)
    assert float(stems["standard_error"]) == pytest.approx(20.547, abs=1e-3)
    assert float(stems["margin_of_error"]) == pytest.approx(3.182 * 20.5468, abs=1e-2)
    assert float(stems["sampling_error_pct"]) == pytest.approx(100 * 3.182 * 20.5468 / 47.7465, abs=1e-2)
    assert float(stems["ci_low"]) == pytest.approx(47.7465 - 3.182 * 20.5468, abs=1e-2)
    assert stems["n_units"] == 4  # the empty plot counts as a zero
    wide = row(estimate(cursor, d, variant, confidence=0.99), "stems_ha")
    assert float(wide["margin_of_error"]) == pytest.approx(5.841 * 20.5468, abs=1e-2)


def test_stratified_matches_r_survey(cur):
    cursor, variant, loc, (sp_a, _) = cur
    d = design(cursor, "t_strat", "stratified_random", radius=10)
    strata = {}
    for name, area in (("A", 30), ("B", 10)):
        cursor.execute(
            "INSERT INTO shared.strata (sampling_design_id, stratum_name, area_ha) VALUES (%s, %s, %s) RETURNING stratum_id",
            (d, name, area),
        )
        strata[name] = cursor.fetchone()[0]
    for name, stratum, n in (("a", "A", 3), ("b", "A", 1), ("c", "B", 2), ("d", "B", 0)):
        trees(cursor, variant, loc, plot(cursor, loc, f"t_strat_{name}", d, strata[stratum]), n, sp_a)
    stems = row(estimate(cursor, d, variant), "stems_ha")
    assert float(stems["estimate"]) == pytest.approx(55.704, abs=1e-3)
    assert float(stems["standard_error"]) == pytest.approx(25.165, abs=1e-3)
    assert float(stems["area_ha"]) == pytest.approx(40)
    assert float(stems["total"]) == pytest.approx(2228.169, abs=1e-2)
    assert float(stems["margin_of_error"]) == pytest.approx(4.303 * 25.1646, abs=1e-2)


def test_census_and_species_split(cur):
    cursor, variant, loc, (sp_a, sp_b) = cur
    d = design(cursor, "t_census", "census")
    p = plot(cursor, loc, "t_census_plot", d, area_m2=2500)
    trees(cursor, variant, loc, p, 3, sp_a)
    trees(cursor, variant, loc, p, 2, sp_b)
    all_sp = estimate(cursor, d, variant)
    stems = row(all_sp, "stems_ha")
    assert float(stems["estimate"]) == pytest.approx(20)
    assert stems["standard_error"] is None and stems["sampling_error_pct"] is None
    assert float(stems["total"]) == pytest.approx(5)
    by_sp = estimate(cursor, d, variant, by_species=True)
    for variable in ("stems_ha", "basal_area_m2ha", "volume_m3ha", "biomass_tha", "carbon_tha"):
        parts = sum(float(r["estimate"]) for r in by_sp if r["variable"] == variable)
        assert parts == pytest.approx(float(row(all_sp, variable)["estimate"]), abs=1e-3)


def test_unsupported_confidence_refused(cur):
    cursor, variant, loc, _ = cur
    d = design(cursor, "t_conf", "census")
    cursor.execute("SAVEPOINT s")
    with pytest.raises(psycopg2.errors.RaiseException):
        estimate(cursor, d, variant, confidence=0.8)
    cursor.execute("ROLLBACK TO SAVEPOINT s")
