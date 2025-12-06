# CSV Importer - User Guide

Flexible, audit-aware tool for importing CSV data into the Digital Forest Twin Database with interactive column mapping.

## Installation

You have three options to run the CSV importer:

### Option 1: Docker (Recommended - No Python installation required)

```bash
cd scripts/import-data
./import-docker.sh --help
```

The first run will build a Docker image with all dependencies. This is the easiest option if you don't have Python/conda installed.

### Option 2: Conda Environment

```bash
cd scripts/import-data
conda env create -f environment.yaml
conda activate dftdb-import
```

**Requirements:**

- Docker (Option 1) OR Conda (Option 2)
- Access to `.env` file in `docker/` directory (for database credentials)
- Running Supabase stack (`docker compose up` in `docker/` directory)

## Basic Usage

### Using Docker

```bash
./import-docker.sh \
  --csv /data/PATH_TO_CSV \
  --table TABLE_NAME \
  --created-by YOUR_NAME \
  [--crs EPSG:CODE] \
  [--interactive] \
  [--dry-run]
```

### Using Python directly

```bash
python csv_importer.py \
  --csv PATH_TO_CSV \
  --table TABLE_NAME \
  --created-by YOUR_NAME \
  [--crs EPSG:CODE] \
  [--interactive] \
  [--dry-run]
```

Note: When using Docker, CSV file paths should be relative to the `data/` directory (automatically mounted as `/data` in the container).

### Required Arguments

- `--csv` - Path to CSV file to import
- `--table` - Target database table (e.g., `Trees`, `sensor.Sensors`)
- `--created-by` - Your name/identifier for audit trail (tracked in `CreatedBy` field)

### Optional Arguments

- `--crs` - Source coordinate reference system (e.g., `EPSG:32632` for UTM Zone 32N, `EPSG:4326` for WGS84)
- `--interactive` - Enable interactive column mapping (default: true)
- `--dry-run` - Validate CSV and mappings without inserting data

## Interactive Column Mapping

When you run the importer in interactive mode, it will:

1. **Preview your CSV** - Shows first 5 rows and column names
2. **Prompt for each column** - You map CSV columns to database fields

For each column, you can enter:

- **Database field name** (e.g., `Height_m`, `SpeciesID`, `SerialNumber`)
- **`lat` or `lon`** - For geometry coordinates (latitude/longitude)
- **`x` or `y`** - For geometry coordinates (projected systems like UTM)
- **`skip`** - Ignore this column

### Example Session

```
📄 CSV Preview (mathisle_250904.csv):
Total rows: 743
Columns: ['species_short', 'date_time', 'qr_code', 'gps_latitude', 'gps_longitude', 'DBH', 'TreeID']

🗺️  Column Mapping for table 'Trees'
============================================================

Column: 'species_short'
Sample values: ['BE', 'BE', 'BE']
Map to: SpeciesID

Column: 'gps_latitude'
Sample values: [47.8851, 47.8852, 47.8850]
Map to: lat

Column: 'gps_longitude'
Sample values: [8.0881, 8.0882, 8.0880]
Map to: lon

Column: 'DBH'
Sample values: [0.42, 0.38, 0.51]
Map to: skip

Column: 'TreeID'
Sample values: [1, 2, 3]
Map to: skip

📋 Column Mapping Summary:
  species_short                  → SpeciesID
  gps_latitude                   → lat
  gps_longitude                  → lon
  DBH                            → skip
  TreeID                         → skip

⚠️  Proceed with import to 'Trees'? (yes/no):
```

## Geometry Handling

The importer supports dual geometry storage:

### With CRS Specified

```bash
--crs EPSG:32632  # UTM Zone 32N
```

- **PositionOriginal**: Stores coordinates in original CRS
- **Position**: Transformed to WGS84 (EPSG:4326)

### Without CRS

```bash
# No --crs parameter
```

- **Position**: Stores coordinates as-is (assumes WGS84)
- **PositionOriginal**: NULL

### Coordinate Validation

The importer validates all coordinates:

- Latitude: -90 to 90
- Longitude: -180 to 180

Invalid coordinates will cause the import to skip that row with an error message.

## Automatic Lookups

The importer performs automatic lookups for:

### Species

Map column to `SpeciesID`:

- Searches by common name OR scientific name
- Case-insensitive fuzzy matching
- Example: "Beech", "beech", "Fagus sylvatica" all match

### Locations

Map column to `LocationID`:

- Searches by location name
- Case-insensitive partial matching

### Sensor Types

Map column to `SensorTypeID`:

- Searches by sensor type name
- Case-insensitive partial matching

## Import Examples

