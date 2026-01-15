# Docker Setup

Simple PostgreSQL + PostGIS database for the Digital Forest Twin project.

## Quick Start

```bash
# Start database
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

The database initializes automatically on first start, loading ~2,200 trees from the EcoSense and Mathisleweiher forest plots.

## Data Loaded

| Source | Location | Trees | Description |
|--------|----------|-------|-------------|
| `ecosense_250911.csv` | EcoSense Mixed Plot | 1,494 | Mixed forest near Freiburg (UTM 32N coordinates) |
| `mathisle_250904.csv` | Mathisleweiher Plot | 727 | High-elevation mixed forest (WGS84 coordinates) |

**Total: 2,221 trees with stem measurements**

### Species Distribution

| Species | EcoSense | Mathisle |
|---------|----------|----------|
| European Beech | 1,317 | 87 |
| Norway Spruce | 44 | 469 |
| Silver Fir | 46 | 170 |
| Douglas Fir | 70 | - |
| Pedunculate Oak | 17 | - |

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | PostgreSQL container configuration |
| `.env` | Environment variables (credentials) |
| `volumes/db/simple-init/` | SQL initialization scripts |
| `../data/` | CSV data files for import |

## Database Schema

```
shared              Reference data (species, locations, scenarios)
trees               Tree measurements and stems
sensor              Environmental sensors and readings
environments        Environmental conditions
pointclouds         LiDAR point cloud metadata
```

### Key Tables

- `shared.Locations` - Forest plot definitions with boundaries
- `shared.Species` - Tree species reference (6 species)
- `trees.Trees` - Individual tree records with position, height, species
- `trees.Stems` - Stem measurements (DBH) per tree
- `sensor.Sensors` - Sensor installations
- `sensor.SensorReadings` - Time-series sensor data

### Convenience Views

- `trees.v_trees_full` - Trees with species, location, and DBH
- `trees.v_tree_summary` - Statistics by location and species
- `trees.v_trees_geojson` - Trees as GeoJSON for mapping

## Initialization Scripts

Scripts in `volumes/db/simple-init/` run automatically on first start (alphabetical order):

| Script | Purpose |
|--------|---------|
| `01-enable-postgis.sql` | Enable PostGIS extension |
| `02-shared-schema.sql` | Reference tables (species, locations, etc.) |
| `03-pointclouds-schema.sql` | LiDAR data management |
| `04-trees-schema.sql` | Tree measurements |
| `05-sensor-schema.sql` | Environmental sensors |
| `06-environments-schema.sql` | Environmental conditions |
| `07-seed-locations.sql` | Sample forest plot locations |
| `08-import-csv-data.sql` | Import tree data from CSV files |
| `09-useful-views.sql` | Convenience views for querying |

## Database Access

```bash
# Connect via docker exec
docker exec -it dftdb-postgres psql -U postgres -d forest_twin

# Or from host (default port 5432)
psql -h localhost -p 5432 -U postgres -d forest_twin
```

### Example Queries

```sql
-- Tree count by location
SELECT LocationName, COUNT(*)
FROM trees.v_trees_full
GROUP BY LocationName;

-- Average DBH by species
SELECT species, AVG(dbh_cm)::numeric(10,1) as avg_dbh
FROM trees.v_trees_full
GROUP BY species
ORDER BY avg_dbh DESC;

-- Export as GeoJSON
SELECT json_agg(row_to_json(t))
FROM trees.v_trees_geojson t
WHERE location = 'EcoSense Mixed Plot';
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `postgres` | Database user |
| `POSTGRES_PASSWORD` | (from .env) | Database password |
| `POSTGRES_DB` | `forest_twin` | Database name |
| `POSTGRES_PORT` | `5432` | Host port mapping |

## Operations

```bash
# Stop
docker compose down

# Reset (delete all data and reinitialize)
docker compose down -v
docker compose up -d

# Backup
docker exec dftdb-postgres pg_dump -U postgres forest_twin > backup.sql

# Restore
docker exec -i dftdb-postgres psql -U postgres -d forest_twin < backup.sql
```

## Troubleshooting

### Port 5432 already in use

```bash
# Option 1: Use a different port
POSTGRES_PORT=5433 docker compose up -d

# Then connect on the new port
psql -h localhost -p 5433 -U postgres -d forest_twin

# Option 2: Find and stop what's using port 5432
sudo lsof -i :5432
```

### Container won't start

```bash
# Check logs for errors
docker compose logs db

# Full reset (removes all data)
docker compose down -v
docker compose up -d
```

### Initialization failed

If init scripts fail, the database may be in a partial state:

```bash
# Check what went wrong
docker compose logs --tail=100

# Reset and try again
docker compose down -v
docker compose up -d
```
