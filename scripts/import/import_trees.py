#!/usr/bin/env python3
"""
Unified tree data import for Digital Forest Twin Database

Imports tree data from any CSV file that follows the standard template format
(see data/templates/trees_import_template.csv).

Usage:
    python import_trees.py <csv_file> [--dry-run]

Examples:
    python import_trees.py ../../data/imports/mathisle_trees_import.csv
    python import_trees.py ../../data/imports/ecosense_trees_import.csv
    python import_trees.py /path/to/new_site_import.csv --dry-run
"""

import argparse
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

# Standard template columns (the 23 core columns)
TEMPLATE_COLUMNS = [
    "LocationID",
    "PlotID",
    "TreeNumber",
    "CampaignID",
    "SpeciesID",
    "VariantTypeID",
    "DataSourceType",
    "Latitude",
    "Longitude",
    "SourceCRS",
    "DBH_cm",
    "Height_m",
    "TreeStatusID",
    "CrownWidth_m",
    "CrownBaseHeight_m",
    "Age_years",
    "HealthScore",
    "TaperTypeID",
    "StraightnessTypeID",
    "BranchingPatternID",
    "BarkCharacteristicID",
    "FieldNotes",
    "MeasurementDate",
]

REQUIRED_COLUMNS = ["LocationID", "Latitude", "Longitude"]

# Extra columns that may appear in import CSVs (for provenance) — not inserted directly
EXTRA_COLUMNS = ["Easting_32632", "Northing_32632"]

CREATED_BY = "import_trees"


def get_db_connection():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER_POOLER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )


def validate_csv(df, csv_path):
    """Validate that the CSV matches the expected template format."""
    errors = []
    warnings = []

    # Check required columns exist
    for col in REQUIRED_COLUMNS:
        if col not in df.columns:
            errors.append(f"Missing required column: {col}")

    # Check for unknown columns
    known = set(TEMPLATE_COLUMNS + EXTRA_COLUMNS)
    unknown = set(df.columns) - known
    if unknown:
        warnings.append(f"Extra columns will be ignored: {sorted(unknown)}")

    # Check required data is present
    if "LocationID" in df.columns:
        missing_loc = df["LocationID"].isna().sum()
        if missing_loc > 0:
            errors.append(f"{missing_loc} rows have missing LocationID")

    if "Latitude" in df.columns and "Longitude" in df.columns:
        missing_coords = (df["Latitude"].isna() | df["Longitude"].isna()).sum()
        if missing_coords > 0:
            warnings.append(
                f"{missing_coords} rows with missing coordinates will be skipped"
            )

    # Validate coordinate ranges
    if "Latitude" in df.columns:
        out_of_range = (
            (df["Latitude"].dropna() < -90) | (df["Latitude"].dropna() > 90)
        ).sum()
        if out_of_range > 0:
            errors.append(f"{out_of_range} rows have Latitude outside [-90, 90]")

    if "Longitude" in df.columns:
        out_of_range = (
            (df["Longitude"].dropna() < -180) | (df["Longitude"].dropna() > 180)
        ).sum()
        if out_of_range > 0:
            errors.append(f"{out_of_range} rows have Longitude outside [-180, 180]")

    # Validate DBH range
    if "DBH_cm" in df.columns:
        bad_dbh = (df["DBH_cm"].dropna() <= 0).sum()
        if bad_dbh > 0:
            warnings.append(
                f"{bad_dbh} rows have DBH_cm <= 0 (will be skipped for stems)"
            )

    # Validate HealthScore range
    if "HealthScore" in df.columns:
        bad_health = (
            (df["HealthScore"].dropna() < 0) | (df["HealthScore"].dropna() > 1)
        ).sum()
        if bad_health > 0:
            errors.append(f"{bad_health} rows have HealthScore outside [0, 1]")

    # Validate DataSourceType values
    valid_sources = {"lidar", "field", "photogrammetry", "estimated", "simulated"}
    if "DataSourceType" in df.columns:
        unique_sources = set(df["DataSourceType"].dropna().str.lower().unique())
        invalid = unique_sources - valid_sources
        if invalid:
            errors.append(f"Invalid DataSourceType values: {invalid}")

    return errors, warnings


