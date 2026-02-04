# Digital Forest Twin - Database Architecture & Services

Comprehensive guide to the database structure, connected services, and interaction patterns.

## System Overview

The Digital Forest Twin is a PostgreSQL-based database infrastructure for forest research with PostGIS spatial support, real-time capabilities, and automated data integration.

**Core Technologies:**

- PostgreSQL 15 + PostGIS (spatial database)
- Supabase (self-hosted infrastructure)
- PostgREST (auto-generated REST APIs)
- Deno Edge Functions (serverless TypeScript)
- Python (CSV data importers)

## Database Architecture

### Schema Organization

The database is organized into 6 custom schemas, each handling a specific domain:

#### 1. **shared** - Reference & Audit Data

Central location for lookup tables and audit functionality used across all domains.

| Table | Purpose |
|-------|---------|
| `Species` | Tree species definitions (name, scientific name, growth characteristics, IsDeciduous flag) |
| `Locations` | Forest plot metadata with PostGIS geometry boundaries |
| `SoilTypes` | Soil classification and properties |
| `ClimateZones` | Climate zone definitions |
| `Scenarios` | Named data variants for analysis scenarios |
| `VariantTypes` | Classification for variant patterns (original, processed, repeat_measurement, etc.) |
| `Campaigns` | Data collection events (LiDAR flights, field inventories) with methodology |
| `Processes` | Audit trail - tracks all data modifications |
| `ProcessParameters` | Parameters associated with processing jobs |
| `ProcessMetrics` | Metrics from processing operations |
| `Plots` | Sub-plot divisions within locations |
| `ManagementEvents` | Forest management activities |
| `DisturbanceEvents` | Natural disturbance events |
| `DisturbanceEvents_Trees` | Junction: disturbance-tree damage links |

**Audit Junction Tables:**

- `ProcessParameters_PointClouds`, `_Trees`, `_Environments`, `_Stems`
- `AuditLog_PointClouds`, `_Trees`, `_Environments`, `_Stems`
- Map audit/process data to domain-specific variants

#### 2. **pointclouds** - LiDAR Data Management

Handles point cloud scan data and processing variants.

| Table | Purpose |
|-------|---------|
| `PointClouds` | LiDAR scan metadata with S3 paths, quality metrics |
| `ScannerTypes` | LiDAR scanner type classifications |
| `Scanners` | Individual scanner hardware instances |

**Key Fields:**

- `LocationID` - Links to specific forest plot
- `CampaignID` - Data collection campaign
- `ScannerID` - Physical scanner hardware used
- `FilePath` - S3 URI to point cloud file
- `SensorModel` - LiDAR scanner model
- `SourceCRS` - EPSG code of original CRS
- `PlatformType` - terrestrial, aerial, mobile, UAV
- `FlightAltitude_m`, `FlightSpeed_ms`, `ScanAngle_deg`, `Overlap_percent` - Flight/scan parameters
- `PointDensity_per_m2` - Average point density
- `ProcessingStatus` - Track processing state (pending, processing, completed, failed)
- `VariantID` / `ParentVariantID` - Variant tracking for temporal lineage

#### 3. **trees** - Tree Measurements & Growth Models

Individual tree data with support for multi-stem trees and growth simulations.

| Table | Purpose |
|-------|---------|
| `Trees` | Main table: tree attributes, position, measurements |
| `Stems` | Multi-stem support (trees with multiple main stems) |
| `TreeStatus` | Health/status classifications |
| `TaperTypes` | Stem profile classifications |
| `StraightnessTypes` | Trunk straightness classifications |
| `BranchingPatterns` | Crown structure patterns |
| `BarkCharacteristics` | Bark feature classifications |
| `PhenologyObservations` | Seasonal development phase observations |
| `Deadwood` | Dead wood inventory |
| `GroundVegetation` | Ground vegetation surveys |

**Key Fields (Trees):**

