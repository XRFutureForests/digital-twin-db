"""Point cloud schemas based on data contracts."""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum


# Enums for point cloud processing
class SensorType(str, Enum):
    TLS = "TLS"  # Terrestrial Laser Scanner
    UAV_LIDAR = "UAV_LiDAR"  # UAV-mounted LiDAR
    ALS = "ALS"  # Airborne Laser Scanner
    MLS = "MLS"  # Mobile Laser Scanner
    TERRESTRIAL_CAMERA = "Terrestrial_Camera"


class ProcessingStatus(str, Enum):
    RAW = "Raw"
    SEGMENTED = "Segmented"
    CLASSIFIED = "Classified"


class JobStatus(str, Enum):
    QUEUED = "queued"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class JobPriority(str, Enum):
    LOW = "low"
    NORMAL = "normal"
    HIGH = "high"


class NoiseLevel(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


# Core data types
class BoundingBox(BaseModel):
    """3D bounding box for point cloud data."""

    min_x: float
    min_y: float
    min_z: Optional[float] = None
    max_x: float
    max_y: float
    max_z: Optional[float] = None
    coordinate_system: str = "EPSG:4326"


class FileReference(BaseModel):
    """File reference for point cloud outputs."""

    file_id: int
    file_path: str
    file_name: str
    file_type: str  # MIME type
    file_size_bytes: int
    checksum_md5: Optional[str] = None
    created_date: datetime
    access_permissions: str = "private"


# Point cloud metadata schemas
class PointCloudMetadataBase(BaseModel):
    """Base point cloud metadata."""

    scan_date: datetime
    sensor_type: SensorType
    scanner_model: Optional[str] = None
    scan_resolution_cm: Optional[float] = Field(None, gt=0)
    coordinate_system: str = "EPSG:4326"
    quality_metrics: Optional[Dict[str, Any]] = None


class PointCloudCreate(PointCloudMetadataBase):
    """Schema for creating point cloud records."""

    location_id: int
    file_path: str = Field(..., max_length=500)
    scan_parameters: Optional[Dict[str, Any]] = None
    created_by: Optional[str] = None


class PointCloudUpdate(BaseModel):
    """Schema for updating point cloud records."""

    processing_status: Optional[ProcessingStatus] = None
    quality_metrics: Optional[Dict[str, Any]] = None
    last_processed_date: Optional[datetime] = None
    point_count: Optional[int] = Field(None, gt=0)
    file_size_mb: Optional[float] = Field(None, gt=0)
    scan_bounds: Optional[BoundingBox] = None


class PointCloudResponse(PointCloudMetadataBase):
    """Schema for point cloud response."""

    id: int
    location_id: int
    file_path: str
    processing_status_type_id: Optional[int]
    last_processed_date: Optional[datetime]
    point_count: Optional[int]
    file_size_mb: Optional[float]
    scan_bounds: Optional[BoundingBox]
    scan_parameters: Optional[Dict[str, Any]]
    created_by: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Processing job schemas
class ProcessingJobBase(BaseModel):
    """Base processing job schema."""

    job_type: str = Field(..., max_length=100)  # segmentation, classification, attribute_extraction
    priority: JobPriority = JobPriority.NORMAL
    configuration: Optional[Dict[str, Any]] = None


class ProcessingJobCreate(ProcessingJobBase):
    """Schema for creating processing jobs."""

    input_id: int  # Point cloud ID or other input data ID
    submitted_by: Optional[str] = None
    estimated_duration_minutes: Optional[int] = None


class ProcessingJobUpdate(BaseModel):
    """Schema for updating processing jobs."""

    status: Optional[JobStatus] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    progress_percent: Optional[float] = Field(None, ge=0, le=100)
    results: Optional[Dict[str, Any]] = None
    error_details: Optional[str] = None
    actual_duration_minutes: Optional[int] = None


class ProcessingJobResponse(ProcessingJobBase):
    """Schema for processing job response."""

    id: int
    input_id: int
    status: JobStatus
    submitted_at: datetime
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    queue_position: Optional[int]
    progress_percent: float
    results: Optional[Dict[str, Any]]
    error_details: Optional[str]
    submitted_by: Optional[str]
    estimated_duration_minutes: Optional[int]
    actual_duration_minutes: Optional[int]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Segmentation job schemas
class SegmentationJobCreate(ProcessingJobCreate):
    """Schema for creating segmentation jobs."""

    job_type: str = "segmentation"


class SegmentationJobResponse(ProcessingJobResponse):
    """Schema for segmentation job response."""

    pass


# Classification job schemas
class ClassificationJobCreate(ProcessingJobCreate):
    """Schema for creating classification jobs."""

    job_type: str = "classification"


class ClassificationJobResponse(ProcessingJobResponse):
    """Schema for classification job response."""

    pass


# Query and search schemas
class PointCloudQuery(BaseModel):
    """Schema for point cloud queries."""

    location_id: Optional[int] = None
    sensor_type: Optional[SensorType] = None
    processing_status: Optional[ProcessingStatus] = None
    scan_date_range: Optional[tuple[datetime, datetime]] = None
    point_count_range: Optional[tuple[int, int]] = None
    quality_threshold: Optional[float] = None


class PointCloudSearchResponse(BaseModel):
    """Schema for point cloud search results."""

    total_count: int
    point_clouds: List[PointCloudResponse]
    search_parameters: PointCloudQuery

    class Config:
        from_attributes = True


# Data ingestion schemas
class PointCloudUpload(BaseModel):
    """Schema for point cloud file upload."""

    location_id: int
    metadata: PointCloudMetadataBase
    quality_metrics: Optional[Dict[str, Any]] = None


class UploadResponse(BaseModel):
    """Schema for upload response."""

    status: str
    pointcloud_id: int
    upload_timestamp: datetime
    file_size_mb: float
    point_count: Optional[int]
    processing_status: ProcessingStatus

    class Config:
        from_attributes = True


# Quality assessment schemas
class QualityAssessmentResponse(BaseModel):
    """Schema for quality assessment response."""

    id: str
    point_cloud_id: str
    assessment_date: datetime
    overall_quality_score: float
    completeness_score: float
    accuracy_score: float
    density_score: float
    noise_level: NoiseLevel
    assessment_method: str
    detailed_metrics: Optional[Dict[str, Any]] = None
    created_at: datetime

    class Config:
        from_attributes = True
