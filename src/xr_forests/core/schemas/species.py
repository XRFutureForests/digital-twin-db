"""Species schemas."""

from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class SpeciesResponse(BaseModel):
    """Schema for species response."""

    id: str
    scientific_name: str
    common_name: Optional[str]
    species_code: Optional[str]
    max_height_m: Optional[float]
    longevity_years: Optional[int]
    created_at: datetime

    class Config:
        from_attributes = True
