#!/usr/bin/env python3
"""
Load the ECOSENSE leaves-on TLS stems as observations and record how each was
matched to an inventory tree (re-identification, XRFF-465).

Source: lidar-to-unreal's full TLS reference join,
`data/output/ecosense_tls_reference/reference_trees.csv` (regenerable there,
RUNBOOK §6): one row per TLS stem of ECOSENSE_TLS_195 with its stem position
(UTM 32N), circle-fit diameters, height and match outcome against the field
inventory (mutual nearest partner within 1.0 m, DBH ratio 0.7-1.4, no
competitor within 0.5 m).

Per stem with outcome matched, ambiguous or dbh_mismatch:
* one trees.observations row in campaign ecosense_tls_2024_leaf_on: position,
  DBH (circle fit at 1.3 m), height, observed 2024-10-15, and the reference's
  instance, outcome and distance in source_attributes. point_cloud_id stays
  NULL: the cloud lives on 3Dtrees.earth and cannot be registered until
  point clouds by reference exist (XRFF-643).
* one trees.entity_matches decision:
    matched       -> 'matched' to the ECOSENSE baseline tree with the same tree
                     number nearest the stem, within --max-dist m; if there is
                     none, 'ambiguous'
    ambiguous,
    dbh_mismatch  -> 'ambiguous', no entity
  method 'spatial', matched against ecosense_inventory_2024.
Unmatched stems (no field tree within 1 m, mostly outside the inventory
extent) are counted and left out: they would be new entities without a tree.

Re-running replaces this campaign's observations and their decisions (the
loader owns them; decisions made by people go in as new, superseding rows).
Needs scripts/seed/ecosense_mathisle_campaigns.sql applied first.

Usage:
    python scripts/import/import_tls_observations.py            # dry run (default)
    python scripts/import/import_tls_observations.py --apply    # write
"""

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path

from psycopg2.extras import execute_values

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection, REPO_ROOT

DEFAULT_REFERENCE = (
    REPO_ROOT.parent / "lidar-to-unreal" / "data" / "output" / "ecosense_tls_reference" / "reference_trees.csv"
)
CAMPAIGN = "ecosense_tls_2024_leaf_on"
REFERENCE_CAMPAIGN = "ecosense_inventory_2024"
DECIDED_BY = "lidar-to-unreal ecosense_tls_reference (XRFF-574)"
LOADED = ("matched", "ambiguous", "dbh_mismatch")


def num(v):
    return float(v) if v not in ("", None) else None


