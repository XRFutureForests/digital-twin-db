"""
Point Cloud model for 3D scan metadata
"""

from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from xr_forests.core.models.base import Base


class PointCloud(Base):
    __tablename__ = "point_clouds"

    id = Column(Integer, primary_key=True)
    filename = Column(String(255), nullable=False)
    file_size = Column(Integer, nullable=False)  # in bytes
    point_count = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Foreign key
    location_id = Column(Integer, ForeignKey("locations.id"), nullable=False)

    # Relationship
    location = relationship("Location", back_populates="point_clouds")
