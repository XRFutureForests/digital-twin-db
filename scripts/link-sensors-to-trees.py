#!/usr/bin/env python3
"""
Link sensors to trees based on label patterns

This script:
1. Analyzes sensor labels to extract tree identifiers
2. Matches sensors to trees using location and tree_id patterns
3. Creates SensorTreeLinks records in the database

Sensor label pattern: {Species}_{PlotType}_{TreeNumber}_{SensorType}
Example: "Beech_Mixed_10_Dendrometer" → plot=Mixed, tree_id=10
"""

import os
import sys
import json
import re
from pathlib import Path
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

# Load environment
env_path = Path(__file__).parent.parent / "docker" / ".env"
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

CREATED_BY = "link_sensors_trees_script"

# Location name to plot type mapping
LOCATION_PLOT_MAP = {
    'Ecosense_MixedPlot': 'Mixed',
    'Ecosense_BeechPlot': 'Beech',
    'Ecosense_MeteoStation': 'Meteo',
}

def get_db_connection():
    """Create database connection"""
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER_POOLER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )

def extract_tree_identifier(label, location_name):
    """
    Extract tree identifier from sensor label

    Pattern: {Species}_{PlotType}_{TreeNumber}_{SensorType}
    Example: "Beech_Mixed_10_Dendrometer" → ("Mixed", "10")
    """
    # Get expected plot type from location
    expected_plot = LOCATION_PLOT_MAP.get(location_name)

    # Pattern to extract tree number after plot type
    # Look for: {PlotType}_{Number}
    if expected_plot:
        pattern = rf'{expected_plot}_(\d+)'
        match = re.search(pattern, label)
        if match:
            tree_num = match.group(1)
            return expected_plot, tree_num

    # Fallback: try to find any pattern with plot type and number
    for plot_type in ['Mixed', 'Beech', 'Meteo']:
        pattern = rf'{plot_type}_(\d+)'
        match = re.search(pattern, label)
        if match:
            tree_num = match.group(1)
            return plot_type, tree_num

    return None, None

def get_sensors_with_locations():
    """Fetch sensors with their location information"""
    print("\n📡 Fetching sensors with locations...")

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT
            s.SensorID,
            s.SerialNumber as Label,
            l.LocationName,
            l.LocationID
        FROM sensor.Sensors s
        JOIN shared.Locations l ON s.LocationID = l.LocationID
        WHERE s.CreatedBy = 'import_sensor_data_script'
        AND l.LocationName LIKE 'Ecosense_%'
    """)

    sensors = []
    for row in cur.fetchall():
        sensor_id, label, location_name, location_id = row
        sensors.append({
            'sensor_id': sensor_id,
            'label': label,
            'location_name': location_name,
            'location_id': location_id,
        })

    conn.close()

    print(f"✓ Found {len(sensors)} Ecosense sensors")
    return sensors

def get_trees_with_metadata():
    """Fetch trees with FieldNotes metadata"""
    print("🌲 Fetching trees with metadata...")

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT
            t.VariantID,
            t.LocationID,
            l.LocationName,
            t.FieldNotes
        FROM trees.Trees t
        JOIN shared.Locations l ON t.LocationID = l.LocationID
        WHERE t.CreatedBy = 'import_ecosense_script'
        AND t.FieldNotes IS NOT NULL
    """)

    trees = []
    for row in cur.fetchall():
        variant_id, location_id, location_name, field_notes_json = row

        # Parse FieldNotes JSON
        try:
            field_notes = json.loads(field_notes_json)
        except:
            continue

        tree_id = field_notes.get('tree_id')
        sensor_tree = field_notes.get('sensor_tree', False)

        if tree_id is not None:
            trees.append({
                'variant_id': variant_id,
                'location_id': location_id,
                'location_name': location_name,
                'tree_id': str(tree_id),
                'sensor_tree': sensor_tree,
                'plot_id': field_notes.get('plot_id'),
            })

    conn.close()

    print(f"✓ Found {len(trees)} trees with metadata")
    sensor_trees = sum(1 for t in trees if t['sensor_tree'])
    print(f"✓ {sensor_trees} trees flagged as sensor_tree: true")

    return trees

