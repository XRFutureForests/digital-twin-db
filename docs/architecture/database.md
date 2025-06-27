# Database Design - XR Future Forests Lab

## Unified Database Design with Schema Organization

This design uses PostgreSQL schemas (`shared`, `pointclouds`, `trees`, `monitoring`, `environments`) to organize a unified forest monitoring database. The design supports efficient time-series sensor data storage with file references managed as simple file paths within the variant and base tables.

## Schema Overview

```mermaid
graph LR
    subgraph shared ["Shared Schema"]
        SL[Locations]
        SS[Species]
        SC[Scenarios]
    end
    
    subgraph pointclouds ["Point Clouds Schema"]
        PC[PointClouds]
        PCV[PointCloudVariants]
    end
    
    subgraph trees ["Trees Schema"]
        TV[TreeVariants]
    end
    
    subgraph monitoring ["Monitoring Schema"]
        S[Sensors]
        SR[SensorReadings]
    end
    
    subgraph environments ["Environments Schema"]
        EV[EnvironmentVariants]
    end
    
    %% Cross-schema relationships
    SL --> PC
    SL --> TV
    SL --> S
    SL --> EV
    SS --> TV
    SC --> PCV
    SC --> TV
    SC --> SR
    SC --> EV
    
    %% Within-schema relationships
    PC --> PCV
    S --> SR

    classDef sharedNodes fill:#F4EFA9,stroke:#c7bb1a,stroke-width:2px,color:#242424
    classDef pointcloudsNodes fill:#e8e8e8,stroke:#4f4f4f,stroke-width:2px,color:#242424
    classDef treesNodes fill:#5CB89C,stroke:#19392f,stroke-width:2px,color:#19392f
    classDef monitoringNodes fill:#AD5643,stroke:#673428,stroke-width:2px,color:#e8e8e8
    classDef environmentsNodes fill:#566b8a,stroke:#181d26,stroke-width:2px,color:#e8e8e8
    
    classDef sharedSubgraph fill:#F4EFA9,fill-opacity:0.3,stroke:#c7bb1a,stroke-width:2px
    classDef pointcloudsSubgraph fill:#e8e8e8,fill-opacity:0.3,stroke:#4f4f4f,stroke-width:2px
    classDef treesSubgraph fill:#5CB89C,fill-opacity:0.3,stroke:#19392f,stroke-width:2px
    classDef monitoringSubgraph fill:#eeb896,fill-opacity:0.3,stroke:#673428,stroke-width:2px
    classDef environmentsSubgraph fill:#566b8a,fill-opacity:0.3,stroke:#181d26,stroke-width:2px
    
    class SL,SS,SC sharedNodes
    class PC,PCV pointcloudsNodes
    class TV treesNodes
    class S,SR monitoringNodes
    class EV environmentsNodes
    
    class shared sharedSubgraph
    class pointclouds pointcloudsSubgraph
    class trees treesSubgraph
    class monitoring monitoringSubgraph
    class environments environmentsSubgraph

    linkStyle 0,1,2,3,4,5,6,7,8,9,10 stroke:#313D4F,stroke-width:2px
```

### Shared Schema

Contains reference tables used across all domains, providing consistent data definitions and relationships throughout the forest monitoring system.

#### Location and Environmental Context

```mermaid
erDiagram
    Locations {
        INT LocationID PK "Unique site/plot ID"
        VARCHAR LocationName "Site name"
        GEOMETRY PlotBoundary "PostGIS polygon for plot boundaries"
        GEOMETRY CenterPoint "PostGIS point for plot center coordinates"
        TEXT Description "Description of the site"
        FLOAT Elevation_m "Site elevation"
        FLOAT Slope_deg "Site slope"
        VARCHAR Aspect "N, NE, E, SE, S, SW, W, NW"
        INT SoilTypeID FK "Soil type reference"
        INT ClimateZoneTypeID FK "Climate zone reference"
    }

    SoilTypes {
        INT SoilTypeID PK
        VARCHAR SoilName "Alfisol, Andisol, Aridisol, Entisol, Gelisol, Histosol, Inceptisol, Mollisol, xisol, Spodosol, Ultisol, Vertisol"
    }

    ClimateZoneTypes {
        INT ClimateZoneTypeID PK
        VARCHAR ZoneName "Köppen climate classification codes"
    }

    SoilTypes ||--o{ Locations : soil_type
    ClimateZoneTypes ||--o{ Locations : climate_zone

    classDef table fill:#F4EFA9
    class Locations,SoilTypes,ClimateZoneTypes table
```

