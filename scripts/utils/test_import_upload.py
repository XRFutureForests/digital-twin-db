#!/usr/bin/env python3
"""
Test upload of generated import CSV files to the Digital Forest Twin database.

This script validates the import files and performs a test upload
(with optional dry-run mode).
"""

import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import execute_values

# Configuration
BASE_DIR = Path(__file__).parent.parent
IMPORT_DIR = BASE_DIR / "data" / "imports"
ENV_PATH = BASE_DIR / "docker" / ".env"

# Import files to test
IMPORT_FILES = [
    IMPORT_DIR / "mathisle_trees_import.csv",
    IMPORT_DIR / "ecosense_trees_import.csv",
]

# Set to False to actually insert data
DRY_RUN = True

# Tag for audit trail
CREATED_BY = "import_test_script"


def load_environment():
    """Load database connection settings from docker/.env"""
    if not ENV_PATH.exists():
        print(f"❌ Environment file not found: {ENV_PATH}")
        sys.exit(1)

    load_dotenv(ENV_PATH)

    config = {
        "host": "localhost",
        "user": os.getenv("POSTGRES_USER", "postgres"),
        "password": os.getenv("POSTGRES_PASSWORD"),
        "database": os.getenv("POSTGRES_DB", "postgres"),
        "port": os.getenv("POSTGRES_PORT", "5432"),
    }

    # Handle pooler tenant ID if set
    pooler_tenant = os.getenv("POOLER_TENANT_ID", "")
    if pooler_tenant:
        config["user"] = f"{config['user']}.{pooler_tenant}"

    if not config["password"]:
        print("❌ POSTGRES_PASSWORD not found in docker/.env")
        sys.exit(1)

    return config


def get_connection(config):
    """Create database connection."""
    return psycopg2.connect(
        host=config["host"],
        user=config["user"],
        password=config["password"],
        database=config["database"],
        port=config["port"],
    )


def load_import_csv(file_path: Path) -> pd.DataFrame:
    """Load import CSV, skipping comment lines."""
    # Read file and skip comment lines
    with open(file_path, "r") as f:
        lines = f.readlines()

    # Find first non-comment line (header)
    header_idx = 0
    for i, line in enumerate(lines):
        if not line.startswith("#"):
            header_idx = i
            break

    # Read from header line onwards
    df = pd.read_csv(file_path, skiprows=header_idx)
    return df


def validate_csv(df: pd.DataFrame, conn) -> dict:
    """Validate CSV data against database constraints."""
    results = {"valid": True, "errors": [], "warnings": [], "stats": {}}

    # Required columns
    required = ["LocationID", "SpeciesID", "Latitude", "Longitude"]
    missing = [col for col in required if col not in df.columns]
    if missing:
        results["valid"] = False
        results["errors"].append(f"Missing required columns: {missing}")
        return results

    # Check for nulls in required columns
    for col in required:
        null_count = df[col].isna().sum()
        if null_count > 0:
            results["valid"] = False
            results["errors"].append(f"{col}: {null_count} NULL values")

    # Validate LocationIDs
    db_locations = pd.read_sql(
        "SELECT locationid, locationname FROM shared.Locations", conn
    )
    csv_locations = df["LocationID"].dropna().unique()
    invalid_locs = [
        loc for loc in csv_locations if loc not in db_locations["locationid"].values
    ]
    if invalid_locs:
        results["valid"] = False
        results["errors"].append(f"Invalid LocationIDs: {invalid_locs}")

    # Validate SpeciesIDs
    db_species = pd.read_sql("SELECT speciesid, commonname FROM shared.Species", conn)
    csv_species = df["SpeciesID"].dropna().unique()
    invalid_species = [
        sp for sp in csv_species if sp not in db_species["speciesid"].values
    ]
    if invalid_species:
        results["valid"] = False
        results["errors"].append(f"Invalid SpeciesIDs: {invalid_species}")

    # Validate TreeStatusIDs if present
    if "TreeStatusID" in df.columns:
        db_status = pd.read_sql("SELECT treestatusid FROM trees.TreeStatus", conn)
        csv_status = df["TreeStatusID"].dropna().unique()
        invalid_status = [
            st for st in csv_status if st not in db_status["treestatusid"].values
        ]
        if invalid_status:
            results["valid"] = False
            results["errors"].append(f"Invalid TreeStatusIDs: {invalid_status}")

    # Stats
    results["stats"] = {
        "total_rows": len(df),
        "unique_locations": len(csv_locations),
        "unique_species": len(csv_species),
        "has_dbh": df["DBH_cm"].notna().sum() if "DBH_cm" in df.columns else 0,
        "has_height": df["Height_m"].notna().sum() if "Height_m" in df.columns else 0,
    }

    return results