def validate_foreign_keys(df, conn):
    """Validate that foreign key references exist in the database."""
    cur = conn.cursor()
    warnings = []

    # Check LocationIDs exist
    location_ids = df["LocationID"].dropna().unique()
    if len(location_ids) > 0:
        cur.execute("SELECT LocationID, LocationName FROM shared.Locations")
        valid_locations = {row[0]: row[1] for row in cur.fetchall()}
        invalid_locs = [
            int(lid) for lid in location_ids if int(lid) not in valid_locations
        ]
        if invalid_locs:
            warnings.append(f"LocationIDs not found in database: {invalid_locs}")
            cur.execute("SELECT LocationID, LocationName FROM shared.Locations")
            print("  Available locations:")
            for lid, name in valid_locations.items():
                print(f"    {lid}: {name}")
        else:
            loc_names = [
                f"{int(lid)}={valid_locations[int(lid)]}" for lid in location_ids
            ]
            print(f"  Locations: {', '.join(loc_names)}")

    # Check SpeciesIDs exist
    if "SpeciesID" in df.columns:
        species_ids = df["SpeciesID"].dropna().unique()
        if len(species_ids) > 0:
            cur.execute("SELECT SpeciesID FROM shared.Species")
            valid_species = {row[0] for row in cur.fetchall()}
            invalid_sp = [
                int(sid) for sid in species_ids if int(sid) not in valid_species
            ]
            if invalid_sp:
                warnings.append(f"SpeciesIDs not found in database: {invalid_sp}")

    # Check PlotIDs exist
    if "PlotID" in df.columns:
        plot_ids = df["PlotID"].dropna().unique()
        if len(plot_ids) > 0:
            cur.execute("SELECT PlotID, PlotName FROM shared.Plots")
            valid_plots = {row[0]: row[1] for row in cur.fetchall()}
            invalid_plots = [
                int(pid) for pid in plot_ids if int(pid) not in valid_plots
            ]
            if invalid_plots:
                warnings.append(f"PlotIDs not found in database: {invalid_plots}")
            else:
                plot_names = [f"{int(pid)}={valid_plots[int(pid)]}" for pid in plot_ids]
                print(f"  Plots: {', '.join(plot_names)}")

    return warnings


def build_position_original(row):
    """Build PositionOriginal WKT from extra provenance columns if available."""
    easting = row.get("Easting_32632")
    northing = row.get("Northing_32632")
    if pd.notna(easting) and pd.notna(northing):
        return f"POINT({easting} {northing})"
    return None


def clean(val):
    """Convert NaN/None to Python None for psycopg2."""
    if val is None:
        return None
    if isinstance(val, float) and pd.isna(val):
        return None
    return val