#### Species Reference

```mermaid
erDiagram
    Species {
        INT SpeciesID PK "Unique species ID"
        VARCHAR CommonName "Common name"
        VARCHAR ScientificName "Scientific name"
        TEXT GrowthCharacteristics "JSON: typical growth patterns"
    }

    classDef table fill:#F4EFA9
    class Species table
```

#### Scenarios and Variant Types

```mermaid
erDiagram
    Scenarios {
        INT ScenarioID PK
        VARCHAR ScenarioName "Current_Conditions, Climate_Change_2050, Drought_Test"
        VARCHAR Description "Scenario description"
    }

    VariantTypes {
        INT VariantTypeID PK
        VARCHAR TypeName "original, processed, manual, simulated_growth, user_input"
        TEXT Description "Description of variant type"
    }

    classDef table fill:#F4EFA9
    class Scenarios,VariantTypes table
```

### Point Clouds Schema

Manages LiDAR scan data and processing variants, supporting different processing algorithms and results while maintaining links to the original scan data.

```mermaid
erDiagram
    Locations
    VariantTypes
    Scenarios

    PointClouds {
        INT PointCloudID PK "Unique scan ID"
        VARCHAR FilePath "Path/URI to raw point cloud file"
        DATETIME ScanDate "Date and time of scan"
        INT LocationID FK "References shared.Locations"
        VARCHAR SensorModel "LiDAR scanner model"
        GEOMETRY ScanBounds "PostGIS polygon defining coverage"
    }

    PointCloudVariants {
        INT VariantID PK
        INT PointCloudID FK "References PointClouds"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT ScenarioID FK "References shared.Scenarios - NULL for non-scenario variants"
        INT ParentVariantID FK "Self-reference for variant lineage"
        VARCHAR VariantName "Descriptive name for variant"
        VARCHAR ProcessingAlgorithm "Algorithm used for processing"
        VARCHAR FilePath "Path to processed point cloud file"
        BIGINT PointCount "Total number of points"
        FLOAT FileSizeMB "File size in megabytes"
        VARCHAR ProcessingStatus "pending, processing, completed, failed"
        FLOAT ProcessingProgress "0.0 to 1.0"
        TIMESTAMP ProcessingStartTime
        TIMESTAMP ProcessingEndTime
        TEXT ErrorMessage
        FLOAT SegmentationConfidence "Average confidence score"
        FLOAT ClassificationConfidence "Average confidence score"
        INT ProcessedTreeCount "Number of trees detected"
    }

    Locations ||--o{ PointClouds : located_at
    VariantTypes ||--o{ PointCloudVariants : variant_type
    Scenarios ||--o{ PointCloudVariants : scenario_context
    PointClouds ||--o{ PointCloudVariants : has_variants
    PointCloudVariants ||--o{ PointCloudVariants : parent_variant

    classDef shared fill:#F4EFA9
    classDef pointcloud fill:#e8e8e8
    class Locations,VariantTypes,Scenarios shared
    class PointClouds,PointCloudVariants pointcloud
```

### Trees Schema

Manages tree measurement and simulation data through variants. Each tree variant represents a specific measurement, simulation state, or modeling result that can reference point cloud variants for detection context.

```mermaid
erDiagram
    Locations
    Species
    VariantTypes
    Scenarios

    TreeStatus {
        INT TreeStatusID PK
        VARCHAR StatusName "healthy, stressed, declining, dead"
        TEXT Description
    }

    TreeVariants {
        INT VariantID PK
        INT LocationID FK "References shared.Locations"
        INT ScenarioID FK "References shared.Scenarios"
        INT ParentVariantID FK "Self-reference for variant lineage"
        INT SpeciesID FK "References shared.Species"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT PointCloudVariantID FK "References pointclouds.PointCloudVariants - NULL if not derived from point cloud"
        FLOAT Height_m
        FLOAT DBH_cm
        FLOAT CrownWidth_m
        FLOAT CrownBaseHeight_m
        GEOMETRY CrownBoundary "PostGIS polygon"
        FLOAT Volume_m3
        INT TreeStatusID FK
        GEOMETRY Position "PostGIS point (plot coordinates)"
        FLOAT TimeDelta_yrs "Time since parent variant (for growth)"
        TIMESTAMP UpdatedAt DEFAULT NOW()
    }

    Locations ||--o{ TreeVariants : located_at
    Scenarios ||--o{ TreeVariants : scenario_context
    TreeStatus ||--o{ TreeVariants : tree_status
    Species ||--o{ TreeVariants : tree_species
    VariantTypes ||--o{ TreeVariants : variant_type
    TreeVariants ||--o{ TreeVariants : parent_variant

    classDef shared fill:#F4EFA9
    classDef tree fill:#5CB89C
    class Locations,Species,VariantTypes,Scenarios shared
    class TreeStatus,TreeVariants tree
```

