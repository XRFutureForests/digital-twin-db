#!/usr/bin/env python3
"""
Test a single sensor query to see the actual API error response
"""

import os
import requests
from requests.auth import HTTPBasicAuth
from pathlib import Path
from datetime import datetime, timedelta
from dotenv import load_dotenv
import json

# Load environment
env_path = Path(__file__).parent.parent / "docker" / ".env"
load_dotenv(env_path)

AQUARIUS_HOSTNAME = os.getenv("AQUARIUS_HOSTNAME")
AQUARIUS_USERNAME = os.getenv("AQUARIUS_USERNAME")
AQUARIUS_PASSWORD = os.getenv("AQUARIUS_PASSWORD")

# Test with a known sensor
test_sensors = [
    "c627490362ba4234bf8b2ba65d43f115",  # First sensor that failed
    "510cd6c1fee4441098da0c3802262753",  # Meteo sensor
]

end_time = datetime.utcnow()
start_time = end_time - timedelta(days=7)

print("Testing Aquarius API sensor data queries\n")
print(f"Time range: {start_time.strftime('%Y-%m-%dT%H:%M:%S.000Z')} to {end_time.strftime('%Y-%m-%dT%H:%M:%S.000Z')}\n")

url = f"{AQUARIUS_HOSTNAME}Publish/v2/GetTimeSeriesData"

for unique_id in test_sensors:
    print(f"\nTesting sensor: {unique_id}")
    print("=" * 80)

    params = {
        'TimeSeriesUniqueId': unique_id,
        'QueryFrom': start_time.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
        'QueryTo': end_time.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
    }

    print(f"Request URL: {url}")
    print(f"Parameters: {json.dumps(params, indent=2)}")

    try:
        response = requests.get(
            url,
            params=params,
            auth=HTTPBasicAuth(AQUARIUS_USERNAME, AQUARIUS_PASSWORD),
            timeout=30
        )

        print(f"\nResponse Status: {response.status_code}")
        print(f"Response Headers: {dict(response.headers)}")

        if response.status_code != 200:
            print(f"\nError Response Body:")
            try:
                error_data = response.json()
                print(json.dumps(error_data, indent=2))
            except:
                print(response.text[:500])
        else:
            data = response.json()
            points = data.get('Points', [])
            print(f"\n✓ Success! Got {len(points)} data points")
            if len(points) > 0:
                print(f"First point: {points[0]}")

    except Exception as e:
        print(f"\n❌ Exception: {e}")
        import traceback
        traceback.print_exc()
