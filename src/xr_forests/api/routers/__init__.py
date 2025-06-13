"""API routers package."""

from .locations import router as locations_router
from .health import router as health_router

__all__ = ["locations_router", "health_router"]
