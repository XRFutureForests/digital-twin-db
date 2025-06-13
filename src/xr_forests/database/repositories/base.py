"""Base repository pattern implementation."""

from abc import ABC, abstractmethod
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, delete, func
from typing import Type, TypeVar, Generic, List, Optional, Dict, Any
from uuid import UUID

ModelType = TypeVar("ModelType")


class BaseRepository(Generic[ModelType], ABC):
    """Base repository with common CRUD operations."""

    def __init__(self, model: Type[ModelType]):
        self.model = model

    async def get_by_id(self, db: AsyncSession, id: UUID) -> Optional[ModelType]:
        """Get a record by ID."""
        result = await db.execute(select(self.model).where(self.model.id == id))
        return result.scalar_one_or_none()

    async def get_all(self, db: AsyncSession, skip: int = 0, limit: int = 100) -> List[ModelType]:
        """Get all records with optional pagination."""
        result = await db.execute(select(self.model).offset(skip).limit(limit))
        return result.scalars().all()

    async def create(self, db: AsyncSession, obj_data: Dict[str, Any]) -> ModelType:
        """Create a new record."""
        obj = self.model(**obj_data)
        db.add(obj)
        await db.commit()
        await db.refresh(obj)
        return obj

    async def update(
        self, db: AsyncSession, id: UUID, obj_data: Dict[str, Any]
    ) -> Optional[ModelType]:
        """Update a record by ID."""
        await db.execute(update(self.model).where(self.model.id == id).values(**obj_data))
        await db.commit()
        return await self.get_by_id(db, id)

    async def delete(self, db: AsyncSession, id: UUID) -> bool:
        """Delete a record by ID."""
        result = await db.execute(delete(self.model).where(self.model.id == id))
        await db.commit()
        return result.rowcount > 0

    async def count(self, db: AsyncSession) -> int:
        """Count total records."""
        result = await db.execute(select(func.count(self.model.id)))
        return result.scalar()

    async def exists(self, db: AsyncSession, id: UUID) -> bool:
        """Check if record exists by ID."""
        result = await db.execute(select(self.model.id).where(self.model.id == id))
        return result.scalar_one_or_none() is not None
