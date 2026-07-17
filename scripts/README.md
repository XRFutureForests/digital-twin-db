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
│   ├── ingest_sensor_data.py       # Provider-agnostic sensor/reading import (CSV/JSON)
│   ├── link_sensors_to_trees.py    # Link sensors to trees (writes sensor_ref)
│   └── archive/                    # Superseded scripts
│       ├── import_ecosense.py      # (replaced by import_trees.py)
│       └── import_mathisle.py      # (replaced by import_trees.py)
├── seed/                     # Optional demo/test data (never auto-applied)
│   └── ecosense_growth_variants.sql # Growth variants generated from real Ecosense baseline (see docs/variant-scenario-model.md)
└── utils/                    # Utility and debug scripts
    ├── check_db_schema.py          # Inspect database schema
    └── test_import_upload.py       # Test import file upload
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

Provider-agnostic: loads sensors and readings from any CSV or JSON export via
the `bulk_upsert_sensors` / `bulk_insert_readings` RPCs. For Aquarius
specifically (requires university VPN), see the sibling
[aquarius-connector](../../aquarius-connector) repo.

```bash
# Preview without writing
python scripts/import/ingest_sensor_data.py sensors data/imports/my_sensors.csv --dry-run

# Load sensors, then readings
python scripts/import/ingest_sensor_data.py sensors data/imports/my_sensors.csv
python scripts/import/ingest_sensor_data.py readings data/imports/my_readings.json

# Link sensors to nearby trees
python scripts/import/link_sensors_to_trees.py
```

## Seed Data (Optional)

`scripts/seed/` holds the growth-variant seeds that are **never auto-applied**. A
fresh `docker compose up` produces a clean, empty database — real forest data
(ecosense, mathisle) and its growth variants are loaded manually, on purpose.

```bash
# Generate growth variants from the real Ecosense baseline — optional
# (creates the location-scoped natural_growth scenario, assigns the baseline
# trees to baseline_2025, and chains growth_2035/growth_2045). See
# docs/variant-scenario-model.md for how to copy this pattern for your own variant.
docker exec -i dftdb-db psql -U postgres -d <POSTGRES_DB> -f - < scripts/seed/ecosense_growth_variants.sql
```

## Utility Scripts

All utility scripts are in `scripts/utils/`.

```bash
# Test database connection and inspect schema
python scripts/utils/check_db_schema.py

# Validate and test import files (dry-run)
python scripts/utils/test_import_upload.py
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
