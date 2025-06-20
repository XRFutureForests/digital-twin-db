"""Environment schemas based on data contracts."""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum


# Enums for environment data
class SensorReadingType(str, Enum):
    TEMPERATURE = "temperature"
    HUMIDITY = "humidity"
    SOIL_MOISTURE = "soil_moisture"
    LIGHT_INTENSITY = "light_intensity"
    WIND_SPEED = "wind_speed"
    WIND_DIRECTION = "wind_direction"
    PRECIPITATION = "precipitation"
    CO2 = "co2"
    PH = "ph"


class SensorStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    MAINTENANCE = "maintenance"
    ERROR = "error"


class CalibrationStatus(str, Enum):
    CALIBRATED = "calibrated"
    DRIFT_DETECTED = "drift_detected"
    MAINTENANCE_REQUIRED = "maintenance_required"


class DataQuality(str, Enum):
    GOOD = "good"
    QUESTIONABLE = "questionable"
    BAD = "bad"
    MISSING = "missing"


class AggregationPeriod(str, Enum):
    INSTANTANEOUS = "instantaneous"
    HOURLY = "hourly"
    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"


# Core data types
class QualityMetrics(BaseModel):
    """Quality indicators for environmental data."""

    overall_grade: DataQuality
    confidence_score: float = Field(..., ge=0, le=1)
    measurement_source: str
    validation_method: Optional[str] = None
    anomaly_flags: Optional[List[str]] = None


# Sensor data schemas
class SensorReadingBase(BaseModel):
    """Base sensor reading schema."""

    timestamp: datetime
    reading_type: SensorReadingType
    value: float
    unit: str
    quality_score: Optional[float] = Field(None, ge=0, le=1)
    validation_flags: Optional[Dict[str, Any]] = None


class SensorReadingCreate(SensorReadingBase):
    """Schema for creating sensor readings."""

    sensor_id: int


class SensorReadingResponse(SensorReadingBase):
    """Schema for sensor reading response."""

    id: int
    sensor_id: int
    created_at: datetime

    class Config:
        from_attributes = True


class SensorReadingBatch(BaseModel):
    """Schema for batch sensor data ingestion."""

    sensor_id: int
    location_id: int
    timestamp: datetime
    readings: List[SensorReadingBase]
    battery_level: Optional[float] = Field(None, ge=0, le=100)
    signal_strength: Optional[float] = None
    device_status: SensorStatus


class SensorReadingBulkCreate(BaseModel):
    """Schema for bulk sensor reading creation."""

    readings: List[SensorReadingCreate] = Field(
        ..., description="List of sensor readings to create"
    )
    batch_id: Optional[str] = Field(None, description="Optional batch identifier")


class SensorReadingBulkResponse(BaseModel):
    """Schema for bulk sensor reading response."""

    success_count: int = Field(..., description="Number of successfully processed readings")
    error_count: int = Field(..., description="Number of failed readings")
    errors: List[str] = Field(default_factory=list, description="List of error messages")
    batch_id: Optional[str] = Field(None, description="Batch identifier if provided")


# Sensor management schemas
class SensorBase(BaseModel):
    """Base sensor schema."""

    location_id: int
    sensor_type_id: int
    installation_date: Optional[datetime] = None
    sensor_config: Optional[Dict[str, Any]] = None


class SensorCreate(SensorBase):
    """Schema for creating sensors."""

    pass


class SensorUpdate(BaseModel):
    """Schema for updating sensors."""

    status_type_id: Optional[int] = None
    sensor_config: Optional[Dict[str, Any]] = None


class SensorResponse(SensorBase):
    """Schema for sensor response."""

    id: int
    status_type_id: Optional[int]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Environmental snapshot schemas
