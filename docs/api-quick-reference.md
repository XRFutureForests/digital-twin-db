# Supabase Quick Reference - Digital Twin Project

## 🌐 Access URLs

| Service | URL | Purpose |
|---------|-----|---------|
| **Supabase Studio** | <http://localhost:54323> | Database management UI |
| **REST API** | <http://localhost:8000/rest/v1> | API Gateway (Kong) |
| **Database Direct** | localhost:5432 | PostgreSQL connection (via pooler) |

## 🔑 API Keys

Get your keys from `docker/.env`:

```bash
# Anonymous Key (use in client applications - public)
# Find ANON_KEY in your .env file

# Service Role Key (use server-side only - KEEP SECRET!)
# Find SERVICE_ROLE_KEY in your .env file
```

## 🗄️ Database Credentials

```
Host: localhost
Port: 5432
Database: postgres
Username: postgres
Password: (from POSTGRES_PASSWORD in docker/.env)
```

### Connect with psql

```bash
# From within Docker network
docker exec -it dftdb-db psql -U postgres

# Or via pooler
psql -h localhost -p 5432 -U postgres
```

### Connect from external clients (pgAdmin, DBeaver)

Use the credentials above with host `localhost` and port `5432`

## 📊 Database Schemas

Your database has these schemas:

| Schema | Purpose | Tables |
|--------|---------|--------|
| **shared** | Reference data | SoilTypes, ClimateZones, Species, Locations, Scenarios, Processes |
| **pointclouds** | LiDAR data | PointClouds (with S3 file paths) |
| **trees** | Tree measurements | Trees, Stems, TreeSimulations |
| **sensor** | IoT sensors | Sensors, SensorReadings |
| **environments** | Environmental data | EnvironmentalConditions |
| **auth** | Supabase auth | (managed by Supabase) |
| **storage** | File storage | (managed by Supabase) |
| **realtime** | Realtime subscriptions | (managed by Supabase) |

## 🔌 REST API Examples

### Using curl

```bash
# Get all soil types
curl "http://localhost:8000/rest/v1/soiltypes?select=*" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY"

# Create a new location
curl -X POST "http://localhost:8000/rest/v1/locations" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"locationname":"Test Plot","latitude":48.0,"longitude":8.0}'
```

### Using JavaScript (Browser or Node.js)

```javascript
// Install: npm install @supabase/supabase-js

import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'http://localhost:8000',
  'YOUR_ANON_KEY'  // from docker/.env
)

// Query data
const { data, error } = await supabase
  .from('soiltypes')
  .select('*')

// Insert data
const { data, error } = await supabase
  .from('locations')
  .insert({ locationname: 'Test Plot', latitude: 48.0, longitude: 8.0 })
```

### Using Python

```python
# Install: pip install supabase

from supabase import create_client

supabase = create_client(
    "http://localhost:8000",
    "YOUR_ANON_KEY"  # from docker/.env
)

# Query data
response = supabase.table('soiltypes').select('*').execute()

# Insert data
response = supabase.table('locations').insert({
    'locationname': 'Test Plot',
    'latitude': 48.0,
    'longitude': 8.0
}).execute()
```

## 🚀 Docker Commands

### Start all services

```bash
cd docker
docker compose up -d
```

### Stop all services

```bash
docker compose down
```

### View service status

```bash
docker compose ps
```

### View logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f studio
docker compose logs -f db
docker compose logs -f kong
```

### Restart a service

```bash
docker compose restart studio
docker compose restart kong
```

### Access database shell

```bash
docker exec -it dftdb-db psql -U postgres
```

### Stop and remove all data (⚠️ DESTRUCTIVE)

```bash
docker compose down -v
sudo rm -rf volumes/db/data
```

## 📝 Common Tasks in Studio

### 1. Browse Tables

- Click on "Table Editor" in left sidebar
- Select schema (shared, trees, etc.)
- View and edit data

### 2. Run SQL Queries

- Click on "SQL Editor" in left sidebar
- Write your SQL
- Click "Run" or press Ctrl+Enter

### 3. View Database Structure

- Click on "Database" in left sidebar
- Explore schemas, tables, columns, relationships

### 4. Check API Docs

- Click on "API" in left sidebar
- See auto-generated REST endpoints for your tables

## 🔧 Troubleshooting

### Services won't start

```bash
# Check logs
docker compose logs

# Restart everything
docker compose down
docker compose up -d
```

### Database connection refused

```bash
# Check if database is healthy
docker compose ps db

# View database logs
docker compose logs db
```

### Port already in use

```bash
# See what's using the port
sudo lsof -i :8000
sudo lsof -i :5432

# Or stop other Docker containers
docker ps
docker stop <container-id>
```

## 📚 Documentation Links

- [Supabase Docs](https://supabase.com/docs)
- [PostgREST API](https://postgrest.org/en/stable/)
- [PostgreSQL Docs](https://www.postgresql.org/docs/)
- [PostGIS Docs](https://postgis.net/documentation/)

## ⚙️ Environment Files

Your configuration is in:

- `docker/.env` - Environment variables (JWT keys, passwords, ports)
- `docker/docker-compose.yml` - Service definitions
- `docker/volumes/db/init/` - Database schema initialization
- `docker/volumes/api/kong.yml` - API Gateway configuration

**Note**: Never commit `.env` to git - it contains secrets!

## 🎯 Next Steps

1. ✅ Access Studio at <http://localhost:54323>
2. Explore the Table Editor to see your data
3. Try running SQL queries in the SQL Editor
4. Test the REST API with curl or from your application
5. Read the [README.md](../README.md) for project-specific information

---

**For detailed troubleshooting help, see [troubleshooting.md](troubleshooting.md)**
