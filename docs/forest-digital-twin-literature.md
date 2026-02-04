# Forest Digital Twin Literature Review

A comprehensive review of academic literature and resources on forest digital twins, standards, and related technologies.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Key Academic Publications](#key-academic-publications)
3. [Industry & Research Resources](#industry--research-resources)
4. [Relevant Standards & Frameworks](#relevant-standards--frameworks)
5. [Technology Components](#technology-components)
6. [Research Gaps & Future Directions](#research-gaps--future-directions)

---

## Introduction

Forest digital twins represent the application of digital twin technology to forest ecosystems, enabling real-time monitoring, simulation, and management of forest resources. This literature review consolidates current academic research, industry initiatives, and relevant standards that inform the development of forest digital twin systems.

---

## Key Academic Publications

### Forest Digital Twins - Core Research

#### A Digital Twin Architecture for Forest Restoration: Integrating AI, IoT, and Blockchain for Smart Ecosystem Management

**Authors:** N. Sasaki, I. Abe (2025)  
**DOI:** [10.3390/fi17090421](https://doi.org/10.3390/fi17090421)

**Key Contributions:**

- Proposes a four-layer architecture for forest restoration digital twins:
  1. **Physical Layer** - Drones and IoT-enabled sensors for environmental monitoring
  2. **Data Layer** - Secure transmission of spatiotemporal data
  3. **Intelligence Layer** - AI-driven modeling, simulation, and predictive analytics
  4. **Application Layer** - Stakeholder dashboards, smart contracts, automated climate finance
- Evidence from Dronecoria, Flash Forest, and AirSeed Technologies demonstrates:
  - Per-tree planting costs reduction from USD 2.00-3.75 to USD 0.11-1.08
  - Enhanced accuracy, scalability, and community participation
- Policy integration with Enhanced Transparency Framework (ETF) and Article 5 of the Paris Agreement

---

#### Forest Digital Twin: A Digital Transformation Approach for Monitoring Greenhouse Gas Emissions

**Authors:** J.R. Silva, P. Artaxo, E. Vital (2023)  
**DOI:** [10.1007/s41050-023-00041-z](https://doi.org/10.1007/s41050-023-00041-z)

**Key Contributions:**

- Framework for GHG monitoring in forest ecosystems
- Integration of sensor networks with digital twin models
- Carbon sequestration calculation methodologies

---

#### Conceptual Model of Graph-based Individual Tree and Its Utilization in Digital Twin and Metaverse of Urban Forest

**Authors:** A. Ambarwari, D. Suwardhi, et al. (2024)  
**DOI:** [10.5194/isprs-archives-xlviii-4-2024-7-2024](https://doi.org/10.5194/isprs-archives-xlviii-4-2024-7-2024)

**Key Contributions:**

- Proposes graph-based conceptual model for individual trees conforming to **CityGML v2.0**
- Emphasizes five main aspects from CityGML:
  1. **Scale/Level of Detail (LoD)**
  2. **Semantics**
  3. **Geometry**
  4. **Topology**
  5. **Appearance**
- Model refers to morphological structure: roots, trunk, crown (branches, twigs, leaves)
- Applicable for urban forest digital twins and metaverse simulations

---

#### Employing Digital Twin to Forest Fire Management Systems

**Authors:** B. Aydin, S.F. Oktug (2024)  
**DOI:** [10.1109/UBMK63289.2024.10773422](https://doi.org/10.1109/UBMK63289.2024.10773422)

**Key Contributions:**

- IoT-based forest fire detection using digital twin
- Network state forecaster for IoT integration
- Real-time fire simulation capabilities

---

### Remote Sensing & LiDAR for Forest Inventory

#### Towards a Digital Twin of Liege: The Core 3D Model based on Semantic Segmentation and Automated Modeling of LiDAR Point Clouds

**Authors:** Z. Ballouch, et al. (2024)  
**DOI:** [10.5194/isprs-annals-x-4-w4-2024-13-2024](https://doi.org/10.5194/isprs-annals-x-4-w4-2024-13-2024)

**Key Contributions:**

- Automatic modeling pipeline for buildings, roads, and vegetation from LiDAR
- Semantic segmentation approach integrating multiple training datasets
- Open-source reconstruction tools for building and road modeling
- Python-optimized code for tree modeling

---

#### Individual Tree Diameter Estimation in Small-Scale Forest Inventory Using UAV Laser Scanning

**Authors:** Y. Hao, et al. (2020)  
**DOI:** [10.3390/rs13010024](https://doi.org/10.3390/rs13010024)

**Key Contributions:**

- DBH-UAVLS point cloud estimation using generalized nonlinear mixed-effects (NLME) model
- 8,364 correctly delineated trees from UAVLS data across 118 plots
- Best linear unbiased predictor (BLUP) for local model calibration
- RMSE of 1.94 cm achieved

---

#### Dominant Tree Species Mapping Using Machine Learning Based on Multi-Temporal and Multi-Source Data

**Authors:** H. Guo, et al. (2024)  
**DOI:** [10.3390/rs16244674](https://doi.org/10.3390/rs16244674)

**Key Contributions:**

- Classification of five dominant tree species using Sentinel-1 and Sentinel-2
- Multi-temporal data from March, June, September, December
- XGBoost achieved 81.25% accuracy (kappa = 0.74)
- Combines SAR and optical data for large-scale classification

---

#### Mapping Dominant Tree Species of German Forests

**Authors:** T. Welle, et al. (2022)  
**DOI:** [10.3390/rs14143330](https://doi.org/10.3390/rs14143330)

**Key Contributions:**

- National-scale tree species mapping using Sentinel-2 time series
- Seven main tree species classes
- F1-scores: 0.77-0.91 (deciduous), 0.85-0.94 (non-deciduous)
- Public web-based interactive map

---

### Digital Twin Standards & Architecture

#### Digital Twin Platforms: Requirements, Capabilities, and Future Prospects

**Authors:** D. Lehner, et al. (2022)  
**DOI:** [10.1109/ms.2021.3133795](https://doi.org/10.1109/ms.2021.3133795)  
**Citations:** 89

**Key Contributions:**

- Investigation of Amazon, Eclipse, and Microsoft DT platforms
- Assessment of standard requirements for digital twins
- Framework for evaluating DT platform capabilities

---

#### XRTwin4Industry: A Comprehensive Framework for Standardisation and Interoperability in XR-Enabled Industrial Digital Twins

**Authors:** T. Lacheroy, et al. (2025)  
**DOI:** [10.1109/PerComWorkshops65533.2025.00056](https://doi.org/10.1109/PerComWorkshops65533.2025.00056)

**Key Contributions:**

- Framework aligned with **IEC 63278** standard series
- **Asset Administration Shell** vision of Industry 4.0
- Focus on visualization, interaction, standardization, interoperability

---

#### Edge Computing-Based Digital Twin Framework Based on ISO 23247 for Enhancing Data Processing Capabilities

**Authors:** M.S. Kang, et al. (2024)  
**DOI:** [10.3390/machines13010019](https://doi.org/10.3390/machines13010019)  
**Citations:** 19

**Key Contributions:**

- Proposes edge computing-based DT (E-DT) framework
- Functional aspects represented using **ISO 23247** reference architecture
- Data fusion model for informational aspects
- Reduced latency through edge processing

---

#### An OGC API–Based Framework for Scalable and Interoperable Urban Digital Twin Ecosystems

**Authors:** T. Santhanavanich, et al. (2025)  
**DOI:** [10.5194/isprs-archives-xlviii-4-w15-2025-135-2025](https://doi.org/10.5194/isprs-archives-xlviii-4-w15-2025-135-2025)

**Key Contributions:**

- Modern **OGC APIs**: Features, 3D GeoVolumes, Tiles, SensorThings
- RESTful APIs surpassing WFS and WMS
- Traffic noise modeling and Geo-AI analysis use cases
- CesiumJS for 3D Tiles and point cloud rendering

---

#### Digital Smart City: Integrating IFC and CityGML with Semantic Graph for Advanced 3D City Model Visualization

**Authors:** P.D. Lam, et al. (2024)  
**DOI:** [10.3390/s24123761](https://doi.org/10.3390/s24123761)  
**Citations:** 21

**Key Contributions:**

- Data transformation between IFC, CityGML, and OWL/RDF
- CityGML LOD4 for enhanced BIM interoperability
- RDF graph for semantic mapping analysis
- Neo4j for visualization

---

### Environmental & Ecosystem Monitoring

#### Digital Twin-Ready Earth Observation: Operationalizing GeoML for Agricultural CO2 Flux Monitoring at Field Scale

**Authors:** A. Khan, et al. (2025)  
**DOI:** [10.3390/rs17213615](https://doi.org/10.3390/rs17213615)

**Key Contributions:**

- Digital Twin-ready framework for GeoML operationalization
- NEE of CO2 prediction with R² of 0.76 and NRMSE of 8%
- Uses Copernicus Data Space Ecosystem OpenEO API
- Average response time of 6.12 seconds

---

#### IoT-Based Digital Twin for Freshwater Pollution Monitoring

**Authors:** M.A. Jarwar, et al. (2025)  
**DOI:** [10.1109/PIMRC62392.2025.11274979](https://doi.org/10.1109/PIMRC62392.2025.11274979)

**Key Contributions:**

- Four-layer architecture: device, virtualization, aggregation, service
- Real-time dissolved oxygen and temperature monitoring
- Anomaly detection and historical trend analysis

---

### Forest Inventory & Growth Modeling

#### Forest Site Classification and Grading Using Mixed-Variables Clustering

**Authors:** B. Wu, et al. (2025)  
**DOI:** [10.1093/forestry/cpaf017](https://doi.org/10.1093/forestry/cpaf017)

**Key Contributions:**

- 16,162 sample plots dataset
- Mixed-variables clustering (discrete + continuous)
- Mixed-effects site form model
- 10 site types with hierarchical agglomeration

---

#### Predicting Individual-Tree Growth of Central European Tree Species

**Authors:** B. Rohner, et al. (2017)  
**DOI:** [10.1007/s10342-017-1087-7](https://doi.org/10.1007/s10342-017-1087-7)  
**Citations:** 82

**Key Contributions:**

- Site, stand, management, nutrient, and climate effects on growth
- Comprehensive growth prediction model
- Applied to multiple Central European species

---

#### An Individual-Tree Linear Mixed-Effects Model for Predicting Basal Area Increment

**Authors:** L. Di Cosmo, et al. (2020)  
**DOI:** [10.5424/fs/2020293-15500](https://doi.org/10.5424/fs/2020293-15500)

**Key Contributions:**

- 34,638 trees of 31 species from Italian National Forest Inventory
- Two-level mixed-effects modeling for hierarchical data
- McFadden's Pseudo-R² of 0.536
- Reduced MAE by 64.5% vs OLS regression

---

## Industry & Research Resources

### VTT Research (Finland)

**URL:** [vttresearch.com - Digital Twins Make Future Forests Accessible](https://www.vttresearch.com/en/news-and-ideas/digital-twins-make-future-forests-accessible-everyone)

Finland's VTT research initiative on making forest digital twins accessible for broader stakeholders.

---

### Technical University of Munich

**URL:** [TUM - Digital Twin Depicts the Forest in 100 Years](https://www.tum.de/en/news-and-events/all-news/press-releases/details/digital-twin-depicts-the-forest-in-100-years)

Long-term forest prediction modeling using digital twin technology, 100-year simulation capabilities.

---

### Modellfabrik Papier (Germany)

**URL:** [Forest Digital Twin Takes Shape](https://modellfabrikpapier.de/en/news-en/forest-digital-twin-takes-shape/)

Industrial application of forest digital twins for the paper industry supply chain.

---

### GDI-DE Presentation

**URL:** [Vortrag Zwillingstag - Forest Digital Twins](https://www.gdi-de.org/download/2025-06/Vortrag_Zwillingstag_Forest_Digital_Twins_Juergen_Doellner.pdf)

**Author:** Jürgen Döllner

Presentation on forest digital twins in the context of German geodata infrastructure.

---

### MDPI Future Internet Journal

**URL:** [MDPI 1999-5903/17/9/421](https://www.mdpi.com/1999-5903/17/9/421)

Open access publication on forest digital twin architectures.

---

## Relevant Standards & Frameworks

### Geospatial Standards

| Standard | Description | Application |
|----------|-------------|-------------|
| **CityGML** | OGC standard for 3D city models | Urban forest modeling, LOD definitions |
| **OGC API - Features** | RESTful API for spatial features | Tree and sensor data access |
| **OGC API - SensorThings** | IoT sensor data standard | Environmental monitoring |
| **OGC 3D Tiles** | Efficient 3D content streaming | Point cloud visualization |
| **IFC (Industry Foundation Classes)** | BIM data exchange | Integration with built environment |

### Digital Twin Standards

| Standard | Description | Application |
|----------|-------------|-------------|
| **ISO 23247** | Digital Twin Framework for Manufacturing | Reference architecture, data fusion |
| **IEC 63278** | Asset Administration Shell | Industry 4.0 interoperability |
| **ISO 10303 STEP** | Product data exchange | Processing lineage tracking |

### Environmental & Forest Standards

| Standard | Description | Application |
|----------|-------------|-------------|
| **GBIF** | Global Biodiversity Information Facility | Species validation |
| **Darwin Core** | Biodiversity data standard | Species occurrence data |
| **Paris Agreement ETF** | Enhanced Transparency Framework | Carbon reporting |
| **UNFCCC LULUCF** | Land Use, Land Use Change and Forestry | Carbon accounting |

### Communication Protocols

| Protocol | Description | Best For |
|----------|-------------|----------|
| **MQTT over TCP** | Message queuing telemetry transport | Lowest latency (290.5 ms avg) |
| **MQTT over WebSocket** | Browser-compatible MQTT | Most stable (193.2 ms std dev) |
| **HTTP** | Traditional REST | Broader compatibility (342.6 ms avg) |
| **OPC UA** | Industrial communication | Manufacturing systems |

---

## Technology Components

Based on the literature review, a comprehensive forest digital twin requires:

### Data Acquisition Layer

1. **LiDAR Systems**
   - Terrestrial Laser Scanning (TLS)
   - Airborne Laser Scanning (ALS)
   - UAV-based Laser Scanning (ULS)
   - Mobile Laser Scanning (MLS)

2. **Remote Sensing**
   - Sentinel-1 (SAR)
   - Sentinel-2 (Multispectral)
   - High-resolution aerial imagery

3. **IoT Sensor Networks**
   - Environmental (temperature, humidity, CO2)
   - Soil (moisture, temperature, nutrients)
   - Tree physiology (sap flow, dendrometers)

### Data Processing Layer

1. **Point Cloud Processing**
   - Semantic segmentation
   - Tree detection and delineation
   - DBH and height extraction

2. **Machine Learning**
   - Species classification
   - Growth prediction
   - Anomaly detection

3. **Simulation Models**
   - Growth models (empirical and process-based)
   - Climate scenario modeling
   - Disturbance simulation

### Data Management Layer

1. **Spatial Database**
   - PostgreSQL + PostGIS
   - Temporal versioning (variant lineage)
   - Audit trail

2. **Standardized APIs**
   - OGC API Features
   - OGC SensorThings
   - RESTful endpoints

3. **Data Interoperability**
   - CityGML for 3D models
   - RDF/OWL for semantic graphs
   - ISO 23247 for DT architecture

### Visualization Layer

1. **3D Rendering**
   - CesiumJS / 3D Tiles
   - Unreal Engine 5
   - Web-based dashboards

2. **XR Applications**
   - VR forest experiences
   - AR field tools
   - Metaverse integration

---

## Research Gaps & Future Directions

Based on the literature analysis, the following gaps and opportunities are identified:

### Current Gaps

1. **Standardization**
   - No unified standard specifically for forest digital twins
   - Limited semantic interoperability between forest data systems
   - Inconsistent tree attribute definitions across systems

2. **Scalability**
   - Most implementations are proof-of-concept or limited scale
   - Challenges in real-time processing of continental-scale data
   - Storage and compute costs for high-resolution data

3. **Integration**
   - Limited connection between forest DTs and climate models
   - Sparse integration with carbon market systems
   - Disconnected from policy and reporting frameworks

### Future Directions

1. **Forest-Specific Standards**
   - CityGML Application Domain Extension (ADE) for forests
   - Standardized tree attribute vocabularies
   - Common API specifications

2. **AI/ML Integration**
   - Foundation models for forest ecosystems
   - Transfer learning across forest types
   - Automated species and health assessment

3. **Carbon & Climate**
   - Real-time carbon flux monitoring
   - Integration with Article 5 reporting
   - Blockchain for verification (MRV)

4. **Accessibility**
   - Lower-cost sensor networks
   - Community science integration
   - Open-source tooling

---

## References Summary

| Category | Count | Key Sources |
|----------|-------|-------------|
| Forest Digital Twins | 4 | Sasaki 2025, Silva 2023, Ambarwari 2024 |
| LiDAR & Remote Sensing | 5 | Hao 2020, Guo 2024, Welle 2022 |
| DT Standards | 5 | Lehner 2022, Kang 2024, Santhanavanich 2025 |
| Forest Inventory | 4 | Wu 2025, Rohner 2017, Di Cosmo 2020 |
| Environmental Monitoring | 3 | Khan 2025, Jarwar 2025 |

---

*Last updated: February 2026*
