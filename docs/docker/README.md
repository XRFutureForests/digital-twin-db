# Supabase Docker - forest digital twin projects

This directory contains the official Supabase Docker Compose setup, customized for the forest digital twin projects digital twin database.

## What's Inside

This setup provides a complete, self-hosted Supabase stack with:

- **PostgreSQL 15 + PostGIS** - Spatial database with custom forest schemas
- **PostgREST** - Auto-generated REST APIs
- **GoTrue** - Authentication service
- **Realtime** - WebSocket subscriptions
- **Storage API** - File management
- **Kong Gateway** - API routing and security
- **Supabase Studio** - Web-based database management UI
- **Edge Functions** - Deno-based serverless functions
- **Analytics** - Logging and monitoring

## Quick Start

### 1. Configuration

The `.env` file contains all configuration. It's already set up with secure credentials.

**Key settings for this project:**

```bash
# Custom schemas exposed through REST API
PGRST_DB_SCHEMAS=public,storage,graphql_public,shared,pointclouds,trees,sensor,environments

# Access ports
KONG_HTTP_PORT=8000          # API Gateway
KONG_HTTPS_PORT=8443         # API Gateway (SSL)
POSTGRES_PORT=5432           # Database (via Supavisor pooler)
```

### 2. Start Services

```bash
cd docker

# Start all services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

All services should show as "healthy" after about 30 seconds.

### 3. Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| **Studio UI** | <http://localhost:54323> | Username: `supabase`; Password: (from `.env`) |
| **REST API** | <http://localhost:8000/rest/v1> | API Key: (from `.env` ANON_KEY) |
| **PostgreSQL** | localhost:5432 | User: `postgres.{POOLER_TENANT_ID}`; Password: (from `.env`) |

### 4. Custom Database Initialization

The forest database schemas are automatically initialized via SQL files in `volumes/db/init/`:

| File | Purpose |
|------|---------|
| `10-enable-postgis.sql` | Enable PostGIS extension |
| `11-shared-schema.sql` | Species, locations, soil, climate |
| `12-pointclouds-schema.sql` | LiDAR data management |
| `13-trees-schema.sql` | Tree measurements with dual geometry support |
| `14-sensor-schema.sql` | IoT sensor data with dual geometry support |
| `15-environments-schema.sql` | Environmental conditions |
| `16-rls-policies.sql` | Row-level security |
| `17-audit-functions.sql` | Change tracking |
| `18a-seed-lookup-data.sql` | Species lookup data |
| `18b-seed-sample-locations.sql` | Sample locations for testing |
| `19-mathisle-seed-data.sql` | Mathisle data seeding |
| `20-mathisle-tree-import.sql` | Mathisle tree data import |
| `21-aquarius-integration.sql` | Aquarius time series API integration |
| `22-link-sensors-to-trees.sql` | Associate sensors with tree measurements |
| `23-processing-jobs.sql` | External workflow job tracking |
| `24-public-api-views.sql` | Public API views |
| `25-seed-aquarius-data.sql` | Aquarius data seeding |

These run automatically when the database is first initialized.

**Data Import**: The database initializes with minimal reference data only. To import tree inventory and sensor data, use the interactive Jupyter notebooks:

```bash
cd ../scripts
conda env create -f environment.yml  # One-time setup
conda activate digital-twin
jupyter notebook  # Open import_trees.ipynb
```

See [`scripts/README.md`](../../scripts/README.md) for detailed import instructions.

## Common Operations

### View Service Status

```bash
docker compose ps
```

### Stop Services

```bash
docker compose down
```

### Restart a Single Service

```bash
docker compose restart rest      # Restart PostgREST
docker compose restart realtime  # Restart Realtime
docker compose restart studio    # Restart Studio UI
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f db
docker compose logs -f rest
docker compose logs -f kong
```

### Access Database Console

```bash
# Via Docker (direct container access)
docker exec -it dftdb-db psql -U postgres

# Then run SQL:
\dn                              # List schemas
\dt shared.*                     # List tables in shared schema
SELECT * FROM shared.species;    # Query data
```

### Connecting from Host Machine

The database is exposed through Supavisor connection pooler on port 5432. You must use the tenant ID format for the username:

```bash
# Connection format (replace with values from .env)
psql 'postgres://postgres.digital-forest-twin-local:YOUR_PASSWORD@localhost:5432/postgres'

# Or with environment variables
source .env
PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 \
  -U "postgres.$POOLER_TENANT_ID" -d postgres
```

**Important**: When connecting through Supavisor (port 5432), the username must be `postgres.{POOLER_TENANT_ID}` (e.g., `postgres.digital-forest-twin-local`).

### Reset Everything

```bash
# Stop and remove all containers and volumes
docker compose down -v

