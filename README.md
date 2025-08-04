# Digital Twin Repository - Data Tier Implementation

> **Multi-Repository Architecture**: Data Tier of XR Future Forests Lab  
> **University**: University of Freiburg, Department of Forest Sciences  
> **Status**: Database Implementation Phase | **Target**: August 15, 2025

This repository implements the **Data Tier** of the XR Future Forests Lab multi-repository architecture, providing the foundational database infrastructure and APIs for creating **digital twins of forests** through immersive XR technologies.

## **Repository Role in XR Future Forests Lab**

### **🏗️ Data Tier Implementation**

- **PostgreSQL + PostGIS**: Spatial database with forest-specific schemas
- **FastAPI Backend**: REST APIs for data access and manipulation
- **VM Deployment**: Production infrastructure and external connectivity
- **Integration Foundation**: Data services for Logic and Presentation tiers

### **🔗 Multi-Repository Architecture**

- **📋 [Planning Hub](../xr-future-forests-lab)**: Central coordination and architecture documentation
- **🌲 [The Grove](../the-grove)**: Logic Tier - Tree Asset Generation Service (consumes Tree API)
- **☁️ [Potree Docker](../potree-docker)**: Logic Tier - Point Cloud Processing Service (uses Point Cloud API)

## **Project Vision**

The XR Future Forests Lab represents a groundbreaking approach to forest science, combining cutting-edge technologies to create comprehensive digital forest ecosystems. This repository provides the data foundation that enables:

### **Research Innovation**

- **Digital Forest Twins**: Complete digital replications of forest ecosystems with real-time data integration
- **Invisible Process Visualization**: Make hidden forest processes (sap flow, root competition, nutrient cycling) visible and interactive
- **Advanced Growth Modeling**: Integration with SILVA and other tree-based models for scientifically accurate forest simulation
- **Multi-scale Analysis**: Seamless exploration from individual tree characteristics to landscape-level dynamics

### **Educational Excellence**

- **Immersive Learning**: Experience forest ecosystems in ways impossible in traditional field studies
- **Risk-free Training**: Practice forest management decisions in virtual environments before real-world application
- **Temporal Dynamics**: Visualize decades of forest change in accelerated time
- **Interactive Data Exploration**: Transform complex datasets into intuitive, engaging learning experiences

### **Stakeholder Engagement**

- **Policy Communication**: Translate complex forest research into accessible visualizations for decision-makers
- **Public Outreach**: Make forest science engaging and understandable for broader audiences
- **Interdisciplinary Collaboration**: Bridge forest science with technology, education, and policy domains
- **Industry Partnerships**: Develop practical tools for modern forest management

## **Documentation & Architecture**

Complete system documentation is available in the `docs/` directory:

- **[System Architecture](./docs/architecture/architecture.md)** - Three-tier architecture design
- **[Database Design](./docs/architecture/database.md)** - Schema specifications  
- **[Tech Stack](./docs/tech-stack.md)** - Technology overview and data flow examples
- **[API Architecture](./docs/architecture/api.md)** - REST API interfaces
- **[Services Architecture](./docs/architecture/services.md)** - Service layer design

## **System Services**

The Data Tier runs four core services via Docker Compose, providing unified data infrastructure for the entire XR Future Forests Lab:

- **PostgreSQL + PostGIS** (`postgres:5432`) - Spatial database with forest-specific schemas
- **Redis** (`redis:6379`) - Caching and event messaging for real-time updates
- **Python API** (`api:8000`) - FastAPI REST services with async processing
- **nginx** (`nginx:80`) - Reverse proxy and API gateway for Logic Tier integration

## **API Services for Multi-Repository Integration**

### **Core APIs**

- **Point Cloud API** (`/api/pointclouds/`) - LiDAR data management for Potree Docker repository
- **Tree API** (`/api/trees/`) - Forest inventory data for The Grove repository
- **Sensor API** (`/api/sensors/`) - Environmental monitoring and time-series data
- **Environment API** (`/api/environments/`) - Environmental condition variants
- **Audit API** (`/api/audit/`) - Field-level change tracking across all data

### **Integration Patterns**

- **The Grove Repository**: Consumes Tree API for species data and measurement input
- **Potree Docker Repository**: Uses Point Cloud API to store processing results
- **External VR Applications**: Access forest data through standardized REST APIs

## **Current Implementation Status**

### ✅ **Foundation Complete** (Milestone 1 - DONE)

- System architecture documented and designed
- Database schema finalized (`docs/architecture/xr_forests_complete_erd.dbml`)
- Docker infrastructure functional and tested
- Development environment ready

### 🔧 **Database Implementation** (Milestone 2 - IN PROGRESS)

- PostgreSQL schema deployment from DBML
- PostGIS spatial data configuration
- Sample forest data loading and validation
- Local testing and development verification

### 📋 **Production Deployment** (Milestone 3 - PLANNED)

- VM server configuration and deployment
- External API connectivity for Logic Tier repositories
- Production monitoring and backup systems
- Documentation for system handoff

**🎯 Target Deadline**: August 15, 2025 - Core database operational for VR integration
