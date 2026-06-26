#!/usr/bin/env python3
"""
Import ecosense tree data into Digital Forest Twin Database

This script imports tree data from ecosense_250911.csv:
- Creates Trees records with species, location, height, position
- Creates Stems records with DBH measurements
- Stores metadata (plot_id, tree_id, etc.) in FieldNotes as JSON
"""

import json
import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values

try:
    from pyproj import Transformer

    HAS_PYPROJ = True
except ImportError:
    print("❌ pyproj not installed. Install with: pip install pyproj")
    sys.exit(1)

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
CSV_PATH = Path(__file__).parent.parent.parent / "data" / "ecosense_250911.csv"
CREATED_BY = "import_ecosense_script"
LOCATION_ID = 5  # Ecosense_MixedPlot
VARIANT_TYPE_ID = 1  # original


def get_db_connection():
    """Create database connection"""
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER_POOLER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )


def get_species_mapping():
    """Load species mapping from database"""
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT SpeciesID, CommonName, ScientificName FROM shared.Species")
    species_map = {}
    for species_id, common_name, scientific_name in cur.fetchall():
        # Map both common and scientific names to ID
        if common_name:
            species_map[common_name.lower()] = species_id
        if scientific_name:
            species_map[scientific_name.lower()] = species_id

    # Add common variations and abbreviations
    species_aliases = {
        "beech": species_map.get("european beech"),
        "be": species_map.get("european beech"),
        "douglas fir": species_map.get("douglas fir"),
        "df": species_map.get("douglas fir"),
        "spruce": species_map.get("norway spruce"),
        "sp": species_map.get("norway spruce"),
        "oak": species_map.get("pedunculate oak"),
        "fir": species_map.get("silver fir"),
        "sf": species_map.get("silver fir"),
        "larch": species_map.get("european larch"),
        "la": species_map.get("european larch"),
    }

    # Merge aliases into map
    species_map.update({k: v for k, v in species_aliases.items() if v is not None})

    conn.close()
    return species_map


def transform_coordinates(df):
    """Transform UTM coordinates to WGS84 and create Position WKT"""
    print("📍 Transforming coordinates from EPSG:32632 to EPSG:4326...")

    transformer = Transformer.from_crs("EPSG:32632", "EPSG:4326", always_xy=True)

    def transform_row(row):
        if pd.notna(row["x_32632"]) and pd.notna(row["y_32632"]):
            lon, lat = transformer.transform(row["x_32632"], row["y_32632"])
            return f"POINT({lon} {lat})"
        return None

    def original_position(row):
        if pd.notna(row["x_32632"]) and pd.notna(row["y_32632"]):
            return f"POINT({row['x_32632']} {row['y_32632']})"
        return None

    df["Position"] = df.apply(transform_row, axis=1)
    df["PositionOriginal"] = df.apply(original_position, axis=1)
    valid_count = df["Position"].notna().sum()
    print(
        f"✓ Created {valid_count} Position geometries (with original UTM coordinates)"
    )

    return df


def prepare_tree_data(df, species_map):
    """Prepare tree data for insertion"""
    print("\n📊 Preparing tree data...")

    trees = []
    for idx, row in df.iterrows():
        # Map species
        species_id = None
        if pd.notna(row["species"]):
            species_name = str(row["species"]).lower()
            species_id = species_map.get(species_name)
            if not species_id:
                print(
                    f"⚠️  Unknown species '{row['species']}' in row {idx}, skipping species mapping"
                )

        # Create metadata for FieldNotes
        field_notes = {
            "plot_id": int(row["plot_id"]) if pd.notna(row["plot_id"]) else None,
            "tree_id": int(row["tree_id"]) if pd.notna(row["tree_id"]) else None,
            "full_id": str(row["full_id"]) if pd.notna(row["full_id"]) else None,
            "qr_code_id": (
                str(row["qr_code_id"]) if pd.notna(row["qr_code_id"]) else None
            ),
            "elevation": (
                float(row["elevation"]) if pd.notna(row["elevation"]) else None
            ),
            "sensor_tree": (
                bool(row["sensor_tree"]) if pd.notna(row["sensor_tree"]) else False
            ),
        }

        tree = {
            "locationid": LOCATION_ID,
            "varianttypeid": VARIANT_TYPE_ID,
            "speciesid": species_id,
            "datasourcetype": "field",
            "sourcecrs": 32632,  # Original data is UTM 32N (EPSG:32632)
            "height_m": (
                float(row["tls_treeheight"])
                if pd.notna(row["tls_treeheight"])
                else None
            ),
            "position": row["Position"],
            "position_original": row.get("PositionOriginal"),
            "fieldnotes": json.dumps(field_notes),
            "createdby": CREATED_BY,
            "diameter_m": (
                float(row["diameter_m"]) if pd.notna(row["diameter_m"]) else None
            ),  # Store for stems
        }

        trees.append(tree)

    print(f"✓ Prepared {len(trees)} tree records")
    return trees


