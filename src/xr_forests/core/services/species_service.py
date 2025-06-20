"""Species service."""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List, Optional

from ..models.species import Species
from ..schemas.species import SpeciesQuery


class SpeciesService:
    """Service for species operations."""

    async def get_species_with_filter(
        self, db: AsyncSession, query_params: SpeciesQuery
    ) -> List[Species]:
        """Get species with optional filtering."""
        query = select(Species)

        if query_params.common_name:
            query = query.where(Species.common_name.ilike(f"%{query_params.common_name}%"))

        if query_params.scientific_name:
            query = query.where(Species.scientific_name.ilike(f"%{query_params.scientific_name}%"))

        if query_params.species_code:
            query = query.where(Species.species_code == query_params.species_code)

        query = query.offset(query_params.offset).limit(query_params.limit)

        result = await db.execute(query)
        return result.scalars().all()

    async def get_species_by_id(self, db: AsyncSession, species_id: str) -> Optional[Species]:
        """Get species by ID."""
        query = select(Species).where(Species.id == species_id)
        result = await db.execute(query)
        return result.scalar_one_or_none()
