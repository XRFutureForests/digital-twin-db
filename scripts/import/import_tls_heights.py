#!/usr/bin/env python3
"""
Replace Ecosense beech heights with the TLS heights of the matched TLS stems.

Source: the Ecosense TLS tree reference built in lidar-to-unreal (XRFF-574) from
ECOSENSE_TLS_195.laz, `docs/ecosense-tls-reference/reference_trees_gate.csv`.
Each row there is a TLS stem matched one-to-one to a field tree (nearest partner
within 1 m, compatible DBH); `height_m` is the highest kept point of the stem's
instance above the stem's ground.

Why: the `measured` heights of the 2025 inventory were read off the ECOSENSE.las
canopy surface. For dominant beech they agree with TLS (median -0.07 m), for
understory beech (DBH < 20 cm) they are the overstory canopy, ~8.5 m too tall
(owner decision 2026-10-27).

Which rows of the reference are used:
* tier A and B only. Tier C (`flag_merged`) instances hold a neighbour's stem,
  so their height may be the neighbour's.
* not `flag_hd` (height implausible for the DBH: crown lost to, or taken from, a
  neighbour) and not `flag_edge` (instance at the scan extent, crown may be cut).

Matching to the database is by position, not by tree_id (tree_id changes on every
rebuild): the baseline tree of the same tree number nearest to the TLS stem centre
at 1.3 m, within --max-dist m. The reference's `field_tree_id` is only checked.

Per matched tree whose height or height_source differs:
* height_m       := TLS height (2 decimals), height_source := 'measured_tls'
* height_class_id := NULL, re-assigned by trg_trees_assign_height_class
* field_notes    += 'pre_tls_height_m: <old> (<old height_source>)'
* crown_width_m, crown_base_height_m, volume_m3, age_years, biomass_kg,
  carbon_content_kg and the stems' stem_volume_m3 := NULL, as in
  scripts/seed/ecosense_canopy_height_fix.sql: all derived from the old height.
  Refill them afterwards (silva-connector scripts/fill_allometry.R,
  scripts/import/fill_missing_ages.py, scripts/import/fill_missing_biomass.py).
* the audit trail (shared.audit_log) records the old and new height with
  change_reason = PROVENANCE.

Before writing, the affected rows (old values) are saved to
data/output/tls_heights/backup_<timestamp>.csv. A second run changes nothing.

Usage:
    python scripts/import/import_tls_heights.py            # dry run (default)
    python scripts/import/import_tls_heights.py --apply    # write
"""

import argparse
import csv
import statistics
import sys
from datetime import datetime
from pathlib import Path

from psycopg2.extras import execute_values

# Allow importing from scripts/utils/ when running as a script
sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import POSTGRES_HOST, POSTGRES_PORT, get_db_connection, REPO_ROOT

DEFAULT_REFERENCE = (
    REPO_ROOT.parent
    / "lidar-to-unreal"
    / "docs"
    / "ecosense-tls-reference"
    / "reference_trees_gate.csv"
)
BACKUP_DIR = REPO_ROOT / "data" / "output" / "tls_heights"

HEIGHT_SOURCE = "measured_tls"
PROVENANCE = "TLS ECOSENSE_TLS_195, lidar-to-unreal XRFF-574, 2026-10-27"
SPECIES = {"european_beech": "Fagus sylvatica"}
EXCLUDE_FLAGS = ("flag_merged", "flag_hd", "flag_edge")
DERIVED_COLUMNS = (
    "crown_width_m",
    "crown_base_height_m",
    "volume_m3",
    "age_years",
    "biomass_kg",
    "carbon_content_kg",
)
DBH_CLASSES = ((0, 20, "<20 cm"), (20, 30, "20-30 cm"), (30, 999, ">=30 cm"))


