# Docker Setup

Simple PostgreSQL + PostGIS database for the Digital Forest Twin project.

## Quick Start

```bash
# Start database
docker compose -f docker-compose.simple.yml up -d

# Check status
docker compose -f docker-compose.simple.yml ps

# View logs
docker compose -f docker-compose.simple.yml logs -f
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.simple.yml` | PostgreSQL container configuration |
| `.env.simple` | Environment variables (credentials) |
| `volumes/db/simple-init/` | SQL initialization scripts |

## Initialization Scripts

Scripts in `volumes/db/simple-init/` run automatically on first start:

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

# Or from host
psql -h localhost -U postgres -d forest_twin
# Password: postgres
```

## Operations

```bash
# Stop
docker compose -f docker-compose.simple.yml down

# Reset (delete all data)
docker compose -f docker-compose.simple.yml down -v
docker compose -f docker-compose.simple.yml up -d

# Backup
docker exec dftdb-postgres pg_dump -U postgres forest_twin > backup.sql

# Restore
docker exec -i dftdb-postgres psql -U postgres -d forest_twin < backup.sql
```

## Troubleshooting

### Port 5432 already in use

```bash
# Find what's using the port
sudo lsof -i :5432

# Use different port (edit .env.simple)
POSTGRES_PORT=5433
```

### Container won't start

```bash
# Check logs
docker compose -f docker-compose.simple.yml logs db

# Reset everything
docker compose -f docker-compose.simple.yml down -v
docker compose -f docker-compose.simple.yml up -d
```
