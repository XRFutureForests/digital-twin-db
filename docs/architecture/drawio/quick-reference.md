# Draw.io Quick Reference - XR Future Forests Lab

## 🚀 Quick Start

1. **Open Draw.io**: Go to <https://draw.io> or use VS Code extension
2. **Load Diagram**: File → Open → Select .drawio file
3. **Edit**: Click elements to modify text, colors, or layout
4. **Save**: File → Save (or Ctrl+S)
5. **Export**: File → Export as → Choose format (PNG, PDF, SVG)

## 📁 Available Diagrams

| Diagram | File | Purpose |
|---------|------|---------|
| System Overview | `system-architecture-overview.drawio` | High-level 3-tier architecture |
| Detailed System | `detailed-system-overview.drawio` | Component breakdown |
| Data Tier | `data-tier-architecture.drawio` | Data sources and storage |
| Logic Tier | `logic-tier-architecture.drawio` | Processing and models |
| Presentation Tier | `presentation-tier-architecture.drawio` | APIs and clients |
| Point Cloud DB | `pointcloud-database-erd.drawio` | LiDAR data schema |
| Tree DB | `tree-database-erd.drawio` | Tree management schema |
| Environment DB | `environment-database-erd.drawio` | Sensor data schema |

## 🎨 Color Scheme

```css
/* Tier Colors */
Data Tier:         #d2d2d2 (background), #505050 (nodes)
Logic Tier:        #e59778 (background), #612515 (nodes)  
Presentation:      #8cdbc0 (background), #265e4d (nodes)

/* Database Colors */
Reference Tables:  #f7dcc7 (background), #ad5643 (border)
Core Tables:       #c0e8d9 (background), #5cb89c (border)
```

## ⚡ Common Tasks

### Adding New Components

1. Select similar existing component
2. Copy (Ctrl+C) and Paste (Ctrl+V)
3. Double-click to edit text
4. Drag to reposition

### Connecting Components

1. Select **Connector** tool from toolbar
2. Click first component (connection point appears)
3. Click second component
4. Double-click connector line to add labels

### Changing Colors

1. Select component(s)
2. Right panel → Style tab
3. Click **Fill** color picker
4. Choose from palette or enter hex code

### Exporting for Documentation

1. File → Export as → PNG
2. Set **Zoom**: 100%
3. Set **Border**: 10px
4. Check **Transparent Background** (optional)
5. Click **Export**

## 🔧 Pro Tips

- **Multi-select**: Hold Ctrl while clicking to select multiple items
- **Alignment**: Format menu → Align for perfect positioning  
- **Grouping**: Select multiple items → Right-click → Group
- **Layers**: View → Layers to organize complex diagrams
- **Grid Snap**: View → Grid for precise alignment

## 📝 Team Conventions

### Editing Process

1. Always work on copies for major changes
2. Save frequently (Ctrl+S)
3. Export PNG after changes for documentation
4. Update corresponding Mermaid diagrams if needed

### Naming Convention

- Use descriptive component names
- Keep relationship labels concise
- Follow database naming standards (PK, FK indicators)

### File Management

- Keep .drawio files in `docs/architecture/drawio/`
- Export images to `docs/architecture/images/` (if needed)
- Version control both .drawio files and exports

## 🆘 Troubleshooting

**Problem**: Diagram won't open

- **Solution**: Try different browser or desktop app

**Problem**: Colors look different  

- **Solution**: Check color values against reference above

**Problem**: Can't connect components

- **Solution**: Ensure connector tool is selected, look for blue connection points

**Problem**: Text is blurry in export

- **Solution**: Use 200% zoom for high-DPI exports

## 📚 Resources

- **Draw.io Help**: Help menu → Online Help
- **Keyboard Shortcuts**: Help menu → Keyboard Shortcuts  
- **Templates**: File → New → Browse templates
- **Team Documentation**: `docs/architecture/drawio/README.md`

## 🔄 Sync with Mermaid

Remember: Mermaid diagrams in markdown files are the **source of truth**

1. Make changes to Mermaid diagrams first
2. Update corresponding Draw.io diagrams  
3. Commit both versions together
4. Update documentation if needed

---

**Location**: `/docs/architecture/drawio/`  
**Contact**: See project documentation for architecture team contacts
