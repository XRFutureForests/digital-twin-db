# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Digital Forest Twin Database** - A Supabase-powered PostgreSQL database infrastructure for forest research with PostGIS spatial support, real-time capabilities, and automated data integration.

Key technologies:

- **Supabase** - Self-hosted infrastructure
- **PostgreSQL 15 + PostGIS** - Spatial database
- **PostgREST** - Auto-generated REST APIs
- **Deno Edge Functions** - Serverless TypeScript/Deno functions
- **Python** - CSV data importer with coordinate transformation

## Common Commands

### Starting & Stopping the Stack

```bash
# Start Supabase stack
cd docker
docker compose up -d

# Stop services
docker compose down

# View service status
docker compose ps

# View logs for all services
docker compose logs -f

# View logs for specific service
docker compose logs -f db
docker compose logs -f rest
docker compose logs -f functions
```

### Database Access

```bash
# Direct PostgreSQL via Docker
docker exec -it dftdb-db psql -U postgres

# List schemas
\dn

# List tables in a schema
\dt shared.*

# Query data
SELECT * FROM shared.species;
```

### Importing Data

```bash
cd scripts/import-data

# Using Docker (recommended - no Python required)
./import-docker.sh --csv /data/PATH_TO_CSV --table TABLE_NAME --created-by YOUR_NAME --interactive

# Using Python directly
python csv_importer.py --csv data.csv --table Trees --created-by "import_user" --crs EPSG:32632 --interactive
```

### Testing Edge Functions

```bash
# Trigger ecosense data sync (requires SERVICE_ROLE_KEY)
curl -X POST "http://localhost:8000/functions/v1/ecosense-ingest?days_back=7" \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
```

### Resetting Database

```bash
cd docker

# Full reset (removes all data and volumes)
./reset.sh

# Or manually
docker compose down -v --remove-orphans
sudo rm -rf volumes/db/data
docker compose up -d
```

## Architecture & Code Structure

### Database Organization (5 Custom Schemas)

1. **shared** - Reference data
   - `Species` - Tree species definitions
   - `Locations` - Forest plot metadata
   - `SoilTypes` - Soil classification
   - `ClimateZones` - Climate zone definitions
   - `Processes` - Audit trail for all changes

2. **pointclouds** - LiDAR data management
   - `PointClouds` - Scan metadata with S3 paths
   - Tracking of processing variants and quality metrics

3. **trees** - Individual tree measurements
   - `Trees` - Tree attributes and measurements
   - `Stems` - Multi-stem support
   - `TreeSimulations` - Growth model outputs

4. **sensor** - Environmental monitoring
   - `Sensors` - Sensor installations and metadata
   - `SensorReadings` - Time-series environmental data
   - `SensorTypes` - Sensor type definitions

5. **environments** - Environmental conditions
   - `EnvironmentalConditions` - Processed environmental data

All tables include:

- **Variant tracking** - Version control for data iterations
- **Audit logging** - Full change history (CreatedBy, CreatedAt)
- **Row-Level Security** - Fine-grained access control

### Database Initialization Migrations

Migrations run automatically when database starts. Located in `docker/volumes/db/init/`:

| File | Purpose |
|------|---------|
| `10-enable-postgis.sql` | PostGIS extension |
| `11-shared-schema.sql` | Shared reference tables |
| `12-pointclouds-schema.sql` | Point cloud tables |
| `13-trees-schema.sql` | Tree measurement tables |
| `14-sensor-schema.sql` | Sensor and readings tables |
| `15-environments-schema.sql` | Environmental data tables |
| `16-rls-policies.sql` | Row-level security policies |
| `17-audit-functions.sql` | Change tracking triggers |
| `18a-seed-lookup-data.sql` | Species lookup data |
| `18b-seed-sample-locations.sql` | Sample locations for testing |
| `21-aquarius-integration.sql` | Aquarius API integration |
| `22-link-sensors-to-trees.sql` | Sensor-tree associations |
| `23-processing-jobs.sql` | External workflow tracking |
| `24-public-api-views.sql` | Public simplified API views |

### Edge Functions (Deno/TypeScript)

Located in `docker/volumes/functions/`:

**ecosense-ingest/index.ts**

- Syncs sensor data from Aquarius API
- Manages sensor metadata and time-series readings
- Triggered via REST endpoint with `days_back` parameter
- Uses `SERVICE_ROLE_KEY` authentication

**Shared utilities** (`_shared/`)

- `database.ts` - Supabase client initialization
- `aquarius.ts` - Aquarius API client
- `validators.ts` - Authentication helpers

### CSV Importer

Located in `scripts/import-data/`:

**csv_importer.py**

- Interactive column mapping
- Coordinate transformation (supports any EPSG code)
- Automatic lookups for species, locations, sensor types
- Dual geometry storage (original CRS + WGS84)
- Audit trail with `--created-by` identifier
- Error reporting with failed row details
- Dry-run mode for validation

Key features:

- Supports Docker or Python environment
- Maps CSV columns to any database field
- Validates coordinates (-90 to 90 lat, -180 to 180 lon)
- Fuzzy matching for species lookups
- Configurable coordinate systems

### Docker Services & Ports

```
Port 8000  → Kong Gateway (REST API + functions)
Port 5432  → PostgreSQL (via Supavisor pooler)
Port 54323 → Supabase Studio (Web UI)
Port 4000  → Analytics (Logflare)
```

**Service dependencies:**

- Studio depends on Analytics
- Kong/Auth/REST/Realtime/Storage depend on Analytics
- All depend on database health checks

### Configuration

Key environment variables in `docker/.env`:

**Security (must be unique in production)**

