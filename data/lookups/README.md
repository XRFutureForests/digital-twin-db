# Lookup Tables

This directory contains CSV files for all database lookup/reference tables. These files are the **source of truth** for lookup data and are loaded into the database during initialization.

## How It Works

### Option 1: Full Rebuild (for new databases)

1. **Edit CSVs here** to add/modify lookup data
2. **Rebuild the database** to apply changes:

   ```bash
   cd docker
   ./reset.sh
   ```

3. The init script `30-load-lookup-tables.sql` loads all CSVs into their respective tables

### Option 2: Refresh Without Rebuild (for running databases)

Update lookup data without losing user data (trees, sensors, readings):

```bash
cd docker

# Refresh all lookup tables
./refresh-lookups.sh

# Refresh specific table
./refresh-lookups.sh species
./refresh-lookups.sh locations

# List available tables
./refresh-lookups.sh --list
```

Or via SQL (in Supabase Studio or psql):

```sql
-- Refresh all lookups
SELECT * FROM shared.refresh_all_lookups();

-- Refresh specific table
SELECT * FROM shared.refresh_lookup('species');
SELECT * FROM shared.refresh_lookup('locations');
SELECT * FROM shared.refresh_lookup('sensor_types');
```

## Files

### Shared Schema (Reference Data)

| File | Target Table | Description |
|------|--------------|-------------|
| `species.csv` | `shared.Species` | Tree species with growth characteristics |
| `soil_types.csv` | `shared.SoilTypes` | USDA soil classification |
| `climate_zones.csv` | `shared.ClimateZones` | Köppen climate zones |
| `variant_types.csv` | `shared.VariantTypes` | Data variant classifications |
| `scenarios.csv` | `shared.Scenarios` | Simulation scenarios |
| `locations.csv` | `shared.Locations` | Research plot locations |

### Sensor Schema

| File | Target Table | Description |
|------|--------------|-------------|
| `sensor_types.csv` | `sensor.SensorTypes` | Environmental sensor types |

### Trees Schema

| File | Target Table | Description |
|------|--------------|-------------|
| `tree_status.csv` | `trees.TreeStatus` | Tree health/status classification |
| `taper_types.csv` | `trees.TaperTypes` | Stem taper form classifications |
| `straightness_types.csv` | `trees.StraightnessTypes` | Stem straightness classifications |
| `branching_patterns.csv` | `trees.BranchingPatterns` | Crown branching patterns |
| `bark_characteristics.csv` | `trees.BarkCharacteristics` | Bark surface characteristics |

### Tree Morphology (from tree_anatomy.pdf by Dr. Kim D. Coder, UGA)

| File | Target Table | Description |
|------|--------------|-------------|
| `phanerophyte_height_classes.csv` | `trees.PhanerophyteHeightClasses` | Tree height classification (mega/meso/micro) |
| `crown_architectures.csv` | `trees.CrownArchitectures` | Crown architecture (excurrent, decurrent, etc.) |
| `branch_elongation_habits.csv` | `trees.BranchElongationHabits` | Branch elongation patterns (acrotony, etc.) |
| `growth_orientations.csv` | `trees.GrowthOrientations` | Shoot growth orientation (orthotropic/plagiotrophic) |
| `shoot_elongation_types.csv` | `trees.ShootElongationTypes` | Shoot elongation (long/short/spur) |
| `crown_shapes.csv` | `trees.CrownShapes` | Visual crown shape descriptions |
| `geometric_crown_solids.csv` | `trees.GeometricCrownSolids` | Geometric crown models with area/volume/drag |
| `axis_structures.csv` | `trees.AxisStructures` | Main axis structure (single leader/polycormic) |
| `growth_forms.csv` | `trees.GrowthForms` | General growth form classifications |

## Adding New Species

Edit `species.csv` and add a new row:

```csv
Common Oak,Quercus petraea,35,180,500,slow,moderate
```

**Required fields:**

- `CommonName` - Common name (e.g., "European Beech")
- `ScientificName` - Scientific name (must be unique)

**Optional fields:**

- `MaxHeight_m` - Maximum typical height in meters
- `MaxDBH_cm` - Maximum diameter at breast height in cm
- `TypicalLifespan_years` - Expected lifespan
- `GrowthRate` - One of: `very_slow`, `slow`, `moderate`, `fast`, `very_fast`
- `ShadeTolerance` - One of: `very_low`, `low`, `moderate`, `high`, `very_high`

## Adding New Locations

Edit `locations.csv` and add a new row:

```csv
My Research Site,Description of the site,8.123,48.456,500,15.0,SW,Alfisol,Cfb
```

**Required fields:**

- `LocationName` - Unique name for the location
- `Description` - Brief description

**Optional fields:**

- `CenterLongitude`, `CenterLatitude` - WGS84 coordinates
- `Elevation_m` - Elevation in meters
- `Slope_deg` - Slope in degrees (0-90)
- `Aspect` - Compass direction: `N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW`
- `SoilTypeName` - Must match a name in `soil_types.csv`
- `ClimateZoneName` - Must match a name in `climate_zones.csv`

## Adding New Sensor Types

Edit `sensor_types.csv` and add a new row:

```csv
Dendrometer,Stem diameter change sensor,mm,-5,5
```

## Species Code Reference

For CSV imports, use these mappings to find SpeciesID:

| Code | Common Name | SpeciesID |
|------|-------------|-----------|
| BE | European Beech | 1 |
| EO, PO | Pedunculate Oak | 2 |
| NS | Norway Spruce | 3 |
| ESF, SF | Silver Fir | 4 |
| SP | Scots Pine | 5 |
| DF | Douglas Fir | 6 |
| ELA, LA | European Larch | 7 |
| NOM | Norway Maple | 8 |
| SY | Sycamore Maple | 9 |
| WCH | Wild Cherry | 10 |
| WST | Wild Service Tree | 11 |
| XBI, BI | Birch | 12 |

> **Note:** SpeciesID values are assigned in the order species appear in the CSV file.

## Validation

Before rebuilding the database, you can validate your CSV files:

```bash
# Check for duplicate species
awk -F',' 'NR>1 {print $2}' species.csv | sort | uniq -d

# Check for duplicate locations
awk -F',' 'NR>1 {print $1}' locations.csv | sort | uniq -d

# Verify foreign key references in locations.csv
awk -F',' 'NR>1 && $8!="" {print $8}' locations.csv | sort -u | while read soil; do
  grep -q "^$soil," soil_types.csv || echo "Unknown soil type: $soil"
done
```
