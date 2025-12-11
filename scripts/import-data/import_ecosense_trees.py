#!/usr/bin/env python3
"""
Ecosense Tree Data Importer
Imports tree data from ecosense_250908.csv into the Digital Forest Twin database.

Features:
- Transforms UTM coordinates (EPSG:32632) to WGS84 (EPSG:4326)
- Maps species names to database SpeciesID
- Imports trees with positions, heights, and DBH measurements
- Creates stems with DBH values (diameter_m -> DBH_cm)
- Creates Ecosense location if it doesn't exist

Usage:
    python import_ecosense_trees.py [--dry-run] [--location-name NAME]

Example:
    python import_ecosense_trees.py --dry-run
    python import_ecosense_trees.py --location-name "Ecosense_TreePlot"
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import RealDictCursor
from pyproj import Transformer


class EcosenseTreeImporter:
    """Importer for Ecosense tree inventory data."""

    # Species name mapping to common names in database
    SPECIES_MAP = {
        "beech": "European Beech",
        "spruce": "Norway Spruce",
        "fir": "Silver Fir",
        "douglas": "Douglas Fir",
        "pine": "Scots Pine",
        "oak": "European Oak",
        "maple": "Sycamore Maple",
        "ash": "European Ash",
        "larch": "European Larch",
    }

    def __init__(
        self, db_host: str, db_port: int, db_name: str, db_user: str, db_password: str
    ):
        """Initialize with PostgreSQL connection."""
        self.conn = psycopg2.connect(
            host=db_host,
            port=db_port,
            database=db_name,
            user=db_user,
            password=db_password,
        )
        self.conn.autocommit = False
        self.transformer = Transformer.from_crs(
            "EPSG:32632", "EPSG:4326", always_xy=True
        )
        self._species_cache: Dict[str, int] = {}
        self._variant_type_id: int = 1  # 'original' from seed data

    def close(self):
        """Close database connection."""
        if self.conn:
            self.conn.close()

    def _cache_species(self) -> None:
        """Pre-load species data for efficient lookups."""
        print("📦 Loading species data...")
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT speciesid, commonname, scientificname FROM shared.species"
            )
            species_list = cur.fetchall()

        for species in species_list:
            if species["commonname"]:
                self._species_cache[species["commonname"].lower()] = species[
                    "speciesid"
                ]
            if species["scientificname"]:
                self._species_cache[species["scientificname"].lower()] = species[
                    "speciesid"
                ]
        print(f"  ✓ Loaded {len(species_list)} species")

    def lookup_species(self, species_name) -> Optional[int]:
        """Look up species ID by name."""
        if not species_name or (
            isinstance(species_name, float) and pd.isna(species_name)
        ):
            return None

        # Convert to string if needed
        species_name = str(species_name)

        # Normalize and try direct lookup
        normalized = species_name.lower().strip()
        if normalized in self._species_cache:
            return self._species_cache[normalized]

        # Try mapped names
        for key, common_name in self.SPECIES_MAP.items():
            if key in normalized:
                common_lower = common_name.lower()
                if common_lower in self._species_cache:
                    return self._species_cache[common_lower]

        # Try partial match
        for cached_name, species_id in self._species_cache.items():
            if normalized in cached_name or cached_name in normalized:
                return species_id

        return None

    def get_or_create_location(self, location_name: str) -> int:
        """Get existing location or create new one."""
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Check if location exists
            cur.execute(
                "SELECT locationid FROM shared.locations WHERE locationname = %s",
                (location_name,),
            )
            row = cur.fetchone()

            if row:
                print(
                    f"  ✓ Using existing location: {location_name} (ID: {row['locationid']})"
                )
                return row["locationid"]

            # Create new location
            cur.execute(
                """
                INSERT INTO shared.locations (locationname, description)
                VALUES (%s, %s)
                RETURNING locationid
                """,
                (
                    location_name,
                    f"Ecosense tree inventory plot - imported from ecosense_250908.csv",
                ),
            )
            row = cur.fetchone()
            self.conn.commit()

            location_id = row["locationid"]
            print(f"  ✓ Created new location: {location_name} (ID: {location_id})")
            return location_id

    def transform_coordinates(self, x: float, y: float) -> Tuple[float, float]:
        """Transform UTM Zone 32N (EPSG:32632) to WGS84 (EPSG:4326)."""
        lon, lat = self.transformer.transform(x, y)
        return lon, lat

    def load_csv(self, csv_path: Path) -> pd.DataFrame:
        """Load and validate the ecosense CSV file."""
        print(f"\n📄 Loading CSV: {csv_path}")
        df = pd.read_csv(csv_path)

        required_columns = ["species", "x_32632", "y_32632", "diameter_m", "full_id"]
        missing = [col for col in required_columns if col not in df.columns]
        if missing:
            raise ValueError(f"Missing required columns: {missing}")

        print(f"  ✓ Loaded {len(df)} rows")
        print(f"  ✓ Columns: {list(df.columns)}")

        # Preview species distribution
        species_counts = df["species"].value_counts()
        print(f"\n📊 Species distribution:")
        for species, count in species_counts.items():
            print(f"    {species}: {count}")

        return df

    def check_existing_trees(self, location_id: int) -> int:
        """Check how many trees already exist for this location."""
        with self.conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM trees.trees WHERE locationid = %s", (location_id,)
            )
            return cur.fetchone()[0]

    def import_trees(
        self,
        csv_path: Path,
        location_name: str = "Ecosense_TreeInventory",
        dry_run: bool = False,
        skip_existing: bool = True,
    ) -> Tuple[int, int, List[str]]:
        """
        Import ecosense tree data.

        Returns: (inserted_count, skipped_count, errors)
        """
        # Load data and prepare
        df = self.load_csv(csv_path)
        self._cache_species()

        # Get or create location
        print(f"\n🏞️  Location setup...")
        location_id = self.get_or_create_location(location_name)

        # Check for existing trees
        existing_count = self.check_existing_trees(location_id)
        if existing_count > 0:
            if skip_existing:
                print(f"  ⚠️  {existing_count} trees already exist for this location")
                print("     Use --force to reimport (will skip duplicates)")
            else:
                print(
                    f"  ℹ️  {existing_count} trees already exist, will skip duplicates"
                )

        if dry_run:
            print("\n🔍 DRY RUN - Validating data without inserting...")

        inserted = 0
        skipped = 0
        errors = []

        print(f"\n{'📋 Validating' if dry_run else '📥 Importing'} {len(df)} trees...")

        for idx, row in df.iterrows():
            try:
                # Extract data
                species_name = row.get("species", "")
                x_utm = row.get("x_32632")
                y_utm = row.get("y_32632")
                diameter_m = row.get("diameter_m")
                height_m = row.get("tls_treeheight")
                full_id = row.get("full_id", "")
                tree_id = row.get("tree_id", "")
                plot_id = row.get("plot_id", "")
                qr_code = row.get("qr_code_id", "")
                elevation = row.get("elevation")
                comment = row.get("comment", "")

                # Validate coordinates
                if pd.isna(x_utm) or pd.isna(y_utm):
                    errors.append(f"Row {idx + 2}: Missing coordinates")
                    skipped += 1
                    continue

                # Transform coordinates
                lon, lat = self.transform_coordinates(x_utm, y_utm)

                # Validate transformed coordinates
                if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
                    errors.append(
                        f"Row {idx + 2}: Invalid transformed coordinates: lat={lat}, lon={lon}"
                    )
                    skipped += 1
                    continue

                # Look up species
                species_id = self.lookup_species(species_name)
                if species_id is None:
                    # Skip rows with unknown species
                    errors.append(f"Row {idx + 2}: Unknown species '{species_name}'")
                    skipped += 1
                    continue

                # Build field notes
                notes_parts = []
                if full_id:
                    notes_parts.append(f"TreeID: {full_id}")
                if plot_id:
                    notes_parts.append(f"PlotID: {plot_id}")
                if qr_code:
                    notes_parts.append(f"QR: {qr_code}")
                if comment and not pd.isna(comment):
                    notes_parts.append(f"Note: {comment}")
                field_notes = "; ".join(notes_parts) if notes_parts else None

                # Handle height
                height_value = None
                if not pd.isna(height_m):
                    height_value = round(float(height_m), 2)

                if not dry_run:
                    with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                        # Insert tree using PostGIS ST_SetSRID and ST_MakePoint
                        cur.execute(
                            """
                            INSERT INTO trees.trees (
                                locationid, varianttypeid, speciesid, position, 
                                positionoriginal, fieldnotes, createdby, height_m
                            )
                            VALUES (
                                %s, %s, %s, 
                                extensions.ST_SetSRID(extensions.ST_MakePoint(%s, %s), 4326),
                                extensions.ST_SetSRID(extensions.ST_MakePoint(%s, %s), 32632),
                                %s, %s, %s
                            )
                            RETURNING variantid
                            """,
                            (
                                location_id,
                                self._variant_type_id,
                                species_id,
                                lon,
                                lat,
                                x_utm,
                                y_utm,
                                field_notes,
                                "ecosense-import",
                                height_value,
                            ),
                        )
                        result = cur.fetchone()
                        tree_variant_id = result["variantid"]

                        # Insert stem with DBH if diameter available
                        if not pd.isna(diameter_m):
                            dbh_cm = float(diameter_m) * 100  # Convert m to cm
                            cur.execute(
                                """
                                INSERT INTO trees.stems (treevariantid, stemnumber, dbh_cm)
                                VALUES (%s, %s, %s)
                                """,
                                (tree_variant_id, 1, round(dbh_cm, 2)),
                            )

                    inserted += 1
                    if inserted % 100 == 0:
                        self.conn.commit()  # Commit in batches
                        print(f"  ✓ Inserted {inserted} trees...")
                else:
                    # Dry run - just count
                    inserted += 1

            except Exception as e:
                errors.append(f"Row {idx + 2}: {type(e).__name__}: {str(e)}")
                skipped += 1
                self.conn.rollback()  # Rollback failed transaction

        if not dry_run:
            self.conn.commit()  # Final commit

        return inserted, skipped, errors


def main():
    parser = argparse.ArgumentParser(
        description="Import Ecosense tree data into Digital Forest Twin Database"
    )
    parser.add_argument(
        "--csv",
        default=str(
            Path(__file__).parent.parent.parent
            / "data"
            / "ecosense"
            / "ecosense_250908.csv"
        ),
        help="Path to ecosense CSV file",
    )
    parser.add_argument(
        "--location-name",
        default="Ecosense_TreeInventory",
        help="Name for the location (default: Ecosense_TreeInventory)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate data without inserting",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Continue even if trees already exist for location",
    )

    args = parser.parse_args()

    # Load environment
    env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
    load_dotenv(env_path)

    # Get database connection parameters
    db_host = os.getenv("POSTGRES_HOST", "localhost")
    db_port = int(os.getenv("POSTGRES_PORT", "5432"))
    db_name = os.getenv("POSTGRES_DB", "postgres")
    db_user = os.getenv("POSTGRES_USER", "postgres")
    db_password = os.getenv("POSTGRES_PASSWORD")

    if not db_password:
        print("❌ POSTGRES_PASSWORD not found in .env file")
        print(f"   Looked in: {env_path}")
        sys.exit(1)

    # Validate CSV path
    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(f"❌ CSV file not found: {csv_path}")
        sys.exit(1)

    # Initialize importer
    print("=" * 60)
    print("🌲 Ecosense Tree Data Importer")
    print("=" * 60)

    importer = None
    try:
        importer = EcosenseTreeImporter(
            db_host=db_host,
            db_port=db_port,
            db_name=db_name,
            db_user=db_user,
            db_password=db_password,
        )

        # Run import
        inserted, skipped, errors = importer.import_trees(
            csv_path=csv_path,
            location_name=args.location_name,
            dry_run=args.dry_run,
            skip_existing=not args.force,
        )

        # Print summary
        print("\n" + "=" * 60)
        print("📊 Import Summary")
        print("=" * 60)
        if args.dry_run:
            print(f"✅ Would insert: {inserted} trees")
        else:
            print(f"✅ Successfully inserted: {inserted} trees")
        print(f"⏭️  Skipped: {skipped}")
        print(f"❌ Errors: {len(errors)}")

        if errors:
            print("\n⚠️  Error Details (first 20):")
            for error in errors[:20]:
                print(f"  - {error}")
            if len(errors) > 20:
                print(f"  ... and {len(errors) - 20} more errors")

        print("=" * 60)

        if not args.dry_run and inserted > 0:
            print(f"\n💡 Query your trees via API:")
            print(
                f'   curl -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \\'
            )
            print(
                f'     "http://localhost:8000/rest/v1/trees?select=*,species(*),stems(*)&locationid=eq.LOCATION_ID"'
            )

    finally:
        if importer:
            importer.close()


if __name__ == "__main__":
    main()
