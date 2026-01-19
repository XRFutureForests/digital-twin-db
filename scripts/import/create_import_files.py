#!/usr/bin/env python3
"""
Create properly formatted import files for EcoSense and Mathisle datasets.

This script transforms raw tree inventory CSV data into the standardized
import format required by the Digital Forest Twin database.

Output format follows: data/templates/trees_import_template.csv
"""

from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

# Try to import pyproj for coordinate transformation
try:
    from pyproj import Transformer

    HAS_PYPROJ = True
except ImportError:
    HAS_PYPROJ = False
    print(
        "Warning: pyproj not installed. EcoSense coordinates will need manual conversion."
    )
    print("Install with: pip install pyproj")


# === Configuration ===
BASE_DIR = Path(__file__).parent.parent
DATA_DIR = BASE_DIR / "data"
OUTPUT_DIR = DATA_DIR / "imports"

# Location IDs (from shared.Locations lookup, 1-indexed)
LOCATION_IDS = {"mathisle": 4, "ecosense": 5}

# Species ID mapping (from shared.Species lookup, 1-indexed)
SPECIES_MAP = {
    # Full names from EcoSense
    "beech": 1,
    "european beech": 1,
    "fagus sylvatica": 1,
    "oak": 2,
    "pedunculate oak": 2,
    "quercus robur": 2,
    "norway spruce": 3,
    "spruce": 3,
    "picea abies": 3,
    "silver fir": 4,
    "abies alba": 4,
    "scots pine": 5,
    "pinus sylvestris": 5,
    "douglas fir": 6,
    "pseudotsuga menziesii": 6,
    "european larch": 7,
    "larch": 7,
    "larix decidua": 7,
    "norway maple": 8,
    "acer platanoides": 8,
    # Mathisle short codes
    "be": 1,  # Beech
    "esf": 4,  # European Silver Fir
    "ns": 3,  # Norway Spruce
    "nom": 8,  # Norway Maple
    "ela": 7,  # European Larch
}

# Tree status IDs (from trees.TreeStatus, 1-indexed)
TREE_STATUS_MAP = {
    "healthy": 1,
    "stressed": 2,
    "declining": 3,
    "dead": 4,
    "harvested": 5,
    "missing": 6,
}

# Default values
DEFAULT_STATUS = 1  # healthy
DEFAULT_VARIANT = 1  # BaseState


def get_species_id(species_value: str) -> int:
    """Map species name/code to SpeciesID."""
    if pd.isna(species_value) or species_value == "":
        return None

    species_lower = str(species_value).lower().strip()
    species_id = SPECIES_MAP.get(species_lower)

    if species_id is None:
        print(f"  Warning: Unknown species '{species_value}'")

    return species_id


def transform_utm_to_wgs84(x_coords, y_coords, source_epsg=32632):
    """Transform UTM coordinates to WGS84 (lat/lon)."""
    if not HAS_PYPROJ:
        raise ImportError("pyproj required for coordinate transformation")

    transformer = Transformer.from_crs(
        f"EPSG:{source_epsg}", "EPSG:4326", always_xy=True
    )

    lons = []
    lats = []

    for x, y in zip(x_coords, y_coords):
        if pd.isna(x) or pd.isna(y):
            lons.append(np.nan)
            lats.append(np.nan)
        else:
            lon, lat = transformer.transform(x, y)
            lons.append(lon)
            lats.append(lat)

    return lats, lons