def create_sensor_tree_links(sensors, trees):
    """Match sensors to trees and create links"""
    print("\n🔗 Creating sensor-tree links...")

    # Index trees by location and tree_id for fast lookup
    tree_index = {}
    for tree in trees:
        key = (tree['location_name'], tree['tree_id'])
        tree_index[key] = tree

    links = []
    matched_count = 0
    unmatched_sensors = []

    for sensor in sensors:
        # Extract tree identifier from sensor label
        plot_type, tree_num = extract_tree_identifier(
            sensor['label'],
            sensor['location_name']
        )

        if not plot_type or not tree_num:
            unmatched_sensors.append({
                'label': sensor['label'],
                'reason': 'Could not extract tree number from label'
            })
            continue

        # Look up tree by location and tree_id
        tree = tree_index.get((sensor['location_name'], tree_num))

        if tree:
            links.append({
                'sensor_id': sensor['sensor_id'],
                'tree_variant_id': tree['variant_id'],
                'sensor_label': sensor['label'],
                'tree_id': tree_num,
                'location': sensor['location_name'],
            })
            matched_count += 1
        else:
            unmatched_sensors.append({
                'label': sensor['label'],
                'location': sensor['location_name'],
                'extracted_tree_id': tree_num,
                'reason': f'No tree found with tree_id={tree_num} at {sensor["location_name"]}'
            })

    print(f"✓ Matched {matched_count} sensors to trees")
    print(f"⚠️  {len(unmatched_sensors)} sensors could not be matched")

    # Show sample of unmatched sensors
    if unmatched_sensors and len(unmatched_sensors) <= 10:
        print("\nUnmatched sensors:")
        for item in unmatched_sensors[:10]:
            print(f"  {item['label']}: {item['reason']}")

    return links

def insert_links(links):
    """Insert sensor-tree links into database"""
    if not links:
        print("\n⚠️  No links to insert")
        return 0

    print(f"\n💾 Inserting {len(links)} sensor-tree links...")

    conn = get_db_connection()
    cur = conn.cursor()

    # Prepare values for insertion
    values = [
        (link['sensor_id'], link['tree_variant_id'], CREATED_BY)
        for link in links
    ]

    # Insert with conflict handling
    execute_values(
        cur,
        """
        INSERT INTO sensor.SensorTreeLinks (SensorID, TreeVariantID, Description)
        VALUES %s
        ON CONFLICT (SensorID, TreeVariantID) DO NOTHING
        """,
        values
    )

    inserted_count = cur.rowcount
    conn.commit()
    conn.close()

    print(f"✓ Inserted {inserted_count} new links (skipped duplicates)")

    return inserted_count

def verify_links():
    """Show summary of created links"""
    print("\n📊 Verifying links...")

    conn = get_db_connection()
    cur = conn.cursor()

    # Count links by location
    cur.execute("""
        SELECT
            l.LocationName,
            COUNT(*) as link_count
        FROM sensor.SensorTreeLinks stl
        JOIN sensor.Sensors s ON stl.SensorID = s.SensorID
        JOIN shared.Locations l ON s.LocationID = l.LocationID
        WHERE stl.Description = %s
        GROUP BY l.LocationName
        ORDER BY link_count DESC
    """, (CREATED_BY,))

    print("\nLinks by location:")
    for location_name, count in cur.fetchall():
        print(f"  {location_name}: {count} links")

    # Count unique trees with sensors
    cur.execute("""
        SELECT COUNT(DISTINCT TreeVariantID)
        FROM sensor.SensorTreeLinks
        WHERE Description = %s
    """, (CREATED_BY,))

    tree_count = cur.fetchone()[0]
    print(f"\n✓ {tree_count} trees linked to sensors")

    conn.close()

def main():
    """Main workflow"""
    print("=" * 80)
    print("SENSOR-TREE LINKING")
    print("=" * 80)

    try:
        # Fetch data
        sensors = get_sensors_with_locations()
        trees = get_trees_with_metadata()

        if not sensors:
            print("❌ No sensors found")
            return 1

        if not trees:
            print("❌ No trees found")
            return 1

        # Create links
        links = create_sensor_tree_links(sensors, trees)

        # Insert into database
        inserted_count = insert_links(links)

        # Verify results
        if inserted_count > 0:
            verify_links()

        print("\n" + "=" * 80)
        print("✅ LINKING COMPLETE")
        print("=" * 80)
        print(f"Created {inserted_count} sensor-tree links")
        print("\nQuery linked data:")
        print(f"  SELECT * FROM sensor.SensorTreeLinks WHERE Description = '{CREATED_BY}';")
        print("""
  SELECT s.SerialNumber as SensorLabel, t.VariantID, t.FieldNotes->>'tree_id' as TreeID
  FROM sensor.SensorTreeLinks stl
  JOIN sensor.Sensors s ON stl.SensorID = s.SensorID
  JOIN trees.Trees t ON stl.TreeVariantID = t.VariantID
  WHERE stl.Description = '""" + CREATED_BY + "';"
        )

        return 0

    except Exception as e:
        print(f"\n❌ Linking failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
