````instructions
# GitHub Copilot Instructions - Digital Twin Repository

## Repository Role: Data Tier Implementation

This repository implements the **Data Tier** of the XR Future Forests Lab multi-repository architecture. It serves as the central data infrastructure for the entire forest monitoring and visualization system, providing unified database services and APIs for the Logic and Presentation tiers.

## Multi-Repository Architecture Context

### **Planning Hub**: XR Future Forests Lab Repository
- **Role**: Central planning and coordination workspace  
- **Contains**: Architecture documentation, issue distribution, milestone tracking
- **Linear Integration**: Coordinates work across all three specialized repositories

### **This Repository**: Digital Twin (Data Tier Implementation)
- **Architecture**: Data Tier - Database infrastructure and API services
- **Linear Project**: Digital Twin Ecosense (`b618c5d3-5daf-45b1-82ba-8a9de81532d8`)
- **Team**: XR Future Forests (`5e3b87df-5f1a-4f70-8621-4ced0ed7bdcf`)
- **Focus**: PostgreSQL + PostGIS database, FastAPI endpoints, VM deployment

### **Consumer Repositories (Logic Tier)**:
- **🌲 The Grove Repository**: Tree Asset Generation Service - consumes Tree API for species/measurements
- **☁️ Potree Docker Repository**: Point Cloud Processing Service - stores results via Point Cloud API

## Project Overview
This is a research project for creating **digital twins of forests** through XR technologies, combining LiDAR point clouds, tree measurements, sensor data, and growth modeling. The system uses a three-tier architecture (Data/Logic/Presentation) with PostgreSQL + PostGIS for spatial forest data.

## Architecture Pattern
**Multi-Schema PostgreSQL Database**: Five schemas organize the unified database:
- `shared`: Reference tables (Locations, Species, Processes, AuditLog)
- `pointclouds`: LiDAR scan data with processing variants
- `trees`: Tree measurements with multi-stem support  
- `sensor`: Environmental monitoring hardware and time-series data
- `environments`: Environmental condition variants

**Key Design Principle**: **Variant-based data lineage** - All major data types use `ParentVariantID` self-references to track processing chains and modifications while maintaining audit trails.

## Critical Patterns

### Database Schema Conventions
```sql
-- Always use schema prefixes in queries
SELECT t.Height_m, s.DBH_cm 
FROM trees.Trees t 
JOIN trees.Stems s ON t.VariantID = s.TreeVariantID
JOIN shared.Locations l ON t.LocationID = l.LocationID;

-- Variant creation must reference parent lineage
INSERT INTO trees.Trees (ParentVariantID, VariantTypeID, ProcessID, ...) 
VALUES (123, 2, 15, ...);
```

### Junction Table Pattern
**Explicit Polymorphic Relationships**: Use junction tables for shared entities linking to domain variants:
```sql
-- Process parameters linked via junction tables
INSERT INTO shared.ProcessParameters_Trees (ParameterID, VariantID) 
VALUES (param_id, tree_variant_id);

-- Audit logging with explicit junction relationships
INSERT INTO shared.AuditLog_Trees (AuditID, VariantID) 
VALUES (audit_id, tree_variant_id);
```

### Spatial Data Handling
- Use PostGIS geometry types for all spatial columns (`Position`, `PlotBoundary`, `CrownBoundary`)
- Spatial queries require proper indexing: `CREATE INDEX idx_location_bounds ON shared.Locations USING GIST (PlotBoundary);`
- Store coordinates in plot-relative system, not global coordinates

### Field-Level Audit System
Every variant table supports granular change tracking through `shared.AuditLog` with explicit junction tables:
```sql
-- Single field updates trigger audit logging through junction tables
UPDATE trees.Trees SET Height_m = 25.3 WHERE VariantID = 456;
-- Automatically creates AuditLog entry + AuditLog_Trees junction link
```

## Development Workflows

