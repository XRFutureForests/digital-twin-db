# Scripts

All runtime scripts for the Digital Forest Twin project. **Python is the standard language** for all scripts.

## Directory Structure

```
scripts/
├── README.md
├── admin/                    # Administrative scripts
│   ├── refresh_lookups.py          # Refresh lookup tables from CSV
│   ├── reset_database.py           # Full database reset
│   └── validate_species_gbif.py    # Validate species names via GBIF
├── import/                   # Data import & sync scripts
│   ├── import_trees.py             # Unified tree import from template CSV
│   ├── import_sensor_data.py       # Import sensor data from Aquarius
│   ├── link_sensors_to_trees.py    # Link sensors to trees
│   ├── sync_aquarius.py            # Sync sensor data via edge function
│   ├── sync_aquarius_direct.py     # Direct Aquarius sync (host-side)
│   ├── find_active_sensors.py      # Find sensors with recent data
│   └── archive/                    # Superseded scripts
│       ├── import_ecosense.py      # (replaced by import_trees.py)
│       └── import_mathisle.py      # (replaced by import_trees.py)
└── utils/                    # Utility and debug scripts
    ├── check_db_schema.py          # Inspect database schema
    ├── test_aquarius.py            # Test Aquarius API connection
    ├── test_import_upload.py       # Test import file upload
    └── test_sensor_query.py        # Test sensor queries
```

## Prerequisites

1. **Conda environment** - Install and activate:

   ```bash
   conda env create -f environment.yml
   conda activate digital-twin
   ```

2. **Database running** - Start Docker containers:

   ```bash
   cd docker && docker compose up -d
   ```

3. **Environment file** - Ensure `docker/.env` exists with valid credentials.

## Import Scripts

All import scripts are in `scripts/import/`. Before importing, prepare your data following the [DATA_PREPARATION_GUIDE.md](../data/templates/DATA_PREPARATION_GUIDE.md) and the templates in `data/templates/`.

### Import Tree Data

Import trees from any CSV following the standard template format (see `data/templates/`):

```bash
# Import from a prepared CSV (validates, then inserts)
python scripts/import/import_trees.py data/imports/ecosense_trees_import.csv
python scripts/import/import_trees.py data/imports/mathisle_trees_import.csv

# Dry run — validate only, no data inserted
python scripts/import/import_trees.py data/imports/my_data.csv --dry-run
```

### Import Sensor Data

```bash
# Import sensor data from Aquarius API
python scripts/import/import_sensor_data.py

# Link sensors to nearby trees
python scripts/import/link_sensors_to_trees.py
```

### Sync Aquarius Data

Sync sensor readings from the Aquarius API (requires university VPN):

```bash
# Sync last 30 days (default)
python scripts/import/sync_aquarius.py

# Sync last N days
python scripts/import/sync_aquarius.py 7
```

### Find Active Sensors

List sensors that have recent data in Aquarius:

```bash
python scripts/import/find_active_sensors.py
```

## Utility Scripts

All utility scripts are in `scripts/utils/`.

```bash
# Test database connection and inspect schema
python scripts/utils/check_db_schema.py

# Test Aquarius API connection
python scripts/utils/test_aquarius.py

# Validate and test import files (dry-run)
python scripts/utils/test_import_upload.py

# Test sensor queries
python scripts/utils/test_sensor_query.py
```

## Admin Scripts

Administrative scripts for database management (in `scripts/admin/`):

```bash
# Full database reset (destroys all data)
python scripts/admin/reset_database.py

# Skip confirmation prompt
python scripts/admin/reset_database.py --force

# Refresh all lookup tables from CSV
python scripts/admin/refresh_lookups.py

# Refresh specific table
python scripts/admin/refresh_lookups.py species

# List available tables
python scripts/admin/refresh_lookups.py --list
```

### Validate Species Names (GBIF)

Validate species names against the GBIF taxonomic backbone to ensure standardization:

```bash
# Validate all species in data/lookups/species.csv
python scripts/admin/validate_species_gbif.py

# Show detailed GBIF API responses
python scripts/admin/validate_species_gbif.py --verbose

# Generate corrections CSV (data/lookups/species_gbif_validation.csv)
python scripts/admin/validate_species_gbif.py --fix
```

The script checks for:

- **Valid names** - exact match in GBIF backbone
- **Synonyms** - names that should use accepted alternatives
- **Misspellings** - fuzzy matches suggesting corrections
- **Unknown** - species not found in GBIF
