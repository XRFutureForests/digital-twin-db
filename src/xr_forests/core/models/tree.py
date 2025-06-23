"""Tree models."""

from sqlalchemy import (
    Column,
    String,
    DateTime,
    Integer,
    Numeric,
    Text,
    Boolean,
    ForeignKey,
    Date,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import relationship
from geoalchemy2 import Geometry
import uuid

from .base import Base, TimestampMixin


class TreeStatus(Base):
    """Tree status reference table (merged from HealthStatus and LiveStatusTypes)."""

    __tablename__ = "tree_status"

    id = Column(Integer, primary_key=True)
    status_name = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class VariantTypes(Base):
    """Variant types reference table."""

    __tablename__ = "variant_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(String(100), nullable=False, unique=True)
    description = Column(Text)


class Scenarios(Base, TimestampMixin):
    """Scenarios model for modeling scenarios."""

    __tablename__ = "scenarios"

    id = Column(Integer, primary_key=True)
    scenario_name = Column(String(200), nullable=False)
    created_by_user_id = Column(Integer)
    scenario_parameters = Column(JSONB)


class Tree(Base, TimestampMixin):
    """Tree model for base tree records."""

    __tablename__ = "trees"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    location_id = Column(UUID(as_uuid=True), ForeignKey("locations.id"))
    species_id = Column(UUID(as_uuid=True), ForeignKey("species.id"))
    tree_tag = Column(String(50))  # Field identification tag
    position = Column(Geometry("POINT", srid=4326), nullable=False)
    discovery_date = Column(Date, default=func.current_date())
    discovery_method = Column(String(50), default="field_survey")

    # Relationships
    # species = relationship("Species")
    # location = relationship("Location")


class TreeVariants(Base, TimestampMixin):
    """Tree variants model for scenario-based modeling."""

    __tablename__ = "tree_variants"

    id = Column(Integer, primary_key=True)
    tree_id = Column(Integer, ForeignKey("trees.id"), nullable=True)  # NULL if new tree in scenario
    scenario_id = Column(Integer, ForeignKey("scenarios.id"))
    parent_variant_id = Column(Integer, ForeignKey("tree_variants.id"), nullable=True)
    species_id = Column(Integer, ForeignKey("species.id"))
    variant_timestamp = Column(DateTime(timezone=True), nullable=False)
    height_m = Column(Numeric(5, 2))
    dbh_cm = Column(Numeric(5, 2))
    crown_width_m = Column(Numeric(5, 2))
    crown_base_height_m = Column(Numeric(5, 2))  # Height to lowest live branch
    crown_volume_m3 = Column(Numeric(8, 3))  # 3D crown volume
    crown_density_percent = Column(Numeric(5, 2))  # Foliage density within crown
    volume_m3 = Column(Numeric(8, 3))
    tree_status_id = Column(Integer, ForeignKey("tree_status.id"))
    position = Column(Geometry("POINT", srid=4326))  # PostGIS point geometry (plot coordinates)
    absolute_position = Column(
        Geometry("POINT", srid=4326)
    )  # PostGIS point geometry (GPS coordinates)
    variant_type_id = Column(Integer, ForeignKey("variant_types.id"))
    time_delta_yrs = Column(
        Numeric(5, 2)
    )  # Time passed since parent state (years) - for growth simulations
    model_type = Column(String(200))  # For growth simulations: model used
    model_parameters = Column(JSONB)  # JSON: model-specific parameters used
    environmental_snapshot_id = Column(Integer, ForeignKey("environmental_snapshots.id"))
    created_by = Column(String(200))  # User or system that created this variant
    notes = Column(Text)

    # Relationships
    tree = relationship("Tree")
    scenario = relationship("Scenarios")
    parent_variant = relationship("TreeVariants", remote_side=[id])
    species = relationship("Species")
    tree_status = relationship("TreeStatus")
    variant_type = relationship("VariantTypes")


class TreeStructures(Base, TimestampMixin):
    """Tree structures model for 3D structural representations."""

    __tablename__ = "tree_structures"

    id = Column(Integer, primary_key=True)
    tree_variant_id = Column(Integer, ForeignKey("tree_variants.id"))
    structure_type = Column(String(100))  # Direct field instead of FK to removed StructureTypes
    file_path = Column(String(500))  # Path to model file (if any)
    structure_data = Column(JSONB)  # JSON or string (e.g. L-system, latent vector, QSM params)
    generation_date = Column(DateTime(timezone=True))
    software = Column(String(200))  # Tool or method used
    metadata = Column(JSONB)  # Additional parameters

    # Relationships
    tree_variant = relationship("TreeVariants")


class StructureBranches(Base):
    """Structure branches model for detailed branch geometry."""

    __tablename__ = "structure_branches"

    id = Column(Integer, primary_key=True)
    structure_id = Column(Integer, ForeignKey("tree_structures.id"))
    parent_branch_id = Column(
        Integer, ForeignKey("structure_branches.id")
    )  # Self-reference for tree hierarchy
    branch_path = Column(String(500))  # Materialized path (/1/3/7/) for efficient queries
    branch_order = Column(Integer)  # 1=primary, 2=secondary, etc.
    branch_depth = Column(Integer)  # Distance from trunk
    length_m = Column(Numeric(6, 3))
    base_diameter_cm = Column(Numeric(5, 2))
    tip_diameter_cm = Column(Numeric(5, 2))
    direction_deg = Column(Numeric(5, 2))  # Azimuth direction (0-360°)
    inclination_deg = Column(Numeric(5, 2))  # Angle from vertical (-90 to 90°)
    branch_angle_deg = Column(Numeric(5, 2))  # Angle from parent (0-180°)
    start_height_m = Column(Numeric(6, 3))  # Height on parent where branch starts
    geometry = Column(JSONB)  # JSON: 3D geometry data

    # Relationships
    structure = relationship("TreeStructures")
    parent_branch = relationship("StructureBranches", remote_side=[id])
