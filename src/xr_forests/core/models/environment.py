"""Environment models."""

from sqlalchemy import Column, String, DateTime, Integer, Numeric, Text, Boolean, ForeignKey
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import relationship
from geoalchemy2 import Geometry

from .base import Base, TimestampMixin


class EnvironmentSensorTypes(Base):
    """Environment sensor types reference table."""

    __tablename__ = "environment_sensor_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(
        String(100), nullable=False, unique=True
    )  # Temperature, Humidity, CO2, Light, Soil_Moisture, Wind
    description = Column(Text)


class SensorStatusTypes(Base):
    """Sensor status types reference table."""

    __tablename__ = "sensor_status_types"

    id = Column(Integer, primary_key=True)
    status_name = Column(
        String(50), nullable=False, unique=True
    )  # active, inactive, maintenance, error
    description = Column(Text)


class AspectTypes(Base):
    """Aspect types reference table."""

    __tablename__ = "aspect_types"

    id = Column(Integer, primary_key=True)
    aspect_name = Column(String(10), nullable=False, unique=True)  # N, NE, E, SE, S, SW, W, NW
    description = Column(Text)


class SpatialDatasetTypes(Base):
    """Spatial dataset types reference table."""

    __tablename__ = "spatial_dataset_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(
        String(100), nullable=False, unique=True
    )  # elevation, soil, vegetation, climate, canopy
    description = Column(Text)


class SpatialTypes(Base):
    """Spatial types reference table."""

    __tablename__ = "spatial_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(String(50), nullable=False, unique=True)  # raster, vector, point_cloud
    description = Column(Text)


class DataFormatTypes(Base):
    """Data format types reference table."""

    __tablename__ = "data_format_types"

    id = Column(Integer, primary_key=True)
    format_name = Column(String(50), nullable=False, unique=True)  # GeoTIFF, Shapefile, LAS, NetCDF
    description = Column(Text)


class DataSourceTypes(Base):
    """Data source types reference table."""

    __tablename__ = "data_source_types"

    id = Column(Integer, primary_key=True)
    source_name = Column(
        String(100), nullable=False, unique=True
    )  # survey, satellite, lidar, model
    description = Column(Text)


class QualityLevelTypes(Base):
    """Quality level types reference table."""

    __tablename__ = "quality_level_types"

    id = Column(Integer, primary_key=True)
    level_name = Column(String(50), nullable=False, unique=True)  # high, medium, low
    description = Column(Text)


class ExtractionMethodTypes(Base):
    """Extraction method types reference table."""

    __tablename__ = "extraction_method_types"

    id = Column(Integer, primary_key=True)
    method_name = Column(
        String(100), nullable=False, unique=True
    )  # point_sample, area_average, interpolation
    description = Column(Text)


class TraitTypes(Base):
    """Trait types reference table."""

    __tablename__ = "trait_types"

    id = Column(Integer, primary_key=True)
    trait_name = Column(
        String(100), nullable=False, unique=True
    )  # elevation, slope, soil_type, canopy_cover, drainage, fertility
    description = Column(Text)


class SoilTypes(Base):
    """Soil types reference table."""

    __tablename__ = "soil_types"

    id = Column(Integer, primary_key=True)
    soil_name = Column(String(100), nullable=False, unique=True)  # Sandy, Clay, Loam, Peat, Rocky
    description = Column(Text)


class ClimateZoneTypes(Base):
    """Climate zone types reference table."""

    __tablename__ = "climate_zone_types"

    id = Column(Integer, primary_key=True)
    zone_name = Column(
        String(10), nullable=False, unique=True
    )  # Köppen climate classification codes
    description = Column(Text)


class VegetationTypes(Base):
    """Vegetation types reference table."""

    __tablename__ = "vegetation_types"

    id = Column(Integer, primary_key=True)
    type_name = Column(
        String(100), nullable=False, unique=True
    )  # Deciduous, Coniferous, Mixed, Grassland, Shrubland
    description = Column(Text)


class Sensors(Base, TimestampMixin):
    """Sensors model for environmental monitoring equipment."""

    __tablename__ = "sensors"

    id = Column(Integer, primary_key=True)
    location_id = Column(Integer, ForeignKey("locations.id"))
    sensor_type_id = Column(Integer, ForeignKey("environment_sensor_types.id"))
    installation_date = Column(DateTime(timezone=True))
    status_type_id = Column(Integer, ForeignKey("sensor_status_types.id"))
    sensor_config = Column(JSONB)  # JSON: config/calibration

    # Relationships
    sensor_type = relationship("EnvironmentSensorTypes")
    status_type = relationship("SensorStatusTypes")


