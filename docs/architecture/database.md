# Database Design - XR Future Forests Lab

## Digital Twin System Overview

```mermaid
%%{
init: {
'theme': 'base',
'themeVariables': {
'primaryColor': '#2E7D32',
'primaryTextColor': '#FFFFFF',
'primaryBorderColor': '#1B5E20',
'lineColor': '#388E3C',
'secondaryColor': '#A5D6A7',
'tertiaryColor': '#E8F5E8',
'background': '#FFFFFF',
'mainBkg': '#F1F8E9',
'secondBkg': '#DCEDC8',
'tertiaryBkg': '#C8E6C9'
}
}
}%%
flowchart TB
    subgraph EXTERNAL["🌍 External Data Sources"]
        direction TB
        EcoSense["🌡️ EcoSense Sensors<br/>• Temperature<br/>• Humidity<br/>• CO₂<br/>• Wind Speed"]
        Trees3D["📡 3DTrees Platform<br/>• LiDAR Point Clouds<br/>• Forest Scans<br/>• Spatial Data"]
        ForestInv["📋 Forest Inventory<br/>• Tree Measurements<br/>• Species Data<br/>• Growth Records"]
        ExtEnv["🌤️ Environmental APIs<br/>• Weather Data<br/>• Climate Models<br/>• Precipitation"]
    end

    subgraph INGESTION["📥 Data Ingestion Layer"]
        direction LR
        Pipeline["🔄 Data Pipeline<br/>• Validation<br/>• Standardization<br/>• Quality Control"]
        SensorAgg["📊 Sensor Aggregation<br/>• Real-time Processing<br/>• Quality Assessment<br/>• Temporal Alignment"]
    end

    subgraph DATABASE["🗄️ Digital Twin Database Core"]
        direction TB
        subgraph SCHEMAS["🏗️ Unified Schema Architecture"]
            direction LR
            SharedS["🔗 Shared Schema<br/>• Locations<br/>• Species<br/>• Scenarios<br/>• Process Tracking"]
            TreesS["🌳 Trees Schema<br/>• Tree Variants<br/>• Growth Data<br/>• Measurements"]
            PointS["☁️ Point Clouds<br/>• LiDAR Data<br/>• Processing Results<br/>• Spatial Bounds"]
            SensorS["📡 Sensor Schema<br/>• Hardware Config<br/>• Time-series Data<br/>• Quality Metrics"]
            EnvS["🌿 Environment<br/>• Conditions<br/>• Aggregated Data<br/>• Model Inputs"]
        end
        
        AuditSys["📝 Audit System<br/>• Field-level Tracking<br/>• Change History<br/>• User Attribution<br/>• Revert Capability"]
    end

    subgraph PROCESSING["⚙️ Processing & Analysis"]
        direction TB
        subgraph POINTCLOUD["☁️ Point Cloud Processing"]
            TreeSeg["🎯 Tree Segmentation<br/>• Individual Detection<br/>• Boundary Definition"]
            SpeciesClass["🔬 Species Classification<br/>• ML Algorithms<br/>• Confidence Scoring"]
            StructExtract["📏 Structure Extraction<br/>• Height & DBH<br/>• Crown Dimensions"]
        end
        
        subgraph MODELS["🌱 Growth & Process Models"]
            SILVA["🌲 SILVA Model<br/>• Individual Tree Growth<br/>• Scientific Validation"]
            Climate["🌡️ Climate Models<br/>• Temperature Effects<br/>• Precipitation Impact"]
            Custom["⚡ Custom Algorithms<br/>• Research Models<br/>• Experimental Methods"]
        end
    end

    subgraph APPLICATIONS["🖥️ User Applications"]
        direction TB
        subgraph XR["🥽 XR Forest Experience"]
            VirtTrees["🌳 Virtual Trees<br/>• Photorealistic Models<br/>• Growth Visualization"]
            EnvVis["🌪️ Environment Viz<br/>• Wind Patterns<br/>• CO₂ Flow<br/>• Nutrient Cycles"]
            Interaction["👋 XR Interaction<br/>• Parameter Control<br/>• Scenario Testing<br/>• Real-time Feedback"]
        end
        
        subgraph WEB["🌐 Web Applications"]
            FieldApp["📱 Field App<br/>• QR Code Access<br/>• Mobile Interface<br/>• Data Collection"]
            WebPlatform["💻 3DTrees Web<br/>• Point Cloud Viewer<br/>• Processing Dashboard"]
        end
    end

    %% External to Ingestion
    EcoSense --> SensorAgg
    Trees3D --> Pipeline
    ForestInv --> Pipeline
    ExtEnv --> Pipeline

    %% Ingestion to Database
    Pipeline --> SharedS
    Pipeline --> TreesS
    Pipeline --> PointS
    Pipeline --> EnvS
    SensorAgg --> SensorS
    SensorAgg --> EnvS

    %% Database internal connections
    SharedS -.-> TreesS
    SharedS -.-> PointS
    SharedS -.-> SensorS
    SharedS -.-> EnvS
    SensorS --> EnvS
    PointS --> TreesS

    %% Processing connections
    PointS --> TreeSeg
    TreeSeg --> SpeciesClass
    SpeciesClass --> StructExtract
    StructExtract --> TreesS

    %% Model connections
    TreesS --> SILVA
    EnvS --> SILVA
    EnvS --> Climate
    SILVA --> TreesS
    Climate --> EnvS

    %% Applications connections
    TreesS --> VirtTrees
    EnvS --> EnvVis
    PointS --> EnvVis
    SensorS --> EnvVis
    VirtTrees --> Interaction
    EnvVis --> Interaction
    Interaction --> TreesS
    Interaction --> EnvS

    TreesS --> FieldApp
    PointS --> WebPlatform
    TreesS --> WebPlatform

    %% Audit connections
    TreesS -.-> AuditSys
    EnvS -.-> AuditSys
    PointS -.-> AuditSys
    FieldApp -.-> AuditSys
    Interaction -.-> AuditSys

    %% Styling
    classDef externalSource fill:#E3F2FD,stroke:#1976D2,stroke-width:3px,color:#0D47A1
    classDef ingestionLayer fill:#FFF3E0,stroke:#F57C00,stroke-width:3px,color:#E65100
    classDef databaseCore fill:#E8F5E8,stroke:#2E7D32,stroke-width:3px,color:#1B5E20
    classDef processingLayer fill:#F3E5F5,stroke:#7B1FA2,stroke-width:3px,color:#4A148C
    classDef applicationLayer fill:#E0F2F1,stroke:#00695C,stroke-width:3px,color:#004D40
    classDef auditSystem fill:#FFF8E1,stroke:#FF8F00,stroke-width:3px,color:#E65100

    class EcoSense,Trees3D,ForestInv,ExtEnv externalSource
    class Pipeline,SensorAgg ingestionLayer
    class SharedS,TreesS,PointS,SensorS,EnvS,SCHEMAS databaseCore
    class TreeSeg,SpeciesClass,StructExtract,SILVA,Climate,Custom,POINTCLOUD,MODELS processingLayer
    class VirtTrees,EnvVis,Interaction,FieldApp,WebPlatform,XR,WEB applicationLayer
    class AuditSys auditSystem
```

