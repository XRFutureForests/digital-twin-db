"""
Business logic services for species
"""

from typing import Sequence, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from xr_forests.core.schemas import SpeciesCreate, SpeciesResponse
from xr_forests.database.species import SpeciesRepository


class SpeciesService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.repository = SpeciesRepository(session)

    async def create_species(self, species_data: SpeciesCreate) -> SpeciesResponse:
        """Create a new species with validation"""
        # Basic validation for species name uniqueness could be added here
        species = await self.repository.create(species_data)
        return SpeciesResponse.model_validate(species)

    async def get_all_species(self) -> Sequence[SpeciesResponse]:
        """Get all species"""
        species = await self.repository.get_all()
        return [SpeciesResponse.model_validate(s) for s in species]

    async def get_species(self, species_id: int) -> Optional[SpeciesResponse]:
        """Get a specific species"""
        species = await self.repository.get_by_id(species_id)
        if species:
            return SpeciesResponse.model_validate(species)
        return None
