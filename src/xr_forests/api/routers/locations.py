"""Location router."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from ...core.schemas.location import LocationCreate, LocationResponse
from ...core.services.location_service import LocationService
from ...database.connection import get_db

router = APIRouter(prefix="/api/locations", tags=["locations"])


@router.get("/", response_model=List[LocationResponse])
async def get_locations(
    db: AsyncSession = Depends(get_db), location_service: LocationService = Depends(LocationService)
):
    """Get all locations."""
    return await location_service.get_all_locations(db)


@router.get("/{location_id}", response_model=LocationResponse)
async def get_location(
    location_id: str,
    db: AsyncSession = Depends(get_db),
    location_service: LocationService = Depends(LocationService),
):
    """Get a specific location."""
    location = await location_service.get_location_by_id(db, location_id)
    if not location:
        raise HTTPException(status_code=404, detail="Location not found")
    return location


@router.post("/", response_model=LocationResponse)
async def create_location(
    location: LocationCreate,
    db: AsyncSession = Depends(get_db),
    location_service: LocationService = Depends(LocationService),
):
    """Create a new location."""
    return await location_service.create_location(db, location)
