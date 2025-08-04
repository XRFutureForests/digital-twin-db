# Linear Workspace Guide - Digital Twin Repository

## Repository Role: Data Tier Implementation

This repository is part of the **XR Future Forests Lab multi-repository architecture** and serves as the **Data Tier implementation**. It provides the foundational database infrastructure and APIs that support the entire forest monitoring and visualization system.

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
- **Target Date**: August 15, 2025

### **Consumer Repositories (Logic Tier)**

- **🌲 The Grove Repository**: Tree Asset Generation Service - consumes Tree API
- **☁️ Potree Docker Repository**: Point Cloud Processing Service - uses Point Cloud API

## Project Structure

### Teams & Initiatives

- **Team: XR Future Forests** - VR/AR forest visualization projects
  - **Initiative: XRFF FoWiTA** - Main research initiative
- **Team: 3Dtrees** - Point cloud processing and web visualization
  - **Initiative: MVP for SilviLaser Demo** - Conference demo preparation

### Workspace-per-Project Approach

Each Linear project gets its own dedicated workspace:

- Focused development environment
- Project-specific dependencies and configurations
- Clear separation of concerns
- Easier context switching between projects

## Linear Integration via MCP

### Available MCP Functions

The workspace has Linear MCP integration enabling:

- `mcp_linear_list_my_issues` - Get my assigned issues
- `mcp_linear_list_issues` - List issues (with filters)
- `mcp_linear_list_projects` - Get project information
- `mcp_linear_list_teams` - Team details
- `mcp_linear_create_issue` - Create new issues
- `mcp_linear_update_issue` - Update existing issues
- `mcp_linear_get_issue` - Get specific issue details
- And more...

### Authentication

Linear MCP is configured and authenticated. Access tokens are managed through MCP configuration.

## Current Workspace Context

### Project: Digital Twin Ecosense

- **Team**: XR Future Forests (XRF)
- **Project ID**: `b618c5d3-5daf-45b1-82ba-8a9de81532d8`
- **Timeline**: Core delivery by August 15, 2025
- **My Role**: Data Tier implementation - database and API infrastructure

### Architecture Responsibilities

**Data Tier Implementation**:

- **PostgreSQL + PostGIS**: Spatial database with forest-specific schemas
- **FastAPI Backend**: REST API endpoints for data access
- **VM Deployment**: Production infrastructure setup
- **Database APIs**: Point Cloud, Tree, Sensor, Environment, Audit APIs
- **Integration Foundation**: Data services for Logic and Presentation tiers

### Current Status (August 2025)

### ✅ **Foundation Complete** (Milestone 1 - DONE)

- **System Architecture**: ✅ Comprehensively documented and designed
- **Database Schema**: ✅ Finalized and optimized (`xr_forests_complete_erd.dbml`)
- **Docker Infrastructure**: ✅ Functional docker-compose setup
- **Project Structure**: ✅ Complete development environment ready

### 🔧 **Current Implementation** (Milestone 2 - IN PROGRESS)

- **Database Tables**: PostgreSQL schema implementation from DBML
- **PostGIS Extensions**: Spatial data configuration
- **Sample Data**: Test forest data loading and validation
- **Local Testing**: Development environment verification
- **Migration Scripts**: Database deployment automation

### 📋 **Production Deployment** (Milestone 3 - PLANNED)

- **VM Configuration**: Production server setup and deployment
- **External Connectivity**: API access for Logic Tier repositories
- **Backup & Monitoring**: Production data protection
- **Security**: Access control and authentication
- **Documentation**: Production deployment guides

## Critical Deliverables (August 15, 2025)

### **Must-Have** 🎯

- **Production Database**: Fully operational PostgreSQL + PostGIS on VM
- **External Access**: Database connectivity for Grove and Potree Docker repositories
- **Core Schema**: All five schemas (shared, pointclouds, trees, sensor, environments) functional

### **Should-Have** 🎯

- **Basic API Endpoints**: FastAPI implementation for core data operations
- **Authentication**: API access control and user management
- **Monitoring**: Basic database health and performance monitoring

### **Could-Have** 🎯

- **Supabase Evaluation**: Alternative API implementation assessment
- **Unity Integration**: Research VR application connectivity requirements
- **Real Sensor Data**: Ecosense sensor network integration planning

## Workflow for AI Assistants

### When Starting Work in This Workspace

1. **Get Project Context**

   ```
   Use mcp_linear_get_project with project ID: b618c5d3-5daf-45b1-82ba-8a9de81532d8
   ```

2. **Check Current Issues**

   ```
   Use mcp_linear_list_my_issues to see assigned database work
   ```

3. **Understand Database Status**

   ```
   Review schema files, Docker setup, current implementation progress
   Check milestone progress and upcoming deliverables
   ```

4. **Assess Integration Needs**
   - API requirements for Grove and Potree Docker repositories
   - VM deployment dependencies
   - External connectivity requirements

### When Creating Issues

