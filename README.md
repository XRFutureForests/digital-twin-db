# Digital Forest Twin Database

> **Supabase-powered database for research connected to digital forest twins**

This repository provides the database infrastructure for creating digital twins of forests. It uses Supabase to deliver a complete PostgreSQL-based data platform with auto-generated REST APIs, real-time subscriptions, and integrated authentication.

---

## Quick Start

### Installation

Get the database running locally in 2 steps:

```bash
# 1. Clone the repository
git clone <repository-url>
cd digital-twin

# 2. Start the Supabase stack (official Docker setup with pre-configured .env)
cd docker
docker compose up -d

# Wait ~30 seconds for all services to become healthy
docker compose ps
```

All services should show as "healthy". The database is automatically initialized with:

- PostGIS extension enabled
- 6 custom forest schemas (shared, pointclouds, trees, sensor, environments, imagery)
- Reference data (species, soil types, climate zones)
- Row-level security policies
- **Empty tables** - No test data is automatically loaded

⚠️ **Note:** The database initializes with schema only. Use the CSV importer tool to load data manually (see "Importing Data" section below).

**About the .env file:**

The `.env` file is already set up with secure credentials. It contains:

- Database passwords and JWT secrets
- API keys for authentication
- Service configuration

**Important**: The `.env` file contains secrets and should never be committed to git. Before deploying to production, regenerate all passwords and tokens.

### Access Points

Once running, access the database through:

- **Supabase Studio UI**: <http://localhost:54323> - Visual database management
- **REST API**: <http://localhost:8000/rest/v1> - Auto-generated endpoints (Kong Gateway)
- **PostgreSQL**: `localhost:5432` - Direct database access (via Supavisor pooler)

### Verify Installation

Check that all services are running:

```bash
cd docker
docker compose ps
```

All services should show "healthy" status. If any show "Exit" or "Restarting", check the logs:

```bash
docker compose logs [service-name]
```

For more troubleshooting, see [docker/README.md](docker/README.md).

**New to Supabase?** See [docs/supabase-introduction.md](docs/supabase-introduction.md) to learn what Supabase is and how it works.

---

## What's in This Repository

### Database Infrastructure

This repository implements the data tier for digital forest twin projects using **Supabase**, providing:

- **PostgreSQL + PostGIS** - Spatial database with forest-specific schemas
- **PostgREST** - Automatically generated REST APIs from database structure
- **Real-time Server** - WebSocket support for live data updates
- **Authentication** - Built-in user management and Row-Level Security
- **Storage API** - S3-compatible storage for point cloud files
- **Edge Functions** - Serverless business logic (Deno/TypeScript)
- **Supabase Studio** - Visual database management interface

### Three-Layer Architecture

The database initialization follows a clean separation of concerns:

| Layer | Files | Purpose |
|-------|-------|---------|
| **1. Structure** | `10-16` | Database schemas, tables, indexes, constraints |
| **2. Functions** | `20-24` | Security policies, audit functions, API views |
| **3. Lookup Data** | `30-31` | Reference data loaded from CSV files |

**User data** (trees, sensors, readings) is NOT loaded during initialization—that's a separate user-triggered import step using the scripts in `scripts/`.

This separation allows you to:

- **Edit lookup data** (species, locations) without touching SQL
- **Refresh lookups** without rebuilding the database
- **Keep user data** separate from reference data

---

## Database Structure

The database organizes forest research data into 6 specialized schemas:

### 1. **shared** - Reference Data

Core reference tables used across all schemas:

- **Species** - Tree species definitions (Beech, Oak, Spruce, etc.)
- **Locations** - Forest plot coordinates and metadata
- **Plots** - Sub-plot divisions within locations
- **Campaigns** - Data collection events (LiDAR flights, field inventories)
- **SoilTypes**, **ClimateZones** - Environmental classification
- **Scenarios**, **VariantTypes** - Analysis variant management
- **ManagementEvents**, **DisturbanceEvents** - Forest event tracking
- **Processes**, **AuditLog** - Change tracking and audit trail

### 2. **pointclouds** - LiDAR Data

Point cloud scan management:

