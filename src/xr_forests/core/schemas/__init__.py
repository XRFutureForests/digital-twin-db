"""
Pydantic schemas for API request/response validation
"""

# Import all schemas to make them available
from xr_forests.core.schemas.species import SpeciesBase, SpeciesCreate, SpeciesResponse
from xr_forests.core.schemas.location import (
    LocationBase,
    LocationCreate,
    LocationResponse,
)
from xr_forests.core.schemas.tree import TreeBase, TreeCreate, TreeResponse

# Export all schemas for easy importing
__all__ = [
    "SpeciesBase",
    "SpeciesCreate",
    "SpeciesResponse",
    "LocationBase",
    "LocationCreate",
    "LocationResponse",
    "TreeBase",
    "TreeCreate",
    "TreeResponse",
]
