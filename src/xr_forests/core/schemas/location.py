"""Location schemas."""

from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from datetime import datetime


class LocationCreate(BaseModel):
    """Schema for creating a location."""

    location_name: str = Field(..., max_length=200)
    description: Optional[str] = None
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    elevation_m: Optional[float] = None


class LocationResponse(BaseModel):
    """Schema for location response."""

    id: str
    location_name: str
    description: Optional[str]
    elevation_m: Optional[float]
    center_point: Optional[Dict[str, Any]]  # GeoJSON point
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
