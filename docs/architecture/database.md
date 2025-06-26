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
graph LR
    subgraph "Shared Schema"
        SL[Locations]
        SS[Species]
        SVT[VariantTypes]
        SC[Scenarios]
    end
    
    subgraph "Point Clouds schema"
        PC[PointClouds]
        PCV[PointCloudVariants]
    end
    
    subgraph "Trees Schema"
        TV[TreeVariants]
    end
    
    subgraph "Sensors Schema"
        S[Sensors]
        SR[SensorReadings]
    end
    
    subgraph "Environments Schema"
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
    SVT --> PCV
    SVT --> TV
    SVT --> SR
    SVT --> EV
    
    %% Within-schema relationships
    PC --> PCV
    S --> SR
    
    classDef schema fill:#e8f4f1,stroke:#2d8659,stroke-width:2px
    classDef shared fill:#fff2cc,stroke:#d6b656,stroke-width:2px
    classDef main fill:#dae8fc,stroke:#6c8ebf,stroke-width:2px
    classDef variant fill:#f8cecc,stroke:#b85450,stroke-width:2px
    
    class SL,SS,SVT,SC shared
    class PC,TV,S main
    class PCV,SR,EV variant
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
        VARCHAR QRCode "For Field Web App scanning"
        FLOAT DetectionConfidence "Confidence in automated detection"
        FLOAT SpeciesConfidence "Confidence in species classification"
        JSONB ProcessingMetadata "Flexible storage for processing details"
        TIMESTAMP CreatedAt DEFAULT NOW()
        TIMESTAMP UpdatedAt DEFAULT NOW()
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

Manages sensor hardware installations and time-series sensor readings. Base tables contain sensor metadata and installation info, while readings tables contain actual sensor measurements optimized for time-series queries.

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

    %% Table coloring
    classDef refTable fill:#f7dcc7,stroke:#ad5643,stroke-width:2px,color:#612515
    classDef coreTable fill:#c0e8d9,stroke:#5cb89c,stroke-width:2px,color:#183029
    
    class Locations,Scenarios,SensorTypes refTable
    class Sensors,SensorReadings coreTable
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

## Database Design Issues and Recommendations

Based on the architecture description, several adjustments are needed to properly support the envisioned functionality:

### **Critical Issues Identified:**

1. **Missing Processing Workflow Support**: The Logic Tier's point cloud processing pipeline requires tracking of processing jobs, status, and intermediate results
2. **Inefficient Sensor Data Storage**: The current sensor readings approach could be further optimized for time-series performance
3. **Missing QR Code Support**: Field Web App functionality requires QR code identifiers for trees
4. **Limited Processing Results Storage**: Segmentation and classification confidence scores need dedicated storage
5. **Missing File Management**: Point cloud file paths and processing result files need better organization

### **Recommended Schema Adjustments:**

#### **1. Point Clouds Schema - Add Processing Support**

```sql
-- Add to PointCloudVariants table:
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN ProcessingStatus VARCHAR(50); -- 'pending', 'processing', 'completed', 'failed'
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN ProcessingProgress FLOAT; -- 0.0 to 1.0
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN ProcessingStartTime TIMESTAMP;
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN ProcessingEndTime TIMESTAMP;
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN ErrorMessage TEXT;
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN SegmentationConfidence FLOAT; -- Average confidence score
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN ClassificationConfidence FLOAT; -- Average confidence score
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN ProcessedTreeCount INT; -- Number of trees detected
```

#### **2. Trees Schema - Add QR and Processing Support**

```sql
-- Add to TreeVariants table:
ALTER TABLE trees.TreeVariants ADD COLUMN QRCode VARCHAR(100) UNIQUE; -- For Field Web App scanning
ALTER TABLE trees.TreeVariants ADD COLUMN DetectionConfidence FLOAT; -- Confidence in automated detection
ALTER TABLE trees.TreeVariants ADD COLUMN SpeciesConfidence FLOAT; -- Confidence in species classification
ALTER TABLE trees.TreeVariants ADD COLUMN ProcessingMetadata JSONB; -- Flexible storage for processing details
ALTER TABLE trees.TreeVariants ADD COLUMN CreatedAt TIMESTAMP DEFAULT NOW();
ALTER TABLE trees.TreeVariants ADD COLUMN UpdatedAt TIMESTAMP DEFAULT NOW();
```

#### **3. Sensors Schema - Optimize for Time-Series Data**

Replace the variant-based approach with a more efficient time-series design:

