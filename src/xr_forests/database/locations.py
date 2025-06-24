"""
Database repository for location operations
"""

from typing import Sequence, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from xr_forests.core.models import Location
from xr_forests.core.schemas import LocationCreate


class LocationRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def create(self, location_data: LocationCreate) -> Location:
        """Create a new location"""
        location = Location(
            name=location_data.name,
            latitude=location_data.latitude,
            longitude=location_data.longitude,
        )
        self.session.add(location)
        await self.session.commit()
        await self.session.refresh(location)
        return location

    async def get_all(self) -> Sequence[Location]:
        """Get all locations"""
        result = await self.session.execute(select(Location))
        return result.scalars().all()

    async def get_by_id(self, location_id: int) -> Optional[Location]:
        """Get location by ID"""
        result = await self.session.execute(
            select(Location).where(Location.id == location_id)
        )
        return result.scalar_one_or_none()