## Supabase Database Implementation

This database is implemented on **Supabase**, a PostgreSQL-based platform that provides:

- **PostgREST Auto-Generated APIs**: Every table automatically gets REST endpoints for CRUD operations, eliminating the need for custom API code
- **Row-Level Security (RLS)**: Fine-grained access control policies defined at the database level for secure multi-user access
- **Real-time Subscriptions**: WebSocket-based change notifications for live updates in XR and web applications
- **Edge Functions**: Deno-based serverless functions for complex business logic (SILVA integration, S3 presigned URLs, data aggregation)
- **Built-in Authentication**: JWT-based auth system (GoTrue) with user management and role-based access
- **PostGIS Extensions**: Full geospatial query capabilities for tree positions, sensor locations, and plot boundaries
- **Automatic Audit Logging**: Database triggers create audit entries automatically on all UPDATE operations
- **S3 Integration**: Point cloud files stored in external S3 buckets, with S3 URIs stored in database

### Key Supabase Features Used

**Auto-Generated REST API via PostgREST**:
- All tables exposed through REST endpoints: `GET/POST/PATCH/DELETE /table_name`
- URL-based filtering, sorting, pagination, aggregation
- Relationship embedding via foreign keys (`?select=*,Species(*),Stems(*)`)
- No custom backend code required for standard CRUD operations

