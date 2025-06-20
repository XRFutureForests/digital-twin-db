"""Location repository."""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from typing import List, Optional
from uuid import UUID

from .base import BaseRepository
from ...core.models.location import Location
from ...core.schemas.location import LocationQuery


class LocationRepository(BaseRepository[Location]):
    """Location repository with specific methods."""

    def __init__(self):
        super().__init__(Location)

    async def get_with_filter(self, db: AsyncSession, query: LocationQuery) -> List[Location]:
        """Get locations with filtering."""
        stmt = select(self.model)

        filters = []
        if query.location_name:
            filters.append(self.model.location_name.ilike(f"%{query.location_name}%"))
        if query.min_elevation:
            filters.append(self.model.elevation_m >= query.min_elevation)
        if query.max_elevation:
            filters.append(self.model.elevation_m <= query.max_elevation)

        if filters:
            stmt = stmt.where(and_(*filters))

        stmt = stmt.offset(query.offset).limit(query.limit)

        result = await db.execute(stmt)
        return result.scalars().all()

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
