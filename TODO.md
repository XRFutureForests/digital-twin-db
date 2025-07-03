# XR Future Forests Lab - TODO

## 📋 TODO (Not Started)

### High Priority - Core Implementation

- [ ] **Generate SQL schema files from DBML**
  - Convert `docs/architecture/xr_forests_complete_erd.dbml` to PostgreSQL DDL
  - Create migration scripts for schema setup
  - Add indexes for spatial data and variant queries

- [ ] **Create FastAPI project structure**
  - Set up FastAPI application in `src/xr_forests/`
  - Implement database connection with AsyncPG + SQLAlchemy
  - Create base models and repository patterns

- [ ] **Implement core API endpoints**
  - Point Cloud API (`/api/pointclouds/`)
  - Tree API (`/api/trees/`)
  - Sensor API (`/api/sensors/`)
  - Environment API (`/api/environments/`)

- [ ] **Production deployment documentation**
  - Docker production configuration
  - SSL/TLS setup with nginx
  - Environment variables and secrets management
  - Security hardening checklist

### Medium Priority - Development Infrastructure

- [ ] **Developer setup guide**
  - Step-by-step local development setup
  - Database seeding with sample data
  - Code style and contribution guidelines
  - VS Code workspace configuration

- [ ] **Testing strategy implementation**
  - Pytest configuration for API testing
  - Database fixtures and test data
  - Integration tests for variant lineage
  - API contract testing with Pydantic models

- [ ] **CI/CD pipeline setup**
  - GitHub Actions for automated testing
  - Docker image building and registry
  - Automated deployment to staging environment
  - Code quality checks (linting, type checking)

- [ ] **User interface design**
  - Web app mockups for forest data visualization
  - Field data collection app wireframes
  - XR experience interaction patterns
  - User workflow documentation

### Low Priority - Advanced Features

- [ ] **External integrations**
  - SILVA database API integration
  - EcoSense sensor network connectivity
  - 3DTrees platform data exchange
  - Authentication flows for external systems

- [ ] **Performance optimization**
  - Point cloud processing benchmarks
  - Database query optimization
  - Horizontal scaling patterns
  - Load testing infrastructure

- [ ] **Monitoring and observability**
  - Prometheus metrics collection
  - Grafana dashboard configuration
  - Structured logging with correlation IDs
  - Health check endpoints

## 🚧 DOING (In Progress)

### Currently Working On

- [ ] **[Pick up work here after breaks]**
  - *This section will contain active tasks being worked on*
  - *Move items here when you start working on them*
  - *Include notes about current progress and next steps*

## ✅ DONE (Completed)

### Architecture & Design Phase

- [x] **Complete database schema design** (DBML format)
- [x] **Three-tier architecture documentation**
- [x] **API specifications and data contracts**
- [x] **Service architecture definition**
- [x] **Docker development environment setup**
- [x] **nginx reverse proxy configuration**
- [x] **Technology stack selection and documentation**
- [x] **Variant-based lineage tracking design**
- [x] **Spatial data patterns with PostGIS**
- [x] **Comprehensive documentation review**

---

## 🎯 Current Sprint Focus

**Goal**: Transition from architecture design to implementation phase

**Primary Objectives**:

1. Get database schema operational
2. Create basic API structure
3. Set up development workflow

**Success Criteria**:

- Database can be created from schema files
- Basic CRUD operations work for trees and point clouds
- Developer can set up environment locally
- API returns proper JSON responses for core endpoints

---

## 📝 Notes

- **Project Status**: Architecture Design Complete → Implementation Phase Starting
- **Next Review**: After completing High Priority tasks
- **Architecture Reference**: All design docs in `docs/architecture/`
- **Key Principle**: Maintain variant-based lineage tracking in all implementations
