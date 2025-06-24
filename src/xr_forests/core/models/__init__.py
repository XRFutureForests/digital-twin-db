"""
Database models for XR Future Forests Lab MVP
"""

# Import all models to make them available
from xr_forests.database.connection import Base
from xr_forests.core.models.species import Species
from xr_forests.core.models.location import Location
from xr_forests.core.models.tree import Tree, TreeStatus

# Export all models for easy importing
__all__ = [
    "Base",
    "TreeStatus", 
    "Species",
    "Location",
    "Tree"
]
