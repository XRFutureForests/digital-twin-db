"""
Tree schemas for API request/response validation
"""

from datetime import datetime
from pydantic import BaseModel, Field


class TreeBase(BaseModel):
    height: float = Field(..., gt=0, description="Height in meters")
    diameter: float = Field(..., gt=0, description="Diameter in centimeters")
    status: str = Field(..., pattern="^(healthy|stressed|diseased|dead)$")


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
