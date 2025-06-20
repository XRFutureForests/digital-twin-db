"""Species router."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional

from ...core.schemas.species import SpeciesResponse, SpeciesQuery
from ...core.services.species_service import SpeciesService
from ...database.connection import get_db

router = APIRouter(prefix="/api/species", tags=["species"])


@router.get("/", response_model=List[SpeciesResponse])
async def get_species(
    common_name: Optional[str] = Query(None, description="Filter by common name"),
    scientific_name: Optional[str] = Query(None, description="Filter by scientific name"),
    limit: int = Query(100, description="Maximum number of results"),
    offset: int = Query(0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    species_service: SpeciesService = Depends(SpeciesService),
):
    """Get all tree species with optional filtering."""
    query_params = SpeciesQuery(
        common_name=common_name,
        scientific_name=scientific_name,
        limit=limit,
        offset=offset,
    )
    return await species_service.get_species_with_filter(db, query_params)


@router.get("/{species_id}", response_model=SpeciesResponse)
async def get_species_by_id(
    species_id: str,
    db: AsyncSession = Depends(get_db),
    species_service: SpeciesService = Depends(SpeciesService),
):
    """Get a specific species by ID."""
    species = await species_service.get_species_by_id(db, species_id)
    if not species:
        raise HTTPException(status_code=404, detail="Species not found")
    return species
