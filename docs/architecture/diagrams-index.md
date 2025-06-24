# Architecture Documentation Index

This document provides links to both Mermaid and Draw.io versions of all architecture diagrams in the XR Future Forests Lab project.

## Format Options

- **Mermaid**: Text-based diagrams embedded directly in markdown documentation
- **Draw.io**: XML-based diagrams that can be edited in Draw.io application or web interface

## Available Diagrams

### 1. System Architecture Overview

**Description**: High-level three-tier architecture showing clients, presentation tier, logic tier, and data tier.

- **Mermaid**: Located in [`system-architecture.md`](./system-architecture.md) (lines 13-63)
- **Draw.io**: [`drawio/system-architecture-overview.drawio`](./drawio/system-architecture-overview.drawio)

### 2. Detailed System Overview  

**Description**: Comprehensive system overview with detailed component breakdown.

- **Mermaid**: Located in [`detailed-architecture.md`](./detailed-architecture.md) (lines 9-36)
- **Draw.io**: [`drawio/detailed-system-overview.drawio`](./drawio/detailed-system-overview.drawio)

### 3. Data Tier Architecture

**Description**: Data sources, ingestion APIs, and storage systems architecture.

- **Mermaid**: Located in [`detailed-architecture.md`](./detailed-architecture.md) (lines 67-181)  
- **Draw.io**: [`drawio/data-tier-architecture.drawio`](./drawio/data-tier-architecture.drawio)

### 4. Logic Tier Architecture

**Description**: Processing pipelines, simulation models, and tree model services.

- **Mermaid**: Located in [`detailed-architecture.md`](./detailed-architecture.md) (lines 182-362)
- **Draw.io**: [`drawio/logic-tier-architecture.drawio`](./drawio/logic-tier-architecture.drawio)

### 5. Presentation Tier Architecture

**Description**: API gateway and client applications including XR, web, and mobile interfaces.

- **Mermaid**: Located in [`detailed-architecture.md`](./detailed-architecture.md) (lines 363-462)
- **Draw.io**: [`drawio/presentation-tier-architecture.drawio`](./drawio/presentation-tier-architecture.drawio)

### 6. Point Cloud Database ERD

**Description**: Entity relationship diagram for point cloud data, processing results, and metadata.

- **Mermaid**: Located in [`database-design.md`](./database-design.md) (lines 47-89 and 90-171)
- **Draw.io**: [`drawio/pointcloud-database-erd.drawio`](./drawio/pointcloud-database-erd.drawio)

### 7. Tree Database ERD  

**Description**: Tree management with scenarios, variants, and structural representations.

- **Mermaid**: Located in [`database-design.md`](./database-design.md) (lines 267-309 and 310-431)
- **Draw.io**: [`drawio/tree-database-erd.drawio`](./drawio/tree-database-erd.drawio)

### 8. Environment Database ERD

**Description**: Sensor data, environmental snapshots, and site characteristics.

- **Mermaid**: Located in [`database-design.md`](./database-design.md) (lines 486-550)  
- **Draw.io**: [`drawio/environment-database-erd.drawio`](./drawio/environment-database-erd.drawio)

## Usage Guidelines

### When to Use Mermaid

- Quick documentation updates
- Version control friendly (text-based)
- Embedded directly in markdown
- Automatic rendering in GitHub/GitLab
- Simple collaborative editing

### When to Use Draw.io

- Complex diagram editing and layout control
- Professional presentations and reports
- Team collaboration with visual diagram tools
- Export to multiple formats (PNG, PDF, SVG)
- Integration with design workflows

### Maintaining Consistency

When updating architecture:

1. **Primary Source**: Make changes to Mermaid diagrams first (in markdown files)
2. **Secondary Update**: Update corresponding Draw.io diagrams to match
3. **Version Control**: Commit both versions together
4. **Documentation**: Update any references in documentation

## Quick Access

| Diagram Type | Mermaid Source | Draw.io File |
|-------------|----------------|--------------|
| System Overview | [system-architecture.md](./system-architecture.md) | [system-architecture-overview.drawio](./drawio/system-architecture-overview.drawio) |
| Detailed Overview | [detailed-architecture.md](./detailed-architecture.md) | [detailed-system-overview.drawio](./drawio/detailed-system-overview.drawio) |
| Data Tier | [detailed-architecture.md](./detailed-architecture.md) | [data-tier-architecture.drawio](./drawio/data-tier-architecture.drawio) |
| Logic Tier | [detailed-architecture.md](./detailed-architecture.md) | [logic-tier-architecture.drawio](./drawio/logic-tier-architecture.drawio) |
| Presentation Tier | [detailed-architecture.md](./detailed-architecture.md) | [presentation-tier-architecture.drawio](./drawio/presentation-tier-architecture.drawio) |
| Point Cloud DB | [database-design.md](./database-design.md) | [pointcloud-database-erd.drawio](./drawio/pointcloud-database-erd.drawio) |
| Tree DB | [database-design.md](./database-design.md) | [tree-database-erd.drawio](./drawio/tree-database-erd.drawio) |
| Environment DB | [database-design.md](./database-design.md) | [environment-database-erd.drawio](./drawio/environment-database-erd.drawio) |

## External Tools

- **Draw.io**: <https://draw.io> (web version)
- **Mermaid Live Editor**: <https://mermaid.live> (for testing Mermaid syntax)
- **VS Code Extensions**:
  - Draw.io Integration
  - Mermaid Preview
