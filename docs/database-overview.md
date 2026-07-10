# Digital Forest Twin - Database Overview

**XR Future Forests Lab** | Database Architecture Summary

---

## Executive Summary

The Digital Forest Twin is a PostgreSQL-based spatial database for forest research, designed to integrate LiDAR point clouds, tree measurements, environmental sensor data, and climate simulations into a unified data platform.

**Key Capabilities:**

- Multi-stem tree modeling with morphological attributes
- Temporal versioning via variant-based lineage
- Real-time sensor integration with external APIs (Aquarius)
- PostGIS spatial queries and coordinate transformations
- Field-level audit trail for reproducible science

---

## Schema Architecture

The database is organized into **6 schemas**, each handling a specific domain:

```mermaid
flowchart LR
    subgraph shared["SHARED SCHEMA"]
        direction TB
        Locations["Locations"]
        Plots["Plots"]
        Species["Species"]
        Scenarios["Scenarios"]
        VariantTypes["VariantTypes"]
        Campaigns["Campaigns"]
        Processes["Processes"]
        AuditLog["AuditLog"]
        ManagementEvents["ManagementEvents"]
        DisturbanceEvents["DisturbanceEvents"]
    end

    subgraph pointclouds["POINTCLOUDS SCHEMA"]
        ScannerTypes["ScannerTypes"]
        Scanners["Scanners"]
        PointClouds["PointClouds"]
    end

    subgraph trees["TREES SCHEMA"]
        Trees["Trees"]
        Stems["Stems"]
        TreeStatus["TreeStatus"]
        TaperTypes["TaperTypes"]
        PhenologyObservations["PhenologyObservations"]
        Deadwood["Deadwood"]
        GroundVegetation["GroundVegetation"]
        GrowthSimulations["GrowthSimulations"]
    end

    subgraph sensor["SENSOR SCHEMA"]
        Sensors["Sensors"]
        SensorReadings["SensorReadings"]
        SensorTreeLinks["SensorTreeLinks"]
    end

    subgraph environments["ENVIRONMENTS SCHEMA"]
        Environments["Environments"]
    end

    subgraph imagery["IMAGERY SCHEMA"]
        Images["Images"]
    end

    %% Cross-schema relationships
    Locations --> Plots
    Locations --> PointClouds
    Locations --> Trees
    Locations --> Sensors
    Locations --> Environments
    Locations --> Campaigns
    Locations --> Images
    Locations --> ManagementEvents
    Locations --> DisturbanceEvents
    Locations --> Deadwood
    Locations --> GroundVegetation
    Locations --> GrowthSimulations

    Plots --> Trees
    Plots --> ManagementEvents
    Plots --> DisturbanceEvents
    Plots --> Deadwood
    Plots --> GroundVegetation
    Plots --> Images
    Plots --> GrowthSimulations

    Species --> Trees
    Species --> Deadwood
    Species --> GrowthSimulations

    Scenarios --> PointClouds
    Scenarios --> Trees
    Scenarios --> Environments
    Scenarios --> SensorReadings
    Scenarios --> GrowthSimulations

    VariantTypes --> PointClouds
    VariantTypes --> Trees
    VariantTypes --> Environments

    Processes --> PointClouds
    Processes --> Trees
    Processes --> Environments

    Campaigns --> PointClouds
    Campaigns --> Trees
    Campaigns --> Sensors
    Campaigns --> Images

    PointClouds --> Trees
    TreeStatus --> Trees
    Trees --> Stems
    Trees --> PhenologyObservations
    Trees --> GrowthSimulations
    TaperTypes --> Stems
    DisturbanceEvents --> Trees
    ScannerTypes --> Scanners
    Scanners --> PointClouds
    Sensors --> SensorReadings
    Sensors --> SensorTreeLinks
    SensorTreeLinks --> Trees

    style shared fill:#F4EFA9,stroke:#c7bb1a
    style pointclouds fill:#e8e8e8,stroke:#4f4f4f
    style trees fill:#5CB89C,stroke:#19392f
    style sensor fill:#eeb896,stroke:#673428
    style environments fill:#8fa8c8,stroke:#181d26
    style imagery fill:#d4a5e5,stroke:#5a2d6a
    classDef cShared fill:#FAF6D2,stroke:#c7bb1a,color:#4a4500;
    classDef cPc fill:#f5f5f5,stroke:#4f4f4f,color:#2a2a2a;
    classDef cTrees fill:#b9e3d4,stroke:#19392f,color:#0c241c;
    classDef cSensor fill:#f6ddcb,stroke:#673428,color:#3c1d13;
    classDef cEnv fill:#c3d2e3,stroke:#181d26,color:#10151d;
    classDef cImg fill:#e7cbf1,stroke:#5a2d6a,color:#321640;
    class Locations,Plots,Species,Scenarios,VariantTypes,Campaigns,Processes,AuditLog,ManagementEvents,DisturbanceEvents cShared;
    class ScannerTypes,Scanners,PointClouds cPc;
    class Trees,Stems,TreeStatus,TaperTypes,PhenologyObservations,Deadwood,GroundVegetation,GrowthSimulations cTrees;
    class Sensors,SensorReadings,SensorTreeLinks cSensor;
    class Environments cEnv;
    class Images cImg;
```

