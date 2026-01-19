#!/usr/bin/env python3
"""
Import Ecosense sensor data from Aquarius API

This script:
1. Fetches sensor metadata from Aquarius API
2. Creates/updates sensors in the database
3. Fetches sensor readings for the last N days
4. Inserts readings into the database
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

import psycopg2
import requests
from dotenv import load_dotenv
from psycopg2.extras import execute_values

# Load environment
env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
load_dotenv(env_path)

# Aquarius configuration
AQUARIUS_HOSTNAME = os.getenv("AQUARIUS_HOSTNAME")
AQUARIUS_USERNAME = os.getenv("AQUARIUS_USERNAME")
AQUARIUS_PASSWORD = os.getenv("AQUARIUS_PASSWORD")

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
DAYS_BACK = 21  # Import last 3 weeks
CREATED_BY = "import_sensor_data_script"

# Parameter to SensorType mapping
PARAM_MAPPING = {
    "Sapflow": "Sap_Flow",
    "StemRadialVar_Volt": "Stem_Radial_Variation",
    "BarPressure": "Barometric_Pressure",
    "SoilMoisture": "Soil_Moisture",
    "SoilTemp": "Soil_Temperature",
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


def create_aquarius_session():
    """Create authenticated session with Aquarius"""
    session = requests.Session()

    # Handle hostname
    if "/AQUARIUS" in AQUARIUS_HOSTNAME:
        base_url = f"{AQUARIUS_HOSTNAME.rstrip('/')}/Publish/v2"
    else:
        base_url = f"{AQUARIUS_HOSTNAME.rstrip('/')}/AQUARIUS/Publish/v2"

    # Authenticate
    auth_url = f"{base_url}/session"
    print(f"Authenticating with Aquarius at: {auth_url}")

    response = session.post(
        auth_url,
        json={
            "Username": AQUARIUS_USERNAME,
            "EncryptedPassword": AQUARIUS_PASSWORD,
        },
        timeout=30,
    )

    if response.status_code != 200:
        print(f"❌ Authentication failed: {response.status_code} - {response.text}")
        return None, None

    token = response.text.strip('\\"')
    session.headers.update({"X-Authentication-Token": token})

    print(f"✓ Authenticated successfully")

    return session, base_url


def fetch_time_series(session, base_url):
    """Fetch time series descriptions from Aquarius"""
    url = f"{base_url}/GetTimeSeriesDescriptionList"

    print(f"Fetching time series from Aquarius...")
    response = session.get(url, timeout=60)

    response.raise_for_status()
    data = response.json()

    descriptions = data.get("TimeSeriesDescriptions", [])
    print(f"✓ Found {len(descriptions)} total time series")

    # Filter for Ecosense sensors with supported parameters
    ecosense_ts = [
        ts
        for ts in descriptions
        if ts.get("LocationIdentifier", "").startswith("Ecosense_")
        and ts.get("Parameter") in PARAM_MAPPING
    ]

    print(f"✓ Found {len(ecosense_ts)} relevant Ecosense sensors")

    return ecosense_ts


def get_sensor_type_map():
    """Load sensor type ID mapping"""
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT SensorTypeID, SensorTypeName FROM sensor.SensorTypes")

    sensor_type_map = {name: id for id, name in cur.fetchall()}

    conn.close()
    return sensor_type_map


def get_location_map():
    """Load location ID mapping"""
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT LocationID, LocationName FROM shared.Locations")

    location_map = {name: id for id, name in cur.fetchall()}

    conn.close()
    return location_map


def upsert_sensors(time_series, sensor_type_map, location_map):
    """Insert or update sensors"""
    print(f"\nUpserting {len(time_series)} sensors...")

    conn = get_db_connection()
    cur = conn.cursor()

    created_count = 0
    updated_count = 0

    for ts in time_series:
        mapped_type = PARAM_MAPPING[ts["Parameter"]]
        sensor_type_id = sensor_type_map.get(mapped_type)

        if not sensor_type_id:
            print(f"⚠️  Sensor type not found: {mapped_type}")
            continue

        location_name = ts["LocationIdentifier"]
        location_id = location_map.get(location_name)

        # Create location if it doesn't exist
        if not location_id:
            cur.execute(
                """
                INSERT INTO shared.Locations (LocationName, CenterPoint)
                VALUES (%s, ST_GeomFromText('POINT(0 0)', 4326))
                RETURNING LocationID
            """,
                (location_name,),
            )

            location_id = cur.fetchone()[0]
            location_map[location_name] = location_id
            conn.commit()

        # Upsert sensor
        cur.execute(
            """
            INSERT INTO sensor.Sensors (
                LocationID, SensorTypeID, SensorModel, SerialNumber,
                Position, SamplingInterval_Seconds, Unit, ExternalID,
                ExternalMetadata, IsActive, CreatedBy
            )
            VALUES (%s, %s, %s, %s, ST_GeomFromText('POINT(0 0)', 4326), %s, %s, %s, %s, %s, %s)
            ON CONFLICT (ExternalID) DO UPDATE SET
                LocationID = EXCLUDED.LocationID,
                SensorTypeID = EXCLUDED.SensorTypeID,
                SensorModel = EXCLUDED.SensorModel,
                SerialNumber = EXCLUDED.SerialNumber,
                SamplingInterval_Seconds = EXCLUDED.SamplingInterval_Seconds,
                Unit = EXCLUDED.Unit,
                ExternalMetadata = EXCLUDED.ExternalMetadata,
                IsActive = EXCLUDED.IsActive,
                UpdatedBy = EXCLUDED.CreatedBy,
                UpdatedAt = NOW()
            RETURNING (xmax = 0) AS inserted
        """,
            (
                location_id,
                sensor_type_id,
                "Ecosense Node",
                ts.get("Label"),
                900,  # 15 minutes
                ts.get("Unit"),
                ts["UniqueId"],
                json.dumps(
                    {
                        "LocationIdentifier": ts["LocationIdentifier"],
                        "Parameter": ts["Parameter"],
                        "Label": ts.get("Label"),
                    }
                ),
                True,
                CREATED_BY,
            ),
        )

        was_inserted = cur.fetchone()[0]
        if was_inserted:
            created_count += 1
        else:
            updated_count += 1

    conn.commit()
    conn.close()

    print(f"✓ Created {created_count} new sensors")
    print(f"✓ Updated {updated_count} existing sensors")


def fetch_sensor_data(session, base_url, time_series, days_back):
    """Fetch sensor readings from Aquarius using authenticated session"""
    print(f"\nFetching sensor readings for last {days_back} days of available data...")

    # Use the actual data end time from sensors (Nov 2024)
    end_time = datetime(2024, 11, 7, 22, 45, 0)
    start_time = end_time - timedelta(days=days_back)

    print(
        f"Date range: {start_time.strftime('%Y-%m-%d')} to {end_time.strftime('%Y-%m-%d')}"
    )

    all_readings = []
    sensor_id_map = {}

    # Get sensor ID mapping from database
    conn = get_db_connection()
    cur = conn.cursor()

    external_ids = [ts["UniqueId"] for ts in time_series]
    cur.execute(
        """
        SELECT SensorID, ExternalID
        FROM sensor.Sensors
        WHERE ExternalID = ANY(%s)
    """,
        (external_ids,),
    )

    sensor_id_map = {ext_id: sensor_id for sensor_id, ext_id in cur.fetchall()}
    conn.close()

    print(f"✓ Found {len(sensor_id_map)} sensors in database")

    # Fetch data for each sensor - KEY: Use GetTimeSeriesCorrectedData endpoint!
    url = f"{base_url}/GetTimeSeriesCorrectedData"

    success_count = 0
    error_count = 0

    for i, ts in enumerate(time_series, 1):
        unique_id = ts["UniqueId"]
        sensor_id = sensor_id_map.get(unique_id)

        if not sensor_id:
            continue

        if i % 50 == 0:
            print(
                f"  Processing sensor {i}/{len(time_series)} (success: {success_count}, errors: {error_count})..."
            )

        try:
            # Format timestamps with milliseconds
            start_str = start_time.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
            end_str = end_time.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

            params = {
                "TimeSeriesUniqueId": unique_id,
                "QueryFrom": start_str,
                "QueryTo": end_str,
            }

            response = session.get(url, params=params, timeout=60)

            if response.status_code != 200:
                error_count += 1
                if error_count <= 5:  # Only show first 5 errors
                    print(
                        f"⚠️  Failed to fetch data for {unique_id}: HTTP {response.status_code}"
                    )
                continue

            data = response.json()
            points = data.get("Points", [])

            if len(points) > 0:
                success_count += 1
                for point in points:
                    value_dict = point.get("Value", {})
                    if "Numeric" in value_dict and value_dict["Numeric"] is not None:
                        all_readings.append(
                            {
                                "sensorid": sensor_id,
                                "timestamp": point["Timestamp"],
                                "value": float(value_dict["Numeric"]),
                                "quality": "good",
                            }
                        )

        except Exception as e:
            error_count += 1
            if error_count <= 5:  # Only show first 5 errors
                print(f"⚠️  Error fetching {unique_id}: {e}")
            continue

    print(
        f"\n✓ Fetch complete: {success_count} sensors with data, {error_count} errors"
    )
    print(f"✓ Fetched {len(all_readings)} total readings")
    return all_readings


def insert_readings(readings):
    """Insert sensor readings into database"""
    if not readings:
        print("⚠️  No readings to insert")
        return 0

    print(f"\nInserting {len(readings)} readings...")

    conn = get_db_connection()
    cur = conn.cursor()

    # Insert in batches
    BATCH_SIZE = 5000
    inserted_count = 0

    for i in range(0, len(readings), BATCH_SIZE):
        batch = readings[i : i + BATCH_SIZE]

        values = [
            (r["sensorid"], r["timestamp"], r["value"], r["quality"]) for r in batch
        ]

        execute_values(
            cur,
            """
            INSERT INTO sensor.SensorReadings (SensorID, Timestamp, Value, Quality)
            VALUES %s
            ON CONFLICT (SensorID, Timestamp) DO NOTHING
            """,
            values,
        )

        inserted_count += cur.rowcount
        conn.commit()

        if (i + BATCH_SIZE) % 10000 == 0:
            print(f"  Inserted {inserted_count} readings so far...")

    conn.close()
    print(f"✓ Inserted {inserted_count} new readings (skipped duplicates)")

    return inserted_count


def main():
    """Main import workflow"""
    print("=" * 80)
    print("ECOSENSE SENSOR DATA IMPORT")
    print("=" * 80)

    # Create authenticated session
    session, base_url = create_aquarius_session()
    if not session:
        print("❌ Failed to authenticate with Aquarius")
        return 1

    try:
        # Fetch time series metadata
        time_series = fetch_time_series(session, base_url)

        if not time_series:
            print("❌ No relevant sensors found")
            return 1

        # Load reference data
        print("\nLoading reference data...")
        sensor_type_map = get_sensor_type_map()
        location_map = get_location_map()
        print(f"✓ Loaded {len(sensor_type_map)} sensor types")
        print(f"✓ Loaded {len(location_map)} locations")

        # Upsert sensors
        upsert_sensors(time_series, sensor_type_map, location_map)

        # Fetch and insert readings
        readings = fetch_sensor_data(session, base_url, time_series, DAYS_BACK)
        inserted_count = insert_readings(readings)

        print("\n" + "=" * 80)
        print("✅ IMPORT COMPLETE")
        print("=" * 80)
        print(f"Processed {len(time_series)} sensors")
        print(f"Inserted {inserted_count} sensor readings from last {DAYS_BACK} days")

        print("\nQuery imported data:")
        print(f"  SELECT * FROM sensor.Sensors WHERE CreatedBy = '{CREATED_BY}';")
        print(
            f"  SELECT COUNT(*) FROM sensor.SensorReadings WHERE SensorID IN (SELECT SensorID FROM sensor.Sensors WHERE CreatedBy = '{CREATED_BY}');"
        )

        return 0

    except Exception as e:
        print(f"\n❌ Import failed: {e}")
        import traceback

        traceback.print_exc()
        return 1
    finally:
        # Disconnect session
        try:
            session.delete(f"{base_url}/session")
            print("Disconnected from Aquarius")
        except:
            pass


if __name__ == "__main__":
    sys.exit(main())
    sys.exit(main())
