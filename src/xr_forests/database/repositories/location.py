"""Location repository."""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional
from uuid import UUID

from .base import BaseRepository
from ...core.models.location import Location


class LocationRepository(BaseRepository[Location]):
    """Location repository with specific methods."""

    def __init__(self):
        super().__init__(Location)

    async def get_by_name(self, db: AsyncSession, name: str) -> Optional[Location]:
        """Get location by name."""
        result = await db.execute(select(Location).where(Location.location_name == name))
        return result.scalar_one_or_none()

    async def get_locations_near_point(
        self, db: AsyncSession, latitude: float, longitude: float, radius_km: float = 10.0
    ) -> List[Location]:
        """Get locations within radius of a point."""
        # This would use PostGIS spatial functions in a real implementation
        # For now, return all locations
        return await self.get_all(db)
