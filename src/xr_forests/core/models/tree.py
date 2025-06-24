"""
Tree model for individual tree records
"""

from datetime import datetime
from enum import Enum
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from xr_forests.database.connection import Base


class TreeStatus(str, Enum):
    """Tree health status enumeration"""

    HEALTHY = "healthy"
    STRESSED = "stressed"
    DISEASED = "diseased"
    DEAD = "dead"


class Tree(Base):
    __tablename__ = "trees"

    id = Column(Integer, primary_key=True)
    height = Column(Float, nullable=False)  # in meters
    diameter = Column(Float, nullable=False)  # in centimeters
    status = Column(String(20), nullable=False, default=TreeStatus.HEALTHY)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Foreign keys
    species_id = Column(Integer, ForeignKey("species.id"), nullable=False)
    location_id = Column(Integer, ForeignKey("locations.id"), nullable=False)

    # Relationships
    species = relationship("Species", back_populates="trees")
    location = relationship("Location", back_populates="trees")
