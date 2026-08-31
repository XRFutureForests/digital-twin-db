#!/usr/bin/env python3
"""
Fill NULL biomass_kg and carbon_content_kg in trees.Trees using pylometree's
Zianis et al. (2005) aboveground biomass equations.

Third in the family after fill_missing_heights.py and fill_missing_ages.py.

    AGB = a * D^b            (M1)
    AGB = a * D^b * H^c      (M4)

from Silva Fennica Monographs 4 (doi:10.14214/sf.sfm4), registered in pylometree
>= 0.2.0 as `zianis2005_eq*_agb`.

Three things constrain what this can fill:

1. Species coverage. The monograph has no qualifying total-aboveground-biomass
   equation for Quercus robur, Quercus petraea, Abies alba or Larix decidua, so
   those trees get nothing. Substituting a congener would be inventing data.

2. DBH range. Each equation was fitted over a stated diameter range, and a
   power law with an exponent near 2.4 extrapolates badly. Trees outside the
   fitted range are filled but flagged in the run summary, because the
   alternative -- silently extrapolating a spruce equation fitted to 47 cm out
   to an 85 cm stem -- is how a plausible-looking wrong number gets published.

   The two directions are not symmetric. Checked against German NFI stem volume
   x wood density, eq141 (Picea, fitted 11-47 cm) extrapolates *upward* almost
   perfectly -- ratio 0.96-0.98 all the way to 85 cm -- but *downward* it fails
   badly, over-estimating a 10 cm spruce by 3.2x and a 20 cm one by 1.5x. So
   trees above the fitted range are filled and flagged; trees below it are left
   NULL, because filling them would put a threefold error into the database
   with nothing to mark it.

3. Carbon fraction. Carbon is not a second model: it is a fixed fraction of dry
   biomass. IPCC (2006, GPG-LULUCF) gives 0.47 for temperate species, used here
   and recorded in the process description so the assumption is visible.

Requires:
    pip install "pylometree>=0.2.0"

Usage:
    python fill_missing_biomass.py             # apply
    python fill_missing_biomass.py --dry-run   # preview only
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection

try:
    import pylometree
    from pylometree.registry.base import registry
except ImportError:
    print('pylometree not installed. Run: pip install "pylometree>=0.2.0"')
    sys.exit(1)

# IPCC 2006 default carbon fraction of dry matter for temperate species.
CARBON_FRACTION = 0.47

# One preferred equation per species. Chosen on fitted DBH range first (it is
# what governs applicability here), then r2 and sample size.
#
#   Fagus     eq 88  D 5.7-62.1 cm, n=20, r2=0.974 -- the only beech entry whose
#                    range actually covers our stands (2.7-63.7 cm).
#   Picea     eq 141 D 11-47 cm, n=17, r2=0.967. The alternative (eq 151,
#                    Iceland) was fitted on trees under 28 cm at a marginal site
#                    and disagrees with eq 141 by a factor of 2.4.
#   Douglas   eq 526 D from 5 cm, upper bound not reported.
#
# Scots pine is registered in pylometree but excluded here: both entries were
# fitted on 2-16 cm saplings.
PREFERRED = {
    "Fagus sylvatica":       ("zianis2005_eq88_fagus_sylvatica_agb",        (5.7, 62.1)),
    "Picea abies":           ("zianis2005_eq141_picea_abies_agb",           (11.0, 47.0)),
    "Pseudotsuga menziesii": ("zianis2005_eq526_pseudotsuga_menziesii_agb", (5.0, None)),
}

PROCESS = {
    "process_name": "Tree Biomass Estimation",
    "algorithm_name": "Zianis 2005 aboveground biomass (pylometree)",
    "description": (
        "Total aboveground dry biomass from published European allometric "
        "equations (Zianis et al. 2005, Silva Fennica Monographs 4), applied per "
        f"species. Carbon content is {CARBON_FRACTION} x dry biomass (IPCC 2006 "
        "default for temperate species), not a separate model. Species without a "
        "qualifying equation in the monograph are left NULL rather than "
        "approximated by a congener."
    ),
    "author": "Zianis, D., Muukkonen, P., Mäkipää, R. & Mencuccini, M.",
    "citation": (
        "Zianis D, Muukkonen P, Mäkipää R, Mencuccini M (2005) Biomass and stem "
        "volume equations for tree species in Europe. Silva Fennica Monographs 4, "
        "63 p. doi:10.14214/sf.sfm4"
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
        (PROCESS["process_name"], PROCESS["algorithm_name"], version,
         PROCESS["description"], PROCESS["author"], PROCESS["citation"],
         PROCESS["category"]),
    )
    return cur.fetchone()[0]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="Preview, write nothing")
    ap.add_argument("--location", default=None, help="Restrict to one location_name")
    args = ap.parse_args()

    conn = get_db_connection()
    cur = conn.cursor()

    sql = """
        SELECT t.tree_id, sp.scientific_name, st.dbh_cm, t.height_m
        FROM trees.trees t
        JOIN shared.species sp USING (species_id)
        JOIN trees.stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
        JOIN shared.locations l ON l.location_id = t.location_id
        WHERE t.biomass_kg IS NULL AND st.dbh_cm IS NOT NULL AND t.height_m IS NOT NULL
    """
    params: list = []
    if args.location:
        sql += " AND l.location_name = %s"
        params.append(args.location)
    cur.execute(sql, params)
    rows = cur.fetchall()
    print(f"Trees needing biomass: {len(rows)}")

    filled: list[tuple[int, float, float]] = []
    skipped: dict[str, int] = {}
    out_of_range: dict[str, int] = {}

    for tree_id, species, dbh, height in rows:
        pref = PREFERRED.get(species)
        if pref is None:
            key = f"{species}: no qualifying Zianis equation"
            skipped[key] = skipped.get(key, 0) + 1
            continue
        model_id, (dmin, dmax) = pref
        entry = registry.get(model_id)
        d, h = float(dbh), float(height)

        if d < dmin:
            key = (f"{species}: DBH below fitted {dmin} cm "
                   f"(downward extrapolation unreliable)")
            skipped[key] = skipped.get(key, 0) + 1
            continue
        if dmax is not None and d > dmax:
            key = f"{species}: DBH above fitted {dmax} cm (upward extrapolation, validated)"
            out_of_range[key] = out_of_range.get(key, 0) + 1

        agb = float(entry.fn(dsob=d, hst=h) if "hst" in entry.covariates
                    else entry.fn(dsob=d))
        if agb != agb or agb <= 0:
            skipped[f"{species}: model returned no value"] = (
                skipped.get(f"{species}: model returned no value", 0) + 1)
            continue
        filled.append((tree_id, round(agb, 2), round(agb * CARBON_FRACTION, 2)))

    print(f"  estimated : {len(filled)}")
    for reason, n in sorted(skipped.items(), key=lambda kv: -kv[1]):
        print(f"  skipped {n:>5}: {reason}")
    for reason, n in sorted(out_of_range.items(), key=lambda kv: -kv[1]):
        print(f"  FILLED BUT EXTRAPOLATED {n:>5}: {reason}")

    if filled:
        agbs = [a for _, a, _ in filled]
        print(f"  biomass   : {min(agbs):.1f}-{max(agbs):.1f} kg "
              f"(mean {sum(agbs)/len(agbs):.1f}, total {sum(agbs)/1000:.1f} t)")

    if args.dry_run:
        print("[dry-run] nothing written")
        return
    if not filled:
        print("Nothing to write.")
        return

    version = pylometree.__version__
    process_id = ensure_process(cur, version)
    print(f"Provenance: shared.Processes id {process_id} (pylometree {version})")

    cur.execute(
        "SET LOCAL app.change_reason = %s",
        (f"Zianis 2005 aboveground biomass, carbon = {CARBON_FRACTION} x dry mass "
         f"(shared.Processes id {process_id}, pylometree {version})",),
    )

    from psycopg2.extras import execute_values

    # page_size covers the whole batch so cur.rowcount reports the true total.
    execute_values(
        cur,
        """UPDATE trees.trees t
           SET biomass_kg = v.agb, carbon_content_kg = v.carbon
           FROM (VALUES %s) AS v(tree_id, agb, carbon)
           WHERE t.tree_id = v.tree_id AND t.biomass_kg IS NULL""",
        filled,
        page_size=max(len(filled), 100),
    )
    n = cur.rowcount
    conn.commit()
    print(f"Updated {n} trees")


if __name__ == "__main__":
    main()