def test_insert(df: pd.DataFrame, conn, dry_run: bool = True) -> dict:
    """Test inserting data into database."""
    results = {"trees_inserted": 0, "stems_inserted": 0, "errors": []}

    cur = conn.cursor()

    try:
        # Prepare tree data
        tree_records = []
        for _, row in df.iterrows():
            # Build position WKT
            lat = row.get("Latitude")
            lon = row.get("Longitude")
            if pd.isna(lat) or pd.isna(lon):
                continue

            position = f"POINT({lon} {lat})"

            record = {
                "LocationID": int(row["LocationID"]),
                "SpeciesID": int(row["SpeciesID"]),
                "VariantTypeID": int(row.get("VariantTypeID", 1)),
                "Position": position,
                "Height_m": (
                    row.get("Height_m") if pd.notna(row.get("Height_m")) else None
                ),
                "TreeStatusID": (
                    int(row.get("TreeStatusID", 1))
                    if pd.notna(row.get("TreeStatusID"))
                    else 1
                ),
                "FieldNotes": (
                    row.get("FieldNotes") if pd.notna(row.get("FieldNotes")) else None
                ),
                "CreatedBy": CREATED_BY,
                "DBH_cm": row.get("DBH_cm") if pd.notna(row.get("DBH_cm")) else None,
            }
            tree_records.append(record)

        if not tree_records:
            results["errors"].append("No valid records to insert")
            return results

        # Insert trees
        insert_query = """
            INSERT INTO trees.Trees (
                LocationID, SpeciesID, VariantTypeID, Position, Height_m, 
                TreeStatusID, FieldNotes, CreatedBy
            )
            VALUES %s
            RETURNING TreeID
        """

        tree_values = [
            (
                r["LocationID"],
                r["SpeciesID"],
                r["VariantTypeID"],
                r["Position"],
                r["Height_m"],
                r["TreeStatusID"],
                r["FieldNotes"],
                r["CreatedBy"],
            )
            for r in tree_records
        ]

        if dry_run:
            # Just validate SQL without executing
            print(f"    [DRY RUN] Would insert {len(tree_values)} trees")
            results["trees_inserted"] = len(tree_values)

            # Count stems
            stems_count = sum(1 for r in tree_records if r["DBH_cm"] is not None)
            print(f"    [DRY RUN] Would insert {stems_count} stems")
            results["stems_inserted"] = stems_count
        else:
            # Actually insert
            tree_ids = execute_values(cur, insert_query, tree_values, fetch=True)
            results["trees_inserted"] = len(tree_ids)

            # Insert stems for trees with DBH
            stem_values = []
            for i, (tree_id_row, record) in enumerate(zip(tree_ids, tree_records)):
                if record["DBH_cm"] is not None:
                    stem_values.append((tree_id_row[0], 1, record["DBH_cm"]))

            if stem_values:
                stem_query = """
                    INSERT INTO trees.Stems (TreeID, StemNumber, DBH_cm)
                    VALUES %s
                """
                execute_values(cur, stem_query, stem_values)
                results["stems_inserted"] = len(stem_values)

            conn.commit()
            print(
                f"    ✓ Inserted {results['trees_inserted']} trees, {results['stems_inserted']} stems"
            )

    except Exception as e:
        conn.rollback()
        results["errors"].append(str(e))
        print(f"    ❌ Error: {e}")

    return results


def main():
    """Main test workflow."""
    print("=" * 70)
    print("Digital Forest Twin - Import Upload Test")
    print("=" * 70)
    print(
        f"Mode: {'DRY RUN (no changes)' if DRY_RUN else '⚠️  LIVE MODE - will insert data!'}"
    )
    print()

    # Load environment
    config = load_environment()
    print(f"✓ Database: {config['user']}@{config['host']}:{config['port']}")

    # Test connection
    try:
        conn = get_connection(config)
        print("✓ Database connection successful\n")
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        print("\nTroubleshooting:")
        print(
            "  1. Ensure Docker containers are running: cd docker && docker compose up -d"
        )
        print("  2. Check docker/.env has correct POSTGRES_PASSWORD")
        sys.exit(1)

    # Process each import file
    all_results = {}

    for file_path in IMPORT_FILES:
        print("-" * 70)
        print(f"📂 Testing: {file_path.name}")
        print("-" * 70)

        if not file_path.exists():
            print(f"  ⚠️  File not found: {file_path}")
            continue

        # Load CSV
        df = load_import_csv(file_path)
        print(f"  ✓ Loaded {len(df)} rows")

        # Validate
        print("\n  📋 Validation:")
        validation = validate_csv(df, conn)

        for error in validation["errors"]:
            print(f"    ❌ {error}")
        for warning in validation["warnings"]:
            print(f"    ⚠️  {warning}")

        if validation["valid"]:
            print("    ✓ All validations passed")

            # Show stats
            stats = validation["stats"]
            print(f"\n  📊 Stats:")
            print(f"    - Rows: {stats['total_rows']}")
            print(f"    - Locations: {stats['unique_locations']}")
            print(f"    - Species: {stats['unique_species']}")
            print(f"    - With DBH: {stats['has_dbh']}")
            print(f"    - With Height: {stats['has_height']}")

            # Test insert
            print(f"\n  🔄 Insert test:")
            insert_results = test_insert(df, conn, dry_run=DRY_RUN)
            all_results[file_path.name] = insert_results
        else:
            print("    ❌ Validation failed - skipping insert test")
            all_results[file_path.name] = {"error": "Validation failed"}

    conn.close()

    # Summary
    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)
    for filename, result in all_results.items():
        if "error" in result:
            print(f"  ❌ {filename}: {result['error']}")
        else:
            print(
                f"  ✓ {filename}: {result['trees_inserted']} trees, {result['stems_inserted']} stems"
            )

    if DRY_RUN:
        print("\n💡 To actually insert data, set DRY_RUN = False in this script")

    print("=" * 70)


if __name__ == "__main__":
    main()
