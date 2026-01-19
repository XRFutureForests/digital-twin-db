# Import Templates

This directory contains CSV templates for importing data into the Digital Forest Twin database.

## Quick Start

1. **Read the preparation guide**: [DATA_PREPARATION_GUIDE.md](DATA_PREPARATION_GUIDE.md)
2. **Prepare your CSV** to match the template format below
3. **Run the import notebook**: `scripts/import/import_trees_simple.ipynb` or `.Rmd`

## Template Files

| File | Description |
|------|-------------|
| [trees_import_template.csv](trees_import_template.csv) | Template for tree inventory data |
| [sensors_import_template.csv](sensors_import_template.csv) | Template for sensor installations |
| [DATA_PREPARATION_GUIDE.md](DATA_PREPARATION_GUIDE.md) | Step-by-step data preparation guide |

## Lookup Tables

Lookup/reference data is managed in CSV files at [../lookups/](../lookups/):

- `species.csv` - Tree species with SpeciesID values
- `locations.csv` - Research locations with LocationID values
- `sensor_types.csv` - Sensor types with SensorTypeID values

See [../lookups/README.md](../lookups/README.md) for adding new lookup values.

---

## Trees Template

**File:** `trees_import_template.csv`

| Column | Required | Type | Description |
|--------|----------|------|-------------|
| `LocationID` | ✓ | Integer | FK to `shared.Locations` |
| `SpeciesID` | | Integer | FK to `shared.Species` (NULL = unknown) |
| `Latitude` | ✓ | Decimal | WGS84 latitude |
| `Longitude` | ✓ | Decimal | WGS84 longitude |
| `DBH_cm` | | Decimal | Diameter at breast height in cm |
| `Height_m` | | Decimal | Tree height in meters |
| `CrownDiameter_m` | | Decimal | Crown diameter in meters |
| `ExternalID` | | Text | Your reference ID (for linking) |
| `Notes` | | Text | Free-text notes |

### Species Lookup

| SpeciesID | CommonName | Abbreviations |
|-----------|------------|---------------|
| 1 | European Beech | BE, Beech |
| 2 | Pedunculate Oak | EO, Oak |
| 3 | Norway Spruce | NS, Spruce |
| 4 | Silver Fir | ESF, SF |
| 5 | Scots Pine | SP, Pine |
| 6 | Douglas Fir | DF |
| 7 | European Larch | ELA, LA, Larch |
| 8 | Norway Maple | NOM |
| 9 | Sycamore Maple | SY |
| 10 | Wild Cherry | WCH |
| 11 | Wild Service Tree | WST |
| 12 | Birch | XBI, BI |

> Query current species: `SELECT SpeciesID, CommonName FROM shared.Species;`

### Location Lookup

| LocationID | LocationName |
|------------|--------------|
| 1 | University Forest Plot A |
| 2 | University Forest Plot B |
| 3 | Black Forest Test Site |
| 4 | Mathisle |
| 5 | Ecosense_MixedPlot |

> Query current locations: `SELECT LocationID, LocationName FROM shared.Locations;`

---

## Sensors Template

**File:** `sensors_import_template.csv`

| Column | Required | Type | Description |
|--------|----------|------|-------------|
| `LocationID` | ✓ | Integer | FK to `shared.Locations` |
| `SensorTypeID` | ✓ | Integer | FK to `sensor.SensorTypes` |
| `SensorModel` | ✓ | Text | Manufacturer and model |
| `Latitude` | ✓ | Decimal | WGS84 latitude |
| `Longitude` | ✓ | Decimal | WGS84 longitude |
| `SamplingInterval_seconds` | ✓ | Integer | Measurement frequency |
| `SerialNumber` | | Text | Device serial number |
| `TreeLinkID` | | Text | ExternalID of linked tree |

### Sensor Type Lookup

| SensorTypeID | SensorTypeName | Unit |
|--------------|----------------|------|
| 1 | Temperature | °C |
| 2 | Humidity | % |
| 3 | CO2 | ppm |
| 4 | Light | lux |
| 5 | Soil_Moisture | % |
| 6 | Wind_Speed | m/s |
| 7 | Wind_Direction | degrees |
| 8 | Precipitation | mm |
| 9 | Barometric_Pressure | hPa |
| 10 | Solar_Radiation | W/m² |
| 11 | Soil_Temperature | °C |
| 12 | Leaf_Wetness | units |
| 13 | Sap_Flow | g/h |

---

## Coordinate Transformation

All coordinates must be in **WGS84 (EPSG:4326)**. If your data uses a different CRS:

```python
from pyproj import Transformer

# UTM 32N → WGS84
transformer = Transformer.from_crs("EPSG:32632", "EPSG:4326", always_xy=True)
lon, lat = transformer.transform(x_utm, y_utm)
```

See the [DATA_PREPARATION_GUIDE.md](DATA_PREPARATION_GUIDE.md) for more transformation examples.

---

## See Also

- [scripts/README.md](../../scripts/README.md) - Import notebook usage
- [data/lookups/README.md](../lookups/README.md) - Managing lookup tables
- [docs/database-schema.md](../../docs/database-schema.md) - Full database documentation
