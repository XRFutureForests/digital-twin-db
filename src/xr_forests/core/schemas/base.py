"""
Base schemas and common Pydantic models
"""

from pydantic import BaseModel


class BaseResponse(BaseModel):
    """Base response model with common configuration"""

    class Config:
        from_attributes = True
