"""Environment router."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from datetime import datetime

from ...core.schemas.environment import (
    SensorReadingCreate,
    SensorReadingResponse,
    EnvironmentalSnapshotCreate,
    EnvironmentalSnapshotResponse,
    SiteCharacteristicsCreate,
    SiteCharacteristicsResponse,
    EnvironmentalQuery,
    SensorReadingBulkCreate,
    SensorReadingBulkResponse,
)
from ...core.services.environment_service import EnvironmentService
from ...database.connection import get_db

router = APIRouter(prefix="/api/environment", tags=["environment"])


# Sensor Readings endpoints
@router.get("/readings", response_model=List[SensorReadingResponse])
async def get_sensor_readings(
    location_id: Optional[str] = Query(None, description="Filter by location ID"),
    sensor_type: Optional[str] = Query(None, description="Filter by sensor type"),
    parameter_type: Optional[str] = Query(None, description="Filter by parameter type"),
    start_time: Optional[datetime] = Query(None, description="Start time for readings"),
    end_time: Optional[datetime] = Query(None, description="End time for readings"),
    min_value: Optional[float] = Query(None, description="Minimum reading value"),
    max_value: Optional[float] = Query(None, description="Maximum reading value"),
    limit: int = Query(1000, description="Maximum number of results"),
    offset: int = Query(0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Get sensor readings with optional filtering."""
    query_params = EnvironmentalQuery(
        location_id=location_id,
        sensor_type=sensor_type,
        parameter_type=parameter_type,
        start_time=start_time,
        end_time=end_time,
        min_value=min_value,
        max_value=max_value,
        limit=limit,
        offset=offset,
    )
    return await env_service.get_sensor_readings_with_filter(db, query_params)


@router.get("/readings/{reading_id}", response_model=SensorReadingResponse)
async def get_sensor_reading(
    reading_id: str,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Get a specific sensor reading."""
    reading = await env_service.get_sensor_reading_by_id(db, reading_id)
    if not reading:
        raise HTTPException(status_code=404, detail="Sensor reading not found")
    return reading


@router.post("/readings", response_model=SensorReadingResponse)
async def create_sensor_reading(
    reading: SensorReadingCreate,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Create a new sensor reading."""
    return await env_service.create_sensor_reading(db, reading)


@router.post("/readings/bulk", response_model=SensorReadingBulkResponse)
async def bulk_create_sensor_readings(
    readings: SensorReadingBulkCreate,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Bulk create sensor readings."""
    return await env_service.bulk_create_sensor_readings(db, readings)


# Environment Snapshots endpoints
@router.get("/snapshots", response_model=List[EnvironmentalSnapshotResponse])
async def get_environment_snapshots(
    location_id: Optional[str] = Query(None, description="Filter by location ID"),
    start_date: Optional[datetime] = Query(None, description="Start date for snapshots"),
    end_date: Optional[datetime] = Query(None, description="End date for snapshots"),
    limit: int = Query(100, description="Maximum number of results"),
    offset: int = Query(0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Get environment snapshots with optional filtering."""
    return await env_service.get_environment_snapshots(
        db, location_id, start_date, end_date, limit, offset
    )


@router.get("/snapshots/{snapshot_id}", response_model=EnvironmentalSnapshotResponse)
async def get_environment_snapshot(
    snapshot_id: str,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Get a specific environment snapshot."""
    snapshot = await env_service.get_environment_snapshot_by_id(db, snapshot_id)
    if not snapshot:
        raise HTTPException(status_code=404, detail="Environment snapshot not found")
    return snapshot


@router.post("/snapshots", response_model=EnvironmentalSnapshotResponse)
async def create_environment_snapshot(
    snapshot: EnvironmentalSnapshotCreate,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Create a new environment snapshot."""
    return await env_service.create_environment_snapshot(db, snapshot)


# Site Characteristics endpoints
@router.get("/sites/{location_id}/characteristics", response_model=SiteCharacteristicsResponse)
async def get_site_characteristics(
    location_id: str,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Get site characteristics for a location."""
    characteristics = await env_service.get_site_characteristics(db, location_id)
    if not characteristics:
        raise HTTPException(status_code=404, detail="Site characteristics not found")
    return characteristics


@router.post("/sites/{location_id}/characteristics", response_model=SiteCharacteristicsResponse)
async def create_site_characteristics(
    location_id: str,
    characteristics: SiteCharacteristicsCreate,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Create site characteristics for a location."""
    return await env_service.create_site_characteristics(db, location_id, characteristics)


@router.put("/sites/{location_id}/characteristics", response_model=SiteCharacteristicsResponse)
async def update_site_characteristics(
    location_id: str,
    characteristics: SiteCharacteristicsCreate,
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Update site characteristics for a location."""
    updated = await env_service.update_site_characteristics(db, location_id, characteristics)
    if not updated:
        raise HTTPException(status_code=404, detail="Site characteristics not found")
    return updated


# Statistics and Aggregation endpoints
@router.get("/stats/readings")
async def get_sensor_reading_statistics(
    location_id: Optional[str] = Query(None, description="Filter by location ID"),
    sensor_type: Optional[str] = Query(None, description="Filter by sensor type"),
    parameter_type: Optional[str] = Query(None, description="Filter by parameter type"),
    start_time: Optional[datetime] = Query(None, description="Start time for statistics"),
    end_time: Optional[datetime] = Query(None, description="End time for statistics"),
    aggregation: str = Query(
        "daily", description="Aggregation period (hourly, daily, weekly, monthly)"
    ),
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Get sensor reading statistics and aggregations."""
    return await env_service.get_sensor_reading_statistics(
        db, location_id, sensor_type, parameter_type, start_time, end_time, aggregation
    )


@router.get("/locations/{location_id}/summary")
async def get_location_environment_summary(
    location_id: str,
    start_date: Optional[datetime] = Query(None, description="Start date for summary"),
    end_date: Optional[datetime] = Query(None, description="End date for summary"),
    db: AsyncSession = Depends(get_db),
    env_service: EnvironmentService = Depends(EnvironmentService),
):
    """Get environmental summary for a location."""
    return await env_service.get_location_environment_summary(db, location_id, start_date, end_date)
