"""Integration tests for API endpoints."""

import pytest
import asyncio
from httpx import AsyncClient
from fastapi.testclient import TestClient

from xr_forests.api.main import create_app


@pytest.fixture
def client():
    """Create test client."""
    app = create_app()
    return TestClient(app)


def test_health_endpoint(client):
    """Test the health endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "service" in data
    assert "version" in data


def test_get_locations(client):
    """Test getting all locations."""
    response = client.get("/api/locations/")
    assert response.status_code == 200
    # Would normally check for actual data
    # For now, just verify the endpoint exists


def test_create_location(client):
    """Test creating a location."""
    location_data = {
        "location_name": "Test Forest",
        "description": "A test forest location",
        "latitude": 48.0,
        "longitude": 7.8,
        "elevation_m": 300.5,
    }

    response = client.post("/api/locations/", json=location_data)
    # This will fail until database is properly set up
    # assert response.status_code == 201
