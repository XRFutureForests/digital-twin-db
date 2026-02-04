#!/usr/bin/env python3
"""
Direct Aquarius data sync (bypasses Docker networking).

Use this script when running on the university network and the Docker
edge-functions container cannot reach the Aquarius server.

This script:
1. Connects to Aquarius API directly from the host
2. Fetches sensor data for the specified time period
3. Inserts data via the Supabase REST API at localhost:8000

Requires: University network access for Aquarius connectivity
"""

import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

import requests
from dotenv import load_dotenv

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent.parent
DOCKER_DIR = PROJECT_ROOT / "docker"
ENV_PATH = DOCKER_DIR / ".env"

# Load environment
load_dotenv(ENV_PATH)

SERVICE_ROLE_KEY = os.getenv("SERVICE_ROLE_KEY", "")
SUPABASE_URL = os.getenv("SUPABASE_URL", "http://localhost:8000")
AQUARIUS_HOSTNAME = os.getenv("AQUARIUS_HOSTNAME", "")
AQUARIUS_USERNAME = os.getenv("AQUARIUS_USERNAME", "")
AQUARIUS_PASSWORD = os.getenv("AQUARIUS_PASSWORD", "")

# API configuration
READINGS_BATCH_SIZE = 1000
API_TIMEOUT = 60

# Parameter to SensorType mapping
PARAM_MAPPING = {
    "Sapflow": "Sap_Flow",
    "StemRadialVar_Volt": "Stem_Radial_Variation",
    "BarPressure": "Barometric_Pressure",
    "SoilMoisture": "Soil_Moisture",
    "SoilTemp": "Soil_Temperature",
}

# Aquarius session token (set during connect)
AQUARIUS_TOKEN = None


