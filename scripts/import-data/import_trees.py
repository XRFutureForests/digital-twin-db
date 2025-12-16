#!/usr/bin/env python3
"""
Digital Forest Twin - Interactive Tree Data Importer
Connects to database, introspects schema, loads CSV, and applies user-defined mapping.
"""

import json
import os
import psycopg2
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd
from dotenv import load_dotenv

try:
    from pyproj import Transformer
    HAS_PYPROJ = True
except ImportError:
    HAS_PYPROJ = False
    print("⚠️  pyproj not installed. Coordinate transformation will be limited.")


class TreeImporter:
    """Interactive importer with database schema introspection."""

    def __init__(self, db_connection_string: str):
        """Initialize with database connection string."""
        self.conn_string = db_connection_string
        self.schema_cache: Dict[str, Any] = {}
        self.reference_data_cache: Dict[str, Dict[str, Any]] = {}

    def connect(self) -> psycopg2.extensions.connection:
        """Establish database connection."""
        try:
            conn = psycopg2.connect(self.conn_string)
            print("✓ Connected to database")
            return conn
        except Exception as e:
            print(f"❌ Database connection failed: {e}")
            raise

    def introspect_database(self) -> Dict[str, Dict[str, List[str]]]:
        """
        Query database to get all tables and columns in custom schemas.
        Returns: {schema_name: {table_name: [column1, column2, ...]}}
        """
        try:
            conn = self.connect()
            cur = conn.cursor()

            schema_info = {}

            # Query all columns from custom schemas
            query = """
            SELECT table_schema, table_name, column_name
            FROM information_schema.columns
            WHERE table_schema IN ('shared', 'trees', 'sensor', 'pointclouds', 'environments')
            ORDER BY table_schema, table_name, ordinal_position
            """

            cur.execute(query)
            rows = cur.fetchall()

            for schema, table, column in rows:
                if schema not in schema_info:
                    schema_info[schema] = {}
                if table not in schema_info[schema]:
                    schema_info[schema][table] = []
                schema_info[schema][table].append(column)

            cur.close()
            conn.close()

            if schema_info:
                print(f"✓ Introspected {sum(len(tables) for tables in schema_info.values())} tables")
                return schema_info
            else:
                print("⚠️  No tables found in custom schemas, using fallback")
                return self._hardcoded_schema()

        except Exception as e:
            print(f"⚠️  Database introspection failed: {e}")
            print("    Using hardcoded schema (may be outdated)")
            return self._hardcoded_schema()

    @staticmethod
    def _hardcoded_schema() -> Dict[str, Dict[str, List[str]]]:
        """Hardcoded schema as final fallback."""
        return {
            "trees": {
                "Trees": [
                    "VariantID", "LocationID", "SpeciesID", "Height_m", "Volume_m3",
                    "Position", "PositionOriginal", "FieldNotes", "CreatedBy", "CreatedAt"
                ],
                "Stems": ["StemID", "TreeID", "StemNumber", "Diameter_m", "CreatedBy"],
            },
            "sensor": {
                "Sensors": [
                    "SensorID", "LocationID", "SensorTypeID", "SerialNumber",
                    "Position", "PositionOriginal", "InstallationDate", "CreatedBy"
                ],
                "SensorReadings": [
                    "ReadingID", "SensorID", "Timestamp", "Value", "Quality", "CreatedAt"
                ],
            },
            "shared": {
                "Species": ["SpeciesID", "CommonName", "ScientificName"],
                "Locations": ["LocationID", "LocationName", "CenterPoint"],
            }
        }

    def load_reference_data(self) -> Dict[str, pd.DataFrame]:
        """
        Load reference lookup tables (Species, Locations, etc.) for user review.
        Returns: {table_name: DataFrame}
        """
        try:
            conn = self.connect()

            # Load reference tables
            reference_tables = {
                "Species": "SELECT SpeciesID, CommonName, ScientificName FROM shared.Species ORDER BY CommonName",
                "Locations": "SELECT LocationID, LocationName FROM shared.Locations ORDER BY LocationName",
                "SensorTypes": "SELECT SensorTypeID, SensorTypeName FROM sensor.SensorTypes ORDER BY SensorTypeName",
            }

            reference_data = {}
            for table_name, query in reference_tables.items():
                try:
                    df = pd.read_sql(query, conn)
                    reference_data[table_name] = df
                except Exception as e:
                    print(f"⚠️  Could not load {table_name}: {e}")

            conn.close()
            return reference_data

        except Exception as e:
            print(f"⚠️  Could not load reference data: {e}")
            return {}

    def display_schema(self, schema_info: Dict[str, Dict[str, List[str]]]):
        """Display available database tables and columns."""
        print("\n" + "=" * 80)
        print("DATABASE SCHEMA - Available Tables & Columns")
        print("=" * 80)

        for schema_name, tables in sorted(schema_info.items()):
            print(f"\n📦 Schema: {schema_name}")
            for table_name, columns in sorted(tables.items()):
                print(f"\n  📋 {table_name} ({len(columns)} columns)")
                for i, col in enumerate(columns, 1):
                    print(f"     {i:2}. {col}")

    def display_reference_data(self, reference_data: Dict[str, pd.DataFrame]):
        """Display reference lookup tables for mapping assistance."""
        print("\n" + "=" * 80)
        print("REFERENCE DATA - Use these for mapping CSV values to database IDs")
        print("=" * 80)

        for table_name, df in reference_data.items():
            if len(df) > 0:
                print(f"\n📚 {table_name}:")
                print(df.to_string(index=False))
            else:
                print(f"\n📚 {table_name}: (empty)")

    def load_csv(self, csv_path: Path) -> pd.DataFrame:
        """Load and display CSV file."""
        df = pd.read_csv(csv_path)
        print(f"\n📄 CSV File: {csv_path.name}")
        print(f"   Rows: {len(df)}")
        print(f"   Columns: {list(df.columns)}")
        print(f"\nFirst 3 rows:")
        print(df.head(3).to_string())
        return df

    def interactive_mapping(
        self, csv_columns: List[str], schema_info: Dict[str, Dict[str, List[str]]]
    ) -> Dict[str, Optional[Dict[str, str]]]:
        """
        Interactive mapping creation.
        Returns: {csv_column: {schema: schema_name, table: table_name, column: column_name} or None}
        """
        mapping = {}

        print("\n" + "=" * 80)
        print("COLUMN MAPPING - Map each CSV column to database table & column")
        print("=" * 80)
        print("Format: schema.table.column (e.g., trees.Trees.Height_m)")
        print("Or: SKIP to ignore this column")
        print("Or: LOOKUP to see reference data for this column")
        print("=" * 80)

        for csv_col in csv_columns:
            while True:
                target = input(f"\n'{csv_col}' maps to: ").strip()

                if target.lower() == "skip":
                    mapping[csv_col] = None
                    break

                if target.lower() == "lookup":
                    # Show sample values from CSV
                    sample_values = df[csv_col].dropna().unique()[:10]
                    print(f"  Sample values from CSV: {', '.join(str(v) for v in sample_values)}")
                    continue

                parts = target.split(".")
                if len(parts) == 3:
                    schema, table, column = parts
                    # Validate
                    if (
                        schema in schema_info
                        and table in schema_info[schema]
                        and column in schema_info[schema][table]
                    ):
                        mapping[csv_col] = {"schema": schema, "table": table, "column": column}
                        print(f"   ✓ Mapped to {schema}.{table}.{column}")
                        break
                    else:
                        print(f"   ❌ Invalid: {schema}.{table}.{column} not found")
                        print(f"   Try one of: {', '.join(list(schema_info.keys())[:3])}.table.column")
                else:
                    print(f"   ❌ Use format: schema.table.column")

        return mapping

    def save_mapping(self, mapping: Dict[str, Any], output_path: Path):
        """Save mapping as JSON for reuse."""
        with open(output_path, "w") as f:
            json.dump(mapping, f, indent=2)
        print(f"\n✓ Mapping saved to {output_path}")

    def load_mapping(self, mapping_path: Path) -> Dict[str, Any]:
        """Load previously saved mapping."""
        with open(mapping_path, "r") as f:
            return json.load(f)

    def apply_mapping(
        self, df: pd.DataFrame, mapping: Dict[str, Any]
    ) -> Dict[str, pd.DataFrame]:
        """
        Apply mapping to create DataFrames per table.
        Returns: {full_table_name: DataFrame}
        """
        table_dfs = {}

        for csv_col, target in mapping.items():
            if target is None:
                continue

            table_key = f"{target['schema']}.{target['table']}"
            column_name = target["column"]

            if table_key not in table_dfs:
                table_dfs[table_key] = pd.DataFrame()

            table_dfs[table_key][column_name] = df[csv_col]

        return table_dfs

    def preview_mapped_data(self, table_dfs: Dict[str, pd.DataFrame]):
        """Preview how data will be inserted."""
        print("\n" + "=" * 80)
        print("DATA PREVIEW - How data will be inserted into each table")
        print("=" * 80)

        for table_name, df in table_dfs.items():
            print(f"\n📊 {table_name} ({len(df)} rows, {len(df.columns)} columns)")
            print(f"   Columns: {', '.join(df.columns)}")
            print(f"\n   First 2 rows:")
            print(f"   {df.head(2).to_string()}")

    def show_coordinate_help(self):
        """Display help for coordinate mapping."""
        print("\n" + "=" * 80)
        print("COORDINATE MAPPING - How to handle spatial data")
        print("=" * 80)
        print("""
Your CSV has coordinates in separate columns (latitude/longitude or x/y).
The database stores them as a single geometry column (Position).

MAPPING STRATEGIES:

1️⃣  COMBINED COLUMN MAPPING (Recommended)
   Format: lat_lon:EPSG_CODE or x_y:EPSG_CODE

   Examples:
   - 'coordinates' maps to: lat_lon:EPSG:4326
     (uses built-in 'latitude' and 'longitude' columns)
   - 'utm_coords' maps to: x_y:EPSG:32632
     (uses built-in 'x' and 'y' columns, transforms to WGS84)

   Benefits: Automatic combination + CRS transformation

   Available column names:
   - Latitude/Longitude: latitude, lat, lat_col, latitude_col, gps_latitude
   - Longitude/Latitude: longitude, lon, lon_col, longitude_col, gps_longitude
   - X/Y (UTM): x, x_col, easting, easting_col, utm_x
   - Y/X (UTM): y, y_col, northing, northing_col, utm_y

2️⃣  MANUAL GEOMETRY STRING
   Map to: shared.Locations.Position (or trees.Trees.Position, etc.)
   Create WKT format before import: POINT(lon lat)

   In mapping JSON:
   "geometry_col": {
     "schema": "trees",
     "table": "Trees",
     "column": "Position",
     "is_geometry": true,
     "format": "wkt"
   }

3️⃣  SEPARATE COORDINATES (Not Recommended)
   ❌ Don't map lat/lon to separate database columns
   ✅ Combine them first using option 1 or 2

CRS SUPPORT:
   - EPSG:4326 (WGS84) - default, no transformation needed
   - EPSG:32632 (UTM Zone 32N) - automatically transforms to WGS84
   - Other EPSG codes - specify in mapping format

   Example: x_y:EPSG:32633 (UTM Zone 33N)

COMMON COORDINATES IN YOUR DATA:
   Mathisle: gps_latitude, gps_longitude (WGS84)
   EcoSense: x_32632, y_32632 (UTM Zone 32N)
""")

    def apply_coordinate_mapping(self, df: pd.DataFrame, mapping: Dict[str, Any]) -> pd.DataFrame:
        """
        Process coordinate columns and create geometry columns.
        Modifies DataFrame in-place to add Position columns.
        """
        if not HAS_PYPROJ:
            print("⚠️  pyproj not available. Coordinate transformation skipped.")
            return df

        for csv_col, target in mapping.items():
            if target is None or not isinstance(target, str):
                continue

            # Check for combined coordinate format: lat_lon:EPSG or x_y:EPSG
            if ":" in target:
                coord_type, crs_code = target.split(":", 1)

                if coord_type == "lat_lon":
                    self._create_latlon_geometry(df, crs_code)

                elif coord_type == "x_y":
                    self._create_xy_geometry(df, crs_code)

        return df

    def _create_latlon_geometry(self, df: pd.DataFrame, crs: str):
        """Create geometry from latitude/longitude columns."""
        # Find lat/lon columns (flexible naming)
        lat_cols = [c for c in df.columns if c.lower() in [
            'latitude', 'lat', 'lat_col', 'latitude_col', 'gps_latitude'
        ]]
        lon_cols = [c for c in df.columns if c.lower() in [
            'longitude', 'lon', 'lon_col', 'longitude_col', 'gps_longitude'
        ]]

        if not lat_cols or not lon_cols:
            print(f"⚠️  Could not find latitude/longitude columns for {crs}")
            return

        lat_col = lat_cols[0]
        lon_col = lon_cols[0]

        print(f"\n📍 Found coordinates: {lat_col} (lat), {lon_col} (lon)")

        # Transform if needed
        if crs.upper() != "EPSG:4326":
            print(f"   Transforming from {crs} to WGS84...")
            transformer = Transformer.from_crs(crs, "EPSG:4326", always_xy=True)

            def transform_coords(row):
                try:
                    lon, lat = transformer.transform(row[lon_col], row[lat_col])
                    return f"POINT({lon} {lat})"
                except:
                    return None

            df["Position"] = df.apply(transform_coords, axis=1)
        else:
            # Already WGS84, just create POINT geometry
            def create_point(row):
                try:
                    return f"POINT({row[lon_col]} {row[lat_col]})"
                except:
                    return None

            df["Position"] = df.apply(create_point, axis=1)

        print(f"   ✓ Created {len(df[df['Position'].notna()])} Position geometries")

    def _create_xy_geometry(self, df: pd.DataFrame, crs: str):
        """Create geometry from x/y coordinates (projected CRS)."""
        # Find x/y columns (flexible naming)
        x_cols = [c for c in df.columns if c.lower() in [
            'x', 'x_col', 'easting', 'easting_col', 'utm_x', 'x_32632'
        ]]
        y_cols = [c for c in df.columns if c.lower() in [
            'y', 'y_col', 'northing', 'northing_col', 'utm_y', 'y_32632'
        ]]

        if not x_cols or not y_cols:
            print(f"⚠️  Could not find x/y columns for {crs}")
            return

        x_col = x_cols[0]
        y_col = y_cols[0]

        print(f"\n📍 Found coordinates: {x_col} (x/easting), {y_col} (y/northing)")
        print(f"   Source CRS: {crs}")

        # Transform to WGS84
        transformer = Transformer.from_crs(crs, "EPSG:4326", always_xy=True)

        def transform_coords(row):
            try:
                lon, lat = transformer.transform(row[x_col], row[y_col])
                return f"POINT({lon} {lat})"
            except:
                return None

        df["Position"] = df.apply(transform_coords, axis=1)
        print(f"   ✓ Transformed to WGS84")
        print(f"   ✓ Created {len(df[df['Position'].notna()])} Position geometries")


