"""Point cloud models."""

from sqlalchemy import Column, String, DateTime, Integer, Numeric, Text, BigInteger
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func
from geoalchemy2 import Geometry
import uuid

from .base import Base, TimestampMixin


class PointCloudScan(Base, TimestampMixin):
    """Point cloud scan model."""

    __tablename__ = "point_clouds"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True))
    file_path = Column(String(500), nullable=False)
    file_name = Column(String(255), nullable=False)
    scan_date = Column(DateTime(timezone=True), nullable=False)
    sensor_type_id = Column(Integer)
    processing_status_id = Column(Integer, default=1)
    point_count = Column(BigInteger)
    file_size_mb = Column(Numeric(10, 2))
    scan_bounds = Column(Geometry("POLYGON", srid=4326))
    scan_resolution_m = Column(Numeric(6, 4))
    point_cloud_metadata = Column(JSONB)


class ProcessingJob(Base, TimestampMixin):
    """Processing job model for point cloud processing."""

    __tablename__ = "processing_jobs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    point_cloud_id = Column(UUID(as_uuid=True))
    job_type = Column(String(50), nullable=False)
    status = Column(String(20), default="queued")
    started_at = Column(DateTime(timezone=True))
    completed_at = Column(DateTime(timezone=True))
    progress_percent = Column(Integer, default=0)
    error_message = Column(Text)
    result_data = Column(JSONB)
