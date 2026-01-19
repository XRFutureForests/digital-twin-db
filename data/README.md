# Data Directory

This directory contains CSV data files for the Digital Forest Twin Database.

## Directory Structure

```
data/
├── lookups/                    # 🔑 Lookup table CSVs (source of truth)
│   ├── species.csv             # Tree species definitions
│   ├── locations.csv           # Research site locations
│   ├── sensor_types.csv        # Sensor type definitions
│   ├── soil_types.csv          # USDA soil classification
│   ├── climate_zones.csv       # Köppen climate zones
│   ├── scenarios.csv           # Simulation scenarios
│   ├── variant_types.csv       # Data variant types
│   └── README.md               # How to edit lookup tables
├── templates/                  # 📋 Import templates & guides
│   ├── trees_import_template.csv
│   ├── sensors_import_template.csv
│   ├── DATA_PREPARATION_GUIDE.md
│   └── README.md
├── ecosense_250911.csv         # Raw EcoSense tree inventory
└── mathisle_250904.csv         # Mathisle tree inventory
```

---

## Lookup Tables (`lookups/`)

These CSV files are the **source of truth** for database reference data. They are loaded into the database during initialization.

### How It Works

1. Edit CSV files in `lookups/` to add/modify lookup values
2. Rebuild the database: `cd docker && ./reset.sh`
3. The new values are automatically loaded

### Files

| File | Database Table | Purpose |
|------|----------------|---------|
| `species.csv` | `shared.Species` | Tree species definitions |
| `locations.csv` | `shared.Locations` | Research site locations |
| `sensor_types.csv` | `sensor.SensorTypes` | Sensor type definitions |
| `soil_types.csv` | `shared.SoilTypes` | USDA soil classification |
| `climate_zones.csv` | `shared.ClimateZones` | Köppen climate zones |
| `scenarios.csv` | `shared.Scenarios` | Simulation scenarios |
| `variant_types.csv` | `shared.VariantTypes` | Data variant types |

See [lookups/README.md](lookups/README.md) for detailed instructions.

---

## Import Templates (`templates/`)

Template CSVs define the expected format for importing tree and sensor data.

### Workflow

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  Raw CSV Data       │────▶│  Manual Preparation │────▶│  Template CSV       │
│  (any format)       │     │  (see guide)        │     │  (standardized)     │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
                                                                  │
                                                                  ▼
                                                        ┌─────────────────────┐
                                                        │  import_trees.ipynb │
                                                        │  (validates + imports)
                                                        └─────────────────────┘
```

### Key Resources

- [DATA_PREPARATION_GUIDE.md](templates/DATA_PREPARATION_GUIDE.md) - Step-by-step preparation instructions
- [templates/README.md](templates/README.md) - Template field specifications

---

## Raw Data Files

### ecosense_250911.csv

EcoSense tree inventory from forest research plots near Freiburg.

- **1,582 trees** from 18 forest plots
- Coordinates: UTM 32N (EPSG:32632)
- Species: Beech, Douglas Fir, Silver Fir, Larch
- Measurements: Diameter (m), TLS height

**Key columns:** `species`, `x_32632`, `y_32632`, `diameter_m`, `tls_treeheight`, `plot_id`, `tree_id`

### mathisle_250904.csv

Mathisle forest plot tree inventory.

- **743 trees** (primarily European Beech)
- Coordinates: WGS84 (EPSG:4326)
- Measurements: DBH (m)

**Key columns:** `species_short`, `gps_latitude`, `gps_longitude`, `DBH`, `TreeID`

---

## Importing Data

### Quick Start

1. Prepare your CSV following [DATA_PREPARATION_GUIDE.md](templates/DATA_PREPARATION_GUIDE.md)
2. Open `scripts/import_trees_simple.ipynb`
3. Set `CSV_FILE` path and `DRY_RUN = True`
4. Run all cells to validate
5. Set `DRY_RUN = False` and run again to import

### Import Order

When importing both trees and sensors:

1. **Sensors first** → `sensors_import_template.csv` format
2. **Trees second** → `trees_import_template.csv` format
3. **Link sensors to trees** → Via ExternalID / TreeLinkID matching

---

## Data Privacy

⚠️ These demo datasets are for development/testing only.

Before committing data:

- Ensure no sensitive or personal information
- Add proprietary files to `.gitignore`
- Document expected structure without actual data

---

## See Also

- [scripts/README.md](../scripts/README.md) - Import notebook usage
- [docker/README.md](../docker/README.md) - Database setup guide