def load_reference(path: Path):
    rows, outcomes = [], Counter()
    with path.open(newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            outcomes[r["match"]] += 1
            if r["match"] not in LOADED:
                continue
            height = num(r["height_m"])
            attrs = {
                "cloud": "ECOSENSE_TLS_195 (3Dtrees.earth dataset 195)",
                "instance": int(r["instance"]),
                "match": r["match"],
                "match_note": r["match_note"] or None,
                "match_dist_m": num(r["match_dist_m"]),
                "dbh_ratio_tls_field": num(r["dbh_ratio_tls_field"]),
                "field_tree_number": int(float(r["field_tree_number"])) if r["field_tree_number"] else None,
                "tier": r["tier"] or None,
            }
            rows.append((
                int(r["instance"]), r["match"], attrs["field_tree_number"],
                float(r["x"]), float(r["y"]), num(r["d13_cm"]),
                round(height, 2) if height and height > 0 else None,
                json.dumps(attrs),
            ))
    return rows, outcomes


WRITE_SQL = """
WITH c AS (SELECT campaign_id, location_id FROM shared.campaigns WHERE campaign_name = %(campaign)s),
     ref AS (SELECT campaign_id FROM shared.campaigns WHERE campaign_name = %(reference_campaign)s),
     base AS (
        SELECT t.tree_id, t.tree_entity_id, t.tree_number, t.position_original
          FROM trees.trees t
          JOIN trees.observations o ON o.tree_id = t.tree_id
          JOIN ref ON ref.campaign_id = o.campaign_id
     ),
     resolved AS (
        SELECT s.*, b.tree_entity_id, b.dist_m
          FROM tls s
          LEFT JOIN LATERAL (
              SELECT b.tree_entity_id,
                     ST_Distance(b.position_original, ST_SetSRID(ST_MakePoint(s.x, s.y), 32632)) AS dist_m
                FROM base b
               WHERE s.match = 'matched'
                 AND b.tree_number IS NOT DISTINCT FROM s.field_tree_number
                 AND ST_SRID(b.position_original) = 32632
               ORDER BY b.position_original <-> ST_SetSRID(ST_MakePoint(s.x, s.y), 32632)
               LIMIT 1
          ) b ON b.dist_m <= %(max_dist)s
     ),
     obs AS (
        INSERT INTO trees.observations (location_id, campaign_id, observed_on, "position", dbh_cm, height_m,
                                        source_attributes)
        SELECT c.location_id, c.campaign_id, DATE '2024-10-15',
               ST_Transform(ST_SetSRID(ST_MakePoint(r.x, r.y), 32632), 4326), r.dbh_cm, r.height_m,
               r.attrs || jsonb_build_object('resolved_tree_entity_id', r.tree_entity_id,
                                             'resolved_dist_m', round(r.dist_m::numeric, 3))
          FROM resolved r, c
        RETURNING observation_id, source_attributes
     )
INSERT INTO trees.entity_matches (observation_id, tree_entity_id, decision, method, reference_campaign_id,
                                  decided_by, notes)
SELECT o.observation_id,
       (o.source_attributes ->> 'resolved_tree_entity_id')::uuid,
       CASE WHEN o.source_attributes ->> 'resolved_tree_entity_id' IS NOT NULL THEN 'matched' ELSE 'ambiguous' END,
       'spatial', ref.campaign_id, %(decided_by)s,
       CASE
         WHEN o.source_attributes ->> 'resolved_tree_entity_id' IS NOT NULL
           THEN format('Mutual nearest partner within 1.0 m, DBH ratio %%s; resolved to the inventory tree %%s m away.',
                       o.source_attributes ->> 'dbh_ratio_tls_field', o.source_attributes ->> 'resolved_dist_m')
         WHEN o.source_attributes ->> 'match' = 'matched'
           THEN 'Matched in the reference, but no inventory tree with that tree number within the distance limit.'
         ELSE concat_ws(': ', o.source_attributes ->> 'match', o.source_attributes ->> 'match_note')
       END
  FROM obs o, ref
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--reference", type=Path, default=DEFAULT_REFERENCE)
    ap.add_argument("--max-dist", type=float, default=1.0, help="metres (default 1.0)")
    ap.add_argument("--apply", action="store_true", help="write (default: dry run, rolled back)")
    args = ap.parse_args()

    if not args.reference.exists():
        print(f"reference not found: {args.reference}", file=sys.stderr)
        return 1
    rows, outcomes = load_reference(args.reference)
    print("reference outcomes:", dict(outcomes), "| loaded:", len(rows))

    conn = get_db_connection()
    try:
        with conn, conn.cursor() as cur:
            cur.execute("SET search_path TO public, extensions")
            cur.execute(
                "SELECT count(*) FROM shared.campaigns WHERE campaign_name IN (%s, %s)",
                (CAMPAIGN, REFERENCE_CAMPAIGN),
            )
            if cur.fetchone()[0] != 2:
                raise RuntimeError("campaigns missing: apply scripts/seed/ecosense_mathisle_campaigns.sql first")
            cur.execute("""CREATE TEMP TABLE tls (instance int, match text, field_tree_number int,
                           x double precision, y double precision, dbh_cm numeric, height_m numeric,
                           attrs jsonb) ON COMMIT DROP""")
            execute_values(cur, "INSERT INTO tls VALUES %s", rows)
            # Deleting the observations cascades to every decision on them, also
            # the superseding ones people added. Those are not the loader's to drop.
            cur.execute("""SELECT count(*) FROM trees.entity_matches m
                             JOIN trees.observations o USING (observation_id)
                             JOIN shared.campaigns c ON c.campaign_id = o.campaign_id
                            WHERE c.campaign_name = %s AND m.decided_by <> %s""", (CAMPAIGN, DECIDED_BY))
            if cur.fetchone()[0]:
                raise RuntimeError("this campaign's observations carry decisions not made by this loader; "
                                   "re-running would delete them")
            cur.execute("""DELETE FROM trees.observations o USING shared.campaigns c
                            WHERE c.campaign_id = o.campaign_id AND c.campaign_name = %s""", (CAMPAIGN,))
            print("replaced observations:", cur.rowcount)
            cur.execute(WRITE_SQL, {"campaign": CAMPAIGN, "reference_campaign": REFERENCE_CAMPAIGN,
                                    "max_dist": args.max_dist, "decided_by": DECIDED_BY})
            cur.execute("""SELECT m.decision, count(*), count(DISTINCT m.tree_entity_id)
                             FROM trees.entity_matches m JOIN trees.observations o USING (observation_id)
                             JOIN shared.campaigns c ON c.campaign_id = o.campaign_id
                            WHERE c.campaign_name = %s GROUP BY 1 ORDER BY 1""", (CAMPAIGN,))
            for decision, n, entities in cur.fetchall():
                print(f"  {decision:<10} {n:>5} observations, {entities} distinct entities")
            if not args.apply:
                conn.rollback()
                print("dry run: rolled back (use --apply to write)")
                return 0
        print("written")
        return 0
    except Exception as exc:  # the runner reads only the exit code
        print(f"failed: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
