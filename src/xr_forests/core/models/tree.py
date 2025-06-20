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


class HealthStatus(Base):
    """Health status reference table."""

    __tablename__ = "health_status_types"

    id = Column(Integer, primary_key=True)
    status = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class PhenologyStatus(Base):
    """Phenology status reference table."""

    __tablename__ = "phenology_status"

    id = Column(Integer, primary_key=True)
    status = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class DataQualityTypes(Base):
    """Data quality types reference table."""

    __tablename__ = "data_quality_types"

    id = Column(Integer, primary_key=True)
    quality_type = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class LiveStatusTypes(Base):
    """Live status types reference table."""

    __tablename__ = "live_status_types"

    id = Column(Integer, primary_key=True)
    status_name = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class VariantTypes(Base):
    """Variant types reference table."""

    __tablename__ = "variant_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(String(100), nullable=False, unique=True)
    description = Column(Text)


class StructureTypes(Base):
    """Structure types reference table."""

    __tablename__ = "structure_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(String(100), nullable=False, unique=True)
    description = Column(Text)


class MicrohabitatTypes(Base):
    """Microhabitat types reference table."""

    __tablename__ = "microhabitat_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(String(100), nullable=False, unique=True)
    description = Column(Text)


class MicrohabitatSizes(Base):
    """Microhabitat sizes reference table."""

    __tablename__ = "microhabitat_sizes"

    id = Column(Integer, primary_key=True)
    size_name = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class MicrohabitatConditions(Base):
    """Microhabitat conditions reference table."""

    __tablename__ = "microhabitat_conditions"

    id = Column(Integer, primary_key=True)
    condition_name = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class StemQualityTypes(Base):
    """Stem quality types reference table."""

    __tablename__ = "stem_quality_types"

    id = Column(Integer, primary_key=True)
    quality_name = Column(String(50), nullable=False, unique=True)
    description = Column(Text)


class StemDefectTypes(Base):
    """Stem defect types reference table."""

    __tablename__ = "stem_defect_types"

    id = Column(Integer, primary_key=True)
    defect_name = Column(String(100), nullable=False, unique=True)
    description = Column(Text)


class CrownMorphologyTypes(Base):
    """Crown morphology types reference table."""

    __tablename__ = "crown_morphology_types"

    id = Column(Integer, primary_key=True)
    morphology_name = Column(String(100), nullable=False, unique=True)
    description = Column(Text)


class RootConditionTypes(Base):
    """Root condition types reference table."""

    __tablename__ = "root_condition_types"

    id = Column(Integer, primary_key=True)
    condition_name = Column(String(50), nullable=False, unique=True)
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
    live_status_type_id = Column(Integer, ForeignKey("live_status_types.id"))
    estimated_age_years = Column(Numeric(5, 1))  # Tree age estimation
    health_status_id = Column(Integer, ForeignKey("health_status.id"))
    position = Column(Geometry("POINT", srid=4326))  # PostGIS point geometry (plot coordinates)
    absolute_position = Column(
        Geometry("POINT", srid=4326)
    )  # PostGIS point geometry (GPS coordinates)
    local_density_trees_per_ha = Column(Numeric(8, 2))  # Tree density in immediate vicinity
    nearest_neighbor_distance_m = Column(Numeric(6, 2))  # Distance to nearest tree
    variant_type_id = Column(Integer, ForeignKey("variant_types.id"))
    time_delta_yrs = Column(
        Numeric(5, 2)
    )  # Time passed since parent state (years) - for growth simulations
    model_type = Column(String(200))  # For growth simulations: model used
    model_parameters = Column(JSONB)  # JSON: model-specific parameters used
    mortality_risk_prob = Column(Numeric(3, 2))  # For growth simulations: predicted mortality risk
    predicted_structure_data = Column(JSONB)  # For growth simulations: predicted structure data
    environmental_snapshot_id = Column(Integer, ForeignKey("environmental_snapshots.id"))
    created_by = Column(String(200))  # User or system that created this variant
    notes = Column(Text)

    # Relationships
    tree = relationship("Tree")
    scenario = relationship("Scenarios")
    parent_variant = relationship("TreeVariants", remote_side=[id])
    species = relationship("Species")
    live_status_type = relationship("LiveStatusTypes")
    health_status = relationship("HealthStatus")
    variant_type = relationship("VariantTypes")


class TreeStructures(Base, TimestampMixin):
    """Tree structures model for 3D structural representations."""

    __tablename__ = "tree_structures"

    id = Column(Integer, primary_key=True)
    tree_variant_id = Column(Integer, ForeignKey("tree_variants.id"))
    structure_type_id = Column(Integer, ForeignKey("structure_types.id"))
    file_path = Column(String(500))  # Path to model file (if any)
    structure_data = Column(JSONB)  # JSON or string (e.g. L-system, latent vector, QSM params)
    generation_date = Column(DateTime(timezone=True))
    software = Column(String(200))  # Tool or method used
    structure_metadata = Column(JSONB)  # Additional parameters

    # Relationships
    tree_variant = relationship("TreeVariants")
    structure_type = relationship("StructureTypes")