**Schema colour key:**

| | Schema | Domain |
|---|---|---|
| 🟨 | `shared` | Reference & audit tables used across all domains |
| ⬜ | `pointclouds` | LiDAR scans and scanner hardware |
| 🟩 | `trees` | Tree inventory, stems, morphology, phenology |
| 🟧 | `sensor` | Environmental sensors and time-series readings |
| 🟦 | `environments` | Aggregated environmental conditions |
| 🟪 | `imagery` | Aerial and ground imagery |

---

## Schema Details

### 1. 🟨 Shared Schema

Central reference tables used across all domains.

| Table | Purpose |
|-------|---------|
| **Locations** | Research sites (`ecosense`, `mathisle`) with PostGIS boundaries, elevation, slope, soil type |
| **Plots** | Named monitoring sub-areas within a location (e.g. `douglas_fir_plot`, tree subplots) |
| **Species** | Tree species (common name, scientific name, growth characteristics, is_deciduous) |
| **Scenarios** | Location-scoped management regimes (Location → Scenario → Variant); e.g. `natural_growth` per site |
| **VariantTypes** | How a variant's data was produced: original, processed, manual, simulated_growth, user_input, sensor_derived, model_output, repeat_measurement |
| **Campaigns** | Data collection events (LiDAR flights, field inventories) with methodology |
| **Processes** | Algorithm/processing metadata with citations |
| **AuditLog** | Field-level change tracking with user attribution |
| **ManagementEvents** | Forest management activities (thinning, planting, harvesting) |
| **DisturbanceEvents** | Natural disturbance events (storms, fire, insects, drought) |

### 2. ⬜ PointClouds Schema

LiDAR scan data and processing variants with scanner hardware tracking.

**Scanner Reference Tables:**

| Table | Purpose |
|-------|---------|
| **ScannerTypes** | LiDAR scanner type classifications (Terrestrial_TLS, Aerial_ALS, Mobile_MLS, UAV_ULS) with manufacturers |
| **Scanners** | Individual scanner hardware instances with serial numbers, acquisition and calibration dates |

**PointClouds Table:**

| Field | Description |
|-------|-------------|
| point_cloud_id | Unique row identifier |
| parent_point_cloud_id | Links to source point cloud for processing lineage |
| campaign_id | Links scan to data collection campaign |
| scanner_id | Physical scanner hardware used for this scan |
| scan_date | Acquisition timestamp |
| file_path | S3/storage reference |
| source_crs | EPSG code of original coordinate reference system |
| platform_type | Scanning platform: terrestrial, aerial, mobile, UAV |
| flight_altitude_m | Flight altitude above ground (for aerial/UAV) |
| flight_speed_ms | Platform speed during scanning in m/s |
| scan_angle_deg | Scanner field of view angle in degrees |
| Overlap_percent | Swath overlap percentage (for aerial scans) |
| point_count | Number of points |
| point_density_per_m2 | Average point density in points per square meter |
| processing_status | pending, processing, completed, failed, cancelled |

### 3. 🟩 Trees Schema

Individual tree measurements with multi-stem support.

