# XR Future Forests Lab

> **Status**: Full-featured MVP with comprehensive API implementation  
> **Live API**: <http://localhost:8000/docs> (when running)  
> **University**: University of Freiburg, Department of Forest Sciences

A comprehensive digital twin ecosystem for forest research and management, combining extended reality (XR), spatial data processing, and real-time environmental monitoring.

## 🚀 **Quick Start**

### 5-Minute Setup

```bash
# Clone and setup
git clone <repository-url>
cd xr-future-forests-lab
./setup.sh

# Start all services
docker-compose up -d

# Verify everything works
curl http://localhost:8000/health
```

**✅ Done!** Access the interactive API at <http://localhost:8000/docs>

### What You Get

- **Complete REST API** with 50+ endpoints for forest data management
- **Interactive Documentation** for testing and exploration
- **Spatial Database** with PostGIS for geographic data
- **Real-time Events** via Redis for live updates
- **Point Cloud Processing** for 3D forest data analysis

## 🌟 **Current Capabilities**

### ✅ **Fully Implemented**

- **Forest Location Management** - CRUD operations for forest sites with spatial data
- **Tree Lifecycle Tracking** - Individual tree monitoring, measurements, and health assessments  
- **Point Cloud Processing** - Upload, segmentation, classification, and quality assessment
- **Environmental Monitoring** - Sensor data collection and site characterization
- **Species Database** - Tree species classification and management
- **Sensor Management** - Sensor monitoring and data collection
- **Bulk Operations** - CSV imports and batch processing
- **Real-time Events** - WebSocket support and event-driven updates

### 🔄 **In Development**

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
  - Three specialized database schemas (Point Cloud, Tree, Environment)
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

### Point Cloud Data

- `GET /api/point-clouds` - List point cloud scans
- `GET /api/point-clouds/{id}` - Get specific point cloud
- `POST /api/point-clouds` - Create point cloud record
- `PUT /api/point-clouds/{id}` - Update point cloud
- `DELETE /api/point-clouds/{id}` - Delete point cloud
- `POST /api/point-clouds/upload` - Upload point cloud file
- `GET /api/point-clouds/{id}/processing-jobs` - Get processing jobs
- `POST /api/point-clouds/{id}/processing-jobs` - Start processing job
- `GET /api/point-clouds/{id}/quality` - Get quality assessment
- `POST /api/point-clouds/{id}/quality` - Run quality assessment

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

## Components

### XR Lab

**Responsible Team**: XRLab (Dr. Christian Scharinger)

The central hub where all components converge. The XR Lab develops immersive visualization applications that bring digital forest twins to life, enabling users to experience and interact with forest data in unprecedented ways.

**Capabilities**:

- Real-time forest visualization and interaction
- Multi-user collaborative environments
- Educational simulation scenarios
- Research data exploration tools

### Point Cloud Processing

**Responsible Team**: Department of Sensor-Based Geoinformatics (Prof. Dr. Teja Kattenborn)

The foundation of the digital forest twin, transforming raw LiDAR and photogrammetric data into structured forest information.

**Key Features**:

- **3DTrees Online Platform**: Web-based interface for point cloud upload and processing
- **Automated Tree Segmentation**: Individual tree identification from forest point clouds
- **Species Classification**: Machine learning-based tree species identification
- **Quality Control**: Validation and accuracy assessment of processed data

**Technology Stack**: Python, R, CloudCompare, lidR, Machine Learning algorithms

### Digital Forest Twin

**Responsible Team**: Department of Forest Growth and Dendroecology (Prof. Dr. Thomas Seifert)

#### Tree Database

#### Quantitative Structure Model (QSM)

Digital representations of individual trees and forest ecosystems for growth simulation.

#### Tree/Forest Growth Models

- **SILVA**: Individual tree growth simulator
- **BALANCE**: Stand-level forest growth model

### Application Conceptualization

#### Teaching

- **Sensor Network Visualization**: Experience EcoSense sensor networks and ecosystem fluxes (e.g., Hartheim site)
- **Remote Sensing Education**: "Experience" LiDAR and other 3D data through immersive exploration
- **Forest Management Training**: Practice forestry decisions in risk-free virtual environments
- **Temporal Dynamics**: Visualize long-term forest changes in accelerated time

#### Research

- **Invisible Processes**: Visualize hidden forest processes (sap flow, root competition, nutrient flows)
- **Data Exploration**: Interactive analysis of complex forest datasets
- **Hypothesis Testing**: Test management scenarios before real-world implementation
- **Multi-scale Analysis**: Examine forests from tree level to landscape scale

