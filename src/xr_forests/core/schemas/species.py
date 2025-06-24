"""
Species schemas for API request/response validation
"""

from pydantic import BaseModel, Field


class SpeciesBase(BaseModel):
    name: str = Field(..., max_length=100)
    scientific_name: str = Field(..., max_length=150)


class SpeciesCreate(SpeciesBase):
    pass


class SpeciesResponse(SpeciesBase):
    id: int

    class Config:
        from_attributes = True
