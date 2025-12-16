# Digital Forest Twin Database Documentation

Complete reference for the database architecture, services, and operations.

## 📚 Documentation Index

### Core Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Database structure, schemas, services, and interaction patterns
  - Schema organization (shared, pointclouds, trees, sensor, environments)
  - Service architecture and edge functions
  - Data interaction patterns and common operations

- **[deployment-guide.md](deployment-guide.md)** - Setup and deployment instructions
  - Local development environment
  - Production deployment
  - Configuration and security

- **[supabase-introduction.md](supabase-introduction.md)** - Beginner-friendly system overview
  - Core concepts and components
  - Practical examples and operations

### Reference Materials

- **[database-schema.md](database-schema.md)** - Detailed schema specifications
  - Complete table definitions
  - Field-level documentation
  - Relationships and constraints

- **[database-erd.dbml](database-erd.dbml)** - Entity Relationship Diagram (DBML format)
  - Visualize at [dbdiagram.io](https://dbdiagram.io/)
  - Import into DBeaver or other tools

- **[database-diagram.drawio](database-diagram.drawio)** - Editable visual diagram
  - Open and edit in [draw.io](https://app.diagrams.net/)
  - Update schema visualizations

- **[api-quick-reference.md](api-quick-reference.md)** - API usage and common commands
  - REST endpoint examples
  - Docker and database commands
  - Quick lookup reference

- **[troubleshooting.md](troubleshooting.md)** - Problem-solving guide
  - Common issues and solutions
  - Docker debugging
  - Database troubleshooting

## 🎯 Quick Navigation

**Getting started?**

1. Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the system
2. Follow [deployment-guide.md](deployment-guide.md) to set up locally
3. Use [api-quick-reference.md](api-quick-reference.md) for day-to-day operations

**Need technical details?**

1. Review [database-schema.md](database-schema.md) for table specifications
2. Check [database-erd.dbml](database-erd.dbml) for visual overview
3. See [ARCHITECTURE.md](ARCHITECTURE.md) for design patterns

**Troubleshooting an issue?**

1. Check [troubleshooting.md](troubleshooting.md) first
2. Review relevant section in [ARCHITECTURE.md](ARCHITECTURE.md)
3. Check service logs: `docker compose logs -f`

## 📖 Document Details

### ARCHITECTURE.md

Comprehensive guide covering:

- Database schema organization (5 custom schemas)
- All tables, their purpose, and key fields
- Design patterns (variants, audit trails, PostGIS)
- Services architecture (Docker, edge functions, REST API)
- Authentication and security
- Data interaction patterns (importing, querying)
- Common operations and configuration

### deployment-guide.md

Complete setup instructions:

- Prerequisites and dependencies
- Local development setup
- Production deployment steps
- Environment configuration
- Database migrations
- SSL/TLS configuration
- Maintenance and updates

### supabase-introduction.md

Beginner-friendly introduction:

- What is Supabase and how it works
- Core concepts (PostgREST, real-time, functions)
- System components and their roles
- Practical examples
- Basic operations

### database-schema.md

Technical database reference:

- Detailed table definitions
- Column specifications and types
- Relationships and foreign keys
- Constraints and validations
- Design principles
- Index documentation

### database-erd.dbml

Machine-readable schema:

- DBML format for standard tools
- Can be imported into dbdiagram.io
- Use for SQL generation and analysis
- Keep in sync with schema changes

### database-diagram.drawio

Visual schema diagram:

- Editable in draw.io
- Graphical representation of tables and relationships
- Update when major schema changes occur

### api-quick-reference.md

Quick lookup guide:

- REST API endpoint examples
- Docker commands
- Database queries
- Credentials and configuration
- Common patterns and solutions

### troubleshooting.md

Problem-solving resource:

- Docker issues and solutions
- Database connection problems
- API and authentication issues
- Performance troubleshooting
- Debugging techniques

## 🔄 Keeping Documentation Updated

When making changes to the database:

1. **Update SQL migrations** in `../docker/volumes/db/init/`
2. **Update [ARCHITECTURE.md](ARCHITECTURE.md)** with new tables/schemas/services
3. **Update [database-schema.md](database-schema.md)** with field specifications
4. **Update [database-erd.dbml](database-erd.dbml)** with schema relationships
5. **Update [database-diagram.drawio](database-diagram.drawio)** if major structural changes
6. **Add tips to [troubleshooting.md](troubleshooting.md)** for new common issues

## 📋 Document Format Standards

- **File naming:** Lowercase with hyphens (kebab-case)
- **Headings:** Use clear hierarchy with proper markdown levels
- **Code blocks:** Always specify language for syntax highlighting
- **Links:** Use relative paths within docs folder
- **Examples:** Include working, tested examples
- **Tables:** Use markdown tables for structured data

## 📞 Support & Resources

- **Documentation:** Full guides in this folder
- **Source code:** See `../docker/volumes/db/init/` for SQL migrations
- **Data importer:** See `../scripts/` for Python importer
- **Supabase docs:** [supabase.com/docs](https://supabase.com/docs)
- **PostGIS docs:** [postgis.net/docs](https://postgis.net/docs/)
- **Docker docs:** [docker.com/docs](https://docs.docker.com/)

---

**Last updated:** December 2025