```mermaid
erDiagram
    Trees {
        int tree_id PK
        uuid tree_entity_id "Persistent tree identity"
        int variant_id FK "Forest state group"
        int parent_tree_id FK
        int campaign_id FK
        int location_id FK
        int plot_id FK
        int species_id FK
        int tree_status_id FK
        date measurement_date
        varchar DataSourceType
        float Height_m
        float Volume_m3
        geometry Position
        geometry position_original
        int source_crs "EPSG code"
        float crown_offset_x_m
        float crown_offset_y_m
        float Age_years
        float health_score
        float carbon_content_kg
        float species_confidence
        float position_confidence
        float height_confidence
        date status_change_date
    }

    Stems {
        int stem_id PK
        int tree_id FK
        int stem_number
        float DBH_cm
        int taper_type_id FK
        int straightness_type_id FK
        float stem_volume_m3
    }

    PhenologyObservations {
        int phenology_observation_id PK
        int tree_id FK
        date observation_date
        varchar phenophase_type
        varchar phenophase_status
        float Intensity_percent
        varchar Observer
    }

    Deadwood {
        int deadwood_id PK
        int location_id FK
        int plot_id FK
        int tree_id FK
        int species_id FK
        varchar wood_type
        float Length_m
        float Diameter_cm
        int decay_class
        float Volume_m3
        geometry Position
    }

    GroundVegetation {
        int ground_vegetation_id PK
        int location_id FK
        int plot_id FK
        varchar species_name
        float cover_percent
        float Height_cm
        varchar Layer
        date measurement_date
    }

    Campaigns {
        int campaign_id PK
        varchar campaign_name
        varchar campaign_type
        date start_date
    }

    TreeStatus {
        int tree_status_id PK
        varchar tree_status_name
    }

    Trees ||--o{ Stems : "has_stems"
    Trees ||--o{ PhenologyObservations : "observed_in"
    Trees }o--|| TreeStatus : "status"
    Trees }o--|| Campaigns : "collected_in"
    Stems }o--|| TaperTypes : "taper"
```

**New Fields for Data Quality:**

| Field | Description |
|-------|-------------|
| `tree_entity_id` | Persistent UUID identifying the physical tree across all variants |
| `campaign_id` | Links measurement to data collection campaign |
| `plot_id` | Sub-plot within the location where the tree is located |
| `measurement_date` | Actual field measurement date (vs. import date) |
| `DataSourceType` | How data was collected: lidar, field, photogrammetry, estimated, simulated |
| `source_crs` | EPSG code of original coordinate reference system for position_original |
| `CrownOffsetX/Y_m` | Crown asymmetry (offset from trunk position) |
| `species_confidence` | 0-1 confidence in species identification |
| `position_confidence` | 0-1 confidence in position accuracy |
| `height_confidence` | 0-1 confidence in height measurement |
| `status_change_date` | Date when tree status changed (e.g., mortality date) |

**Morphology Lookup Tables:**

- `TaperTypes`: Cylinder, Cone, Paraboloid, Neiloid
- `StraightnessTypes`: Straight, Slight_sweep, Moderate_sweep, Severe_sweep
- `BranchingPatterns`: Alternate, Opposite, Whorled, Spiral
- `BarkCharacteristics`: Smooth, Furrowed, Plated, Exfoliating

**Additional Trees Schema Tables:**

| Table | Purpose |
|-------|---------|
| **PhenologyObservations** | Tree phenology observations tracking seasonal development phases (bud_break, leaf_out, flowering, fruit_set, leaf_color, leaf_fall, dormancy) |
| **Deadwood** | Dead wood inventory including standing dead, fallen logs, stumps, and branches with decay classification (1-5) |
| **GroundVegetation** | Ground vegetation survey records by plot and layer (herb, shrub, moss, litter, fern, grass) |
| **GrowthSimulations** | Per-tree dimensional projections from external growth simulators (SILVA, FVS, iLand, manual) at discrete future years, keyed by `run_id` and `tree_entity_id`; powers the Unreal Time Machine feature |

### 4. 🟧 Sensor Schema

Environmental monitoring hardware and time-series data.

```mermaid
erDiagram
    Sensors {
        int sensor_id PK
        int location_id FK
        int sensor_type_id FK
        int campaign_id FK
        varchar sensor_model
        varchar serial_number
        geometry Position
        geometry position_original
        int source_crs "EPSG code"
        float installation_height_m
        boolean is_active
    }

    SensorReadings {
        bigint sensor_reading_id PK
        int sensor_id FK
        timestamp Timestamp
        float Value
        varchar Unit
        varchar Quality
    }

    SensorTreeLinks {
        int SensorTreeLinkID PK
        int sensor_id FK
        int tree_id FK
        varchar Description
        date start_date
        date end_date
    }

    SensorTypes {
        int sensor_type_id PK
        varchar sensor_type_name
    }

    Sensors ||--o{ SensorReadings : "records"
    Sensors ||--o{ SensorTreeLinks : "monitors"
    Sensors }o--|| SensorTypes : "type"
```

