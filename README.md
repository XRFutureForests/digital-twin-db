# Digital Forest Twin Database

A PostgreSQL database with PostGIS for forest research, containing tree inventory and sensor data.

## Quick Start

```bash
# Start the database (data loads automatically from CSV files)
cd docker
docker compose up -d

# Verify it's running
docker compose ps

# Connect to the database
docker exec -it dftdb-postgres psql -U postgres -d forest_twin
```

## What's Included

The database initializes with:

- **PostGIS** spatial extension for geometry operations
- **5 schemas**: shared, pointclouds, trees, sensor, environments
- **Reference data**: Species, soil types, climate zones, tree characteristics
- **~2,300 trees** from two forest plots (auto-imported from CSV)
- **Spatial coordinates** in WGS84 (transformed from original UTM/GPS)

## Database Connection

| Setting | Value |
|---------|-------|
| Host | `localhost` |
| Port | `5432` |
| Database | `forest_twin` |
| User | `postgres` |
| Password | `postgres` |

### Connection String

```
postgresql://postgres:postgres@localhost:5432/forest_twin
```

### Using psql

```bash
# Inside container
docker exec -it dftdb-postgres psql -U postgres -d forest_twin

# From host (if psql installed)
psql -h localhost -U postgres -d forest_twin
```

## Sample Queries

```sql
-- List all schemas
\dn

-- Count trees by species
SELECT s.commonname, COUNT(*) as tree_count
FROM trees.trees t
JOIN shared.species s ON t.speciesid = s.speciesid
GROUP BY s.commonname
ORDER BY tree_count DESC;

-- Get trees with coordinates
SELECT treeid, ST_X(position) as longitude, ST_Y(position) as latitude
FROM trees.trees
LIMIT 10;

-- Trees with full details
SELECT * FROM trees.v_trees_full LIMIT 10;

-- Summary by location
SELECT * FROM trees.v_tree_summary;
```

## Data Sources

### Tree Data (auto-loaded)

| File | Location | Trees | Description |
|------|----------|-------|-------------|
| `ecosense_250911.csv` | EcoSense Mixed Plot | ~1,500 | Douglas Fir & Beech, UTM coordinates |
| `mathisle_250904.csv` | Mathisleweiher Plot | ~740 | European Beech, GPS coordinates |

### Database Schemas

| Schema | Purpose |
|--------|---------|
| `shared` | Reference data (species, locations, soil types) |
| `pointclouds` | LiDAR scan metadata |
| `trees` | Tree measurements and stems |
| `sensor` | Environmental sensors and readings |
| `environments` | Aggregated environmental conditions |

## Common Operations

```bash
# Stop database
docker compose down

# Reset database (delete all data)
docker compose down -v
docker compose up -d

# View logs
docker compose logs -f

# Backup database
docker exec dftdb-postgres pg_dump -U postgres forest_twin > backup.sql

# Restore database
docker exec -i dftdb-postgres psql -U postgres -d forest_twin < backup.sql
```

## Project Structure

```
digital-twin/
├── data/                    # CSV source files
│   ├── ecosense_250911.csv  # EcoSense tree inventory
│   └── mathisle_250904.csv  # Mathisleweiher tree inventory
├── docker/
│   ├── docker-compose.yml   # PostgreSQL container config
│   ├── .env                 # Environment variables
│   └── volumes/db/simple-init/    # Database initialization scripts
└── docs/                    # Documentation
    ├── database-schema.md   # Schema details
    └── database-erd.dbml    # Entity relationship diagram
```

## Useful Views

The database includes pre-built views for common queries:

| View | Description |
|------|-------------|
| `trees.v_trees_full` | Trees with species, location, and DBH |
| `trees.v_tree_summary` | Statistics by location and species |
| `trees.v_trees_geojson` | Trees formatted for GeoJSON export |
| `shared.v_locations_overview` | Locations with tree/sensor counts |
| `sensor.v_active_sensors` | Active sensors with latest readings |

## Requirements

- Docker and Docker Compose
- ~500MB disk space
- No other services on port 5432

## Documentation

- [Database Schema](docs/database-schema.md) - Detailed table specifications
- [Database ERD](docs/database-erd.dbml) - Visual diagram at [dbdiagram.io](https://dbdiagram.io/)
