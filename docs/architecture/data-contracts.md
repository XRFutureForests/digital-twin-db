# Data Contracts - XR Future Forests Lab

## Overview

This document defines the API request/response contracts and data validation rules for the XR Future Forests Lab system. These contracts serve as the interface specification between frontend applications, external integrations, and the FastAPI backend.

## Contract Patterns

### Base Models

All API models follow consistent patterns with variant-based lineage tracking:

```python
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from enum import Enum

class VariantBaseResponse(BaseModel):
    VariantID: int
    VariantTypeID: int
    VariantName: str
    ParentVariantID: Optional[int] = None
    ProcessID: Optional[int] = None
    CreatedAt: datetime
    UpdatedAt: Optional[datetime] = None

class AuditableResponse(BaseModel):
    CreatedBy: Optional[str] = None
    UpdatedBy: Optional[str] = None
    ChangeReason: Optional[str] = None
```

### Validation Rules

- **Spatial Data**: All geometry fields use WKT (Well-Known Text) format
- **Measurements**: Physical measurements include realistic constraints
- **File Paths**: Validated against allowed upload directories
- **Timestamps**: ISO 8601 format with timezone information

---

## Point Cloud Contracts

### Create Point Cloud

**Endpoint**: `POST /api/pointclouds/`

```python
class PointCloudCreateRequest(BaseModel):
    LocationID: int = Field(..., gt=0, description="Reference to shared.Locations")
    SensorModel: str = Field(..., max_length=100, description="LiDAR scanner model")
    ScanDate: datetime = Field(..., description="Timestamp of point cloud acquisition")
    FilePath: str = Field(..., regex=r"^/uploads/.*\.(las|laz)$", description="Path to uploaded LAS/LAZ file")
    ScanBounds: Optional[str] = Field(None, description="WKT POLYGON defining scan area")
    SensorHeight_m: Optional[float] = Field(None, ge=0, le=100, description="Scanner height above ground")
    ScanResolution_mm: Optional[float] = Field(None, ge=0.1, le=100, description="Point spacing resolution")
    WeatherConditions: Optional[str] = Field(None, max_length=500)
    OperatorNotes: Optional[str] = Field(None, max_length=1000)

class PointCloudResponse(VariantBaseResponse, AuditableResponse):
    LocationID: int
    SensorModel: str
    ScanDate: datetime
    FilePath: str
    ScanBounds: Optional[str]
    SensorHeight_m: Optional[float]
    ScanResolution_mm: Optional[float]
    ProcessingStatus: Optional[str]
    PointCount: Optional[int] = Field(None, ge=0)
    FileSizeMB: Optional[float] = Field(None, ge=0)
    WeatherConditions: Optional[str]
    OperatorNotes: Optional[str]
    
    # Computed fields
    ProcessingProgress: Optional[float] = Field(None, ge=0, le=100, description="Processing completion percentage")
    QualityScore: Optional[float] = Field(None, ge=0, le=1, description="Point cloud quality assessment")
```

### Point Cloud Processing

**Endpoint**: `POST /api/pointclouds/{variant_id}/process`

```python
class ProcessingAlgorithm(str, Enum):
    TREE_SEGMENTATION = "tree_segmentation"
    GROUND_CLASSIFICATION = "ground_classification"
    NOISE_REMOVAL = "noise_removal"
    VEGETATION_ANALYSIS = "vegetation_analysis"

class PointCloudProcessingRequest(BaseModel):
    Algorithm: ProcessingAlgorithm
    Parameters: dict = Field(..., description="Algorithm-specific parameters")
    Priority: str = Field("normal", regex=r"^(low|normal|high|urgent)$")
    NotifyOnCompletion: bool = Field(True)
    
    class Config:
        schema_extra = {
            "example": {
                "Algorithm": "tree_segmentation",
                "Parameters": {
                    "min_points_per_tree": 100,
                    "height_threshold_m": 2.0,
                    "crown_overlap_threshold": 0.3
                },
                "Priority": "normal",
                "NotifyOnCompletion": True
            }
        }

class ProcessingJobResponse(BaseModel):
    JobID: str
    SourceVariantID: int
    Algorithm: ProcessingAlgorithm
    Status: str = Field(..., regex=r"^(queued|processing|completed|failed|cancelled)$")
    Progress: float = Field(..., ge=0, le=100)
    EstimatedCompletionTime: Optional[datetime]
    ResultVariantID: Optional[int]
    ErrorMessage: Optional[str]
    StartedAt: Optional[datetime]
    CompletedAt: Optional[datetime]
```

