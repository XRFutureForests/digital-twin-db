"""Main FastAPI application factory."""

import os
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import redis.asyncio as redis

from config.settings import settings
from .exception_handlers import EXCEPTION_HANDLERS
from .routers import (
    health_router,
    locations_router,
    tree_router,
    point_cloud_router,
    environment_router,
)

# Redis connection
redis_client = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    # Startup
    global redis_client
    redis_client = redis.from_url(settings.redis_url)
    yield
    # Shutdown
    if redis_client:
        await redis_client.close()


def create_app() -> FastAPI:
    """Create and configure FastAPI application."""
    app = FastAPI(
        title="XR Future Forests Lab API",
        description="API for the XR Future Forests Lab system",
        version="1.0.0",
        lifespan=lifespan,
    )

    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=settings.cors_allow_credentials,
        allow_methods=settings.cors_allow_methods,
        allow_headers=settings.cors_allow_headers,
    )

    # Include routers
    app.include_router(health_router)
    app.include_router(locations_router)
    app.include_router(tree_router)
    app.include_router(point_cloud_router)
    app.include_router(environment_router)

    # Register exception handlers
    for exception_type, handler in EXCEPTION_HANDLERS.items():
        app.add_exception_handler(exception_type, handler)

    return app


# Create app instance
app = create_app()


def main():
    """Main entry point for running the application."""
    import uvicorn

    uvicorn.run(
        "xr_forests.api.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.api_reload,
        workers=settings.api_workers,
    )


if __name__ == "__main__":
    main()
