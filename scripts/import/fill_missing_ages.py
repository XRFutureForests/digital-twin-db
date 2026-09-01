#!/usr/bin/env python3
"""
Fill NULL age_years in trees.Trees using pylometree's Chapman-Richards inversion.

Companion to fill_missing_heights.py. Where that fills height from DBH, this
fills age from height, using Pretzsch et al. (2025), "Estimating tree age from
height using the extended Chapman-Richards function" (doi:10.1007/s00468-025-02692-0):

    H = hmax * (1 - exp(-k*t))^c        inverted to
    t = -(1/k) * ln(1 - (H/hmax)^(1/c))

Two things worth understanding before trusting the numbers:

1. Species coverage is partial. pylometree ships parameters for five European
   species (Norway spruce, Scots pine, European beech, sessile and common oak),
   which covers ~85% of our baseline trees. Silver fir, Douglas fir, larch and
   the scattered broadleaves get no age and are reported, not guessed.

2. The curve asymptotes at hmax, so age becomes unstable as height approaches
   it -- a 35 m sessile oak already returns 186 years against an hmax of 36 m.
   Trees above ASYMPTOTE_GUARD * hmax are skipped rather than given a number
   that is arithmetic rather than information. As of 2026-08-31 no tree in the
   database is anywhere near that boundary, so nothing is lost today; the guard
   exists so that stays true as taller trees arrive.

Ages for simulated variants are NOT re-inverted from projected height. A tree
20 years into a projection is its baseline age plus 20 -- exact, and immune to
the asymptote problem. Only measured baselines go through the model.

Requires:
    pip install pylometree

Usage:
    python fill_missing_ages.py             # apply
    python fill_missing_ages.py --dry-run   # preview only
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection

try:
    from pylometree.models.volume import CR_SPECIES_PARAMS, age_from_height_cr
except ImportError:
    print("pylometree not installed. Run: pip install pylometree")
    sys.exit(1)

# Above this fraction of hmax the inverse is numerically unstable: a few cm of
# height error moves the age estimate by decades.
ASYMPTOTE_GUARD = 0.95

PROCESS = {
    "process_name": "Tree Age Estimation",
    "algorithm_name": "Chapman-Richards height-age inversion (pylometree)",
    "description": (
        "Estimates tree age by inverting the extended Chapman-Richards "
        "height-age function at medium site index. Species coverage is limited "
        "to the five European species pylometree carries parameters for, and "
        "trees near the height asymptote are excluded. Ignores stand-density "
        "interaction."
    ),
    "author": "Pretzsch, H. et al.",
    "citation": (
        "Pretzsch, H. et al. (2025). Estimating tree age from height using the "
        "extended Chapman-Richards function. Trees. "
        "doi:10.1007/s00468-025-02692-0"
    ),
    "category": "analysis",
}


def ensure_process(cur, version: str) -> int:
    cur.execute(
        """SELECT process_id FROM shared.processes
           WHERE process_name = %s AND algorithm_name = %s AND version = %s""",
        (PROCESS["process_name"], PROCESS["algorithm_name"], version),
    )
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute(
        """INSERT INTO shared.processes
             (process_name, algorithm_name, version, description, author, citation, category)
           VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING process_id""",
        (
            PROCESS["process_name"], PROCESS["algorithm_name"], version,
            PROCESS["description"], PROCESS["author"], PROCESS["citation"],
            PROCESS["category"],
        ),
    )
    return cur.fetchone()[0]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="Preview, write nothing")
    ap.add_argument("--location", default=None, help="Restrict to one location_name")
    args = ap.parse_args()

    import pylometree

    conn = get_db_connection()
    cur = conn.cursor()

    # Only measured baselines go through the model; simulated variants are
    # derived from them afterwards.
    sql = """
        SELECT t.tree_id, sp.scientific_name, t.height_m
        FROM trees.trees t
        JOIN shared.species sp USING (species_id)
        JOIN shared.variants v USING (variant_id)
        JOIN shared.locations l ON l.location_id = t.location_id
        WHERE v.variant_type_id = (SELECT variant_type_id FROM shared.varianttypes
                                   WHERE variant_type_name = 'original')
          AND t.height_m IS NOT NULL AND t.age_years IS NULL
    """
    params: list = []
    if args.location:
        sql += " AND l.location_name = %s"
        params.append(args.location)
    cur.execute(sql, params)
    rows = cur.fetchall()
    print(f"Baseline trees needing an age: {len(rows)}")

    filled: list[tuple[int, int]] = []
    skipped: dict[str, int] = {}
    for tree_id, species, height in rows:
        pars = CR_SPECIES_PARAMS.get(species)
        if pars is None:
            skipped[f"{species}: no Chapman-Richards parameters"] = (
                skipped.get(f"{species}: no Chapman-Richards parameters", 0) + 1)
            continue
        if float(height) >= ASYMPTOTE_GUARD * pars["hmax"]:
            key = f"{species}: height >= {ASYMPTOTE_GUARD:.0%} of hmax ({pars['hmax']:.0f} m)"
            skipped[key] = skipped.get(key, 0) + 1
            continue
        age = float(age_from_height_cr(float(height), **pars))
        if age != age or age <= 0:  # NaN or nonsensical
            skipped[f"{species}: inversion undefined"] = (
                skipped.get(f"{species}: inversion undefined", 0) + 1)
            continue
        filled.append((tree_id, int(round(age))))

    print(f"  estimated : {len(filled)}")
    for reason, n in sorted(skipped.items(), key=lambda kv: -kv[1]):
        print(f"  skipped {n:>5}: {reason}")

    if filled:
        ages = [a for _, a in filled]
        print(f"  age range : {min(ages)}-{max(ages)} yr (mean {sum(ages)/len(ages):.0f})")

    if args.dry_run:
        print("[dry-run] nothing written")
        return
    # No early return when `filled` is empty: the projected-variant update below
    # still has work to do. The documented pipeline order runs this script before
    # silva-connector, so the first pass fills baselines while no simulated
    # variants exist yet, and every later pass finds no new baseline age. Returning
    # here left projected trees with age_years NULL permanently.

    version = pylometree.__version__
    process_id = ensure_process(cur, version)
    print(f"Provenance: shared.Processes id {process_id} (pylometree {version})")

    # Read by shared.audit_update_trigger(), so every changed age records why.
    cur.execute(
        "SET LOCAL app.change_reason = %s",
        (f"Chapman-Richards height-age inversion "
         f"(shared.Processes id {process_id}, pylometree {version})",),
    )

    from psycopg2.extras import execute_values

    n_base = 0
    if filled:
        # page_size must cover the whole batch: execute_values otherwise splits the
        # UPDATE into several statements and cur.rowcount reports only the last one
        # (1904 rows in pages of 100 reads back as "4 updated").
        execute_values(
            cur,
            """UPDATE trees.trees t SET age_years = v.age
               FROM (VALUES %s) AS v(tree_id, age)
               WHERE t.tree_id = v.tree_id AND t.age_years IS NULL""",
            filled,
            page_size=max(len(filled), 100),
        )
        n_base = cur.rowcount

    # A projected tree's age is its baseline age plus the elapsed years -- exact,
    # and it avoids inverting a modelled height through a modelled curve.
    cur.execute(
        """UPDATE trees.trees sim
           SET age_years = base.age_years + COALESCE(sim.time_delta_yrs, 0)::int
           FROM trees.trees base
           WHERE sim.tree_entity_id = base.tree_entity_id
             AND base.variant_id IN (SELECT variant_id FROM shared.variants
                                     WHERE variant_type_id = (SELECT variant_type_id
                                       FROM shared.varianttypes WHERE variant_type_name = 'original'))
             AND base.age_years IS NOT NULL
             AND sim.age_years IS NULL
             AND sim.tree_id <> base.tree_id"""
    )
    n_sim = cur.rowcount

    conn.commit()
    print(f"Updated {n_base} baseline trees and {n_sim} projected trees")


if __name__ == "__main__":
    main()
