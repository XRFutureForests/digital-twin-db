# Data Importer - Jupyter & R Markdown Notebooks

Step-by-step interactive notebooks for importing CSV data into the Digital Forest Twin database.

Available as:

- **Python**: Jupyter Notebook (`import_trees.ipynb`)
- **R**: R Markdown (`import_trees.Rmd`)

## Overview

These notebooks help you import CSV data into the database by:

1. **Connecting to the database** and retrieving all table and column definitions
2. **Loading your CSV file** and showing you the available columns
3. **Exploring reference data** (Species, Locations, SensorTypes) for mapping decisions
4. **Creating an interactive mapping** between CSV columns and database tables/columns
5. **Handling coordinates** automatically (lat/lon or x/y with CRS transformation)
6. **Previewing data** organized by table before insertion
7. **Inserting data** into the database (optional, manual step)

## Quick Start

### Setup (One-time)

```bash
cd scripts
conda env create -f environment.yml
conda activate digital-twin
```

### Python - Jupyter Notebook

```bash
# Start Jupyter
jupyter notebook

# Open import_trees.ipynb
# Run cells sequentially from top to bottom
# Modify CSV path and mapping as needed
```

### R - R Markdown

```bash
# Option 1: Open in RStudio
# File → Open → import_trees.Rmd
# Run cells sequentially or knit the document

# Option 2: Render from command line
Rscript -e "rmarkdown::render('import_trees.Rmd')"
```

## Notebook Workflow

Run the notebook cells sequentially from top to bottom. Each cell is a self-contained step.

### Step 1: Setup - Load Dependencies

Load required packages (pandas, RPostgres, psycopg2, etc.) and test database connection.

### Step 2: Introspect Database Schema

Query the database and display all available tables and columns:

```text
📦 Schema: trees
  📋 Trees (10 columns)
     1. VariantID
     2. LocationID
     3. SpeciesID
     ...
```

### Step 3: Load Reference Data

Display Species, Locations, and SensorTypes tables to understand mapping options:

```text
📚 Species:
SpeciesID  CommonName         ScientificName
    1      European Beech     Fagus sylvatica
    6      Douglas Fir        Pseudotsuga menziesii

📚 Locations:
LocationID  LocationName
    1       University Forest Plot A
    4       Ecosense_MixedPlot
```

### Step 4: Load CSV File

Load your CSV and display first few rows. Edit the `CSV_PATH` variable to change the file.

### Step 5: Coordinate Mapping Guide

Reference for handling lat/lon or x/y coordinates:

- **Option 1**: `lat_lon:EPSG:4326` - Auto-detects and combines latitude/longitude
- **Option 2**: `x_y:EPSG:32632` - Auto-detects and transforms x/y (UTM) to WGS84
- **Option 3**: `SKIP` - Handle coordinates manually

### Step 6: Define Column Mapping

Edit the `mapping` dictionary to specify where each CSV column goes:

```python
mapping = {
    "species_short": "shared.Species.CommonName",
    "gps_latitude": "lat_lon:EPSG:4326",
    "gps_longitude": "SKIP",  # Handled by lat_lon mapping
    "DBH": "trees.Trees.FieldNotes",
    "height": "trees.Trees.Height_m",
}
```

**Format:** `"csv_column": "schema.table.column"`

**Special formats:**

- `"SKIP"` - Ignore this column
- `"lat_lon:EPSG:CODE"` - Auto-detect lat/lon, create Position geometry
- `"x_y:EPSG:CODE"` - Auto-detect x/y, transform to WGS84, create Position geometry

### Step 7: Use LOOKUP to Inspect Values

Before deciding on mapping, use the LOOKUP cell to examine column values:

```python
column_to_inspect = "species_short"
# Shows unique values in that column to help decide mapping
```

This helps you understand the data encoding (e.g., is it "Beech" or "1"?) before mapping.

### Step 8: Save Mapping as JSON

The mapping is automatically saved to `CSV_filename_mapping.json` for reuse.

### Step 9: Process Coordinates

Coordinate columns are automatically processed:

- Detects lat/lon or x/y columns by flexible naming
- Transforms CRS if needed (with pyproj)
- Creates WKT POINT geometry in Position column

### Step 10: Organize Data by Table

Data is organized into separate tables based on mapping:

```text
📊 trees.Trees (741 rows, 3 columns)
   Columns: SpeciesID, Position, FieldNotes

📊 shared.Species (0 rows, 0 columns)
```

### Step 11: Preview Data

Review how data will be inserted before committing to database.

### Step 12: Insert Data (Optional)

Uncomment the insertion code to load data into the database, or use the data in another way.

## Species Mapping Guide

Your CSV might have species as text (e.g., "Beech"), but the database uses numeric IDs (1, 6).

### Option 1: Map to CommonName (Recommended)

```python
"species_short": "shared.Species.CommonName"
```

- Insert the text values as-is
- Database will resolve IDs via foreign key
- Works if CSV values match database CommonName

### Option 2: Pre-map in CSV

```python
# Edit your CSV: "Beech" → 1, "Douglas Fir" → 6
"species_column": "trees.Trees.SpeciesID"
```

- Requires editing CSV before import
- Use LOOKUP to verify values first

### Option 3: Use LOOKUP to Decide

