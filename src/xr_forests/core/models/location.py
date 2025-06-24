"""
Location model for forest locations lookup table
"""
from sqlalchemy import Column, Integer, String, Float
from sqlalchemy.orm import relationship
from xr_forests.database.connection import Base


class Location(Base):
    __tablename__ = "locations"
    
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    
    # Relationships
    trees = relationship("Tree", back_populates="location")
