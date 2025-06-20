"""Sensor schemas."""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class SensorQuery(BaseModel):
    """Schema for sensor query parameters."""

    location_id: Optional[str] = None
    sensor_type: Optional[str] = None
    status: Optional[str] = None
    limit: int = 100
    offset: int = 0


class SensorResponse(BaseModel):
    """Schema for sensor response."""

    id: str
    sensor_id: str
    location_id: str
    sensor_type: str
    status: str
    battery_level: Optional[float]
    last_reading_time: Optional[datetime]
    position: Optional[dict]  # GeoJSON point
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class SensorReadingResponse(BaseModel):
    """Schema for sensor reading response."""

    id: str
    sensor_id: str
    parameter_type: str
    value: float
    unit: str
    quality_grade: Optional[str]
    timestamp: datetime
    created_at: datetime

    class Config:
        from_attributes = True