def insert_trees(trees):
    """Insert trees into database and return variant IDs"""
    print("\n💾 Inserting trees into database...")

    conn = get_db_connection()
    cur = conn.cursor()

    # Prepare INSERT statement
    insert_query = """
        INSERT INTO trees.Trees (LocationID, VariantTypeID, SpeciesID, DataSourceType, SourceCRS, Height_m, Position, PositionOriginal, FieldNotes, CreatedBy)
        VALUES %s
        RETURNING TreeID
    """

    def _clean(val):
        """Convert NaN/None to Python None for psycopg2"""
        if val is None:
            return None
        if isinstance(val, float) and pd.isna(val):
            return None
        return val

    values = [
        (
            tree["locationid"],
            tree["varianttypeid"],
            tree["speciesid"],
            tree["datasourcetype"],
            tree["sourcecrs"],
            tree["height_m"],
            tree["position"],
            tree["position_original"],
            tree["fieldnotes"],
            tree["createdby"],
        )
        for tree in trees
    ]

    # Execute insert and get variant IDs
    variant_ids = execute_values(
        cur,
        insert_query,
        values,
        template="(%s, %s, %s, %s, %s, %s, ST_GeomFromText(%s, 4326), ST_GeomFromText(%s, 32632), %s, %s)",
        fetch=True,
    )

    conn.commit()

    # Store variant IDs back in trees
    for i, (variant_id,) in enumerate(variant_ids):
        trees[i]["variant_id"] = variant_id

    conn.close()
    print(f"✓ Inserted {len(trees)} trees")

    return trees


def insert_stems(trees):
    """Insert stem DBH measurements for trees"""
    print("\n💾 Inserting stem measurements...")

    conn = get_db_connection()
    cur = conn.cursor()

    # Prepare stems data
    stems = []
    for tree in trees:
        if tree["diameter_m"] is not None:
            # Convert meters to centimeters
            dbh_cm = tree["diameter_m"] * 100
            stems.append((tree["variant_id"], 1, dbh_cm))  # stemnumber=1

    if not stems:
        print("⚠️  No diameter measurements to insert")
        conn.close()
        return

    # Insert stems
    insert_query = """
        INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm)
        VALUES %s
    """

    execute_values(cur, insert_query, stems)
    conn.commit()
    conn.close()

    print(f"✓ Inserted {len(stems)} stem measurements")


def main():
    """Main import workflow"""
    print("=" * 80)
    print("ECOSENSE TREE DATA IMPORT")
    print("=" * 80)

    # Check CSV exists
    if not CSV_PATH.exists():
        print(f"❌ CSV file not found: {CSV_PATH}")
        sys.exit(1)

    # Load CSV
    print(f"\n📂 Loading CSV: {CSV_PATH.name}")
    df = pd.read_csv(CSV_PATH)
    print(f"✓ Loaded {len(df)} rows with {len(df.columns)} columns")

    # Load species mapping
    print("\n📚 Loading species reference data...")
    species_map = get_species_mapping()
    print(f"✓ Loaded {len(species_map)} species mappings")

    # Transform coordinates
    df = transform_coordinates(df)

    # Prepare tree data
    trees = prepare_tree_data(df, species_map)

    # Filter out trees without valid Position (required field)
    # Note: pandas converts None to NaN in DataFrames, so check with pd.notna()
    trees_with_position = [t for t in trees if pd.notna(t["position"])]
    trees_without_position = len(trees) - len(trees_with_position)

    if trees_without_position > 0:
        print(f"⚠️  Skipping {trees_without_position} trees without valid coordinates")

    if not trees_with_position:
        print("❌ No trees with valid coordinates to import")
        sys.exit(1)

    # Insert trees
    trees = insert_trees(trees_with_position)

    # Insert stems
    insert_stems(trees)

    print("\n" + "=" * 80)
    print("✅ IMPORT COMPLETE")
    print("=" * 80)
    print(f"Imported {len(trees)} trees from ecosense data")
    print(f"All trees assigned to Location: Ecosense_MixedPlot (ID: {LOCATION_ID})")
    print(
        f"Metadata stored in FieldNotes: plot_id, tree_id, full_id, qr_code_id, elevation, sensor_tree"
    )
    print("\nQuery imported data:")
    print(f"  SELECT * FROM trees.Trees WHERE CreatedBy = '{CREATED_BY}';")
    print(
        f"  SELECT * FROM trees.Stems WHERE TreeID IN (SELECT TreeID FROM trees.Trees WHERE CreatedBy = '{CREATED_BY}');"
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n❌ Import failed: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)
        sys.exit(1)
