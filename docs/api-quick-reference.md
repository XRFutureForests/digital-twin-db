# Supabase Quick Reference - Digital Twin Project

## 🌐 Access URLs (Use from Windows)

| Service | URL | Purpose |
|---------|-----|---------|
| **Supabase Studio** | http://172.17.200.223:54323 | Database management UI |
| **REST API** | http://172.17.200.223:54321 | API Gateway (Kong) |
| **Database Direct** | 172.17.200.223:54322 | PostgreSQL connection |

## 🔑 API Keys

```bash
# Anonymous Key (use in client applications - public)
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzYwNTE3MzI3LCJleHAiOjIwNzU4NzczMjd9.lIi-KdAxFeBpXYR5jdKJA-vJfZ0eL9y0n7Lx4mUYNv8

# Service Role Key (use server-side only - KEEP SECRET!)
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE3NjA1MTczMjcsImV4cCI6MjA3NTg3NzMyN30.SBbtSD8usWyQNSuOZYPFLdJ0SJh2i77fUMLZkeA0DDc

# JWT Secret (for token verification)
SUPABASE_JWT_SECRET=ihoCUZVDMY+OSlgFoMCmjsEidbo5BtCK6i4kBsecm3c=
```

## 🗄️ Database Credentials

```
Host: 172.17.200.223
Port: 54322
Database: postgres
Username: postgres
Password: postgres
```

### Connect with psql (from WSL2)
```bash
psql -h localhost -p 54322 -U postgres
```

### Connect from Windows (using pgAdmin or DBeaver)
Use the credentials above with host `172.17.200.223`

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
curl "http://172.17.200.223:54321/rest/v1/soiltypes?select=*" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzYwNTE3MzI3LCJleHAiOjIwNzU4NzczMjd9.lIi-KdAxFeBpXYR5jdKJA-vJfZ0eL9y0n7Lx4mUYNv8" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzYwNTE3MzI3LCJleHAiOjIwNzU4NzczMjd9.lIi-KdAxFeBpXYR5jdKJA-vJfZ0eL9y0n7Lx4mUYNv8"

# Create a new location
curl -X POST "http://172.17.200.223:54321/rest/v1/locations" \
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
  'http://172.17.200.223:54321',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzYwNTE3MzI3LCJleHAiOjIwNzU4NzczMjd9.lIi-KdAxFeBpXYR5jdKJA-vJfZ0eL9y0n7Lx4mUYNv8'
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
    "http://172.17.200.223:54321",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzYwNTE3MzI3LCJleHAiOjIwNzU4NzczMjd9.lIi-KdAxFeBpXYR5jdKJA-vJfZ0eL9y0n7Lx4mUYNv8"
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
cd ~/git/digital-twin
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
docker exec -it xr_forests_db psql -U postgres
```

### Stop and remove all data (⚠️ DESTRUCTIVE)
```bash
docker compose down -v
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

### Can't connect from Windows
```bash
# Get current WSL2 IP (run in WSL2)
hostname -I

# Update your URLs with the new IP
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
sudo lsof -i :54322

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
- `.env` - Environment variables (JWT keys, passwords, ports)
- `docker compose.yml` - Service definitions
- `supabase/migrations/` - Database schema migrations
- `supabase/kong.yml` - API Gateway configuration

**Note**: Never commit `.env` to git - it contains secrets!

## 🎯 Next Steps

1. ✅ Access Studio at http://172.17.200.223:54323
2. Explore the Table Editor to see your data
3. Try running SQL queries in the SQL Editor
4. Test the REST API with curl or from your application
5. Read the [README.md](README.md) for project-specific information

---

**For detailed WSL2 networking help, see [WSL2_ACCESS_GUIDE.md](WSL2_ACCESS_GUIDE.md)**