class SensorReadings(Base, TimestampMixin):
    """Sensor readings model for time-series environmental data."""

    __tablename__ = "sensor_readings"

    id = Column(Integer, primary_key=True)
    sensor_id = Column(Integer, ForeignKey("sensors.id"))
    timestamp = Column(DateTime(timezone=True), nullable=False)
    reading_type = Column(String(100))  # Type (e.g. Temperature)
    value = Column(Numeric(12, 4))  # Value
    unit = Column(String(20))  # Unit
    quality_score = Column(Numeric(3, 2))  # Reading quality score (0-1)
    validation_flags = Column(JSONB)  # JSON: validation status, outlier detection

    # Relationships
    sensor = relationship("Sensors")


class EnvironmentalSnapshots(Base, TimestampMixin):
    """Environmental snapshots model for aggregated environmental data."""

    __tablename__ = "environmental_snapshots"

    id = Column(Integer, primary_key=True)
    location_id = Column(Integer, ForeignKey("locations.id"))
    timestamp = Column(DateTime(timezone=True), nullable=False)
    avg_temperature_c = Column(Numeric(5, 2))
    avg_humidity_percent = Column(Numeric(5, 2))
    total_precipitation_mm = Column(Numeric(6, 2))
    avg_global_radiation = Column(Numeric(8, 2))
    avg_co2_ppm = Column(Numeric(6, 2))
    avg_wind_speed_ms = Column(Numeric(4, 2))
    dominant_wind_direction_deg = Column(Numeric(5, 2))
    obstacle_voxel_grid_ref = Column(Text)
    other_environmental_factors = Column(JSONB)


class SiteCharacteristics(Base):
    """Site characteristics model for static environmental features."""

    __tablename__ = "site_characteristics"

    id = Column(Integer, primary_key=True)
    location_id = Column(Integer, ForeignKey("locations.id"))
    elevation_m = Column(Numeric(8, 2))
    slope_deg = Column(Numeric(5, 2))
    aspect_type_id = Column(Integer, ForeignKey("aspect_types.id"))
    soil_type_id = Column(Integer, ForeignKey("soil_types.id"))
    climate_zone_type_id = Column(Integer, ForeignKey("climate_zone_types.id"))
    annual_precipitation_mm = Column(Numeric(8, 2))
    mean_temperature_c = Column(Numeric(5, 2))
    vegetation_type_id = Column(Integer, ForeignKey("vegetation_types.id"))
    canopy_cover_percent = Column(Numeric(5, 2))
    additional_metadata = Column(JSONB)
    last_updated = Column(DateTime(timezone=True))

    # Relationships
    aspect_type = relationship("AspectTypes")
    soil_type = relationship("SoilTypes")
    climate_zone_type = relationship("ClimateZoneTypes")
    vegetation_type = relationship("VegetationTypes")


class SpatialDatasets(Base):
    """Spatial datasets model for managing spatial data sources."""

    __tablename__ = "spatial_datasets"

    id = Column(Integer, primary_key=True)
    location_id = Column(Integer, ForeignKey("locations.id"))
    dataset_name = Column(String(200))
    dataset_type_id = Column(Integer, ForeignKey("spatial_dataset_types.id"))
    spatial_type_id = Column(Integer, ForeignKey("spatial_types.id"))
    data_format_type_id = Column(Integer, ForeignKey("data_format_types.id"))
    file_path = Column(String(500))
    resolution_m = Column(Numeric(8, 4))
    coordinate_system = Column(String(50))  # EPSG code
    bounding_geometry = Column(Geometry("POLYGON", srid=4326))
    dataset_metadata = Column(JSONB)
    acquisition_date = Column(DateTime(timezone=True))
    import_date = Column(DateTime(timezone=True))
    data_source_type_id = Column(Integer, ForeignKey("data_source_types.id"))
    quality_level_id = Column(Integer, ForeignKey("quality_level_types.id"))

    # Relationships
    dataset_type = relationship("SpatialDatasetTypes")
    spatial_type = relationship("SpatialTypes")
    data_format_type = relationship("DataFormatTypes")
    data_source_type = relationship("DataSourceTypes")
    quality_level = relationship("QualityLevelTypes")


class SpatialTraitMappings(Base):
    """Spatial trait mappings model for connecting spatial data to site traits."""

    __tablename__ = "spatial_trait_mappings"

    id = Column(Integer, primary_key=True)
    spatial_dataset_id = Column(Integer, ForeignKey("spatial_datasets.id"))
    trait_type_id = Column(Integer, ForeignKey("trait_types.id"))
    extraction_method_type_id = Column(Integer, ForeignKey("extraction_method_types.id"))
    extraction_parameters = Column(JSONB)
    units = Column(String(50))
    created_date = Column(DateTime(timezone=True))
    is_active = Column(Boolean, default=True)

    # Relationships
    spatial_dataset = relationship("SpatialDatasets")
    trait_type = relationship("TraitTypes")
    extraction_method_type = relationship("ExtractionMethodTypes")
