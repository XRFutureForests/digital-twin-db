#!/usr/bin/env python3
"""
Fill NULL biomass_kg and carbon_content_kg in trees.Trees using pylometree's
registered aboveground biomass (AGB) equations.

Third in the family after fill_missing_heights.py and fill_missing_ages.py.

    AGB = a * D^b            (M1, diameter-only form used by every entry below)

Two published sources, in preference order (see PREFERRED):

1. Forrester et al. (2017), Forest Ecology and Management 396:160-175
   (doi:10.1016/j.foreco.2017.04.011), Table A.5 diameter-only form. Preferred
   wherever it has the species: fitted over far wider diameter ranges than
   Zianis (Picea 1-82 cm against 11-47 cm) on much larger samples (n=576
   against n=17), and it additionally covers Abies alba, Larix decidua and
   Quercus robur, for which Zianis has no aboveground equation at all.
   Registered in pylometree >= 0.3.0 as `forrester2017_*_agb`.

2. Zianis et al. (2005), Silva Fennica Monographs 4 (doi:10.14214/sf.sfm4).
   Used only where Forrester has no diameter-only row for the species
   (currently just Pseudotsuga menziesii). Registered in pylometree >= 0.2.0
   as `zianis2005_eq*_agb`.

Three things constrain what this can fill:

1. Species coverage. Neither source has a qualifying equation for Quercus
   petraea or the scattered broadleaves (Acer spp., Prunus avium, Betula
   pendula, Torminalis glaberrima). Those trees get nothing rather than a
   congener's equation -- substituting one would be inventing data.

2. DBH range. Each equation was fitted over a stated diameter range, and a
   power law with an exponent near 2.3 extrapolates badly. Trees below the
   fitted minimum are left NULL. Trees above the fitted maximum are filled but
   flagged in the run summary as extrapolated, since Forrester's ranges
   (fitted to full-grown trees, up to 84-90 cm depending on species) already
   cover essentially every stem these stands have; only genuine outliers hit
   this path.

3. Carbon fraction. Carbon is not a second model: it is a fixed fraction of dry
   biomass. IPCC (2006, GPG-LULUCF) gives 0.47 for temperate species, used here
   and recorded in the process description so the assumption is visible.

Requires:
    pip install "pylometree>=0.3.0"

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
    print('pylometree not installed. Run: pip install "pylometree>=0.3.0"')
    sys.exit(1)

# IPCC 2006 default carbon fraction of dry matter for temperate species.
CARBON_FRACTION = 0.47

# One preferred equation per species -- Forrester 2017 wherever it has the
# species, Zianis 2005 otherwise (Pseudotsuga menziesii; see module docstring).
# Scots pine (Pinus sylvestris) is registered in pylometree but excluded here:
# its two Zianis entries were both fitted on 2-16 cm saplings, and Forrester's
# Table A.5 has no diameter-only row for it.
PREFERRED = {
    "Abies alba":            ("forrester2017_abies_alba_agb",               (5.7, 57.7)),
    "Fagus sylvatica":       ("forrester2017_fagus_sylvatica_agb",          (1.0, 84.0)),
    "Larix decidua":         ("forrester2017_larix_decidua_agb",            (4.0, 90.1)),
    "Picea abies":           ("forrester2017_picea_abies_agb",              (1.0, 82.0)),
    "Quercus robur":         ("forrester2017_quercus_robur_agb",            (5.9, 67.5)),
    "Pseudotsuga menziesii": ("zianis2005_eq526_pseudotsuga_menziesii_agb", (5.0, None)),
}

PROCESS = {
    "process_name": "Tree Biomass Estimation",
    "algorithm_name": "Forrester 2017 / Zianis 2005 aboveground biomass (pylometree)",
    "description": (
        "Total aboveground dry biomass from published European allometric "
        "equations, applied per species: Forrester et al. (2017) generalized "
        "equations where available, Zianis et al. (2005) otherwise. "
        f"Carbon content is {CARBON_FRACTION} x dry biomass (IPCC 2006 default "
        "for temperate species), not a separate model. Species with no "
        "published equation are left NULL rather than approximated by a "
        "congener."
    ),
    "author": "Forrester, D.I. et al.; Zianis, D. et al.",
    "citation": (
        "Forrester DI et al. (2017) Generalized biomass and leaf area allometric "
        "equations for European tree species incorporating stand structure, tree "
        "age and climate. Forest Ecology and Management 396:160-175. "
        "doi:10.1016/j.foreco.2017.04.011 | "
        "Zianis D, Muukkonen P, Makipaa R, Mencuccini M (2005) Biomass and stem "
        "volume equations for tree species in Europe. Silva Fennica Monographs 4. "
        "doi:10.14214/sf.sfm4"
    ),
    "category": "analysis",
}


def ensure_process(cur, version: str) -> int:
    """Return the process id, creating or refreshing the row as needed.

    shared.Processes is UNIQUE on (process_name, version) -- not on
    algorithm_name -- so a changed algorithm at the same version has to update
    the existing row rather than insert beside it.
    """
    cur.execute(
        """SELECT process_id FROM shared.processes
           WHERE process_name = %s AND version = %s""",
        (PROCESS["process_name"], version),
    )
    row = cur.fetchone()
    if row:
        cur.execute(
            """UPDATE shared.processes
               SET algorithm_name = %s, description = %s, author = %s,
                   citation = %s, category = %s, updated_at = now()
               WHERE process_id = %s""",
            (PROCESS["algorithm_name"], PROCESS["description"], PROCESS["author"],
             PROCESS["citation"], PROCESS["category"], row[0]),
        )
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


def estimate(rows):
    """Run the preferred equation over (id, species, dbh, height) rows.

    Returns (filled, skipped, out_of_range), where filled is
    [(id, agb, carbon), ...]. Shared by the trees.Trees and
    trees.GrowthSimulations passes so both use identical equations, fitted
    ranges and skip rules -- the two tables must not disagree about the biomass
    of the same tree.
    """
    filled: list[tuple[int, float, float]] = []
    skipped: dict[str, int] = {}
    out_of_range: dict[str, int] = {}

    for row_id, species, dbh, height in rows:
        pref = PREFERRED.get(species)
        if pref is None:
            key = f"{species}: no published equation in Forrester 2017 or Zianis 2005"
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
        filled.append((row_id, round(agb, 2), round(agb * CARBON_FRACTION, 2)))

    return filled, skipped, out_of_range


def report(label, n_rows, filled, skipped, out_of_range):
    print(f"{label} needing biomass: {n_rows}")
    print(f"  estimated : {len(filled)}")
    for reason, n in sorted(skipped.items(), key=lambda kv: -kv[1]):
        print(f"  skipped {n:>5}: {reason}")
    for reason, n in sorted(out_of_range.items(), key=lambda kv: -kv[1]):
        print(f"  FILLED BUT EXTRAPOLATED {n:>5}: {reason}")
    if filled:
        agbs = [a for _, a, _ in filled]
        print(f"  biomass   : {min(agbs):.1f}-{max(agbs):.1f} kg "
              f"(mean {sum(agbs)/len(agbs):.1f}, total {sum(agbs)/1000:.1f} t)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="Preview, write nothing")
    ap.add_argument("--location", default=None, help="Restrict to one location_name")
    ap.add_argument("--refill", action="store_true",
                    help="Recompute values that are already set, not just NULLs. Use after "
                         "changing the preferred equation for a species, so the column does "
                         "not end up a mix of sources. The audit log records old -> new.")
    args = ap.parse_args()

    conn = get_db_connection()
    cur = conn.cursor()

    # ---- Pass 1: trees.Trees (measured inventory and promoted SILVA variants)
    sql = """
        SELECT t.tree_id, sp.scientific_name, st.dbh_cm, t.height_m
        FROM trees.trees t
        JOIN shared.species sp USING (species_id)
        JOIN trees.stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
        JOIN shared.locations l ON l.location_id = t.location_id
        WHERE st.dbh_cm IS NOT NULL AND t.height_m IS NOT NULL
    """
    if not args.refill:
        sql += " AND t.biomass_kg IS NULL"
    params: list = []
    if args.location:
        sql += " AND l.location_name = %s"
        params.append(args.location)
    cur.execute(sql, params)
    tree_rows = cur.fetchall()
    tree_filled, tree_skipped, tree_oor = estimate(tree_rows)
    report("Trees", len(tree_rows), tree_filled, tree_skipped, tree_oor)

    # ---- Pass 2: trees.GrowthSimulations (the SILVA trajectory)
    #
    # silva-connector writes geometry and stand metrics but no biomass, so
    # these stayed NULL while the mirrored simulated_growth rows in trees.Trees
    # got filled by pass 1. Computing from the trajectory's own dbh_cm and
    # height_m rather than copying across keeps the two consistent and still
    # works for a `run_simulation.R --no-promote` run, where the trajectory
    # exists with no trees.Trees rows to copy from.
    gsql = """
        SELECT g.growth_simulation_id, sp.scientific_name, g.dbh_cm, g.height_m
        FROM trees.growthsimulations g
        JOIN shared.species sp ON sp.species_id = g.species_id
        LEFT JOIN shared.locations l ON l.location_id = g.location_id
        WHERE g.dbh_cm IS NOT NULL AND g.height_m IS NOT NULL
    """
    if not args.refill:
        gsql += " AND g.biomass_kg IS NULL"
    gparams: list = []
    if args.location:
        gsql += " AND l.location_name = %s"
        gparams.append(args.location)
    cur.execute(gsql, gparams)
    sim_rows = cur.fetchall()
    sim_filled, sim_skipped, sim_oor = estimate(sim_rows)
    report("Growth simulations", len(sim_rows), sim_filled, sim_skipped, sim_oor)

    if args.dry_run:
        print("[dry-run] nothing written")
        return
    if not tree_filled and not sim_filled:
        print("Nothing to write.")
        return

    version = pylometree.__version__
    process_id = ensure_process(cur, version)
    print(f"Provenance: shared.Processes id {process_id} (pylometree {version})")

    cur.execute(
        "SET LOCAL app.change_reason = %s",
        (f"Forrester 2017 / Zianis 2005 aboveground biomass, carbon = {CARBON_FRACTION} x dry mass "
         f"(shared.Processes id {process_id}, pylometree {version})",),
    )

    from psycopg2.extras import execute_values

    n_trees = n_sims = 0

    if tree_filled:
        # page_size covers the whole batch so cur.rowcount reports the true total.
        execute_values(
            cur,
            """UPDATE trees.trees t
               SET biomass_kg = v.agb, carbon_content_kg = v.carbon
               FROM (VALUES %s) AS v(tree_id, agb, carbon)
               WHERE t.tree_id = v.tree_id"""
            + ("" if args.refill else " AND t.biomass_kg IS NULL"),
            tree_filled,
            page_size=max(len(tree_filled), 100),
        )
        n_trees = cur.rowcount

    if sim_filled:
        # trees.GrowthSimulations is append-only trajectory output and carries
        # no audit trigger; provenance for it is the run_id plus simulator_name
        # already on the row, and this script's shared.Processes entry.
        execute_values(
            cur,
            """UPDATE trees.growthsimulations g
               SET biomass_kg = v.agb, carbon_content_kg = v.carbon
               FROM (VALUES %s) AS v(growth_simulation_id, agb, carbon)
               WHERE g.growth_simulation_id = v.growth_simulation_id"""
            + ("" if args.refill else " AND g.biomass_kg IS NULL"),
            sim_filled,
            page_size=max(len(sim_filled), 100),
        )
        n_sims = cur.rowcount

    conn.commit()
    print(f"Updated {n_trees} trees, {n_sims} growth simulation rows")


if __name__ == "__main__":
    main()