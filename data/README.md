# Data Directory

This directory contains sample CSV data files that serve as **templates and examples** for importing data into the Digital Forest Twin Database.

⚠️ **Important:** These CSV files are **NOT automatically loaded** into the database during initialization. You must manually import them using the CSV importer tool.

## Available Datasets

### Tree Inventory Data

#### ecosense_250908.csv

Real tree inventory data from forest plots collected via EcoSense mobile app.

**Contents:**

- 1,582 trees from 18 forest plots
- Tree species: Beech, Douglas Fir, Silver Fir, Spruce, Oak
- GPS coordinates (UTM 32632 projection)
- Diameter measurements and TLS tree heights
- QR code links to tree images

**Columns:**

- `fid` - Feature ID
- `species` - Tree species name
- `qr_code_id` - URL to tree image/data
- `diameter_m` - Diameter in meters
- `tls_treeheight` - Height from laser scanning
- `x_32632`, `y_32632` - UTM coordinates
- `plot_id`, `tree_id`, `full_id` - Identifiers
- `elevation` - Elevation in meters

#### mathisle_250904.csv

Tree inventory data from Mathisleweiher forest plot.

**Contents:**

- 743 trees (primarily European Beech)
- GPS coordinates (WGS84)
- Diameter at breast height (DBH)
- Tree IDs and QR codes

**Columns:**

- `species_short` - Species abbreviation (BE = Beech)
- `date_time` - Measurement timestamp
- `qr_code` - URL to tree data
- `gps_latitude`, `gps_longitude`, `gps_height` - GPS coordinates
- `DBH` - Diameter at breast height in meters
- `TreeID` - Unique tree identifier
- `species_label` - Full species name

### Sensor Time-Series Data (ecosense/)

Real environmental sensor data from Douglas Fir tree monitoring in EcoSense mixed plot.

#### <Sapflow.DouglasFir_Mixed_5_Total_SapFlow@Ecosense_MixedPlot.csv>

- **9,066 readings** of tree sap flow
- 15-minute intervals
- Unit: g/h (grams per hour)
- Date range: Aug 2024 - Aug 2025

#### <SoilMoisture.DouglasFir_Mixed_5_edge_E@Ecosense_MixedPlot.csv>

- **23,044 readings** of soil volumetric water content
- 15-minute intervals
- Unit: % (percentage)
- Location: Edge E sensor position

#### <SoilTemp.DouglasFir_Mixed_5_edge_E@Ecosense_MixedPlot.csv>

- **23,026 readings** of subsurface soil temperature
- 15-minute intervals
- Unit: °C (Celsius)
- Location: Edge E sensor position

#### <StemRadialVar.DouglasFir_Mixed_5_Dendrometer@Ecosense_MixedPlot.csv>

- **34,441 readings** of stem diameter variations
- 15-minute intervals
- Unit: mm (millimeters)
- Dendrometer on Douglas Fir tree

**Total: 89,577 sensor readings spanning 1 year**

## How to Import Data

Use the interactive Jupyter notebooks located in `scripts/`:

```bash
# Setup environment (one-time)
cd scripts
conda env create -f environment.yml
conda activate digital-twin

# Start Jupyter and open import_trees.ipynb
jupyter notebook

# Or use R Markdown version in RStudio
# Open import_trees.Rmd
```

### Import Workflow

The notebooks provide a step-by-step interactive workflow:

1. **Connect to database** and display available tables/columns
2. **Load your CSV** (e.g., `mathisle_250904.csv` or `ecosense_250908.csv`)
3. **Explore reference data** (species, locations, sensor types)
4. **Define column mappings** with LOOKUP support to inspect values
5. **Handle coordinates** - Specify CRS (e.g., `EPSG:4326` for WGS84, `EPSG:32632` for UTM)
6. **Preview data** organized by table before insertion
7. **Save mapping** as JSON for reuse
8. **Insert data** (optional, review first)

The notebooks will:

- Display the first 5 rows of your CSV
- Let you interactively map columns to database fields
- Handle species lookups automatically
- Transform coordinates from any CRS to WGS84
- Store both original and transformed geometries
- Track all changes with `CreatedBy` field for audit purposes

For detailed usage instructions and troubleshooting, see [`scripts/README.md`](../scripts/README.md).

## Data Privacy

**Important:** These demo datasets are provided for development and testing purposes only.

Before committing any data to the repository:

- Ensure it contains no sensitive or personal information
- Do not include proprietary research data without permission
- Add sensitive data files to `.gitignore`

For production use with sensitive data:

1. Add data files to `.gitignore`
2. Document the expected data structure without actual data
3. Share sensitive data through secure channels (not git)

---

**See Also:**

- [docker/README.md](../docker/README.md) - Database setup guide
- [README.md](../README.md) - Main project documentation
