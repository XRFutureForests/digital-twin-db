"""Location router."""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional

from ...core.schemas.location import LocationCreate, LocationResponse, LocationUpdate, LocationQuery
from ...core.services.location_service import LocationService
from ...database.connection import get_db

router = APIRouter(prefix="/api/locations", tags=["locations"])


@router.get("/", response_model=List[LocationResponse])
async def get_locations(
    location_name: Optional[str] = Query(None, description="Filter by location name"),
    min_elevation: Optional[float] = Query(None, description="Minimum elevation filter"),
    max_elevation: Optional[float] = Query(None, description="Maximum elevation filter"),
    limit: int = Query(100, ge=1, le=1000, description="Maximum number of results"),
    offset: int = Query(0, ge=0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    location_service: LocationService = Depends(LocationService),
):
    """Get all locations with optional filtering."""
    query_params = LocationQuery(
        location_name=location_name,
        min_elevation=min_elevation,
        max_elevation=max_elevation,
        limit=limit,
        offset=offset,
    )
    return await location_service.get_locations_with_filter(db, query_params)


@router.get("/{location_id}", response_model=LocationResponse)
async def get_location(
    location_id: str,
    db: AsyncSession = Depends(get_db),
    location_service: LocationService = Depends(LocationService),
):
    """Get a specific location."""
    return await location_service.get_by_id_or_404(db, location_id)


@router.post("/", response_model=LocationResponse)
async def create_location(
    location: LocationCreate,
    db: AsyncSession = Depends(get_db),
    location_service: LocationService = Depends(LocationService),
):
    """Create a new location."""
    return await location_service.create(db, location)


@router.put("/{location_id}", response_model=LocationResponse)
async def update_location(
    location_id: str,
    location_update: LocationUpdate,
    db: AsyncSession = Depends(get_db),
    location_service: LocationService = Depends(LocationService),
):
    """Update an existing location."""
    return await location_service.update_or_404(db, location_id, location_update)


@router.delete("/{location_id}")
async def delete_location(
    location_id: str,
    db: AsyncSession = Depends(get_db),
    location_service: LocationService = Depends(LocationService),
):
    """Delete a location."""
    await location_service.delete_or_404(db, location_id)
    return {"message": "Location deleted successfully"}
