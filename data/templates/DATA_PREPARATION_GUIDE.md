# Data Preparation Guide

This guide explains how to prepare tree and sensor inventory data for import into the Forest Digital Twin database. Rather than relying on automated data transformation, we recommend manually preparing your CSV files to match the expected template format.

## Overview

The import workflow has two steps:

1. **Prepare your CSV** (manual) → Match the template format
2. **Run the import notebook** → Validates and inserts data

This separation ensures:

- Full control over data transformations
- Clear visibility into what gets imported
- Easier debugging when issues arise
- Consistent data quality

> **Important:** Any useful data embedded in raw field notes (tree IDs, plot numbers, etc.)
> should be manually extracted and placed into the appropriate structured columns (`TreeNumber`,
> `PlotID`, etc.) in the CSV **before** import. The import script does not parse FieldNotes.

---

## Template Formats

### Trees Import Template

Your prepared CSV must have these 23 columns. The import creates one record in `trees.Trees` and one stem (StemNumber=1) in `trees.Stems` for single-stem trees.

**Required fields:**

| Column | Type | Description |
|--------|------|-------------|
| `LocationID` | Integer | Foreign key to `shared.Locations` |
| `Latitude` | Decimal | WGS84 latitude (e.g., 47.995) |
| `Longitude` | Decimal | WGS84 longitude (e.g., 7.855) |

**Recommended fields:**

| Column | Type | Description |
|--------|------|-------------|
| `PlotID` | Integer | Foreign key to `shared.Plots` (sub-plot within location) |
| `TreeNumber` | Integer | Local tree identifier within the plot/location (e.g., tree 62 in plot 4) |
| `SpeciesID` | Integer | Foreign key to `shared.Species` (NULL = unknown) |
| `DBH_cm` | Decimal | Diameter at breast height in centimeters |
| `Height_m` | Decimal | Tree height in meters |
| `MeasurementDate` | Date | Date of field measurement (YYYY-MM-DD) |

**Optional fields:**

| Column | Type | Description |
|--------|------|-------------|
| `CampaignID` | Integer | Foreign key to `shared.Campaigns` (data collection campaign) |
| `VariantTypeID` | Integer | Foreign key to `shared.VariantTypes` (1=original, 2=processed, 3=manual, 8=repeat_measurement) |
| `DataSourceType` | String | How data was collected: `lidar`, `field`, `photogrammetry`, `estimated`, `simulated` |
| `SourceCRS` | Integer | EPSG code of original coordinate system before WGS84 transformation (e.g., `32632` for UTM 32N). For data provenance tracking |
| `TreeStatusID` | Integer | Foreign key to `trees.TreeStatus` (1=healthy, 2=stressed, 3=declining, 4=dead, 5=harvested, 6=missing) |
| `CrownWidth_m` | Decimal | Crown width in meters |
| `CrownBaseHeight_m` | Decimal | Height to base of live crown in meters |
| `Age_years` | Integer | Estimated tree age in years |
| `HealthScore` | Decimal | Health assessment score (0.0 = dead, 1.0 = optimal) |
| `TaperTypeID` | Integer | Foreign key to `trees.TaperTypes` (1=Cylinder, 2=Cone, 3=Paraboloid, 4=Neiloid) |
| `StraightnessTypeID` | Integer | Foreign key to `trees.StraightnessTypes` (1=Straight, 2=Slight_sweep, 3=Moderate_sweep, 4=Severe_sweep) |
| `BranchingPatternID` | Integer | Foreign key to `trees.BranchingPatterns` (1=Alternate, 2=Opposite, 3=Whorled, 4=Spiral, 5=Random) |
| `BarkCharacteristicID` | Integer | Foreign key to `trees.BarkCharacteristics` (1=Smooth, 2=Furrowed, 3=Plated, 4=Exfoliating, 5=Scaly) |
| `FieldNotes` | String | Free-text field notes (e.g., original IDs, plot info, observations) |

**Example:**

```csv
LocationID,PlotID,TreeNumber,CampaignID,SpeciesID,VariantTypeID,DataSourceType,Latitude,Longitude,SourceCRS,DBH_cm,Height_m,TreeStatusID,CrownWidth_m,CrownBaseHeight_m,Age_years,HealthScore,TaperTypeID,StraightnessTypeID,BranchingPatternID,BarkCharacteristicID,FieldNotes,MeasurementDate
4,19,42,,1,1,field,47.88512,8.08834,,45.2,28.5,1,12.3,8.0,85,0.95,3,1,1,2,"Healthy specimen",2025-03-05
4,19,43,,6,1,field,47.88523,8.08856,32632,32.1,22.0,1,,,45,,,,,,Young tree,2025-03-05
4,19,,,,,47.88534,8.08878,,28.0,18.5,,,,,,,,,,Species unknown,
```

