"""
API router for tree endpoints
"""

from typing import Sequence
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from xr_forests.database.connection import get_db
from xr_forests.core.schemas import TreeCreate, TreeResponse
from xr_forests.core.services.trees import TreeService

router = APIRouter(prefix="/api/trees", tags=["trees"])


@router.post("/", response_model=TreeResponse)
async def create_tree(
    tree_data: TreeCreate, db: AsyncSession = Depends(get_db)
) -> TreeResponse:
    """Create a new tree"""
    service = TreeService(db)
    try:
        return await service.create_tree(tree_data)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/", response_model=list[TreeResponse])
async def get_all_trees(db: AsyncSession = Depends(get_db)) -> Sequence[TreeResponse]:
    """Get all trees"""
    service = TreeService(db)
    return await service.get_all_trees()


@router.get("/{tree_id}", response_model=TreeResponse)
async def get_tree(tree_id: int, db: AsyncSession = Depends(get_db)) -> TreeResponse:
    """Get a specific tree by ID"""
    service = TreeService(db)
    tree = await service.get_tree(tree_id)
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    return tree
