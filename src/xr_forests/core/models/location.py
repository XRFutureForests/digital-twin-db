"""Location model."""

from sqlalchemy import Column, String, Text, Numeric
from sqlalchemy.dialects.postgresql import UUID
from geoalchemy2 import Geometry
import uuid

from .base import Base, TimestampMixin


class Location(Base, TimestampMixin):
    """Location model for forest areas."""

    __tablename__ = "locations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_name = Column(String(200), nullable=False)
    description = Column(Text)
    plot_boundary = Column(Geometry("POLYGON", srid=4326))
    center_point = Column(Geometry("POINT", srid=4326))
    elevation_m = Column(Numeric(8, 2))