def import_trees(df, dry_run=False):
    """Import tree data from a validated DataFrame."""
    conn = get_db_connection()
    cur = conn.cursor()

    # Check existing trees for these locations
    location_ids = df["LocationID"].dropna().unique()
    for loc_id in location_ids:
        cur.execute(
            "SELECT count(*) FROM trees.trees WHERE locationid = %s", (int(loc_id),)
        )
        existing = cur.fetchone()[0]
        if existing > 0:
            print(
                f"  Note: {existing} trees already exist for LocationID={int(loc_id)}"
            )

    # Build insert values
    has_position_original = (
        "Easting_32632" in df.columns and "Northing_32632" in df.columns
    )

    tree_values = []
    skipped = 0
    for _, row in df.iterrows():
        lat = row.get("Latitude")
        lon = row.get("Longitude")
        if pd.isna(lat) or pd.isna(lon):
            skipped += 1
            continue

        position_wkt = f"POINT({lon} {lat})"
        position_original = (
            build_position_original(row) if has_position_original else None
        )
        source_crs = clean(row.get("SourceCRS"))
        if source_crs is not None:
            source_crs = int(source_crs)

        tree_values.append(
            (
                int(row["LocationID"]),
                int(row["PlotID"]) if pd.notna(row.get("PlotID")) else None,
                int(row["TreeNumber"]) if pd.notna(row.get("TreeNumber")) else None,
                int(row["CampaignID"]) if pd.notna(row.get("CampaignID")) else None,
                int(row["VariantTypeID"]) if pd.notna(row.get("VariantTypeID")) else 1,
                int(row["SpeciesID"]) if pd.notna(row.get("SpeciesID")) else None,
                int(row["TreeStatusID"]) if pd.notna(row.get("TreeStatusID")) else None,
                (
                    int(row["BranchingPatternID"])
                    if pd.notna(row.get("BranchingPatternID"))
                    else None
                ),
                (
                    int(row["BarkCharacteristicID"])
                    if pd.notna(row.get("BarkCharacteristicID"))
                    else None
                ),
                (
                    str(row["MeasurementDate"])
                    if pd.notna(row.get("MeasurementDate"))
                    else None
                ),
                (
                    str(row["DataSourceType"]).lower()
                    if pd.notna(row.get("DataSourceType"))
                    else None
                ),
                float(row["Height_m"]) if pd.notna(row.get("Height_m")) else None,
                (
                    float(row["CrownWidth_m"])
                    if pd.notna(row.get("CrownWidth_m"))
                    else None
                ),
                (
                    float(row["CrownBaseHeight_m"])
                    if pd.notna(row.get("CrownBaseHeight_m"))
                    else None
                ),
                position_wkt,
                position_original,
                source_crs,
                int(row["Age_years"]) if pd.notna(row.get("Age_years")) else None,
                float(row["HealthScore"]) if pd.notna(row.get("HealthScore")) else None,
                str(row["FieldNotes"]) if pd.notna(row.get("FieldNotes")) else None,
                CREATED_BY,
                # Stem data (not inserted into Trees, used after)
                (
                    float(row["DBH_cm"])
                    if pd.notna(row.get("DBH_cm")) and float(row.get("DBH_cm", 0)) > 0
                    else None
                ),
                int(row["TaperTypeID"]) if pd.notna(row.get("TaperTypeID")) else None,
                (
                    int(row["StraightnessTypeID"])
                    if pd.notna(row.get("StraightnessTypeID"))
                    else None
                ),
            )
        )

    if skipped > 0:
        print(f"  Skipped {skipped} rows with missing coordinates")

    print(f"  Prepared {len(tree_values)} trees for import")

    if dry_run:
        print("\n  [DRY RUN] No data inserted.")
        with_dbh = sum(1 for v in tree_values if v[21] is not None)
        print(
            f"  Would insert {len(tree_values)} trees and {with_dbh} stem measurements"
        )
        conn.close()
        return

    # Insert trees
    insert_query = """
        INSERT INTO trees.Trees (
            LocationID, PlotID, TreeNumber, CampaignID, VariantTypeID, SpeciesID,
            TreeStatusID, BranchingPatternID, BarkCharacteristicID,
            MeasurementDate, DataSourceType,
            Height_m, CrownWidth_m, CrownBaseHeight_m,
            Position, PositionOriginal, SourceCRS,
            Age_years, HealthScore, FieldNotes, CreatedBy
        )
        VALUES %s
        RETURNING VariantID
    """

    # Template: 21 tree columns (excluding the 3 stem columns at the end)
    if has_position_original:
        template = (
            "(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, "
            "ST_GeomFromText(%s, 4326), ST_GeomFromText(%s, 32632), "
            "%s, %s, %s, %s, %s)"
        )
    else:
        template = (
            "(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, "
            "ST_GeomFromText(%s, 4326), %s, "
            "%s, %s, %s, %s, %s)"
        )

    # Extract only the tree columns (first 21) for insertion
    tree_only = [v[:21] for v in tree_values]

    variant_ids = execute_values(
        cur,
        insert_query,
        tree_only,
        template=template,
        fetch=True,
    )
    conn.commit()
    print(f"  Inserted {len(variant_ids)} trees")

    # Insert stems for trees with DBH
    stems = []
    for i, (variant_id,) in enumerate(variant_ids):
        dbh_cm = tree_values[i][21]
        taper_type_id = tree_values[i][22]
        straightness_type_id = tree_values[i][23]
        if dbh_cm is not None:
            stems.append((variant_id, 1, dbh_cm, taper_type_id, straightness_type_id))

    if stems:
        stem_query = """
            INSERT INTO trees.Stems (TreeVariantID, StemNumber, DBH_cm, TaperTypeID, StraightnessTypeID)
            VALUES %s
        """
        execute_values(cur, stem_query, stems)
        conn.commit()
        print(f"  Inserted {len(stems)} stem measurements")
    else:
        print("  No DBH measurements to insert")

    conn.close()


