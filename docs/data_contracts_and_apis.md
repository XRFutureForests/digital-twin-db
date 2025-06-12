# Data Contracts & APIs - XR Future Forests Lab

> **Version**: 1.0  
> **Last Updated**: June 12, 2025  
> **Related**: [Architecture](./architecture.md) | [Database Design](./database_design.md)

This document defines the data contracts and API specifications for the XR Future Forests Lab system. Data contracts specify the standardized data structures, formats, and validation rules used consistently across all system components. API specifications define the exact request/response schemas for all system endpoints.

---

## Table of Contents

1. [Data Contracts](#data-contracts)
   - [Core Data Types](#core-data-types)
   - [Tree Data Contracts](#tree-data-contracts)
   - [Environmental Data Contracts](#environmental-data-contracts)
   - [Point Cloud Data Contracts](#point-cloud-data-contracts)
   - [Simulation Data Contracts](#simulation-data-contracts)
2. [API Specifications](#api-specifications)
   - [Data Tier APIs](#data-tier-apis)
   - [Logic Tier APIs](#logic-tier-apis)
   - [Presentation Tier APIs](#presentation-tier-apis)
3. [Common API Data Types](#common-api-data-types)
4. [Error Handling](#error-handling)
5. [API Types and Interface Patterns](#api-types-and-interface-patterns)

---

## Data Contracts

Data contracts define the standardized data structures and formats used throughout the XR Future Forests Lab system. These contracts ensure consistency, interoperability, and data integrity across all components.

### Core Data Types

#### Identifier Types

```typescript
type UUID = string; // UUID v4 format: "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
type LocationID = UUID;
type TreeID = UUID;
type SpeciesID = UUID;
type SensorID = UUID;
type JobID = UUID;
```

#### Geographic Data Types

```typescript
interface Coordinates {
  latitude: number;        // Decimal degrees, WGS84, range: [-90, 90]
  longitude: number;       // Decimal degrees, WGS84, range: [-180, 180]
  elevation_m?: number;    // Meters above sea level
  coordinate_system: "EPSG:4326" | "EPSG:25832" | "EPSG:31467";
}

interface BoundingBox {
  min_x: number;
  min_y: number;
  min_z?: number;
  max_x: number;
  max_y: number;
  max_z?: number;
  coordinate_system: string;
}
```

#### Temporal Data Types

```typescript
type Timestamp = string; // ISO 8601 format: "2025-06-12T10:30:00Z"

interface TimeRange {
  start: Timestamp;
  end: Timestamp;
}

interface TemporalResolution {
  resolution: "minute" | "hourly" | "daily" | "weekly" | "monthly" | "annual";
  interval?: number; // For custom intervals (e.g., every 15 minutes)
}
```

#### Quality and Validation Types

```typescript
type DataQuality = "A" | "B" | "C" | "D"; // A=Excellent, B=Good, C=Acceptable, D=Poor

type MeasurementSource = "Direct_Measurement" | "Point_Cloud_Derived" | "Model_Estimated";

interface QualityMetrics {
  overall_grade: DataQuality;
  confidence_score: number; // Range: [0, 1]
  measurement_source: MeasurementSource;
  validation_method?: string;
  anomaly_flags?: string[];
}
```

### Tree Data Contracts

#### Tree Identity and Classification

```typescript
interface TreeIdentity {
  tree_id: TreeID;
  variant_id?: UUID;
  species_id: SpeciesID;
  location_id: LocationID;
  tree_tag?: string; // Field identification tag
}

interface Species {
  species_id: SpeciesID;
  scientific_name: string; // e.g., "Fagus sylvatica"
  common_name: string;     // e.g., "European Beech"
  species_code: string;    // Standardized code (e.g., "FASY")
  growth_characteristics: {
    max_height_m: number;
    max_dbh_cm: number;
    growth_rate: "slow" | "medium" | "fast";
    longevity_years: number;
  };
}
```

#### Tree Measurements

```typescript
interface TreeMeasurements {
  height_m: number;
  height_quality: QualityMetrics;
  
  dbh_cm: number; // Diameter at Breast Height
  dbh_quality: QualityMetrics;
  
  crown_width_m: number;
  crown_width_quality: QualityMetrics;
  
  crown_height_m?: number;
  crown_base_height_m?: number;
  
  volume_m3?: number;
  volume_quality?: QualityMetrics;
  
  biomass_kg?: number;
  biomass_quality?: QualityMetrics;
  
  measurement_date: Timestamp;
}

interface TreeHealth {
  vitality: "healthy" | "stressed" | "declining" | "dead";
  health_score: number; // Range: [0, 100]
  disease_indicators: string[];
  pest_indicators: string[];
  environmental_stress_indicators: string[];
  assessment_date: Timestamp;
  assessment_method: "field_survey" | "remote_sensing" | "automated_analysis";
}
```

#### Tree Structure Data

```typescript
interface TreeStructure {
  structure_id: UUID;
  tree_variant_id: UUID;
  structure_type: "QSM" | "L_System" | "DeepTree" | "Manual" | "Hybrid";
  
  // Structural components
  trunk: TrunkStructure;
  branches: BranchStructure[];
  leaves: LeafStructure[];
  
  // Metadata
  generation_date: Timestamp;
  generation_method: string;
  quality_metrics: QualityMetrics;
  file_references?: FileReference[];
}

interface BranchStructure {
  branch_id: UUID;
  parent_branch_id?: UUID; // null for main trunk
  
  // Geometric properties
  length_m: number;
  base_diameter_cm: number;
  tip_diameter_cm: number;
  
  // Spatial orientation
  azimuth_deg: number;        // 0-360 degrees from North
  inclination_deg: number;    // 0-90 degrees from vertical
  start_height_m: number;     // Height where branch starts
  
  // Additional properties
  branch_order: number;       // 1=primary, 2=secondary, etc.
  leaf_area_m2?: number;
  biomass_kg?: number;
}

interface TrunkStructure {
  trunk_id: UUID;
  base_diameter_cm: number;
  height_m: number;
  taper_curve: {
    height_m: number;
    diameter_cm: number;
  }[];
  bark_thickness_cm: number;
  heartwood_diameter_cm?: number;
}

interface LeafStructure {
  leaf_id: UUID;
  branch_id: UUID;
  leaf_area_cm2: number;
  leaf_angle_deg: number;
  phenology_status: "budding" | "growing" | "mature" | "senescent" | "fallen";
  color_rgb?: string; // For phenology visualization
}
```

### Environmental Data Contracts

#### Sensor Data Structures

```typescript
interface SensorReading {
  reading_id: UUID;
  sensor_id: SensorID;
  timestamp: Timestamp;
  
  // Measurement data
  reading_type: "temperature" | "humidity" | "soil_moisture" | "light_intensity" | 
                "wind_speed" | "wind_direction" | "precipitation" | "co2" | "ph";
  value: number;
  unit: string;
  
  // Quality indicators
  quality: QualityMetrics;
  calibration_status: "calibrated" | "drift_detected" | "maintenance_required";
  
  // Sensor status
  battery_level?: number; // Percentage
  signal_strength?: number; // dBm or percentage
}

interface EnvironmentalSnapshot {
  snapshot_id: UUID;
  location_id: LocationID;
  timestamp: Timestamp;
  aggregation_period: "instantaneous" | "hourly" | "daily" | "weekly" | "monthly";
  
  // Climate variables
  temperature_c: number;
  humidity_percent: number;
  precipitation_mm: number;
  wind_speed_ms: number;
  wind_direction_deg: number;
  solar_radiation_wm2: number;
  atmospheric_pressure_hpa: number;
  
  // Atmospheric composition
  co2_ppm: number;
  o2_percent?: number;
  
  // Soil conditions
  soil_temperature_c: number;
  soil_moisture_percent: number;
  soil_ph: number;
  
  // Additional factors
  light_availability_percent: number;
  canopy_openness_percent?: number;
  
  // Quality and metadata
  data_completeness_percent: number;
  source_sensors: SensorID[];
  quality_flags: string[];
}
```

### Point Cloud Data Contracts

#### Point Cloud Metadata

```typescript
interface PointCloudMetadata {
  pointcloud_id: UUID;
  location_id: LocationID;
  
  // Acquisition details
  scan_date: Timestamp;
  sensor_type: "TLS" | "UAV_LiDAR" | "ALS" | "MLS"; // Terrestrial, UAV, Airborne, Mobile
  scanner_model: string;
  scan_resolution_cm: number;
  
  // Spatial information
  coordinate_system: string; // EPSG code
  bounding_box: BoundingBox;
  point_count: number;
  point_density_per_m2: number;
  
  // Quality metrics
  coverage_percentage: number;
  noise_level: "low" | "medium" | "high";
  registration_accuracy_cm: number;
  
  // File information
  file_path: string;
  file_size_mb: number;
  file_format: "LAS" | "LAZ" | "PLY" | "PCD";
  compression_ratio?: number;
}

interface PointCloudProcessingResult {
  result_id: UUID;
  pointcloud_id: UUID;
  processing_type: "segmentation" | "classification" | "attribute_extraction";
  
  // Processing details
  algorithm_name: string;
  algorithm_version: string;
  processing_date: Timestamp;
  processing_duration_seconds: number;
  
  // Results
  trees_detected?: number;
  classification_accuracy?: number;
  segmentation_quality_score?: number;
  
  // Output references
  output_files: FileReference[];
  quality_metrics: QualityMetrics;
}
```

### Simulation Data Contracts

#### Growth Simulation Data

```typescript
interface GrowthSimulationParameters {
  simulation_id: UUID;
  simulation_name: string;
  
  // Temporal scope
  start_date: Timestamp;
  end_date: Timestamp;
  time_step: TemporalResolution;
  
  // Models to use
  growth_models: ("SILVA" | "BALANCE" | "iLand")[];
  model_coupling: "sequential" | "parallel" | "ensemble";
  
  // Environmental scenarios
  climate_scenario: "current" | "rcp26" | "rcp45" | "rcp85" | "custom";
  management_scenario?: ManagementScenario;
  
  // Model parameters
  model_parameters: Record<string, any>;
  
  // Output preferences
  output_frequency: TemporalResolution;
  spatial_resolution_m: number;
  include_uncertainty: boolean;
}

interface GrowthSimulationResult {
  simulation_id: UUID;
  tree_variant_id: UUID;
  simulation_timestamp: Timestamp;
  
  // Predicted measurements
  predicted_measurements: TreeMeasurements;
  prediction_uncertainty?: {
    height_uncertainty_m: number;
    dbh_uncertainty_cm: number;
    biomass_uncertainty_kg: number;
  };
  
  // Model-specific outputs
  model_outputs: {
    model_name: string;
    carbon_sequestration_kg: number;
    water_use_liters: number;
    mortality_risk: number; // Range: [0, 1]
    stress_indicators: string[];
  }[];
  
  // Quality indicators
  model_confidence: number; // Range: [0, 1]
  validation_score?: number;
}

interface ManagementScenario {
  scenario_name: string;
  management_actions: {
    action_type: "thinning" | "fertilization" | "irrigation" | "pruning" | "harvesting";
    scheduled_date: Timestamp;
    intensity: number; // Percentage or specific units
    target_criteria: string;
  }[];
}
```

#### File Reference Standard

```typescript
interface FileReference {
  file_id: UUID;
  file_path: string;
  file_name: string;
  file_type: string; // MIME type
  file_size_bytes: number;
  checksum_md5: string;
  created_date: Timestamp;
  access_permissions: "public" | "restricted" | "private";
}
```

---

## API Specifications

The following sections define the specific API endpoints and their request/response schemas. All APIs use the data contracts defined above to ensure consistency across the system.

---

### Data Tier APIs

### Data Ingestion APIs

#### Point Cloud Data Ingestion

**Endpoint**: `POST /api/data-ingest/pointcloud`  
**Description**: Upload raw point cloud files with metadata for processing

```json
// Request
Content-Type: multipart/form-data
{
  "file": "<LAS/LAZ_FILE>",
  "metadata": {
    "location_id": "string",
    "scan_date": "2025-06-12T10:30:00Z",
    "sensor_type": "TLS|UAV_LiDAR|ALS",
    "scanner_model": "string",
    "point_density": "number",
    "coordinate_system": "EPSG:4326",
    "quality_metrics": {
      "coverage_percentage": "number",
      "noise_level": "number",
      "registration_error": "number"
    }
  }
}

// Response (Success)
{
  "status": "success",
  "pointcloud_id": "uuid",
  "upload_timestamp": "2025-06-12T10:35:00Z",
  "file_size_mb": "number",
  "point_count": "number",
  "processing_status": "uploaded|queued|processing|completed|failed"
}

// Response (Error)
{
  "status": "error",
  "error_code": "INVALID_FILE_FORMAT|FILE_TOO_LARGE|DUPLICATE_UPLOAD",
  "message": "string",
  "details": "string"
}
```

#### EcoSense Sensor Data Ingestion

**Endpoints**:

- MQTT Topic: `ecosense/sensor/reading`
- HTTP: `POST /api/data-ingest/sensor-data`
- WebSocket: `/ws/sensor-stream`

```json
// MQTT Payload / HTTP Request Body
{
  "sensor_id": "string",
  "location_id": "string", 
  "timestamp": "2025-06-12T10:30:00Z",
  "readings": [
    {
      "measurement_type": "soil_moisture|temperature|humidity|ph|co2|light_intensity",
      "value": "number",
      "unit": "string",
      "quality_flag": "good|questionable|bad|missing",
      "calibration_date": "2025-06-01T00:00:00Z"
    }
  ],
  "battery_level": "number",
  "signal_strength": "number",
  "device_status": "active|low_battery|maintenance_required|offline"
}

// HTTP Response (Success)
{
  "status": "success",
  "reading_ids": ["uuid"],
  "processed_timestamp": "2025-06-12T10:30:05Z",
  "validation_results": {
    "passed": "boolean",
    "warnings": ["string"],
    "anomalies_detected": ["string"]
  }
}

// HTTP Response (Error)
{
  "status": "error",
  "error_code": "INVALID_SENSOR_ID|TIMESTAMP_OUT_OF_RANGE|DUPLICATE_READING",
  "message": "string",
  "rejected_readings": ["object"]
}

// WebSocket Real-time Stream Format
{
  "event_type": "sensor_reading|sensor_alert|sensor_offline",
  "data": {
    // Same structure as MQTT payload above
  },
  "stream_metadata": {
    "sequence_number": "number",
    "batch_id": "string"
  }
}
```

#### Climate/Weather Data Ingestion

**Endpoint**: `POST /api/data-ingest/weather`  
**Description**: Import climate and weather data from external sources

```json
// Request Body
{
  "location_id": "string",
  "data_source": "DWD|NOAA|MeteoBlue|local_station",
  "time_period": {
    "start_date": "2025-06-01T00:00:00Z",
    "end_date": "2025-06-12T23:59:59Z",
    "resolution": "hourly|daily|monthly"
  },
  "measurements": [
    {
      "timestamp": "2025-06-12T10:00:00Z",
      "temperature_celsius": "number",
      "humidity_percent": "number", 
      "precipitation_mm": "number",
      "wind_speed_ms": "number",
      "wind_direction_degrees": "number",
      "solar_radiation_wm2": "number",
      "atmospheric_pressure_hpa": "number",
      "quality_flags": {
        "temperature": "good|estimated|questionable",
        "precipitation": "measured|radar_estimated|interpolated"
      }
    }
  ]
}

// Response (Success)
{
  "status": "success",
  "imported_records": "number",
  "time_range_coverage": {
    "start": "2025-06-01T00:00:00Z",
    "end": "2025-06-12T23:59:59Z",
    "gaps": ["time_range"]
  },
  "data_quality_summary": {
    "complete_records": "number",
    "estimated_values": "number",
    "missing_data_points": "number"
  }
}
```

#### Soil/Groundwater Data Ingestion

**Endpoint**: `POST /api/data-ingest/soil`  
**Description**: Upload soil analysis and groundwater monitoring data

```json
// Request Body
{
  "location_id": "string",
  "sampling_date": "2025-06-12T00:00:00Z",
  "data_type": "soil_analysis|groundwater_monitoring|continuous_sensor",
  "spatial_reference": {
    "coordinates": {
      "latitude": "number",
      "longitude": "number", 
      "elevation_m": "number"
    },
    "coordinate_system": "EPSG:4326",
    "sampling_depth_m": "number"
  },
  "soil_properties": {
    "ph": "number",
    "organic_matter_percent": "number",
    "nitrogen_mg_kg": "number",
    "phosphorus_mg_kg": "number",
    "potassium_mg_kg": "number",
    "soil_texture": {
      "sand_percent": "number",
      "silt_percent": "number", 
      "clay_percent": "number"
    },
    "bulk_density_g_cm3": "number",
    "porosity_percent": "number"
  },
  "groundwater": {
    "depth_to_water_table_m": "number",
    "water_ph": "number",
    "conductivity_us_cm": "number",
    "nitrate_mg_l": "number"
  },
  "analysis_method": "laboratory|field_measurement|sensor_reading",
  "quality_certification": "iso_certified|standard_protocol|preliminary"
}

// Response (Success)  
{
  "status": "success",
  "soil_data_id": "uuid",
  "validation_results": {
    "values_in_range": "boolean",
    "texture_sum_valid": "boolean",
    "quality_grade": "A|B|C|D"
  },
  "spatial_integration": {
    "nearest_trees": ["tree_id"],
    "affected_area_m2": "number"
  }
}
```

#### Forest Inventory Data Ingestion

**Endpoint**: `POST /api/data-ingest/inventory`  
**Description**: Upload traditional field survey data

```json
// Request Body (CSV/JSON format)
{
  "survey_metadata": {
    "survey_id": "string",
    "location_id": "string",
    "survey_date": "2025-06-12T00:00:00Z",
    "surveyor": "string",
    "survey_method": "full_inventory|sample_plots|transect",
    "plot_size_m2": "number",
    "coordinate_system": "EPSG:4326"
  },
  "trees": [
    {
      "tree_tag": "string",
      "coordinates": {
        "latitude": "number",
        "longitude": "number",
        "elevation_m": "number"
      },
      "species": {
        "scientific_name": "string",
        "common_name": "string", 
        "species_code": "string"
      },
      "measurements": {
        "dbh_cm": "number",
        "height_m": "number",
        "crown_diameter_m": "number",
        "crown_height_m": "number",
        "stem_quality": "1|2|3|4|5",
        "vitality": "healthy|stressed|declining|dead"
      },
      "health_indicators": {
        "defoliation_percent": "number",
        "crown_transparency_percent": "number", 
        "pest_damage": "none|light|moderate|severe",
        "disease_signs": ["string"]
      },
      "measurement_precision": {
        "dbh_precision_cm": "number",
        "height_method": "hypsometer|measuring_tape|estimation",
        "gps_accuracy_m": "number"
      }
    }
  ]
}

// Response (Success)
{
  "status": "success", 
  "imported_trees": "number",
  "validation_summary": {
    "coordinates_validated": "number",
    "species_verified": "number",
    "measurement_outliers": "number",
    "duplicate_detections": "number"
  },
  "integration_results": {
    "matched_with_pointcloud": "number",
    "new_tree_records": "number",
    "updated_existing_records": "number"
  },
  "quality_assessment": {
    "overall_grade": "A|B|C|D",
    "precision_metrics": {
      "spatial_accuracy": "high|medium|low",
      "measurement_consistency": "high|medium|low"
    }
  }
}
```

### Storage System APIs

#### Point Cloud Database

**Endpoints**:

- `PUT /api/pointcloud/{id}` - Update point cloud metadata/status
- `GET /api/process/result/{job_id}` - Retrieve processing results

```json
// PUT /api/pointcloud/{id} - Update Request
{
  "processing_status": "uploaded|segmented|classified|completed|failed",
  "quality_metrics": {
    "point_density_per_m2": "number",
    "coverage_percentage": "number",
    "noise_level": "number",
    "ground_classification_accuracy": "number"
  },
  "segmentation_results": {
    "trees_detected": "number",
    "algorithm_used": "TreeLearn|3DFin|custom",
    "confidence_scores": {
      "min": "number",
      "max": "number", 
      "average": "number"
    }
  },
  "classification_results": {
    "species_identified": ["species_code"],
    "classification_confidence": "number",
    "unclassified_trees": "number"
  }
}

// GET /api/process/result/{job_id} - Response
{
  "job_id": "uuid",
  "pointcloud_id": "uuid",
  "processing_type": "segmentation|classification|qsm_generation",
  "status": "completed|failed|in_progress",
  "results": {
    "output_files": [
      {
        "file_type": "segmented_trees|classified_trees|qsm_data",
        "file_path": "string",
        "file_size_mb": "number",
        "format": "LAS|PLY|JSON|OBJ"
      }
    ],
    "tree_segments": [
      {
        "tree_id": "uuid",
        "species_prediction": "string",
        "confidence": "number",
        "bounding_box": {
          "min_x": "number", "min_y": "number", "min_z": "number",
          "max_x": "number", "max_y": "number", "max_z": "number"
        },
        "point_count": "number"
      }
    ],
    "processing_metrics": {
      "processing_time_seconds": "number",
      "memory_usage_gb": "number",
      "algorithm_parameters": "object"
    }
  }
}
```

#### Tree Database

**Endpoints**:

- `PUT /api/tree/{tree_id}` - Update tree attributes
- `GET /api/tree/{tree_id}` - Retrieve tree data
- `POST /api/tree` - Create new tree record

```json
// PUT /api/tree/{tree_id} - Update Request
{
  "variant_type": "original|growth_simulation|species_replacement|manual_edit",
  "scenario_id": "uuid", 
  "measurements": {
    "height_m": "number",
    "dbh_cm": "number", 
    "crown_width_m": "number",
    "crown_height_m": "number",
    "volume_m3": "number",
    "biomass_kg": "number"
  },
  "measurement_quality": {
    "height_quality": "Direct_Measurement|Point_Cloud_Derived|Model_Estimated",
    "dbh_quality": "Direct_Measurement|Point_Cloud_Derived|Model_Estimated",
    "crown_width_quality": "Direct_Measurement|Point_Cloud_Derived|Model_Estimated"
  },
  "health_status": {
    "vitality": "healthy|stressed|declining|dead",
    "defoliation_percent": "number",
    "pest_damage": "none|light|moderate|severe",
    "disease_indicators": ["string"]
  },
  "growth_simulation_data": {
    "model_type": "SILVA|BALANCE|iLand|hybrid",
    "time_delta_years": "number",
    "growth_rate": "number",
    "mortality_risk_probability": "number",
    "environmental_stress_factors": {
      "drought_stress": "number",
      "temperature_stress": "number", 
      "competition_index": "number"
    }
  },
  "structure_data": {
    "qsm_id": "uuid",
    "l_system_parameters": "object",
    "branch_count": "number",
    "leaf_count": "number"
  }
}

// GET /api/tree/{tree_id} - Response  
{
  "tree_id": "uuid",
  "variant_id": "uuid",
  "location_data": {
    "location_id": "uuid",
    "coordinates": {
      "latitude": "number",
      "longitude": "number",
      "elevation_m": "number"
    }
  },
  "species": {
    "species_id": "uuid", 
    "scientific_name": "string",
    "common_name": "string"
  },
  "current_measurements": {
    // Same structure as PUT request measurements
  },
  "historical_variants": [
    {
      "variant_id": "uuid",
      "timestamp": "2025-06-12T10:30:00Z",
      "variant_type": "string",
      "measurements": "object"
    }
  ],
  "associated_structures": [
    {
      "structure_id": "uuid",
      "structure_type": "QSM|L_System|DeepTree",
      "creation_date": "2025-06-12T10:30:00Z",
      "model_version": "string"
    }
  ]
}
```

#### Environment Database

**Endpoints**:

- `PUT /api/environment/{env_id}` - Update environmental record
- `GET /api/environment/query` - Query environmental data
- `POST /api/environment/snapshot` - Create environmental snapshot

```json
// GET /api/environment/query - Request
{
  "location_id": "uuid",
  "time_range": {
    "start": "2025-06-01T00:00:00Z",
    "end": "2025-06-12T23:59:59Z"
  },
  "measurement_types": ["temperature|humidity|soil_moisture|precipitation"],
  "aggregation": {
    "temporal_resolution": "hourly|daily|weekly|monthly",
    "spatial_radius_m": "number",
    "statistical_method": "mean|median|min|max|sum"
  },
  "data_quality_filter": {
    "min_quality": "good|questionable|bad",
    "exclude_estimated": "boolean"
  }
}

// GET /api/environment/query - Response
{
  "query_metadata": {
    "total_records": "number",
    "time_coverage": {
      "actual_start": "2025-06-01T00:00:00Z", 
      "actual_end": "2025-06-12T23:59:59Z",
      "data_gaps": ["time_range"]
    },
    "spatial_coverage": {
      "center_point": {"lat": "number", "lon": "number"},
      "radius_m": "number",
      "sensor_count": "number"
    }
  },
  "time_series_data": [
    {
      "timestamp": "2025-06-12T10:00:00Z",
      "measurements": {
        "temperature_celsius": {
          "value": "number",
          "quality": "good|questionable|bad",
          "source": "sensor_id|interpolated|estimated"
        },
        "humidity_percent": {
          "value": "number", 
          "quality": "good|questionable|bad",
          "source": "sensor_id|interpolated|estimated"
        },
        "soil_moisture_percent": {
          "value": "number",
          "depth_cm": "number",
          "quality": "good|questionable|bad", 
          "source": "sensor_id|interpolated|estimated"
        }
      },
      "spatial_context": {
        "representative_area_m2": "number",
        "interpolation_confidence": "number"
      }
    }
  ],
  "statistical_summary": {
    "temperature": {
      "mean": "number", "min": "number", "max": "number",
      "standard_deviation": "number"
    },
    "humidity": {
      "mean": "number", "min": "number", "max": "number", 
      "standard_deviation": "number"
    }
  }
}

// POST /api/environment/snapshot - Create Environmental Snapshot
{
  "location_id": "uuid",
  "snapshot_date": "2025-06-12T12:00:00Z",
  "aggregation_period": "daily|weekly|monthly",
  "environmental_conditions": {
    "climate": {
      "temperature_mean_celsius": "number",
      "precipitation_total_mm": "number",
      "humidity_mean_percent": "number",
      "solar_radiation_mean_wm2": "number"
    },
    "soil": {
      "moisture_mean_percent": "number",
      "temperature_mean_celsius": "number",
      "ph": "number",
      "nutrient_availability_index": "number"
    },
    "stress_indicators": {
      "drought_index": "number",
      "heat_stress_days": "number",
      "frost_risk": "low|medium|high"
    }
  }
}
```

---

### Logic Tier APIs

### Point Cloud Processing APIs

#### Tree Segmentation

**Endpoints**:

- `POST /api/process/segment` - Start segmentation job
- `GET /api/process/segment/{job_id}/status` - Check job status

```json
// POST /api/process/segment - Request
{
  "pointcloud_id": "uuid",
  "algorithm_config": {
    "algorithm": "TreeLearn|3DFin|watershed|region_growing",
    "parameters": {
      "min_tree_height_m": "number",
      "max_tree_height_m": "number", 
      "crown_diameter_range_m": [1.0, 25.0],
      "point_density_threshold": "number",
      "clustering_epsilon": "number",
      "minimum_points_per_tree": "number"
    },
    "quality_filters": {
      "remove_noise": "boolean",
      "ground_filtering": "boolean",
      "vegetation_filtering": "boolean"
    }
  },
  "output_format": "LAS|PLY|JSON",
  "priority": "low|normal|high"
}

// Response (Job Submitted)
{
  "status": "accepted", 
  "job_id": "uuid",
  "estimated_processing_time_minutes": "number",
  "queue_position": "number"
}

// GET /api/process/segment/{job_id}/status - Response
{
  "job_id": "uuid",
  "status": "queued|processing|completed|failed",
  "progress_percent": "number",
  "processing_details": {
    "current_stage": "preprocessing|segmentation|validation|output",
    "trees_detected": "number",
    "processing_time_elapsed_seconds": "number"
  },
  "results": {
    "segmented_trees": [
      {
        "tree_segment_id": "uuid",
        "point_count": "number", 
        "bounding_box": {
          "min_x": "number", "min_y": "number", "min_z": "number",
          "max_x": "number", "max_y": "number", "max_z": "number"
        },
        "estimated_height_m": "number",
        "confidence_score": "number"
      }
    ],
    "output_files": [
      {
        "file_path": "string",
        "file_size_mb": "number",
        "format": "LAS|PLY|JSON"
      }
    ]
  }
}
```

#### Species Classification

**Endpoint**: `POST /api/process/classify` - Start classification job

```json
// POST /api/process/classify - Request
{
  "segmentation_job_id": "uuid",
  "tree_segments": ["tree_segment_id"],
  "classification_model": {
    "model_name": "cnn_morphology|random_forest|ensemble",
    "model_version": "string",
    "confidence_threshold": "number"
  },
  "feature_extraction": {
    "morphological_features": "boolean",
    "spectral_features": "boolean", 
    "geometric_features": "boolean",
    "texture_features": "boolean"
  },
  "species_scope": "all|european_trees|coniferous|deciduous|custom_list",
  "custom_species_list": ["species_code"]
}

// Response (Classification Results)
{
  "job_id": "uuid",
  "status": "completed",
  "classification_results": [
    {
      "tree_segment_id": "uuid",
      "predictions": [
        {
          "species_code": "FASY", // Fagus sylvatica
          "scientific_name": "Fagus sylvatica",
          "common_name": "European Beech",
          "confidence": "number",
          "probability": "number"
        },
        {
          "species_code": "QUPE", // Quercus petraea  
          "scientific_name": "Quercus petraea",
          "common_name": "Sessile Oak",
          "confidence": "number",
          "probability": "number"
        }
      ],
      "best_prediction": {
        "species_code": "string",
        "confidence": "number"
      },
      "feature_importance": {
        "crown_shape": "number",
        "bark_texture": "number",
        "branching_pattern": "number",
        "leaf_characteristics": "number"
      }
    }
  ],
  "model_performance": {
    "overall_confidence": "number",
    "uncertain_classifications": "number",
    "processing_time_seconds": "number"
  }
}
```

#### Tree Attribute Extraction

**Endpoint**: `POST /api/process/extract-attributes` - Start attribute extraction

```json
// POST /api/process/extract-attributes - Request
{
  "classification_job_id": "uuid",
  "tree_segments": ["tree_segment_id"],
  "extraction_methods": {
    "height_estimation": "highest_point|alpha_shape|convex_hull",
    "dbh_estimation": "circle_fitting|ellipse_fitting|manual_slice",
    "crown_analysis": "alpha_shape|voxel_based|convex_hull",
    "volume_calculation": "voxel_counting|convex_hull|qsm_based"
  },
  "measurement_precision": {
    "height_precision_cm": "number",
    "dbh_precision_mm": "number",
    "crown_precision_cm": "number"
  },
  "quality_validation": {
    "outlier_detection": "boolean",
    "measurement_plausibility": "boolean",
    "species_specific_ranges": "boolean"
  }
}

// Response (Extracted Attributes)
{
  "job_id": "uuid",
  "status": "completed",
  "extracted_attributes": [
    {
      "tree_segment_id": "uuid",
      "measurements": {
        "height_m": {
          "value": "number",
          "precision_cm": "number",
          "method": "string",
          "confidence": "number"
        },
        "dbh_cm": {
          "value": "number", 
          "precision_mm": "number",
          "measurement_height_m": 1.3,
          "method": "string",
          "confidence": "number"
        },
        "crown_dimensions": {
          "diameter_ns_m": "number",
          "diameter_ew_m": "number",
          "height_m": "number",
          "volume_m3": "number",
          "surface_area_m2": "number"
        },
        "stem_attributes": {
          "taper": "number",
          "straightness": "number",
          "lean_angle_degrees": "number",
          "lean_direction_degrees": "number"
        }
      },
      "health_indicators": {
        "crown_transparency_percent": "number",
        "defoliation_estimate_percent": "number", 
        "dead_branch_percentage": "number",
        "crown_asymmetry": "number"
      },
      "quality_assessment": {
        "measurement_quality": "high|medium|low",
        "completeness_score": "number",
        "occlusion_effects": "none|minor|moderate|severe"
      }
    }
  ],
  "processing_summary": {
    "total_trees_processed": "number",
    "successful_extractions": "number", 
    "failed_extractions": "number",
    "average_processing_time_per_tree_seconds": "number"
  }
}
```

### Model Management APIs

#### Model Registry/Orchestrator

**Endpoints**:

- `POST /api/model/register` - Register new model
- `POST /api/model/run` - Start simulation
- `GET /api/model/status/{job_id}` - Check simulation status

```json
// POST /api/model/run - Request
{
  "simulation_config": {
    "simulation_name": "string",
    "scenario_id": "uuid",
    "time_horizon_years": "number",
    "time_step_years": "number",
    "models_to_run": ["SILVA|BALANCE|iLand"],
    "model_coupling": "sequential|parallel|ensemble"
  },
  "spatial_extent": {
    "location_id": "uuid",
    "bounding_box": {
      "min_lat": "number", "min_lon": "number",
      "max_lat": "number", "max_lon": "number"
    },
    "tree_selection": {
      "criteria": "all|species_filter|health_filter|size_filter",
      "species_codes": ["string"],
      "min_dbh_cm": "number",
      "health_states": ["healthy|stressed|declining"]
    }
  },
  "environmental_scenarios": {
    "climate_scenario": "current|rcp26|rcp45|rcp85|custom",
    "management_scenario": "no_intervention|selective_harvesting|clear_cut|continuous_cover",
    "disturbance_events": [
      {
        "event_type": "drought|storm|fire|pest_outbreak",
        "year": "number",
        "intensity": "low|medium|high",
        "affected_area_percent": "number"
      }
    ]
  },
  "output_preferences": {
    "temporal_resolution": "annual|decadal|final_only",
    "spatial_resolution": "individual_tree|stand_level|landscape_level",
    "variables_of_interest": ["biomass|carbon|biodiversity|timber_volume"],
    "export_formats": ["json|csv|geojson|netcdf"]
  }
}

// Response (Simulation Started)
{
  "status": "accepted",
  "simulation_job_id": "uuid", 
  "estimated_completion_time": "2025-06-12T15:30:00Z",
  "models_scheduled": [
    {
      "model_name": "SILVA",
      "model_job_id": "uuid",
      "priority": "number",
      "dependencies": ["string"]
    }
  ]
}

// GET /api/model/status/{job_id} - Response
{
  "simulation_job_id": "uuid",
  "overall_status": "queued|running|completed|failed|cancelled",
  "progress_percent": "number",
  "model_status": [
    {
      "model_name": "SILVA",
      "model_job_id": "uuid", 
      "status": "queued|running|completed|failed",
      "progress_percent": "number",
      "current_simulation_year": "number",
      "processing_time_elapsed_minutes": "number"
    }
  ],
  "preliminary_results": {
    "trees_simulated": "number",
    "mortality_events": "number",
    "biomass_change_percent": "number"
  }
}
```

#### SILVA Model Integration

**Endpoint**: `POST /api/silva/simulate` - Execute SILVA simulation (internal)

```json
// POST /api/silva/simulate - Request (Internal)
{
  "silva_config": {
    "model_version": "2.3.1",
    "calibration_region": "Baden_Wuerttemberg|Bavaria|Germany|Europe",
    "site_quality_index": "number"
  },
  "tree_data": [
    {
      "tree_id": "uuid",
      "species_code": "string",
      "age_years": "number",
      "dbh_cm": "number",
      "height_m": "number",
      "coordinates": {"x": "number", "y": "number"},
      "competition_indices": {
        "bal": "number", // Basal area of larger trees
        "distance_dependent_index": "number"
      }
    }
  ],
  "environmental_data": {
    "site_conditions": {
      "elevation_m": "number",
      "slope_degrees": "number",
      "aspect_degrees": "number",
      "soil_type": "string",
      "soil_depth_cm": "number",
      "water_availability_index": "number"
    },
    "climate_data": {
      "annual_temperature_celsius": "number",
      "annual_precipitation_mm": "number",
      "growing_season_length_days": "number",
      "climate_trend": "stable|warming|cooling"
    }
  },
  "management_actions": [
    {
      "year": "number",
      "action_type": "thinning|harvesting|planting",
      "intensity": "number",
      "target_trees": ["tree_id"],
      "removal_criteria": {
        "diameter_threshold_cm": "number",
        "species_preference": ["string"]
      }
    }
  ],
  "simulation_parameters": {
    "time_horizon_years": "number",
    "mortality_model": "deterministic|stochastic",
    "regeneration_model": "automatic|manual|none"
  }
}

// Response (SILVA Results)  
{
  "silva_job_id": "uuid",
  "status": "completed",
  "simulation_results": {
    "annual_results": [
      {
        "year": "number",
        "tree_states": [
          {
            "tree_id": "uuid",
            "status": "alive|harvested|natural_mortality",
            "dbh_cm": "number",
            "height_m": "number", 
            "biomass_kg": "number",
            "volume_m3": "number",
            "crown_ratio": "number",
            "growth_stress": "number"
          }
        ],
        "stand_metrics": {
          "total_volume_m3_ha": "number",
          "total_biomass_kg_ha": "number",
          "trees_per_ha": "number",
          "mean_dbh_cm": "number",
          "basal_area_m2_ha": "number"
        },
        "regeneration": [
          {
            "species_code": "string", 
            "new_trees": "number",
            "survival_rate": "number"
          }
        ]
      }
    ],
    "management_outcomes": {
      "harvested_volume_m3": "number",
      "carbon_sequestration_kg": "number",
      "economic_value_euros": "number"
    }
  }
}
```

---

### Presentation Tier APIs

### API Gateway

#### REST API Examples

**Tree Data Retrieval**: `GET /api/tree/{id}`

```json
// Response
{
  "tree_id": "uuid",
  "location": {
    "location_id": "uuid",
    "coordinates": {"lat": "number", "lon": "number", "elevation_m": "number"}
  },
  "species": {
    "scientific_name": "string",
    "common_name": "string",
    "species_code": "string"
  },
  "current_state": {
    "measurements": {
      "height_m": "number",
      "dbh_cm": "number", 
      "crown_width_m": "number",
      "biomass_kg": "number"
    },
    "health": {
      "vitality": "healthy|stressed|declining|dead",
      "defoliation_percent": "number"
    },
    "last_updated": "2025-06-12T10:30:00Z"
  },
  "growth_history": [
    {
      "timestamp": "2025-01-01T00:00:00Z",
      "measurements": "object",
      "data_source": "field_measurement|simulation|point_cloud"
    }
  ],
  "available_models": [
    {
      "structure_type": "QSM|L_System|DeepTree", 
      "model_id": "uuid",
      "creation_date": "2025-06-12T10:30:00Z",
      "download_urls": {
        "glb": "string",
        "obj": "string", 
        "json": "string"
      }
    }
  ]
}
```

**Real-time Environmental Data**: `GET /api/environment/live`

```json
// Response
{
  "location_id": "uuid",
  "timestamp": "2025-06-12T10:30:00Z",
  "current_conditions": {
    "temperature_celsius": "number",
    "humidity_percent": "number",
    "soil_moisture_percent": "number",
    "wind_speed_ms": "number",
    "solar_radiation_wm2": "number"
  },
  "sensor_network_status": {
    "active_sensors": "number",
    "offline_sensors": "number",
    "last_data_update": "2025-06-12T10:29:00Z",
    "network_health": "excellent|good|degraded|critical"
  },
  "alerts": [
    {
      "alert_type": "drought_warning|equipment_failure|data_anomaly",
      "severity": "low|medium|high|critical",
      "message": "string",
      "affected_sensors": ["sensor_id"]
    }
  ]
}
```

#### GraphQL Schema Examples

```graphql
# Query Example
query GetForestData($locationId: ID!, $timeRange: TimeRange) {
  location(id: $locationId) {
    name
    coordinates {
      latitude
      longitude
      elevation
    }
    trees(filters: {healthStatus: HEALTHY}) {
      id
      species {
        scientificName
        commonName
      }
      measurements {
        height
        dbh
        crownWidth
      }
      structures {
        type
        modelUrl
        createdAt
      }
    }
    environmentalData(timeRange: $timeRange) {
      timestamp
      temperature
      humidity 
      soilMoisture
    }
    simulations {
      id
      modelType
      status
      results {
        biomassProjection
        carbonSequestration
      }
    }
  }
}
```

#### WebSocket Real-time Updates

```json
// WebSocket Message Format
{
  "event_type": "tree_update|environment_change|simulation_progress|user_action",
  "timestamp": "2025-06-12T10:30:00Z",
  "data": {
    "tree_update": {
      "tree_id": "uuid",
      "change_type": "measurement_update|health_change|structure_update",
      "new_values": "object",
      "previous_values": "object"
    },
    "environment_change": {
      "location_id": "uuid", 
      "sensor_id": "string",
      "measurement_type": "string",
      "new_value": "number",
      "alert_triggered": "boolean"
    },
    "simulation_progress": {
      "simulation_id": "uuid",
      "progress_percent": "number",
      "current_year": "number",
      "preliminary_results": "object"
    }
  },
  "affected_clients": ["client_session_id"],
  "requires_ui_update": "boolean"
}
```

### Client Application APIs

#### Virtual Tree Model (XR Application)

**3D Model Request**: `GET /api/tree/{id}/model`

```json
// Request
{
  "tree_id": "uuid",
  "model_type": "QSM|L_System|DeepTree|hybrid",
  "level_of_detail": "high|medium|low",
  "output_format": "glb|obj|fbx|usd",
  "include_animations": "boolean",
  "temporal_state": {
    "target_date": "2025-06-12T00:00:00Z",
    "growth_simulation_id": "uuid"
  }
}

// Response - 3D Model Data
{
  "model_metadata": {
    "tree_id": "uuid",
    "model_version": "string",
    "creation_date": "2025-06-12T10:30:00Z",
    "model_type": "string",
    "complexity_level": "string"
  },
  "model_files": {
    "primary_model": {
      "url": "string",
      "format": "glb|obj|fbx",
      "file_size_mb": "number",
      "compression": "draco|none"
    },
    "textures": [
      {
        "texture_type": "diffuse|normal|roughness|seasonal",
        "url": "string",
        "resolution": "1024x1024|2048x2048|4096x4096"
      }
    ]
  },
  "structure_data": {
    "branch_count": "number",
    "leaf_count": "number",
    "total_vertices": "number",
    "total_triangles": "number"
  },
  "interaction_metadata": {
    "interactive_components": ["trunk|branches|leaves|crown"],
    "available_animations": ["growth|seasonal|wind"],
    "physics_properties": {
      "mass_kg": "number",
      "collision_mesh_simplified": "boolean"
    }
  }
}
```

**User Interaction Recording**: `POST /api/tree/{id}/interaction`

```json
// Request
{
  "interaction_type": "selection|measurement|annotation|modification",
  "user_session_id": "uuid",
  "timestamp": "2025-06-12T10:30:00Z",
  "interaction_data": {
    "component_selected": "trunk|branch|leaf|crown",
    "world_position": {"x": "number", "y": "number", "z": "number"},
    "measurement_taken": {
      "measurement_type": "height|diameter|distance",
      "value": "number",
      "unit": "m|cm|mm"
    },
    "annotation": {
      "text": "string",
      "category": "observation|question|issue|suggestion"
    }
  },
  "vr_context": {
    "headset_type": "Quest3|PICO4|HoloLens2",
    "user_height_m": "number",
    "room_scale": "boolean"
  }
}
```

#### Interaction Tools (Advanced Control)

**Scenario Execution**: `POST /api/scenario/run`

```json
// Request
{
  "scenario_definition": {
    "scenario_name": "string",
    "scenario_type": "climate_change|management|disturbance|species_replacement",
    "description": "string",
    "base_location_id": "uuid"
  },
  "scenario_parameters": {
    "climate_change": {
      "temperature_increase_celsius": "number",
      "precipitation_change_percent": "number",
      "co2_concentration_ppm": "number",
      "time_horizon_years": "number"
    },
    "management_actions": [
      {
        "year": "number",
        "action": "selective_harvest|clear_cut|thinning|planting",
        "intensity_percent": "number",
        "target_species": ["string"]
      }
    ],
    "disturbance_events": [
      {
        "event_type": "storm|drought|fire|pest_outbreak|disease",
        "probability": "number", 
        "intensity": "low|medium|high|extreme",
        "affected_area_percent": "number"
      }
    ]
  },
  "execution_settings": {
    "models_to_run": ["SILVA|BALANCE|iLand"],
    "parallel_execution": "boolean",
    "output_resolution": "annual|decadal",
    "comparison_baseline": "uuid"
  }
}

// Response
{
  "scenario_id": "uuid",
  "execution_status": "queued|running|completed|failed|paused",
  "progress": {
    "overall_percent": "number",
    "current_year": "number",
    "estimated_completion": "2025-06-12T15:30:00Z"
  },
  "real_time_results": {
    "trees_affected": "number",
    "mortality_events": "number", 
    "biomass_change_percent": "number",
    "carbon_flux_kg": "number"
  },
  "model_execution_status": [
    {
      "model_name": "SILVA",
      "status": "running", 
      "progress_percent": "number",
      "current_processing": "tree_growth_calculation"
    }
  ]
}
```

**Model Control Commands**: `POST /api/model/control`

```json
// Request
{
  "control_action": "pause|resume|stop|restart|update_parameters",
  "target": {
    "model_type": "SILVA|BALANCE|iLand|all",
    "simulation_id": "uuid",
    "specific_job_id": "uuid"
  },
  "control_parameters": {
    "pause_after_year": "number",
    "save_intermediate_state": "boolean",
    "parameter_updates": {
      "mortality_rate_modifier": "number",
      "growth_rate_modifier": "number",
      "climate_sensitivity": "number"
    }
  },
  "authorization": {
    "user_id": "uuid",
    "permission_level": "read|write|admin",
    "reason": "string"
  }
}
```

**WebSocket Bidirectional Control Messages**:

```json
// WebSocket Control Message Format
{
  "message_type": "control_command|status_update|user_feedback|system_alert",
  "direction": "client_to_server|server_to_client",
  "timestamp": "2025-06-12T10:30:00Z",
  "payload": {
    "control_command": {
      "command": "string",
      "parameters": "object",
      "requires_confirmation": "boolean"
    },
    "status_update": {
      "component": "string",
      "new_status": "string", 
      "details": "object"
    },
    "user_feedback": {
      "feedback_type": "confirmation|input_required|error_report",
      "message": "string",
      "options": ["string"]
    }
  },
  "response_required": "boolean",
  "priority": "low|normal|high|urgent"
}
```

---

## Common API Data Types

### Geographic Coordinates

```json
{
  "latitude": "number",    // Decimal degrees, WGS84
  "longitude": "number",   // Decimal degrees, WGS84
  "elevation_m": "number", // Meters above sea level
  "coordinate_system": "EPSG:4326|EPSG:25832|EPSG:31467" // Spatial reference system
}
```

### Time Range

```json
{
  "start": "2025-06-01T00:00:00Z", // ISO 8601 format
  "end": "2025-06-12T23:59:59Z"    // ISO 8601 format
}
```

### Bounding Box

```json
{
  "min_x": "number", "min_y": "number", "min_z": "number",
  "max_x": "number", "max_y": "number", "max_z": "number"
}
```

### File Reference

```json
{
  "file_path": "string",        // Absolute path or URL
  "file_size_mb": "number",     // File size in megabytes
  "format": "LAS|PLY|JSON|OBJ|GLB", // File format
  "compression": "draco|none|gzip",  // Compression method
  "checksum": "string"          // File integrity hash
}
```

### Quality Metrics

```json
{
  "quality_grade": "A|B|C|D",     // Overall quality assessment
  "confidence": "number",         // 0.0 to 1.0
  "precision": "number",          // Measurement precision
  "accuracy": "number",           // Measurement accuracy
  "completeness": "number",       // Data completeness 0.0 to 1.0
  "method": "string"              // Method used for measurement/estimation
}
```

---

## Error Handling

### Standard Error Response Format

```json
{
  "status": "error",
  "error_code": "ERROR_TYPE_SPECIFIC_CODE",
  "message": "Human-readable error description",
  "details": "Additional technical details",
  "timestamp": "2025-06-12T10:30:00Z",
  "request_id": "uuid",
  "suggested_action": "string"
}
```

### Common Error Codes

| Error Code | Description | HTTP Status |
|------------|-------------|-------------|
| `INVALID_FILE_FORMAT` | Uploaded file format not supported | 400 |
| `FILE_TOO_LARGE` | File exceeds maximum size limit | 413 |
| `DUPLICATE_UPLOAD` | File already exists in system | 409 |
| `INVALID_COORDINATES` | Geographic coordinates out of valid range | 400 |
| `SENSOR_OFFLINE` | Requested sensor is not responding | 503 |
| `PROCESSING_FAILED` | Point cloud processing failed | 500 |
| `MODEL_NOT_FOUND` | Requested model does not exist | 404 |
| `SIMULATION_TIMEOUT` | Model simulation exceeded time limit | 408 |
| `INSUFFICIENT_DATA` | Not enough data for requested operation | 422 |
| `AUTHORIZATION_REQUIRED` | User lacks required permissions | 403 |
| `RATE_LIMIT_EXCEEDED` | Too many requests in time window | 429 |

### Validation Error Format

```json
{
  "status": "validation_error",
  "error_code": "VALIDATION_FAILED",
  "message": "Request validation failed",
  "validation_errors": [
    {
      "field": "measurements.height_m",
      "error": "Value must be between 0.1 and 100.0",
      "provided_value": "-5.2",
      "expected_type": "number"
    }
  ],
  "timestamp": "2025-06-12T10:30:00Z",
  "request_id": "uuid"
}
```

---

## API Versioning

All APIs use semantic versioning in the URL path:

- **Current Version**: `v1`
- **URL Format**: `/api/v1/endpoint`
- **Deprecation Policy**: 6 months notice before removing old versions
- **Version Header**: `X-API-Version: 1.0`

### Version Compatibility

```json
// API Version Information Response
{
  "current_version": "1.0",
  "supported_versions": ["1.0"],
  "deprecated_versions": [],
  "sunset_dates": {},
  "changelog_url": "https://docs.xr-forests.uni-freiburg.de/api/changelog"
}
```

---

## API Types and Interface Patterns

### What is an API?

An **API** (Application Programming Interface) is a set of rules and protocols that allows different software components to communicate and exchange data or functions. It acts as a contract between systems, specifying how requests and responses should be structured and what operations are available.

**Key Elements of an API:**

- **Endpoints:** URLs or paths for accessing specific functions or data
- **Methods:** Operations like GET (retrieve), POST (create), PUT (update), DELETE (remove)
- **Request/Response Formats:** Data structures (often JSON or XML) for communication
- **Parameters/Headers:** Additional data for filtering, authentication, etc.
- **Status Codes:** Indicate the result of a request (e.g., 200 OK, 404 Not Found)

### Types of APIs in the XR Future Forests Lab Architecture

#### Data Ingestion API

**Purpose:** Handles the intake of new data from external sources (sensors, field uploads, external datasets)

**How it works:** Provides endpoints for batch uploads (CSV, LAS/LAZ files) and streaming data (sensor feeds via WebSocket or MQTT)

**Example Endpoints:**

- `POST /api/data-ingest/pointcloud` for batch uploads
- `POST /api/data-ingest/sensor-data` for real-time sensor data
- MQTT Topic: `ecosense/sensor/reading` for streaming

#### Processing Pipeline API

**Purpose:** Manages the submission, monitoring, and results of data processing tasks (tree segmentation, classification)

**How it works:** Exposes endpoints to submit jobs, check status, and retrieve results with asynchronous processing and completion notifications

**Example Endpoints:**

- `POST /api/process/segment` (submit new segmentation job)
- `GET /api/process/status/{job_id}` (check job status)
- `GET /api/process/result/{job_id}` (retrieve results)

#### DB Update API

**Purpose:** Allows authorized components to create, update, or delete records in the databases

**How it works:** Provides endpoints for CRUD operations on database records, ensuring data integrity and access control

**Example Endpoints:**

- `PUT /api/tree/{id}` (update tree attributes)
- `POST /api/tree` (create new tree record)
- `DELETE /api/environment/{id}` (remove environmental record)

#### Model/Simulation Control API

**Purpose:** Allows clients to trigger, pause, or modify model runs and simulations

**How it works:** Endpoints for starting/stopping simulations, updating parameters, and retrieving results

**Example Endpoints:**

- `POST /api/model/run` (start simulation)
- `GET /api/model/status/{job_id}` (check simulation status)
- `POST /api/model/control` (pause/resume simulation)

#### Event Bus

**Purpose:** Enables real-time, asynchronous communication between components

**How it works:** Uses publish/subscribe protocols (MQTT, Kafka, WebSockets) where components subscribe to topics and receive messages as events occur

**Example Topics:**

- `sensor-updates` for broadcasting new sensor readings
- `tree-updates` for tree state changes
- `simulation-progress` for model execution updates

#### REST/GraphQL API

**Purpose:** Provides standardized web-based access to backend services and data for clients

**How it works:**

- **REST:** Uses HTTP methods and endpoints for each resource with stateless operations
- **GraphQL:** Allows clients to specify exactly what data they need in a single query

**Examples:**

- REST: `GET /api/tree/123` (get tree with ID 123)
- GraphQL: `query { tree(id: 123) { species, height, health } }`

### API Type Comparison

| API Type | Purpose/Flow | Typical Protocols | Example Use Case |
|----------|--------------|------------------|------------------|
| Data Ingestion | Import new data into system | HTTP (REST), MQTT, WebSocket | Upload LAS files, stream sensor data |
| Processing Pipeline | Manage processing jobs | HTTP (REST), WebSocket | Submit segmentation jobs, check status |
| DB Update | CRUD operations on data stores | HTTP (REST), GraphQL | Update tree attributes, create records |
| Model/Simulation Control | Control models/simulations | HTTP (REST), gRPC, WebSocket | Start growth simulation, update parameters |
| Event Bus | Real-time notifications | WebSocket, MQTT, Kafka | Broadcast sensor updates, system events |
| REST/GraphQL | General data access | HTTP (REST), GraphQL | Query tree data, retrieve environmental info |