### Tree Inventory (WGS84 coordinates)

**Docker:**

```bash
./import-docker.sh \
  --csv /data/mathisle_250904.csv \
  --table Trees \
  --created-by "max_import_2024" \
  --crs EPSG:4326 \
  --interactive
```

**Python:**

```bash
python csv_importer.py \
  --csv ../../data/mathisle_250904.csv \
  --table Trees \
  --created-by "max_import_2024" \
  --crs EPSG:4326 \
  --interactive
```

### Tree Inventory (UTM coordinates)

**Docker:**

```bash
./import-docker.sh \
  --csv /data/ecosense/ecosense_250908.csv \
  --table Trees \
  --created-by "ecosense_import_nov2024" \
  --crs EPSG:32632 \
  --interactive
```

**Python:**

```bash
python csv_importer.py \
  --csv ../../data/ecosense/ecosense_250908.csv \
  --table Trees \
  --created-by "ecosense_import_nov2024" \
  --crs EPSG:32632 \
  --interactive
```

### Sensor Metadata

**Docker:**

```bash
./import-docker.sh \
  --csv /data/my_sensors.csv \
  --table sensor.Sensors \
  --created-by "sensor_deployment_2024" \
  --crs EPSG:4326 \
  --interactive
```

**Python:**

```bash
python csv_importer.py \
  --csv ../../data/my_sensors.csv \
  --table sensor.Sensors \
  --created-by "sensor_deployment_2024" \
  --crs EPSG:4326 \
  --interactive
```

## Dry Run Mode

Test your import without actually inserting data:

```bash
python csv_importer.py \
  --csv data.csv \
  --table Trees \
  --created-by "test" \
  --dry-run
```

This will:

- Load and preview CSV
- Perform interactive mapping
- Validate all configurations
- **NOT insert any data**

## Error Handling

The importer continues on errors and reports them at the end:

```
📊 Import Summary
============================================================
✅ Successfully inserted: 720
⏭️  Skipped: 23
❌ Errors: 23

⚠️  Error Details:
  - Row 45: Species not found: Oak
  - Row 102: Coordinates out of bounds: lat=95.2, lon=8.5
  - Row 205: Missing required field: LocationID
  ... and 20 more errors

💡 Failed rows must be cleaned up manually via Supabase Studio
============================================================
```

Failed rows are **not inserted** and must be corrected manually.

## Troubleshooting

### Connection Errors

**Problem:** `SERVICE_ROLE_KEY not found in .env file`

**Solution:** Ensure you're running from the correct directory and the `.env` file exists in `docker/`:

```bash
ls ../../docker/.env  # Should exist
```

### Import Errors

**Problem:** `Species not found: Oak`

**Solution:** Check species exist in database:

```sql
SELECT * FROM shared.Species WHERE CommonName ILIKE '%oak%';
```

Add missing species via Supabase Studio or SQL.

### Geometry Errors

**Problem:** `Coordinates out of bounds: lat=95.2`

**Solution:** Verify coordinate columns are mapped correctly:

- Ensure lat/lon aren't swapped
- Check if coordinates are in correct CRS

### Supabase Connection

**Problem:** Import hangs or times out

**Solution:**

1. Verify database is running: `docker-compose ps`
2. Check Supabase URL in `.env`: should be `http://localhost:54321`
3. Test connection: `curl http://localhost:54321/rest/v1/`

## Configuration

The importer reads credentials from `docker/.env`:

- `SUPABASE_URL` - Supabase instance URL (default: `http://localhost:54321`)
- `SERVICE_ROLE_KEY` - Service role key with full database access

## Audit Trail

All imported data is tracked with:

- **CreatedBy** - Your identifier from `--created-by`
- **CreatedAt** - Automatic timestamp

Query your imports:

```sql
SELECT * FROM trees.Trees WHERE CreatedBy = 'your_name';
```

## Advanced Usage

### Batch Imports

Import multiple files by running the script multiple times:

```bash
for file in data/*.csv; do
  python csv_importer.py \
    --csv "$file" \
    --table Trees \
    --created-by "batch_$(date +%Y%m%d)" \
    --crs EPSG:4326 \
    --interactive
done
```

### Custom Field Mappings

You can map CSV columns to any database field:

- Direct fields: `Height_m`, `Age_years`, `HealthScore`
- Foreign keys: `SpeciesID`, `LocationID`, `SensorTypeID`
- Geometry: `lat`, `lon`, `x`, `y`

See database schema documentation for available fields.

## See Also

- [Database Schema Documentation](../../docs/database-schema.md)
- [Data Directory](../../data/README.md)
- [Main Documentation](../../README.md)