def build_connection_string(docker_compose_env: str = "docker/.env") -> str:
    """
    Build PostgreSQL connection string from environment or docker-compose.
    First tries docker-compose local setup, then falls back to SUPABASE_URL.
    """
    # Try local docker-compose setup first (direct PostgreSQL)
    try:
        db_user = os.getenv("POSTGRES_USER", "postgres")
        db_password = os.getenv("POSTGRES_PASSWORD")
        db_host = os.getenv("DB_HOST", "localhost")
        db_port = os.getenv("DB_PORT", "5432")
        db_name = os.getenv("POSTGRES_DB", "postgres")

        if db_password:
            return f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
        else:
            # Try without password (local docker setup)
            return f"postgresql://{db_user}@{db_host}:{db_port}/{db_name}"
    except Exception as e:
        print(f"⚠️  Could not build local connection string: {e}")
        return None


def main():
    """Main workflow."""
    # Load environment
    env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
    load_dotenv(env_path)

    # Build connection string
    conn_string = build_connection_string()

    if not conn_string:
        print("❌ Could not determine database connection parameters")
        print("   Make sure docker/.env contains POSTGRES_PASSWORD or set DB_* environment variables")
        return

    # Initialize importer
    importer = TreeImporter(conn_string)

    # Step 1: Introspect database
    print("\n🔍 Connecting to database and introspecting schema...")
    schema_info = importer.introspect_database()

    # Step 2: Display schema
    importer.display_schema(schema_info)

    # Step 3: Load and display reference data
    print("\n📚 Loading reference data...")
    reference_data = importer.load_reference_data()
    if reference_data:
        importer.display_reference_data(reference_data)

    # Step 4: Load CSV
    csv_path = Path("../../data/mathisle_250904.csv")
    if not csv_path.exists():
        csv_input = input("\nEnter path to CSV file: ").strip()
        csv_path = Path(csv_input)

    if not csv_path.exists():
        print(f"❌ CSV file not found: {csv_path}")
        return

    df = importer.load_csv(csv_path)

    # Step 5: Show coordinate mapping help
    importer.show_coordinate_help()

    # Step 6: Create mapping
    mapping = importer.interactive_mapping(list(df.columns), schema_info)

    # Step 7: Save mapping
    mapping_path = csv_path.parent / f"{csv_path.stem}_mapping.json"
    importer.save_mapping(mapping, mapping_path)

    # Step 8: Apply coordinate mapping if present
    print("\n🔄 Processing coordinate columns...")
    df = importer.apply_coordinate_mapping(df, mapping)

    # Step 9: Apply column mapping and preview
    table_dfs = importer.apply_mapping(df, mapping)
    importer.preview_mapped_data(table_dfs)

    # Step 10: Next steps
    print("\n" + "=" * 80)
    print("Next Steps:")
    print("=" * 80)
    print("1. Review the preview above")
    print("2. Mapping saved to:", mapping_path)
    print("3. Data is ready in DataFrames for insertion")
    print("4. Coordinates:")
    print("   - Position column created from lat/lon or x/y")
    print("   - Transformed to WGS84 if needed")
    print("5. For reference data lookups (Species ID, Location ID, etc.):")
    print("   - Use the reference data displayed above")
    print("   - Map CSV values to database IDs in your mapping")
    print("6. Insert using:")
    print("   for table_name, df in table_dfs.items():")
    print("       importer.supabase.table(table_name).insert(df.to_dict('records')).execute()")
    print("=" * 80)


if __name__ == "__main__":
    main()
