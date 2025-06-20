"""Base service class for common patterns."""

from abc import ABC
from typing import TypeVar, Generic, List, Optional, Type
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import UUID

from ..exceptions import NotFoundError, DatabaseError
from ...database.repositories.base import BaseRepository

ModelType = TypeVar("ModelType")
CreateSchemaType = TypeVar("CreateSchemaType")
UpdateSchemaType = TypeVar("UpdateSchemaType")
ResponseSchemaType = TypeVar("ResponseSchemaType")


class BaseService(Generic[ModelType, CreateSchemaType, UpdateSchemaType, ResponseSchemaType], ABC):
    """Base service class with common CRUD operations."""

    def __init__(self, repository: BaseRepository[ModelType], resource_name: str):
        self.repository = repository
        self.resource_name = resource_name

    async def get_by_id(self, db: AsyncSession, id: str) -> Optional[ResponseSchemaType]:
        """Get resource by ID."""
        try:
            resource = await self.repository.get_by_id(db, UUID(id))
            return self._to_response(resource) if resource else None
        except Exception as e:
            raise DatabaseError("get", str(e))

    async def get_by_id_or_404(self, db: AsyncSession, id: str) -> ResponseSchemaType:
        """Get resource by ID or raise NotFoundError."""
        resource = await self.get_by_id(db, id)
        if not resource:
            raise NotFoundError(self.resource_name, id)
        return resource

    async def create(self, db: AsyncSession, create_data: CreateSchemaType) -> ResponseSchemaType:
        """Create a new resource."""
        try:
            create_dict = create_data.dict(exclude_unset=True)
            # Apply any pre-create transformations
            create_dict = self._pre_create_transform(create_dict)

            resource = await self.repository.create(db, create_dict)
            return self._to_response(resource)
        except Exception as e:
            raise DatabaseError("create", str(e))

    async def update(
        self, db: AsyncSession, id: str, update_data: UpdateSchemaType
    ) -> Optional[ResponseSchemaType]:
        """Update an existing resource."""
        try:
            update_dict = update_data.dict(exclude_unset=True)
            # Apply any pre-update transformations
            update_dict = self._pre_update_transform(update_dict)

            resource = await self.repository.update(db, UUID(id), update_dict)
            return self._to_response(resource) if resource else None
        except Exception as e:
            raise DatabaseError("update", str(e))

    async def update_or_404(
        self, db: AsyncSession, id: str, update_data: UpdateSchemaType
    ) -> ResponseSchemaType:
        """Update resource or raise NotFoundError."""
        resource = await self.update(db, id, update_data)
        if not resource:
            raise NotFoundError(self.resource_name, id)
        return resource

    async def delete(self, db: AsyncSession, id: str) -> bool:
        """Delete a resource."""
        try:
            return await self.repository.delete(db, UUID(id))
        except Exception as e:
            raise DatabaseError("delete", str(e))

    async def delete_or_404(self, db: AsyncSession, id: str) -> bool:
        """Delete resource or raise NotFoundError."""
        if not await self.repository.exists(db, UUID(id)):
            raise NotFoundError(self.resource_name, id)
        return await self.delete(db, id)

    async def count(self, db: AsyncSession) -> int:
        """Count total resources."""
        try:
            return await self.repository.count(db)
        except Exception as e:
            raise DatabaseError("count", str(e))

    def _pre_create_transform(self, create_dict: dict) -> dict:
        """Override in subclasses to apply transformations before create."""
        return create_dict

    def _pre_update_transform(self, update_dict: dict) -> dict:
        """Override in subclasses to apply transformations before update."""
        return update_dict

    def _to_response(self, resource: ModelType) -> ResponseSchemaType:
        """Convert model to response schema. Must be implemented by subclasses."""
        raise NotImplementedError("Subclasses must implement _to_response method")
