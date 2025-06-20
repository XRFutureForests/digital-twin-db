"""Environment repository."""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from .base import BaseRepository
from ...core.models.environment import SensorReadings, EnvironmentalSnapshots, SiteCharacteristics
from ...core.schemas.environment import EnvironmentalQuery


class EnvironmentRepository(BaseRepository[SensorReadings]):
    """Repository for environment operations."""

    def __init__(self):
        super().__init__(SensorReadings)

    async def get_sensor_readings_with_filter(
        self, db: AsyncSession, query: EnvironmentalQuery
    ) -> List[SensorReadings]:
        """Get sensor readings with filtering."""
        stmt = select(self.model)

        filters = []
        if query.location_id:
            filters.append(self.model.location_id == int(query.location_id))
        if query.sensor_type:
            filters.append(self.model.sensor_type == query.sensor_type)
        if query.parameter_type:
            filters.append(self.model.parameter_type == query.parameter_type)
        if query.start_time:
            filters.append(self.model.reading_timestamp >= query.start_time)
        if query.end_time:
            filters.append(self.model.reading_timestamp <= query.end_time)
        if query.min_value:
            filters.append(self.model.reading_value >= query.min_value)
        if query.max_value:
            filters.append(self.model.reading_value <= query.max_value)

        if filters:
            stmt = stmt.where(and_(*filters))

        stmt = stmt.offset(query.offset).limit(query.limit)

        result = await db.execute(stmt)
        return result.scalars().all()

    async def get_sensor_reading_by_id(
        self, db: AsyncSession, reading_id: UUID
    ) -> Optional[SensorReadings]:
        """Get sensor reading by ID."""
        return await self.get_by_id(db, reading_id)

    async def create_sensor_reading(self, db: AsyncSession, reading_data: dict) -> SensorReadings:
        """Create a sensor reading."""
        reading = SensorReadings(**reading_data)
        db.add(reading)
        await db.commit()
        await db.refresh(reading)
        return reading

    async def get_environment_snapshots(
        self,
        db: AsyncSession,
        location_id: Optional[str],
        start_date: Optional[datetime],
        end_date: Optional[datetime],
        limit: int,
        offset: int,
    ) -> List[EnvironmentalSnapshots]:
        """Get environment snapshots."""
        stmt = select(EnvironmentalSnapshots)

        filters = []
        if location_id:
            filters.append(EnvironmentalSnapshots.location_id == int(location_id))
        if start_date:
            filters.append(EnvironmentalSnapshots.snapshot_date >= start_date)
        if end_date:
            filters.append(EnvironmentalSnapshots.snapshot_date <= end_date)

        if filters:
            stmt = stmt.where(and_(*filters))

        stmt = stmt.offset(offset).limit(limit)

        result = await db.execute(stmt)
        return result.scalars().all()

    async def get_environment_snapshot_by_id(
        self, db: AsyncSession, snapshot_id: UUID
    ) -> Optional[EnvironmentalSnapshots]:
        """Get environment snapshot by ID."""
        stmt = select(EnvironmentalSnapshots).where(EnvironmentalSnapshots.id == snapshot_id)
        result = await db.execute(stmt)
        return result.scalars().first()

    async def create_environment_snapshot(
        self, db: AsyncSession, snapshot_data: dict
    ) -> EnvironmentalSnapshots:
        """Create environment snapshot."""
        snapshot = EnvironmentalSnapshots(**snapshot_data)
        db.add(snapshot)
        await db.commit()
        await db.refresh(snapshot)
        return snapshot

    async def get_site_characteristics(
        self, db: AsyncSession, location_id: int
    ) -> Optional[SiteCharacteristics]:
        """Get site characteristics for a location."""
        stmt = select(SiteCharacteristics).where(SiteCharacteristics.location_id == location_id)
        result = await db.execute(stmt)
        return result.scalars().first()

    async def create_site_characteristics(
        self, db: AsyncSession, characteristics_data: dict
    ) -> SiteCharacteristics:
        """Create site characteristics."""
        characteristics = SiteCharacteristics(**characteristics_data)
        db.add(characteristics)
        await db.commit()
        await db.refresh(characteristics)
        return characteristics

    async def update_site_characteristics(
        self, db: AsyncSession, location_id: int, characteristics_data: dict
    ) -> Optional[SiteCharacteristics]:
        """Update site characteristics."""
        characteristics = await self.get_site_characteristics(db, location_id)
        if characteristics:
            for key, value in characteristics_data.items():
                setattr(characteristics, key, value)
            await db.commit()
            await db.refresh(characteristics)
        return characteristics

    async def get_sensor_reading_statistics(
        self,
        db: AsyncSession,
        location_id: Optional[str],
        sensor_type: Optional[str],
        parameter_type: Optional[str],
        start_time: Optional[datetime],
        end_time: Optional[datetime],
        aggregation: str,
    ):
        """Get sensor reading statistics."""
        # Implementation would depend on specific aggregation requirements
        # This is a placeholder that would need to be implemented based on business requirements
        return {
            "aggregation_type": aggregation,
            "period_start": start_time,
            "period_end": end_time,
            "statistics": {},
        }

    async def get_location_environment_summary(
        self,
        db: AsyncSession,
        location_id: int,
        start_date: Optional[datetime],
        end_date: Optional[datetime],
    ):
        """Get environmental summary for a location."""
        # Implementation would aggregate various environmental data
        # This is a placeholder that would need to be implemented based on business requirements
        return {
            "location_id": location_id,
            "summary_period": {"start": start_date, "end": end_date},
            "summary_data": {},
        }