- `TreeEntityID` - Persistent UUID identifying the physical tree across all variants
- `LocationID` - Forest plot location
- `PlotID` - Sub-plot within the location
- `CampaignID` - Data collection campaign this measurement belongs to
- `SourceCRS` - EPSG code of original CRS
- `Position` - WGS84 point geometry (tree position)
- `PositionOriginal` - Original coordinate system with elevation
- `SpeciesID` - Links to Species lookup
- `MeasurementDate` - Actual date of field measurement
- `DataSourceType` - How data was collected (lidar, field, photogrammetry, estimated, simulated)
- `Height_m`, `Volume_m3` - Measurements
- `CrownOffsetX_m`, `CrownOffsetY_m` - Crown asymmetry from trunk position
- `SpeciesConfidence`, `PositionConfidence`, `HeightConfidence` - Quality scores (0-1)
- `StatusChangeDate` - Date when tree status changed (e.g., mortality)
- `VariantID` - Version control for tree data
- `CreatedBy`, `CreatedAt` - Audit trail

#### 4. **sensor** - Environmental Monitoring

Sensor hardware configuration and time-series environmental data.

| Table | Purpose |
|-------|---------|
| `Sensors` | Sensor installations: model, location, calibration, battery |
| `SensorReadings` | Time-series environmental measurements (temperature, humidity, etc.) |
| `SensorTypes` | Sensor type definitions (Temperature, Humidity, CO2, etc.) |
| `SensorTreeLinks` | Relationships between sensors and individual trees |

**Key Fields (Sensors):**

- `LocationID` - Forest plot where sensor is installed
- `CampaignID` - Deployment campaign
- `Position` - WGS84 point geometry (sensor location)
- `PositionOriginal` - Original CRS coordinates before transformation
- `SourceCRS` - EPSG code of original CRS
- `SensorTypeID` - Links to SensorTypes
- `InstallationHeight_m` - Height above ground
- `SerialNumber`, `ExternalID` - Hardware identification
- `InstallationDate`, `DecommissionDate` - Lifecycle tracking
- `IsActive` - Current status
- `ExternalID`, `ExternalMetadata` - Integration with external systems (e.g., Aquarius)

**Key Fields (SensorReadings):**

- `SensorID` - Links to Sensors table
- `Timestamp` - Measurement time
- `Value` - Actual measurement data (unit inherited from parent Sensor)
- `Quality` - Data quality flag (good, suspect, bad, missing, calibration)
- `BatteryVoltage`, `SignalStrength` - Hardware diagnostics

**Key Fields (SensorTreeLinks):**

- `sensor_id`, `tree_variant_id` - Direct relationship between sensor and tree variant
- `StartDate`, `EndDate` - Monitoring period
- Enables growth monitoring and environmental correlation analysis

#### 5. **environments** - Environmental Conditions

Processed environmental data from sensor networks or simulations.

| Table | Purpose |
|-------|---------|
| `Environments` | Processed environmental conditions linked to locations |

#### 6. **imagery** - Aerial & Ground Imagery

Aerial and ground-based imagery with spatial metadata.

| Table | Purpose |
|-------|---------|
| `Images` | Aerial and ground-based imagery with spatial metadata |

### Design Patterns

#### Variant-Based Lineage

Point clouds, trees, and environments use a parent-child variant pattern for version control:

```
VariantID (unique identifier for this version)
├── ParentVariantID (previous version, if applicable)
├── VariantTypeID (original, processed, simulated, etc.)
└── ScenarioID (named analysis scenario)
```

This enables:

- Temporal tracking of data changes
- Comparison between different processing approaches
- Reproducible analysis scenarios

#### PostGIS Geometry Storage

All spatial data uses PostGIS geometries:

```sql
Position            -- WGS84 (EPSG:4326) point geometry
                    -- Standard for all external coordinates

PositionOriginal    -- Preserves original CRS
                    -- Format: SRID=32632;POINT(x y z)
                    -- Enables accurate coordinate transformations
```

#### Audit Trail

Every variant table includes:

- `CreatedBy` - User/system identifier
- `CreatedAt` - Timestamp
- `UpdatedBy` - Last modifier
- `UpdatedAt` - Last modification time

Linked to `AuditLog` junction tables for full change history:

```sql
-- View audit history for a specific tree
SELECT al.* FROM shared.auditlog al
JOIN shared.auditlog_trees at ON al.auditlogid = at.auditlogid
WHERE at.variantid = 123
ORDER BY al.changedat DESC;
```

#### External System Integration

Sensors table supports external integrations:

- `ExternalID` - ID in external system (e.g., Aquarius API)
- `ExternalMetadata` - JSONB metadata from external source
- Enables bidirectional sync with APIs

## Services Architecture

### Deployed Services

