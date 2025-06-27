# XR Future Forests Lab

> **University**: University of Freiburg, Department of Forest Sciences  
> **Status**: Architecture Design & Planning Phase

An ambitious research project aimed at creating **digital twins of forests** through immersive XR technologies. The project combines advanced data acquisition, spatial analysis, and growth modeling to enable unprecedented forest visualization, research, and management capabilities.

## 🌟 **Project Vision**

The XR Future Forests Lab represents a groundbreaking approach to forest science, combining cutting-edge technologies to create comprehensive digital forest ecosystems. Our vision encompasses three primary domains:

### 🔬 **Research Innovation**

- **Digital Forest Twins**: Complete digital replications of forest ecosystems with real-time data integration
- **Invisible Process Visualization**: Make hidden forest processes (sap flow, root competition, nutrient cycling) visible and interactive
- **Advanced Growth Modeling**: Integration with SILVA and BALANCE models for scientifically accurate forest simulation
- **Multi-scale Analysis**: Seamless exploration from individual tree characteristics to landscape-level dynamics

### 🎓 **Educational Excellence**

- **Immersive Learning**: Experience forest ecosystems in ways impossible in traditional field studies
- **Risk-free Training**: Practice forest management decisions in virtual environments before real-world application
- **Temporal Dynamics**: Visualize decades of forest change in accelerated time
- **Interactive Data Exploration**: Transform complex datasets into intuitive, engaging learning experiences

### 🤝 **Stakeholder Engagement**

- **Policy Communication**: Translate complex forest research into accessible visualizations for decision-makers
- **Public Outreach**: Make forest science engaging and understandable for broader audiences
- **Interdisciplinary Collaboration**: Bridge forest science with technology, education, and policy domains
- **Industry Partnerships**: Develop practical tools for modern forest management

## 🏗️ **System Architecture**

The XR Future Forests Lab implements a sophisticated three-tier architecture designed to seamlessly integrate forest data acquisition, processing, and immersive visualization.

### **Data Tier**

- **Diverse Data Sources**: Integration with 3DTrees Platform, EcoSense Sensors, Forest Inventory systems, and External Environmental Data
- **Intelligent Data Ingestion**: Automated pipeline service for data validation, format standardization, and temporal alignment
- **Comprehensive Database**: PostgreSQL with PostGIS extensions organized into specialized schemas (shared, pointclouds, trees, monitoring, environments)
- **Real-time Processing**: High-frequency sensor data aggregation with quality assessment and spatial correlation

### **Logic Tier**

- **Advanced Point Cloud Processing**: Automated tree segmentation, species classification, and structural attribute extraction
- **Growth Simulation Engine**: Integration with scientific models (SILVA, BALANCE) for accurate forest development prediction
- **Processing Services**: Distributed services for LiDAR analysis, environmental modeling, and simulation orchestration

### **Presentation Tier**

- **Immersive XR Experiences**: Full-featured XR applications for forest exploration and interaction
- **3DTrees Web Platform**: Browser-based point cloud visualization and processing management
- **Field Web Application**: Mobile-optimized interface with QR code scanning for real-time forest inventory
- **API Gateway**: Unified access point with comprehensive REST APIs for all system components

### **Core Technologies**

- **Database**: PostgreSQL with PostGIS for spatial data management
- **APIs**: RESTful services (Point Cloud, Tree, Sensor, Environment, Simulation APIs)
- **Processing**: Python-based services for LiDAR analysis and growth modeling
- **Visualization**: WebGL-based web interfaces and native XR applications
- **Real-time**: Event-driven architecture for live data updates and collaborative experiences

## � **Documentation**

### Architecture Documentation

- **[System Architecture](./docs/architecture/architecture.md)** - Comprehensive three-tier architecture design
- **[Database Design](./docs/architecture/database.md)** - Detailed database schemas and relationships
- **[API Architecture](./docs/architecture/api.md)** - Complete API specifications and interfaces
- **[Services Architecture](./docs/architecture/services.md)** - Service layer design and integration patterns

### Reference Documentation

- **[Project Overview & Vision](./docs/README.md)** - Understanding our goals and approach
- **[Technology Stack](./docs/architecture/)** - Technical components and design decisions

### Manual Database Setup

```bash
# Create tables
docker-compose exec api python create_tables.py

# Insert sample data (automatically included)
```

## 🧪 **Testing**

```bash
# Test API endpoints
python test_api.py

# Manual testing via documentation
open http://localhost:8000/docs
```

## 📝 **Sample API Usage**

### Create a Location

```bash
curl -X POST "http://localhost:8000/api/locations/" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Forest", "latitude": 47.9947, "longitude": 7.8394}'
```

### Create a Tree

```bash  
curl -X POST "http://localhost:8000/api/trees/" \
  -H "Content-Type: application/json" \
  -d '{"height": 15.5, "diameter": 45.2, "status": "healthy", "species_id": 1, "location_id": 1}'
```