**Sensor Types:** Temperature, Humidity, CO2, Light, Soil_Moisture, Wind, Stem_Radial_Variation, Sap_Flow

**New Sensor Columns:**

| Field | Description |
|-------|-------------|
| `campaign_id` | Deployment campaign this sensor was installed during |
| `source_crs` | EPSG code of original coordinate reference system for position_original |
| `installation_height_m` | Height of sensor installation above ground in meters |

**SensorTreeLinks** now includes `start_date` and `end_date` fields to track the temporal validity of sensor-to-tree relationships.

**External Integration:** `external_id` and `ExternalMetadata` columns enable synchronization with the Aquarius API for automated data ingestion.

### 5. 🟦 Environments Schema

Aggregated environmental conditions per location/time period.

| Field | Description |
|-------|-------------|
| avg_temperature_c | Mean temperature |
| avg_humidity_percent | Mean humidity |
| total_precipitation_mm | Precipitation total |
| avg_soil_moisture_percent | Soil moisture |
| stress_factor | 0.0-1.0 combined stress indicator |
| nutrient_nitrogen_mg_kg | Soil nitrogen content |

---

## Key Design Patterns

### Persistent Tree Identity

The `tree_entity_id` (UUID) provides a stable identifier for physical trees across all measurement variants:

```mermaid
flowchart TB
    subgraph Physical["Physical Tree in Forest"]
        Tree["tree_entity_id: abc-123"]
    end

    subgraph Variants["Measurement Variants"]
        V1["tree_id: 1<br/>Campaign: 2024 Inventory<br/>Height: 15.2m"]
        V2["tree_id: 5<br/>Campaign: 2025 Inventory<br/>Height: 15.8m"]
        V3["tree_id: 12<br/>Campaign: LiDAR 2025<br/>Height: 15.9m"]
    end

    Tree --> V1
    Tree --> V2
    Tree --> V3
    V1 -.->|parent_tree_id| V2
    V2 -.->|parent_tree_id| V3

    style Physical fill:#2d5a3d,color:#fff
    style V1 fill:#5CB89C
    style V2 fill:#8fd4b8
    style V3 fill:#c5e8d8
```

### Campaign-Based Data Collection

Campaigns track data collection events with full methodology:

| Campaign Type | Example |
|---------------|---------|
| `lidar_flight` | Annual LiDAR acquisition flight |
| `field_inventory` | Ground-based tree measurements |
| `sensor_deployment` | Installation of environmental sensors |
| `drone_survey` | UAV-based photogrammetry |
| `manual_update` | Individual tree corrections |

**Workflow:**

1. Create Campaign record with dates, methodology, equipment
2. Import data with `campaign_id` reference
3. Set `variant_type_id` = "repeat_measurement" for follow-up surveys
4. Link to parent tree row via `parent_tree_id` using `tree_entity_id` matching

### Variant-Based Lineage

All core entities (PointClouds, Trees, Environments) use a parent-child versioning pattern:

```mermaid
flowchart LR
    subgraph Lineage["Tree Variant Lineage"]
        V1["Variant 1<br/>Original Field Survey"]
        V2["Variant 2<br/>LiDAR Processed"]
        V3["Variant 3<br/>Growth Simulation +5yr"]
        V4["Variant 4<br/>Manual Correction"]
    end

    V1 --> V2
    V2 --> V3
    V2 --> V4

    style V1 fill:#5CB89C
    style V2 fill:#8fd4b8
    style V3 fill:#c5e8d8
    style V4 fill:#c5e8d8
```

**Benefits:**

- Full temporal history of measurements
- Compare different processing algorithms
- Reproducible simulation scenarios
- Non-destructive updates

### Data Quality Tracking

Per-field confidence scores enable quality-aware analysis:

```sql
-- Find trees with uncertain species identification
SELECT tree_entity_id, species_id, species_confidence
FROM trees.trees
WHERE species_confidence < 0.8
ORDER BY species_confidence;

-- Compare LiDAR vs field measurements
SELECT tree_entity_id, DataSourceType, Height_m, height_confidence
FROM trees.trees
WHERE tree_entity_id = 'abc-123'
ORDER BY measurement_date;
```