- **PointClouds** - Scan metadata with S3 file paths
- **ScannerTypes**, **Scanners** - Scanner hardware tracking
- Supports multiple processing variants (raw, filtered, classified)
- Tracks processing status and quality metrics

### 3. **trees** - Tree Measurements

Individual tree data with multi-stem support:

- **Trees** - Tree measurements and attributes with persistent TreeEntityID
- **Stems** - Multi-stem measurements for trees with multiple main stems
- **PhenologyObservations** - Seasonal development phase tracking
- **Deadwood** - Dead wood inventory with decay classification
- **GroundVegetation** - Ground vegetation surveys
- **TreeStatus**, **TaperTypes**, **StraightnessTypes**, **BranchingPatterns**, **BarkCharacteristics** - Classification tables

### 4. **sensor** - Environmental Monitoring

IoT sensor data collection:

- **Sensors** - Sensor installations and configurations
- **SensorReadings** - Time-series environmental data
- **SensorTreeLinks** - Relationships between sensors and individual trees

### 5. **environments** - Environmental Conditions

Processed environmental data:

- **Environments** - Temperature, humidity, soil moisture, nutrients
- Derived from sensors, manual input, or model outputs

### 6. **imagery** - Aerial & Ground Imagery

- **Images** - Aerial and ground-based imagery with spatial metadata and camera parameters

All tables include:

- **Variant tracking** - Version control for data iterations
- **Audit logging** - Full change history with user attribution
- **Row-Level Security** - Fine-grained access control

---

## Importing Data

The database initializes with empty tables. Import data using the Python scripts in `scripts/import/`.

### Installation

```bash
cd scripts
conda env create -f environment.yml
conda activate digital-twin
```

### Import Scripts

```bash
# Import tree data from EcoSense
python scripts/import/import_ecosense.py

# Import sensor data from Aquarius API
python scripts/import/import_sensor_data.py

# Link sensors to nearby trees (run after importing both)
python scripts/import/link_sensors_to_trees.py

# Sync latest sensor readings from Aquarius (default: last 30 days)
python scripts/import/sync_aquarius.py

# Find sensors with recent data in Aquarius
python scripts/import/find_active_sensors.py
```

Prepare your data following the [DATA_PREPARATION_GUIDE.md](data/templates/DATA_PREPARATION_GUIDE.md) and the templates in `data/templates/`.

For detailed usage guide, see [`scripts/README.md`](scripts/README.md)

---

## Edge Functions

External data sources and processing services communicate with the database through Supabase Edge Functions. These are serverless TypeScript/Deno functions that act as API gateways.

**Note:** Edge Functions auto-reload on file changes during development - no restart needed!

### Available Functions

#### `/functions/v1/ecosense-ingest`

Syncs sensor data from Aquarius API (EcoSense sensors).

**Trigger manually:**

```bash
curl -X POST "http://localhost:8000/functions/v1/ecosense-ingest?days_back=7" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
```

**Returns:**

```json
{
  "success": true,
  "count": 1523,
  "sensors": 4
}
```

**Authentication:** All Edge Functions require `SERVICE_ROLE_KEY` for authentication.

**Configuration:** Edge Function credentials are set in `docker/.env`:

- `AQUARIUS_HOSTNAME`, `AQUARIUS_USERNAME`, `AQUARIUS_PASSWORD`

---

## How to Use

### Option 1: Visual Interface (Supabase Studio)

Open <http://localhost:54323> in your browser.

**Table Editor** - Browse and edit data:

1. Select a schema in the left sidebar
2. Click on a table to view its contents
3. Add, edit, or delete rows directly

**SQL Editor** - Run custom queries:

```sql
-- Example: Get all beech trees
SELECT t.*, s.speciesname
FROM trees.trees t
JOIN shared.species s ON t.speciesid = s.speciesid
WHERE s.speciesname = 'Fagus sylvatica';
```

**API Documentation** - View auto-generated endpoints for every table.

### Option 2: REST API

The database automatically provides REST endpoints for all tables.

**API Base URL**: `http://localhost:8000/rest/v1`
**API Key**: Find `SUPABASE_ANON_KEY` in your `.env` file

**Example using curl**:

```bash
# Get all species
curl "http://localhost:8000/rest/v1/species?select=*" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"

# Get trees with species information
curl "http://localhost:8000/rest/v1/trees?select=*,species(*)" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"

# Create a new location
curl -X POST "http://localhost:8000/rest/v1/locations" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"locationname":"New Plot","latitude":48.0,"longitude":8.0}'
```

**Example using Python**:

```python
from supabase import create_client

# Initialize client
supabase = create_client(
    "http://localhost:8000",
    "YOUR_ANON_KEY"  # from .env file
)

# Query data
response = supabase.table('species').select('*').execute()
print(response.data)

# Insert data
response = supabase.table('locations').insert({
    'locationname': 'Test Plot',
    'latitude': 48.0,
    'longitude': 8.0
}).execute()
```

**Example using R**:

```r
library(httr)

# Your API key from .env
api_key <- "YOUR_ANON_KEY"

# Make request
response <- GET(
  "http://localhost:8000/rest/v1/species?select=*",
  add_headers(
    apikey = api_key,
    Authorization = paste("Bearer", api_key)
  )
)

# Parse response
data <- content(response)
```

### Option 3: Direct PostgreSQL Connection

Connect with any PostgreSQL client (psql, DBeaver, pgAdmin, etc.):

```
Host: localhost
Port: 5432
Database: postgres
Username: postgres.digital-forest-twin-local  (format: postgres.{POOLER_TENANT_ID})
Password: (from POSTGRES_PASSWORD in .env)
```

**Important**: Connections on port 5432 go through Supavisor connection pooler. The username must include the tenant ID suffix (e.g., `postgres.digital-forest-twin-local`). Check your `.env` for the `POOLER_TENANT_ID` value.

**Using psql from host**:

```bash
# Connect via Supavisor (from host machine)
source docker/.env
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 \
  -U "postgres.$POOLER_TENANT_ID" -d postgres
```

**Using psql inside container** (bypasses Supavisor):

```bash
# Connect directly inside container
docker exec -it dftdb-db psql -U postgres

# List schemas
\dn

# List tables
\dt shared.*

# Query
SELECT * FROM shared.species;

# Exit
\q
```

---

## Documentation

### Getting Started

- **[docs/README.md](docs/README.md)** - Complete documentation index
- **[docs/supabase-introduction.md](docs/supabase-introduction.md)** - Learn what Supabase is and how it works
- **[docs/troubleshooting.md](docs/troubleshooting.md)** - Common issues and solutions

### Technical Documentation

- **[Database Schema](docs/database-schema.md)** - Schema specifications and design
- **[Database ERD](docs/database-erd.dbml)** - Entity relationship diagram (DBML format)
- **[Database Diagram](docs/database-diagram.drawio)** - Visual schema diagram (editable)
- **[Deployment Guide](docs/deployment-guide.md)** - Production deployment instructions

### Reference Guides

- **[API Quick Reference](docs/api-quick-reference.md)** - Common commands, URLs, and examples

---

## Development Workflow

### Starting and Stopping

```bash
# Navigate to docker directory
cd docker

# Start all services
docker compose up -d

# Stop all services
docker compose down

# View status
docker compose ps

# View logs
docker compose logs -f
```

### Working with Data

**Add sample data**:

- Use Supabase Studio UI for manual entry
- Use REST API for programmatic insertion
- Write SQL migrations in `docker/volumes/db/init/`

**Update lookup tables** (species, locations, sensor types):

1. Edit CSV files in `data/lookups/`
2. Refresh without rebuilding:

```bash
# Refresh all lookup tables
python scripts/admin/refresh_lookups.py

# Refresh specific table
python scripts/admin/refresh_lookups.py species

# List available tables
python scripts/admin/refresh_lookups.py --list
```

Or via SQL:

```sql
SELECT * FROM shared.refresh_all_lookups();
SELECT * FROM shared.refresh_lookup('species');
```

**Update database schema**:

1. Create new migration file: `docker/volumes/db/init/26-your-changes.sql`
2. Write SQL DDL commands
3. Apply manually: `docker exec -i dftdb-db psql -U postgres < docker/volumes/db/init/26-your-changes.sql`

