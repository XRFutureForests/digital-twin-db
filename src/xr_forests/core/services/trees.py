"""
Business logic services for trees
"""

from typing import Sequence, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from xr_forests.core.schemas import TreeCreate, TreeResponse
from xr_forests.database.trees import TreeRepository


class TreeService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.repository = TreeRepository(session)

    async def create_tree(self, tree_data: TreeCreate) -> TreeResponse:
        """Create a new tree with validation"""
        # Basic business validation
        if tree_data.height > 100:  # Very tall tree check
            raise ValueError("Tree height seems unusually tall (>100m)")

        if tree_data.diameter > 500:  # Very wide tree check
            raise ValueError("Tree diameter seems unusually large (>500cm)")

        tree = await self.repository.create(tree_data)
        return TreeResponse.model_validate(tree)

    async def get_all_trees(self) -> Sequence[TreeResponse]:
        """Get all trees"""
        trees = await self.repository.get_all()
        return [TreeResponse.model_validate(tree) for tree in trees]

    async def get_tree(self, tree_id: int) -> Optional[TreeResponse]:
        """Get a specific tree"""
        tree = await self.repository.get_by_id(tree_id)
        if tree:
            return TreeResponse.model_validate(tree)
        return None
