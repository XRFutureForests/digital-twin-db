"""Tree models."""

from sqlalchemy import Column, String, Date, DateTime, Integer, Numeric, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from geoalchemy2 import Geometry
import uuid

from .base import Base, TimestampMixin


class Tree(Base, TimestampMixin):
    """Tree model for individual trees."""

    __tablename__ = "trees"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True))
    tree_tag = Column(String(50))
    species_id = Column(UUID(as_uuid=True))
    position = Column(Geometry("POINT", srid=4326), nullable=False)
    discovery_date = Column(Date, server_default=func.current_date())
    discovery_method = Column(String(50), default="field_survey")


class TreeMeasurement(Base):
    """Tree measurement model for tracking growth and health."""

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
