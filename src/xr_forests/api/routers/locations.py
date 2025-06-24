"""
API router for location endpoints
"""

from typing import Sequence
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from xr_forests.database.connection import get_db
from xr_forests.core.schemas import LocationCreate, LocationResponse
from xr_forests.core.services.locations import LocationService

router = APIRouter(prefix="/api/locations", tags=["locations"])


@router.post("/", response_model=LocationResponse)
async def create_location(
    location_data: LocationCreate, db: AsyncSession = Depends(get_db)
) -> LocationResponse:
    """Create a new forest location"""
    service = LocationService(db)
    try:
        return await service.create_location(location_data)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/", response_model=list[LocationResponse])
async def get_all_locations(
    db: AsyncSession = Depends(get_db),
) -> Sequence[LocationResponse]:
    """Get all forest locations"""
    service = LocationService(db)
    return await service.get_all_locations()


@router.get("/{location_id}", response_model=LocationResponse)
async def get_location(
    location_id: int, db: AsyncSession = Depends(get_db)
) -> LocationResponse:
    """Get a specific location by ID"""
    service = LocationService(db)
    location = await service.get_location(location_id)
    if not location:
        raise HTTPException(status_code=404, detail="Location not found")
    return location
