# Data Preparation Guide

This guide explains how to prepare tree and sensor inventory data for import into the Digital Forest Twin database. Rather than relying on automated data transformation, we recommend manually preparing your CSV files to match the expected template format.

## Overview

The import workflow has two steps:

1. **Prepare your CSV** (manual) → Match the template format
2. **Run the import notebook** → Validates and inserts data

This separation ensures:

- Full control over data transformations
- Clear visibility into what gets imported
- Easier debugging when issues arise
- Consistent data quality

---

## Template Formats

### Trees Import Template

Your prepared CSV must have these columns:

| Column | Required | Type | Description |
|--------|----------|------|-------------|
| `LocationID` | Yes | Integer | Foreign key to `shared.Locations` |
| `SpeciesID` | No | Integer | Foreign key to `shared.Species` (NULL = unknown) |
| `Latitude` | Yes | Decimal | WGS84 latitude (e.g., 47.995) |
| `Longitude` | Yes | Decimal | WGS84 longitude (e.g., 7.855) |
| `DBH_cm` | No | Decimal | Diameter at breast height in centimeters |
| `Height_m` | No | Decimal | Tree height in meters |
| `CrownDiameter_m` | No | Decimal | Crown diameter in meters |
| `ExternalID` | No | String | Your original ID for reference |
| `Notes` | No | String | Any additional notes |

**Example:**

```csv
LocationID,SpeciesID,Latitude,Longitude,DBH_cm,Height_m,CrownDiameter_m,ExternalID,Notes
4,1,47.88512,8.08834,45.2,28.5,12.3,TREE001,Healthy specimen
4,6,47.88523,8.08856,32.1,22.0,,TREE002,Young tree
4,,47.88534,8.08878,28.0,18.5,,TREE003,Species unknown
```

### Sensors Import Template

| Column | Required | Type | Description |
|--------|----------|------|-------------|
| `LocationID` | Yes | Integer | Foreign key to `shared.Locations` |
| `SensorTypeID` | Yes | Integer | Foreign key to `sensor.SensorTypes` |
| `SensorModel` | Yes | String | Model/make of sensor |
| `SerialNumber` | No | String | Device serial number |
| `Latitude` | Yes | Decimal | WGS84 latitude |
| `Longitude` | Yes | Decimal | WGS84 longitude |
| `SamplingInterval_seconds` | Yes | Integer | Measurement frequency |
| `TreeLinkID` | No | String | ExternalID of linked tree |

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
| `species` | → | `SpeciesID` | Needs species lookup |
| `diameter_m` | → | `DBH_cm` | Multiply by 100 |
| `height` | → | `Height_m` | Direct copy |
| `tree_id` | → | `ExternalID` | Direct copy |

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
# Check for duplicate external IDs
df[df['ExternalID'].duplicated()]

# Check for trees at exactly the same position
df[df.duplicated(subset=['Latitude', 'Longitude'])]
```

**Corrupt data:**

```python
# Check for non-numeric values in numeric columns
df[pd.to_numeric(df['DBH_cm'], errors='coerce').isna() & df['DBH_cm'].notna()]
```

### Step 8: Export to Template Format

Create the final CSV with exactly the template columns:

```python
import pandas as pd

# Select and rename columns to match template
output = df[['LocationID', 'SpeciesID', 'Latitude', 'Longitude', 
             'DBH_cm', 'Height_m', 'CrownDiameter_m', 'ExternalID', 'Notes']]

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
        'SpeciesID': species_id,
        'Latitude': round(lat, 6),
        'Longitude': round(lon, 6),
        'DBH_cm': round(row['diameter_m'] * 100, 1) if pd.notna(row.get('diameter_m')) else None,
        'Height_m': row.get('height'),
        'CrownDiameter_m': None,
        'ExternalID': row.get('tree_id'),
        'Notes': None,
    })

# Export
pd.DataFrame(result).to_csv('ecosense_prepared.csv', index=False)
print(f"Prepared {len(result)} trees for import")
```

---

## Running the Import

Once your CSV matches the template format:

1. Open `scripts/import_trees_simple.ipynb` or `scripts/import_trees_simple.Rmd`
2. Set `CSV_FILE` to your prepared CSV path
3. Set `DRY_RUN = True` for testing
4. Run all cells to validate
5. If validation passes, set `DRY_RUN = False` and run again

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
   ```

See [data/lookups/README.md](../lookups/README.md) for detailed instructions.

---

## Common Issues

### "Foreign key violation" errors

- The SpeciesID or LocationID doesn't exist in the database
- Solution: Add the missing value to the lookup CSV and rebuild

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
