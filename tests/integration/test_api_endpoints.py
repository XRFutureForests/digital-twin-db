#!/usr/bin/env python3
"""
XR Future Forests Lab - Simple API Test Script
Tests the basic functionality of the API endpoints
"""

import requests
import json
import time
from datetime import datetime

API_BASE = "http://localhost:8000"


def test_health():
    """Test the health endpoint"""
    print("🔍 Testing health endpoint...")
    try:
        response = requests.get(f"{API_BASE}/health")
        if response.status_code == 200:
            print("✅ Health check passed")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to API. Is it running?")
        return False


def test_locations():
    """Test location endpoints"""
    print("\n🌍 Testing location endpoints...")

    # Get all locations
    response = requests.get(f"{API_BASE}/api/locations")
    if response.status_code == 200:
        locations = response.json()
        print(f"✅ Found {len(locations)} locations")
        if locations:
            location_id = locations[0]["id"]

            # Get specific location
            response = requests.get(f"{API_BASE}/api/locations/{location_id}")
            if response.status_code == 200:
                print("✅ Location detail retrieval works")
                return location_id

    print("❌ Location endpoints failed")
    return None


def test_species():
    """Test species endpoint"""
    print("\n🌳 Testing species endpoint...")

    response = requests.get(f"{API_BASE}/api/species")
    if response.status_code == 200:
        species = response.json()
        print(f"✅ Found {len(species)} species")
        if species:
            return species[0]["id"]

    print("❌ Species endpoint failed")
    return None


def test_trees(location_id, species_id):
    """Test tree endpoints"""
    print("\n🌲 Testing tree endpoints...")

    # Get all trees
    response = requests.get(f"{API_BASE}/api/trees")
    if response.status_code == 200:
        trees = response.json()
        print(f"✅ Found {len(trees)} trees")

        if trees:
            tree_id = trees[0]["id"]

            # Get tree details
            response = requests.get(f"{API_BASE}/api/trees/{tree_id}")
            if response.status_code == 200:
                print("✅ Tree detail retrieval works")

                # Add a measurement
                measurement_data = {
                    "height_m": 16.5,
                    "dbh_cm": 26.8,
                    "crown_width_m": 8.5,
                    "health_status": "healthy",
                    "measurement_method": "manual",
                    "measured_by": "API Test Script",
                }

                response = requests.post(
                    f"{API_BASE}/api/trees/{tree_id}/measurements",
                    json=measurement_data,
                )

                if response.status_code == 200:
                    print("✅ Tree measurement added successfully")
                    return True

    print("❌ Tree endpoints failed")
    return False


def test_sensors():
    """Test sensor endpoints"""
    print("\n📡 Testing sensor endpoints...")

    response = requests.get(f"{API_BASE}/api/sensors")
    if response.status_code == 200:
        sensors = response.json()
        print(f"✅ Found {len(sensors)} sensors")

        if sensors:
            sensor_id = sensors[0]["id"]

            # Get sensor readings
            response = requests.get(f"{API_BASE}/api/sensors/{sensor_id}/readings")
            if response.status_code == 200:
                readings = response.json()
                print(f"✅ Found {len(readings)} sensor readings")
                return True

    print("❌ Sensor endpoints failed")
    return False


def test_point_clouds():
    """Test point cloud endpoints"""
    print("\n☁️ Testing point cloud endpoints...")

    response = requests.get(f"{API_BASE}/api/point-clouds")
    if response.status_code == 200:
        point_clouds = response.json()
        print(f"✅ Found {len(point_clouds)} point clouds")
        return True

    print("❌ Point cloud endpoints failed")
    return False


def main():
    """Run all tests"""
    print("🧪 XR Future Forests Lab - API Test Suite")
    print("=" * 50)

    # Test health first
    if not test_health():
        print("\n❌ Cannot proceed - API is not healthy")
        return

    # Wait a moment for services to stabilize
    time.sleep(2)

    # Run all tests
    location_id = test_locations()
    species_id = test_species()

    if location_id and species_id:
        test_trees(location_id, species_id)

    test_sensors()
    test_point_clouds()

    print("\n" + "=" * 50)
    print("🎉 API test suite completed!")
    print(f"📊 View detailed API documentation: {API_BASE}/docs")


if __name__ == "__main__":
    main()
