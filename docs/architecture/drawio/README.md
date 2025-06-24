# Draw.io Architecture Diagrams

This directory contains Draw.io (.drawio) format versions of all the Mermaid diagrams from the XR Future Forests Lab architecture documentation.

## Overview

The architecture diagrams have been converted from Mermaid format to Draw.io XML format for better compatibility with teams that prefer using Draw.io for diagram editing and collaboration.

## Available Diagrams

### 1. System Architecture Diagrams

- **`system-architecture-overview.drawio`** - High-level three-tier architecture overview
- **`detailed-system-overview.drawio`** - Comprehensive system overview with detailed components

### 2. Tier-Specific Diagrams

- **`data-tier-architecture.drawio`** - Data sources, ingestion, and storage systems
- **`logic-tier-architecture.drawio`** - Processing pipelines and simulation models
- **`presentation-tier-architecture.drawio`** - API gateway and client applications

### 3. Database Entity Relationship Diagrams (ERDs)

- **`pointcloud-database-erd.drawio`** - Point cloud database schema and relationships
- **`tree-database-erd.drawio`** - Tree database schema with scenarios and variants
- **`environment-database-erd.drawio`** - Environment database for sensor data and site characteristics

## How to Use

### Opening in Draw.io

1. **Web Version**: Go to [draw.io](https://draw.io) and select "Open Existing Diagram"
2. **Desktop Version**: Download Draw.io desktop app and open the .drawio files directly
3. **VS Code**: Install the "Draw.io Integration" extension and open files in VS Code

### Editing Guidelines

- **Colors**: The diagrams use a consistent color scheme:
  - **Data Tier**: Gray tones (#d2d2d2, #505050)
  - **Logic Tier**: Orange/brown tones (#e59778, #612515)
  - **Presentation Tier**: Teal/green tones (#8cdbc0, #265e4d)
  - **Reference Tables**: Light orange (#f7dcc7, #ad5643)
  - **Core Tables**: Light teal (#c0e8d9, #5cb89c)

- **Fonts**: All diagrams use Verdana for consistency
- **Layout**: Maintain the hierarchical flow (top-to-bottom or left-to-right)

### Exporting

Draw.io supports multiple export formats:

- **PNG/JPG**: For documentation and presentations
- **SVG**: For scalable vector graphics
- **PDF**: For reports and documents
- **HTML**: For interactive web embedding

## Relationship to Mermaid Diagrams

These Draw.io diagrams are direct translations of the Mermaid diagrams found in:

- `docs/architecture/system-architecture.md`
- `docs/architecture/detailed-architecture.md`
- `docs/architecture/database-design.md`

## Maintenance

When updating the architecture:

1. **Update both formats**: Maintain consistency between Mermaid and Draw.io versions
2. **Version control**: Commit both .drawio files and exported images
3. **Documentation**: Update corresponding markdown files with new diagrams

## Color Reference

### Tier Colors

```css
Data Tier Background:      #d2d2d2
Data Tier Border:          #505050
Data Tier Nodes:           #505050

Logic Tier Background:     #e59778
Logic Tier Border:         #612515
Logic Tier Nodes:          #612515

Presentation Background:   #8cdbc0
Presentation Border:       #265e4d
Presentation Nodes:        #265e4d
```

### Database Colors

```css
Reference Tables:          #f7dcc7 (background), #ad5643 (border)
Core Tables:              #c0e8d9 (background), #5cb89c (border)
```

## File Structure

```text
docs/architecture/drawio/
├── README.md                           # This file
├── system-architecture-overview.drawio # High-level system overview
├── detailed-system-overview.drawio     # Detailed component overview
├── data-tier-architecture.drawio       # Data tier components
├── logic-tier-architecture.drawio      # Logic tier components
├── presentation-tier-architecture.drawio # Presentation tier components
├── pointcloud-database-erd.drawio      # Point cloud database ERD
├── tree-database-erd.drawio            # Tree database ERD
└── environment-database-erd.drawio     # Environment database ERD
```

## Usage Tips

- **Zoom**: Use Ctrl+Mouse wheel or the zoom controls for better visibility
- **Layers**: Some diagrams may use layers to organize components
- **Connectors**: Connection lines automatically route around objects
- **Alignment**: Use Draw.io's alignment tools to maintain clean layouts
- **Grouping**: Related components may be grouped for easier manipulation

## Contributing

When adding new diagrams:

1. Follow the established color scheme
2. Use consistent naming conventions
3. Include relationship labels where appropriate
4. Export PNG versions for documentation
5. Update this README with new diagram descriptions