1. **Database Implementation Focus**
   - PostgreSQL schema deployment
   - PostGIS spatial data setup
   - Data loading and validation

2. **API Development Priorities**
   - Core API endpoints for data access
   - Integration points for Logic Tier repositories
   - Authentication and security

3. **Infrastructure Deployment**
   - VM server configuration
   - Production database setup
   - External access and networking

### Standard Issue Categories

1. **Database Implementation** (high priority)
   - Schema deployment from DBML
   - PostGIS configuration
   - Sample data loading
   - Migration script development

2. **API Development** (high priority)
   - FastAPI endpoint implementation
   - Database connection and ORM setup
   - API documentation and testing

3. **Infrastructure Deployment** (critical priority)
   - VM server configuration
   - Production database deployment
   - External connectivity setup
   - Backup and monitoring

4. **Integration Support** (medium priority)
   - API design for Logic Tier repositories
   - Data format specifications
   - Performance optimization

## Team Information

### Team IDs

- **XR Future Forests**: `5e3b87df-5f1a-4f70-8621-4ced0ed7bdcf`
- **3Dtrees**: `7ac53333-6ade-4845-b5f5-76ead398222d`

### My User ID

`5b1ad7e6-6e86-4f20-ba34-d2d70c93eab3`

### Project Context

**Multi-Repository Foundation**:

- This repository provides database infrastructure for entire system
- The Grove repository depends on Tree API for species and measurement data
- Potree Docker repository stores processing results via Point Cloud API
- XR Future Forests Lab repository coordinates overall architecture

## Key Commands Reference

### Essential Linear MCP Commands

```bash
# Get my work
mcp_linear_list_my_issues

# Get project details
mcp_linear_get_project "Digital Twin Ecosense"

# List XR Future Forests team issues
mcp_linear_list_issues teamId="5e3b87df-5f1a-4f70-8621-4ced0ed7bdcf"

# Create new issue for this team
mcp_linear_create_issue assigneeId="USER_ID" title="..." description="..." projectId="b618c5d3-5daf-45b1-82ba-8a9de81532d8" teamId="5e3b87df-5f1a-4f70-8621-4ced0ed7bdcf"
```

## Technical Architecture

### Database Design

**Multi-Schema PostgreSQL Database**:

- `shared`: Reference tables (Locations, Species, Processes, AuditLog)
- `pointclouds`: LiDAR scan data with processing variants
- `trees`: Tree measurements with multi-stem support
- `sensor`: Environmental monitoring hardware and time-series data
- `environments`: Environmental condition variants

### API Architecture

**Five Core APIs**:

- **Point Cloud API**: LiDAR data operations and processing workflows
- **Tree API**: Forest inventory data with variant tracking
- **Sensor API**: Environmental monitoring and time-series data
- **Environment API**: Environmental context consolidation
- **Audit API**: Field-level change tracking across all variants

### Docker Services

```yaml
services:
  postgres:     # PostgreSQL + PostGIS (port 5432)
  redis:        # Caching and events (port 6379)
  api:          # FastAPI backend (port 8000)
  nginx:        # Reverse proxy (port 80)
```

## Integration Points

### Logic Tier Repositories

**The Grove Repository**:

- **Tree API**: Species data, measurements, growth parameters
- **Spatial Data**: Tree positions and plot boundaries
- **Species Mapping**: Database species to Grove preset conversion

**Potree Docker Repository**:

- **Point Cloud API**: Store processing results as PointCloudVariants
- **Tree API**: Tree detection results from point cloud analysis
- **Spatial Coordination**: Shared coordinate systems and spatial references

### External Integrations

**VR Applications (Unity/Unreal)**:

- **Database Connectivity**: Direct API access for forest data
- **Real-time Updates**: Live data integration for immersive experiences
- **Spatial Consistency**: Coordinate system alignment

## Development Environment

### Local Setup

```bash
# Start complete development environment
docker-compose up -d

# Access services
# Database: localhost:5432 (forests_user/forests_password)
# API: localhost/api/ (proxied through nginx)
# Web Interface: localhost:80
# Redis: localhost:6379
```

### Key Files

```
docs/architecture/xr_forests_complete_erd.dbml    # Complete database schema
docker-compose.yml                                # Service orchestration
nginx/conf.d/xr_forests.conf                     # API gateway configuration
requirements.txt                                  # FastAPI dependencies
```

## Benefits of This Approach

- **Unified Data Foundation**: Single source of truth for all forest data
- **API-First Design**: Clean integration points for consumer repositories
- **Spatial Data Expertise**: PostgreSQL + PostGIS optimized for forest monitoring
- **Scalable Architecture**: Production-ready infrastructure patterns
- **Multi-Repository Support**: Designed to serve Logic and Presentation tiers

---

*Last Updated: August 4, 2025*  
*Workspace: digital-twin (Data Tier Implementation)*  
*Team: XR Future Forests | Project: Digital Twin Ecosense*