def load_reference(path: Path, tiers: set[str]):
    """Rows of the gate table usable for heights, and the excluded counts."""
    rows, excluded = [], {}
    with path.open(newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["tier"] not in tiers:
                key = f"tier {r['tier']}"
                excluded[key] = excluded.get(key, 0) + 1
                continue
            hit = [f for f in EXCLUDE_FLAGS if r[f] == "True"]
            if hit:
                key = "+".join(hit)
                excluded[key] = excluded.get(key, 0) + 1
                continue
            if r["species_key"] not in SPECIES:
                excluded["species"] = excluded.get("species", 0) + 1
                continue
            flags = "+".join(
                k[5:] for k, v in r.items() if k.startswith("flag_") and v == "True"
            )
            rows.append(
                (
                    int(r["tls_instance"]),
                    int(r["field_tree_id"]) if r["field_tree_id"] else None,
                    int(r["field_tree_number"]) if r["field_tree_number"] else None,
                    SPECIES[r["species_key"]],
                    r["tier"],
                    flags,
                    round(float(r["height_m"]), 2),
                    float(r["stem_x"]),
                    float(r["stem_y"]),
                )
            )
    return rows, excluded


RESOLVE_SQL = """
SELECT r.tls_instance, r.field_tree_id, r.tier, r.flags, r.h_tls,
       t.tree_id, p.plot_name, t.tree_number, t.dist_m,
       st.dbh_cm, t.height_m, t.height_source, t.height_class_id,
       t.crown_width_m, t.crown_base_height_m, t.volume_m3, t.age_years,
       t.biomass_kg, t.carbon_content_kg, st.stem_volume_m3, t.field_notes
FROM tls_ref r
JOIN LATERAL (
    SELECT t.*,
           ST_Distance(t.position_original,
                       ST_SetSRID(ST_MakePoint(r.stem_x, r.stem_y), 32632)) AS dist_m
    FROM trees.trees t
    JOIN shared.species s ON s.species_id = t.species_id
    WHERE t.location_id = %(location_id)s
      AND t.variant_id = %(variant_id)s
      AND s.scientific_name = r.scientific_name
      AND t.tree_number IS NOT DISTINCT FROM r.field_tree_number
      AND ST_SRID(t.position_original) = 32632
    ORDER BY t.position_original <-> ST_SetSRID(ST_MakePoint(r.stem_x, r.stem_y), 32632)
    LIMIT 1
) t ON t.dist_m <= %(max_dist)s
LEFT JOIN shared.plots p ON p.plot_id = t.plot_id
LEFT JOIN trees.stems st ON st.tree_id = t.tree_id AND st.stem_number = 1
ORDER BY t.tree_id
"""

COLUMNS = (
    "tls_instance field_tree_id tier flags h_tls tree_id plot_name tree_number "
    "dist_m dbh_cm height_m height_source height_class_id crown_width_m "
    "crown_base_height_m volume_m3 age_years biomass_kg carbon_content_kg "
    "stem_volume_m3 field_notes"
).split()


def dbh_class(dbh):
    for lo, hi, name in DBH_CLASSES:
        if dbh is not None and lo <= float(dbh) < hi:
            return name
    return "no DBH"


def q(values, p):
    """Quantile p of a list (nearest rank on the sorted values)."""
    s = sorted(values)
    return s[min(len(s) - 1, max(0, round(p * (len(s) - 1))))]


def summary(label, old, new):
    if not old:
        return f"  {label:<26} n    0"
    d = [n - o for o, n in zip(old, new)]
    return (
        f"  {label:<26} n {len(old):4d}  old median {statistics.median(old):5.2f}"
        f"  new median {statistics.median(new):5.2f}  delta median {statistics.median(d):+6.2f}"
        f"  p5 {q(d, 0.05):+6.2f}  p95 {q(d, 0.95):+6.2f}"
    )


def report(targets, unchanged):
    print(f"\nMatched trees already at the TLS height and source: {unchanged}")
    print(f"Trees to update: {len(targets)}")
    if not targets:
        return

    print("\nBy tier x DBH class (count):")
    tiers = sorted({t["tier"] for t in targets})
    print("  " + " " * 10 + "".join(f"{t:>7}" for t in tiers) + "    all")
    for _, _, name in DBH_CLASSES + ((None, None, "no DBH"),):
        row = [sum(1 for t in targets if t["tier"] == k and dbh_class(t["dbh_cm"]) == name) for k in tiers]
        if sum(row):
            print(f"  {name:<10}" + "".join(f"{n:7d}" for n in row) + f"{sum(row):7d}")

    print("\nBy old height_source:")
    for src in sorted({str(t["height_source"]) for t in targets}):
        n = sum(1 for t in targets if str(t["height_source"]) == src)
        print(f"  {src:<26} {n:4d}")

    print("\nOld vs new height (m), by old source and DBH class:")
    for src in sorted({str(t["height_source"]) for t in targets}):
        for _, _, name in DBH_CLASSES:
            sel = [t for t in targets if str(t["height_source"]) == src and dbh_class(t["dbh_cm"]) == name]
            print(summary(f"{src} {name}", [float(t["height_m"]) for t in sel], [float(t["h_tls"]) for t in sel]))
    allo = [float(t["height_m"]) for t in targets]
    print(summary("all", allo, [float(t["h_tls"]) for t in targets]))

    meas = [t for t in targets if t["height_source"] == "measured"]
    big = [t for t in meas if abs(float(t["h_tls"]) - float(t["height_m"])) > 1.0]
    allometric = [t for t in targets if str(t["height_source"]).startswith("allometric")]
    print(f"\n'measured' heights changing by > 1 m: {len(big)} of {len(meas)}"
          f" (lower {sum(1 for t in big if t['h_tls'] < t['height_m'])},"
          f" higher {sum(1 for t in big if t['h_tls'] > t['height_m'])})")
    print(f"Allometric heights replaced: {len(allometric)}"
          f" ({', '.join(f'{s} {sum(1 for t in allometric if t['height_source'] == s)}' for s in sorted({t['height_source'] for t in allometric}))})")
    cbh = sum(1 for t in targets if t["crown_base_height_m"] is not None
              and float(t["crown_base_height_m"]) > float(t["h_tls"]))
    print(f"Current crown base above the TLS height (would break chk_crown_base_height): {cbh}")


def write_backup(targets) -> Path:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    path = BACKUP_DIR / f"backup_{datetime.now():%Y%m%d_%H%M%S}.csv"
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(targets)
    return path


def main():
    parser = argparse.ArgumentParser(description="Write Ecosense TLS beech heights")
    parser.add_argument("--reference", type=Path, default=DEFAULT_REFERENCE,
                        help="reference_trees_gate.csv of the Ecosense TLS reference")
    parser.add_argument("--apply", action="store_true", help="write (default: dry run)")
    parser.add_argument("--location", default="ecosense")
    parser.add_argument("--variant", default="baseline_2025")
    parser.add_argument("--tiers", default="A,B")
    parser.add_argument("--max-dist", type=float, default=1.0,
                        help="max TLS stem to field position distance, m (the reference matching radius)")
    args = parser.parse_args()

    print("=" * 60)
    print("TLS HEIGHTS — Ecosense TLS reference -> trees.trees")
    print("=" * 60)
    print(f"Database: {POSTGRES_HOST}:{POSTGRES_PORT}   mode: {'APPLY' if args.apply else 'dry run'}")
    print(f"Reference: {args.reference}")

    ref, excluded = load_reference(args.reference, set(args.tiers.split(",")))
    print(f"Reference rows used: {len(ref)}; excluded: "
          + ", ".join(f"{k} {v}" for k, v in sorted(excluded.items())))

    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SET search_path TO trees, shared, extensions, public")
    cur.execute(
        """SELECT l.location_id, v.variant_id FROM shared.locations l
           JOIN shared.variants v ON v.location_id = l.location_id
           WHERE l.location_name = %s AND v.variant_name = %s""",
        (args.location, args.variant),
    )
    found = cur.fetchone()
    if not found:
        print(f"No variant {args.variant} at location {args.location}.")
        return 1
    location_id, variant_id = found

    cur.execute(
        """CREATE TEMP TABLE tls_ref (tls_instance int, field_tree_id int,
           field_tree_number int, scientific_name text, tier text, flags text,
           h_tls numeric(6,2), stem_x float8, stem_y float8) ON COMMIT DROP"""
    )
    execute_values(cur, "INSERT INTO tls_ref VALUES %s", ref)
    cur.execute(RESOLVE_SQL, {"location_id": location_id, "variant_id": variant_id,
                              "max_dist": args.max_dist})
    matched = [dict(zip(COLUMNS, r)) for r in cur.fetchall()]

    ids = [m["tree_id"] for m in matched]
    if len(ids) != len(set(ids)):
        print("ERROR: a database tree matched more than one TLS stem; nothing written.")
        conn.rollback()
        return 1
    id_mismatch = sum(1 for m in matched if m["field_tree_id"] != m["tree_id"])
    print(f"Matched to {args.location}/{args.variant}: {len(matched)} of {len(ref)}"
          f" (unmatched {len(ref) - len(matched)}; reference field_tree_id differs: {id_mismatch};"
          f" max distance {max((float(m['dist_m']) for m in matched), default=0):.3f} m)")

    targets = [m for m in matched
               if m["height_m"] != m["h_tls"] or m["height_source"] != HEIGHT_SOURCE]
    report(targets, len(matched) - len(targets))

    if not args.apply or not targets:
        conn.rollback()
        conn.close()
        print("\nDry run — nothing written. Re-run with --apply to write." if not args.apply
              else "\nNothing to do.")
        return 0

    backup = write_backup(targets)
    print(f"\nBackup of {len(targets)} rows: {backup}")

    cur.execute("SET LOCAL app.change_reason = %s", (PROVENANCE,))
    cur.execute(
        """CREATE TEMP TABLE tls_hit ON COMMIT DROP AS
           SELECT t.tree_id, r.h_tls FROM tls_ref r
           JOIN unnest(%s::int[], %s::int[]) AS m(tree_id, tls_instance)
             ON m.tls_instance = r.tls_instance
           JOIN trees.trees t ON t.tree_id = m.tree_id""",
        ([m["tree_id"] for m in targets], [m["tls_instance"] for m in targets]),
    )
    cur.execute(
        f"""UPDATE trees.trees t
            SET height_m = h.h_tls,
                height_source = %s,
                height_class_id = NULL,
                field_notes = coalesce(t.field_notes || ' | ', '')
                    || 'pre_tls_height_m: ' || coalesce(t.height_m::text, 'NULL')
                    || ' (' || coalesce(t.height_source, 'NULL') || ')',
                {', '.join(f'{c} = NULL' for c in DERIVED_COLUMNS)}
            FROM tls_hit h
            WHERE t.tree_id = h.tree_id""",
        (HEIGHT_SOURCE,),
    )
    n_trees = cur.rowcount
    cur.execute(
        """UPDATE trees.stems s SET stem_volume_m3 = NULL
           FROM tls_hit h WHERE s.tree_id = h.tree_id AND s.stem_volume_m3 IS NOT NULL"""
    )
    n_stems = cur.rowcount
    conn.commit()
    print(f"Updated {n_trees} trees ({n_stems} stem volumes cleared).")

    cur.execute(
        """SELECT height_source, count(*) FROM trees.trees
           WHERE location_id = %s AND variant_id = %s GROUP BY 1 ORDER BY 1""",
        (location_id, variant_id),
    )
    print("\nHeight sources now:")
    for src, n in cur.fetchall():
        print(f"  {src or 'NULL'}: {n}")
    print("\nRefill the cleared derived values next (see the module docstring).")
    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