```sql
-- Replace SensorVariants with:
CREATE TABLE sensors.SensorReadings (
    ReadingID BIGSERIAL PRIMARY KEY,
    SensorID INT REFERENCES sensors.Sensors(SensorID),
    Timestamp TIMESTAMP NOT NULL,
    FLOAT Value NOT NULL,
    Quality VARCHAR(20) DEFAULT 'good', -- 'good', 'suspect', 'bad'
    ScenarioID INT REFERENCES shared.Scenarios(ScenarioID), -- NULL for real readings
    INDEX (SensorID, Timestamp), -- For time-series queries
    INDEX (Timestamp), -- For temporal queries across sensors
    PARTITION BY RANGE (Timestamp) -- For large-scale time-series performance
);

-- Aggregate table for faster queries:
CREATE TABLE sensors.SensorReadingsHourly (
    SensorID INT REFERENCES sensors.Sensors(SensorID),
    HourTimestamp TIMESTAMP NOT NULL,
    AvgValue FLOAT,
    MinValue FLOAT,
    MaxValue FLOAT,
    ReadingCount INT,
    PRIMARY KEY (SensorID, HourTimestamp)
);
```

#### **4. Add Processing Jobs Tracking**

```sql
-- New table to support Processing API:
CREATE TABLE shared.ProcessingJobs (
    JobID BIGSERIAL PRIMARY KEY,
    JobType VARCHAR(50) NOT NULL, -- 'segmentation', 'classification', 'attribute_extraction'
    PointCloudID INT REFERENCES pointclouds.PointClouds(PointCloudID),
    Status VARCHAR(50) NOT NULL, -- 'queued', 'running', 'completed', 'failed'
    Progress FLOAT DEFAULT 0.0,
    StartTime TIMESTAMP,
    EndTime TIMESTAMP,
    ErrorMessage TEXT,
    Parameters JSONB, -- Processing parameters
    Results JSONB, -- Processing results and metadata
    CreatedAt TIMESTAMP DEFAULT NOW()
);
```

### **Schema Organization Recommendations:**

#### **Rename `sensors` to `monitoring`**

The current sensors schema should be renamed to better reflect its role in environmental monitoring:

- `monitoring.Sensors` → Hardware installations
- `monitoring.SensorReadings` → Time-series data
- `monitoring.SensorTypes` → Sensor type reference

#### **Add File Management Schema**

```sql
CREATE SCHEMA files;

CREATE TABLE files.FileStorage (
    FileID BIGSERIAL PRIMARY KEY,
    FilePath VARCHAR(500) NOT NULL,
    FileType VARCHAR(50) NOT NULL, -- 'point_cloud', 'processed_cloud', 'model'
    FileSize BIGINT,
    CheckSum VARCHAR(64),
    StorageLocation VARCHAR(100), -- 'local', 's3', 'azure_blob'
    CreatedAt TIMESTAMP DEFAULT NOW(),
    AccessedAt TIMESTAMP
);

-- Link files to point clouds
ALTER TABLE pointclouds.PointClouds ADD COLUMN FileID BIGINT REFERENCES files.FileStorage(FileID);
ALTER TABLE pointclouds.PointCloudVariants ADD COLUMN FileID BIGINT REFERENCES files.FileStorage(FileID);
```

### **Updated API Mapping:**

- **Point Cloud API**: Reads from `pointclouds.PointClouds` and `pointclouds.PointCloudVariants`
- **Tree API**: Reads from `trees.TreeVariants` with QR code support
- **Processing API**: Manages `shared.ProcessingJobs` and processing status in variants
- **Sensor API**: Reads from `monitoring.SensorReadings` with efficient time-series queries
- **Environment API**: Reads from `environments.EnvironmentVariants`
- **Tree Lookup API**: Uses QR codes in `trees.TreeVariants`
- **Simulation API**: Creates new variants in `trees.TreeVariants` with simulation metadata

These changes will properly support the architecture's vision while maintaining performance and data integrity.

## **Summary**

The current database design provides a solid foundation but requires several enhancements to fully support the envisioned XR Future Forests Lab architecture:

**✅ **What Works Well:**

- Variant-based pattern for temporal tracking
- Spatial data support with PostGIS
- Clear schema separation
- Flexible scenario modeling

**⚠️ **Critical Adjustments Needed:**

- Add processing workflow tracking for the Logic Tier
- Implement QR code support for Field Web App
- Optimize sensor data storage for time-series performance
- Add file management for point cloud and processing results
- Include confidence scores for processing results

**🚀 **Performance Benefits:**

- Time-series optimization will handle millions of sensor readings efficiently
- Processing job tracking enables real-time status updates
- File management schema supports scalable storage solutions

With these adjustments, the database will fully support the three-tier architecture while providing the performance and flexibility needed for the XR Future Forests Lab's ambitious vision.
