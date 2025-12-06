# Introduction to Supabase

This guide explains what Supabase is and how it's used in the XR Future Forests Lab project.

---

## What is Supabase?

**Supabase** is an open-source platform that provides everything you need to build a database-backed application without writing backend code. Think of it as a complete "backend-in-a-box" that runs in Docker containers.

### Why Supabase?

Instead of manually setting up:
- A database server (PostgreSQL)
- An API server (to let applications talk to the database)
- An authentication system (for user logins)
- File storage (for large files)
- Real-time updates (for live data)

...Supabase provides all of this pre-configured and working together.

---

## Core Components

### 1. PostgreSQL Database

**What is it?**
PostgreSQL is a powerful, open-source relational database. Think of it like Excel on steroids - data is organized in tables with rows and columns, but it can handle millions of rows, complex relationships, and advanced queries.

**What we use it for:**
- Storing tree measurements
- Recording sensor data
- Managing point cloud metadata
- Tracking location information

**PostGIS Extension:**
We also use PostGIS, which adds geographic/spatial capabilities to PostgreSQL. This allows us to:
- Store coordinates and boundaries
- Query trees within a specific area
- Calculate distances between locations
- Work with 3D spatial data

### 2. Auto-Generated REST API (PostgREST)

**What is an API?**
An API (Application Programming Interface) is like a waiter in a restaurant:
- You (the application) tell the waiter (API) what you want
- The waiter goes to the kitchen (database) and gets it
- The waiter brings back your food (data)

**How it works in Supabase:**
For every table in your database, Supabase automatically creates API endpoints:

```
Database Table: species
↓
Auto-generated API: http://localhost:54321/rest/v1/species
```

**Example - Get all tree species:**
```bash
curl "http://localhost:54321/rest/v1/species?select=*"
```

**Example - Get trees in a specific location:**
```bash
curl "http://localhost:54321/rest/v1/trees?locationid=eq.15"
```

No need to write API code! Supabase generates it all from your database schema.

### 3. Authentication (GoTrue)

**What is it?**
A built-in system for managing users, logins, and permissions.

**Row-Level Security (RLS):**
You can set rules like:
- "Users can only see their own data"
- "Admins can edit everything"
- "Anonymous users can only read public data"

These rules are enforced at the database level, making them very secure.

### 4. Real-time Subscriptions

**What is it?**
Instead of repeatedly asking "has the data changed?", you can subscribe to changes and get notified automatically.

**Example use case:**
- Multiple researchers viewing the same plot data
- When one person adds a tree measurement, everyone else sees it instantly
- No need to refresh the page

### 5. Storage API

**What is it?**
A system for storing and managing large files (like point cloud LiDAR scans).

**How we use it:**
- Point cloud files are too large to store in the database
- They're stored in S3-compatible storage (like AWS S3 or MinIO)
- The database stores just the file path: `s3://bucket/scan.las`
- The Storage API provides secure, temporary download URLs

### 6. Edge Functions

**What is it?**
Serverless functions that run custom business logic. Written in TypeScript/JavaScript using Deno.

**Example use case:**
```javascript
// Edge Function: Generate presigned S3 URL
export async function handler(req) {
  const { filePath } = await req.json()
  const url = await generatePresignedURL(filePath, 3600) // 1 hour expiry
  return new Response(JSON.stringify({ url }))
}
```

---

## Database Migrations

**What are migrations?**
Migrations are SQL files that define your database structure. They're like a recipe for building your database.

**Where are they?**
`supabase/migrations/` folder:
```
001_shared_schema.sql       # Create reference tables
002_pointclouds_schema.sql  # Create point cloud tables
003_trees_schema.sql        # Create tree measurement tables
...
```

**How do they work?**
1. When you start the database for the first time, migrations run automatically
2. They create all tables, relationships, and initial data
3. If you need to change the schema later, you create a new migration file

**Example migration:**
```sql
-- 010_add_new_column.sql
ALTER TABLE trees.trees
ADD COLUMN crown_diameter_m DECIMAL(5,2);

COMMENT ON COLUMN trees.trees.crown_diameter_m IS 'Crown diameter in meters';
```

**Why use migrations?**
- **Version control**: Your database structure is in git
- **Reproducible**: Everyone on the team gets the same database structure
- **Documented**: Each change has a clear purpose
- **Reversible**: You can roll back changes if needed

---

## Access Rights and Security

### API Keys

There are two types of API keys:

**1. Anonymous Key (SUPABASE_ANON_KEY)**
- Safe to use in client applications (R scripts, web apps, Python notebooks)
- Subject to Row-Level Security policies
- Can only access what the RLS rules allow
- Example: "anonymous users can read public data but not modify it"

