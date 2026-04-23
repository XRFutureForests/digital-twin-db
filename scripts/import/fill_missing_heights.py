#!/usr/bin/env python3
"""
Fill NULL Height_m values in trees.Trees using pylometree H-D allometric models.

Requires:
    pip install pylometree  (XRFF-131: pylometree published to PyPI)

Usage:
    python fill_missing_heights.py            # apply updates
    python fill_missing_heights.py --dry-run  # preview only
"""

import argparse
import os
import sys
from collections import defaultdict
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

try:
    from pylometree.models.hd import fit_hd_model
    from pylometree.yield_tables import get_yield_table
except ImportError:
    print("pylometree not installed. Run: pip install pylometree")
    print("(Requires XRFF-131: pylometree published to PyPI)")
    sys.exit(1)

env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
load_dotenv(env_path)

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DATABASE = os.getenv("POSTGRES_DB", "postgres")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POOLER_TENANT_ID = os.getenv("POOLER_TENANT_ID", "")

if POOLER_TENANT_ID:
    POSTGRES_USER = f"{POSTGRES_USER}.{POOLER_TENANT_ID}"


def get_db_connection():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )


def ensure_height_source_column(conn):
    cur = conn.cursor()
    cur.execute("""
        ALTER TABLE trees.Trees
        ADD COLUMN IF NOT EXISTS HeightSource VARCHAR(50) DEFAULT 'measured'
    """)
    conn.commit()
    cur.close()


def fetch_trees_missing_height(conn):
    cur = conn.cursor()
    cur.execute("""
        SELECT t.VariantID, s.ScientificName, st.DBH_cm
        FROM trees.Trees t
        JOIN shared.Species s ON t.SpeciesID = s.SpeciesID
        JOIN trees.Stems st ON st.TreeVariantID = t.VariantID
        WHERE t.Height_m IS NULL
          AND st.DBH_cm IS NOT NULL
          AND st.StemNumber = 1
    """)
    rows = cur.fetchall()
    cur.close()
    return rows


def build_species_models(rows):
    species_dbhs = defaultdict(list)
    for _, scientific_name, dbh_cm in rows:
        species_dbhs[scientific_name].append(dbh_cm)

    models = {}
    for scientific_name in species_dbhs:
        try:
            yt = get_yield_table(scientific_name)
            models[scientific_name] = fit_hd_model(yt)
        except Exception as e:
            print(f"  Warning: no H-D model for '{scientific_name}': {e}")
    return models


def main():
    parser = argparse.ArgumentParser(description="Fill missing tree heights via allometry")
    parser.add_argument("--dry-run", action="store_true", help="Preview without updating")
    args = parser.parse_args()

    print("=" * 60)
    print("FILL MISSING TREE HEIGHTS — pylometree allometric models")
    print("=" * 60)

    conn = get_db_connection()

    ensure_height_source_column(conn)

    rows = fetch_trees_missing_height(conn)
    print(f"Trees with NULL Height_m: {len(rows)}")

    if not rows:
        print("Nothing to do.")
        conn.close()
        return 0

    print("\nFitting H-D models per species...")
    models = build_species_models(rows)

    updates = []
    skipped = 0

    for variant_id, scientific_name, dbh_cm in rows:
        model = models.get(scientific_name)
        if model is None:
            skipped += 1
            continue
        try:
            predicted_h = float(model.predict(dbh_cm))
            updates.append((predicted_h, 'allometric_pylometree', variant_id))
        except Exception as e:
            print(f"  Warning: prediction failed for VariantID={variant_id}: {e}")
            skipped += 1

    print(f"\nPredictions ready: {len(updates)} updates, {skipped} skipped")

    if args.dry_run:
        print("\nDry-run — sample predictions (first 10):")
        for h, source, vid in updates[:10]:
            print(f"  VariantID={vid}: Height_m={h:.2f} (source={source})")
        print("\nRe-run without --dry-run to apply.")
        conn.close()
        return 0

    cur = conn.cursor()
    cur.executemany("""
        UPDATE trees.Trees
        SET Height_m = %s,
            HeightSource = %s,
            DataSourceType = 'estimated',
            UpdatedAt = NOW(),
            UpdatedBy = 'fill_missing_heights'
        WHERE VariantID = %s
    """, updates)
    conn.commit()
    cur.close()

    print(f"\nUpdated {len(updates)} trees.")

    # Verify
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM trees.Trees WHERE Height_m IS NULL")
    remaining = cur.fetchone()[0]
    cur.execute("""
        SELECT HeightSource, COUNT(*)
        FROM trees.Trees
        GROUP BY HeightSource
        ORDER BY HeightSource
    """)
    source_counts = cur.fetchall()
    cur.close()
    conn.close()

    print(f"Remaining NULL heights: {remaining}")
    print("\nHeight sources:")
    for source, count in source_counts:
        print(f"  {source or 'NULL'}: {count}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
