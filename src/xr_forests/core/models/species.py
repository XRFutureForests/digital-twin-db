"""
Species model for tree species lookup table
"""
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import relationship
from xr_forests.database.connection import Base


class Species(Base):
    __tablename__ = "species"
    
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False, unique=True)
    scientific_name = Column(String(150), nullable=False)
    
    # Relationship
    trees = relationship("Tree", back_populates="species")