class EnvironmentalSnapshotBase(BaseModel):
    """Base environmental snapshot schema."""

    location_id: int
    timestamp: datetime
    aggregation_period: AggregationPeriod

    # Climate variables
    temperature_c: Optional[float] = Field(None, ge=-50, le=60)
    humidity_percent: Optional[float] = Field(None, ge=0, le=100)
    precipitation_mm: Optional[float] = Field(None, ge=0)
    wind_speed_ms: Optional[float] = Field(None, ge=0)
    wind_direction_deg: Optional[float] = Field(None, ge=0, lt=360)
    solar_radiation_wm2: Optional[float] = Field(None, ge=0)
    atmospheric_pressure_hpa: Optional[float] = Field(None, gt=0)

    # Atmospheric composition
    co2_ppm: Optional[float] = Field(None, ge=0)
    o2_percent: Optional[float] = Field(None, ge=0, le=100)

    # Soil conditions
    soil_temperature_c: Optional[float] = Field(None, ge=-20, le=40)
    soil_moisture_percent: Optional[float] = Field(None, ge=0, le=100)
    soil_ph: Optional[float] = Field(None, ge=0, le=14)

    # Additional factors
    light_availability_percent: Optional[float] = Field(None, ge=0, le=100)
    canopy_openness_percent: Optional[float] = Field(None, ge=0, le=100)

    # Quality and metadata
    data_completeness_percent: Optional[float] = Field(None, ge=0, le=100)
    source_sensors: Optional[List[int]] = None
    quality_flags: Optional[List[str]] = None


class EnvironmentalSnapshotCreate(EnvironmentalSnapshotBase):
    """Schema for creating environmental snapshots."""

    pass


class EnvironmentalSnapshotResponse(EnvironmentalSnapshotBase):
    """Schema for environmental snapshot response."""

    id: int
    created_at: datetime

    class Config:
        from_attributes = True


# Site characteristics schemas
class SiteCharacteristicsBase(BaseModel):
    """Base site characteristics schema."""

    location_id: int
    elevation_m: Optional[float] = None
    slope_deg: Optional[float] = Field(None, ge=0, le=90)
    aspect_type_id: Optional[int] = None
    soil_type_id: Optional[int] = None
    climate_zone_type_id: Optional[int] = None
    annual_precipitation_mm: Optional[float] = Field(None, ge=0)
    mean_temperature_c: Optional[float] = Field(None, ge=-50, le=50)
    vegetation_type_id: Optional[int] = None
    canopy_cover_percent: Optional[float] = Field(None, ge=0, le=100)
    additional_metadata: Optional[Dict[str, Any]] = None


class SiteCharacteristicsCreate(SiteCharacteristicsBase):
    """Schema for creating site characteristics."""

    pass


class SiteCharacteristicsUpdate(BaseModel):
    """Schema for updating site characteristics."""

    elevation_m: Optional[float] = None
    slope_deg: Optional[float] = Field(None, ge=0, le=90)
    aspect_type_id: Optional[int] = None
    soil_type_id: Optional[int] = None
    climate_zone_type_id: Optional[int] = None
    annual_precipitation_mm: Optional[float] = Field(None, ge=0)
    mean_temperature_c: Optional[float] = Field(None, ge=-50, le=50)
    vegetation_type_id: Optional[int] = None
    canopy_cover_percent: Optional[float] = Field(None, ge=0, le=100)
    additional_metadata: Optional[Dict[str, Any]] = None


class SiteCharacteristicsResponse(SiteCharacteristicsBase):
    """Schema for site characteristics response."""

    id: int
    last_updated: Optional[datetime]

    class Config:
        from_attributes = True


# Environmental query schemas
class EnvironmentalQuery(BaseModel):
    """Schema for environmental data queries."""

    location_id: int
    time_range: Optional[tuple[datetime, datetime]] = None
    measurement_types: Optional[List[SensorReadingType]] = None
    aggregation: Optional[Dict[str, Any]] = {
        "temporal_resolution": "hourly",
        "spatial_radius_m": 100,
        "statistical_method": "mean",
    }
    data_quality_filter: Optional[Dict[str, Any]] = {
        "min_quality": "good",
        "exclude_estimated": False,
    }


