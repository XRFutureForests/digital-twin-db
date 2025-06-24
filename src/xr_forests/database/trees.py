"""
Database repository for tree operations
"""

from typing import List, Optional, Sequence
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from xr_forests.core.models import Tree
from xr_forests.core.schemas import TreeCreate


class TreeRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def create(self, tree_data: TreeCreate) -> Tree:
        """Create a new tree"""
        tree = Tree(
            height=tree_data.height,
            diameter=tree_data.diameter,
            status=tree_data.status,
            species_id=tree_data.species_id,
            location_id=tree_data.location_id,
        )
        self.session.add(tree)
        await self.session.commit()
        await self.session.refresh(tree)
        return tree

    async def get_all(self) -> Sequence[Tree]:
        """Get all trees"""
        result = await self.session.execute(select(Tree))
        return result.scalars().all()

    async def get_by_id(self, tree_id: int) -> Optional[Tree]:
        """Get tree by ID"""
        result = await self.session.execute(select(Tree).where(Tree.id == tree_id))
        return result.scalar_one_or_none()
