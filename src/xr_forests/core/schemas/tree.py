"""Tree schemas based on data contracts."""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any, Union
from datetime import datetime
from enum import Enum


# Enums for standardized values
class DataQuality(str, Enum):
    A = "A"  # Excellent
    B = "B"  # Good
    C = "C"  # Acceptable
    D = "D"  # Poor


class MeasurementSource(str, Enum):
    DIRECT_MEASUREMENT = "Direct_Measurement"
    POINT_CLOUD_DERIVED = "Point_Cloud_Derived"
    MODEL_ESTIMATED = "Model_Estimated"


class TreeStatus(str, Enum):
    HEALTHY = "healthy"
    STRESSED = "stressed"
    DECLINING = "declining"
    DEAD = "dead"
    DECAYING = "decaying"
    SNAG = "snag"


class VariantType(str, Enum):
    ORIGINAL = "Original"
    GROWTH_SIMULATION = "Growth_Simulation"
    SPECIES_REPLACEMENT = "Species_Replacement"
    MANUAL_EDIT = "Manual_Edit"
    NEW = "New"


class StructureType(str, Enum):
    QSM = "QSM"
    L_SYSTEM = "L-System"
    MANUAL = "Manual"
    PROCEDURAL = "Procedural"


# Core Data Types
class Coordinates(BaseModel):
    """Geographic coordinates with validation."""

    latitude: float = Field(..., ge=-90, le=90, description="Decimal degrees, WGS84")
    longitude: float = Field(..., ge=-180, le=180, description="Decimal degrees, WGS84")
    elevation_m: Optional[float] = Field(None, description="Meters above sea level")
    coordinate_system: str = Field(default="EPSG:4326")


class QualityMetrics(BaseModel):
    """Quality and validation metrics."""

    overall_grade: DataQuality
    confidence_score: float = Field(..., ge=0, le=1, description="Range: [0, 1]")
    measurement_source: MeasurementSource
    validation_method: Optional[str] = None
    anomaly_flags: Optional[List[str]] = None


# Species schemas
class SpeciesBase(BaseModel):
    """Base species schema."""

    scientific_name: str = Field(..., max_length=200)
    common_name: Optional[str] = Field(None, max_length=200)
    growth_characteristics: Optional[Dict[str, Any]] = None


class SpeciesCreate(SpeciesBase):
    """Schema for creating species."""

    pass


class SpeciesResponse(SpeciesBase):
    """Schema for species response."""

    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Tree measurements schemas
class TreeMeasurements(BaseModel):
    """Tree measurements with validation."""

    height_m: float = Field(..., gt=0.1, le=130.0, description="Realistic tree height range")
    height_quality: QualityMetrics

    dbh_cm: float = Field(..., ge=1.0, le=400.0, description="Diameter at breast height")
    dbh_quality: QualityMetrics

    crown_width_m: float = Field(..., ge=0.5, le=50.0, description="Crown diameter range")
    crown_width_quality: QualityMetrics

    crown_height_m: Optional[float] = Field(None, gt=0.1, description="Cannot exceed tree height")
    crown_base_height_m: Optional[float] = Field(
        None, ge=0.0, description="Height to lowest live branch"
    )

    volume_m3: Optional[float] = Field(None, ge=0.001, le=200.0, description="Tree volume range")
    volume_quality: Optional[QualityMetrics] = None

    biomass_kg: Optional[float] = Field(None, ge=0.1, le=50000.0, description="Tree biomass range")
    biomass_quality: Optional[QualityMetrics] = None

    measurement_date: datetime


class TreeHealth(BaseModel):
    """Tree health assessment."""

    vitality: TreeStatus
    health_score: float = Field(..., ge=0, le=100)
    disease_indicators: List[str] = []
    pest_indicators: List[str] = []
    environmental_stress_indicators: List[str] = []
    assessment_date: datetime
    assessment_method: str = "field_survey"


