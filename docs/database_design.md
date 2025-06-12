# Database Design

> **Related Documentation**: [Architecture](./architecture.md) | [Data Contracts & APIs](./data_contracts_and_apis.md)

This document defines the database schema for the XR Future Forests Lab system. The database architecture consists of three specialized databases, each optimized for different types of forest-related data and their specific access patterns.

---

## 1. Point Cloud Database (Point Cloud DB)

Stores metadata and processing results from LiDAR point cloud data, including references to raw files, segmentation outputs, and classification results. This database serves as the primary repository for all spatial scan data and their derived products, enabling efficient storage and retrieval of massive 3D datasets while maintaining processing lineage and quality metrics.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#ad5643',
      'primaryColor': '#5cb89c',
      'primaryTextColor': '#1d242f',
      'primaryBorderColor': '#313d4f',
      'secondaryColor': '#d6aaa1',
      'secondaryTextColor': '#1d242f',
      'secondaryBorderColor': '#ad5643',
      'tertiaryColor': '#d5d8db',
      'tertiaryTextColor': '#1d242f',
      'tertiaryBorderColor': '#313d4f'
    }
  }
}%%
erDiagram
    Locations {
        INT LocationID PK "Unique site/plot ID"
        VARCHAR LocationName "Site name"
        TEXT Coordinates "Geographic coordinates"
        TEXT Description "Description of the site"
    }

    PointClouds {
        INT PointCloudID PK "Unique scan ID"
        VARCHAR FilePath "Path/URI to raw point cloud file (.las, .laz)"
        DATETIME ScanDate "Date and time of scan"
        INT LocationID FK "References Locations.LocationID"
        VARCHAR SensorType "Sensor type (e.g., TLS, UAV_LiDAR)"
        VARCHAR ProcessingStatus "Current status: 'Raw', 'Segmented', 'Classified'"
        TEXT QualityMetrics "JSON: density, accuracy"
        DATETIME LastProcessedDate "Last processing date"
    }

    PointCloudSegmentationResults {
        INT SegmentationResultID PK "Unique segmentation run ID"
        INT PointCloudID FK "References PointClouds.PointCloudID"
        DATETIME ProcessDate "Segmentation date"
        VARCHAR SegmentationAlgorithm "Algorithm used (e.g., TreeLearn, 3D Forest)"
        TEXT SegmentDataRef "JSON: references to tree segments"
        TEXT Metrics "JSON: segmentation quality"
    }

    TreeClassificationResults {
        INT ClassificationResultID PK "Unique classification run ID"
        INT SegmentationResultID FK "References PointCloudSegmentationResults.SegmentationResultID"
        DATETIME ProcessDate "Classification date"
        VARCHAR ClassificationAlgorithm "Algorithm used (e.g., ML model)"
        TEXT ClassifiedTreesData "JSON: tree IDs, species IDs, probabilities"
        TEXT Metrics "JSON: classification accuracy"
    }

    Species {
        INT SpeciesID PK "Unique species ID"
        VARCHAR CommonName "Common name"
        VARCHAR ScientificName "Scientific name"
        TEXT GrowthCharacteristics "JSON: typical growth"
    }

    Locations ||--o{ PointClouds : has_scans
    PointClouds ||--o{ PointCloudSegmentationResults : has_segmentations
    PointCloudSegmentationResults ||--o{ TreeClassificationResults : has_classifications
    Species ||--o{ TreeClassificationResults : classifies_species
```

### Table Descriptions

**Locations**  
Master table storing geographic site information for all forest plots and monitoring locations across the system.

**PointClouds**  
Core table containing metadata for each LiDAR scan, including file references, sensor information, and processing status tracking.

**PointCloudSegmentationResults**  
Stores results from tree segmentation algorithms, maintaining references to the algorithms used and quality metrics for each segmentation run.

**TreeClassificationResults**  
Contains species classification outputs with confidence scores and accuracy metrics for each classified tree segment.

**Species**  
Reference table defining tree species information and their growth characteristics for classification and modeling purposes.

### Table Relationships

- **Locations** serve as the spatial foundation, with each location hosting multiple point cloud scans
- **PointClouds** represent individual scanning sessions, each producing segmentation results
- **PointCloudSegmentationResults** feed into classification processes, maintaining the processing pipeline lineage
- **TreeClassificationResults** link to **Species** for taxonomic validation and growth modeling
- The design ensures full traceability from raw scans through segmentation to final species classification

---

## 2. Tree Database (Tree DB)

Central repository for all tree-related data, supporting scenario-based modeling, variant management, growth simulation, and detailed structural representation. This database enables both data-driven (QSM) and generative (L-system, DeepTree, etc.) models in a unified structure, supports fine-grained modeling of branches, twigs, and leaves, and maintains complete history and lineage of all tree variants across different scenarios and time periods.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#ad5643',
      'primaryColor': '#5cb89c',
      'primaryTextColor': '#1d242f',
      'primaryBorderColor': '#313d4f',
      'secondaryColor': '#d6aaa1',
      'secondaryTextColor': '#1d242f',
      'secondaryBorderColor': '#ad5643',
      'tertiaryColor': '#d5d8db',
      'tertiaryTextColor': '#1d242f',
      'tertiaryBorderColor': '#313d4f'
    }
  }
}%%
erDiagram
    Locations {
        INT LocationID PK
        VARCHAR LocationName
    }

    Species {
        INT SpeciesID PK
        VARCHAR CommonName
        VARCHAR ScientificName
        TEXT GrowthCharacteristics
    }

    HealthStatus {
        INT HealthStatusID PK
        VARCHAR Status
        TEXT Description
    }

    PhenologyStatus {
        INT PhenologyStatusID PK
        VARCHAR Status
        TEXT Description
    }

    Scenarios {
        INT ScenarioID PK
        VARCHAR ScenarioName
        INT CreatedByUserID
        DATETIME CreatedAt
        TEXT ScenarioParameters
    }

    Trees {
        INT TreeID PK
        INT LocationID FK
        INT SpeciesID FK
        DATETIME InitialCaptureDate
        FLOAT InitialHeight_m
        FLOAT InitialDBH_cm
        FLOAT InitialCrownWidth_m
        FLOAT InitialVolume_m3
        INT HealthStatusID FK
        INT PointCloudID FK
    }

    DataQualityTypes {
        INT QualityTypeID PK
        VARCHAR QualityType "Direct_Measurement, Point_Cloud_Derived, Model_Estimated"
        TEXT Description
    }

    TreeVariants {
        INT TreeVariantID PK
        INT TreeID FK "Nullable: NULL if new tree in scenario"
        INT ScenarioID FK
        INT ParentVariantID FK "Nullable: NULL if original or first variant"
        INT SpeciesID FK
        DATETIME VariantTimestamp
        FLOAT Height_m
        INT HeightQualityID FK "References DataQualityTypes"
        FLOAT DBH_cm
        INT DBHQualityID FK "References DataQualityTypes"
        FLOAT CrownWidth_m
        INT CrownWidthQualityID FK "References DataQualityTypes"
        FLOAT Volume_m3
        INT VolumeQualityID FK "References DataQualityTypes"
        INT HealthStatusID FK
        VARCHAR VariantType "Original, Growth_Simulation, Species_Replacement, Manual_Edit, New"
        FLOAT TimeDelta_yrs "Time passed since parent state (years) - for growth simulations"
        VARCHAR ModelType "For growth simulations: model used"
        FLOAT MortalityRisk_prob "For growth simulations: predicted mortality risk"
        TEXT PredictedStructureData "For growth simulations: predicted structure data"
        INT EnvironmentalSnapshotID FK "For growth simulations: environmental context"
        TEXT Notes
    }

    TreeStructures {
        INT StructureID PK
        INT TreeVariantID FK
        VARCHAR StructureType "QSM, LSystem, DeepTree, etc."
        VARCHAR FilePath "Path to model file (if any)"
        TEXT StructureData "JSON or string (e.g. L-system, latent vector, QSM params)"
        DATETIME GenerationDate
        VARCHAR Software "Tool or method used"
        TEXT Metadata "Additional parameters"
    }

    StructureBranches {
        INT BranchID PK
        INT StructureID FK
        FLOAT Length_m
        FLOAT Diameter_cm
        FLOAT Direction_deg "Azimuth (horizontal direction in degrees)"
        FLOAT Inclination_deg "Inclination angle from vertical (degrees)"
        FLOAT StartHeight_m "Height of branch start on parent (m)"
        FLOAT StartRadius_cm "Radius at branch base (cm)"
        TEXT Geometry "JSON/OBJ"
    }

    StructureTwigs {
        INT TwigID PK
        INT BranchID FK
        FLOAT Length_m
        FLOAT Diameter_cm
        FLOAT Direction_deg
        FLOAT Inclination_deg
        FLOAT StartHeight_m
        TEXT Geometry "JSON/OBJ"
    }

    StructureLeaves {
        INT LeafID PK
        INT TwigID FK
        TEXT Geometry "JSON/OBJ"
        INT PhenologyStatusID FK
        FLOAT Direction_deg
        FLOAT Inclination_deg
        FLOAT StartHeight_m
        VARCHAR Color "Optional: leaf color for phenology/health"
    }



    Locations ||--o{ Trees : has_trees
    Species ||--o{ Trees : is_species
    HealthStatus ||--o{ Trees : has_health
    Trees ||--o{ TreeVariants : has_variants
    Scenarios ||--o{ TreeVariants : scenario_variants
    TreeVariants ||--o{ TreeStructures : has_structures
    TreeStructures ||--o{ StructureBranches : has_branches
    StructureBranches ||--o{ StructureTwigs : has_twigs
    StructureTwigs ||--o{ StructureLeaves : has_leaves
    PhenologyStatus ||--o{ StructureLeaves : has_phenology
    TreeVariants ||--o{ TreeVariants : parent_variant
    DataQualityTypes ||--o{ TreeVariants : height_quality
    DataQualityTypes ||--o{ TreeVariants : dbh_quality
    DataQualityTypes ||--o{ TreeVariants : crown_width_quality
    DataQualityTypes ||--o{ TreeVariants : volume_quality
```

### Tree Database Table Descriptions

#### Reference Tables

- **Locations**: Shared spatial reference for all tree locations
- **Species**: Tree species definitions with growth characteristics for modeling
- **HealthStatus**: Standardized health condition classifications
- **PhenologyStatus**: Seasonal and developmental stage classifications
- **DataQualityTypes**: Measurement quality indicators (Direct_Measurement, Point_Cloud_Derived, Model_Estimated)

#### Core Tables

- **Scenarios**: User-defined scenario definitions for modeling and analysis
- **Trees**: Immutable base records of observed trees from scans or field inventory
- **TreeVariants**: All tree versions including original observations, growth simulations, species replacements, and manual edits; supports scenario-based modeling with parent-child relationships

#### Structural Detail Tables

- **TreeStructures**: Unified storage for all structural representations (QSM, L-system, DeepTree, etc.)
- **StructureBranches**: Detailed branch geometry, dimensions, and spatial positioning
- **StructureTwigs**: Fine-scale twig data with morphological attributes
- **StructureLeaves**: Individual leaf data including phenology status and spatial positioning

### Tree Database Table Relationships

- **Trees** maintain immutable baseline records while **TreeVariants** enable temporal and scenario-based variations
- **Scenarios** group related variants and enable comparative analysis across different modeling conditions
- **TreeStructures** provide multiple structural representations per variant, supporting both data-driven and generative modeling approaches
- **Parent-child relationships** in TreeVariants enable growth sequence tracking and variant lineage
- **Quality metadata** ensures scientific traceability from measurement source through modeling to visualization
- **Hierarchical structure detail** (branches → twigs → leaves) enables fine-grained 3D modeling and realistic visualization

---

## 3. Environment Database (Environment DB)

Stores sensor readings, aggregated environmental snapshots, and metadata for all environmental data streams and sources. This database supports real-time environmental monitoring, historical data analysis, and provides essential environmental context for growth models, simulation scenarios, and real-time visualization systems.

```mermaid
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'background': '#FFFFFF',
      'fontFamily': 'verdana',
      'lineColor': '#ad5643',
      'primaryColor': '#5cb89c',
      'primaryTextColor': '#1d242f',
      'primaryBorderColor': '#313d4f',
      'secondaryColor': '#d6aaa1',
      'secondaryTextColor': '#1d242f',
      'secondaryBorderColor': '#ad5643',
      'tertiaryColor': '#d5d8db',
      'tertiaryTextColor': '#1d242f',
      'tertiaryBorderColor': '#313d4f'
    }
  }
}%%
erDiagram
    Locations {
        INT LocationID PK
        VARCHAR LocationName
    }

    Sensors {
        INT SensorID PK "Unique sensor ID"
        INT LocationID FK "References Locations"
        VARCHAR SensorType "Sensor type"
        DATETIME InstallationDate "Installation date"
        VARCHAR Status "Status"
        TEXT SensorConfig "JSON: config/calibration"
    }

    SensorReadings {
        INT ReadingID PK "Unique reading ID"
        INT SensorID FK "References Sensors"
        DATETIME Timestamp "Measurement time"
        VARCHAR ReadingType "Type (e.g. Temperature)"
        FLOAT Value "Value"
        VARCHAR Unit "Unit"
    }

    EnvironmentalSnapshots {
        INT SnapshotID PK "Unique snapshot ID"
        INT LocationID FK "References Locations"
        DATETIME Timestamp "Snapshot time"
        FLOAT AvgTemperature_C "Avg. temperature"
        FLOAT AvgHumidity_percent "Avg. humidity"
        FLOAT TotalPrecipitation_mm "Total precipitation"
        FLOAT AvgGlobalRadiation "Avg. radiation"
        FLOAT AvgCO2_ppm "Avg. CO2"
        FLOAT AvgWindSpeed_ms "Avg. wind speed"
        FLOAT DominantWindDirection_deg "Wind direction"
        TEXT ObstacleVoxelGridRef "Path to voxel grid"
        TEXT OtherEnvironmentalFactors "JSON: soil, groundwater, pollutants"
    }

    Locations ||--o{ Sensors : has_sensors
    Sensors ||--o{ SensorReadings : has_readings
    Locations ||--o{ EnvironmentalSnapshots : has_snapshots
    EnvironmentalSnapshots }o--|| SensorReadings : aggregates
```

### Environment Database Table Descriptions

**Locations**  
Shared spatial reference table linking environmental data to specific forest plots and monitoring sites.

**Sensors**  
Inventory of all environmental monitoring equipment with configuration, status, and installation metadata.

**SensorReadings**  
Time-series data from individual sensors capturing real-time environmental measurements with full temporal resolution.

**EnvironmentalSnapshots**  
Aggregated environmental summaries providing consolidated environmental state for specific locations and time periods, essential for modeling and scenario analysis.

### Environment Database Table Relationships

- **Locations** serve as the spatial foundation linking environmental data to specific forest sites
- **Sensors** are deployed at locations and generate continuous streams of **SensorReadings**
- **SensorReadings** provide high-resolution temporal data that feeds into aggregated **EnvironmentalSnapshots**
- **EnvironmentalSnapshots** provide model-ready environmental context by aggregating multiple sensor readings and external data sources
- The design supports both real-time monitoring and historical analysis while maintaining data lineage from individual sensors to aggregated environmental context

---

## Design Principles and System Integration

### Data Quality and Traceability

The database design ensures scientific rigor through comprehensive data quality tracking and measurement lineage. Each measurement includes metadata indicating its source (direct field measurement, point cloud analysis, or model estimation), enabling researchers to assess data reliability and maintain reproducible scientific workflows.

### Scenario-Based Modeling Support

The unified TreeVariants approach enables sophisticated scenario analysis by maintaining all tree states and modifications within a single, coherent structure. This design supports comparative analysis across different management strategies, climate scenarios, and species composition changes while preserving the original observed data.

### Multi-Scale Integration

The three-database architecture supports analysis from individual leaf geometry to landscape-scale forest dynamics. Point cloud data provides detailed 3D structure, tree data enables individual-based modeling, and environmental data supplies the context for realistic growth simulation and ecosystem analysis.

### Temporal Analysis Capabilities

Parent-child relationships in TreeVariants combined with time-series environmental data enable comprehensive temporal analysis. Researchers can track individual tree growth, analyze environmental trends, and validate growth model predictions against observed changes over time.