Services run in Docker Compose (see `docker/docker-compose.yml`):

| Service | Port | Purpose |
|---------|------|---------|
| **kong** | 8000 | API Gateway (REST/functions) |
| **db** | 5432 | PostgreSQL database |
| **rest** | Internal | PostgREST (auto-generated APIs) |
| **realtime** | Internal | WebSocket support for subscriptions |
| **auth** | Internal | Authentication/authorization |
| **storage** | Internal | File storage (S3-compatible) |
| **studio** | 54323 | Web UI (Supabase Studio) |
| **analytics** | 4000 | Logging (Logflare) |

**Service Dependencies:**

- All depend on database health checks
- Kong/Auth/REST depend on Analytics
- Studio depends on Analytics

### Edge Functions

Serverless TypeScript/Deno functions deployed at `docker/volumes/functions/`:

#### ecosense-ingest

Syncs sensor data from Aquarius API to SensorReadings table.

**Endpoint:** `POST http://localhost:8000/functions/v1/ecosense-ingest`

**Parameters:**

- `days_back` - Number of days to sync (e.g., 7)

**Authentication:** `SERVICE_ROLE_KEY` required

**Functionality:**

- Fetches readings from Aquarius API
- Creates/updates Sensor records
- Inserts SensorReadings with validation
- Tracks external IDs for deduplication

**Example:**

```bash
curl -X POST "http://localhost:8000/functions/v1/ecosense-ingest?days_back=7" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
```

#### Shared Utilities

`_shared/` directory contains reusable modules:

- `database.ts` - Supabase client initialization
- `aquarius.ts` - Aquarius API client
- `validators.ts` - Authentication helpers

### REST API

Auto-generated by PostgREST, accessible at `http://localhost:8000/rest/v1/`

**Example queries:**

```bash
# Get all species
curl "http://localhost:8000/rest/v1/species" \
  -H "apikey: $ANON_KEY"

# Get trees with species information
curl "http://localhost:8000/rest/v1/trees?select=*,species(*)" \
  -H "apikey: $ANON_KEY"

# Filter trees by location
curl "http://localhost:8000/rest/v1/trees?locationid=eq.4" \
  -H "apikey: $ANON_KEY"

# Create new location
curl -X POST "http://localhost:8000/rest/v1/locations" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"locationname":"New Plot","latitude":48.0,"longitude":8.0}'
```

**Accessible Schemas:**
Set in `docker/.env` via `PGRST_DB_SCHEMAS`:

```
shared,pointclouds,trees,sensor,environments,imagery
```

### Authentication

Two API keys (in `docker/.env`):

- **ANON_KEY** - Public key, limited to SELECT operations and RLS policies
- **SERVICE_ROLE_KEY** - Admin key, bypasses RLS, used for data imports and edge functions

### Row-Level Security (RLS)

PostgreSQL policies enforce access control at database layer:

- Implemented in `20-rls-policies.sql`
- All API requests respect RLS regardless of client
- Prevents unauthorized data access

## Data Interaction Patterns

### Importing Data

**Python Import Scripts:**
Located in `scripts/import/`:

```bash
# Setup
cd scripts
conda env create -f environment.yml
conda activate digital-twin

# Import tree data from EcoSense
python scripts/import/import_ecosense.py

# Import sensor data from Aquarius API
python scripts/import/import_sensor_data.py

# Link sensors to nearby trees
python scripts/import/link_sensors_to_trees.py

# Sync latest sensor readings
python scripts/import/sync_aquarius.py
```

**Features:**

- Automatic coordinate transformation (any CRS → WGS84)
- Species name/code matching via database lookups
- Location lookup and validation
- Audit trail via CreatedBy field

### Querying Data

**Via REST API:**

```bash
# Get trees at specific location with species
curl "http://localhost:8000/rest/v1/trees?locationid=eq.4&select=*,species(commonname)" \
  -H "apikey: $ANON_KEY" | jq
```

**Via psql (direct database access):**

```bash
docker exec -it dftdb-db psql -U postgres

# List all species
SELECT commonname, scientificname FROM shared.species;

# Find trees by species
SELECT t.variantid, t.height_m, s.commonname
FROM trees.trees t
JOIN shared.species s ON t.speciesid = s.speciesid
WHERE s.commonname ILIKE '%Beech%';

# Check audit trail for trees
SELECT al.* FROM shared.auditlog al
JOIN shared.auditlog_trees at ON al.auditlogid = at.auditlogid
ORDER BY al.changedat DESC
LIMIT 10;
```

