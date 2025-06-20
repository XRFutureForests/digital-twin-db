"""Sensors router."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from datetime import datetime

from ...core.schemas.sensor import SensorResponse, SensorQuery, SensorReadingResponse
from ...core.services.sensor_service import SensorService
from ...database.connection import get_db

router = APIRouter(prefix="/api/sensors", tags=["sensors"])


@router.get("/", response_model=List[SensorResponse])
async def get_sensors(
    location_id: Optional[str] = Query(None, description="Filter by location ID"),
    sensor_type: Optional[str] = Query(None, description="Filter by sensor type"),
    status: Optional[str] = Query(None, description="Filter by sensor status"),
    limit: int = Query(100, description="Maximum number of results"),
    offset: int = Query(0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    sensor_service: SensorService = Depends(SensorService),
):
    """Get all sensors with optional filtering."""
    query_params = SensorQuery(
        location_id=location_id,
        sensor_type=sensor_type,
        status=status,
        limit=limit,
        offset=offset,
    )
    return await sensor_service.get_sensors_with_filter(db, query_params)


@router.get("/{sensor_id}", response_model=SensorResponse)
async def get_sensor(
    sensor_id: str,
    db: AsyncSession = Depends(get_db),
    sensor_service: SensorService = Depends(SensorService),
):
    """Get a specific sensor by ID."""
    sensor = await sensor_service.get_sensor_by_id(db, sensor_id)
    if not sensor:
        raise HTTPException(status_code=404, detail="Sensor not found")
    return sensor


@router.get("/{sensor_id}/readings", response_model=List[SensorReadingResponse])
async def get_sensor_readings(
    sensor_id: str,
    start_time: Optional[datetime] = Query(None, description="Start time for readings"),
    end_time: Optional[datetime] = Query(None, description="End time for readings"),
    limit: int = Query(1000, description="Maximum number of results"),
    offset: int = Query(0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    sensor_service: SensorService = Depends(SensorService),
):
    """Get readings for a specific sensor."""
    return await sensor_service.get_sensor_readings(
        db, sensor_id, start_time, end_time, limit, offset
    )