class StructureBranches(Base):
    """Structure branches model for detailed branch geometry."""

    __tablename__ = "structure_branches"

    id = Column(Integer, primary_key=True)
    structure_id = Column(Integer, ForeignKey("tree_structures.id"))
    length_m = Column(Numeric(6, 3))
    diameter_cm = Column(Numeric(5, 2))
    direction_deg = Column(Numeric(5, 2))  # Azimuth (horizontal direction in degrees)
    inclination_deg = Column(Numeric(5, 2))  # Inclination angle from vertical (degrees)
    start_height_m = Column(Numeric(6, 3))  # Height of branch start on parent (m)
    start_radius_cm = Column(Numeric(5, 2))  # Radius at branch base (cm)
    geometry = Column(JSONB)  # JSON/OBJ

    # Relationships
    structure = relationship("TreeStructures")


class StructureTwigs(Base):
    """Structure twigs model for fine-scale twig data."""

    __tablename__ = "structure_twigs"

    id = Column(Integer, primary_key=True)
    branch_id = Column(Integer, ForeignKey("structure_branches.id"))
    length_m = Column(Numeric(6, 3))
    diameter_cm = Column(Numeric(5, 2))
    direction_deg = Column(Numeric(5, 2))
    inclination_deg = Column(Numeric(5, 2))
    start_height_m = Column(Numeric(6, 3))
    geometry = Column(JSONB)  # JSON/OBJ

    # Relationships
    branch = relationship("StructureBranches")


class StructureLeaves(Base):
    """Structure leaves model for individual leaf data."""

    __tablename__ = "structure_leaves"

    id = Column(Integer, primary_key=True)
    twig_id = Column(Integer, ForeignKey("structure_twigs.id"))
    geometry = Column(JSONB)  # JSON/OBJ
    phenology_status_id = Column(Integer, ForeignKey("phenology_status.id"))
    direction_deg = Column(Numeric(5, 2))
    inclination_deg = Column(Numeric(5, 2))
    start_height_m = Column(Numeric(6, 3))
    color = Column(String(50))  # Optional: leaf color for phenology/health

    # Relationships
    twig = relationship("StructureTwigs")
    phenology_status = relationship("PhenologyStatus")


class TreeMicrohabitats(Base, TimestampMixin):
    """Tree microhabitats model for biodiversity features."""

    __tablename__ = "tree_microhabitats"

    id = Column(Integer, primary_key=True)
    tree_variant_id = Column(Integer, ForeignKey("tree_variants.id"))
    microhabitat_type_id = Column(Integer, ForeignKey("microhabitat_types.id"))
    height_m = Column(Numeric(6, 3))  # Height of microhabitat feature
    size_id = Column(Integer, ForeignKey("microhabitat_sizes.id"))
    condition_id = Column(Integer, ForeignKey("microhabitat_conditions.id"))
    description = Column(Text)  # Detailed description of microhabitat
    first_observed = Column(DateTime(timezone=True))  # When microhabitat was first noted

    # Relationships
    tree_variant = relationship("TreeVariants")
    microhabitat_type = relationship("MicrohabitatTypes")
    size = relationship("MicrohabitatSizes")
    condition = relationship("MicrohabitatConditions")


class TreeQualityAssessment(Base, TimestampMixin):
    """Tree quality assessment model for comprehensive quality metrics."""

    __tablename__ = "tree_quality_assessment"

    id = Column(Integer, primary_key=True)
    tree_variant_id = Column(Integer, ForeignKey("tree_variants.id"))
    height_quality_id = Column(Integer, ForeignKey("data_quality_types.id"))
    dbh_quality_id = Column(Integer, ForeignKey("data_quality_types.id"))
    crown_width_quality_id = Column(Integer, ForeignKey("data_quality_types.id"))
    volume_quality_id = Column(Integer, ForeignKey("data_quality_types.id"))
    stem_straightness_index = Column(Numeric(3, 2))  # 0-1: trunk straightness quality
    stem_quality_type_id = Column(Integer, ForeignKey("stem_quality_types.id"))
    knot_frequency_per_m = Column(Numeric(5, 2))  # Number of knots per meter
    stem_defect_type_id = Column(Integer, ForeignKey("stem_defect_types.id"))
    crown_morphology_type_id = Column(Integer, ForeignKey("crown_morphology_types.id"))
    crown_height_ratio = Column(Numeric(3, 2))  # Crown height / total height
    root_condition_type_id = Column(Integer, ForeignKey("root_condition_types.id"))
    timber_value_index = Column(Numeric(3, 2))  # 0-1: estimated timber quality
    quality_notes = Column(Text)  # Additional quality observations
    assessment_date = Column(DateTime(timezone=True))  # When quality assessment was performed
    assessed_by = Column(String(200))  # Personnel or method that performed assessment

    # Relationships
    tree_variant = relationship("TreeVariants")
    height_quality = relationship("DataQualityTypes", foreign_keys=[height_quality_id])
    dbh_quality = relationship("DataQualityTypes", foreign_keys=[dbh_quality_id])
    crown_width_quality = relationship("DataQualityTypes", foreign_keys=[crown_width_quality_id])
    volume_quality = relationship("DataQualityTypes", foreign_keys=[volume_quality_id])
    stem_quality_type = relationship("StemQualityTypes")
    stem_defect_type = relationship("StemDefectTypes")
    crown_morphology_type = relationship("CrownMorphologyTypes")
    root_condition_type = relationship("RootConditionTypes")
