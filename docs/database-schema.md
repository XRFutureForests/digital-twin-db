# Database Design - XR Future Forests Lab

## Overview

This document describes the PostgreSQL database schema for the XR Future Forests Lab. The database is organized into five schemas:

- **shared**: Reference tables used across all domains
- **pointclouds**: LiDAR scan data and processing variants
- **trees**: Tree measurement and simulation data with multi-stem support
- **sensor**: Environmental sensor hardware and time-series readings
- **environments**: Environmental variants from sensor data or simulations

### Key Design Principles

- **Schema Organization**: PostgreSQL schemas organize related tables for clarity and access control
- **Variant-Based Lineage**: Point clouds, trees, and environments use variant patterns for temporal tracking
- **Junction Tables**: Explicit junction tables link shared tables (ProcessParameters, AuditLog) to domain-specific variants
- **PostGIS Integration**: Geometry columns for spatial data (locations, tree positions, sensor placement)
- **Field-Level Auditing**: Comprehensive change tracking across all variant tables with IP and user agent tracking
- **External Integration**: Support for Aquarius API time-series data via ExternalID/ExternalMetadata columns
- **Sensor-Tree Linking**: Direct relationships between environmental sensors and individual trees for growth monitoring

### Complete ERD Reference

For a comprehensive view of the entire database structure in a single diagram, see **[database_erd.dbml](./database-erd.dbml)** - visualize at [dbdiagram.io](https://dbdiagram.io/)

---

## Schema Organization

```mermaid
graph LR
    subgraph shared ["Shared Schema"]
        SL[Locations]
        SS[Species]
        SC[Scenarios]
        SVT[VariantTypes]
        SAL[AuditLog]
        SP[Processes]
        SPP[ProcessParameters]
        SPM[ProcessMetrics]
        SPPPC[ProcessParameters_PointClouds]
        SPPT[ProcessParameters_Trees]
        SPPE[ProcessParameters_Environments]
        SPPS[ProcessParameters_Stems]
        SALPC[AuditLog_PointClouds]
        SALT[AuditLog_Trees]
        SALE[AuditLog_Environments]
        SALS[AuditLog_Stems]
    end
    
    subgraph pointclouds ["Point Clouds Schema"]
        PCV[PointClouds]
    end
    
    subgraph trees ["Trees Schema"]
        TV[Trees]
        TST[Stems]
        TTS[TreeStatus]
        TTT[TaperTypes]
        TST2[StraightnessTypes]
        TBP[BranchingPatterns]
        TBC[BarkCharacteristics]
    end
    
    subgraph sensor ["Sensor Schema"]
        S[Sensors]
        SR[SensorReadings]
        SST[SensorTypes]
        STL[SensorTreeLinks]
    end
    
    subgraph environments ["Environments Schema"]
        EV[Environments]
    end
    
    %% Junction table connections
    SPP --> SPPPC
    SPP --> SPPT  
    SPP --> SPPE
    SPP --> SPPS
    SAL --> SALPC
    SAL --> SALT
    SAL --> SALE
    SAL --> SALS
    SPPPC --> PCV
    SPPT --> TV
    SPPE --> EV
    SPPS --> TST
    SALPC --> PCV
    SALT --> TV
    SALE --> EV
    SALS --> TST
    
    %% Cross-schema relationships
    SL --> PCV
    SL --> TV
    SL --> S
    SL --> EV
    SS --> TV
    SST --> S
    S --> SR
    S --> STL
    STL --> TV
    TV --> TST
    TV --> TTS
    TV --> TTT
    TV --> TST2
    TV --> TBP
    TV --> TBC
    TST --> TTT
    TST --> TST2
    SC --> PCV
    SC --> TV
    SC --> SR
    SC --> EV
    SVT --> PCV
    SVT --> TV
    SVT --> EV
    SP --> PCV
    SP --> TV
    SP --> EV
    SP --> SPM

    classDef sharedNodes fill:#F4EFA9,stroke:#c7bb1a,stroke-width:2px,color:#242424
    classDef pointcloudsNodes fill:#e8e8e8,stroke:#4f4f4f,stroke-width:2px,color:#242424
    classDef treesNodes fill:#5CB89C,stroke:#19392f,stroke-width:2px,color:#19392f
    classDef sensorNodes fill:#AD5643,stroke:#673428,stroke-width:2px,color:#e8e8e8
    classDef environmentsNodes fill:#566b8a,stroke:#181d26,stroke-width:2px,color:#e8e8e8
    
    classDef sharedSubgraph fill:#F4EFA9,fill-opacity:0.3,stroke:#c7bb1a,stroke-width:2px
    classDef pointcloudsSubgraph fill:#e8e8e8,fill-opacity:0.3,stroke:#4f4f4f,stroke-width:2px
    classDef treesSubgraph fill:#5CB89C,fill-opacity:0.3,stroke:#19392f,stroke-width:2px
    classDef sensorSubgraph fill:#eeb896,fill-opacity:0.3,stroke:#673428,stroke-width:2px
    classDef environmentsSubgraph fill:#566b8a,fill-opacity:0.3,stroke:#181d26,stroke-width:2px
    
    class SL,SS,SC,SVT,SAL,SP,SPP,SPM,SPPPC,SPPT,SPPE,SPPS,SALPC,SALT,SALE,SALS sharedNodes
    class PCV pointcloudsNodes
    class TV,TST,TTS,TTT,TST2,TBP,TBC treesNodes
    class S,SR,SST sensorNodes
    class EV environmentsNodes
    
    class shared sharedSubgraph
    class pointclouds pointcloudsSubgraph
    class trees treesSubgraph
    class sensor sensorSubgraph
    class environments environmentsSubgraph
```

---

## SHARED SCHEMA

Contains reference tables used across all domains, providing consistent data definitions and relationships throughout the forest monitoring system.

### Locations and Environmental Context

```mermaid
erDiagram
    Locations {
        integer LocationID PK "Unique location ID"
        varchar LocationName "Location name"
        geometry Boundary "PostGIS polygon for location boundaries"
        geometry CenterPoint "PostGIS point for location center"
        text Description "Description of the location"
        float Elevation_m "Location elevation"
        float Slope_deg "Location slope"
        varchar Aspect "N, NE, E, SE, S, SW, W, NW"
        integer SoilTypeID FK "Soil type reference"
        integer ClimateZoneID FK "Climate zone reference"
    }

    SoilTypes {
        integer SoilTypeID PK
        varchar SoilTypeName "Alfisol, Andisol, Aridisol, Entisol, Gelisol, Histosol, Inceptisol, Mollisol, Oxisol, Spodosol, Ultisol, Vertisol"
    }

    ClimateZones {
        integer ClimateZoneID PK
        varchar ClimateZoneName "Köppen climate classification codes"
    }

    Locations }o--|| SoilTypes : "soil_type"
    Locations }o--|| ClimateZones : "climate_zone"
```

### Species Reference

```mermaid
erDiagram
    Species {
        integer SpeciesID PK "Unique species ID"
        varchar CommonName "Common name"
        varchar ScientificName "Scientific name"
        text GrowthCharacteristics "JSON: typical growth patterns"
    }
```

### Scenarios and Variant Types

```mermaid
erDiagram
    Scenarios {
        integer ScenarioID PK
        varchar ScenarioName "Current_Conditions, Climate_Change_2050, Drought_Test"
        varchar Description "Scenario description"
    }

    VariantTypes {
        integer VariantTypeID PK
        varchar VariantTypeName "original, processed, manual, simulated_growth, user_input"
        text Description "Description of variant type"
    }
```

### Process Management and Algorithm Tracking

```mermaid
erDiagram
    Processes {
        integer ProcessID PK
        varchar ProcessName "LiDAR_Segmentation, Tree_Detection, Growth_Simulation, Climate_Modeling"
        varchar AlgorithmName "RandomForest, DeepLearning, RulesBased, Statistical"
        varchar Version "v1.0.2, v2.1.0"
        text Description "Algorithm description and purpose"
        varchar Author "Algorithm developer/organization"
        date PublicationDate "When algorithm was published/released"
        text Citation "Academic citation if applicable"
        varchar Category "detection, classification, simulation, analysis"
    }

    ProcessParameters {
        integer ParameterID PK
        varchar ParameterName "learning_rate, max_depth, threshold, growth_rate, interpolation_method"
        varchar ParameterValue "Actual parameter value used for this variant"
        varchar DataType "float, int, string, boolean"
        text Description "Parameter description"
    }

    ProcessParameters_PointClouds {
        integer ParameterID FK "References ProcessParameters"
        integer VariantID FK "References pointclouds.PointClouds.VariantID"
    }

    ProcessParameters_Trees {
        integer ParameterID FK "References ProcessParameters"
        integer VariantID FK "References trees.Trees.VariantID"
    }

    ProcessParameters_Environments {
        integer ParameterID FK "References ProcessParameters"
        integer VariantID FK "References environments.Environments.VariantID"
    }

    ProcessParameters_Stems {
        integer ParameterID FK "References ProcessParameters"
        integer StemID FK "References trees.Stems.StemID"
    }

    ProcessMetrics {
        integer MetricID PK
        integer ProcessID FK "References Processes"
        varchar MetricName "accuracy, precision, recall, f1_score, rmse"
        float MetricValue "Published performance value"
        text Source "Paper, report, or source of metric"
    }

    Processes ||--o{ ProcessMetrics : "has_metrics"
    ProcessParameters ||--o{ ProcessParameters_PointClouds : "parameter_links"
    ProcessParameters ||--o{ ProcessParameters_Trees : "parameter_links"
    ProcessParameters ||--o{ ProcessParameters_Environments : "parameter_links"
    ProcessParameters ||--o{ ProcessParameters_Stems : "parameter_links"
```

**Junction Table Design**: Process parameters use explicit junction tables to link with domain-specific variants, providing clear foreign key relationships while maintaining flexibility for cross-schema operations.

### Field-Level Change Tracking

```mermaid
erDiagram
    AuditLog {
        bigint AuditID PK
        varchar FieldName "Specific field changed"
        text OldValue "Previous value (JSON)"
        text NewValue "New value (JSON)"
        varchar ChangeReason "User explanation"
        varchar UserID "User who made change"
        timestamp Timestamp "When change occurred"
        varchar ChangeType "field_update, bulk_update, revert"
        inet IPAddress "IP address of change origin"
        text UserAgent "Browser/client identification"
    }

    AuditLog_PointClouds {
        bigint AuditID FK "References AuditLog"
        integer VariantID FK "References pointclouds.PointClouds.VariantID"
    }

    AuditLog_Trees {
        bigint AuditID FK "References AuditLog"
        integer VariantID FK "References trees.Trees.VariantID"
    }

    AuditLog_Environments {
        bigint AuditID FK "References AuditLog"
        integer VariantID FK "References environments.Environments.VariantID"
    }

    AuditLog_Stems {
        bigint AuditID FK "References AuditLog"
        integer StemID FK "References trees.Stems.StemID"
    }

    AuditLog ||--o{ AuditLog_PointClouds : "audit_links"
    AuditLog ||--o{ AuditLog_Trees : "audit_links"
    AuditLog ||--o{ AuditLog_Environments : "audit_links"
    AuditLog ||--o{ AuditLog_Stems : "audit_links"
```

The AuditLog system provides granular change tracking for individual field modifications across all variant tables through explicit junction tables.

**Key Features**:

- **Junction Table Design**: Explicit relationships through dedicated junction tables
- **Granular Logging**: Each field change creates a separate audit entry with full before/after context
- **Revert Capability**: Changes can be undone using audit log data without creating new variants
- **User Attribution**: All changes tracked to specific authenticated users with IP address and user agent

### Utility Views

- **`recent_changes`**: Latest database modifications across all schemas
- **`user_activity_summary`**: User activity statistics and change patterns

---

## POINTCLOUDS SCHEMA

Manages LiDAR scan data and processing variants through a unified variant-based approach.

```mermaid
erDiagram
    PointClouds {
        integer VariantID PK
        integer ParentVariantID FK "Self-reference for variant lineage"
        integer LocationID FK "References shared.Locations"
        integer ScenarioID FK "References shared.Scenarios - NULL for non-scenario variants"
        integer VariantTypeID FK "References shared.VariantTypes"
        integer ProcessID FK "References shared.Processes - NULL for original scans"
        varchar VariantName "Descriptive name for variant"
        timestamp ScanDate "Date and time of original scan"
        varchar SensorModel "LiDAR scanner model"
        geometry ScanBounds "PostGIS polygon defining coverage"
        varchar FilePath "Path to point cloud file"
        bigint PointCount "Total number of points"
        float FileSizeMB "File size in megabytes"
        varchar ProcessingStatus "pending, processing, completed, failed - NULL for original scans"
    }

    PointClouds }o--|| PointClouds : "parent_variant"
```

### Utility Views

- **`processing_lineage`**: Tracks point cloud processing history and variant relationships

---

## TREES SCHEMA

Manages tree measurement and simulation data through variants with multi-stem support.

### Tree Status and Morphology Reference Tables

```mermaid
erDiagram
    TreeStatus {
        integer TreeStatusID PK
        varchar TreeStatusName "healthy, stressed, declining, dead"
        text Description
    }

    TaperTypes {
        integer TaperTypeID PK
        varchar TaperTypeName "Cylinder, Cone, Paraboloid, Neiloid"
        text Description "Form description"
        float TypicalTaperRatioMin "Typical minimum taper ratio"
        float TypicalTaperRatioMax "Typical maximum taper ratio"
    }

    StraightnessTypes {
        integer StraightnessTypeID PK
        varchar StraightnessName "Straight, Slight_sweep, Moderate_sweep, Severe_sweep"
        text Description "Curvature description"
        float DeviationAngleMin "Minimum deviation angle in degrees"
        float DeviationAngleMax "Maximum deviation angle in degrees"
    }

    BranchingPatterns {
        integer BranchingPatternID PK
        varchar BranchingPatternName "Alternate, Opposite, Whorled, Spiral, Random"
        text Description "Branching arrangement description"
    }

    BarkCharacteristics {
        integer BarkCharacteristicID PK
        varchar BarkCharacteristicName "Smooth, Furrowed, Plated, Exfoliating"
        text Description "Bark texture description"
        text TypicalSpecies "Examples: e.g., Fagus, Quercus, Pinus, Platanus"
    }
```

### Trees and Stems

```mermaid
erDiagram
    Trees {
        integer VariantID PK
        integer ParentVariantID FK "Self-reference for variant lineage"
        integer PointCloudVariantID FK "References pointclouds.PointClouds - NULL if not derived from point cloud"
        integer LocationID FK "References shared.Locations"
        integer ScenarioID FK "References shared.Scenarios"
        integer VariantTypeID FK "References shared.VariantTypes"
        integer ProcessID FK "References shared.Processes - NULL for manual measurements"
        integer SpeciesID FK "References shared.Species"
        integer TreeStatusID FK "References TreeStatus"
        integer BranchingPatternID FK "References BranchingPatterns"
        integer BarkCharacteristicID FK "References BarkCharacteristics"
        float Height_m "Total tree height"
        float CrownWidth_m "Crown diameter"
        float CrownBaseHeight_m "Height to crown base"
        geometry CrownBoundary "PostGIS polygon"
        float Volume_m3 "Total tree volume"
        geometry Position "PostGIS point (tree coordinates)"
        float LeanAngle_deg "0-90 degrees from vertical"
        integer LeanDirection_azimuth "0-360 degrees, 0=North"
        float TimeDelta_yrs "Time since parent variant (for growth)"
        integer Age_years "Tree age in years"
        float HealthScore "0.0-1.0, overall tree health assessment"
        float Biomass_kg "Total above-ground biomass"
        float CarbonContent_kg "Carbon sequestration amount"
        text FieldNotes "Field observations and FID identifiers"
        timestamp CreatedAt
        timestamp UpdatedAt
        varchar CreatedBy
        varchar UpdatedBy
    }

    Stems {
        integer StemID PK
        integer TreeVariantID FK "References Trees.VariantID"
        integer StemNumber "1=main stem, 2+=secondary stems"
        integer TaperTypeID FK "References TaperTypes"
        integer StraightnessTypeID FK "References StraightnessTypes"
        float DBH_cm "Diameter at breast height (1.3m)"
        float TaperRatio "0.0-1.0, diameter ratio top/bottom"
        float Sweep_cm_per_m "Maximum horizontal deviation per meter"
        float StemHeight_m "Individual stem height"
        float StemVolume_m3 "Individual stem volume"
        float BarkThickness_mm "Bark thickness measurement"
        float WoodDensity_kg_m3 "Wood density for biomass calculations"
        timestamp CreatedAt
        timestamp UpdatedAt
    }

    Trees ||--o{ Stems : "has_stems"
    Trees }o--|| Trees : "parent_variant"
```

### Utility Views

- **`trees_with_metrics`**: Aggregated view showing trees with computed metrics (stem count, total volume, crown metrics)

---

## SENSOR SCHEMA

Manages sensor hardware installations and time-series sensor readings.

```mermaid
erDiagram
    SensorTypes {
        integer SensorTypeID PK
        varchar SensorTypeName "Temperature, Humidity, CO2, Light, Soil_Moisture, Wind"
        text Description
    }

    Sensors {
        integer SensorID PK
        integer LocationID FK "References shared.Locations"
        integer SensorTypeID FK
        varchar SensorModel "Specific sensor model"
        geometry Position "Sensor position within location"
        varchar ReadingType "Temperature, Humidity, etc."
        varchar Unit
    }

    SensorReadings {
        bigint ReadingID PK
        integer SensorID FK "References sensor.Sensors"
        timestamp Timestamp "Reading timestamp"
        float Value
        varchar Quality "good, suspect, bad"
        integer ScenarioID FK "References shared.Scenarios - NULL for real readings"
    }

    SensorTypes ||--o{ Sensors : "sensor_type"
    Sensors ||--o{ SensorReadings : "has_readings"
```

---

## ENVIRONMENTS SCHEMA

Manages environmental variants that can be derived from sensor combinations, user input, or hybrid approaches.

```mermaid
erDiagram
    Environments {
        integer VariantID PK
        integer ParentVariantID FK "Self-reference for variant lineage"
        integer LocationID FK "References shared.Locations"
        integer ScenarioID FK "References shared.Scenarios"
        integer VariantTypeID FK "References shared.VariantTypes"
        integer ProcessID FK "References shared.Processes - NULL for manual input"
        varchar VariantName "Descriptive name for variant"
        timestamp StartDate "Period start date"
        timestamp EndDate "Period end date"
        float AvgTemperature_C
        float AvgHumidity_percent
        float TotalPrecipitation_mm
        float AvgGlobalRadiation
        float AvgCO2_ppm
        float AvgWindSpeed_ms
        float DominantWindDirection_deg
        float AvgSoilMoisture_percent "Average soil moisture content"
        float AvgSoilTemperature_C "Average soil temperature"
        float SoilPH "Soil acidity/alkalinity"
        float NutrientNitrogen_mg_kg "Nitrogen content in soil"
        float NutrientPhosphorus_mg_kg "Phosphorus content in soil"
        float NutrientPotassium_mg_kg "Potassium content in soil"
        float StressFactor "0.0-1.0, combined environmental stress indicator"
        text Description
        text ResearchNotes "Scientific observations and analysis notes"
        timestamp CreatedAt
        timestamp UpdatedAt
        varchar CreatedBy
        varchar UpdatedBy
    }

    Environments }o--|| Environments : "parent_variant"
```

### Utility Views

- **`active_environments`**: Current environmental variants with latest data
- **`location_environment_summary`**: Environmental conditions aggregated by location
