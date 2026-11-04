#!/usr/bin/env python3
"""
Fill missing tree heights from height-diameter curves fitted to this database.

For every species with at least MIN_TREES measured trees (height_source
'measured' or 'measured_tls', baseline variant, stem-1 DBH), a Naslund curve
H = 1.3 + D^2 / (a + b*D)^2 (D in cm) is fitted with pylometree, pooled over all
sites. Species with fewer measured trees get the curve pooled over their leaf
type (broadleaf / needleleaf). The fit is redone on every run, so new
measurements improve it.

Why Naslund and not Chapman-Richards: the measured conifers have few small
trees (spruce DBH >= 18.5 cm, larch >= 40 cm), so a free Chapman-Richards fit
drifts to an unbounded power law and gives a 5 cm understory spruce 14 m.
Naslund passes through 1.3 m at D = 0 and has an asymptote 1.3 + 1/b^2, which
keeps extrapolation to small and large trees plausible.

Targets are baseline trees with a DBH and either no height or a height this
script wrote before (including the old generic 'allometric_pylometree' fill,
which used one unfitted curve, a=30 b=0.05 c=1, for every species). The tree
record's data_source_type stays 'field': only the height is modelled, and
height_source says so ('allometric_fitted_species' or
'allometric_fitted_leaf_type').

A tree whose height changes loses every value derived from the old height --
age, crown width and base, volume, stem volumes, biomass, carbon -- so that the
three fill scripts recompute them. Run, in this order:
    silva-connector scripts/fill_allometry.R  (crown, volume)
    fill_missing_ages.py
    fill_missing_biomass.py

Usage:
    python fill_missing_heights.py            # apply updates
    python fill_missing_heights.py --dry-run  # fit and preview only
"""

import argparse
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection

try:
    import pylometree
    from pylometree.fitting.nonlinear import fit_model
except ImportError:
    print("pylometree not installed. Run: pip install pylometree")
    sys.exit(1)

MIN_TREES = 20
# A fitted asymptote outside this range is a failed fit, not a species trait.
PLAUSIBLE_ASYMPTOTE_M = (8.0, 75.0)
SPECIES_SOURCE = "allometric_fitted_species"
LEAF_TYPE_SOURCE = "allometric_fitted_leaf_type"
REFILLED = ("allometric_pylometree", SPECIES_SOURCE, LEAF_TYPE_SOURCE)
MEASURED = ("measured", "measured_tls")

BASELINE = """
    t.variant_type_id = (SELECT variant_type_id FROM shared.variant_types
                         WHERE variant_type_name = 'original')
"""


def fetch(conn, where: str, params: tuple) -> list:
    cur = conn.cursor()
    cur.execute(
        f"""
        SELECT t.tree_id, s.scientific_name, s.leaf_type, st.dbh_cm, t.height_m
        FROM trees.trees t
        JOIN shared.species s ON t.species_id = s.species_id
        JOIN trees.stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
        WHERE {BASELINE} AND st.dbh_cm > 0 AND ({where})
        """,
        params,
    )
    rows = cur.fetchall()
    cur.close()
    return rows


def fetch_sources(conn, tree_ids: list) -> list:
    cur = conn.cursor()
    cur.execute(
        "SELECT tree_id, height_source, height_m FROM trees.trees WHERE tree_id = ANY(%s)",
        (tree_ids,),
    )
    rows = cur.fetchall()
    cur.close()
    return rows


def naslund(d, a, b):
    return 1.3 + d**2 / (a + b * d) ** 2


def fit(dbh: list, height: list):
    """Naslund fit, or None when it fails or its asymptote is implausible."""
    result = fit_model(
        naslund, np.asarray(dbh, float), np.asarray(height, float),
        param_names=["a", "b"], p0=[1.5, 0.18], bounds=([0.0, 0.05], [20.0, 1.0]),
        model_name="naslund",
    )
    asymptote = 1.3 + 1 / result.params["b"] ** 2
    if not result.converged or not PLAUSIBLE_ASYMPTOTE_M[0] <= asymptote <= PLAUSIBLE_ASYMPTOTE_M[1]:
        return None
    return result


