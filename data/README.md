# Data Directory

This directory contains CSV data files for the Digital Forest Twin Database.

## Directory Structure

```
data/
├── lookups/                    # Lookup table CSVs (source of truth)
│   ├── species.csv             # Tree species definitions (13 species)
│   ├── locations.csv           # Research site locations (5 locations)
│   ├── sensor_types.csv        # Sensor type definitions (14 types)
│   ├── soil_types.csv          # USDA soil classification
│   ├── climate_zones.csv       # Köppen climate zones
│   ├── scenarios.csv           # Simulation scenarios
│   ├── variant_types.csv       # Data variant types (8 types)
│   ├── tree_status.csv         # Tree health status codes
│   ├── taper_types.csv         # Stem form classifications
│   ├── straightness_types.csv  # Trunk straightness classifications
│   ├── branching_patterns.csv  # Crown structure patterns
│   ├── bark_characteristics.csv # Bark feature classifications
│   └── README.md               # How to edit lookup tables
├── templates/                  # Import templates & guides
│   ├── trees_import_template.csv    # 22-column tree import template
│   ├── sensors_import_template.csv  # 15-column sensor import template
│   ├── DATA_PREPARATION_GUIDE.md    # Step-by-step data preparation
│   └── README.md                    # Template field specifications
├── imports/                    # Prepared import files (examples)
│   ├── ecosense_trees_import.csv    # 1,502 trees from EcoSense
│   └── mathisle_trees_import.csv    # 730 trees from Mathisle
├── ecosense_250911.csv         # Raw EcoSense tree inventory
└── mathisle_250904.csv         # Raw Mathisle tree inventory
```

---

## Lookup Tables (`lookups/`)

These CSV files are the **source of truth** for database reference data. They are loaded into the database during initialization by `30-load-lookup-tables.sql`.

### How It Works

1. Edit CSV files in `lookups/` to add/modify lookup values
2. Rebuild the database: `cd docker && ./reset.sh`
3. The new values are automatically loaded

### Files

| File | Database Table | Purpose |
|------|----------------|---------|
| `species.csv` | `shared.Species` | Tree species (name, growth, IsDeciduous) |
| `locations.csv` | `shared.Locations` | Research site locations with PostGIS geometry |
| `sensor_types.csv` | `sensor.SensorTypes` | Sensor type definitions with units and ranges |
| `soil_types.csv` | `shared.SoilTypes` | USDA soil classification |
| `climate_zones.csv` | `shared.ClimateZones` | Köppen climate zones |
| `scenarios.csv` | `shared.Scenarios` | Simulation scenarios |
| `variant_types.csv` | `shared.VariantTypes` | Data variant types |
| `tree_status.csv` | `trees.TreeStatus` | Tree health/status codes |
| `taper_types.csv` | `trees.TaperTypes` | Stem form classifications |
| `straightness_types.csv` | `trees.StraightnessTypes` | Trunk straightness |
| `branching_patterns.csv` | `trees.BranchingPatterns` | Crown branching patterns |
| `bark_characteristics.csv` | `trees.BarkCharacteristics` | Bark texture types |

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
                                                        │  import script      │
                                                        │  (validates+imports)│
                                                        └─────────────────────┘
```

### Template Columns

**Trees** (22 columns): LocationID, PlotID, CampaignID, SpeciesID, VariantTypeID, DataSourceType, Latitude, Longitude, SourceCRS, DBH_cm, Height_m, TreeStatusID, CrownWidth_m, CrownBaseHeight_m, Age_years, HealthScore, TaperTypeID, StraightnessTypeID, BranchingPatternID, BarkCharacteristicID, FieldNotes, MeasurementDate

**Sensors** (15 columns): LocationID, CampaignID, SensorTypeID, SensorModel, SerialNumber, Latitude, Longitude, SourceCRS, InstallationHeight_m, SamplingInterval_seconds, InstallationDate, Unit, IsActive, TreeLinkID, Notes

### Key Resources

- [DATA_PREPARATION_GUIDE.md](templates/DATA_PREPARATION_GUIDE.md) - Step-by-step preparation instructions
- [templates/README.md](templates/README.md) - Template field specifications

---

## Prepared Import Files (`imports/`)

Example import files that follow the template format. Use these as references when preparing your own data.

### ecosense_trees_import.csv

- **1,502 trees** prepared from EcoSense raw data
- Coordinates transformed from UTM 32N (EPSG:32632) to WGS84
- SourceCRS set to 32632 for provenance
- DataSourceType: field
- Diameter converted from meters to cm

### mathisle_trees_import.csv

- **730 trees** prepared from Mathisle raw data
- Coordinates already in WGS84 (no transformation needed)
- DataSourceType: field
- DBH converted from meters to cm

---

## Raw Data Files

### ecosense_250911.csv

EcoSense tree inventory from forest research plots near Freiburg.

- **1,530 rows** from 18 forest plots
- Coordinates: UTM 32N (EPSG:32632) - requires transformation
- Species: Beech, Douglas Fir, Silver Fir, Larch, and others
- Measurements: Diameter (m), TLS height

**Key columns:** `species`, `x_32632`, `y_32632`, `diameter_m`, `tls_treeheight`, `plot_id`, `tree_id`, `sensor_tree`

### mathisle_250904.csv

Mathisle forest plot tree inventory.

- **741 rows** (primarily European Beech)
- Coordinates: WGS84 (EPSG:4326) - no transformation needed
- Measurements: DBH (m)

**Key columns:** `species_short`, `gps_latitude`, `gps_longitude`, `DBH`, `TreeID`, `species_label`

---

## Importing Data

### Quick Start

1. Prepare your CSV following [DATA_PREPARATION_GUIDE.md](templates/DATA_PREPARATION_GUIDE.md)
2. See `imports/` for examples of properly prepared import files
3. Use the import scripts to load prepared data into the database

### Import Scripts

```bash
# Import EcoSense trees directly from raw CSV
conda activate dtm-to-unreal
python scripts/import/import_ecosense.py

# Import sensor data from Aquarius API
python scripts/import/import_sensor_data.py

# Link sensors to trees
python scripts/import/link_sensors_to_trees.py
```

### Import Order

When importing both trees and sensors:

1. **Sensors first** - `sensors_import_template.csv` format
2. **Trees second** - `trees_import_template.csv` format
3. **Link sensors to trees** - Via FieldNotes tree IDs / TreeLinkID matching

---

## Data Privacy

These demo datasets are for development/testing only.

Before committing data:

- Ensure no sensitive or personal information
- Add proprietary files to `.gitignore`
- Document expected structure without actual data

---

## See Also

- [scripts/README.md](../scripts/README.md) - Import script usage
- [docker/README.md](../docker/README.md) - Database setup guide
- [docs/database-schema.md](../docs/database-schema.md) - Full database schema documentation
