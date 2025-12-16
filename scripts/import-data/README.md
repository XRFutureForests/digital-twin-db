# Data Importer Scripts

Interactive database schema introspection and CSV column mapping tools. Available in Python and R.

## Overview

These scripts help you import CSV data into the database by:

1. **Connecting to the database** and retrieving all table and column definitions
2. **Loading your CSV file** and showing you the available columns
3. **Creating an interactive mapping** between CSV columns and database tables/columns
4. **Generating a mapping file** that you can reuse or edit
5. **Preparing data as DataFrames/Tibbles** ready for insertion

## Quick Start

### Setup (One-time)

```bash
cd scripts/import-data
conda env create -f environment.yml
conda activate digital-twin
```

### Python

```bash
# Run the importer
python import_trees.py

# Follow the interactive prompts:
# 1. Database schema will be displayed
# 2. CSV file will be loaded (defaults to mathisle_250904.csv)
# 3. You'll map each column interactively: schema.table.column
# 4. Mapping is saved as JSON
# 5. Data preview shown before insertion
```

### R

```bash
# Run the importer
Rscript import_trees.R

# Follow the interactive prompts (same workflow as Python)
```

## Workflow

### Step 1: Database Introspection

The script connects to the database and displays:

```text
📦 Schema: trees
  📋 Trees (10 columns)
     1. VariantID
     2. LocationID
     3. SpeciesID
     ...
```

All available schemas, tables, and columns are listed for reference.

### Step 2: CSV Loading

Your CSV file is loaded and previewed:

```text
📄 CSV File: mathisle_250904.csv
   Rows: 741
   Columns: species_short, gps_latitude, gps_longitude, ...

First 3 rows:
[data preview]
```

### Step 3: Reference Data & Species Mapping

The script displays reference tables to help with mapping:

```text
📚 REFERENCE DATA - Use these for mapping CSV values to database IDs

📚 Species:
SpeciesID  CommonName         ScientificName
    1      European Beech     Fagus sylvatica
    6      Douglas Fir        Pseudotsuga menziesii
    ...

📚 Locations:
LocationID  LocationName
    4       Ecosense_MixedPlot
    1       University Forest Plot A
    ...
```

**How to handle species mapping:**

Your CSV might have species as names (e.g., "Beech", "Douglas Fir"), but the database uses numeric IDs (1, 6, etc.).

### Option 1: Map directly to CommonName (recommended)

- `csv_species_column` → `shared.Species.CommonName`
- The actual CSV values ("Beech", "Douglas Fir") will be inserted as species names
- Database will match them to IDs via foreign key

### Option 2: Pre-map species in CSV

- Create a lookup: "Beech" → 1, "Douglas Fir" → 6
- Edit your CSV before importing OR
- Edit the mapping JSON to transform values
- Then map to `SpeciesID` column directly

### Option 3: Use LOOKUP during mapping

- Type `LOOKUP` when prompted for a column
- See sample CSV values to understand encoding
- Then decide on mapping strategy

### Step 4: Interactive Mapping

For each CSV column, you specify where it goes in the database:

```text
'species_short' maps to: shared.Species.CommonName
✓ Mapped to shared.Species.CommonName

'gps_latitude' maps to: trees.Trees.Position
✓ Mapped to trees.Trees.Position

...
```

**Format:** `schema.table.column`

**Special values:**

- `SKIP` - Ignore this column
- `LOOKUP` - See sample values from CSV to help decide mapping

### Step 4: Mapping Storage

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
   ```

2. **Environment variables in `docker/.env`:**

   - `SUPABASE_URL` - Database URL (default: `http://localhost:8000`)
   - `SERVICE_ROLE_KEY` - Admin API key (required)

3. **Reference data exists:**

   ```bash
   # Check if species exist
   docker exec -it dftdb-db psql -U postgres -c "SELECT * FROM shared.species;"

   # Check if locations exist
   docker exec -it dftdb-db psql -U postgres -c "SELECT * FROM shared.locations;"
   ```

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

### SERVICE_ROLE_KEY not found

Check that `docker/.env` exists in the docker directory with:

```bash
SERVICE_ROLE_KEY=your_key_here
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

1. Supabase services running: `docker compose -C docker ps`
2. `SUPABASE_URL` in `docker/.env` is correct
3. `SERVICE_ROLE_KEY` is valid

## Files

- `import_trees.py` - Python implementation
- `import_trees.R` - R implementation
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
