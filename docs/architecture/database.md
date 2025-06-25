# Database Design - XR Future Forests Lab

## Unified Database Design with Schema Organization

This design uses PostgreSQL schemas (`shared`, `pointclouds`, `trees`, `environments`) to organize a unified forest monitoring database. Each domain follows a consistent variant pattern where base entities can have multiple variants representing different processing results, temporal states, or user modifications.

## Schema Overview

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#313d4f',
      'primaryColor': '#8cdbc0',
      'primaryTextColor': '#183029',
      'primaryBorderColor': '#265e4d',
      'secondaryColor': '#71a897',
      'secondaryTextColor': '#183029',
      'secondaryBorderColor': '#458875',
      'tertiaryColor': '#c0e8d9',
      'tertiaryTextColor': '#183029',
      'tertiaryBorderColor': '#5cb89c'
    }
  }
}%%
graph TB
    subgraph "shared schema"
        SL[Locations]
        SS[Species]
        SVT[VariantTypes]
        SC[Scenarios]
    end
    
    subgraph "pointclouds schema"
        PC[PointClouds]
        PCV[PointCloudVariants]
    end
    
    subgraph "trees schema"
        TV[TreeVariants]
    end
    
    subgraph "sensors schema"
        S[Sensors]
        SV[SensorVariants]
    end
    
    subgraph "environments schema"
        EV[EnvironmentVariants]
    end
    
    %% Cross-schema relationships
    SL -.-> PC
    SL -.-> TV
    SL -.-> S
    SL -.-> EV
    SS -.-> TV
    SC -.-> PCV
    SC -.-> TV
    SC -.-> SV
    SC -.-> EV
    SVT -.-> PCV
    SVT -.-> TV
    SVT -.-> SV
    SVT -.-> EV
    
    %% Within-schema relationships
    PC --> PCV
    S --> SV
    
    classDef schema fill:#e8f4f1,stroke:#2d8659,stroke-width:2px
    classDef shared fill:#fff2cc,stroke:#d6b656,stroke-width:2px
    classDef main fill:#dae8fc,stroke:#6c8ebf,stroke-width:2px
    classDef variant fill:#f8cecc,stroke:#b85450,stroke-width:2px
    
    class SL,SS,SVT,SC shared
    class PC,TV,S main
    class PCV,SV,EV variant
```

### Shared Schema

Contains reference tables used across all domains, providing consistent data definitions and relationships throughout the forest monitoring system.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#313d4f',
      'primaryColor': '#d2d2d2',
      'primaryTextColor': '#0f0f0f',
      'primaryBorderColor': '#505050',
      'secondaryColor': '#8e8e8e',
      'secondaryTextColor': '#0f0f0f',
      'secondaryBorderColor': '#505050',
      'tertiaryColor': '#e6e6e6',
      'tertiaryTextColor': '#0f0f0f',
      'tertiaryBorderColor': '#8e8e8e'
    }
  }
}%%
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

    Species {
        INT SpeciesID PK "Unique species ID"
        VARCHAR CommonName "Common name"
        VARCHAR ScientificName "Scientific name"
        TEXT GrowthCharacteristics "JSON: typical growth patterns"
    }

    VariantTypes {
        INT VariantTypeID PK
        VARCHAR TypeName "Original, Processing_Result, Temporal_State, User_Modification"
        TEXT Description "Variant type description"
    }

    Scenarios {
        INT ScenarioID PK
        VARCHAR ScenarioName "Current_Conditions, Climate_Change_2050, Drought_Test"
        VARCHAR Description "Scenario description"
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

    %% Table coloring
    classDef refTable fill:#f7dcc7,stroke:#ad5643,stroke-width:2px,color:#612515
    
    class Locations,Species,VariantTypes,Scenarios,SoilTypes,ClimateZoneTypes refTable
```

### Point Clouds Schema