---

## Tree Contracts

### Tree Data Models

```python
class TreeStatus(str, Enum):
    ALIVE = "alive"
    DEAD = "dead"
    DISEASED = "diseased"
    HARVESTED = "harvested"
    UNKNOWN = "unknown"

class MeasurementMethod(str, Enum):
    FIELD_MEASUREMENT = "field_measurement"
    LIDAR_DETECTION = "lidar_detection"
    PHOTOGRAMMETRY = "photogrammetry"
    ESTIMATED = "estimated"

class StemModel(BaseModel):
    StemID: int
    StemNumber: int = Field(..., ge=1, description="Stem number for multi-stem trees")
    DBH_cm: Optional[float] = Field(None, ge=0.1, le=500, description="Diameter at breast height")
    Height_m: Optional[float] = Field(None, ge=0.1, le=100, description="Individual stem height")
    TaperRatio: Optional[float] = Field(None, ge=0, le=1, description="Stem taper coefficient")
    StraightnessIndex: Optional[float] = Field(None, ge=0, le=1, description="Stem straightness measure")
    BarkThickness_mm: Optional[float] = Field(None, ge=0, le=50)
    WoodDensity_kg_m3: Optional[float] = Field(None, ge=100, le=2000)

class SpeciesModel(BaseModel):
    SpeciesID: int
    ScientificName: str
    CommonName: Optional[str]
    FamilyName: str
    MaxHeight_m: Optional[float]
    MaxDBH_cm: Optional[float]
    TypicalLifespan_years: Optional[int]

class TreeCreateRequest(BaseModel):
    LocationID: int = Field(..., gt=0)
    SpeciesID: Optional[int] = Field(None, gt=0)
    Position: str = Field(..., description="WKT POINT in plot coordinates")
    Height_m: Optional[float] = Field(None, ge=0.1, le=100)
    CrownDiameter_m: Optional[float] = Field(None, ge=0.1, le=50)
    CrownHeight_m: Optional[float] = Field(None, ge=0.1, le=100)
    TreeStatus: TreeStatus = TreeStatus.ALIVE
    MeasurementMethod: MeasurementMethod = MeasurementMethod.FIELD_MEASUREMENT
    PointCloudVariantID: Optional[int] = Field(None, description="Source point cloud if detected")
    Age_years: Optional[int] = Field(None, ge=0, le=2000)
    HealthScore: Optional[float] = Field(None, ge=0, le=1, description="Tree health assessment 0-1")
    Volume_m3: Optional[float] = Field(None, ge=0, description="Estimated tree volume")
    Biomass_kg: Optional[float] = Field(None, ge=0, description="Estimated above-ground biomass")
    CarbonContent_kg: Optional[float] = Field(None, ge=0, description="Estimated carbon storage")
    FieldNotes: Optional[str] = Field(None, max_length=1000)

class TreeResponse(VariantBaseResponse, AuditableResponse):
    LocationID: int
    SpeciesID: Optional[int]
    Position: str
    Height_m: Optional[float]
    CrownDiameter_m: Optional[float]
    CrownHeight_m: Optional[float]
    TreeStatus: TreeStatus
    MeasurementMethod: MeasurementMethod
    PointCloudVariantID: Optional[int]
    Age_years: Optional[int]
    HealthScore: Optional[float]
    Volume_m3: Optional[float]
    Biomass_kg: Optional[float]
    CarbonContent_kg: Optional[float]
    FieldNotes: Optional[str]
    
    # Related data
    Species: Optional[SpeciesModel]
    Stems: List[StemModel] = []
    
    # Computed fields
    BasalArea_m2: Optional[float] = Field(None, description="Calculated from DBH measurements")
    CrownVolume_m3: Optional[float] = Field(None, description="Estimated crown volume")
    CompetitionIndex: Optional[float] = Field(None, description="Competition pressure from neighboring trees")
```

