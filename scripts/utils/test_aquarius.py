#!/usr/bin/env python3
"""
Test Aquarius API connection and list available sensors
"""

import os
import sys
import requests
from requests.auth import HTTPBasicAuth
from pathlib import Path
from dotenv import load_dotenv

# Load environment
env_path = Path(__file__).parent.parent.parent / "docker" / ".env"
load_dotenv(env_path)

# Aquarius configuration
AQUARIUS_HOSTNAME = os.getenv("AQUARIUS_HOSTNAME")
AQUARIUS_USERNAME = os.getenv("AQUARIUS_USERNAME")
AQUARIUS_PASSWORD = os.getenv("AQUARIUS_PASSWORD")

print("=" * 80)
print("AQUARIUS API CONNECTION TEST")
print("=" * 80)

print(f"\nConfiguration:")
print(f"  Hostname: {AQUARIUS_HOSTNAME}")
print(f"  Username: {AQUARIUS_USERNAME}")

# Test connection
try:
    # Get time series descriptions
    url = f"{AQUARIUS_HOSTNAME}Publish/v2/GetTimeSeriesDescriptionList"

    print(f"\nConnecting to: {url}")

    response = requests.get(
        url,
        auth=HTTPBasicAuth(AQUARIUS_USERNAME, AQUARIUS_PASSWORD),
        timeout=30
    )

    response.raise_for_status()
    data = response.json()

    descriptions = data.get('TimeSeriesDescriptions', [])
    print(f"\n✓ Connected successfully!")
    print(f"✓ Found {len(descriptions)} total time series")

    # Filter for Ecosense sensors
    ecosense_ts = [ts for ts in descriptions if ts.get('LocationIdentifier', '').startswith('Ecosense_')]

    print(f"✓ Found {len(ecosense_ts)} Ecosense time series")

    if len(ecosense_ts) > 0:
        print(f"\nFirst 10 Ecosense sensors:")
        for i, ts in enumerate(ecosense_ts[:10], 1):
            print(f"  {i}. Location: {ts.get('LocationIdentifier')}")
            print(f"     Parameter: {ts.get('Parameter')}")
            print(f"     Label: {ts.get('Label')}")
            print(f"     Unit: {ts.get('Unit')}")
            print(f"     UniqueId: {ts.get('UniqueId')}")
            print()

        if len(ecosense_ts) > 10:
            print(f"  ... and {len(ecosense_ts) - 10} more")

        # Count by parameter type
        param_counts = {}
        for ts in ecosense_ts:
            param = ts.get('Parameter')
            param_counts[param] = param_counts.get(param, 0) + 1

        print(f"\nSensors by parameter type:")
        for param, count in sorted(param_counts.items(), key=lambda x: -x[1]):
            print(f"  {param}: {count}")

    else:
        print("\n⚠️  No Ecosense sensors found")
        print("  Listing first 5 sensors:")
        for i, ts in enumerate(descriptions[:5], 1):
            print(f"  {i}. Location: {ts.get('LocationIdentifier')}")
            print(f"     Parameter: {ts.get('Parameter')}")

except requests.exceptions.ConnectionError as e:
    print(f"\n❌ Connection failed: {e}")
    print("  The Aquarius server may be unreachable from this network.")
except requests.exceptions.Timeout:
    print(f"\n❌ Connection timed out")
    print("  The Aquarius server took too long to respond.")
except requests.exceptions.HTTPError as e:
    print(f"\n❌ HTTP Error: {e}")
    print(f"  Status code: {response.status_code}")
    if response.status_code == 401:
        print("  Authentication failed - check username/password")
except Exception as e:
    print(f"\n❌ Unexpected error: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "=" * 80)