### Sensors Import Template

Your prepared CSV must have these 15 columns.

**Required fields:**

| Column | Type | Description |
|--------|------|-------------|
| `LocationID` | Integer | Foreign key to `shared.Locations` |
| `SensorTypeID` | Integer | Foreign key to `sensor.SensorTypes` |
| `SensorModel` | String | Model/make of sensor |
| `Latitude` | Decimal | WGS84 latitude |
| `Longitude` | Decimal | WGS84 longitude |
| `SamplingInterval_seconds` | Integer | Measurement frequency in seconds |

**Optional fields:**

| Column | Type | Description |
|--------|------|-------------|
| `CampaignID` | Integer | Foreign key to `shared.Campaigns` (data collection campaign) |
| `SerialNumber` | String | Device serial number |
| `SourceCRS` | Integer | EPSG code of original coordinate system before WGS84 transformation (e.g., `32632` for UTM 32N) |
| `InstallationHeight_m` | Decimal | Sensor height above ground in meters (e.g., 1.3 for breast height dendrometers) |
| `InstallationDate` | Date | Date the sensor was installed (YYYY-MM-DD) |
| `Unit` | String | Measurement unit (e.g., `mm`, `%`, `C`) |
| `IsActive` | Boolean | Whether the sensor is currently active (`true`/`false`) |
| `TreeLinkID` | String | Identifier to link sensor to a specific tree |
| `Notes` | String | Any additional notes |

**Example:**

```csv
LocationID,CampaignID,SensorTypeID,SensorModel,SerialNumber,Latitude,Longitude,SourceCRS,InstallationHeight_m,SamplingInterval_seconds,InstallationDate,Unit,IsActive,TreeLinkID,Notes
4,,13,EMS Dendro DR26,Beech_Mixed_5_Dendrometer,47.884878,8.088243,,1.3,900,2024-01-15,mm,true,ecosense_8_15,"Dendrometer on tree 8_15 at breast height"
4,,5,Decagon 5TM,SoilMoisture_E,47.884880,8.088245,,0.1,900,2024-01-15,%,true,ecosense_8_15,"Soil moisture sensor 10cm depth"
```

---

## Step-by-Step Preparation

### Step 1: Identify Your Source Format

Examine your raw data and note:

- What columns do you have?
- What coordinate system is used?
- How are species identified (names, codes, IDs)?
- What units are measurements in?

### Step 2: Create Column Mapping

Map your source columns to template columns:

| Your Column | → | Template Column | Notes |
|-------------|---|-----------------|-------|
| `x_32632` | → | `Longitude` | Needs coordinate transformation |
| `y_32632` | → | `Latitude` | Needs coordinate transformation |
| (source CRS) | → | `SourceCRS` | Set to `32632` if source is UTM 32N |
| `species` | → | `SpeciesID` | Needs species lookup |
| `diameter_m` | → | `DBH_cm` | Multiply by 100 |
| `height` | → | `Height_m` | Direct copy |
| `crown_width` | → | `CrownWidth_m` | Direct copy |
| `tree_id` | → | `TreeNumber` | Local tree identifier within the plot |
| `plot_id` | → | `PlotID` | Look up in shared.Plots (or create new plot) |
| `collection_method` | → | `DataSourceType` | Map to: lidar, field, photogrammetry, estimated, simulated |
| `date` | → | `MeasurementDate` | Format as YYYY-MM-DD |

### Step 3: Look Up Location ID

Find or create your location in `data/lookups/locations.csv`:

```bash
# Check existing locations
cat data/lookups/locations.csv
```

If your location doesn't exist, add it to the CSV:

```csv
My Research Site,Description of site,8.123,48.456,500,15.0,SW,Alfisol,Cfb
```

Then rebuild the database to load the new location:

```bash
cd docker && ./reset.sh
```

After rebuild, query for the LocationID:

```sql
SELECT LocationID, LocationName FROM shared.Locations;
```

### Step 4: Look Up Species IDs

Reference the species lookup table:

| SpeciesID | CommonName | ScientificName | Common Abbreviations |
|-----------|------------|----------------|---------------------|
| 1 | European Beech | Fagus sylvatica | BE, Beech |
| 2 | Pedunculate Oak | Quercus robur | EO, PO, Oak |
| 3 | Norway Spruce | Picea abies | NS, Spruce |
| 4 | Silver Fir | Abies alba | ESF, SF, Fir |
| 5 | Scots Pine | Pinus sylvestris | SP, Pine |
| 6 | Douglas Fir | Pseudotsuga menziesii | DF |
| 7 | European Larch | Larix decidua | ELA, LA, Larch |
| 8 | Norway Maple | Acer platanoides | NOM |
| 9 | Sycamore Maple | Acer pseudoplatanus | SY, Sycamore |
| 10 | Wild Cherry | Prunus avium | WCH, Cherry |
| 11 | Wild Service Tree | Sorbus torminalis | WST |
| 12 | Birch | Betula spp. | XBI, BI, Birch |

