"""Tree schemas."""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime, date


class TreeCreate(BaseModel):
    """Schema for creating a tree."""

    location_id: str
    tree_tag: Optional[str] = None
    species_id: str
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    discovery_method: str = Field(default="field_survey")


class TreeResponse(BaseModel):
    """Schema for tree response."""

    id: str
    tree_tag: Optional[str]
    species_scientific_name: Optional[str]
    species_common_name: Optional[str]
    species_code: Optional[str]
    location_name: Optional[str]
    position: Optional[Dict[str, Any]]  # GeoJSON point
    discovery_date: Optional[date]
    discovery_method: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TreeMeasurementCreate(BaseModel):
    """Schema for creating tree measurements."""

    measurement_date: Optional[datetime] = None
    height_m: Optional[float] = Field(None, gt=0)
    dbh_cm: Optional[float] = Field(None, gt=0)
    crown_width_m: Optional[float] = Field(None, gt=0)
    crown_height_m: Optional[float] = Field(None, gt=0)
    health_status: Optional[str] = None
    measurement_method: str = Field(default="manual")
    measurement_quality: str = Field(default="B", pattern="^[A-D]$")
    notes: Optional[str] = None
    measured_by: Optional[str] = None


class TreeMeasurementResponse(BaseModel):
    """Schema for tree measurement response."""

    id: str
    measurement_date: datetime
    height_m: Optional[float]
    dbh_cm: Optional[float]
    crown_width_m: Optional[float]
    crown_height_m: Optional[float]
    health_status: Optional[str]
    measurement_method: Optional[str]
    measurement_quality: Optional[str]
    notes: Optional[str]
    measured_by: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class TreeDetailResponse(TreeResponse):
    """Schema for detailed tree response with measurements."""

    location_id: str
    measurements: List[TreeMeasurementResponse] = []
