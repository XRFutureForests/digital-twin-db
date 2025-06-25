"""
Database repository for species operations
"""

from typing import Sequence, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from xr_forests.core.models import Species
from xr_forests.core.schemas import SpeciesCreate


class SpeciesRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def create(self, species_data: SpeciesCreate) -> Species:
        """Create a new species"""
        species = Species(
            name=species_data.name,
            scientific_name=species_data.scientific_name,
        )
        self.session.add(species)
        await self.session.commit()
        await self.session.refresh(species)
        return species

    async def get_all(self) -> Sequence[Species]:
        """Get all species"""
        result = await self.session.execute(select(Species))
        return result.scalars().all()

    async def get_by_id(self, species_id: int) -> Optional[Species]:
        """Get species by ID"""
        result = await self.session.execute(
            select(Species).where(Species.id == species_id)
        )
        return result.scalar_one_or_none()