# Start fresh
docker compose up -d
```

## Environment Variables

The `.env` file is organized into sections:

### Security Critical (MUST be unique in production)

- `POSTGRES_PASSWORD` - Database password
- `JWT_SECRET` - Token signing secret
- `ANON_KEY` - Public API key (signed with JWT_SECRET)
- `SERVICE_ROLE_KEY` - Admin API key (signed with JWT_SECRET)
- `SECRET_KEY_BASE` - Session encryption
- `VAULT_ENC_KEY` - Vault encryption (32+ chars)
- `PG_META_CRYPTO_KEY` - Metadata encryption (32+ chars)

### Database Configuration

- `POSTGRES_HOST=db` - Database container name
- `POSTGRES_PORT=5432` - Internal port
- `POSTGRES_DB=postgres` - Database name

### API Configuration

- `PGRST_DB_SCHEMAS` - **IMPORTANT**: Schemas exposed via REST API
  - Must include: `shared,pointclouds,trees,sensor,environments`

### Access Configuration

- `DASHBOARD_USERNAME=supabase` - Studio UI username
- `DASHBOARD_PASSWORD` - Studio UI password
- `SUPABASE_PUBLIC_URL` - External URL for Studio

## Architecture

### Service Dependencies

```text
                   ┌─────────────┐
                   │   Studio    │  (Web UI)
                   └──────┬──────┘
                          │
                   ┌──────▼──────┐
                   │    Kong     │  (API Gateway)
                   └──────┬──────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
    ┌────▼────┐     ┌────▼────┐     ┌────▼────┐
    │  Auth   │     │  REST   │     │ Storage │
    │ (GoTrue)│     │(PostgREST)│   │   API   │
    └────┬────┘     └────┬────┘     └────┬────┘
         │               │               │
         └───────────────┼───────────────┘
                         │
                  ┌──────▼──────┐
                  │ PostgreSQL  │
                  │  + PostGIS  │
                  └─────────────┘
```

### Port Mapping

| Internal | External | Service |
|----------|----------|--------|
| 3000 | 54323 | Studio UI |
| 8000 | 8000 | Kong Gateway (HTTP) |
| 8443 | 8443 | Kong Gateway (HTTPS) |
| 5432 | 5432 | PostgreSQL (via Supavisor pooler) |
| 4000 | 4000 | Analytics |

## Customization for Forest Database

This setup differs from the official Supabase Docker in these ways:

1. **Custom Schemas Exposed**: Added forest schemas to `PGRST_DB_SCHEMAS`
2. **PostGIS Enabled**: Automatically enabled in initialization
3. **Forest Schema Migrations**: Custom SQL files in `volumes/db/init/`
4. **Dual Geometry Support**: Both original CRS and WGS84 coordinates stored
5. **Edge Functions**: Deno functions for ecosense sensor data sync
6. **Manual Data Import**: CSV importer with audit trail and coordinate transformation
7. **Studio Port**: Exposed on port 54323 for WSL/Windows compatibility

## Troubleshooting

### Database Container Shows Unhealthy

The database takes 30-60 seconds to initialize on first startup. This is normal.

```bash
# Monitor initialization
docker compose logs -f db

# Wait for all 4 health checks to pass
docker compose ps db

# If it fails after 2+ minutes, check for errors
docker compose logs db | tail -30
```

**Common database initialization issues:**

1. **Port already in use**: Another service is using port 5432

   ```bash
   sudo lsof -i :5432
   ```

2. **Insufficient disk space**: Less than 1GB free

   ```bash
   df -h
   ```

3. **Docker resource limits**: Set at least 4GB RAM in Docker Desktop settings

4. **File permissions**: On Linux, ensure write access to `volumes/db/data`

   ```bash
   sudo chown -R $USER:$USER volumes/db/data
   ```

### Service Won't Start

```bash
# Check logs for the specific service
docker compose logs [service-name]

# Common service names: db, auth, rest, realtime, storage, kong, studio
```

### Can't Access API

```bash
# Verify PostgREST is running and healthy
docker compose ps rest

# Check if custom schemas are exposed
grep PGRST_DB_SCHEMAS .env
# Should include: shared,pointclouds,trees,sensor,environments

# Restart PostgREST (after db is healthy)
docker compose restart rest
```

### Database Connection Failed

```bash
# Test database connectivity
docker exec dftdb-db psql -U postgres -c "SELECT version();"

# Check database health and wait for readiness
docker compose ps db
```

### Studio UI Not Accessible (WSL Users)

If running in WSL, the Studio UI might not be accessible from Windows browser:

1. Try `http://localhost:54323` first (usually works)
2. If that fails, get WSL IP: `ip addr show eth0 | grep inet`
3. Access via WSL IP: `http://172.x.x.x:54323`

### Services Keep Restarting

On first start, auth, realtime, and storage may restart 2-3 times while waiting for database initialization. This is normal—wait 3-5 minutes for stabilization.

```bash
# If restarting continues after 5 minutes:
docker compose restart auth realtime storage

# Check specific logs
docker compose logs auth
```

## Production Deployment

Before deploying to production:

1. **Generate new secrets**: All passwords, tokens, and encryption keys
2. **Update SMTP settings**: Configure real email service
3. **Set up SSL/TLS**: Use reverse proxy (nginx, Caddy, Traefik)
4. **Configure backups**: Regular backups of `volumes/db/data`
5. **Update firewall**: Only expose necessary ports
6. **Set DISABLE_SIGNUP=true**: Prevent public registrations

## Official Documentation

- [Supabase Self-Hosting Guide](https://supabase.com/docs/guides/hosting/docker)
- [Supabase Docker GitHub](https://github.com/supabase/supabase/tree/master/docker)
- [PostgREST Documentation](https://postgrest.org/)
- [Kong Gateway Docs](https://docs.konghq.com/)
