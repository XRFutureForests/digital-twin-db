#!/usr/bin/env python3
"""
Digital Forest Twin Database - CSV Importer
Audit-aware tool for importing CSV data with interactive column mapping.
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import pandas as pd
from dotenv import load_dotenv
from pyproj import Transformer

from supabase import Client, create_client


class CSVImporter:
    # Class-level lookup caches to avoid N+1 queries
    _species_cache: Dict[str, Optional[int]] = {}
    _location_cache: Dict[str, Optional[int]] = {}
    _sensor_type_cache: Dict[str, Optional[int]] = {}

    def __init__(self, supabase_url: str, service_role_key: str):
        """Initialize the importer with Supabase client."""
        self.supabase: Client = create_client(supabase_url, service_role_key)
        self._max_csv_size_mb = 100  # Maximum CSV file size

    def preview_csv(self, csv_path: Path, num_rows: int = 5) -> pd.DataFrame:
        """Load and preview the first few rows of a CSV file."""
        try:
            # Check file size
            file_size_mb = csv_path.stat().st_size / (1024 * 1024)
            if file_size_mb > self._max_csv_size_mb:
                print(f"❌ CSV file too large: {file_size_mb:.1f}MB (max: {self._max_csv_size_mb}MB)")
                sys.exit(1)

            df = pd.read_csv(csv_path)
            print(f"\n📄 CSV Preview ({csv_path.name}):")
            print(f"Total rows: {len(df)}")
            print(f"File size: {file_size_mb:.1f}MB")
            print(f"Columns: {list(df.columns)}\n")
            print(df.head(num_rows))
            return df
        except Exception as e:
            print(f"❌ Error loading CSV: {e}")
            sys.exit(1)

    def validate_coordinates(self, lat: float, lon: float) -> bool:
        """Validate latitude and longitude bounds."""
        if not (-90 <= lat <= 90):
            return False
        if not (-180 <= lon <= 180):
            return False
        return True

    def transform_geometry(
        self, x: float, y: float, source_crs: Optional[str] = None
    ) -> Tuple[str, Optional[str]]:
        """
        Transform coordinates to WGS84 and create PostGIS point strings.
        Expects x, y in the order (longitude, latitude) for WGS84 or (easting, northing) for projected CRS.
        Returns: (position_wgs84, position_original)
        """
        if source_crs and source_crs.upper() != "EPSG:4326":
            # For projected coordinates: x=easting, y=northing
            position_original = f"SRID={source_crs.split(':')[1]};POINT({x} {y})"

            # Transform to WGS84
            transformer = Transformer.from_crs(source_crs, "EPSG:4326", always_xy=True)
            lon, lat = transformer.transform(x, y)

            if not self.validate_coordinates(lat, lon):
                raise ValueError(
                    f"Transformed coordinates out of bounds: lat={lat}, lon={lon}"
                )

            position_wgs84 = f"POINT({lon} {lat})"
            return position_wgs84, position_original
        else:
            # Already in WGS84 or no CRS specified: x=lon, y=lat
            if not self.validate_coordinates(y, x):
                raise ValueError(f"Coordinates out of bounds: lat={y}, lon={x}")

            position_wgs84 = f"POINT({x} {y})"
            return position_wgs84, None

    def _cache_lookup_data(self) -> None:
        """Pre-fetch and cache all species, locations, and sensor types to avoid N+1 queries."""
        print("\n📦 Pre-loading reference data...")
        try:
            # Cache species
            species_result = self.supabase.table("Species").select("SpeciesID, CommonName, ScientificName").execute()
            for species in species_result.data:
                key_common = species["CommonName"].lower() if species["CommonName"] else ""
                key_scientific = species["ScientificName"].lower() if species["ScientificName"] else ""
                if key_common:
                    self._species_cache[key_common] = species["SpeciesID"]
                if key_scientific:
                    self._species_cache[key_scientific] = species["SpeciesID"]

            # Cache locations
            location_result = self.supabase.table("Locations").select("LocationID, LocationName").execute()
            for location in location_result.data:
                key = location["LocationName"].lower() if location["LocationName"] else ""
                if key:
                    self._location_cache[key] = location["LocationID"]

            # Cache sensor types
            sensor_result = self.supabase.table("SensorTypes").select("SensorTypeID, SensorTypeName").execute()
            for sensor_type in sensor_result.data:
                key = sensor_type["SensorTypeName"].lower() if sensor_type["SensorTypeName"] else ""
                if key:
                    self._sensor_type_cache[key] = sensor_type["SensorTypeID"]

            print(f"  ✓ Cached {len(self._species_cache)} species names")
            print(f"  ✓ Cached {len(self._location_cache)} locations")
            print(f"  ✓ Cached {len(self._sensor_type_cache)} sensor types")
        except Exception as e:
            print(f"⚠️  Warning: Could not pre-load reference data: {e}")
            print("  Falling back to per-row lookups (slower)")

    def lookup_species(self, species_name: str) -> Optional[int]:
        """Lookup species ID by common or scientific name (cached)."""
        if not species_name:
            return None

        search_key = species_name.lower()

        # Check exact cache match first
        if search_key in self._species_cache:
            return self._species_cache[search_key]

        # Fall back to database lookup if cache is empty
        try:
            result = (
                self.supabase.table("Species")
                .select("SpeciesID")
                .or_(
                    f"CommonName.ilike.%{species_name}%,ScientificName.ilike.%{species_name}%"
                )
                .limit(1)
                .execute()
            )

            if result.data:
                species_id = result.data[0]["SpeciesID"]
                self._species_cache[search_key] = species_id
                return species_id

            self._species_cache[search_key] = None
            return None
        except Exception as e:
            print(f"⚠️  Species lookup error for '{species_name}': {e}")
            return None

    def lookup_location(self, location_name: str) -> Optional[int]:
        """Lookup location ID by name (cached)."""
        if not location_name:
            return None

        search_key = location_name.lower()

        # Check exact cache match first
        if search_key in self._location_cache:
            return self._location_cache[search_key]

        # Fall back to database lookup if cache is empty
        try:
            result = (
                self.supabase.table("Locations")
                .select("LocationID")
                .ilike("LocationName", f"%{location_name}%")
                .limit(1)
                .execute()
            )

            if result.data:
                location_id = result.data[0]["LocationID"]
                self._location_cache[search_key] = location_id
                return location_id

            self._location_cache[search_key] = None
            return None
        except Exception as e:
            print(f"⚠️  Location lookup error for '{location_name}': {e}")
            return None

    def lookup_sensor_type(self, sensor_type_name: str) -> Optional[int]:
        """Lookup sensor type ID by name (cached)."""
        if not sensor_type_name:
            return None

        search_key = sensor_type_name.lower()

        # Check exact cache match first
        if search_key in self._sensor_type_cache:
            return self._sensor_type_cache[search_key]

        # Fall back to database lookup if cache is empty
        try:
            result = (
                self.supabase.table("SensorTypes")
                .select("SensorTypeID")
                .ilike("SensorTypeName", f"%{sensor_type_name}%")
                .limit(1)
                .execute()
            )

            if result.data:
                sensor_type_id = result.data[0]["SensorTypeID"]
                self._sensor_type_cache[search_key] = sensor_type_id
                return sensor_type_id

            self._sensor_type_cache[search_key] = None
            return None
        except Exception as e:
            print(f"⚠️  Sensor type lookup error for '{sensor_type_name}': {e}")
            return None

    def interactive_mapping(self, df: pd.DataFrame, table: str) -> Dict[str, str]:
        """
        Interactive column mapping from CSV to database fields.
        Returns mapping dict: {csv_column: db_field or 'skip' or 'lat' or 'lon'}
        """
        print(f"\n🗺️  Column Mapping for table '{table}'")
        print("=" * 60)
        print("For each CSV column, enter:")
        print("  - Database field name (e.g., 'Height_m', 'SpeciesID')")
        print("  - 'lat' or 'lon' for geometry coordinates")
        print("  - 'skip' to ignore the column")
        print("=" * 60)

        mapping = {}
        for col in df.columns:
            print(f"\nColumn: '{col}'")
            print(f"Sample values: {df[col].head(3).tolist()}")
            target = input("Map to: ").strip()
            mapping[col] = target if target else "skip"

        return mapping

    def prepare_row(
        self,
        row: pd.Series,
        mapping: Dict[str, str],
        table: str,
        created_by: str,
        crs: Optional[str] = None,
        row_number: int = 0,
    ) -> Optional[Dict]:
        """
        Prepare a single row for insertion based on column mapping.
        Returns dict ready for Supabase insert, or None if row should be skipped.
        row_number: Excel-style row number (1-indexed) for error reporting
        """
        data = {"CreatedBy": created_by}
        geometry_data = {}
        critical_fields_missing = []

        try:
            for csv_col, db_field in mapping.items():
                if db_field == "skip":
                    continue

                value = row[csv_col]

                # Handle NaN/NULL values
                if pd.isna(value):
                    continue

                # Collect geometry coordinates
                if db_field in ["lat", "lon", "x", "y"]:
                    try:
                        geometry_data[db_field] = float(value)
                    except (ValueError, TypeError):
                        raise ValueError(f"Invalid coordinate in {csv_col}: {value}")
                    continue

                # Handle lookups
                if db_field == "SpeciesID" and isinstance(value, str):
                    species_id = self.lookup_species(value)
                    if species_id:
                        data[db_field] = species_id
                    else:
                        critical_fields_missing.append(f"Species '{value}' not found")

                elif db_field == "LocationID" and isinstance(value, str):
                    location_id = self.lookup_location(value)
                    if location_id:
                        data[db_field] = location_id
                    else:
                        critical_fields_missing.append(f"Location '{value}' not found")

                elif db_field == "SensorTypeID" and isinstance(value, str):
                    sensor_type_id = self.lookup_sensor_type(value)
                    if sensor_type_id:
                        data[db_field] = sensor_type_id
                    else:
                        critical_fields_missing.append(f"SensorType '{value}' not found")

                else:
                    # Direct mapping - convert to appropriate type
                    data[db_field] = value

            # Skip row if critical lookups failed
            if critical_fields_missing:
                return None

            # Create geometry if lat/lon or x/y provided
            if "lat" in geometry_data and "lon" in geometry_data:
                position_wgs84, position_original = self.transform_geometry(
                    geometry_data["lon"], geometry_data["lat"], crs
                )
                data["Position"] = position_wgs84
                if position_original:
                    data["PositionOriginal"] = position_original

            elif "x" in geometry_data and "y" in geometry_data:
                position_wgs84, position_original = self.transform_geometry(
                    geometry_data["x"], geometry_data["y"], crs
                )
                data["Position"] = position_wgs84
                if position_original:
                    data["PositionOriginal"] = position_original

            return data

        except Exception as e:
            error_msg = f"Row {row_number}: {type(e).__name__}: {str(e)}"
            if critical_fields_missing:
                error_msg += f" ({'; '.join(critical_fields_missing)})"
            return None

    def import_data(
        self,
        csv_path: Path,
        table: str,
        created_by: str,
        crs: Optional[str] = None,
        interactive: bool = True,
        dry_run: bool = False,
    ) -> Tuple[int, int, List[str]]:
        """
        Import CSV data into database table with caching and improved error handling.
        Returns: (inserted_count, skipped_count, errors)
        """
        # Load CSV
        df = self.preview_csv(csv_path)

        # Pre-load reference data to avoid N+1 queries
        self._cache_lookup_data()

        # Get column mapping
        if interactive:
            mapping = self.interactive_mapping(df, table)
        else:
            print("❌ Non-interactive mode not yet supported")
            sys.exit(1)

        print(f"\n📋 Column Mapping Summary:")
        for csv_col, db_field in mapping.items():
            print(f"  {csv_col:30} → {db_field}")

        if dry_run:
            print("\n🔍 DRY RUN MODE - Validating all rows without inserting...")
            # Prepare all rows to validate mappings
            prepared_count = 0
            error_count = 0
            for idx, row in df.iterrows():
                prepared = self.prepare_row(row, mapping, table, created_by, crs, row_number=idx+2)
                if prepared is not None:
                    prepared_count += 1
                else:
                    error_count += 1
            print(f"  ✓ Successfully validated {prepared_count} rows")
            print(f"  ✗ Would skip {error_count} rows")
            return 0, 0, []

        # Confirm before proceeding
        confirm = (
            input(f"\n⚠️  Proceed with import to '{table}'? (yes/no): ").strip().lower()
        )
        if confirm not in ["yes", "y"]:
            print("Import cancelled.")
            sys.exit(0)

        # Process and insert rows
        print(f"\n📥 Importing {len(df)} rows...")
        inserted = 0
        skipped = 0
        errors = []

        for idx, row in df.iterrows():
            try:
                prepared_data = self.prepare_row(row, mapping, table, created_by, crs, row_number=idx+2)

                if prepared_data is None:
                    skipped += 1
                    continue

                # Insert via Supabase
                result = self.supabase.table(table).insert(prepared_data).execute()

                if result.data:
                    inserted += 1
                    if inserted % 10 == 0:
                        print(f"  ✓ Inserted {inserted} rows...")
                else:
                    skipped += 1
                    errors.append(f"Row {idx+2}: Insert returned no data")

            except Exception as e:
                skipped += 1
                errors.append(f"Row {idx+2}: {type(e).__name__}: {str(e)}")

        return inserted, skipped, errors


def main():
    parser = argparse.ArgumentParser(
        description="Import CSV data into Digital Forest Twin Database"
    )
    parser.add_argument("--csv", required=True, help="Path to CSV file")
    parser.add_argument(
        "--table",
        required=True,
        help="Target table (e.g., 'Trees' or 'sensor.Sensors')",
    )
    parser.add_argument(
        "--created-by", required=True, help="User identifier for audit trail"
    )
    parser.add_argument("--crs", help="Source coordinate system (e.g., 'EPSG:32632')")
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Interactive column mapping (prompt for each column)",
    )
    parser.add_argument(
        "--no-interactive",
        dest="interactive",
        action="store_false",
        help="Non-interactive mode (error if mapping needed)",
    )
    parser.set_defaults(interactive=False)
    parser.add_argument(
        "--dry-run", action="store_true", help="Validate without inserting"
    )

    args = parser.parse_args()

    # Load environment
    env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
    load_dotenv(env_path)

    supabase_url = os.getenv("SUPABASE_URL", "http://localhost:8000")
    service_role_key = os.getenv("SERVICE_ROLE_KEY")

    if not service_role_key:
        print("❌ SERVICE_ROLE_KEY not found in .env file")
        sys.exit(1)

    # Initialize importer
    importer = CSVImporter(supabase_url, service_role_key)

    # Run import
    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(f"❌ CSV file not found: {csv_path}")
        sys.exit(1)

    inserted, skipped, errors = importer.import_data(
        csv_path=csv_path,
        table=args.table,
        created_by=args.created_by,
        crs=args.crs,
        interactive=args.interactive,
        dry_run=args.dry_run,
    )

    # Print summary
    print("\n" + "=" * 60)
    print("📊 Import Summary")
    print("=" * 60)
    print(f"✅ Successfully inserted: {inserted}")
    print(f"⏭️  Skipped: {skipped}")
    print(f"❌ Errors: {len(errors)}")

    if errors:
        print("\n⚠️  Error Details:")
        for error in errors[:10]:  # Show first 10 errors
            print(f"  - {error}")
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more errors")
        print("\n💡 Failed rows must be cleaned up manually via Supabase Studio")

    print("=" * 60)


if __name__ == "__main__":
    main()