class EnvironmentalTimeSeries(BaseModel):
    """Time series environmental data point."""

    timestamp: datetime
    measurements: Dict[str, Dict[str, Any]]  # measurement_type -> {value, quality, source}
    spatial_context: Optional[Dict[str, Any]] = None


class EnvironmentalQueryResponse(BaseModel):
    """Schema for environmental query results."""

    query_metadata: Dict[str, Any]
    time_series_data: List[EnvironmentalTimeSeries]
    statistical_summary: Optional[Dict[str, Dict[str, float]]] = None

    class Config:
        from_attributes = True


# Data ingestion schemas
class WeatherDataIngestion(BaseModel):
    """Schema for weather data ingestion."""

    location_id: int
    data_source: str = "DWD"  # DWD, NOAA, MeteoBlue, local_station
    time_period: Dict[str, Any]
    measurements: List[Dict[str, Any]]


class SoilDataIngestion(BaseModel):
    """Schema for soil data ingestion."""

    location_id: int
    sampling_date: datetime
    data_type: str = "soil_analysis"  # soil_analysis, groundwater_monitoring, continuous_sensor
    spatial_reference: Dict[str, Any]
    soil_properties: Optional[Dict[str, Any]] = None
    groundwater: Optional[Dict[str, Any]] = None
    analysis_method: str = "laboratory"
    quality_certification: str = "iso_certified"


class InventoryDataIngestion(BaseModel):
    """Schema for forest inventory data ingestion."""

    survey_metadata: Dict[str, Any]
    trees: List[Dict[str, Any]]


# Response schemas for data ingestion
class DataIngestionResponse(BaseModel):
    """Base response for data ingestion."""

    status: str
    timestamp: datetime
    imported_records: int
    validation_results: Dict[str, Any]

    class Config:
        from_attributes = True


class WeatherIngestionResponse(DataIngestionResponse):
    """Response for weather data ingestion."""

    time_range_coverage: Dict[str, Any]
    data_quality_summary: Dict[str, Any]


class SoilIngestionResponse(DataIngestionResponse):
    """Response for soil data ingestion."""

    soil_data_id: int
    spatial_integration: Dict[str, Any]


class InventoryIngestionResponse(DataIngestionResponse):
    """Response for inventory data ingestion."""

    imported_trees: int
    integration_results: Dict[str, Any]
    quality_assessment: Dict[str, Any]


# Spatial data schemas
class SpatialDatasetBase(BaseModel):
    """Base spatial dataset schema."""

    location_id: int
    dataset_name: str = Field(..., max_length=200)
    dataset_type_id: int
    spatial_type_id: int
    data_format_type_id: int
    file_path: Optional[str] = Field(None, max_length=500)
    resolution_m: Optional[float] = None
    coordinate_system: str = "EPSG:4326"
    metadata: Optional[Dict[str, Any]] = None
    acquisition_date: Optional[datetime] = None
    data_source_type_id: Optional[int] = None
    quality_level_id: Optional[int] = None


class SpatialDatasetCreate(SpatialDatasetBase):
    """Schema for creating spatial datasets."""

    pass


class SpatialDatasetResponse(SpatialDatasetBase):
    """Schema for spatial dataset response."""

    id: int
    import_date: Optional[datetime]

    class Config:
        from_attributes = True


class SpatialTraitMappingBase(BaseModel):
    """Base spatial trait mapping schema."""

    spatial_dataset_id: int
    trait_type_id: int
    extraction_method_type_id: int
    extraction_parameters: Optional[Dict[str, Any]] = None
    units: Optional[str] = Field(None, max_length=50)
    is_active: bool = True


class SpatialTraitMappingCreate(SpatialTraitMappingBase):
    """Schema for creating spatial trait mappings."""

    pass


class SpatialTraitMappingResponse(SpatialTraitMappingBase):
    """Schema for spatial trait mapping response."""

    id: int
    created_date: Optional[datetime]

    class Config:
        from_attributes = True
