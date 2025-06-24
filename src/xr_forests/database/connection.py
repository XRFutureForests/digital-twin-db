"""
Database connection configuration for XR Future Forests Lab
"""

import os
from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base

# Database configuration
DATABASE_URL = os.getenv(
    "XR_FORESTS_DATABASE_URL",
    "postgresql+asyncpg://forests_user:forests_password@localhost:5432/xr_forests_lab",
)

# Create async engine
engine = create_async_engine(
    DATABASE_URL, echo=True, pool_size=10, max_overflow=20  # Set to False in production
)

# Create async session factory
AsyncSessionLocal = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

# Base class for all models
Base = declarative_base()


# Dependency for getting database session
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