Edit the LOOKUP cell to see sample values, then decide which option works best.

## Mapping Storage

The mapping is automatically saved as JSON:

```json
{
  "species_short": {
    "schema": "trees",
    "table": "Trees",
    "column": "SpeciesID"
  },
  "gps_latitude": {
    "schema": "trees",
    "table": "Trees",
    "column": "Position"
  }
}
```

You can edit this file and reuse it for multiple imports.

### Step 5: Data Preparation

Data is organized by table:

```text
📊 trees.Trees (741 rows, 3 columns)
   Columns: SpeciesID, Position, FieldNotes

   First 2 rows:
   [data preview]

📊 shared.Species (0 rows, 0 columns)
   [if any species data was mapped]
```

### Step 6: Insertion

Data is prepared as DataFrames/Tibbles ready for insertion:

**Python:**

```python
for table_name, df in table_dfs.items():
    importer.supabase.table(table_name).insert(df.to_dict('records')).execute()
```

**R:**

```r
for (table_name in names(table_dfs)) {
  df <- table_dfs[[table_name]]
  # Use RPostgres or httr to insert
}
```

## Column Mapping Examples

### For Mathisle Trees

Map the Mathisle CSV columns to database tables:

| CSV Column | Maps To | Format |
|---|---|---|
| `species_short` | Species lookup | `shared.Species.CommonName` |
| `gps_latitude` | Tree position | `trees.Trees.Position` |
| `gps_longitude` | Tree position | `trees.Trees.Position` |
| `DBH` | Field notes | `trees.Trees.FieldNotes` |
| `TreeID` | Field notes | `trees.Trees.FieldNotes` |

### For EcoSense Trees

| CSV Column | Maps To | Format |
|---|---|---|
| `species` | Species lookup | `shared.Species.CommonName` |
| `x_32632` | Sensor position | `sensor.Sensors.Position` |
| `y_32632` | Sensor position | `sensor.Sensors.Position` |
| `diameter_m` | Field notes | `sensor.Sensors.FieldNotes` |

## Database Prerequisites

Before running imports:

1. **Database running:**

   ```bash
   cd docker
   docker compose ps
   # All services should show "healthy"
   ```

2. **Environment variables in `docker/.env`:**

   - `POSTGRES_PASSWORD` - Database password (required)
   - `POOLER_TENANT_ID` - Supavisor tenant ID (default: `digital-forest-twin-local`)
   - `POSTGRES_PORT` - Database port (default: `5432`)

3. **Reference data exists:**

   ```bash
   # Check if species exist
   docker exec -it dftdb-db psql -U postgres -c "SELECT * FROM shared.species;"

   # Check if locations exist
   docker exec -it dftdb-db psql -U postgres -c "SELECT * FROM shared.locations;"
   ```

**Note**: The notebooks connect via Supavisor connection pooler on port 5432. The username format is `postgres.{POOLER_TENANT_ID}` (e.g., `postgres.digital-forest-twin-local`).

## Customization

### Using Saved Mappings

After creating a mapping once, you can reuse it:

**Python:**

```python
importer.load_mapping(Path("mathisle_250904_mapping.json"))
```

**R:**

```r
importer$load_mapping("mathisle_250904_mapping.json")
```

### Specifying CSV Path

The scripts default to looking for:

- `../../data/mathisle_250904.csv`

If not found, they'll prompt you to enter the path manually.

### Direct Database Connection

For production use, you may want to:

1. **Python** - Use `psycopg2` for direct PostgreSQL connection
2. **R** - Use `RPostgres` to connect directly to the database

Both are included in the conda environment.

## Troubleshooting

### POSTGRES_PASSWORD not found

Check that `docker/.env` exists in the docker directory with:

```bash
POSTGRES_PASSWORD=your_password_here
POOLER_TENANT_ID=digital-forest-twin-local
```

### CSV file not found

Either:

1. Place CSV in `data/` folder with expected name
2. Specify full path when prompted

### Column mapping validation fails

Check the schema display output to ensure:

1. Schema name is correct (trees, sensor, shared, etc.)
2. Table name is correct
3. Column name exists in that table

### Database connection fails

Verify:

1. All Docker services are healthy: `cd docker && docker compose ps`
2. `POSTGRES_PASSWORD` in `docker/.env` is correct
3. `POOLER_TENANT_ID` is set (default: `digital-forest-twin-local`)
4. Supavisor pooler is running: `docker logs dftdb-pooler`

**Common error**: "Tenant or user not found" - This means the username format is wrong. The notebooks should use `postgres.{POOLER_TENANT_ID}` format.

## Files

- `import_trees.ipynb` - Python Jupyter Notebook implementation
- `import_trees.Rmd` - R Markdown implementation
- `environment.yml` - Conda environment with all dependencies

## Next Steps

1. Create mapping for your CSV files
2. Review the data preview
3. Implement insertion logic for your use case
4. Monitor imports via database logs or Supabase Studio

## Language Choice

**Use Python if:**

- You prefer Python ecosystem
- Working with multiple data formats
- Need integrated data transformation

**Use R if:**

- Prefer R for data science workflows
- Want to use tidyverse ecosystem
- Integrating with R-based analysis

Both provide the same workflow and flexibility.