def supabase_headers() -> dict:
    """Get headers for Supabase REST API requests."""
    return {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def get_aquarius_base_url() -> str:
    """Get the Aquarius API base URL."""
    hostname = AQUARIUS_HOSTNAME.rstrip("/")
    if "/AQUARIUS" in hostname:
        return f"{hostname}/Publish/v2"
    return f"{hostname}/AQUARIUS/Publish/v2"


def aquarius_connect() -> str:
    """Connect to Aquarius and get session token."""
    base_url = get_aquarius_base_url()
    response = requests.post(
        f"{base_url}/session",
        headers={"Content-Type": "application/json"},
        json={
            "Username": AQUARIUS_USERNAME,
            "EncryptedPassword": AQUARIUS_PASSWORD,
        },
        timeout=API_TIMEOUT,
    )
    response.raise_for_status()
    token = response.text.strip().replace('"', "")
    return token


def aquarius_disconnect(token: str) -> None:
    """Disconnect from Aquarius."""
    try:
        base_url = get_aquarius_base_url()
        requests.delete(
            f"{base_url}/session",
            headers={"X-Authentication-Token": token},
            timeout=10,
        )
    except Exception:
        pass


def aquarius_get(endpoint: str, token: str, params: dict | None = None) -> dict:
    """Make a GET request to the Aquarius API."""
    base_url = get_aquarius_base_url()
    url = f"{base_url}/{endpoint}"
    response = requests.get(
        url,
        params=params,
        headers={"X-Authentication-Token": token},
        timeout=API_TIMEOUT,
    )
    response.raise_for_status()
    return response.json()


def get_time_series_descriptions(token: str) -> list:
    """Get all time series descriptions from Aquarius."""
    data = aquarius_get("GetTimeSeriesDescriptionList", token)
    return data.get("TimeSeriesDescriptions", [])


def get_time_series_data(
    token: str, unique_id: str, start_time: datetime, end_time: datetime
) -> list:
    """Get time series data for a specific sensor."""
    # Format dates without milliseconds
    start_str = start_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    end_str = end_time.strftime("%Y-%m-%dT%H:%M:%SZ")

    params = {
        "TimeSeriesUniqueId": unique_id,
        "QueryFrom": start_str,
        "QueryTo": end_str,
    }
    data = aquarius_get("GetTimeSeriesCorrectedData", token, params)
    return data.get("Points", [])


def supabase_get(table: str, select: str = "*", filters: dict | None = None) -> list:
    """Make a GET request to the Supabase REST API."""
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    params = {"select": select}
    if filters:
        params.update(filters)

    response = requests.get(url, headers=supabase_headers(), params=params, timeout=30)
    response.raise_for_status()
    return response.json()


def supabase_rpc(function: str, params: dict) -> dict:
    """Call a Supabase RPC function."""
    url = f"{SUPABASE_URL}/rest/v1/rpc/{function}"
    response = requests.post(url, headers=supabase_headers(), json=params, timeout=120)
    response.raise_for_status()
    return response.json()


def main():
    """Main sync workflow."""
    # Parse arguments
    days_back = 30
    if len(sys.argv) > 1:
        try:
            days_back = int(sys.argv[1])
        except ValueError:
            print(f"Usage: {sys.argv[0]} [days_back]")
            print("  days_back: Number of days to sync (default: 30)")
            sys.exit(1)

    days_back = max(1, min(365, days_back))

    print("=" * 60)
    print("Aquarius Direct Data Sync")
    print("=" * 60)
    print(f"Days back: {days_back}")
    print(f"Aquarius: {AQUARIUS_HOSTNAME}")
    print(f"Supabase: {SUPABASE_URL}")
    print()

    # Connect to Aquarius
    print("Connecting to Aquarius...")
    token = None
    try:
        token = aquarius_connect()
        print("✓ Connected to Aquarius")
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Cannot connect to Aquarius: {e}")
        print("   Make sure you are on the university network")
        sys.exit(1)
    except requests.exceptions.HTTPError as e:
        print(f"❌ Aquarius authentication failed: {e}")
        sys.exit(1)

    try:
        # Fetch time series descriptions
        print("Fetching time series descriptions...")
        descriptions = get_time_series_descriptions(token)
        print(f"✓ Found {len(descriptions)} time series")

        # Check Supabase connectivity
        print("Checking Supabase connectivity...")
        try:
            sensor_types = supabase_get("sensortypes", "sensortypeid,sensortypename")
            print(f"✓ Connected to Supabase ({len(sensor_types)} sensor types)")
        except requests.exceptions.ConnectionError as e:
            print(f"❌ Cannot connect to Supabase: {e}")
            print("   Make sure Docker services are running")
            sys.exit(1)
        except requests.exceptions.HTTPError as e:
            print(f"❌ Supabase API error: {e}")
            sys.exit(1)

        # Filter for Ecosense sensors
        ecosense_ts = [
            ts
            for ts in descriptions
            if ts.get("LocationIdentifier", "").startswith("Ecosense_")
            and ts.get("Parameter") in PARAM_MAPPING
        ]
        print(f"\nFound {len(ecosense_ts)} Ecosense sensors to sync")

        if not ecosense_ts:
            print("No sensors to sync")
            return

        # Build lookup maps
        sensor_type_map = {
            st["sensortypename"]: st["sensortypeid"] for st in sensor_types
        }

        locations = supabase_get("locations", "locationid,locationname")
        location_map = {loc["locationname"]: loc["locationid"] for loc in locations}

        # Prepare sensors for upsert
        print("\nPreparing sensor metadata...")
        sensors_to_upsert = []

        for ts in ecosense_ts:
            mapped_type = PARAM_MAPPING[ts["Parameter"]]
            sensor_type_id = sensor_type_map.get(mapped_type)

            if not sensor_type_id:
                print(f"  ⚠️  Sensor type not found: {mapped_type}")
                continue

            location_id = location_map.get(ts["LocationIdentifier"])

            # Create location if it doesn't exist
            if not location_id:
                try:
                    url = f"{SUPABASE_URL}/rest/v1/locations"
                    new_loc = {
                        "locationname": ts["LocationIdentifier"],
                        "centerpoint": "POINT(0 0)",
                    }
                    response = requests.post(
                        url, headers=supabase_headers(), json=new_loc, timeout=30
                    )
                    response.raise_for_status()
                    result = response.json()
                    if result:
                        location_id = result[0]["locationid"]
                        location_map[ts["LocationIdentifier"]] = location_id
                except Exception as e:
                    print(
                        f"  ⚠️  Failed to create location {ts['LocationIdentifier']}: {e}"
                    )
                    continue

            sensors_to_upsert.append(
                {
                    "locationid": location_id,
                    "sensortypeid": sensor_type_id,
                    "sensormodel": "Ecosense Node",
                    "serialnumber": ts.get("Label", ""),
                    "position": "POINT(0 0)",
                    "samplinginterval_seconds": 900,
                    "unit": ts.get("Unit", ""),
                    "externalid": ts["UniqueId"],
                    "externalmetadata": {
                        "LocationIdentifier": ts["LocationIdentifier"],
                        "Parameter": ts["Parameter"],
                        "Label": ts.get("Label", ""),
                    },
                    "isactive": True,
                    "createdby": "sync_aquarius_direct.py",
                }
            )

        # Upsert sensors
        if sensors_to_upsert:
            print(f"Upserting {len(sensors_to_upsert)} sensors...")
            try:
                result = supabase_rpc(
                    "bulk_upsert_sensors", {"p_sensors": sensors_to_upsert}
                )
                print(
                    f"✓ Upserted {len(result) if isinstance(result, list) else 'N/A'} sensors"
                )
            except Exception as e:
                print(f"⚠️  Sensor upsert error: {e}")

        # Get sensor ID mapping
        print("Fetching sensor mappings...")
        external_ids = [ts["UniqueId"] for ts in ecosense_ts]

        # Fetch in batches to avoid URL length issues
        sensor_id_map = {}
        batch_size = 50
        for i in range(0, len(external_ids), batch_size):
            batch = external_ids[i : i + batch_size]
            filter_str = ",".join(f'"{eid}"' for eid in batch)
            sensors = supabase_get(
                "sensors", "sensorid,externalid", {"externalid": f"in.({filter_str})"}
            )
            for s in sensors:
                sensor_id_map[s["externalid"]] = s["sensorid"]

        print(f"✓ Mapped {len(sensor_id_map)} sensors")

        # Sync readings
        end_time = datetime.now()
        start_time = end_time - timedelta(days=days_back)

        print(f"\nFetching readings from {start_time.date()} to {end_time.date()}...")

        total_points = 0
        errors = []

        for i, ts in enumerate(ecosense_ts, 1):
            sensor_id = sensor_id_map.get(ts["UniqueId"])
            if not sensor_id:
                continue

            try:
                print(
                    f"  [{i}/{len(ecosense_ts)}] {ts['LocationIdentifier']} - {ts['Parameter']}...",
                    end=" ",
                    flush=True,
                )
                points = get_time_series_data(
                    token, ts["UniqueId"], start_time, end_time
                )

                if not points:
                    print("0 points")
                    continue

                # Prepare readings
                readings = [
                    {
                        "sensorid": sensor_id,
                        "timestamp": p["Timestamp"],
                        "value": p["Value"]["Numeric"],
                        "quality": "good",
                    }
                    for p in points
                    if p.get("Value", {}).get("Numeric") is not None
                ]

                if not readings:
                    print("0 valid points")
                    continue

                # Insert in batches
                inserted = 0
                for j in range(0, len(readings), READINGS_BATCH_SIZE):
                    batch = readings[j : j + READINGS_BATCH_SIZE]
                    try:
                        result = supabase_rpc(
                            "bulk_insert_readings", {"readings": batch}
                        )
                        if result and len(result) > 0:
                            inserted += result[0].get("out_inserted_count", 0)
                    except Exception as e:
                        if len(errors) < 10:
                            errors.append(f"Insert error for {ts['UniqueId']}: {e}")

                total_points += inserted
                print(f"{len(readings)} fetched, {inserted} inserted")

            except Exception as e:
                print(f"error: {e}")
                if len(errors) < 10:
                    errors.append(f"Failed to fetch {ts['UniqueId']}: {e}")

        # Summary
        print()
        print("=" * 60)
        print("✅ Sync completed!")
        print(f"   Sensors processed: {len(ecosense_ts)}")
        print(f"   Readings inserted: {total_points}")
        if errors:
            print(f"   Errors: {len(errors)}")
            for err in errors[:5]:
                print(f"     - {err}")
            if len(errors) > 5:
                print(f"     ... and {len(errors) - 5} more")
        print("=" * 60)

    finally:
        # Always disconnect from Aquarius
        if token:
            aquarius_disconnect(token)


if __name__ == "__main__":
    main()
