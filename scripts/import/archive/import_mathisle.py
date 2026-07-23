#!/usr/bin/env python3
"""
Import Mathisle tree data into Forest Digital Twin Database

This script imports tree data from data/imports/mathisle_trees_import.csv:
- Creates Trees records with species, location, position (WGS84)
- Creates Stems records with DBH measurements
- Stores FieldNotes metadata (TreeID, Plot, Species, QR code)
"""

import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values

# Load environment
env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
load_dotenv(env_path)

# Database configuration
POSTGRES_HOST = "localhost"
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DATABASE = os.getenv("POSTGRES_DB", "postgres")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POOLER_TENANT_ID = os.getenv("POOLER_TENANT_ID", "")

if POOLER_TENANT_ID:
    POSTGRES_USER_POOLER = f"{POSTGRES_USER}.{POOLER_TENANT_ID}"
else:
    POSTGRES_USER_POOLER = POSTGRES_USER

# Constants
CSV_PATH = (
    Path(__file__).parent.parent.parent
    / "data"
    / "imports"
    / "mathisle_trees_import.csv"
)
CREATED_BY = "import_mathisle_script"
LOCATION_ID = 4  # Mathisle


def get_db_connection():
    """Create database connection"""
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER_POOLER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )


def main():
    print("=" * 80)
    print("MATHISLE TREE DATA IMPORT")
    print("=" * 80)

    # Check CSV exists
    if not CSV_PATH.exists():
        print(f"❌ CSV file not found: {CSV_PATH}")
        sys.exit(1)

    # Check if trees already exist for Mathisle
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT count(*) FROM trees.trees WHERE locationid = %s", (LOCATION_ID,)
    )
    existing = cur.fetchone()[0]
    if existing > 0:
        print(
            f"⚠️  {existing} trees already exist for LocationID={LOCATION_ID} (Mathisle)"
        )
        response = input("Continue and add more? (y/N): ").strip().lower()
        if response != "y":
            print("Aborted.")
            conn.close()
            sys.exit(0)
    conn.close()

    # Load CSV (skip comment lines starting with #)
    print(f"\n📂 Loading CSV: {CSV_PATH.name}")
    df = pd.read_csv(CSV_PATH, comment="#")
    print(f"✓ Loaded {len(df)} rows")

    # Filter rows with valid coordinates
    valid = df["Latitude"].notna() & df["Longitude"].notna()
    skipped = len(df) - valid.sum()
    if skipped > 0:
        print(f"⚠️  Skipping {skipped} rows with missing coordinates")
    df = df[valid].copy()
    print(f"✓ {len(df)} rows with valid coordinates")

    # Insert trees
    print("\n💾 Inserting trees into database...")
    conn = get_db_connection()
    cur = conn.cursor()

    insert_query = """
        INSERT INTO trees.Trees (
            LocationID, PlotID, CampaignID, VariantTypeID, SpeciesID,
            TreeStatusID, DataSourceType, SourceCRS,
            Height_m, Position, FieldNotes, MeasurementDate, CreatedBy
        )
        VALUES %s
        RETURNING TreeID
    """

    def _clean(val):
        if val is None:
            return None
        if isinstance(val, float) and pd.isna(val):
            return None
        return val

    values = []
    for _, row in df.iterrows():
        position_wkt = f"POINT({row['Longitude']} {row['Latitude']})"
        values.append(
            (
                LOCATION_ID,
                _clean(row.get("PlotID")),
                _clean(row.get("CampaignID")),
                int(row["VariantTypeID"]) if pd.notna(row.get("VariantTypeID")) else 1,
                int(row["SpeciesID"]) if pd.notna(row.get("SpeciesID")) else None,
                int(row["TreeStatusID"]) if pd.notna(row.get("TreeStatusID")) else None,
                (
                    str(row["DataSourceType"])
                    if pd.notna(row.get("DataSourceType"))
                    else "field"
                ),
                _clean(row.get("SourceCRS")),
                float(row["Height_m"]) if pd.notna(row.get("Height_m")) else None,
                position_wkt,
                str(row["FieldNotes"]) if pd.notna(row.get("FieldNotes")) else None,
                (
                    str(row["MeasurementDate"])
                    if pd.notna(row.get("MeasurementDate"))
                    else None
                ),
                CREATED_BY,
            )
        )

    tree_ids = execute_values(
        cur,
        insert_query,
        values,
        template="(%s, %s, %s, %s, %s, %s, %s, %s, %s, ST_GeomFromText(%s, 4326), %s, %s, %s)",
        fetch=True,
    )

    conn.commit()
    print(f"✓ Inserted {len(tree_ids)} trees")

    # Insert stems for trees with DBH
    print("\n💾 Inserting stem measurements...")
    stems = []
    for i, (tree_id,) in enumerate(tree_ids):
        row = df.iloc[i]
        dbh = row.get("DBH_cm")
        if pd.notna(dbh) and float(dbh) > 0:
            stems.append((tree_id, 1, float(dbh)))

    if stems:
        stem_query = """
            INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm)
            VALUES %s
        """
        execute_values(cur, stem_query, stems)
        conn.commit()
        print(f"✓ Inserted {len(stems)} stem measurements")
    else:
        print("⚠️  No DBH measurements to insert")

    conn.close()

    # Verify
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT count(*) FROM trees.trees WHERE locationid = %s", (LOCATION_ID,)
    )
    total = cur.fetchone()[0]
    cur.execute(
        "SELECT count(*) FROM trees.stems s JOIN trees.trees t ON s.treeid = t.treeid WHERE t.locationid = %s",
        (LOCATION_ID,),
    )
    stem_total = cur.fetchone()[0]
    conn.close()

    print(f"\n✅ MATHISLE IMPORT COMPLETE")
    print(f"   Trees in database (LocationID={LOCATION_ID}): {total}")
    print(f"   Stems in database: {stem_total}")


if __name__ == "__main__":
    main()
