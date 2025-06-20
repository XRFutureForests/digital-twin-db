"""Location service layer."""

from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from uuid import UUID

from ..schemas.location import LocationCreate, LocationResponse, LocationUpdate, LocationQuery
from ...database.repositories.location import LocationRepository
from ...core.models.location import Location
from .base import BaseService


class LocationService(BaseService[Location, LocationCreate, LocationUpdate, LocationResponse]):
    """Service layer for location operations."""

    def __init__(self):
        super().__init__(LocationRepository(), "location")

    async def get_locations_with_filter(
        self, db: AsyncSession, query: LocationQuery
    ) -> List[LocationResponse]:
        """Get locations with filtering."""
        locations = await self.repository.get_with_filter(db, query)
        return [self._to_response(loc) for loc in locations]

    async def get_location_by_name(self, db: AsyncSession, name: str) -> Optional[LocationResponse]:
        """Get location by name."""
        location = await self.repository.get_by_name(db, name)
        return self._to_response(location) if location else None

    def _pre_create_transform(self, create_dict: dict) -> dict:
        """Apply location-specific transformations before create."""
        # Handle coordinate conversion if provided
        if "latitude" in create_dict and "longitude" in create_dict:
            # In real implementation, would convert to PostGIS geometry
            create_dict["center_point"] = {
                "type": "Point",
                "coordinates": [create_dict["longitude"], create_dict["latitude"]],
            }
        return create_dict

    def _pre_update_transform(self, update_dict: dict) -> dict:
        """Apply location-specific transformations before update."""
        # Handle coordinate conversion if provided
        if "latitude" in update_dict and "longitude" in update_dict:
            update_dict["center_point"] = {
                "type": "Point",
                "coordinates": [update_dict["longitude"], update_dict["latitude"]],
            }
        return update_dict

    def _to_response(self, resource: Location) -> LocationResponse:
        """Convert model to response schema."""
        return LocationResponse(
            id=str(resource.id),
            location_name=resource.location_name,
            description=resource.description,
            elevation_m=float(resource.elevation_m) if resource.elevation_m else None,
            plot_boundary=None,  # Would convert from PostGIS geometry
            center_point=None,  # Would convert from PostGIS geometry
            created_at=resource.created_at,
            updated_at=resource.updated_at,
        )
