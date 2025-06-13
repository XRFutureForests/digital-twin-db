"""Location service."""

from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from uuid import UUID

from ..schemas.location import LocationCreate, LocationResponse
from ...database.repositories.location import LocationRepository


class LocationService:
    """Service layer for location operations."""

    def __init__(self):
        self.repository = LocationRepository()

    async def get_all_locations(self, db: AsyncSession) -> List[LocationResponse]:
        """Get all locations."""
        locations = await self.repository.get_all(db)
        return [self._to_response(loc) for loc in locations]

    async def get_location_by_id(
        self, db: AsyncSession, location_id: str
    ) -> Optional[LocationResponse]:
        """Get location by ID."""
        location = await self.repository.get_by_id(db, UUID(location_id))
        return self._to_response(location) if location else None

    async def create_location(
        self, db: AsyncSession, location_data: LocationCreate
    ) -> LocationResponse:
        """Create a new location."""
        location_dict = location_data.dict(exclude_unset=True)

        # Handle coordinate conversion if provided
        if location_data.latitude and location_data.longitude:
            # In real implementation, would convert to PostGIS geometry
            location_dict["center_point"] = {
                "type": "Point",
                "coordinates": [location_data.longitude, location_data.latitude],
            }

        location = await self.repository.create(db, location_dict)
        return self._to_response(location)

    async def get_location_by_name(self, db: AsyncSession, name: str) -> Optional[LocationResponse]:
        """Get location by name."""
        location = await self.repository.get_by_name(db, name)
        return self._to_response(location) if location else None

    def _to_response(self, location) -> LocationResponse:
        """Convert model to response schema."""
        return LocationResponse(
            id=str(location.id),
            location_name=location.location_name,
            description=location.description,
            elevation_m=float(location.elevation_m) if location.elevation_m else None,
            center_point=None,  # Would convert from PostGIS geometry
            created_at=location.created_at,
            updated_at=location.updated_at,
        )