### Data Tier Implementation Focus
This repository focuses on:
1. **Database Schema Implementation**: Converting DBML to PostgreSQL DDL
2. **API Development**: FastAPI endpoints for data access and manipulation  
3. **Infrastructure Deployment**: VM setup and production database deployment
4. **Integration Services**: APIs consumed by Logic Tier repositories (Grove, Potree Docker)

### Service Consumers
- **The Grove Repository**: Consumes Tree API for species data and measurement input
- **Potree Docker Repository**: Uses Point Cloud API to store processing results
- **External VR Applications**: Access forest data through standardized APIs

### Database Development
1. **Schema Changes**: Modify `docs/architecture/xr_forests_complete_erd.dbml` first
2. **Visualization**: Use [dbdiagram.io](https://dbdiagram.io/) to import DBML for ERD viewing
3. **SQL Generation**: Convert DBML to PostgreSQL DDL for implementation

### Docker Environment
```bash
# Start complete development environment
docker-compose up -d

# Access services
# Web Interface: localhost:80 (nginx reverse proxy)
# API: localhost/api/ (proxied through nginx)
# Database: localhost:5432 (forests_user/forests_password)
# Redis: localhost:6379  
```

### nginx Integration
The system uses nginx as a reverse proxy and static file server:
- **API Gateway**: Routes `/api/*` to FastAPI backend
- **Large File Handling**: Optimized for point cloud uploads (up to 2GB)
- **Static Content**: Serves field web app (`/field/`) and 3DTrees platform (`/3dtrees/`)
- **File Downloads**: Efficient serving of point cloud files with caching

### API Development
The system uses FastAPI with SQLAlchemy async patterns:
- Environment variables: `XR_FORESTS_DATABASE_URL`, `XR_FORESTS_REDIS_URL`
- API structure follows domain schemas: `/pointclouds/`, `/trees/`, `/sensors/`, `/environments/`

## Key Files & Directories

- `docs/architecture/xr_forests_complete_erd.dbml` - Complete database schema (DBML format)
- `docs/architecture/database.md` - Schema documentation with mermaid diagrams
- `docs/architecture/architecture.md` - Three-tier system architecture
- `docker-compose.yml` - PostgreSQL+PostGIS, Redis, Python API, nginx services
- `nginx/conf.d/xr_forests.conf` - nginx routing for API gateway and static content
- `requirements.txt` - FastAPI, SQLAlchemy, AsyncPG, Pydantic stack
- `src/xr_forests/` - Python API source (currently empty - in planning phase)

## Domain-Specific Patterns

### Point Cloud Processing Lineage
```sql
-- Original scan -> Processing variants -> Tree detection results
PointClouds: original (VariantTypeID=1) -> processed (ParentVariantID=original_id) -> segmented (ParentVariantID=processed_id)
```

### Multi-Stem Tree Support
Single tree record in `trees.Trees` references multiple stems in `trees.Stems` table with detailed measurements (DBH, taper, straightness).

### Cross-Schema Integration
- Trees can reference `PointCloudVariantID` for detection source
- Process parameters link to variants via junction tables (`shared.ProcessParameters_Trees`, `ProcessParameters_PointClouds`, etc.)
- Audit logs track changes through junction tables (`shared.AuditLog_Trees`, `AuditLog_PointClouds`, etc.)
- Environmental context through `ScenarioID` references

## Documentation & Resources
- Avoid using emojis in documentation
- Use clear, concise language with technical accuracy
- Maintain consistent naming conventions across schemas
- Keep the TODO list updated with current tasks and priorities

## Project Status (August 2025)
Currently in **Database Implementation Phase** - schema complete, API implementation pending. Focus on schema understanding and PostgreSQL/PostGIS spatial database patterns.

**Target Date**: August 15, 2025
- **Must-have**: Core database running on VM
- **Should-have**: Basic API endpoints functional  
- **Could-have**: Unity/Unreal Engine integration research

This repository serves as the **data foundation** for the entire XR Future Forests Lab system, providing unified data services to specialized Logic Tier repositories and external applications.
