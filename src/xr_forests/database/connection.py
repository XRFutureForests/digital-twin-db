"""Database connection and session management."""

import os
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from config.settings import settings

# Import Base to ensure models are registered
from ..core.models.base import Base


# Create async engine
engine = create_async_engine(
    settings.database_url,
    echo=settings.database_echo,
    pool_pre_ping=True,
    pool_recycle=300,
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
)

# Create async session factory
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


# Dependency to get database session
async def get_db():
    """Get database session dependency."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
