from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime, date
from enum import Enum

# =====================================================
# LOCATION SCHEMAS
# =====================================================


class LocationCreate(BaseModel):
    location_name: str = Field(..., max_length=200)
    description: Optional[str] = None
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    elevation_m: Optional[float] = None


class LocationResponse(BaseModel):
    id: str
    location_name: str
    description: Optional[str]
    elevation_m: Optional[float]
    center_point: Optional[Dict[str, Any]]  # GeoJSON point
    created_at: datetime
    updated_at: datetime


# =====================================================
# SPECIES SCHEMAS
# =====================================================


class SpeciesResponse(BaseModel):
    id: str
    scientific_name: str
    common_name: Optional[str]
    species_code: Optional[str]
    max_height_m: Optional[float]
    longevity_years: Optional[int]
    created_at: datetime


# =====================================================
# TREE SCHEMAS
# =====================================================


class TreeCreate(BaseModel):
    location_id: str
    tree_tag: Optional[str] = None
    species_id: str
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    discovery_method: str = Field(default="field_survey")


class TreeResponse(BaseModel):
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


class TreeMeasurementCreate(BaseModel):
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


class TreeDetailResponse(TreeResponse):
    location_id: str
    measurements: List[TreeMeasurementResponse] = []


# =====================================================
# POINT CLOUD SCHEMAS
# =====================================================


class PointCloudResponse(BaseModel):
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


# =====================================================
# ENVIRONMENTAL SCHEMAS
# =====================================================


class SensorResponse(BaseModel):
    id: str
    sensor_name: str
    sensor_type: Optional[str]
    measurement_unit: Optional[str]
    location_name: Optional[str]
    position: Optional[Dict[str, Any]]  # GeoJSON point
    installation_date: Optional[date]
    status: Optional[str]
    last_reading_at: Optional[datetime]


class SensorReadingResponse(BaseModel):
    id: str
    sensor_name: str
    reading_timestamp: datetime
    value: float
    measurement_unit: Optional[str]
    quality_flag: Optional[str]
    created_at: datetime


# =====================================================
# PROCESSING JOB SCHEMAS
# =====================================================


class ProcessingJobResponse(BaseModel):
    id: str
    job_type: str
    status: str
    progress_percent: int
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    error_message: Optional[str]
    created_at: datetime