Manages LiDAR scan data and processing variants, supporting different processing algorithms and results while maintaining links to the original scan data.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#313d4f',
      'primaryColor': '#8cdbc0',
      'primaryTextColor': '#183029',
      'primaryBorderColor': '#265e4d',
      'secondaryColor': '#71a897',
      'secondaryTextColor': '#183029',
      'secondaryBorderColor': '#458875',
      'tertiaryColor': '#c0e8d9',
      'tertiaryTextColor': '#183029',
      'tertiaryBorderColor': '#5cb89c'
    }
  }
}%%
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
    }

    Locations ||--o{ PointClouds : located_at
    VariantTypes ||--o{ PointCloudVariants : variant_type
    Scenarios ||--o{ PointCloudVariants : scenario_context
    PointClouds ||--o{ PointCloudVariants : has_variants
    PointCloudVariants ||--o{ PointCloudVariants : parent_variant

    %% Table coloring
    classDef refTable fill:#f7dcc7,stroke:#ad5643,stroke-width:2px,color:#612515
    classDef coreTable fill:#c0e8d9,stroke:#5cb89c,stroke-width:2px,color:#183029
    
    class Locations,VariantTypes,Scenarios refTable
    class PointClouds,PointCloudVariants coreTable
```

### Trees Schema

Manages tree measurement and simulation data through variants. Each tree variant represents a specific measurement, simulation state, or modeling result that can reference point cloud variants for detection context.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#313d4f',
      'primaryColor': '#8cdbc0',
      'primaryTextColor': '#183029',
      'primaryBorderColor': '#265e4d',
      'secondaryColor': '#71a897',
      'secondaryTextColor': '#183029',
      'secondaryBorderColor': '#458875',
      'tertiaryColor': '#c0e8d9',
      'tertiaryTextColor': '#183029',
      'tertiaryBorderColor': '#5cb89c'
    }
  }
}%%
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
        VARCHAR ModelType "Growth model used if applicable"
        INT EnvironmentVariantID FK "Environmental context"
        TEXT Notes
    }

    Locations ||--o{ TreeVariants : located_at
    Scenarios ||--o{ TreeVariants : scenario_context
    TreeStatus ||--o{ TreeVariants : tree_status
    Species ||--o{ TreeVariants : tree_species
    VariantTypes ||--o{ TreeVariants : variant_type
    TreeVariants ||--o{ TreeVariants : parent_variant

    %% Table coloring
    classDef refTable fill:#f7dcc7,stroke:#ad5643,stroke-width:2px,color:#612515
    classDef coreTable fill:#c0e8d9,stroke:#5cb89c,stroke-width:2px,color:#183029
    
    class Locations,Species,VariantTypes,Scenarios,TreeStatus refTable
    class TreeVariants coreTable
```

### Sensors Schema

Manages sensor hardware installations (base tables) and sensor readings/data (variant tables). Base tables contain sensor metadata and installation info, while variants contain actual sensor readings and measurements.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#313d4f',
      'primaryColor': '#8cdbc0',
      'primaryTextColor': '#183029',
      'primaryBorderColor': '#265e4d',
      'secondaryColor': '#71a897',
      'secondaryTextColor': '#183029',
      'secondaryBorderColor': '#458875',
      'tertiaryColor': '#c0e8d9',
      'tertiaryTextColor': '#183029',
      'tertiaryBorderColor': '#5cb89c'
    }
  }
}%%
erDiagram
    Locations
    VariantTypes
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

    SensorVariants {
        INT VariantID PK
        INT SensorID FK "References Sensors"
        INT VariantTypeID FK "References shared.VariantTypes"
        INT ScenarioID FK "References shared.Scenarios - NULL for non-scenario variants"
        INT ParentVariantID FK "Self-reference for variant lineage"
        DATETIME Timestamp "Reading timestamp"
        FLOAT Value
    }

    Locations ||--o{ Sensors : located_at
    SensorTypes ||--o{ Sensors : sensor_type
    Sensors ||--o{ SensorVariants : has_variants
    VariantTypes ||--o{ SensorVariants : variant_type
    Scenarios ||--o{ SensorVariants : scenario_context
    SensorVariants ||--o{ SensorVariants : parent_variant

    %% Table coloring
    classDef refTable fill:#f7dcc7,stroke:#ad5643,stroke-width:2px,color:#612515
    classDef coreTable fill:#c0e8d9,stroke:#5cb89c,stroke-width:2px,color:#183029
    
    class Locations,VariantTypes,Scenarios,SensorTypes refTable
    class Sensors,SensorVariants coreTable
```

### Environments Schema

Manages environmental variants that can be derived from sensor combinations, user input, or hybrid approaches for modeling and analysis context.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#313d4f',
      'primaryColor': '#8cdbc0',
      'primaryTextColor': '#183029',
      'primaryBorderColor': '#265e4d',
      'secondaryColor': '#71a897',
      'secondaryTextColor': '#183029',
      'secondaryBorderColor': '#458875',
      'tertiaryColor': '#c0e8d9',
      'tertiaryTextColor': '#183029',
      'tertiaryBorderColor': '#5cb89c'
    }
  }
}%%
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

    %% Table coloring
    classDef refTable fill:#f7dcc7,stroke:#ad5643,stroke-width:2px,color:#612515
    classDef coreTable fill:#c0e8d9,stroke:#5cb89c,stroke-width:2px,color:#183029
    
    class Locations,VariantTypes,Scenarios refTable
    class EnvironmentVariants coreTable
```
