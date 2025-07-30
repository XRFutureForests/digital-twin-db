# XR Future Forests Lab

> **University**: University of Freiburg, Department of Forest Sciences  
> **Status**: Architecture Design & Planning Phase

An ambitious research project aimed at creating **digital twins of forests** through immersive XR technologies. The project combines advanced data acquisition, spatial analysis, and growth modeling to enable unprecedented forest visualization, research, and management capabilities.

## **Project Vision**

The XR Future Forests Lab represents a groundbreaking approach to forest science, combining cutting-edge technologies to create comprehensive digital forest ecosystems. Our vision encompasses three primary domains:

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

The system runs four core services via Docker Compose:

- **PostgreSQL + PostGIS** (`postgres:5432`) - Spatial database with forest-specific schemas
- **Redis** (`redis:6379`) - Caching and event messaging for real-time updates
- **Python API** (`api:8000`) - FastAPI REST services with async processing
- **nginx** (`nginx:80`) - Reverse proxy and static file server for large LiDAR files
