"""Sensor and environmental models."""

from sqlalchemy import Column, String, Date, DateTime, Integer, Numeric, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from geoalchemy2 import Geometry
import uuid

from .base import Base, TimestampMixin


class EnvironmentSensor(Base, TimestampMixin):
    """Environmental sensor model."""

    __tablename__ = "environment_sensors"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True))
    sensor_type_id = Column(Integer)
    sensor_name = Column(String(100), nullable=False)
    position = Column(Geometry("POINT", srid=4326))
    installation_date = Column(Date)
    status = Column(String(20), default="active")
    last_reading_at = Column(DateTime(timezone=True))


class SensorReading(Base):
    """Sensor reading model."""

    __tablename__ = "sensor_readings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sensor_id = Column(UUID(as_uuid=True))
    reading_timestamp = Column(DateTime(timezone=True), nullable=False)
    value = Column(Numeric(10, 4), nullable=False)
    quality_flag = Column(String(1), default="A")
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class EnvironmentalSnapshot(Base, TimestampMixin):
    """Environmental snapshot model for aggregated readings."""

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