def print_summary(df, csv_path):
    """Print a summary of what will be imported."""
    print(f"\n  File: {csv_path.name}")
    print(f"  Rows: {len(df)}")

    locations = df["LocationID"].dropna().unique()
    print(f"  Location IDs: {sorted([int(x) for x in locations])}")

    if "SpeciesID" in df.columns:
        species_count = df["SpeciesID"].notna().sum()
        species_null = df["SpeciesID"].isna().sum()
        print(f"  With species: {species_count}, unknown: {species_null}")

    if "DBH_cm" in df.columns:
        dbh_count = df["DBH_cm"].notna().sum()
        print(f"  With DBH: {dbh_count}")

    if "Height_m" in df.columns:
        height_count = df["Height_m"].notna().sum()
        print(f"  With height: {height_count}")

    if "MeasurementDate" in df.columns:
        dates = df["MeasurementDate"].dropna().unique()
        if len(dates) <= 5:
            print(f"  Measurement dates: {sorted(dates)}")
        else:
            print(f"  Measurement dates: {len(dates)} unique dates")


def main():
    parser = argparse.ArgumentParser(
        description="Import tree data from a template-format CSV into the Digital Forest Twin database.",
        epilog="CSV must follow the standard template format. See data/templates/trees_import_template.csv",
    )
    parser.add_argument("csv_file", help="Path to the CSV file to import")
    parser.add_argument(
        "--dry-run", action="store_true", help="Validate only, do not insert data"
    )
    args = parser.parse_args()

    csv_path = Path(args.csv_file).resolve()

    print("=" * 70)
    print("DIGITAL FOREST TWIN — TREE DATA IMPORT")
    print("=" * 70)

    # Load CSV
    if not csv_path.exists():
        print(f"Error: file not found: {csv_path}")
        sys.exit(1)

    print(f"\nLoading {csv_path.name}...")
    df = pd.read_csv(csv_path, comment="#")

    # Summary
    print_summary(df, csv_path)

    # Validate structure
    print("\nValidating CSV format...")
    errors, warnings = validate_csv(df, csv_path)

    for w in warnings:
        print(f"  Warning: {w}")

    if errors:
        print("\nValidation FAILED:")
        for e in errors:
            print(f"  Error: {e}")
        sys.exit(1)

    print("  CSV format OK")

    # Validate foreign keys against database
    print("\nChecking database references...")
    try:
        conn = get_db_connection()
        fk_warnings = validate_foreign_keys(df, conn)
        conn.close()
        for w in fk_warnings:
            print(f"  Warning: {w}")
        if fk_warnings:
            response = input("\nContinue despite warnings? (y/N): ").strip().lower()
            if response != "y":
                print("Aborted.")
                sys.exit(0)
    except psycopg2.OperationalError as e:
        print(f"  Could not connect to database: {e}")
        if args.dry_run:
            print("  (Skipping FK validation in dry-run mode)")
        else:
            sys.exit(1)

    # Import
    if args.dry_run:
        print("\n[DRY RUN] Validating import...")
    else:
        print("\nImporting trees...")

    import_trees(df, dry_run=args.dry_run)

    # Final verification
    if not args.dry_run:
        conn = get_db_connection()
        cur = conn.cursor()
        location_ids = df["LocationID"].dropna().unique()
        print("\nVerification:")
        for loc_id in location_ids:
            cur.execute(
                "SELECT count(*) FROM trees.trees WHERE locationid = %s", (int(loc_id),)
            )
            total_trees = cur.fetchone()[0]
            cur.execute(
                "SELECT count(*) FROM trees.stems s JOIN trees.trees t ON s.treevariantid = t.variantid WHERE t.locationid = %s",
                (int(loc_id),),
            )
            total_stems = cur.fetchone()[0]
            cur.execute(
                "SELECT locationname FROM shared.locations WHERE locationid = %s",
                (int(loc_id),),
            )
            loc_name = cur.fetchone()
            loc_name = loc_name[0] if loc_name else f"LocationID={int(loc_id)}"
            print(f"  {loc_name}: {total_trees} trees, {total_stems} stems")
        conn.close()

    print("\nDone.")


if __name__ == "__main__":
    main()
