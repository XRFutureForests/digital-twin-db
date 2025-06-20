"""Point cloud models."""

from sqlalchemy import Column, String, DateTime, Integer, Numeric, Text, BigInteger, ForeignKey
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import relationship
from geoalchemy2 import Geometry

from .base import Base, TimestampMixin


class ProcessingStatusTypes(Base):
    """Processing status types reference table."""

    __tablename__ = "processing_status_types"

    id = Column(Integer, primary_key=True)
    status_name = Column(String(50), nullable=False, unique=True)  # Raw, Segmented, Classified
    description = Column(Text)


class SensorTypes(Base):
    """Sensor types reference table."""

    __tablename__ = "sensor_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(
        String(100), nullable=False, unique=True
    )  # TLS, UAV_LiDAR, Terrestrial_Camera, etc.
    description = Column(Text)


class PointClouds(Base, TimestampMixin):
    """Point clouds model for LiDAR scan metadata."""

    __tablename__ = "point_clouds"

    id = Column(Integer, primary_key=True)
    file_path = Column(String(500), nullable=False)  # Path/URI to raw point cloud file (.las, .laz)
    scan_date = Column(DateTime(timezone=True), nullable=False)
    location_id = Column(Integer, ForeignKey("locations.id"))
    sensor_type_id = Column(Integer, ForeignKey("sensor_types.id"))
    processing_status_type_id = Column(Integer, ForeignKey("processing_status_types.id"))
    quality_metrics = Column(JSONB)  # JSON: density, accuracy, coverage
    last_processed_date = Column(DateTime(timezone=True))
    point_count = Column(BigInteger)  # Total number of points in scan
    file_size_mb = Column(Numeric(10, 2))  # File size in megabytes
    scan_bounds = Column(
        Geometry("POLYGON", srid=4326)
    )  # PostGIS polygon defining scan coverage area
    scanner_model = Column(String(200))  # Model of LiDAR scanner used
    scan_parameters = Column(JSONB)  # JSON: scan settings, resolution, etc.
    created_by = Column(String(200))  # Operator or automated system

    # Relationships
    sensor_type = relationship("SensorTypes")
    processing_status_type = relationship("ProcessingStatusTypes")


class ProcessingJobs(Base, TimestampMixin):
    """Processing jobs model for job lifecycle management."""

    __tablename__ = "processing_jobs"

    id = Column(Integer, primary_key=True)
    job_type = Column(
        String(100), nullable=False
    )  # segmentation, classification, attribute_extraction, simulation
    input_id = Column(Integer)  # ID of input data (PointCloudID, SegmentationResultID, etc.)
    status = Column(
        String(50), default="queued"
    )  # queued, processing, completed, failed, cancelled
    submitted_at = Column(DateTime(timezone=True))
    started_at = Column(DateTime(timezone=True))
    completed_at = Column(DateTime(timezone=True))
    priority = Column(String(20), default="normal")  # low, normal, high
    queue_position = Column(Integer)
    progress_percent = Column(Numeric(5, 2), default=0)  # Processing progress (0-100)
    configuration = Column(JSONB)  # JSON: algorithm parameters and settings
    results = Column(JSONB)  # JSON: processing results and output references
    error_details = Column(Text)  # Error information if job failed
    submitted_by = Column(String(200))  # User or system that submitted job
    estimated_duration_minutes = Column(Integer)  # Estimated processing time
    actual_duration_minutes = Column(Integer)  # Actual processing time


class PointCloudSegmentationResults(Base, TimestampMixin):
    """Point cloud segmentation results model."""

    __tablename__ = "point_cloud_segmentation_results"

    id = Column(Integer, primary_key=True)
    point_cloud_id = Column(Integer, ForeignKey("point_clouds.id"))
    process_date = Column(DateTime(timezone=True), nullable=False)
    segmentation_algorithm = Column(String(200))  # Algorithm used (e.g., TreeLearn, 3D Forest)
    segment_data_ref = Column(JSONB)  # JSON: references to tree segments
    metrics = Column(JSONB)  # JSON: segmentation quality

    # Relationships
    point_cloud = relationship("PointClouds")


class TreeClassificationResults(Base, TimestampMixin):
    """Tree classification results model."""

    __tablename__ = "tree_classification_results"

    id = Column(Integer, primary_key=True)
    segmentation_result_id = Column(Integer, ForeignKey("point_cloud_segmentation_results.id"))
    process_date = Column(DateTime(timezone=True), nullable=False)
    classification_algorithm = Column(String(200))  # Algorithm used (e.g., ML model)
    model_version = Column(String(100))  # Version of classification model used
    confidence_threshold = Column(Numeric(3, 2))  # Minimum confidence threshold applied
    classified_trees_data = Column(
        JSONB
    )  # JSON: tree IDs, species IDs, probabilities, confidence scores
    feature_importance = Column(JSONB)  # JSON: importance of different morphological features
    overall_accuracy = Column(Numeric(3, 2))  # Overall classification accuracy score
    uncertain_classifications = Column(Integer)  # Number of trees with low confidence
    metrics = Column(JSONB)  # JSON: classification accuracy, model performance

    # Relationships
    segmentation_result = relationship("PointCloudSegmentationResults")