def process_mathisle(input_file: Path) -> pd.DataFrame:
    """Process Mathisle dataset into import format."""
    print(f"\nProcessing Mathisle: {input_file}")

    df = pd.read_csv(input_file)
    print(f"  Input rows: {len(df)}")

    # Create output DataFrame
    output = pd.DataFrame()

    # Required fields
    output["LocationID"] = LOCATION_IDS["mathisle"]
    output["SpeciesID"] = df["species_short"].apply(get_species_id)
    output["VariantTypeID"] = DEFAULT_VARIANT
    output["Latitude"] = pd.to_numeric(df["gps_latitude"], errors="coerce")
    output["Longitude"] = pd.to_numeric(df["gps_longitude"], errors="coerce")

    # Measurements - DBH appears to be in cm already based on values like 21.963
    # But check if values seem too small (likely in meters)
    dbh_values = pd.to_numeric(df["DBH"], errors="coerce")
    if dbh_values.median() < 5:  # If median < 5, likely in meters
        output["DBH_cm"] = (dbh_values * 100).round(2)
        print("  Note: DBH values converted from meters to cm")
    else:
        output["DBH_cm"] = dbh_values.round(2)

    # Height - not available in mathisle data
    output["Height_m"] = np.nan

    # Status - default to healthy
    output["TreeStatusID"] = DEFAULT_STATUS

    # Optional fields (not available)
    output["CrownWidth_m"] = np.nan
    output["CrownBaseHeight_m"] = np.nan
    output["Age_years"] = np.nan
    output["HealthScore"] = np.nan
    output["TaperTypeID"] = np.nan
    output["StraightnessTypeID"] = np.nan
    output["BranchingPatternID"] = np.nan
    output["BarkCharacteristicID"] = np.nan

    # Field notes with original identifiers
    def make_field_note(row):
        parts = []
        if pd.notna(row.get("TreeID")) and row["TreeID"] != "":
            parts.append(
                f"TreeID: {int(row['TreeID']) if isinstance(row['TreeID'], float) else row['TreeID']}"
            )
        elif pd.notna(row.get("tree_id_fallback")) and row["tree_id_fallback"] != "":
            parts.append(f"TreeID: {row['tree_id_fallback']}")
        parts.append("Plot: Mathisle")
        if pd.notna(row.get("species_label")) and row["species_label"] != "":
            parts.append(f"Species: {row['species_label']}")
        if pd.notna(row.get("qr_code")) and row["qr_code"] != "":
            parts.append(f"QR: {row['qr_code']}")
        return " | ".join(parts)

    output["FieldNotes"] = df.apply(make_field_note, axis=1)

    # Measurement date from date_time column
    output["MeasurementDate"] = pd.to_datetime(
        df["date_time"], errors="coerce"
    ).dt.strftime("%Y-%m-%d")

    # Filter out rows with missing required fields
    valid_mask = (
        output["SpeciesID"].notna()
        & output["Latitude"].notna()
        & output["Longitude"].notna()
    )

    invalid_count = (~valid_mask).sum()
    if invalid_count > 0:
        print(f"  Skipping {invalid_count} rows with missing required data")

    output = output[valid_mask].copy()
    output = output.reset_index(drop=True)
    output["SpeciesID"] = output["SpeciesID"].astype(int)
    output["LocationID"] = output["LocationID"].astype(int)

    print(f"  Output rows: {len(output)}")
    return output


def process_ecosense(input_file: Path) -> pd.DataFrame:
    """Process EcoSense dataset into import format."""
    print(f"\nProcessing EcoSense: {input_file}")

    df = pd.read_csv(input_file)
    print(f"  Input rows: {len(df)}")

    # Create output DataFrame
    output = pd.DataFrame()

    # Required fields
    output["LocationID"] = LOCATION_IDS["ecosense"]
    output["SpeciesID"] = df["species"].apply(get_species_id)
    output["VariantTypeID"] = DEFAULT_VARIANT

    # Transform coordinates from UTM (EPSG:32632) to WGS84
    x_coords = pd.to_numeric(df["x_32632"], errors="coerce")
    y_coords = pd.to_numeric(df["y_32632"], errors="coerce")

    if HAS_PYPROJ:
        lats, lons = transform_utm_to_wgs84(x_coords, y_coords)
        output["Latitude"] = lats
        output["Longitude"] = lons
        print("  Coordinates transformed from EPSG:32632 to WGS84")
    else:
        # Store original UTM coords and warn user
        output["Latitude"] = np.nan
        output["Longitude"] = np.nan
        print("  Warning: Could not transform coordinates - pyproj not available")

    # Measurements - diameter_m is in meters, convert to cm
    diameter_m = pd.to_numeric(df["diameter_m"], errors="coerce")
    output["DBH_cm"] = (diameter_m * 100).round(2)

    # Height from TLS measurement
    output["Height_m"] = pd.to_numeric(df["tls_treeheight"], errors="coerce").round(2)

    # Status - default to healthy
    output["TreeStatusID"] = DEFAULT_STATUS

    # Optional fields (not available in source)
    output["CrownWidth_m"] = np.nan
    output["CrownBaseHeight_m"] = np.nan
    output["Age_years"] = np.nan
    output["HealthScore"] = np.nan
    output["TaperTypeID"] = np.nan
    output["StraightnessTypeID"] = np.nan
    output["BranchingPatternID"] = np.nan
    output["BarkCharacteristicID"] = np.nan

    # Field notes with original identifiers
    def make_field_note(row):
        parts = []
        if pd.notna(row.get("full_id")) and row["full_id"] != "":
            parts.append(f"TreeID: {row['full_id']}")
        if pd.notna(row.get("plot_id")):
            parts.append(
                f"Plot: {int(row['plot_id']) if isinstance(row['plot_id'], float) else row['plot_id']}"
            )
        if (
            row.get("sensor_tree") == True
            or str(row.get("sensor_tree")).lower() == "true"
        ):
            parts.append("EcoSense sensor tree")
        if pd.notna(row.get("qr_code_id")) and row["qr_code_id"] != "":
            parts.append(f"QR: {row['qr_code_id']}")
        if pd.notna(row.get("elevation")):
            parts.append(f"Elevation: {row['elevation']}m")
        if pd.notna(row.get("comment")) and row["comment"] != "":
            parts.append(f"Comment: {row['comment']}")
        return " | ".join(parts)

    output["FieldNotes"] = df.apply(make_field_note, axis=1)

    # No measurement date in EcoSense data - use file date from filename or current date
    # Extract date from filename if possible (ecosense_250911.csv -> 2025-09-11)
    filename = input_file.name
    if "_" in filename:
        date_part = filename.split("_")[1].split(".")[0]
        if len(date_part) == 6:
            try:
                year = 2000 + int(date_part[:2])
                month = int(date_part[2:4])
                day = int(date_part[4:6])
                measurement_date = f"{year}-{month:02d}-{day:02d}"
            except ValueError:
                measurement_date = datetime.now().strftime("%Y-%m-%d")
        else:
            measurement_date = datetime.now().strftime("%Y-%m-%d")
    else:
        measurement_date = datetime.now().strftime("%Y-%m-%d")

    output["MeasurementDate"] = measurement_date

    # Filter out rows with missing required fields
    valid_mask = (
        output["SpeciesID"].notna()
        & output["Latitude"].notna()
        & output["Longitude"].notna()
    )

    invalid_count = (~valid_mask).sum()
    if invalid_count > 0:
        print(f"  Skipping {invalid_count} rows with missing required data")

    output = output[valid_mask].copy()
    output = output.reset_index(drop=True)
    output["SpeciesID"] = output["SpeciesID"].astype(int)
    output["LocationID"] = output["LocationID"].astype(int)

    print(f"  Output rows: {len(output)}")
    return output