### Tree Search and Filtering

**Endpoint**: `GET /api/trees/`

```python
class TreeSearchRequest(BaseModel):
    LocationID: Optional[int] = None
    SpeciesID: Optional[int] = None
    MinHeight_m: Optional[float] = Field(None, ge=0)
    MaxHeight_m: Optional[float] = Field(None, le=100)
    MinDBH_cm: Optional[float] = Field(None, ge=0)
    MaxDBH_cm: Optional[float] = Field(None, le=500)
    TreeStatus: Optional[List[TreeStatus]] = None
    MeasurementMethod: Optional[List[MeasurementMethod]] = None
    BoundingBox: Optional[str] = Field(None, description="WKT POLYGON for spatial filtering")
    BufferDistance_m: Optional[float] = Field(None, ge=0, le=1000, description="Buffer around point/polygon")
    MinHealthScore: Optional[float] = Field(None, ge=0, le=1)
    SortBy: str = Field("VariantID", regex=r"^(VariantID|Height_m|CreatedAt|UpdatedAt)$")
    SortOrder: str = Field("asc", regex=r"^(asc|desc)$")
    Limit: int = Field(100, ge=1, le=1000)
    Offset: int = Field(0, ge=0)

class TreeSearchResponse(BaseModel):
    Trees: List[TreeResponse]
    TotalCount: int
    FilteredCount: int
    SearchParams: TreeSearchRequest
    BoundingBox: Optional[str] = Field(None, description="WKT POLYGON of result extent")
```

---

## Sensor Contracts

### Sensor Data Models

```python
class SensorType(str, Enum):
    TEMPERATURE = "temperature"
    HUMIDITY = "humidity"
    SOIL_MOISTURE = "soil_moisture"
    LIGHT_INTENSITY = "light_intensity"
    WIND_SPEED = "wind_speed"
    PRECIPITATION = "precipitation"
    CO2_CONCENTRATION = "co2_concentration"
    PH_LEVEL = "ph_level"

class SensorModel(BaseModel):
    SensorID: int
    LocationID: int
    SensorType: SensorType
    Model: str = Field(..., max_length=100)
    SerialNumber: str = Field(..., max_length=50)
    Position: str = Field(..., description="WKT POINT sensor location")
    InstallationDate: datetime
    CalibrationDate: Optional[datetime]
    BatteryLevel: Optional[float] = Field(None, ge=0, le=100, description="Battery percentage")
    SamplingInterval_seconds: int = Field(..., ge=1, le=86400)
    Range_m: Optional[float] = Field(None, ge=0, description="Sensor measurement radius")
    MinValue: Optional[float] = Field(None, description="Sensor minimum measurable value")
    MaxValue: Optional[float] = Field(None, description="Sensor maximum measurable value")
    Accuracy: Optional[float] = Field(None, description="Sensor accuracy specification")
    IsActive: bool = Field(True)
    MaintenanceNotes: Optional[str] = Field(None, max_length=500)

class SensorReadingCreate(BaseModel):
    SensorID: int = Field(..., gt=0)
    Timestamp: datetime
    Value: float
    Unit: str = Field(..., max_length=20)
    QualityFlag: str = Field("good", regex=r"^(good|questionable|bad|missing)$")
    BatteryVoltage: Optional[float] = Field(None, ge=0, le=12)
    SignalStrength: Optional[float] = Field(None, ge=-120, le=0, description="Signal strength in dBm")
    Notes: Optional[str] = Field(None, max_length=200)

class SensorReadingResponse(BaseModel):
    ReadingID: int
    SensorID: int
    Timestamp: datetime
    Value: float
    Unit: str
    QualityFlag: str
    BatteryVoltage: Optional[float]
    SignalStrength: Optional[float]
    Notes: Optional[str]
    CreatedAt: datetime
    
    # Related data
    Sensor: Optional[SensorModel]

class SensorDataQuery(BaseModel):
    SensorIDs: Optional[List[int]] = Field(None, description="Specific sensors to query")
    LocationID: Optional[int] = Field(None, description="All sensors at location")
    SensorTypes: Optional[List[SensorType]] = Field(None, description="Filter by sensor type")
    StartTime: datetime = Field(..., description="Query start timestamp")
    EndTime: datetime = Field(..., description="Query end timestamp")
    Aggregation: str = Field("raw", regex=r"^(raw|hourly|daily|weekly|monthly)$")
    QualityFilter: List[str] = Field(["good"], description="Include readings with these quality flags")
    IncludeMetadata: bool = Field(False, description="Include sensor metadata in response")
```

