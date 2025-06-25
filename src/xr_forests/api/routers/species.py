"""
API router for species endpoints
"""

from typing import Sequence
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from xr_forests.database.connection import get_db
from xr_forests.core.schemas import SpeciesCreate, SpeciesResponse
from xr_forests.core.services.species import SpeciesService

router = APIRouter(prefix="/api/species", tags=["species"])


@router.post("/", response_model=SpeciesResponse)
async def create_species(
    species_data: SpeciesCreate, db: AsyncSession = Depends(get_db)
) -> SpeciesResponse:
    """Create a new tree species"""
    service = SpeciesService(db)
    try:
        return await service.create_species(species_data)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/", response_model=list[SpeciesResponse])
async def get_all_species(
    db: AsyncSession = Depends(get_db),
) -> Sequence[SpeciesResponse]:
    """Get all tree species"""
    service = SpeciesService(db)
    return await service.get_all_species()


@router.get("/{species_id}", response_model=SpeciesResponse)
async def get_species(
    species_id: int, db: AsyncSession = Depends(get_db)
) -> SpeciesResponse:
    """Get a specific species by ID"""
    service = SpeciesService(db)
    species = await service.get_species(species_id)
    if not species:
        raise HTTPException(status_code=404, detail="Species not found")
    return species