#### Communication

- **Faculty Collaboration**: Platform for visualizing research from Excellence Clusters, RTGs, SFBs
- **Stakeholder Engagement**: Communicate forest research to policymakers and the public
- **Interdisciplinary Outreach**: Bridge forest science with other disciplines
- **Public Education**: Make forest science accessible to broader audiences

## Database Schema

The implementation includes three specialized databases with minimal schemas:

### Point Cloud Database

- `point_clouds`: LiDAR scan metadata and file references
- `processing_jobs`: Background processing job tracking
- `processing_status_types`: Processing workflow states

### Tree Database  

- `trees`: Individual tree records with spatial positioning
- `tree_measurements`: Biometric measurements over time
- `species`: Tree species reference data

### Environment Database

- `environment_sensors`: Sensor device inventory
- `sensor_readings`: Time-series environmental data
- `environmental_snapshots`: Aggregated environmental summaries

## Sample Data

The database is initialized with sample data including:

- Test forest plot location with PostGIS geometry
- 3 sample trees (European Beech, Sessile Oak, Norway Spruce)
- Tree measurements with quality indicators
- Environmental sensor and readings
- Complete species reference data

## Configuration

Environment variables can be set in `docker-compose.yml`:

- `DATABASE_URL`: PostgreSQL connection string
- `REDIS_URL`: Redis connection string  
- `API_HOST` / `API_PORT`: API server configuration
- `ENVIRONMENT`: Set to `development` for verbose logging

Copy `.env.example` to `.env` to customize configuration.

## Event System

The system uses Redis for real-time event communication:

- **Channels**: `tree_events`, `location_events`, `sensor_events`
- **WebSocket**: Events are forwarded to connected clients via `/ws`
- **Event Types**: `tree_created`, `tree_measurement_added`, `location_created`

## Spatial Queries

The implementation supports PostGIS spatial operations:

- Point-in-polygon queries for trees within locations
- Distance calculations between sensors and trees
- Spatial indexing for performance
- GeoJSON output for web mapping applications

## Testing

Run the included test script to verify API functionality:

```bash
python test_api.py
```

Or use the convenient setup script:

```bash
./setup.sh
```

## Troubleshooting

### Database Connection Issues

```bash
# Check if PostgreSQL is ready
docker exec -it xr_forests_db pg_isready -U forests_user

# View database logs
docker logs xr_forests_db

# Connect to database
docker exec -it xr_forests_db psql -U forests_user -d xr_forests_lab
```

### API Issues

```bash
# Check API logs
docker logs xr_forests_api

# Test database connectivity from API
curl http://localhost:8000/health
```

### Redis Connection Issues

```bash
# Test Redis connectivity
docker exec -it xr_forests_redis redis-cli ping

# View Redis logs
docker logs xr_forests_redis
```

## Next Steps

This minimal implementation provides the foundation for:

1. **Point Cloud Processing**: Add LiDAR file upload and processing workflows
2. **Simulation Models**: Integrate SILVA, BALANCE, and iLand models
3. **XR Client**: Build Unity/Unreal applications consuming the API
4. **Advanced Analytics**: Add machine learning for species classification
5. **Real-time Monitoring**: Expand sensor data ingestion capabilities

## Documentation

For detailed system architecture and design decisions, see:

### 🎯 New to the Project?

**Start Here**: [Documentation Overview](docs/documentation_overview.md) - Choose your learning path

### 📚 Core Documentation

- [Architecture Overview](docs/architecture.md) - System design and technology decisions
- [Database Design](docs/database_design.md) - Data models and schema design
- [Data Contracts & APIs](docs/data_contracts_and_apis.md) - API specifications
- [System Introduction](docs/system_introduction.md) - Technology stack explanation

### 🚀 Developer Resources

- [Developer Guide](docs/developer_guide.md) - Complete development workflow and tutorials
- [Project Structure Guide](docs/project_structure_guide.md) - Visual project overview and development workflow
- [API Reference (Visual)](docs/api_reference_visual.md) - Quick visual API endpoint reference
- [Interactive API Docs](http://localhost:8000/docs) - Live API documentation (when running)

### 📋 Quick References

- **New to the project?** Start with [Documentation Overview](docs/documentation_overview.md)
- **Need API details?** Check [API Reference (Visual)](docs/api_reference_visual.md)
- **Want to develop features?** Follow [Developer Guide](docs/developer_guide.md)
- **Curious about technology?** Read [System Introduction](docs/system_introduction.md)
