"""
Business logic services for locations
"""

from typing import Sequence, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from xr_forests.core.schemas import LocationCreate, LocationResponse
from xr_forests.database.locations import LocationRepository


class LocationService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.repository = LocationRepository(session)

    async def create_location(self, location_data: LocationCreate) -> LocationResponse:
        """Create a new location with validation"""
        # Basic validation for coordinates
        if not (-90 <= location_data.latitude <= 90):
            raise ValueError("Latitude must be between -90 and 90 degrees")

        if not (-180 <= location_data.longitude <= 180):
            raise ValueError("Longitude must be between -180 and 180 degrees")

        location = await self.repository.create(location_data)
        return LocationResponse.model_validate(location)

    async def get_all_locations(self) -> Sequence[LocationResponse]:
        """Get all locations"""
        locations = await self.repository.get_all()
        return [LocationResponse.model_validate(location) for location in locations]

    async def get_location(self, location_id: int) -> Optional[LocationResponse]:
        """Get a specific location"""
        location = await self.repository.get_by_id(location_id)
        if location:
            return LocationResponse.model_validate(location)
        return None