- `POSTGRES_PASSWORD` - Database password
- `JWT_SECRET` - Token signing secret
- `ANON_KEY` - Public API key
- `SERVICE_ROLE_KEY` - Admin API key
- `SECRET_KEY_BASE` - Session encryption

**API Configuration**

- `PGRST_DB_SCHEMAS` - Schemas exposed via REST API (critical: must include custom schemas)
- `PGRST_JWT_SECRET` - Must match JWT_SECRET

**External Services**

- `AQUARIUS_HOSTNAME`, `AQUARIUS_USERNAME`, `AQUARIUS_PASSWORD` - EcoSense sensor data API

**Access**

- `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD` - Studio UI credentials
- `SUPABASE_PUBLIC_URL` - External URL for Studio

## Key Design Patterns

### Geometry Storage

- **PositionOriginal** - Preserves original coordinate reference system
- **Position** - Always transformed to WGS84 (EPSG:4326) for consistency
- Dual storage enables accurate coordinate transformations and historical CRS tracking

### Audit Trail

- Every table has `CreatedBy` and `CreatedAt` fields
- Database level triggers in `17-audit-functions.sql` track all changes
- Query audit trail: `SELECT * FROM shared.processes WHERE TableName = 'Trees' ORDER BY CreatedAt DESC`

### Row-Level Security (RLS)

- Implemented via PostgreSQL policies in `16-rls-policies.sql`
- Controls data access based on user roles
- Enforced at database layer for all API requests

### Data Import Pattern

- CSV importer uses `SERVICE_ROLE_KEY` for full database access
- All imports tracked with `CreatedBy` identifier
- Batch operations with conflict handling
- Failed rows reported but not inserted - manual cleanup required

## Development Workflow

### Modifying Database Schema

1. Create new migration file: `docker/volumes/db/init/25-your-feature.sql`
2. Write SQL DDL commands
3. Apply manually: `docker exec -i dftdb-db psql -U postgres < docker/volumes/db/init/25-your-feature.sql`
4. Or restart services to run migrations automatically: `docker compose restart db`

### Creating New Edge Functions

1. Create directory: `docker/volumes/functions/my-function/`
2. Add `index.ts` with Deno code
3. Functions auto-reload on file changes - no restart needed
4. Use `getSupabaseClient()` from `_shared/database.ts` for database access

### REST API Testing

```bash
# Export API key
export SUPABASE_KEY="<your ANON_KEY from .env>"

# Get all species
curl "http://localhost:8000/rest/v1/species?select=*" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY"

# Get trees with species info (nested select)
curl "http://localhost:8000/rest/v1/trees?select=*,species(*)" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY"

# Create new location
curl -X POST "http://localhost:8000/rest/v1/locations" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"locationname":"New Plot","latitude":48.0,"longitude":8.0}'
```

## Important Notes

### Production Deployment

- Regenerate all passwords, tokens, and encryption keys before production
- Use strong cryptographic keys: `openssl rand -base64 32`
- Set `DISABLE_SIGNUP=true` to prevent public registrations
- Configure SSL/TLS via reverse proxy (nginx, Caddy, Traefik)
- See `docs/deployment-guide.md` for full production setup

### Edge Function Auto-reload

- Functions automatically reload on file changes during development
- No Docker restart needed - changes take effect immediately
- Keep `VERIFY_JWT=true` (set in `docker-compose.yml`) for security

### CSV Import Audit

- All imports create an audit trail with `CreatedBy` identifier
- Query your imports: `SELECT * FROM trees.Trees WHERE CreatedBy = 'your_name'`
- Facilitate data lineage and reproducibility

### Coordinate Systems

- Always use EPSG codes for coordinate transformations
- Common codes: EPSG:4326 (WGS84), EPSG:32632 (UTM Zone 32N)
- CSV importer validates latitude (-90 to 90) and longitude (-180 to 180)

## Documentation Structure

All documentation in `docs/`:

- `README.md` - Documentation index
- `supabase-introduction.md` - Supabase overview
- `database-schema.md` - Complete schema specifications
- `database-erd.dbml` - Entity relationship diagram
- `database-diagram.drawio` - Visual schema (editable)
- `deployment-guide.md` - Production deployment instructions
- `api-quick-reference.md` - Common API commands

Docker-specific docs in `docker/`:

- `README.md` - Docker setup and service details
- `TROUBLESHOOTING.md` - Common issues and solutions
- `CHANGELOG.md` - Version history
- `versions.md` - Service version specifications

## File Organization

```
digital_twin_db/
├── docker/                           # Supabase Docker Compose setup
│   ├── docker-compose.yml            # Main service configuration
│   ├── .env                          # Credentials and configuration
│   ├── volumes/
│   │   ├── db/
│   │   │   ├── init/                 # Database migration files (10-24-*.sql)
│   │   │   ├── data/                 # Persistent database volume
│   │   │   └── *.sql                 # Supabase infrastructure scripts
│   │   ├── functions/                # Edge functions (Deno/TypeScript)
│   │   │   ├── ecosense-ingest/
│   │   │   ├── hello/                # Test function
│   │   │   └── _shared/              # Shared utility modules
│   │   ├── storage/                  # File storage volume
│   │   └── logs/                     # Vector logging configuration
│   ├── reset.sh                      # Full database reset script
│   └── cleanup-volumes.sh            # Volume cleanup script
├── scripts/import-data/              # CSV importer
│   ├── csv_importer.py               # Main importer script
│   ├── import-docker.sh              # Docker wrapper
│   ├── requirements.txt              # Python dependencies
│   └── environment.yaml              # Conda environment
├── docs/                             # Documentation
│   ├── database-schema.md
│   ├── deployment-guide.md
│   ├── troubleshooting.md
│   └── ...
└── data/                             # Data files (CSV imports, seed data)
```