**Create Edge Functions**:

1. Create directory: `docker/volumes/functions/my-function/`
2. Add `index.ts` with Deno code
3. Restart functions: `docker compose restart functions`

### Testing APIs

```bash
# Set your API key
export SUPABASE_KEY="your_anon_key"

# Test endpoints
curl "http://localhost:8000/rest/v1/species?select=*" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY"
```

---

## Cleanup and Reset

### Quick Cleanup (Preserves Data)

Stop all services without removing volumes:

```bash
cd docker
docker compose down
```

Restart with preserved data:

```bash
docker compose up -d
```

### Full Reset (Removes All Data)

**⚠️ WARNING: This will permanently delete all database data, volumes, and containers.**

```bash
python scripts/admin/reset_database.py

# Skip confirmation prompt
python scripts/admin/reset_database.py --force
```

Or use native Docker commands:

```bash
cd docker

# Stop and remove all containers and volumes
docker compose down -v --remove-orphans

# Remove the persistent database data directory
rm -rf volumes/db/data

# Restart fresh
docker compose up -d
```

### Common Issues

**Analytics container fails to start:**

```bash
# The analytics container requires the _supabase database
# If it fails, check database logs:
docker compose logs db | grep -i error

# Force a complete reset:
docker compose down -v
sudo rm -rf volumes/db/data
docker compose up -d
```

**Auth/Realtime/Storage containers keep restarting:**

These services may restart several times on first initialization due to database migration timing. This is normal behavior. Wait 2-3 minutes for all services to stabilize.

If they don't stabilize after 5 minutes:

```bash
# Restart the failing services
docker compose restart auth realtime storage

# Check logs
docker compose logs auth
docker compose logs realtime
docker compose logs storage
```

**Port conflicts:**

If ports 8000, 5432, 54323, or 6543 are already in use:

```bash
# Find what's using the port
sudo lsof -i :8000

# Stop the conflicting service or change ports in docker-compose.yml
```

For more troubleshooting, see [docs/troubleshooting.md](docs/troubleshooting.md).

---

## S3 Storage for Point Clouds (Optional)

Large LiDAR files (.las, .laz) can be stored in external S3 buckets rather than the database.

**Note**: S3 storage is **optional**. The database works perfectly fine for tree measurements, sensor data, and locations without S3. Only configure S3 if you're working with point cloud files.

**How it works** (when configured):

1. Database stores S3 file paths: `s3://bucket-name/path/file.las`
2. Edge Functions generate presigned URLs for secure access
3. Clients download directly from S3

**Benefits**:

- Unlimited storage capacity
- Cost-effective for large files
- No database bloat
- Direct downloads with temporary URLs

**Configuration**:
See the Edge Functions in `docker/volumes/functions/` and [Deployment Guide](docs/deployment-guide.md) for S3 setup instructions (only needed if using point clouds).

---

## Production Deployment

This repository is designed for both local development and production deployment.

### Local Development

- Use default configuration from `.env` in docker directory
- Run on `localhost` with Docker Compose
- Pre-configured credentials suitable for local testing
- Start with: `cd docker && docker compose up -d`

### Production Server

- Use strong cryptographic keys (generate with `openssl rand -base64 32`)
- Configure domain names and SSL/TLS certificates
- Set up S3 bucket with proper IAM permissions
- Configure backups and monitoring
- Disable public signup (`DISABLE_SIGNUP=true`)

**See [docs/deployment-guide.md](docs/deployment-guide.md) and the official [Supabase Self-Hosting Guide](https://supabase.com/docs/guides/hosting/docker) for detailed production deployment instructions.**

---

## Support

### Finding Help

All documentation is in the `docs/` directory, organized by topic. Start with [docs/README.md](docs/README.md) for a complete guide.

### Issues

- Check [docs/troubleshooting.md](docs/troubleshooting.md) for common problems
- Review existing GitHub issues
- Create new issue with detailed description

### External Resources

- [Supabase Documentation](https://supabase.com/docs)
- [PostgREST API Reference](https://postgrest.org/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PostGIS Documentation](https://postgis.net/)