### Monitoring Schema

Manages sensor hardware installations and time-series sensor readings. Base tables contain sensor metadata and installation info, while readings tables contain actual sensor measurements optimized for time-series queries.

```mermaid
erDiagram
    Locations
    Scenarios

    SensorTypes {
        INT SensorTypeID PK
        VARCHAR TypeName "Temperature, Humidity, CO2, Light, Soil_Moisture, Wind"
        TEXT Description
    }

    Sensors {
        INT SensorID PK
        INT LocationID FK "References shared.Locations"
        INT SensorTypeID FK
        VARCHAR SensorModel "Specific sensor model"
        GEOMETRY Position "Sensor position within location"
        VARCHAR ReadingType "Temperature, Humidity, etc."
        VARCHAR Unit
    }

    SensorReadings {
        BIGSERIAL ReadingID PK
        INT SensorID FK "References sensors.Sensors"
        TIMESTAMP Timestamp "Reading timestamp"
        FLOAT Value
        VARCHAR Quality "good, suspect, bad"
        INT ScenarioID FK "References shared.Scenarios - NULL for real readings"
    }

    Locations ||--o{ Sensors : located_at
    SensorTypes ||--o{ Sensors : sensor_type
    Sensors ||--o{ SensorReadings : has_readings
    Scenarios ||--o{ SensorReadings : scenario_context

    classDef shared fill:#F4EFA9
    classDef monitoring fill:#eeb896
    class Locations,Scenarios shared
    class SensorTypes,Sensors,SensorReadings monitoring
```

### Environments Schema

Manages environmental variants that can be derived from sensor combinations, user input, or hybrid approaches for modeling and analysis context.

```mermaid
erDiagram
    Locations
    VariantTypes
    Scenarios

    EnvironmentVariants {
        INT VariantID PK
        INT LocationID FK "References shared.Locations"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT ScenarioID FK "References shared.Scenarios"
        INT ParentVariantID FK "Self-reference for variant lineage"
        VARCHAR VariantName "Descriptive name for variant"
        FLOAT AvgTemperature_C
        FLOAT AvgHumidity_percent
        FLOAT TotalPrecipitation_mm
        FLOAT AvgGlobalRadiation
        FLOAT AvgCO2_ppm
        FLOAT AvgWindSpeed_ms
        FLOAT DominantWindDirection_deg
    }

    Locations ||--o{ EnvironmentVariants : has_variants
    VariantTypes ||--o{ EnvironmentVariants : variant_type
    Scenarios ||--o{ EnvironmentVariants : scenario_context
    EnvironmentVariants ||--o{ EnvironmentVariants : parent_variant

    classDef shared fill:#F4EFA9
    classDef environment fill:#566b8a
    class Locations,VariantTypes,Scenarios shared
    class EnvironmentVariants environment
```

## Database Design Summary

This PostgreSQL database design provides a robust foundation for the XR Future Forests Lab with the following key characteristics:

### Schema Organization

- **Shared Schema**: Core reference tables (Locations, Species, Scenarios, VariantTypes) used across all domains
- **Point Clouds Schema**: LiDAR scan management with processing variants and file path references
- **Trees Schema**: Tree inventory with growth simulation support and QR code integration
- **Monitoring Schema**: Efficient time-series sensor data storage optimized for high-frequency readings
- **Environments Schema**: Environmental context management derived from sensor aggregations

### Key Design Principles

- **Variant Pattern**: Flexible data versioning across point clouds, trees, and environments
- **Time-Series Optimization**: Efficient sensor readings storage for high-volume environmental monitoring
- **File Path Management**: Simple file references within tables for external file handling
- **Spatial Support**: PostGIS integration for geographic and geometric data
- **Processing Flexibility**: External processing workflow support through clear status tracking

### Scalability Features

- Optimized for high-volume sensor data ingestion
- Efficient querying through proper indexing on time-series data
- Flexible JSON metadata storage for processing parameters
- Cross-schema relationships enabling complex forest analysis workflows

This design supports the three-tier architecture vision while maintaining data integrity, performance, and flexibility for forest research applications.
