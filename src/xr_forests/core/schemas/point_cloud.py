"""Point cloud schemas."""

from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class PointCloudResponse(BaseModel):
    """Schema for point cloud response."""

    id: str
    file_name: str
    scan_date: datetime
    processing_status: Optional[str]
    sensor_name: Optional[str]
    location_name: Optional[str]
    point_count: Optional[int]
    file_size_mb: Optional[float]
    scan_resolution_m: Optional[float]
    created_at: datetime

    class Config:
        from_attributes = True
