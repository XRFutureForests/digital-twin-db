# Database Design - XR Future Forests Lab

## Unified Database Design with Schema Organization

This design uses PostgreSQL schemas (`shared`, `pointclouds`, `trees`, `sensor`, `environments`) to organize a unified forest monitoring database. The design supports efficient time-series sensor data storage with file references managed as simple file paths within the variant and base tables.

> **📊 Complete ERD Available**: For a comprehensive view of the entire database structure in a single diagram, see the complete ERD files:
>
> - **Visual ERD**: [`xr_forests_complete_erd.dbml`](./xr_forests_complete_erd.dbml) - Use with [dbdiagram.io](https://dbdiagram.io/) for interactive visualization
> - **SQL Schema**: [`xr_forests_complete_schema.sql`](./xr_forests_complete_schema.sql) - Ready-to-execute PostgreSQL DDL
> - **Usage Guide**: [`README_ERD.md`](./README_ERD.md) - How to use the ERD files

## Schema Overview

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
    end
    
    subgraph pointclouds ["Point Clouds Schema"]
        PCV[PointClouds]
    end
    
    subgraph trees ["Trees Schema"]
        TV[Trees]
        TST[Stems]
    end
    
    subgraph sensor ["Sensor Schema"]
        S[Sensors]
        SR[SensorReadings]
    end
    
    subgraph environments ["Environments Schema"]
        EV[Environments]
    end
    
    %% Cross-schema relationships
    SL --> PCV
    SL --> TV
    SL --> S
    SL --> EV
    SS --> TV
    SC --> PCV
    SC --> TV
    SC --> SR
    SC --> EV
    SVT --> PCV
    SVT --> TV
    SVT --> EV
    SAL --> PCV
    SAL --> TV
    SAL --> EV
    SP --> PCV
    SP --> TV
    SP --> EV
    SPP --> PCV
    SPP --> TV
    SPP --> EV
    
    %% Within-schema relationships
    S --> SR
    SP --> SPM
    TV --> TST

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
    
    class SL,SS,SC,SVT,SAL,SP,SPP,SPM sharedNodes
    class PCV pointcloudsNodes
    class TV,TST treesNodes
    class S,SR sensorNodes
    class EV environmentsNodes
    
    class shared sharedSubgraph
    class pointclouds pointcloudsSubgraph
    class trees treesSubgraph
    class sensor sensorSubgraph
    class environments environmentsSubgraph


```

### Shared Schema

Contains reference tables used across all domains, providing consistent data definitions and relationships throughout the forest monitoring system.

#### Location and Environmental Context

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
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
        INT ClimateZoneID FK "Climate zone reference"
    }

    SoilTypes {
        INT SoilTypeID PK
        VARCHAR SoilName "Alfisol, Andisol, Aridisol, Entisol,<br>Gelisol, Histosol, Inceptisol, Mollisol,<br>Oxisol, Spodosol, Ultisol, Vertisol"
    }

    ClimateZones {
        INT ClimateZoneID PK
        VARCHAR ZoneName "Köppen climate classification codes"
    }

    SoilTypes ||--o{ Locations : soil_type
    ClimateZones ||--o{ Locations : climate_zone
```

#### Species Reference

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
erDiagram
    Species {
        INT SpeciesID PK "Unique species ID"
        VARCHAR CommonName "Common name"
        VARCHAR ScientificName "Scientific name"
        TEXT GrowthCharacteristics "JSON: typical growth patterns"
    }
```

#### Scenarios and Variant Types

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
erDiagram

    Scenarios {
        INT ScenarioID PK
        VARCHAR ScenarioName "Current_Conditions, Climate_Change_2050, Drought_Test"
        VARCHAR Description "Scenario description"
    }

    VariantTypes {
        INT VariantTypeID PK
        VARCHAR VariantTypeName "original, processed, manual, simulated_growth, user_input"
        TEXT Description "Description of variant type"
    }

```

#### Process Management and Algorithm Tracking

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
erDiagram
    Processes {
        INT ProcessID PK
        VARCHAR ProcessName "LiDAR_Segmentation, Tree_Detection, Growth_Simulation, Climate_Modeling"
        VARCHAR AlgorithmName "RandomForest, DeepLearning, RulesBased, Statistical"
        VARCHAR Version "v1.0.2, v2.1.0"
        TEXT Description "Algorithm description and purpose"
        VARCHAR Author "Algorithm developer/organization"
        DATE PublicationDate "When algorithm was published/released"
        TEXT Citation "Academic citation if applicable"
        VARCHAR Category "detection, classification, simulation, analysis"
    }

    ProcessParameters {
        INT ParameterID PK
        VARCHAR VariantSchema "pointclouds, trees, environments, stems"
        INT VariantID "References VariantID in the specified schema"
        VARCHAR ParameterName "learning_rate, max_depth, threshold, growth_rate, interpolation_method"
        VARCHAR ParameterValue "Actual parameter value used for this variant"
        VARCHAR DataType "float, int, string, boolean"
        TEXT Description "Parameter description"
    }

    ProcessMetrics {
        INT MetricID PK
        INT ProcessID FK "References Processes"
        VARCHAR MetricName "accuracy, precision, recall, f1_score, rmse"
        FLOAT MetricValue "Published performance value"
        VARCHAR DatasetName "Dataset used for evaluation"
        TEXT TestConditions "Conditions under which metric was measured"
        DATE MeasurementDate "When metric was evaluated"
        TEXT Source "Paper, report, or source of metric"
    }

    Processes ||--o{ ProcessMetrics : has_metrics
```

#### Field-Level Change Tracking

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
erDiagram
    PointClouds
    Trees
    Stems
    Environments

    AuditLog {
        BIGSERIAL AuditID PK
        VARCHAR TableName "Source table name: pointclouds.PointClouds, trees.Trees, trees.Stems, environments.Environments"
        INT RecordID "VariantID or StemID being modified"
        VARCHAR FieldName "Specific field changed"
        TEXT OldValue "Previous value (JSON)"
        TEXT NewValue "New value (JSON)"
        VARCHAR ChangeReason "User explanation"
        VARCHAR UserID "User who made change"
        TIMESTAMP Timestamp "When change occurred"
        VARCHAR ChangeType "field_update, bulk_update, revert"
    }

    PointClouds ||--o{ AuditLog : tracks_changes
    Trees ||--o{ AuditLog : tracks_changes
    Stems ||--o{ AuditLog : tracks_changes
    Environments ||--o{ AuditLog : tracks_changes
```

The AuditLog table provides granular change tracking for individual field modifications across all variant tables without creating full variants.

**Key Features**:

- **API-Level Tracking**: All changes go through REST API endpoints to ensure audit logging
- **Granular Logging**: Each field change creates a separate audit entry with full before/after context
- **Revert Capability**: Changes can be undone using audit log data without creating new variants
- **User Attribution**: All changes tracked to specific authenticated users
- **Reason Codes**: Optional explanations provide context for change decisions

**Implementation Strategy**:

1. **Single Field Updates**: Modify variant record directly, log change in AuditLog
2. **Multiple Field Updates**: Option to create micro-variant or log individual changes  
3. **Major Changes**: Continue using full variant system for significant modifications
4. **Revert Operations**: Use audit log to restore previous values with new audit entries

### Point Clouds Schema

Manages LiDAR scan data and processing variants through a unified variant-based approach. Original scans and processed variants are stored in the same table, with variant types determining the relationship and processing status.

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
erDiagram
    Locations
    VariantTypes
    Scenarios
    Processes
    ProcessParameters

    PointClouds {
        INT VariantID PK
        INT LocationID FK "References shared.Locations"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT ScenarioID FK "References shared.Scenarios - NULL for non-scenario variants"
        INT ParentVariantID FK "Self-reference for variant lineage"
        INT ProcessID FK "References shared.Processes - NULL for original scans"
        VARCHAR VariantName "Descriptive name for variant"
        DATETIME ScanDate "Date and time of original scan"
        VARCHAR SensorModel "LiDAR scanner model"
        GEOMETRY ScanBounds "PostGIS polygon defining coverage"
        VARCHAR FilePath "Path to point cloud file"
        BIGINT PointCount "Total number of points"
        FLOAT FileSizeMB "File size in megabytes"
        VARCHAR ProcessingStatus "pending, processing, completed, failed - NULL for original scans"
        TIMESTAMP UpdatedAt "DEFAULT NOW()"
    }

    Locations ||--o{ PointClouds : located_at
    VariantTypes ||--o{ PointClouds : variant_type
    Scenarios ||--o{ PointClouds : scenario_context
    Processes ||--o{ PointClouds : processing_algorithm
    PointClouds ||--o{ PointClouds : parent_variant
    PointClouds ||--o{ ProcessParameters : variant_parameters
```

### Trees Schema

Manages tree measurement and simulation data through variants. Each tree variant represents a specific measurement, simulation state, or modeling result that can reference point cloud variants for detection context.

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
erDiagram
    Locations
    Species
    VariantTypes
    Scenarios
    Processes
    ProcessParameters

    TreeStatus {
        INT TreeStatusID PK
        VARCHAR StatusName "healthy, stressed, declining, dead"
        TEXT Description
    }

    TaperTypes {
        INT TaperTypeID PK
        VARCHAR TaperTypeName "Cylinder, Cone, Paraboloid, Neiloid"
        TEXT Description "Form description"
        FLOAT TypicalTaperRatioMin "Typical minimum taper ratio"
        FLOAT TypicalTaperRatioMax "Typical maximum taper ratio"
    }

    StraightnessTypes {
        INT StraightnessTypeID PK
        VARCHAR StraightnessName "Straight, Slight_sweep, Moderate_sweep, Severe_sweep"
        TEXT Description "Curvature description"
        FLOAT DeviationAngleMin "Minimum deviation angle in degrees"
        FLOAT DeviationAngleMax "Maximum deviation angle in degrees"
    }

    BranchingPatterns {
        INT BranchingPatternID PK
        VARCHAR PatternName "Alternate, Opposite, Whorled, Spiral, Random"
        TEXT Description "Branching arrangement description"
    }

    BarkCharacteristics {
        INT BarkCharacteristicID PK
        VARCHAR BarkTypeName "Smooth, Furrowed, Plated, Exfoliating"
        TEXT Description "Bark texture description"
        TEXT TypicalSpecies "Examples: e.g., Fagus, Quercus, Pinus, Platanus"
    }

    Trees {
        INT VariantID PK
        INT LocationID FK "References shared.Locations"
        INT ScenarioID FK "References shared.Scenarios"
        INT ParentVariantID FK "Self-reference for variant lineage"
        INT SpeciesID FK "References shared.Species"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT PointCloudVariantID FK "References pointclouds.PointClouds - NULL if not derived from point cloud"
        INT ProcessID FK "References shared.Processes - NULL for manual measurements"
        INT TreeStatusID FK "References TreeStatus"
        INT BranchingPatternID FK "References BranchingPatterns"
        INT BarkCharacteristicID FK "References BarkCharacteristics"
        FLOAT Height_m "Total tree height"
        FLOAT CrownWidth_m "Crown diameter"
        FLOAT CrownBaseHeight_m "Height to crown base"
        GEOMETRY CrownBoundary "PostGIS polygon"
        FLOAT Volume_m3 "Total tree volume"
        GEOMETRY Position "PostGIS point (plot coordinates)"
        FLOAT LeanAngle_deg "0-90 degrees from vertical"
        INT LeanDirection_azimuth "0-360 degrees, 0=North"
        FLOAT TimeDelta_yrs "Time since parent variant (for growth)"
        TIMESTAMP UpdatedAt "DEFAULT NOW()"
    }

    Stems {
        INT StemID PK
        INT TreeVariantID FK "References Trees.VariantID"
        INT StemNumber "1=main stem, 2+=secondary stems"
        INT TaperTypeID FK "References TaperTypes"
        INT StraightnessTypeID FK "References StraightnessTypes"
        FLOAT DBH_cm "Diameter at breast height (1.3m)"
        FLOAT TaperRatio "0.0-1.0, diameter ratio top/bottom"
        FLOAT Sweep_cm_per_m "Maximum horizontal deviation per meter"
        FLOAT StemHeight_m "Individual stem height"
        FLOAT StemVolume_m3 "Individual stem volume"
        GEOMETRY StemPosition "PostGIS point for multi-stem trees"
        TEXT Notes "Additional stem observations"
        TIMESTAMP UpdatedAt "DEFAULT NOW()"
    }

    Locations ||--o{ Trees : located_at
    Scenarios ||--o{ Trees : scenario_context
    TreeStatus ||--o{ Trees : tree_status
    Species ||--o{ Trees : tree_species
    VariantTypes ||--o{ Trees : variant_type
    Processes ||--o{ Trees : processing_algorithm
    Trees ||--o{ Trees : parent_variant
    Trees ||--o{ ProcessParameters : variant_parameters
    BranchingPatterns ||--o{ Trees : branching_pattern
    BarkCharacteristics ||--o{ Trees : bark_characteristic
    Trees ||--o{ Stems : has_stems
    TaperTypes ||--o{ Stems : taper_type
    StraightnessTypes ||--o{ Stems : straightness_type
```

### Sensor Schema

Manages sensor hardware installations and time-series sensor readings. Base tables contain sensor metadata and installation info, while readings tables contain actual sensor measurements optimized for time-series queries.

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
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
```

### Environments Schema

Manages environmental variants that can be derived from sensor combinations, user input, or hybrid approaches for modeling and analysis context.

```mermaid
%%{init: {
  "theme": "neutral"
}}%%
erDiagram
    Locations
    VariantTypes
    Scenarios
    Processes
    ProcessParameters

    Environments {
        INT VariantID PK
        INT LocationID FK "References shared.Locations"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT ScenarioID FK "References shared.Scenarios"
        INT ParentVariantID FK "Self-reference for variant lineage"
        INT ProcessID FK "References shared.Processes - NULL for manual input"
        VARCHAR VariantName "Descriptive name for variant"
        FLOAT AvgTemperature_C
        FLOAT AvgHumidity_percent
        FLOAT TotalPrecipitation_mm
        FLOAT AvgGlobalRadiation
        FLOAT AvgCO2_ppm
        FLOAT AvgWindSpeed_ms
        FLOAT DominantWindDirection_deg
        TIMESTAMP UpdatedAt "DEFAULT NOW()"
    }

    Locations ||--o{ Environments : has_variants
    VariantTypes ||--o{ Environments : variant_type
    Scenarios ||--o{ Environments : scenario_context
    Processes ||--o{ Environments : processing_algorithm
    Environments ||--o{ Environments : parent_variant
    Environments ||--o{ ProcessParameters : variant_parameters
```
