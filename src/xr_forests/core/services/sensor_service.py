"""Sensor service."""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional
from datetime import datetime

from ..models.sensor import Sensor, SensorReading
from ..schemas.sensor import SensorQuery


class SensorService:
    """Service for sensor operations."""

    async def get_sensors_with_filter(
        self, db: AsyncSession, query_params: SensorQuery
    ) -> List[Sensor]:
        """Get sensors with optional filtering."""
        query = select(Sensor)

        if query_params.location_id:
            query = query.where(Sensor.location_id == query_params.location_id)

        if query_params.sensor_type:
            query = query.where(Sensor.sensor_type == query_params.sensor_type)

        if query_params.status:
            query = query.where(Sensor.status == query_params.status)

        query = query.offset(query_params.offset).limit(query_params.limit)

        result = await db.execute(query)
        return result.scalars().all()

    async def get_sensor_by_id(self, db: AsyncSession, sensor_id: str) -> Optional[Sensor]:
        """Get sensor by ID."""
        query = select(Sensor).where(Sensor.id == sensor_id)
        result = await db.execute(query)
        return result.scalar_one_or_none()

    async def get_sensor_readings(
        self,
        db: AsyncSession,
        sensor_id: str,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 1000,
        offset: int = 0,
    ) -> List[SensorReading]:
        """Get readings for a specific sensor."""
        query = select(SensorReading).where(SensorReading.sensor_id == sensor_id)

        if start_time:
            query = query.where(SensorReading.timestamp >= start_time)

        if end_time:
            query = query.where(SensorReading.timestamp <= end_time)

        query = query.order_by(SensorReading.timestamp.desc()).offset(offset).limit(limit)

        result = await db.execute(query)
        return result.scalars().all()
