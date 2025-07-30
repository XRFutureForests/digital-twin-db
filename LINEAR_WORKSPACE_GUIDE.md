# LINEAR_WORKSPACE_GUIDE.md

## Project Context

**Project**: Digital Twin Ecosense  
**Linear Project ID**: `b618c5d3-5daf-45b1-82ba-8a9de81532d8`  
**Team**: XR Future Forests (`5e3b87df-5f1a-4f70-8621-4ced0ed7bdcf`)  
**Initiative**: XRFF FoWiTA  
**Project Lead**: Maximilian Sperlich (`5b1ad7e6-6e86-4f20-ba34-d2d70c93eab3`)  
**Target Date**: August 15, 2025

## Project Overview

Setting up the digital twin Ecosense database and API infrastructure to support VR forest visualization. This workspace focuses on the backend data layer that will feed into Paul Lakos's Unity VR visualization work.

## Current Status (July 30, 2025)

- **System Architecture**: ✅ Comprehensively documented and designed (XRF-27 ✅)
- **Database Schema**: ✅ Finalized and optimized (XRF-29 ✅)
- **Docker Infrastructure**: ✅ Functional docker-compose setup (XRF-28 ✅)
- **Database Implementation**: 🔄 Next priority (XRF-30)
- **VM Deployment**: 🔄 Must-have for deadline (XRF-31)
- **API Endpoints**: 🔄 Should-have (XRF-32 - FastAPI vs Supabase)
- **VR Integration**: 🔄 Could-have (XRF-33)
- **Data Integration**: 🔄 Low priority (XRF-34)

## Key Deliverables for August 15th Deadline

1. **Must-have**: Core database running on VM
2. **Should-have**: Basic API endpoints functional
3. **Could-have**: Unity/Unreal Engine integration research
4. **Alternative**: Supabase evaluation as API replacement

## Technical Stack

- **Database**: PostgreSQL with PostGIS extensions
- **API**: FastAPI (Python)
- **Infrastructure**: Docker + docker-compose
- **Deployment**: VM server (configuration TBD)
- **Alternative**: Supabase for managed database + access control

## Team Coordination

- **Weekly sync meetings**: XRLab team and 3DTrees team
- **VR Integration partner**: Paul Lakos (Unity development)
- **Data sources**: Ecosense sensor network

## Workspace Structure

```
/docs/architecture/    # System architecture documentation
/docs/reference/       # Reference materials and sources
docker-compose.yml     # Infrastructure setup
Dockerfile            # Container configuration
requirements.txt      # Python dependencies
data/                 # Sample data and assets
db/                   # Database scripts and migrations
```

## Project Milestones

### 🎯 **Milestone 1: Foundation Complete** ✅ *COMPLETED - July 30, 2025*

**Status**: ✅ **DONE**  
**Description**: Core project foundation and planning completed  
**Deliverables**:

- ✅ System architecture documented (XRF-27)
- ✅ Database schema finalized (XRF-29)
- ✅ Docker infrastructure functional (XRF-28)
- ✅ Project structure and Linear issues defined

### 🎯 **Milestone 2: Local Database Implementation**

**Target**: August 5, 2025 (6 days)  
**Status**: 🔄 **IN PROGRESS**  
**Description**: Functional database running locally with test data  
**Deliverables**:

- [ ] Database tables implemented (XRF-30)
- [ ] PostGIS extensions configured
- [ ] Sample forest data loaded
- [ ] Local testing and validation complete
- [ ] Database migration scripts ready

### 🎯 **Milestone 3: Production Deployment**

**Target**: August 12, 2025 (13 days)  
**Status**: 🔄 **PLANNED**  
**Description**: Database deployed and accessible on VM server  
**Deliverables**:

- [ ] VM server configuration completed (XRF-31)
- [ ] Production database deployed
- [ ] External connectivity verified
- [ ] Backup and monitoring configured
- [ ] Production documentation complete

### 🎯 **Milestone 4: Project Deadline** 🚀

**Target**: August 15, 2025 (16 days)  
**Status**: 🎯 **TARGET**  
**Description**: Core digital twin infrastructure ready for VR integration  
**Must-Have Deliverables**:

- [ ] Production database fully operational
- [ ] External access confirmed for Unity integration
- [ ] Documentation complete for handoff to Paul Lakos

**Optional Deliverables** (if time permits):

- [ ] API endpoints implemented OR Supabase evaluated (XRF-32)
- [ ] Unity integration research completed (XRF-33)

### 🎯 **Future Milestones** (Post-August 15)

**Milestone 5: Full Integration** (August 30, 2025)

- [ ] VR integration with Paul's Unity work
- [ ] Real Ecosense sensor data integration (XRF-34)
- [ ] Performance optimization and monitoring

## Critical Path & Risk Assessment

**🔥 Critical Path**: Foundation ✅ → Local DB → VM Deployment → Deadline  
**⚠️ Key Risks**:

- VM server configuration unknown (could delay Milestone 3)
- Integration complexity with Unity (affects post-deadline work)
- Real sensor data access dependencies

**🛡️ Mitigation Strategies**:

- Early VM investigation (Week 1 of August)
- Supabase as backup for API complexity
- Close coordination with Paul for VR requirements

## Dependencies & Blockers

- VM server configuration details (Docker, ports, access)
- Supabase evaluation for API alternative
- Unity/Unreal Engine database integration requirements
- Real Ecosense data access and format specification

---
*This guide is updated as the project progresses*