def main():
    parser = argparse.ArgumentParser(description="Fill missing tree heights via fitted H-D curves")
    parser.add_argument("--dry-run", action="store_true", help="Fit and preview without updating")
    args = parser.parse_args()

    conn = get_db_connection()
    training = fetch(conn, "t.height_source IN %s AND t.height_m > 1.3", (MEASURED,))
    targets = fetch(conn, "t.height_m IS NULL OR t.height_source IN %s", (REFILLED,))
    print(f"Measured trees for fitting: {len(training)}; trees to fill: {len(targets)}")

    by_species, by_leaf = defaultdict(lambda: ([], [])), defaultdict(lambda: ([], []))
    for _, species, leaf_type, dbh, h in training:
        for group in (by_species[species], by_leaf[leaf_type]):
            group[0].append(float(dbh))
            group[1].append(float(h))

    leaf_fits = {k: fit(*v) for k, v in by_leaf.items() if len(v[0]) >= MIN_TREES}
    species_fits = {}
    def row(label, n, result):
        a, b = result.params["a"], result.params["b"]
        print(f"{label:<28} {n:>5} {a:6.3f} {b:7.4f} {1.3 + 1 / b**2:7.1f} {result.metrics['rmse']:7.2f}")

    print(f"\n{'curve':<28} {'n':>5} {'a':>6} {'b':>7} {'asym m':>7} {'RMSE m':>7}")
    for name, (dbh, h) in sorted(by_species.items()):
        if len(dbh) >= MIN_TREES and (result := fit(dbh, h)):
            species_fits[name] = result
            row(name, len(dbh), result)
    for name, result in sorted(leaf_fits.items()):
        if result:
            row(f"[{name}]", len(by_leaf[name][0]), result)

    updates, unfitted = [], defaultdict(int)
    current = {tid: (h, src) for tid, src, h in fetch_sources(conn, [t[0] for t in targets])}
    for tree_id, species, leaf_type, dbh, _ in targets:
        if species in species_fits:
            curve, source = species_fits[species], SPECIES_SOURCE
        elif leaf_fits.get(leaf_type):
            curve, source = leaf_fits[leaf_type], LEAF_TYPE_SOURCE
        else:
            unfitted[species] += 1
            continue
        height = round(float(curve.predict(float(dbh))), 2)
        old_h, old_src = current[tree_id]
        if old_src == source and old_h is not None and abs(float(old_h) - height) < 0.005:
            continue  # unchanged: keep its derived values
        updates.append((height, source, tree_id))

    print(f"\nChanged heights: {len(updates)} of {len(targets)}; no curve: {dict(unfitted) or 0}")
    if args.dry_run:
        for h, source, tid in updates[:10]:
            print(f"  tree {tid}: {h:.2f} m ({source})")
        print("[dry-run] nothing written")
        return 0

    cur = conn.cursor()
    cur.execute(
        "SET LOCAL app.change_reason = %s",
        (f"Naslund H-D fitted to measured trees (pylometree {pylometree.__version__})",),
    )
    cur.executemany(
        """
        UPDATE trees.trees
        SET height_m = %s,
            height_source = %s,
            data_source_type_id = (SELECT data_source_type_id FROM trees.data_source_types
                                   WHERE data_source_type_name = 'field'),
            age_years = NULL, crown_width_m = NULL, crown_base_height_m = NULL,
            volume_m3 = NULL, biomass_kg = NULL, carbon_content_kg = NULL,
            updated_at = NOW(),
            updated_by = 'fill_missing_heights'
        WHERE tree_id = %s
        """,
        updates,
    )
    cur.execute(
        "UPDATE trees.stems SET stem_volume_m3 = NULL WHERE tree_id = ANY(%s)",
        ([tid for _, _, tid in updates],),
    )
    conn.commit()
    print(f"Updated {len(updates)} trees.")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