### Working with Geometry

**PostGIS Functions:**

```bash
# Distance between two points (in meters)
SELECT ST_Distance(
  'POINT(8.088 47.885)'::geography,
  'POINT(8.089 47.886)'::geography
) AS distance_m;

# Points within radius (1km)
SELECT variantid, height_m FROM trees.trees
WHERE ST_DWithin(
  position::geography,
  'POINT(8.088 47.885)'::geography,
  1000  -- 1000 meters
);

# Count trees in polygon
SELECT COUNT(*) FROM trees.trees
WHERE ST_Contains(
  (SELECT boundary FROM shared.locations WHERE locationid = 4),
  position
);
```

## Configuration

### Environment Variables

Key variables in `docker/.env`:

**Database:**

- `POSTGRES_PASSWORD` - Database password
- `PGRST_DB_SCHEMAS` - Schemas exposed via REST API

**Security:**

- `JWT_SECRET` - Token signing secret
- `ANON_KEY` - Public API key
- `SERVICE_ROLE_KEY` - Admin API key
- `SECRET_KEY_BASE` - Session encryption

**External Services:**

- `AQUARIUS_HOSTNAME`, `AQUARIUS_USERNAME`, `AQUARIUS_PASSWORD` - EcoSense API credentials

**Access:**

- `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD` - Supabase Studio login
- `SUPABASE_PUBLIC_URL` - External URL for Studio

## Database Initialization

Migrations run automatically when database starts. Located in `docker/volumes/db/init/`:

| File | Purpose |
|------|---------|
| `10-enable-postgis.sql` | PostGIS extension setup |
| `11-shared-schema.sql` | Reference tables (locations, species, campaigns, etc.) |
| `12-pointclouds-schema.sql` | Point cloud tables |
| `13-trees-schema.sql` | Tree measurement tables |
| `14-sensor-schema.sql` | Sensor infrastructure |
| `15-environments-schema.sql` | Environmental conditions |
| `16-sensor-tree-links-schema.sql` | Sensor-tree relationships |
| `17-imagery-schema.sql` | Aerial & ground imagery |
| `20-rls-policies.sql` | Security policies and triggers |
| `21-audit-functions.sql` | Change tracking |
| `22-aquarius-integration.sql` | Aquarius API support |
| `23-processing-jobs.sql` | Workflow tracking |
| `24-public-api-views.sql` | Public API views with CRUD triggers |
| `30-load-lookup-tables.sql` | Reference data from CSVs |
| `31-refresh-lookup-functions.sql` | Lookup table refresh functions |

## Common Operations

### Start/Stop Stack

```bash
cd docker
docker compose up -d      # Start services
docker compose down       # Stop services
docker compose ps         # Check status
docker compose logs -f    # View logs
```

### Database Access

```bash
# Direct PostgreSQL access
docker exec -it dftdb-db psql -U postgres

# List schemas
\dn

# List tables in schema
\dt shared.*

# Query data
SELECT * FROM shared.species;
```

### Resetting Database

```bash
# Full reset via Python script (removes all data)
python scripts/admin/reset_database.py

# Or manually:
cd docker
docker compose down -v --remove-orphans
sudo rm -rf volumes/db/data
docker compose up -d
```

### Checking Imports

```bash
# Count trees by importer
docker exec -it dftdb-db psql -U postgres -c \
  "SELECT createdby, COUNT(*) FROM trees.trees GROUP BY createdby;"

# Check recent audit entries
docker exec -it dftdb-db psql -U postgres -c \
  "SELECT fieldname, COUNT(*) FROM shared.auditlog GROUP BY fieldname ORDER BY count DESC;"
```

## Next Steps

- **New to the system?** Start with [supabase-introduction.md](supabase-introduction.md)
- **Setting up locally?** Follow [deployment-guide.md](deployment-guide.md)
- **Need quick API examples?** See [api-quick-reference.md](api-quick-reference.md)
- **Troubleshooting?** Check [troubleshooting.md](troubleshooting.md)
- **View full schema in diagram?** Open [database-erd.dbml](database-erd.dbml) at [dbdiagram.io](https://dbdiagram.io/)