### Get All Trees

```bash
curl "http://localhost:8000/api/trees/"
```

## 🔧 **Configuration**

Environment variables (set in `docker-compose.yml`):

- `XR_FORESTS_DATABASE_URL` - PostgreSQL connection string
- `XR_FORESTS_API_HOST` - API host binding

## 🐛 **Troubleshooting**

### Common Issues

**API not responding:**

```bash
# Check if containers are running
docker-compose ps

# Check API logs
docker-compose logs api
```

**Database connection errors:**

```bash
# Restart PostgreSQL
docker-compose restart postgres

# Check database logs
docker-compose logs postgres
```

## 🚧 **Future Enhancements**

- Redis integration for caching
- Authentication and authorization
- Advanced spatial queries with PostGIS
- Real-time WebSocket updates
- XR visualization clients

---

This MVP provides a solid foundation for forest research data management and can be extended with additional features as needed.

- XR client applications for immersive forest exploration
- Advanced machine learning for automated species classification
- Integration with external sensor networks and IoT devices

## 📚 **Documentation**

### 🎯 **Get Started**

- **[Setup Guide](./docs/guides/setup.md)** - Complete installation and first run
- **[Project Overview](./docs/guides/project-overview.md)** - Understanding our vision and goals
- **[API Overview](./docs/api/overview.md)** - Using the REST API with examples

### 👨‍💻 **For Developers**

- **[Development Guide](./docs/guides/development.md)** - Complete development workflow
- **[Contributing Guide](./docs/guides/contributing.md)** - How to contribute to the project
- **[System Architecture](./docs/architecture/system-architecture.md)** - Technical design details
- **[Architecture Diagrams](./docs/architecture/diagrams-index.md)** - Visual diagrams (Mermaid + Draw.io)

### 🔧 **Technical Reference**

- **[API Documentation](./docs/api/endpoints.md)** - Complete endpoint reference
- **[Database Design](./docs/architecture/database-design.md)** - Schema and data models
- **[Technology Stack](./docs/architecture/technology-stack.md)** - Technology explanations

## 🏗️ **Architecture Summary**

**Three-Tier Design** optimized for spatial data and real-time processing:

- **🖥️ Presentation Tier**: FastAPI REST API with interactive documentation
- **⚙️ Logic Tier**: Business services, data processing, and event handling  
- **🗄️ Data Tier**: PostgreSQL + PostGIS + Redis for comprehensive data management

**Technology Stack**: Python, FastAPI, PostgreSQL, PostGIS, Redis, Docker

## Services

### 1. PostgreSQL with PostGIS (`postgres`)

- **Image**: `postgis/postgis:15-3.3`
- **Port**: `5432`
- **Database**: `xr_forests_lab`
- **Features**:
  - Spatial data support via PostGIS
  - Simplified MVP database schema (Trees, Locations, Species)
  - Sample data included

### 2. Redis (`redis`)

- **Image**: `redis:7-alpine`
- **Port**: `6379`
- **Features**:
  - Event bus for real-time communication
  - Persistent storage enabled
  - Health checks configured

### 3. Python API (`api`)

- **Framework**: FastAPI with async support
- **Port**: `8000`
- **Features**:
  - RESTful API endpoints
  - WebSocket support for real-time updates
  - Redis event publishing
  - PostGIS spatial queries

## API Endpoints

### Core Resources

#### Locations

- `GET /api/locations` - List all forest locations
- `GET /api/locations/{id}` - Get specific location
- `POST /api/locations` - Create new location
- `PUT /api/locations/{id}` - Update location
- `DELETE /api/locations/{id}` - Delete location

#### Trees

- `GET /api/trees` - List trees with optional filtering
- `GET /api/trees/{tree_id}` - Get detailed tree information
- `POST /api/trees` - Create new tree record
- `PUT /api/trees/{tree_id}` - Update tree record
- `DELETE /api/trees/{tree_id}` - Delete tree record
- `GET /api/trees/{tree_id}/measurements` - Get tree measurements
- `POST /api/trees/{tree_id}/measurements` - Add tree measurements
- `GET /api/trees/{tree_id}/health` - Get health assessments
- `POST /api/trees/{tree_id}/health` - Add health assessment
- `POST /api/trees/bulk-import` - Bulk import trees
- `POST /api/trees/upload-csv` - Upload trees from CSV

### Environmental Data

#### Sensors

- `GET /api/sensors` - List environmental sensors
- `GET /api/sensors/{sensor_id}` - Get specific sensor
- `GET /api/sensors/{sensor_id}/readings` - Get sensor readings

#### Environment Data

- `GET /api/environment/readings` - Get sensor readings
- `POST /api/environment/readings` - Add sensor reading
- `GET /api/environment/snapshots` - Get environmental snapshots
- `POST /api/environment/snapshots` - Create environmental snapshot
- `GET /api/environment/sites/{id}/characteristics` - Get site characteristics
- `POST /api/environment/sites/{id}/characteristics` - Add site characteristics
- `PUT /api/environment/sites/{id}/characteristics` - Update site characteristics