### Spatial Data (PostGIS)

All positions stored as PostGIS geometries:

```sql
Position         -- WGS84 (EPSG:4326) for standardized queries
position_original -- Original CRS preserved (e.g., EPSG:32632)
Boundary         -- Polygon geometries for locations
```

### Audit Trail

Every data modification is tracked:

```mermaid
flowchart LR
    Change["Field Update"] --> AuditLog
    AuditLog --> |"Records"| Details["field_name<br/>old_value → new_value<br/>user_id<br/>Timestamp<br/>ip_address"]
    style AuditLog fill:#F4EFA9,stroke:#c7bb1a,color:#3a3600
    style Change fill:#f5f5f5,stroke:#4f4f4f,color:#2a2a2a
    style Details fill:#FAF6D2,stroke:#c7bb1a,color:#4a4500
```

Junction tables link audit entries to specific variants:

- `AuditLog_Trees`
- `AuditLog_PointClouds`
- `AuditLog_Environments`
- `AuditLog_Stems`

---

## Data Flow

```mermaid
flowchart TB
    subgraph Sources["Data Sources"]
        LiDAR["LiDAR Scanners"]
        Field["Field Surveys"]
        API["Aquarius API"]
        Sim["Growth Simulations"]
    end

    subgraph DB["PostgreSQL + PostGIS"]
        PC["PointClouds"]
        TR["Trees"]
        SE["Sensors"]
        SR["SensorReadings"]
        EN["Environments"]
    end

    subgraph Consumers["Consumers"]
        UE["Unreal Engine<br/>Visualization"]
        REST["REST API<br/>PostgREST"]
        Analysis["R/Python<br/>Analysis"]
    end

    LiDAR --> PC
    PC --> TR
    Field --> TR
    API --> SE
    SE --> SR
    SR --> EN
    Sim --> TR
    Sim --> EN

    TR --> REST
    EN --> REST
    REST --> UE
    REST --> Analysis

    style DB fill:#fbfbfb,stroke:#888888
    style PC fill:#f5f5f5,stroke:#4f4f4f,color:#2a2a2a
    style TR fill:#b9e3d4,stroke:#19392f,color:#0c241c
    style SE fill:#f6ddcb,stroke:#673428,color:#3c1d13
    style SR fill:#f6ddcb,stroke:#673428,color:#3c1d13
    style EN fill:#c3d2e3,stroke:#181d26,color:#10151d
```

---

## Technology Stack

| Component | Technology |
|-----------|------------|
| Database | PostgreSQL 15 + PostGIS |
| Infrastructure | Self-hosted Supabase |
| REST API | PostgREST (auto-generated) |
| Edge Functions | Deno (TypeScript) |
| Data Import | Python scripts |
| Visualization | Unreal Engine 5 |

---

## Access Patterns

### REST API (Port 8000)

```bash
# Get trees with species info
GET /rest/v1/trees?select=*,species(common_name)

# Filter by location
GET /rest/v1/trees?location_id=eq.4

# Spatial query (via RPC)
POST /rest/v1/rpc/trees_within_radius
```

### Direct SQL

```sql
-- Trees with stems at location
SELECT t.*, s.dbh_cm, sp.common_name
FROM trees.trees t
JOIN trees.stems s ON t.tree_id = s.tree_id
JOIN shared.species sp ON t.species_id = sp.species_id
WHERE t.location_id = 4;

-- Sensor readings for tree correlation
SELECT sr.timestamp, sr.value, stl.tree_id
FROM sensor.sensorreadings sr
JOIN sensor.sensor_tree_links stl ON sr.sensor_id = stl.sensor_id
WHERE sr.timestamp > NOW() - INTERVAL '30 days';
```

---

## Summary

The Digital Forest Twin database provides:

1. **Unified spatial model** for LiDAR, tree measurements, and sensors
2. **Temporal versioning** through variant lineage
3. **Multi-stem support** with detailed morphological attributes
4. **External API integration** for automated sensor data ingestion
5. **Field-level auditing** for scientific reproducibility
6. **Auto-generated REST API** for application integration

For detailed schema definitions, see [database_schema.md](database_schema.md) and [database-erd.dbml](database-erd.dbml).
