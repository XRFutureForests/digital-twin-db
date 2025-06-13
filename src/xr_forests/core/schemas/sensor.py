"""Sensor schemas."""

from pydantic import BaseModel
from typing import Optional, Dict, Any
from datetime import datetime, date


class SensorResponse(BaseModel):
    """Schema for sensor response."""

    id: str
    sensor_name: str
    sensor_type: Optional[str]
    measurement_unit: Optional[str]
    location_name: Optional[str]
    position: Optional[Dict[str, Any]]  # GeoJSON point
    installation_date: Optional[date]
    status: Optional[str]
    last_reading_at: Optional[datetime]

    class Config:
        from_attributes = True


class SensorReadingResponse(BaseModel):
    """Schema for sensor reading response."""

    id: str
    sensor_name: str
    reading_timestamp: datetime
    value: float
    measurement_unit: Optional[str]
    quality_flag: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True
