"""
Tree schemas for API request/response validation
"""

from datetime import datetime
from pydantic import BaseModel, Field
from xr_forests.core.models.tree import TreeStatus


class TreeBase(BaseModel):
    height: float = Field(..., gt=0, description="Height in meters")
    diameter: float = Field(..., gt=0, description="Diameter in centimeters")
    status: TreeStatus = Field(..., description="Tree health status")


class TreeCreate(TreeBase):
    species_id: int
    location_id: int


class TreeResponse(TreeBase):
    id: int
    species_id: int
    location_id: int
    created_at: datetime

    class Config:
        from_attributes = True