### Reference Data

- `GET /api/species` - List tree species
- `GET /api/species/{id}` - Get specific species

### Real-time Updates

- `WebSocket /ws` - Real-time event stream

## Project Overview

The XR Future Forest Lab aims to create **digital twins of forests** that can be visualized and experienced through **immersive XR technologies**. The project combines advanced data acquisition, analysis, and modeling to simulate forest growth, management processes, and environmental changes and their impact on the forest over time.

### Objectives

- Create comprehensive digital twins of forest ecosystems
- Develop immersive XR applications for forest visualization
- Enable simulation of forest growth and management scenarios
- Provide innovative tools for research, education, and forest management
- Bridge the gap between forest science and cutting-edge technology

## Team

### Lead

- **Prof. Dr. Thomas Purfürst**: Chair of Forest Operations, Project Spokesperson
- **Prof. Dr. Thomas Seifert**: Chair of Forest Growth and Dendroecology
- **Prof. Dr. Teja Kattenborn**: Professor of Sensor-Based Geoinformatics
- **Dr. Christian Scharinger**: Head of XRLab, Project Coordinator
- **Andreas Friedrich**: Administration

### Core Researchers

- **Paul Lakos**: XR Game Developer
- **Tom Jaksztat**: Software Development & System Integration
- **Salim Soltani**: Data Engineer
- **Joachim Maack**: GIS Lecturer
- **Maximilian Sperlich**: Geospatial Data Scientist & System Integration

### Associated Researchers

- **Daniel Lusk**: DevOps
- **Julian Frey**: Quantitative Structure Models (QSM)
- **Katja Kröner**: Tree Growth Models

## 🚀 **Core Components**

### **XR Lab**

*Responsible Team*: XRLab (Dr. Christian Scharinger)

The central hub where all components converge. The XR Lab develops immersive visualization applications that bring digital forest twins to life, enabling users to experience and interact with forest data in unprecedented ways.

**Planned Capabilities**:

- Real-time forest visualization and interaction
- Multi-user collaborative environments  
- Educational simulation scenarios
- Research data exploration tools

### **Point Cloud Processing**

*Responsible Team*: Department of Sensor-Based Geoinformatics (Prof. Dr. Teja Kattenborn)

The foundation of the digital forest twin, transforming raw LiDAR and photogrammetric data into structured forest information.

**Key Features**:

- **3DTrees Online Platform**: Web-based interface for point cloud upload and processing
- **Automated Tree Segmentation**: Individual tree identification from forest point clouds
- **Species Classification**: Machine learning-based tree species identification
- **Quality Control**: Validation and accuracy assessment of processed data

**Technology Stack**: Python, R, CloudCompare, lidR, Machine Learning algorithms

### **Digital Forest Twin**

*Responsible Team*: Department of Forest Growth and Dendroecology (Prof. Dr. Thomas Seifert)

Digital representations of individual trees and forest ecosystems for growth simulation.

**Growth Models**:

- **SILVA**: Individual tree growth simulator
- **BALANCE**: Stand-level forest growth model
- **Quantitative Structure Models (QSM)**: Detailed tree structural analysis

## 🎯 **Applications & Use Cases**

### **Teaching & Education**

- **Sensor Network Visualization**: Experience EcoSense sensor networks and ecosystem fluxes (e.g., Hartheim site)
- **Remote Sensing Education**: "Experience" LiDAR and other 3D data through immersive exploration
- **Forest Management Training**: Practice forestry decisions in risk-free virtual environments
- **Temporal Dynamics**: Visualize long-term forest changes in accelerated time

### **Research Innovation**

- **Invisible Processes**: Visualize hidden forest processes (sap flow, root competition, nutrient flows)
- **Data Exploration**: Interactive analysis of complex forest datasets
- **Hypothesis Testing**: Test management scenarios before real-world implementation
- **Multi-scale Analysis**: Examine forests from tree level to landscape scale

### **Communication & Outreach**

- **Faculty Collaboration**: Platform for visualizing research from Excellence Clusters, RTGs, SFBs
- **Stakeholder Engagement**: Communicate forest research to policymakers and the public
- **Interdisciplinary Outreach**: Bridge forest science with other disciplines
- **Public Education**: Make forest science accessible to broader audiences

## 🔮 **Future Vision**

This project represents the future of forest science - where cutting-edge technology meets traditional forest research to create unprecedented insights and experiences. The XR Future Forests Lab will serve as a model for how immersive technologies can transform scientific research, education, and public engagement in environmental sciences.

The comprehensive architecture and database designs documented in this repository provide the foundation for implementing this vision, enabling the creation of truly immersive forest experiences that will revolutionize how we understand, study, and manage forest ecosystems.