Create a mapping for your data:

```python
SPECIES_MAP = {
    'Beech': 1, 'BE': 1, 'European Beech': 1,
    'Oak': 2, 'EO': 2,
    'Spruce': 3, 'NS': 3, 'Norway Spruce': 3,
    'Douglas Fir': 6, 'DF': 6,
    'Larch': 7, 'LA': 7, 'ELA': 7,
    'other': None,  # Unknown species → NULL
    '': None,       # Empty → NULL
}
```

### Step 5: Transform Coordinates

If your coordinates are not in WGS84 (EPSG:4326), transform them.

**Common source CRS:**

- UTM 32N (EPSG:32632) - Central Europe
- UTM 33N (EPSG:32633) - Eastern Europe
- German GK Zone 3 (EPSG:31467)

**Python transformation:**

```python
from pyproj import Transformer

# UTM 32N → WGS84
transformer = Transformer.from_crs("EPSG:32632", "EPSG:4326", always_xy=True)

# Transform each point
lon, lat = transformer.transform(x_utm, y_utm)
```

**R transformation:**

```r
library(sf)

# Create point from UTM coordinates
pt <- st_sfc(st_point(c(x_utm, y_utm)), crs = 32632)

# Transform to WGS84
pt_wgs84 <- st_transform(pt, 4326)
coords <- st_coordinates(pt_wgs84)
lon <- coords[1]
lat <- coords[2]
```

**Online tools:**

