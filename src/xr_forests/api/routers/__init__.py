"""API routers package."""

from .locations import router as locations_router
from .health import router as health_router
from .tree import router as tree_router
from .point_cloud import router as point_cloud_router
from .environment import router as environment_router

__all__ = [
    "locations_router",
    "health_router",
    "tree_router",
    "point_cloud_router",
    "environment_router",
]
