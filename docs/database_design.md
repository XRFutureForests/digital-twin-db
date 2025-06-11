# Database Design

## 1. Point Cloud Database (Point Cloud DB)

**Purpose:**  
Stores metadata and results from the processing of point cloud data, including references to raw files, segmentation, and classification outputs. This is the primary storage for all spatial scan data and their derived products.

**Mermaid ER Diagram:**

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

**Inputs:**  

- Raw point cloud files (uploaded via Data Ingestion API)
- Segmentation/classification outputs (via Processing Pipeline API)

**Outputs:**  

- Segmented/classified tree data (to Tree DB via Processing Pipeline API)
- 3D data for visualization (to Presentation Tier via REST/GraphQL API)

---

## 2. Tree Database (Tree DB) – Scenario & Variant-Aware

Certainly! Here is the **updated Tree DB design and description** with a single unified structure table, and extended branch, twig, and leaf tables including features such as direction, height of starting point on parent, and angle. This design is ready for copy-paste into your documentation.

---
Here is the **updated Tree Database (Tree DB) design and description** reflecting your requirements for scenario/variant management, unified structure storage, and detailed growth simulation tracking. This version:

- Uses a single `TreeStructures` table for all structure types (QSM, L-System, DeepTree, etc.)
- Links all growth simulations to `TreeVariantID` (including base/original variants)
- Includes a `TimeDelta_yrs` field in `TreeGrowthSimulations` for time interval tracking
- Extends `StructureBranches`, `StructureTwigs`, and `StructureLeaves` with direction, height of starting point, and angle fields

---

## Tree Database (Tree DB)

**Purpose:**  
Central repository for all tree-related data, supporting scenario-based modeling, variant management, growth simulation, and detailed structural representation. This design enables both data-driven (QSM) and generative (L-system, DeepTree, etc.) models in a unified structure, and supports fine-grained modeling of branches, twigs, and leaves.

### Mermaid ER Diagram

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

    TreeVariants {
        INT TreeVariantID PK
        INT TreeID FK "Nullable: NULL if new tree in scenario"
        INT ScenarioID FK
        INT ParentVariantID FK "Nullable: NULL if original or first variant"
        INT SpeciesID FK
        DATETIME VariantTimestamp
        FLOAT Height_m
        FLOAT DBH_cm
        FLOAT CrownWidth_m
        FLOAT Volume_m3
        INT HealthStatusID FK
        VARCHAR VariantType "Original, Simulated, Replaced, New"
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

    TreeGrowthSimulations {
        INT SimulationID PK
        INT TreeVariantID FK
        INT ScenarioID FK
        VARCHAR ModelType
        DATETIME SimulationTimestamp
        FLOAT TimeDelta_yrs "Time passed since parent state (years)"
        INT ParentSimulationID FK "Nullable: previous simulation, if any"
        FLOAT PredictedHeight_m
        FLOAT PredictedDBH_cm
        FLOAT PredictedVolume_m3
        FLOAT MortalityRisk_prob
        TEXT PredictedStructureData "Optional: predicted structure (e.g. L-system, QSM params)"
        INT EnvironmentalSnapshotID FK
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
    TreeVariants ||--o{ TreeGrowthSimulations : has_growth_sim
    Scenarios ||--o{ TreeGrowthSimulations : scenario_sims
    TreeVariants ||--o{ TreeVariants : parent_variant
    TreeGrowthSimulations ||--o| TreeGrowthSimulations : parent_sim
```

### Table Descriptions

- **Locations, Species, HealthStatus, PhenologyStatus:**  
  Lookup/reference tables for spatial, biological, and status data.

- **Scenarios:**  
  User-defined scenario context (e.g., species replacement, climate change).

- **Trees:**  
  Immutable records of observed trees from scans or inventory.

- **TreeVariants:**  
  All versions (original, simulated, replaced, or new) of a tree, each linked to a scenario and (optionally) a parent variant.  
  - `TreeID` is NULL for new trees created only for a scenario.

- **TreeStructures:**  
  Unified table for all structural representations (QSM, L-system, DeepTree, etc.) for each tree variant.  
  - `StructureType` distinguishes the method/model used.
  - `StructureData` can store JSON, strings, or parameters as needed.

- **StructureBranches:**  
  Detailed branch data for each structure, including length, diameter, direction (azimuth), inclination (angle from vertical), starting height on parent, and geometry.

- **StructureTwigs:**  
  Fine-scale twig data, with similar geometric and positional attributes as branches.

- **StructureLeaves:**  
  Leaf data, including geometry, phenology status, direction, inclination, starting height, and optional color for health/phenology visualization.

- **TreeGrowthSimulations:**  
  Stores simulation results for each tree variant and scenario, including predicted dimensions, mortality risk, (optionally) predicted structure data, and a `TimeDelta_yrs` field for the time interval since the parent state. `ParentSimulationID` enables chaining for time series.

### API/Data Flow Mapping

- **Data Ingestion API:**  
  Adds observed trees and initial structures.
- **Processing Pipeline API:**  
  Generates and updates QSMs and other structure types.
- **Model/Simulation Control API:**  
  Creates variants, runs growth simulations, and generates procedural/generative structures.
- **Scenario/Model Control API:**  
  Manages scenario creation, variant management, and scenario-based edits.
- **Presentation Tier (REST/GraphQL):**  
  Queries structures, branches, twigs, and leaves for visualization.

---

## 3. Environment Database (Environment DB)

**Purpose:**  
Stores sensor readings, aggregated environmental snapshots, and metadata for all environmental data streams and sources. Essential for growth models, simulation, and real-time visualization.

**Mermaid ER Diagram:**

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

**Inputs:**

- Sensor data (EcoSense, weather, soil) via Data Ingestion API (batch or streaming)
- Aggregated/derived environmental snapshots (via Model/Simulation Control API)
- User modifications for scenario testing (via DB Update API)

**Outputs:**

- Environmental context for growth models (to Logic Tier)
- Real-time or historical data for presentation (to XR/Web)
- Data for scenario analysis and simulation

---

## **How the Design Supports Your Use Cases**

- **Original trees are never overwritten.** All simulated or replaced trees are stored as new TreeVariants, each linked to a scenario and (optionally) their parent variant.
- **Scenario-based replacement and creation:** New trees for scenarios are supported by TreeVariants with `TreeID = NULL`.
- **Growth results:** Growth simulations are always linked to the TreeVariant and Scenario, allowing side-by-side comparison of multiple scenarios.
- **Consistent lookup tables:** Species and HealthStatus ensure data integrity and interoperability.
- **Comprehensive data flow:** All data flows and API endpoints are mapped to the architecture, supporting ingestion, processing, simulation, scenario analysis, and visualization.
