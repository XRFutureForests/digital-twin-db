"""Test configuration and fixtures for XR Future Forests Lab."""

import pytest
import asyncio
from typing import AsyncGenerator, Generator
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool

from config.settings import TestingSettings

# Test settings
test_settings = TestingSettings()


@pytest.fixture(scope="session")
def event_loop() -> Generator:
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
async def test_engine():
    """Create test database engine."""
    engine = create_async_engine(
        test_settings.database_url,
        echo=test_settings.database_echo,
        poolclass=NullPool,  # Use NullPool for testing
    )

    # Create tables
    # Note: This would import from your models module once it's restructured
    # from xr_forests.database.models import Base
    # async with engine.begin() as conn:
    #     await conn.run_sync(Base.metadata.create_all)

    yield engine

    # Cleanup
    await engine.dispose()


@pytest.fixture
async def test_db(test_engine) -> AsyncGenerator[AsyncSession, None]:
    """Create test database session."""
    async_session = sessionmaker(test_engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # Start a transaction
        transaction = await session.begin()

        yield session

        # Rollback transaction after test
        await transaction.rollback()


@pytest.fixture
def client(test_db) -> TestClient:
    """Create test client with database override."""
    # This would be implemented once the API is restructured
    # from xr_forests.api.main import create_app
    # from xr_forests.database.connection import get_db

    # app = create_app()
    # app.dependency_overrides[get_db] = lambda: test_db
    # return TestClient(app)

    # For now, return a placeholder
    pass


@pytest.fixture
async def sample_location_data():
    """Sample location data for testing."""
    return {
        "location_name": "Test Forest Area",
        "description": "A test forest location for unit testing",
        "latitude": 48.0,
        "longitude": 7.8,
        "elevation_m": 300.5,
    }


@pytest.fixture
async def sample_tree_data():
    """Sample tree data for testing."""
    return {
        "location_id": "sample-location-id",
        "species_id": "sample-species-id",
        "latitude": 48.001,
        "longitude": 7.801,
        "height_m": 15.5,
        "dbh_cm": 25.3,
        "crown_width_m": 8.2,
        "health_status": "healthy",
        "planted_year": 2010,
    }


@pytest.fixture
async def sample_species_data():
    """Sample species data for testing."""
    return {
        "scientific_name": "Pinus sylvestris",
        "common_name": "Scots Pine",
        "species_code": "PISL",
        "max_height_m": 35.0,
        "longevity_years": 200,
    }