- [EPSG.io Transform](https://epsg.io/transform)
- [MyGeodata Converter](https://mygeodata.cloud/converter/coordinates)

### Step 6: Convert Units

Common conversions:

| From | To | Formula |
|------|-----|---------|
| Diameter (m) | DBH (cm) | `DBH_cm = diameter_m × 100` |
| Diameter (mm) | DBH (cm) | `DBH_cm = diameter_mm / 10` |
| Height (feet) | Height (m) | `Height_m = height_ft × 0.3048` |

### Step 7: Clean the Data

Before finalizing, check for:

**Missing required fields:**

```python
# Check for missing coordinates
df[df['Latitude'].isna() | df['Longitude'].isna()]

# Check for missing LocationID
df[df['LocationID'].isna()]
```

**Invalid values:**

```python
# Coordinates should be reasonable for your region
# Central Europe: Lat 45-55, Lon 5-15
df[(df['Latitude'] < 45) | (df['Latitude'] > 55)]
df[(df['Longitude'] < 5) | (df['Longitude'] > 15)]

# DBH should be positive and reasonable (< 500 cm)
df[(df['DBH_cm'] <= 0) | (df['DBH_cm'] > 500)]

# Height should be positive and reasonable (< 80 m)
df[(df['Height_m'] <= 0) | (df['Height_m'] > 80)]
```

**Duplicate records:**

```python
# Check for trees at exactly the same position
df[df.duplicated(subset=['Latitude', 'Longitude'])]
```

**Corrupt data:**

```python
# Check for non-numeric values in numeric columns
df[pd.to_numeric(df['DBH_cm'], errors='coerce').isna() & df['DBH_cm'].notna()]
```

### Step 8: Export to Template Format

Create the final CSV with exactly the template columns (in order):

```python
import pandas as pd

# Define template column order
TREE_TEMPLATE_COLUMNS = [
    'LocationID', 'PlotID', 'TreeNumber', 'CampaignID', 'SpeciesID', 'VariantTypeID',
    'DataSourceType', 'Latitude', 'Longitude', 'SourceCRS', 'DBH_cm',
    'Height_m', 'TreeStatusID', 'CrownWidth_m', 'CrownBaseHeight_m',
    'Age_years', 'HealthScore', 'TaperTypeID', 'StraightnessTypeID',
    'BranchingPatternID', 'BarkCharacteristicID', 'FieldNotes', 'MeasurementDate'
]

# Add any missing columns as empty, then reorder
for col in TREE_TEMPLATE_COLUMNS:
    if col not in df.columns:
        df[col] = None

output = df[TREE_TEMPLATE_COLUMNS]

# Save with UTF-8 encoding
output.to_csv('my_trees_prepared.csv', index=False, encoding='utf-8')
```

---

## Example: Preparing EcoSense Data

The EcoSense CSV has these columns:

- `tree_id` - Tree identifier
- `species` - Species name (e.g., "Beech", "Douglas Fir", "BE")
- `x_32632`, `y_32632` - UTM 32N coordinates
- `diameter_m` - Stem diameter in meters
- `height` - Height in meters

**Preparation script:**

```python
import pandas as pd
from pyproj import Transformer

# Load raw data
df = pd.read_csv('ecosense_250911.csv')

# Set up coordinate transformer
transformer = Transformer.from_crs("EPSG:32632", "EPSG:4326", always_xy=True)

# Species mapping
SPECIES_MAP = {
    'Beech': 1, 'BE': 1,
    'Douglas Fir': 6, 'DF': 6,
    'Larch': 7, 'LA': 7,
}

# Transform data
result = []
for _, row in df.iterrows():
    # Skip invalid rows
    if pd.isna(row['x_32632']) or pd.isna(row['y_32632']):
        continue

    # Transform coordinates
    lon, lat = transformer.transform(row['x_32632'], row['y_32632'])

    # Map species
    species_id = SPECIES_MAP.get(row.get('species', '').strip())

    result.append({
        'LocationID': 4,  # Mathisle
        'PlotID': 19,     # Mathisle plot
        'TreeNumber': int(row.get('tree_id')) if pd.notna(row.get('tree_id')) else None,
        'CampaignID': None,
        'SpeciesID': species_id,
        'VariantTypeID': 1,  # original
        'DataSourceType': 'field',
        'Latitude': round(lat, 6),
        'Longitude': round(lon, 6),
        'SourceCRS': 32632,  # Original data was UTM 32N
        'DBH_cm': round(row['diameter_m'] * 100, 1) if pd.notna(row.get('diameter_m')) else None,
        'Height_m': row.get('height'),
        'TreeStatusID': None,
        'CrownWidth_m': None,
        'CrownBaseHeight_m': None,
        'Age_years': None,
        'HealthScore': None,
        'TaperTypeID': None,
        'StraightnessTypeID': None,
        'BranchingPatternID': None,
        'BarkCharacteristicID': None,
        'FieldNotes': f"Source CRS: EPSG:32632",
        'MeasurementDate': '2025-09-11',
    })

# Export
pd.DataFrame(result).to_csv('ecosense_prepared.csv', index=False)
print(f"Prepared {len(result)} trees for import")
```

---

## Running the Import

Once your CSV matches the template format, use the import scripts in `scripts/import/`:

```bash
# Activate environment
conda activate digital-twin

# Import trees (replace with your prepared CSV path)
python scripts/import/import_trees.py data/imports/my_trees_prepared.csv

# Import sensors
python scripts/import/import_sensors.py data/imports/my_sensors_prepared.csv
```

See [scripts/README.md](../../scripts/README.md) for detailed import script documentation.

---

## Adding New Lookup Values

If your data contains species, locations, or sensor types not in the lookup tables:

1. Edit the appropriate CSV in `data/lookups/`:
   - `species.csv` - Tree species
   - `locations.csv` - Research locations
   - `sensor_types.csv` - Sensor types
   - `soil_types.csv` - USDA soil types
   - `climate_zones.csv` - Köppen climate zones

2. Rebuild the database:

   ```bash
   cd docker && ./reset.sh
   ```

3. Query for new IDs:

   ```sql
   SELECT SpeciesID, CommonName FROM shared.Species;
   SELECT LocationID, LocationName FROM shared.Locations;

SELECT PlotID, PlotName, PlotNumber, LocationID FROM shared.Plots;

   ```

See [data/lookups/README.md](../lookups/README.md) for detailed instructions.

---

## Common Issues

### "Foreign key violation" errors

- A foreign key ID (LocationID, SpeciesID, PlotID, CampaignID, TreeStatusID, etc.) doesn't exist in the database
- Solution: Add the missing value to the appropriate lookup CSV and rebuild, or query the database for valid IDs

### Coordinates appear in wrong location

- CRS transformation error or wrong source CRS
- Solution: Verify source CRS, test with a known point

### Duplicate key errors

- ExternalID or tree position already exists
- Solution: Check for duplicates in your data, or update existing records instead

### Character encoding errors

- Non-UTF-8 characters in the CSV
- Solution: Convert file to UTF-8 encoding before import

---

## Tools and Resources

- **Coordinate Transformation**: [EPSG.io](https://epsg.io/transform)
- **CSV Validation**: [CSV Lint](https://csvlint.io/)
- **Species Lookup**: [GBIF Species Matcher](https://www.gbif.org/tools/species-lookup)
- **Scientific Names**: [The Plant List](http://www.theplantlist.org/)
