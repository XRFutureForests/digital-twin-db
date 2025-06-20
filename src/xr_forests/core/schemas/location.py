"""Location schemas."""

from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
from datetime import datetime


class BaseQuery(BaseModel):
    """Base query schema with pagination."""

    limit: int = Field(100, ge=1, le=1000, description="Maximum number of results")
    offset: int = Field(0, ge=0, description="Number of results to skip")


class GeoJSONPoint(BaseModel):
    """GeoJSON Point geometry."""

    type: str = Field("Point", description="GeoJSON type")
    coordinates: List[float] = Field(..., description="[longitude, latitude]")


class GeoJSONPolygon(BaseModel):
    """GeoJSON Polygon geometry."""

    type: str = Field("Polygon", description="GeoJSON type")
    coordinates: List[List[List[float]]] = Field(
        ..., description="Polygon coordinates [[[lon, lat], ...]]"
    )


class LocationCreate(BaseModel):
    """Schema for creating a location."""

    location_name: str = Field(..., max_length=200)
    description: Optional[str] = None
    plot_boundary: Optional[GeoJSONPolygon] = None
    center_point: Optional[GeoJSONPoint] = None


class LocationUpdate(BaseModel):
    """Schema for updating a location."""

    location_name: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    plot_boundary: Optional[GeoJSONPolygon] = None
    center_point: Optional[GeoJSONPoint] = None


class LocationQuery(BaseQuery):
    """Schema for location query parameters."""

    location_name: Optional[str] = None
    description: Optional[str] = None
    min_elevation: Optional[float] = None
    max_elevation: Optional[float] = None
    within_bounds: Optional[str] = None  # GeoJSON polygon for spatial queries


class LocationResponse(BaseModel):
    """Schema for location response."""

    id: str
    location_name: str
    description: Optional[str]
    elevation_m: Optional[float]
    plot_boundary: Optional[GeoJSONPolygon]
    center_point: Optional[GeoJSONPoint]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
