"""Species model."""

from sqlalchemy import Column, String, Integer, Numeric, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
import uuid

from .base import Base


class Species(Base):
    """Species model for tree species."""

    __tablename__ = "species"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    scientific_name = Column(String(200), nullable=False, unique=True)
    common_name = Column(String(200))
    species_code = Column(String(10), unique=True)
    max_height_m = Column(Numeric(5, 2))
    longevity_years = Column(Integer)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
