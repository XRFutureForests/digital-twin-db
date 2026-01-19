#!/usr/bin/env python3
"""
Find Ecosense sensors that have recent data
"""

import json
import os
from datetime import datetime, timedelta
from pathlib import Path

import requests
from dotenv import load_dotenv
from requests.auth import HTTPBasicAuth

# Load environment
env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
load_dotenv(env_path)

AQUARIUS_HOSTNAME = os.getenv("AQUARIUS_HOSTNAME")
AQUARIUS_USERNAME = os.getenv("AQUARIUS_USERNAME")
AQUARIUS_PASSWORD = os.getenv("AQUARIUS_PASSWORD")

# Parameter mapping
PARAM_MAPPING = {
    "Sapflow": "Sap_Flow",
    "StemRadialVar_Volt": "Stem_Radial_Variation",
    "BarPressure": "Barometric_Pressure",
    "SoilMoisture": "Soil_Moisture",
    "SoilTemp": "Soil_Temperature",
}

print("=" * 80)
print("FINDING ACTIVE ECOSENSE SENSORS")
print("=" * 80)

# Get time series descriptions
url = f"{AQUARIUS_HOSTNAME}Publish/v2/GetTimeSeriesDescriptionList"
response = requests.get(
    url, auth=HTTPBasicAuth(AQUARIUS_USERNAME, AQUARIUS_PASSWORD), timeout=60
)

data = response.json()
descriptions = data.get("TimeSeriesDescriptions", [])

# Filter for Ecosense sensors with supported parameters
ecosense_ts = [
    ts
    for ts in descriptions
    if ts.get("LocationIdentifier", "").startswith("Ecosense_")
    and ts.get("Parameter") in PARAM_MAPPING
]

print(f"\nFound {len(ecosense_ts)} Ecosense sensors with supported parameters")

# Check which ones have data coverage information
print("\nAnalyzing sensor data coverage...")

sensors_with_coverage = []

for i, ts in enumerate(ecosense_ts[:20], 1):  # Test first 20
    # Check if has coverage information
    if "TimeRange" in ts and ts["TimeRange"]:
        time_range = ts["TimeRange"]
        start = time_range.get("StartTime")
        end = time_range.get("EndTime")

        if start and end:
            print(f"\n{i}. {ts['LocationIdentifier']} - {ts['Parameter']}")
            print(f"   Label: {ts.get('Label')}")
            print(f"   Data range: {start} to {end}")
            print(f"   UniqueId: {ts['UniqueId']}")

            # Check if end time is recent (within last 30 days)
            try:
                end_dt = datetime.fromisoformat(end.replace("Z", "+00:00"))
                now = datetime.now(end_dt.tzinfo)
                days_ago = (now - end_dt).days
                print(f"   Last data: {days_ago} days ago")

                if days_ago < 30:
                    sensors_with_coverage.append({"ts": ts, "days_ago": days_ago})
            except:
                pass

print(f"\n" + "=" * 80)
print(f"Found {len(sensors_with_coverage)} sensors with data in last 30 days")

if sensors_with_coverage:
    print("\nMost recent sensors:")
    for item in sorted(sensors_with_coverage, key=lambda x: x["days_ago"])[:10]:
        ts = item["ts"]
        print(
            f"  {ts['LocationIdentifier']} - {ts['Parameter']} ({item['days_ago']} days ago)"
        )
        print(f"    UniqueId: {ts['UniqueId']}")
        print(f"    UniqueId: {ts['UniqueId']}")
