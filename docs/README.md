# Digital Twin Database Documentation

This folder contains all documentation for the XR Future Forests Lab digital twin database system.

## 📚 Documentation Index

### Getting Started

- **[supabase-introduction.md](supabase-introduction.md)** - Start here! Explains what Supabase is and how the system works
- **[deployment-guide.md](deployment-guide.md)** - Complete setup instructions for local development and production deployment

### Database Documentation

- **[database-schema.md](database-schema.md)** - Detailed database design documentation with schema organization and relationships
- **[database-erd.dbml](database-erd.dbml)** - Entity Relationship Diagram in DBML format (view at [dbdiagram.io](https://dbdiagram.io/))
- **[database-diagram.drawio](database-diagram.drawio)** - Editable database diagram (open with [draw.io](https://app.diagrams.net/))

### Reference Guides

- **[api-quick-reference.md](api-quick-reference.md)** - Quick reference for API endpoints, database credentials, and common operations
- **[troubleshooting.md](troubleshooting.md)** - Common problems and solutions for local development and deployment

## 🚀 Quick Links

### For First-Time Users

1. Read [supabase-introduction.md](supabase-introduction.md) to understand the system
2. Follow [deployment-guide.md](deployment-guide.md) to set up your local environment
3. Use [api-quick-reference.md](api-quick-reference.md) for day-to-day operations

### For Developers

1. Review [database-schema.md](database-schema.md) to understand data structures
2. View [database-erd.dbml](database-erd.dbml) for visual schema reference
3. Check [troubleshooting.md](troubleshooting.md) when issues arise

### For Database Designers

1. Open [database-diagram.drawio](database-diagram.drawio) in draw.io for editing
2. Export schema changes to [database-erd.dbml](database-erd.dbml)
3. Update [database-schema.md](database-schema.md) with documentation

## 📖 Document Descriptions

### supabase-introduction.md

**Purpose:** Beginner-friendly introduction to Supabase and the database system  
**Audience:** New users, researchers, students  
**Content:** Core concepts, components, examples, and practical operations

### deployment-guide.md

**Purpose:** Complete deployment and configuration instructions  
**Audience:** System administrators, DevOps engineers  
**Content:** Prerequisites, local setup, production deployment, environment configuration, migrations, and maintenance

### database-schema.md

**Purpose:** Technical database design documentation  
**Audience:** Database designers, backend developers  
**Content:** Schema organization, table relationships, design principles, field-level specifications

### database-erd.dbml

**Purpose:** Machine-readable entity relationship diagram  
**Audience:** Developers, database tools  
**Content:** Complete schema definition in DBML format (can be imported into dbdiagram.io, DBeaver, etc.)

### database-diagram.drawio

**Purpose:** Editable visual database diagram  
**Audience:** Database designers, documentation maintainers  
**Content:** Graphical schema representation (editable in draw.io)

### api-quick-reference.md

**Purpose:** Quick lookup for common tasks and configurations  
**Audience:** All users  
**Content:** Access URLs, API keys, credentials, code examples, Docker commands

### troubleshooting.md

**Purpose:** Problem-solving guide for common issues  
**Audience:** All users  
**Content:** Step-by-step solutions for Docker, database, API, and networking problems

## 🔧 Maintenance

### Updating Documentation

When making changes to the database:

1. Update SQL migrations in `../docker/volumes/db/init/`
2. Update [database-schema.md](database-schema.md) with new tables/columns
3. Update [database-erd.dbml](database-erd.dbml) with schema changes
4. Update [database-diagram.drawio](database-diagram.drawio) if major structural changes
5. Add any new troubleshooting tips to [troubleshooting.md](troubleshooting.md)

### Documentation Standards

- **File naming:** Use lowercase with hyphens (kebab-case): `my-document.md`
- **Headings:** Use sentence case: "Getting started" not "Getting Started"
- **Code blocks:** Always specify language for syntax highlighting
- **Links:** Use relative links within docs folder
- **Examples:** Include working examples with actual values (sanitized credentials)

## 🤝 Contributing

When adding new documentation:

1. Use descriptive filenames that indicate content
2. Add entry to this README in appropriate section
3. Cross-reference related documents
4. Include practical examples
5. Test all commands and code samples

## 📞 Support

For questions or issues:

- Check [troubleshooting.md](troubleshooting.md) first
- Review [Supabase documentation](https://supabase.com/docs)
- Contact: University of Freiburg, Department of Forest Sciences

---

Last updated: November 2025