---

## Environment Contracts

### Environmental Conditions

```python
class EnvironmentType(str, Enum):
    BASELINE = "baseline"
    DROUGHT_STRESS = "drought_stress"
    HEAT_STRESS = "heat_stress"
    FLOODING = "flooding"
    PEST_OUTBREAK = "pest_outbreak"
    DISEASE_PRESSURE = "disease_pressure"
    FIRE_RECOVERY = "fire_recovery"
    HARVEST_RECOVERY = "harvest_recovery"

class EnvironmentCreateRequest(BaseModel):
    LocationID: int = Field(..., gt=0)
    EnvironmentType: EnvironmentType
    StartDate: datetime
    EndDate: Optional[datetime] = None
    Temperature_C: Optional[float] = Field(None, ge=-50, le=60)
    Humidity_percent: Optional[float] = Field(None, ge=0, le=100)
    SoilMoisture_percent: Optional[float] = Field(None, ge=0, le=100)
    LightIntensity_lux: Optional[float] = Field(None, ge=0, le=200000)
    WindSpeed_ms: Optional[float] = Field(None, ge=0, le=100)
    Precipitation_mm: Optional[float] = Field(None, ge=0, le=1000)
    CO2_ppm: Optional[float] = Field(None, ge=200, le=2000)
    SoilPH: Optional[float] = Field(None, ge=3, le=10)
    NutrientNitrogen_mg_kg: Optional[float] = Field(None, ge=0)
    NutrientPhosphorus_mg_kg: Optional[float] = Field(None, ge=0)
    NutrientPotassium_mg_kg: Optional[float] = Field(None, ge=0)
    StressFactor: Optional[float] = Field(None, ge=0, le=1, description="Environmental stress index")
    Description: Optional[str] = Field(None, max_length=1000)
    ResearchNotes: Optional[str] = Field(None, max_length=2000)

class EnvironmentResponse(VariantBaseResponse, AuditableResponse):
    LocationID: int
    EnvironmentType: EnvironmentType
    StartDate: datetime
    EndDate: Optional[datetime]
    Temperature_C: Optional[float]
    Humidity_percent: Optional[float]
    SoilMoisture_percent: Optional[float]
    LightIntensity_lux: Optional[float]
    WindSpeed_ms: Optional[float]
    Precipitation_mm: Optional[float]
    CO2_ppm: Optional[float]
    SoilPH: Optional[float]
    NutrientNitrogen_mg_kg: Optional[float]
    NutrientPhosphorus_mg_kg: Optional[float]
    NutrientPotassium_mg_kg: Optional[float]
    StressFactor: Optional[float]
    Description: Optional[str]
    ResearchNotes: Optional[str]
    
    # Computed fields
    Duration_days: Optional[int] = Field(None, description="Environment duration in days")
    IsActive: bool = Field(..., description="Whether environment is currently active")
```

---

## Audit Contracts

### Audit Trail

