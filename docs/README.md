# XR Future Forests Lab - Documentation

> **Current Status**: Full-featured MVP with comprehensive API implementations  
> **Live API**: <http://localhost:8000/docs> (when running)  
> **Updated**: December 2024

Welcome to the XR Future Forests Lab documentation. This guide helps you navigate our comprehensive digital forest ecosystem platform.

## 🚀 **Quick Start**

### For New Users

1. **[Setup Guide](./guides/setup.md)** - Get the system running in 5 minutes
2. **[Project Overview](./guides/project-overview.md)** - Understand what we're building
3. **[API Quick Reference](./api/overview.md)** - Start using the APIs

### For Developers

1. **[Development Guide](./guides/development.md)** - Complete development workflow
2. **[Architecture Overview](./architecture/system-architecture.md)** - System design
3. **[Contributing Guide](./guides/contributing.md)** - How to contribute

## 📁 **Documentation Structure**

```text
docs/
├── 📖 README.md                    ← You are here!
├── 📁 guides/                      ← User & developer guides
│   ├── setup.md                   ← Quick setup instructions
│   ├── project-overview.md        ← What we're building
│   ├── development.md              ← Development workflow
│   └── contributing.md             ← Contribution guidelines
├── 📁 api/                         ← API documentation
│   ├── overview.md                 ← API overview & examples
│   ├── endpoints.md                ← Complete endpoint reference
│   └── schemas.md                  ← Data models & schemas
├── 📁 architecture/                ← Technical architecture
│   ├── system-architecture.md     ← High-level system design
│   ├── database-design.md          ← Database schema & design
│   └── technology-stack.md         ← Technology explanations
└── 📁 reference/                   ← Additional references
    ├── sources.md                  ← Research sources & links
    └── deployment.md               ← Production deployment
```

## 🎯 **Current System Capabilities**

### ✅ **Implemented Features**

- **Complete REST API** with 40+ endpoints
- **Forest Location Management** - CRUD operations for forest sites
- **Tree Management** - Individual tree tracking, measurements, health assessments
- **Point Cloud Processing** - Upload, processing, segmentation, and classification
- **Environmental Data** - Sensor readings, site characteristics, environmental snapshots
- **Species Management** - Tree species database and classification
- **Bulk Operations** - CSV import, bulk tree creation
- **Quality Assessment** - Automated quality checks for point clouds
- **Real-time Events** - Redis-based event system
- **Spatial Data Support** - PostGIS integration for geographic data

### 🔄 **In Development**

- XR Client Applications
- Advanced Forest Growth Models
- Machine Learning Integration
- Real-time Data Streaming

## 🌐 **API Overview**

The system provides comprehensive REST APIs organized by domain:

| Domain | Endpoints | Status | Description |
|--------|-----------|--------|-------------|
| **Health** | `/health` | ✅ Live | System health monitoring |
| **Locations** | `/api/locations/*` | ✅ Live | Forest site management |
| **Trees** | `/api/trees/*` | ✅ Live | Individual tree operations |
| **Point Clouds** | `/api/point-clouds/*` | ✅ Live | 3D data processing |
| **Environment** | `/api/environment/*` | ✅ Live | Environmental monitoring |
| **Species** | `/api/species/*` | ✅ Live | Tree species database |
| **Sensors** | `/api/sensors/*` | ✅ Live | Sensor management |

**Live Documentation**: [http://localhost:8000/docs](http://localhost:8000/docs)

## 🏗️ **Architecture Summary**

The system follows a three-tier architecture:

- **🖥️ Presentation Tier**: FastAPI REST API with real-time WebSocket support
- **⚙️ Logic Tier**: Business logic, data processing, and event handling
- **🗄️ Data Tier**: PostgreSQL + PostGIS + Redis for comprehensive data management

**Technology Stack**: Python, FastAPI, PostgreSQL, PostGIS, Redis, Docker

## 📚 **Documentation Sections**

### 🎯 **Getting Started**

- [Setup Guide](./guides/setup.md) - Installation and first run
- [Project Overview](./guides/project-overview.md) - Vision and goals
- [API Overview](./api/overview.md) - Using the APIs

### 👨‍💻 **For Developers**

- [Development Guide](./guides/development.md) - Complete development workflow
- [Architecture Documentation](./architecture/system-architecture.md) - Technical details
- [Contributing](./guides/contributing.md) - How to contribute

### 🔧 **Technical Reference**

- [API Reference](./api/endpoints.md) - Complete endpoint documentation
- [Database Design](./architecture/database-design.md) - Schema and models
- [Technology Stack](./architecture/technology-stack.md) - Technical explanations

### 📖 **Additional Resources**

- [Research Sources](./reference/sources.md) - Academic and technical references
- [Deployment Guide](./reference/deployment.md) - Production deployment

## 🔗 **Quick Links**

- **🌐 Live API**: <http://localhost:8000/docs>
- **🗄️ Database**: `docker exec -it xr_forests_db psql -U forests_user -d xr_forests_lab`
- **📡 Redis**: `docker exec -it xr_forests_redis redis-cli`
- **📊 Test Coverage**: `open htmlcov/index.html`

## 💡 **Need Help?**

1. **First time here?** → Start with [Setup Guide](./guides/setup.md)
2. **Want to develop?** → Follow [Development Guide](./guides/development.md)
3. **Using the API?** → Check [API Overview](./api/overview.md)
4. **Understanding the system?** → Read [Architecture Overview](./architecture/system-architecture.md)

---

*This documentation reflects the current state of the XR Future Forests Lab as of December 2024. The system is actively maintained and regularly updated.*
