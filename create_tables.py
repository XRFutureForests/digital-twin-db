"""
Script to create database tables
"""

import asyncio
from sqlalchemy import text
from xr_forests.database.connection import engine, Base
from xr_forests.core.models import *  # Import all models to register them


async def create_tables():
    """Create all database tables"""
    async with engine.begin() as conn:
        # Drop and recreate all tables (for development only)
        # Use CASCADE to handle foreign key dependencies
        await conn.execute(text("DROP SCHEMA public CASCADE;"))
        await conn.execute(text("CREATE SCHEMA public;"))
        await conn.run_sync(Base.metadata.create_all)

    print("✅ Database tables created successfully!")


if __name__ == "__main__":
    asyncio.run(create_tables())