# Tree structure schemas
class BranchStructure(BaseModel):
    """Branch structure data."""

    branch_id: int
    parent_branch_id: Optional[int] = None
    length_m: float = Field(..., gt=0)
    base_diameter_cm: float = Field(..., gt=0)
    tip_diameter_cm: float = Field(..., gt=0)
    azimuth_deg: float = Field(..., ge=0, lt=360)
    inclination_deg: float = Field(..., ge=0, le=90)
    start_height_m: float = Field(..., ge=0)
    branch_order: int = Field(..., ge=1)
    leaf_area_m2: Optional[float] = None
    biomass_kg: Optional[float] = None


class TreeStructure(BaseModel):
    """Tree structure representation."""

    structure_id: int
    tree_variant_id: int
    structure_type: StructureType
    generation_date: datetime
    generation_method: str
    quality_metrics: QualityMetrics
    file_references: Optional[List[Dict[str, Any]]] = None


# Tree variant schemas
class TreeVariantBase(BaseModel):
    """Base tree variant schema."""

    species_id: int
    variant_timestamp: datetime
    measurements: TreeMeasurements
    health_status: Optional[TreeHealth] = None
    position: Optional[Coordinates] = None
    variant_type: VariantType
    notes: Optional[str] = None


class TreeVariantCreate(TreeVariantBase):
    """Schema for creating tree variants."""

    scenario_id: int
    tree_id: Optional[int] = None  # NULL if new tree in scenario
    parent_variant_id: Optional[int] = None


class TreeVariantUpdate(BaseModel):
    """Schema for updating tree variants."""

    measurements: Optional[TreeMeasurements] = None
    health_status: Optional[TreeHealth] = None
    position: Optional[Coordinates] = None
    notes: Optional[str] = None


class TreeVariantResponse(TreeVariantBase):
    """Schema for tree variant response."""

    id: int
    tree_id: Optional[int]
    scenario_id: int
    parent_variant_id: Optional[int]
    created_by: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Tree base schemas
class TreeBase(BaseModel):
    """Base tree schema."""

    location_id: int
    species_id: int
    tree_tag: Optional[str] = Field(None, max_length=50, description="Field identification tag")
    latitude: Optional[float] = Field(None, ge=-90, le=90, description="Decimal degrees, WGS84")
    longitude: Optional[float] = Field(None, ge=-180, le=180, description="Decimal degrees, WGS84")
    elevation_m: Optional[float] = Field(None, description="Meters above sea level")
    initial_capture_date: Optional[datetime] = None
    initial_height_m: Optional[float] = Field(None, gt=0)
    initial_dbh_cm: Optional[float] = Field(None, gt=0)
    initial_crown_width_m: Optional[float] = Field(None, gt=0)
    initial_volume_m3: Optional[float] = Field(None, gt=0)


class TreeCreate(TreeBase):
    """Schema for creating trees."""

    pass


class TreeResponse(TreeBase):
    """Schema for tree response."""

    id: str  # Changed to string to align with documentation
    health_status_id: Optional[int]
    point_cloud_id: Optional[int]
    created_at: datetime
    updated_at: datetime

    # Related data
    species: Optional[SpeciesResponse] = None
    variants: Optional[List[TreeVariantResponse]] = None

    class Config:
        from_attributes = True


class TreeDetailResponse(TreeResponse):
    """Schema for detailed tree response with measurements."""

    measurements: List["TreeMeasurementResponse"] = []


# Scenario schemas
class ScenarioBase(BaseModel):
    """Base scenario schema."""

    scenario_name: str = Field(..., max_length=200)
    scenario_parameters: Optional[Dict[str, Any]] = None


class ScenarioCreate(ScenarioBase):
    """Schema for creating scenarios."""

    created_by_user_id: Optional[int] = None


class ScenarioResponse(ScenarioBase):
    """Schema for scenario response."""

    id: int
    created_by_user_id: Optional[int]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Growth simulation schemas
class GrowthSimulationParameters(BaseModel):
    """Growth simulation parameters."""

    simulation_name: str
    start_date: datetime
    end_date: datetime
    growth_models: List[str]  # ["SILVA", "BALANCE", "iLand"]
    model_coupling: str = "sequential"
    climate_scenario: str = "current"
    model_parameters: Dict[str, Any] = {}
    output_frequency: str = "annual"
    include_uncertainty: bool = False


