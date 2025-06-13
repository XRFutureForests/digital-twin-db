from sqlalchemy import (
    Column,
    String,
    DateTime,
    Integer,
    Numeric,
    Text,
    Date,
    BigInteger,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func
from geoalchemy2 import Geometry
from database import Base
import uuid

# =====================================================
# LOCATION MODEL
# =====================================================


class Location(Base):
    __tablename__ = "locations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_name = Column(String(200), nullable=False)
    description = Column(Text)
    plot_boundary = Column(Geometry("POLYGON", srid=4326))
    center_point = Column(Geometry("POINT", srid=4326))
    elevation_m = Column(Numeric(8, 2))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


# =====================================================
# SPECIES MODEL
# =====================================================


class Species(Base):
    __tablename__ = "species"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    scientific_name = Column(String(200), nullable=False, unique=True)
    common_name = Column(String(200))
    species_code = Column(String(10), unique=True)
    max_height_m = Column(Numeric(5, 2))
    longevity_years = Column(Integer)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


# =====================================================
# TREE MODELS
# =====================================================


class Tree(Base):
    __tablename__ = "trees"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True))
    tree_tag = Column(String(50))
    species_id = Column(UUID(as_uuid=True))
    position = Column(Geometry("POINT", srid=4326), nullable=False)
    discovery_date = Column(Date, server_default=func.current_date())
    discovery_method = Column(String(50), default="field_survey")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TreeMeasurement(Base):
    __tablename__ = "tree_measurements"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tree_id = Column(UUID(as_uuid=True))
    measurement_date = Column(DateTime(timezone=True), nullable=False)
    height_m = Column(Numeric(5, 2))
    dbh_cm = Column(Numeric(5, 2))
    crown_width_m = Column(Numeric(5, 2))
    crown_height_m = Column(Numeric(5, 2))
    health_status_id = Column(Integer)
    measurement_method = Column(String(50), default="manual")
    measurement_quality = Column(String(1), default="B")
    notes = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    measured_by = Column(String(100))


# =====================================================
# POINT CLOUD MODELS
# =====================================================


class PointCloud(Base):
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
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    point_cloud_metadata = Column(JSONB)


class ProcessingJob(Base):
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
    created_at = Column(DateTime(timezone=True), server_default=func.now())


# =====================================================
# ENVIRONMENTAL MODELS
# =====================================================


class EnvironmentSensor(Base):
    __tablename__ = "environment_sensors"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True))
    sensor_type_id = Column(Integer)
    sensor_name = Column(String(100), nullable=False)
    position = Column(Geometry("POINT", srid=4326))
    installation_date = Column(Date)
    status = Column(String(20), default="active")
    last_reading_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class SensorReading(Base):
    __tablename__ = "sensor_readings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sensor_id = Column(UUID(as_uuid=True))
    reading_timestamp = Column(DateTime(timezone=True), nullable=False)
    value = Column(Numeric(10, 4), nullable=False)
    quality_flag = Column(String(1), default="A")
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class EnvironmentalSnapshot(Base):
    __tablename__ = "environmental_snapshots"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True))
    snapshot_timestamp = Column(DateTime(timezone=True), nullable=False)
    avg_temperature_c = Column(Numeric(5, 2))
    avg_humidity_percent = Column(Numeric(5, 2))
    avg_soil_moisture_percent = Column(Numeric(5, 2))
    total_precipitation_mm = Column(Numeric(6, 2))
    avg_light_intensity_lux = Column(Numeric(8, 2))
    avg_wind_speed_ms = Column(Numeric(4, 2))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