```python
class AuditLogResponse(BaseModel):
    AuditID: int
    TableName: str
    FieldName: str
    OldValue: Optional[str]
    NewValue: Optional[str]
    ChangeType: str = Field(..., regex=r"^(INSERT|UPDATE|DELETE)$")
    UserID: Optional[str]
    ChangeReason: Optional[str]
    Timestamp: datetime
    IPAddress: Optional[str]
    UserAgent: Optional[str]
    
    # Junction table references
    RelatedVariantID: Optional[int] = Field(None, description="Related variant from junction tables")
    RelatedVariantType: Optional[str] = Field(None, description="Type of related variant")

class AuditQueryRequest(BaseModel):
    TableName: Optional[str] = Field(None, regex=r"^(Trees|PointClouds|Sensors|Environments)$")
    VariantID: Optional[int] = Field(None, gt=0)
    UserID: Optional[str] = None
    FieldName: Optional[str] = None
    ChangeType: Optional[str] = Field(None, regex=r"^(INSERT|UPDATE|DELETE)$")
    StartTime: Optional[datetime] = None
    EndTime: Optional[datetime] = None
    Limit: int = Field(100, ge=1, le=1000)
    Offset: int = Field(0, ge=0)

class AuditSummaryResponse(BaseModel):
    TotalChanges: int
    ChangesByType: dict = Field(..., description="Count of changes by type (INSERT/UPDATE/DELETE)")
    ChangesByTable: dict = Field(..., description="Count of changes by table")
    ChangesByUser: dict = Field(..., description="Count of changes by user")
    MostActiveVariants: List[dict] = Field(..., description="Variants with most changes")
    RecentChanges: List[AuditLogResponse] = Field(..., description="Most recent audit entries")
```

---

## Error Handling

### Standard Error Responses

```python
class ValidationError(BaseModel):
    field: str
    message: str
    rejectedValue: Optional[str] = None

class ErrorResponse(BaseModel):
    error: str
    message: str
    details: Optional[List[ValidationError]] = None
    timestamp: datetime
    path: str
    requestId: Optional[str] = None

# HTTP Status Code Mappings
# 400 Bad Request: ValidationError with details
# 401 Unauthorized: Authentication required
# 403 Forbidden: Insufficient permissions
# 404 Not Found: Resource not found
# 409 Conflict: Variant lineage or constraint violation
# 422 Unprocessable Entity: Business logic validation failure
# 500 Internal Server Error: Unexpected system error
```

---

## Usage Examples

### Complete Point Cloud to Tree Detection Workflow

```python
# 1. Upload point cloud
pointcloud_request = PointCloudCreateRequest(
    LocationID=15,
    SensorModel="Leica BLK360",
    ScanDate="2025-07-03T14:30:00Z",
    FilePath="/uploads/plot_001_scan_20250703.las",
    ScanBounds="POLYGON((0 0, 100 0, 100 100, 0 100, 0 0))",
    SensorHeight_m=1.5,
    ScanResolution_mm=5.0,
    WeatherConditions="Clear, light wind",
    OperatorNotes="High-quality scan of mature forest plot"
)

# 2. Process for tree detection
processing_request = PointCloudProcessingRequest(
    Algorithm="tree_segmentation",
    Parameters={
        "min_points_per_tree": 100,
        "height_threshold_m": 2.0,
        "crown_overlap_threshold": 0.3,
        "species_hints": ["fagus_sylvatica", "quercus_robur"]
    },
    Priority="high"
)

# 3. Create detected trees
tree_request = TreeCreateRequest(
    LocationID=15,
    SpeciesID=42,  # Fagus sylvatica
    Position="POINT(125.3 78.9)",
    Height_m=24.7,
    CrownDiameter_m=8.5,
    TreeStatus="alive",
    MeasurementMethod="lidar_detection",
    PointCloudVariantID=1002,  # Processed point cloud
    HealthScore=0.92,
    Volume_m3=2.15,
    FieldNotes="Automatically detected, verified by field measurement"
)
```

### Sensor Data Monitoring

```python
# Query recent temperature readings
sensor_query = SensorDataQuery(
    SensorTypes=["temperature"],
    LocationID=15,
    StartTime="2025-07-03T00:00:00Z",
    EndTime="2025-07-03T23:59:59Z",
    Aggregation="hourly",
    QualityFilter=["good", "questionable"]
)

# Add new sensor reading
reading = SensorReadingCreate(
    SensorID=301,
    Timestamp="2025-07-03T15:30:00Z",
    Value=22.5,
    Unit="celsius",
    QualityFlag="good",
    BatteryVoltage=3.7,
    SignalStrength=-65
)
```

These data contracts provide type-safe, validated interfaces for all major operations in the XR Future Forests Lab system, ensuring consistency across frontend applications, external integrations, and the FastAPI backend while maintaining the variant-based lineage tracking essential for forest research data integrity.