**Row-Level Security Policies**:
```sql
-- Example RLS policy on Trees table
CREATE POLICY "Trees are viewable by everyone"
    ON trees.Trees FOR SELECT
    USING (true);

CREATE POLICY "Authenticated users can update trees"
    ON trees.Trees FOR UPDATE
    TO authenticated
    USING (CreatedBy = auth.uid()::TEXT);
```

**Audit Triggers**:
```sql
-- Automatic field-level change tracking
CREATE TRIGGER audit_trees_changes
    BEFORE UPDATE ON trees.Trees
    FOR EACH ROW
    EXECUTE FUNCTION shared.log_field_changes();
```

**Real-time Change Notifications**:
```javascript
// Client-side real-time subscription
supabase
  .channel('tree-changes')
  .on('postgres_changes', {event: '*', schema: 'trees', table: 'Trees'},
      (payload) => updateVirtualForest(payload.new))
  .subscribe()
```

## Unified Database Design with Schema Organization

This design uses PostgreSQL schemas (`shared`, `pointclouds`, `trees`, `sensor`, `environments`) to organize a unified forest monitoring database deployed on Supabase. The design supports efficient time-series sensor data storage with S3 URIs for point cloud file references.

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
        VARCHAR ParameterName "learning_rate, max_depth, threshold, growth_rate, interpolation_method"
        VARCHAR ParameterValue "Actual parameter value used for this variant"
        VARCHAR DataType "float, int, string, boolean"
        TEXT Description "Parameter description"
    }

    ProcessParameters_PointClouds {
        INT ParameterID FK "References ProcessParameters"
        INT VariantID FK "References pointclouds.PointClouds.VariantID"
    }

    ProcessParameters_Trees {
        INT ParameterID FK "References ProcessParameters"
        INT VariantID FK "References trees.Trees.VariantID"
    }

    ProcessParameters_Environments {
        INT ParameterID FK "References ProcessParameters"
        INT VariantID FK "References environments.Environments.VariantID"
    }

    ProcessParameters_Stems {
        INT ParameterID FK "References ProcessParameters"
        INT StemID FK "References trees.Stems.StemID"
    }

    ProcessMetrics {
        INT MetricID PK
        INT ProcessID FK "References Processes"
        VARCHAR MetricName "accuracy, precision, recall, f1_score, rmse"
        FLOAT MetricValue "Published performance value"
        TEXT Source "Paper, report, or source of metric"
    }

    Processes ||--o{ ProcessMetrics : has_metrics
    ProcessParameters ||--o{ ProcessParameters_PointClouds : parameter_links
    ProcessParameters ||--o{ ProcessParameters_Trees : parameter_links
    ProcessParameters ||--o{ ProcessParameters_Environments : parameter_links
    ProcessParameters ||--o{ ProcessParameters_Stems : parameter_links
```

**Junction Table Design**: Process parameters use explicit junction tables to link with domain-specific variants, providing clear foreign key relationships while maintaining flexibility for cross-schema operations.

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
        BIGINT AuditID PK
        VARCHAR FieldName "Specific field changed"
        TEXT OldValue "Previous value (JSON)"
        TEXT NewValue "New value (JSON)"
        VARCHAR ChangeReason "User explanation"
        VARCHAR UserID "User who made change"
        TIMESTAMP Timestamp "When change occurred"
        VARCHAR ChangeType "field_update, bulk_update, revert"
    }

    AuditLog_PointClouds {
        BIGINT AuditID FK "References AuditLog"
        INT VariantID FK "References pointclouds.PointClouds.VariantID"
    }

    AuditLog_Trees {
        BIGINT AuditID FK "References AuditLog"
        INT VariantID FK "References trees.Trees.VariantID"
    }

    AuditLog_Environments {
        BIGINT AuditID FK "References AuditLog"
        INT VariantID FK "References environments.Environments.VariantID"
    }

    AuditLog_Stems {
        BIGINT AuditID FK "References AuditLog"
        INT StemID FK "References trees.Stems.StemID"
    }

    AuditLog ||--o{ AuditLog_PointClouds : audit_links
    AuditLog ||--o{ AuditLog_Trees : audit_links
    AuditLog ||--o{ AuditLog_Environments : audit_links
    AuditLog ||--o{ AuditLog_Stems : audit_links
    AuditLog_PointClouds }o--|| PointClouds : tracks_changes
    AuditLog_Trees }o--|| Trees : tracks_changes
    AuditLog_Stems }o--|| Stems : tracks_changes
    AuditLog_Environments }o--|| Environments : tracks_changes
```

The AuditLog system provides granular change tracking for individual field modifications across all variant tables through explicit junction tables.

**Key Features**:

- **Junction Table Design**: Explicit relationships through dedicated junction tables (AuditLog_PointClouds, AuditLog_Trees, etc.)
- **API-Level Tracking**: All changes go through REST API endpoints to ensure audit logging
- **Granular Logging**: Each field change creates a separate audit entry with full before/after context
- **Revert Capability**: Changes can be undone using audit log data without creating new variants
- **User Attribution**: All changes tracked to specific authenticated users
- **Reason Codes**: Optional explanations provide context for change decisions

**Implementation Strategy**:

1. **Single Field Updates**: Modify variant record directly, create AuditLog entry with junction table link
2. **Multiple Field Updates**: Option to create micro-variant or log individual changes through junction tables
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
        INT ParentVariantID FK "Self-reference for variant lineage"
        INT PointCloudVariantID FK "References pointclouds.PointClouds - NULL if not derived from point cloud"
        INT LocationID FK "References shared.Locations"
        INT ScenarioID FK "References shared.Scenarios"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT ProcessID FK "References shared.Processes - NULL for manual measurements"
        INT SpeciesID FK "References shared.Species"
        INT TreeStatusID FK "References TreeStatus"
        INT BranchingPatternID FK "References BranchingPatterns"
        INT BarkCharacteristicID FK "References BarkCharacteristics"
        FLOAT Height_m "Total tree height"
        FLOAT CrownWidth_m "Crown diameter"
        FLOAT CrownBaseHeight_m "Height to crown base"
        GEOMETRY CrownBoundary "PostGIS polygon"
        FLOAT Volume_m3 "Total tree volume"
        GEOMETRY Position "PostGIS point (tree coordinates)"
        FLOAT LeanAngle_deg "0-90 degrees from vertical"
        INT LeanDirection_azimuth "0-360 degrees, 0=North"
        FLOAT TimeDelta_yrs "Time since parent variant (for growth)"
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
    }

    Locations ||--o{ Trees : located_at
    Scenarios ||--o{ Trees : scenario_context
    TreeStatus ||--o{ Trees : tree_status
    Species ||--o{ Trees : tree_species
    VariantTypes ||--o{ Trees : variant_type
    Processes ||--o{ Trees : processing_algorithm
    Trees ||--o{ Trees : parent_variant
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
        BIGINT ReadingID PK
        INT SensorID FK "References sensor.Sensors"
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
        INT ParentVariantID FK "Self-reference for variant lineage"
        INT LocationID FK "References shared.Locations"
        INT ScenarioID FK "References shared.Scenarios"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT ProcessID FK "References shared.Processes - NULL for manual input"
        VARCHAR VariantName "Descriptive name for variant"
        FLOAT AvgTemperature_C
        FLOAT AvgHumidity_percent
        FLOAT TotalPrecipitation_mm
        FLOAT AvgGlobalRadiation
        FLOAT AvgCO2_ppm
        FLOAT AvgWindSpeed_ms
        FLOAT DominantWindDirection_deg
    }

    Locations ||--o{ Environments : has_variants
    VariantTypes ||--o{ Environments : variant_type
    Scenarios ||--o{ Environments : scenario_context
    Processes ||--o{ Environments : processing_algorithm
    Environments ||--o{ Environments : parent_variant
```