def write_import_csv(df: pd.DataFrame, output_file: Path, dataset_name: str):
    """Write DataFrame to CSV with header comments matching template format."""

    # Ensure output directory exists
    output_file.parent.mkdir(parents=True, exist_ok=True)

    # Define column order matching template
    columns = [
        "LocationID",
        "SpeciesID",
        "VariantTypeID",
        "Latitude",
        "Longitude",
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

    # Ensure all columns exist
    for col in columns:
        if col not in df.columns:
            df[col] = np.nan

    # Reorder columns
    df = df[columns]

    # Write header comments
    header_lines = [
        f"# DIGITAL FOREST TWIN - {dataset_name.upper()} IMPORT FILE",
        f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"# Source: {dataset_name} raw data",
        f"# Records: {len(df)}",
        "#",
        "# REQUIRED FIELDS: LocationID, SpeciesID, Latitude, Longitude",
        "# All coordinates in WGS84 (EPSG:4326)",
        "#",
    ]

    with open(output_file, "w") as f:
        for line in header_lines:
            f.write(line + "\n")

    # Append data
    df.to_csv(output_file, mode="a", index=False)

    print(f"  Written to: {output_file}")
    return output_file


def main():
    """Main entry point."""
    print("=" * 60)
    print("Digital Forest Twin - Import File Generator")
    print("=" * 60)

    # Input files
    mathisle_file = DATA_DIR / "mathisle_250904.csv"
    ecosense_file = DATA_DIR / "ecosense_250911.csv"

    # Process datasets
    results = {}

    if mathisle_file.exists():
        mathisle_df = process_mathisle(mathisle_file)
        output_file = OUTPUT_DIR / "mathisle_trees_import.csv"
        write_import_csv(mathisle_df, output_file, "Mathisle")
        results["mathisle"] = len(mathisle_df)
    else:
        print(f"\nWarning: Mathisle file not found: {mathisle_file}")

    if ecosense_file.exists():
        ecosense_df = process_ecosense(ecosense_file)
        output_file = OUTPUT_DIR / "ecosense_trees_import.csv"
        write_import_csv(ecosense_df, output_file, "EcoSense")
        results["ecosense"] = len(ecosense_df)
    else:
        print(f"\nWarning: EcoSense file not found: {ecosense_file}")

    # Summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    for dataset, count in results.items():
        print(f"  {dataset}: {count} trees exported")
    print(f"\nOutput files saved to: {OUTPUT_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
