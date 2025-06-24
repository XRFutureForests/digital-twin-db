"""
Point Cloud schemas for API request/response validation
"""

from datetime import datetime
from pydantic import BaseModel, Field
from xr_forests.core.schemas.base import BaseResponse


class PointCloudBase(BaseModel):
    filename: str = Field(..., max_length=255)
    file_size: int = Field(..., gt=0, description="File size in bytes")
    point_count: int = Field(..., gt=0, description="Number of points")


class PointCloudCreate(PointCloudBase):
    location_id: int


class PointCloudResponse(PointCloudBase, BaseResponse):
    id: int
    location_id: int
    created_at: datetime
