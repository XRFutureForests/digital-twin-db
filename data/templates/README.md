# Import Templates

This directory contains CSV templates for importing data into the Digital Forest Twin database.

## Quick Start

1. **Read the preparation guide**: [DATA_PREPARATION_GUIDE.md](DATA_PREPARATION_GUIDE.md)
2. **Prepare your CSV** to match the template format below
3. **Import** using the scripts in `scripts/import/` (see [scripts/README.md](../../scripts/README.md))

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

**Required:** `LocationID`, `Latitude`, `Longitude`
**Recommended:** `SpeciesID`, `DBH_cm`, `Height_m`, `MeasurementDate`

| Column | Required | Type | Description |
|--------|----------|------|-------------|
| `LocationID` | ✓ | Integer | FK to `shared.Locations` |
| `PlotID` | | Integer | FK to `shared.Plots` (sub-plot within location) |
| `CampaignID` | | Integer | FK to `shared.Campaigns` (data collection campaign) |
| `SpeciesID` | recommended | Integer | FK to `shared.Species` (NULL = unknown) |
| `VariantTypeID` | | Integer | FK to `shared.VariantTypes` (1=original, 2=processed, 3=manual, 8=repeat_measurement) |
| `DataSourceType` | | Text | How data was collected: `lidar`, `field`, `photogrammetry`, `estimated`, `simulated` |
| `Latitude` | ✓ | Decimal | WGS84 latitude |
| `Longitude` | ✓ | Decimal | WGS84 longitude |
| `SourceCRS` | | Integer | EPSG code of original coordinate system before transformation to WGS84 (e.g., `32632` for UTM 32N) |
| `DBH_cm` | recommended | Decimal | Diameter at breast height in cm |
| `Height_m` | recommended | Decimal | Tree height in meters |
| `TreeStatusID` | | Integer | FK to `trees.TreeStatus` (1=healthy, 2=stressed, 3=declining, 4=dead, 5=harvested, 6=missing) |
| `CrownWidth_m` | | Decimal | Crown width in meters |
| `CrownBaseHeight_m` | | Decimal | Height to base of crown in meters |
| `Age_years` | | Integer | Estimated tree age in years |
| `HealthScore` | | Decimal | Health score from 0.0 to 1.0 |
| `TaperTypeID` | | Integer | FK to `trees.TaperTypes` (1=Cylinder, 2=Cone, 3=Paraboloid, 4=Neiloid) |
| `StraightnessTypeID` | | Integer | FK to `trees.StraightnessTypes` (1=Straight, 2=Slight_sweep, 3=Moderate_sweep, 4=Severe_sweep) |
| `BranchingPatternID` | | Integer | FK to `trees.BranchingPatterns` (1=Alternate, 2=Opposite, 3=Whorled, 4=Spiral, 5=Random) |
| `BarkCharacteristicID` | | Integer | FK to `trees.BarkCharacteristics` (1=Smooth, 2=Furrowed, 3=Plated, 4=Exfoliating, 5=Scaly) |
| `FieldNotes` | | Text | Free-text field notes |
| `MeasurementDate` | recommended | Date | Date of measurement (YYYY-MM-DD) |

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

**Required:** `LocationID`, `SensorTypeID`, `SensorModel`, `Latitude`, `Longitude`, `SamplingInterval_seconds`

| Column | Required | Type | Description |
|--------|----------|------|-------------|
| `LocationID` | ✓ | Integer | FK to `shared.Locations` |
| `CampaignID` | | Integer | FK to `shared.Campaigns` (data collection campaign) |
| `SensorTypeID` | ✓ | Integer | FK to `sensor.SensorTypes` |
| `SensorModel` | ✓ | Text | Manufacturer and model |
| `SerialNumber` | | Text | Device serial number |
| `Latitude` | ✓ | Decimal | WGS84 latitude |
| `Longitude` | ✓ | Decimal | WGS84 longitude |
| `SourceCRS` | | Integer | EPSG code of original coordinate system before transformation to WGS84 (e.g., `32632` for UTM 32N) |
| `InstallationHeight_m` | | Decimal | Sensor height above ground in meters |
| `SamplingInterval_seconds` | ✓ | Integer | Measurement frequency in seconds |
| `InstallationDate` | | Date | Date sensor was installed (YYYY-MM-DD) |
| `Unit` | | Text | Measurement unit (e.g., `mm`, `°C`, `%`) |
| `IsActive` | | Boolean | Whether the sensor is currently active (`true`/`false`) |
| `TreeLinkID` | | Text | ExternalID of linked tree |
| `Notes` | | Text | Free-text notes |

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

All coordinates must be in **WGS84 (EPSG:4326)**. If your data uses a different CRS, convert before import and record the original CRS in the `SourceCRS` column (as an EPSG code, e.g., `32632` for UTM 32N) for provenance tracking:

```python
from pyproj import Transformer

# UTM 32N → WGS84
transformer = Transformer.from_crs("EPSG:32632", "EPSG:4326", always_xy=True)
lon, lat = transformer.transform(x_utm, y_utm)
# Set SourceCRS = 32632 in your CSV to record the original CRS
```

See the [DATA_PREPARATION_GUIDE.md](DATA_PREPARATION_GUIDE.md) for more transformation examples.

---

## See Also

- [scripts/README.md](../../scripts/README.md) - Import notebook usage
- [data/lookups/README.md](../lookups/README.md) - Managing lookup tables
- [docs/database-schema.md](../../docs/database-schema.md) - Full database documentation