**2. Service Role Key (SUPABASE_SERVICE_ROLE_KEY)**
- NEVER expose in client applications!
- Bypasses all security rules
- Only use server-side (in Edge Functions, backend scripts)
- Example: For admin tasks, data imports, backups

### Row-Level Security (RLS) Policies

RLS policies are SQL rules that control data access:

```sql
-- Example: Users can only see their own trees
CREATE POLICY "Users see own trees"
ON trees.trees
FOR SELECT
USING (auth.uid() = user_id);

-- Example: Anyone can read species reference data
CREATE POLICY "Public species read"
ON shared.species
FOR SELECT
USING (true);
```

**Benefits:**
- Security enforced at database level (can't be bypassed)
- Same rules apply whether accessing via API, SQL, or dashboard
- Fine-grained control (row-by-row, column-by-column)

---

## How Everything Connects

```
┌─────────────────┐
│  Your R Script  │
└────────┬────────┘
         │ HTTP Request
         ↓
┌─────────────────┐
│   Kong Gateway  │ ← Checks API key
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│    PostgREST    │ ← Converts HTTP → SQL
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│   PostgreSQL    │ ← Checks RLS policies → Returns data
└─────────────────┘
```

**Step by step:**
1. Your R script sends an HTTP request with an API key
2. Kong checks if the API key is valid
3. PostgREST translates your request into a SQL query
4. PostgreSQL checks RLS policies (can this user access this data?)
5. If allowed, data is returned as JSON
6. Your R script receives the data

---

## Practical Examples

### Query data from R

```r
library(httr)

# Your API key from .env file
api_key <- "eyJhbGci..."

# Get all beech trees
response <- GET(
  "http://localhost:54321/rest/v1/trees",
  query = list(speciesid = "eq.1"),  # Filter: species ID = 1
  add_headers(
    apikey = api_key,
    Authorization = paste("Bearer", api_key)
  )
)

trees <- content(response)
print(trees)
```

### Query data from Python

```python
from supabase import create_client

# Initialize client
supabase = create_client(
    "http://localhost:54321",
    "your-anon-key"
)

# Get trees with related species info
response = supabase.table('trees') \
    .select('*, species(commonname, scientificname)') \
    .eq('locationid', 15) \
    .execute()

print(response.data)
```

### Insert data using SQL

```sql
-- Connect to database
-- docker exec -it xr_forests_db psql -U postgres

-- Insert a new tree
INSERT INTO trees.trees (
    locationid,
    speciesid,
    dbh_cm,
    height_m,
    latitude,
    longitude
) VALUES (
    15,
    1,  -- Beech
    42.5,
    28.3,
    48.0,
    8.0
);
```

---

## Common Operations

### View your data

1. Open Supabase Studio: http://localhost:54323
2. Click "Table Editor"
3. Select a schema (shared, trees, etc.)
4. Click on a table to view/edit data

### Run a custom query

1. Click "SQL Editor" in Studio
2. Write your query:
```sql
SELECT
    l.locationname,
    COUNT(t.variantid) as tree_count
FROM trees.trees t
JOIN shared.locations l ON t.locationid = l.locationid
GROUP BY l.locationname;
```
3. Click "Run" or press Ctrl+Enter

### Add a new column

1. Create a new migration file: `supabase/migrations/011_add_column.sql`
2. Write the SQL:
```sql
ALTER TABLE trees.trees
ADD COLUMN health_status TEXT CHECK (health_status IN ('healthy', 'stressed', 'dead'));
```
3. Restart the database: `docker compose restart db`

### Check access policies

```sql
-- View all RLS policies
SELECT schemaname, tablename, policyname, permissive, roles, qual
FROM pg_policies
WHERE schemaname = 'trees';
```

---

## Troubleshooting

**Problem: API returns 401 Unauthorized**
- Check your API key is correct (from .env file)
- Make sure you're using BOTH `apikey` header AND `Authorization` header

**Problem: API returns empty results**
- Check RLS policies - might be blocking access
- Verify data exists: check in Studio or with SQL

**Problem: Can't connect to database**
- Ensure Docker is running: `docker compose ps`
- Check database is healthy: `docker compose ps db`

---

## Learn More

- **[Supabase Documentation](https://supabase.com/docs)** - Official docs
- **[PostgREST API](https://postgrest.org/)** - API query syntax
- **[PostgreSQL Documentation](https://www.postgresql.org/docs/)** - SQL reference
- **[PostGIS Documentation](https://postgis.net/docs/)** - Spatial queries

---

**Next Steps:**
1. Try querying data from Supabase Studio
2. Make a test API request from R or Python
3. Explore the database schema in `docs/architecture/database.md`
4. Read about migrations in `supabase/migrations/README.md`
