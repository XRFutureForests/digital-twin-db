# XR Future Forests Lab

A comprehensive research initiative developing cutting-edge extended reality (XR) applications for forest and environmental sciences at the University of Freiburg.

## Project Overview

The XR Future Forest Lab aims to create **digital twins forests** that can be visualized and experienced through **immersive XR technologies**. The project combines advanced data acquisition, analysis, and modeling to simulate forest growth, management processes, and environmental changes and their impact on the forest over time.

## Team

### Lead

- **Prof. Dr. Thomas Purfürst**: Chair of Forest Operations, Project Spokesperson
- **Prof. Dr. Thomas Seifert**: Chair of Forest Growth and Dendroecology
- **Prof. Dr. Teja Kattenborn**: Professor of Sensor-Based Geoinformatics
- **Dr. Christian Scharinger**: Head of XRLab, Project Coordinator
- **Andreas Friedrich**: Administration

### Core Researchers

- **Paul Lakos**: XR Game Developer
- **Tom Jaksztat**:
- **Salim Soltani**: Data Engineer
- **Joachim Maack**: GIS Lectuer
- **Maximilian Sperlich**: Geospatial Data Scientist
-

### Associated Researchers

- **Daniel Lusk**: LiDAR Data management and processing
- **Julian Frey**: Quantitative Structure Models (QSM)
- **Katja Kröner**: Tree growth models
-

## Components

### XR Lab

**Responsible Team**: XRLab (Dr. Christian Scharinger)

Immersive visualization of digital forest twins for research, education, and management applications. This is the heart of the project, where the output of the different components comes to gether.

### Point Cloud Processing

**Responsible Team**: Department of Sensor-Based Geoinformatics (Prof. Dr. Teja Kattenborn)

The foundation of the digital forest twin, processing raw LiDAR and photogrammetric data.

- **3DTrees Online Platform**: Web-based interface for point cloud upload and processing
- **Automated Tree Segmentation**: Individual tree identification from forest point clouds
- **Species Classification**: Machine learning-based tree species identification
- **Quality Control**: Validation and accuracy assessment of processed data

### Digital Forest Twin

**Responsible Team**: Department of Forest Growth and Dendroecology (Prof. Dr. Thomas Seifert)Œ

Creates mathematical representations of individual trees and forest ecosystems for growth simulation.

#### Quantitative Structure Model (QSM)

#### Tree/Forest Growth Models

- **SILVA**: Individual tree growth simulator ([OptForests Toolkit](https://www.optforests.eu/toolkit/models/silva))
- **BALANCE**: Stand-level forest growth model ([TUM Archive](https://webarchiv.it.ls.tum.de/waldwachstum.wzw.tum.de/forschung/modelle/balance/index.html))

### Application conceptualization

#### Teaching

- Visualize Sensor Networks, ecosystem fluxes and processes (e.g. Hartheim, ECOSENSE)
- "Experience" remote sensing data (LiDAR and other 3D data)
-

#### Research

- Show things we cannot see (sapflow, competition, temporal dynamics)
-

#### Communication

- Service for other faculty members to visualize/communicate their research, research sites (e.g. in context of Excellence Cluster, RTGs, SFBs...).
-

### Data management

Centralized data storage of point clouds, QSM and auxiliary data

- uploaded and processed point clouds from 3Dtrees
- QSMs derived from processed point clouds or as results from forest models
- Sensor data from EcoSense
- Auxiliary data for digital forest twin:
  - Climate data
  - Weather data
  - Soil data
  - Ground water