class GrowthSimulationResult(BaseModel):
    """Growth simulation result."""

    simulation_id: int
    tree_variant_id: int
    simulation_timestamp: datetime
    predicted_measurements: TreeMeasurements
    prediction_uncertainty: Optional[Dict[str, float]] = None
    model_outputs: List[Dict[str, Any]] = []
    model_confidence: float = Field(..., ge=0, le=1)
    validation_score: Optional[float] = None


# Additional schemas for API operations
class TreeUpdate(BaseModel):
    """Schema for updating trees."""

    species_id: Optional[int] = None
    tree_tag: Optional[str] = Field(None, max_length=50)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    elevation_m: Optional[float] = None
    initial_height_m: Optional[float] = Field(None, gt=0)
    initial_dbh_cm: Optional[float] = Field(None, gt=0)
    initial_crown_width_m: Optional[float] = Field(None, gt=0)
    initial_volume_m3: Optional[float] = Field(None, gt=0)
    initial_capture_date: Optional[datetime] = None


class TreeMeasurementCreate(BaseModel):
    """Schema for creating tree measurements."""

    measurement_date: datetime = Field(
        default_factory=datetime.now, description="Date of measurement"
    )
    height_m: Optional[float] = Field(None, gt=0.1, le=130.0)
    dbh_cm: Optional[float] = Field(None, ge=1.0, le=400.0)
    crown_width_m: Optional[float] = Field(None, ge=0.5, le=50.0)
    crown_height_m: Optional[float] = Field(None, gt=0.1)
    health_status: Optional[str] = None
    measurement_method: Optional[str] = None
    measurement_quality: Optional[str] = None
    notes: Optional[str] = None
    measured_by: Optional[str] = None


class TreeMeasurementResponse(BaseModel):
    """Schema for tree measurement response."""

    id: str
    measurement_date: datetime
    height_m: Optional[float]
    dbh_cm: Optional[float]
    crown_width_m: Optional[float]
    crown_height_m: Optional[float]
    health_status: Optional[str]
    measurement_method: Optional[str]
    measurement_quality: Optional[str]
    notes: Optional[str]
    measured_by: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class TreeHealthAssessmentCreate(BaseModel):
    """Schema for creating tree health assessments."""

    assessment_date: datetime = Field(
        default_factory=datetime.now, description="Date of assessment"
    )
    health_status: TreeStatus
    health_score: float = Field(..., ge=0, le=100)
    disease_indicators: List[str] = []
    pest_indicators: List[str] = []
    environmental_stress_indicators: List[str] = []
    assessment_method: str = "field_survey"
    assessed_by: Optional[str] = None
    notes: Optional[str] = None


class TreeHealthAssessmentResponse(BaseModel):
    """Schema for tree health assessment response."""

    id: str
    assessment_date: datetime
    health_status: TreeStatus
    health_score: float
    disease_indicators: List[str]
    pest_indicators: List[str]
    environmental_stress_indicators: List[str]
    assessment_method: str
    assessed_by: Optional[str]
    notes: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class TreeBulkImportCreate(BaseModel):
    """Schema for bulk import of trees."""

    trees: List[TreeCreate] = Field(..., min_length=1, max_length=1000)
    location_id: str
    default_species_id: Optional[int] = None
    import_source: str = "manual"
    import_notes: Optional[str] = None


class TreeBulkImportResponse(BaseModel):
    """Schema for bulk import response."""

    import_id: str
    total_trees: int
    successful_imports: int
    failed_imports: int
    errors: List[str] = []
    imported_tree_ids: List[str] = []
    import_timestamp: datetime

    class Config:
        from_attributes = True


class TreeQuery(BaseModel):
    """Schema for tree queries."""

    location_id: Optional[str] = None
    species_name: Optional[str] = None
    min_dbh: Optional[float] = None
    max_dbh: Optional[float] = None
    min_height: Optional[float] = None
    max_height: Optional[float] = None
    health_status: Optional[str] = None
    limit: int = 100
    offset: int = 0
