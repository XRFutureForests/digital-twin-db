# Digital Twin Repository - Data Tier Implementation with Supabase

> **Multi-Repository Architecture**: Data Tier of XR Future Forests Lab
> **University**: University of Freiburg, Department of Forest Sciences
> **Status**: Supabase Database Implementation | **Target**: August 15, 2025

This repository implements the **Data Tier** of the XR Future Forests Lab multi-repository architecture, providing the foundational database infrastructure using **Supabase** for creating **digital twins of forests** through immersive XR technologies.

## **Repository Role in XR Future Forests Lab**

### **🏗️ Data Tier Implementation with Supabase**

- **Supabase PostgreSQL + PostGIS**: Spatial database with forest-specific schemas
- **PostgREST Auto-generated APIs**: REST APIs automatically created from database schema
- **Real-time Subscriptions**: WebSocket support for live data updates
- **Row-Level Security**: Fine-grained access control policies
- **Edge Functions (Deno)**: Serverless business logic for processing workflows
- **S3 Integration**: Point cloud storage in external S3 buckets
- **Docker Deployment**: Complete containerized stack for VM deployment

### **🔗 Multi-Repository Architecture**

- **📋 [Planning Hub](../xr-future-forests-lab)**: Central coordination and architecture documentation
- **🌲 [The Grove](../the-grove)**: Logic Tier - Tree Asset Generation Service (consumes Tree API)
- **☁️ [Potree Docker](../potree-docker)**: Logic Tier - Point Cloud Processing Service (uses Point Cloud API)

## **Project Vision**

The XR Future Forests Lab represents a groundbreaking approach to forest science, combining cutting-edge technologies to create comprehensive digital forest ecosystems. This repository provides the data foundation using **Supabase** that enables:

### **Research Innovation**

- **Digital Forest Twins**: Complete digital replications of forest ecosystems with real-time data integration
- **Invisible Process Visualization**: Make hidden forest processes (sap flow, root competition, nutrient cycling) visible and interactive
- **Advanced Growth Modeling**: Integration with SILVA and other tree-based models for scientifically accurate forest simulation
- **Multi-scale Analysis**: Seamless exploration from individual tree characteristics to landscape-level dynamics
- **Field-Level Audit Logging**: Complete change tracking with user attribution for scientific reproducibility

### **Educational Excellence**

- **Immersive Learning**: Experience forest ecosystems in ways impossible in traditional field studies
- **Risk-free Training**: Practice forest management decisions in virtual environments before real-world application
- **Temporal Dynamics**: Visualize decades of forest change in accelerated time
- **Interactive Data Exploration**: Transform complex datasets into intuitive, engaging learning experiences

### **Stakeholder Engagement**

- **Policy Communication**: Translate complex forest research into accessible visualizations for decision-makers
- **Public Outreach**: Make forest science engaging and understandable for broader audiences
- **Interdisciplinary Collaboration**: Bridge forest science with technology, education, and policy domains
- **Industry Partnerships**: Develop practical tools for modern forest management

## **Documentation & Architecture**

Complete system documentation is available in the `docs/` directory:

- **[System Architecture](./docs/architecture/architecture.md)** - Three-tier architecture with Supabase
- **[Database Design](./docs/architecture/database.md)** - Schema specifications and ERD
- **[Tech Stack](./docs/tech-stack.md)** - Supabase technology overview
- **[API Architecture](./docs/architecture/api.md)** - PostgREST API interfaces
- **[Supabase Setup Guide](./docs/supabase/setup-guide.md)** - Docker deployment instructions
- **[S3 Integration](./docs/supabase/s3-integration.md)** - Point cloud storage configuration

## **System Architecture with Supabase**

The Data Tier runs a complete **Supabase stack** via Docker Compose, providing unified data infrastructure for the entire XR Future Forests Lab:

### **Core Services**

- **PostgreSQL + PostGIS** (`db:5432`) - Spatial database with 5 forest-specific schemas
- **PostgREST** (`rest:3000`) - Auto-generated REST API from database schema
- **Kong API Gateway** (`kong:8000`) - API routing and authentication (replaces nginx)
- **Supabase Auth** (`auth:9999`) - Built-in authentication with JWT
- **Realtime Server** (`realtime:4000`) - WebSocket subscriptions for live updates
- **Storage API** (`storage:5000`) - S3-compatible storage (connects to external S3)
- **Edge Functions** (`functions:9000`) - Deno-based serverless functions
- **Supabase Studio** (`studio:3000`) - Web-based database management UI

### **No Custom Backend Required**

Unlike traditional FastAPI/Flask backends, Supabase provides:
- ✅ Automatic REST API generation from PostgreSQL schemas
- ✅ Built-in authentication and row-level security
- ✅ Real-time subscriptions without Redis
- ✅ Serverless Edge Functions for business logic
- ✅ Connection pooling and query optimization
- ✅ Visual database management (Studio)

## **Database Schemas**

Five specialized PostgreSQL schemas organize forest data:

1. **shared** - Reference tables (Species, Locations, Scenarios, Processes, AuditLog)
2. **pointclouds** - LiDAR scan metadata (S3 file paths, processing variants)
3. **trees** - Tree measurements and simulations (multi-stem support, growth variants)
4. **sensor** - Environmental monitoring (sensor installations, time-series readings)
5. **environments** - Environmental conditions (sensor-derived, user-defined, model outputs)

All schemas support **variant-based versioning** and **field-level audit logging**.

## **API Access Patterns**

### **PostgREST Auto-generated Endpoints**

All database tables automatically expose REST endpoints:

```bash
# Get all trees at a location
GET /rest/v1/Trees?LocationID=eq.15&select=*,Species(*)

# Get point clouds with processing status
GET /rest/v1/PointClouds?ProcessingStatus=eq.completed

# Get sensor readings (time-series)
GET /rest/v1/SensorReadings?Timestamp=gte.2024-01-01&SensorID=eq.301

# Create new tree measurement
POST /rest/v1/Trees
```

### **Real-time Subscriptions**

```javascript
// Subscribe to tree updates
const subscription = supabase
  .channel('trees-changes')
  .on('postgres_changes',
    { event: '*', schema: 'trees', table: 'Trees' },
    (payload) => console.log('Tree updated:', payload)
  )
  .subscribe()
```

### **Edge Functions**

```bash
# Generate S3 presigned URL for point cloud
POST /functions/v1/s3-presigned-url
{
  "file_path": "s3://xr-forests-pointclouds/plot-a/scan.las",
  "expiration_seconds": 3600
}
```

## **S3 Integration for Point Clouds**

Point cloud LiDAR files (.las, .laz) are stored in **external S3 buckets**:

- **Database stores**: S3 URIs (e.g., `s3://bucket-name/path/file.las`)
- **Access control**: RLS policies + presigned URLs via Edge Functions
- **File size**: Up to 2GB per file
- **Metadata**: Stored in `pointclouds.PointClouds` table

Benefits:
- ✅ Unlimited storage capacity
- ✅ Cost-effective for large files
- ✅ No database bloat
- ✅ Direct client downloads with presigned URLs
- ✅ Compatible with external processing tools

## **Quick Start**

### Prerequisites
- Docker and Docker Compose
- 8GB+ RAM recommended
- S3 bucket (AWS, MinIO, or compatible service)

### 1. Clone Repository
```bash
git clone https://github.com/your-org/digital-twin.git
cd digital-twin
```

### 2. Configure Environment

Create your environment file and generate secure keys:

```bash
cp .env.example .env
```

**⚠️ IMPORTANT**: You must generate secure keys before starting Supabase. See [Environment Configuration Guide](#environment-configuration-guide) below for detailed instructions on:
- Generating JWT secrets and API keys
- Testing vs Production configuration
- S3 bucket setup
- External service integration

### 3. Start Supabase Stack
```bash
docker-compose up -d
```

Services will be available at:
- **Supabase Studio**: http://localhost:54323 (Database management UI)
- **REST API**: http://localhost:54321/rest/v1
- **Auth API**: http://localhost:54321/auth/v1
- **Realtime**: http://localhost:54321/realtime/v1
- **Edge Functions**: http://localhost:54321/functions/v1
- **Direct PostgreSQL**: localhost:54322

### 4. Initialize Database
Migrations run automatically on first startup from `supabase/migrations/`:
- `001_shared_schema.sql` - Core reference tables
- `002_pointclouds_schema.sql` - LiDAR data structure
- `003_trees_schema.sql` - Tree measurements and simulations
- `004_sensor_schema.sql` - Environmental monitoring
- `005_environments_schema.sql` - Environmental conditions
- `006_rls_policies.sql` - Row-level security
- `007_audit_functions_triggers.sql` - Audit logging
- `008_seed_data.sql` - Sample forest data

### 5. Access Supabase Studio
Open http://localhost:54323 to:
- Explore database schemas
- Run SQL queries
- View table data
- Test API endpoints
- Monitor real-time subscriptions

## **Environment Configuration Guide**

### **Generating Required Keys and Secrets**

Supabase requires several cryptographically secure keys. Here's how to generate them:

#### **1. JWT Secret (SUPABASE_JWT_SECRET)**

This secret is used to sign and verify JWT tokens. Generate a 32-byte random secret:

```bash
# Using OpenSSL (recommended)
openssl rand -base64 32

# Using Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"

# Using Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

**Example output**: `your-super-secret-jwt-token-with-at-least-32-characters`

Copy this value to `.env`:
```env
SUPABASE_JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters
```

#### **2. Anonymous Key (SUPABASE_ANON_KEY)**

This key is used for public API access with RLS policies enforced. Generate using JWT with the secret:

**Option A: Using Supabase CLI** (Recommended):
```bash
# Install Supabase CLI
npm install -g supabase

# Generate keys automatically
supabase init
supabase start
# Keys will be displayed in terminal
```

**Option B: Using JWT.io**:
1. Go to https://jwt.io/
2. Select algorithm: **HS256**
3. Set payload:
```json
{
  "role": "anon",
  "iss": "supabase",
  "iat": 1704067200,
  "exp": 2019427200
}
```
4. Paste your JWT secret in "Verify Signature" section
5. Copy the generated JWT token

**Option C: Using Node.js**:
```javascript
const jwt = require('jsonwebtoken');
const secret = 'your-super-secret-jwt-token';

const anonKey = jwt.sign(
  {
    role: 'anon',
    iss: 'supabase',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (10 * 365 * 24 * 60 * 60) // 10 years
  },
  secret
);

console.log('ANON KEY:', anonKey);
```

Copy this value to `.env`:
```env
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
PUBLIC_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### **3. Service Role Key (SUPABASE_SERVICE_ROLE_KEY)**

This key bypasses RLS policies and should only be used server-side. Generate similar to anon key but with `service_role`:

```javascript
const jwt = require('jsonwebtoken');
const secret = 'your-super-secret-jwt-token';

const serviceRoleKey = jwt.sign(
  {
    role: 'service_role',
    iss: 'supabase',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (10 * 365 * 24 * 60 * 60)
  },
  secret
);

console.log('SERVICE ROLE KEY:', serviceRoleKey);
```

Copy this value to `.env`:
```env
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### **4. Database Password (POSTGRES_PASSWORD)**

Generate a strong password for PostgreSQL:

```bash
# Using OpenSSL
openssl rand -base64 24

# Using pwgen (if installed)
pwgen -s 32 1
```

Copy to `.env`:
```env
POSTGRES_PASSWORD=your_secure_db_password_here
SUPABASE_DB_PASSWORD=your_secure_db_password_here
```

### **Testing vs Production Configuration**

#### **🧪 Testing/Development Environment**

For local development and testing:

```env
# Development Environment
ENVIRONMENT=development

# Database (use default PostgreSQL password for local testing)
POSTGRES_PASSWORD=postgres
SUPABASE_DB_PASSWORD=postgres

# JWT Secret (generate once, reuse for local dev)
SUPABASE_JWT_SECRET=local-dev-secret-at-least-32-characters-long

# API Keys (generate using methods above)
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# API URLs (localhost)
API_EXTERNAL_URL=http://localhost:54321
PUBLIC_REST_URL=http://localhost:54321/rest/v1
SITE_URL=http://localhost:3000

# S3 Configuration (use MinIO or LocalStack for testing)
S3_ENDPOINT=http://localhost:9000  # MinIO local endpoint
S3_REGION=us-east-1
S3_BUCKET_NAME=test-pointclouds
S3_ACCESS_KEY_ID=minioadmin  # MinIO default
S3_SECRET_ACCESS_KEY=minioadmin  # MinIO default

# External Services (use mock endpoints or skip)
ECOSENSE_API_URL=http://localhost:8001  # Mock server
THREEDTREES_API_URL=http://localhost:8002  # Mock server
SILVA_MODEL_ENDPOINT=http://localhost:8003  # Mock server

# Logging (verbose for debugging)
LOG_LEVEL=debug
ENABLE_QUERY_LOGGING=true

# Auth (permissive for testing)
ENABLE_SIGNUP=true
JWT_EXPIRY=86400  # 24 hours
```

**What you DON'T need to change for testing**:
- ✅ Port numbers (54321, 54322, 54323) - defaults are fine
- ✅ Database name (`postgres`) - default is fine
- ✅ Storage backend - can use local filesystem
- ✅ External API keys - can mock or skip

**What you MUST change for testing**:
- ⚠️ JWT secret (generate once)
- ⚠️ API keys (generate from JWT secret)
- ⚠️ Database password (can use simple password for local)

#### **🚀 Production Environment**

For production deployment on VM server:

```env
# Production Environment
ENVIRONMENT=production

# Database (MUST use strong passwords)
POSTGRES_PASSWORD=<use 32+ character random password>
SUPABASE_DB_PASSWORD=<same as above>

# JWT Secret (MUST be cryptographically secure)
SUPABASE_JWT_SECRET=<use 32-byte random secret>

# API Keys (generated from production JWT secret)
SUPABASE_ANON_KEY=<generate with production JWT secret>
SUPABASE_SERVICE_ROLE_KEY=<generate with production JWT secret>

# API URLs (use your domain or IP)
API_EXTERNAL_URL=https://api.xrforests.your-domain.com
PUBLIC_REST_URL=https://api.xrforests.your-domain.com/rest/v1
SITE_URL=https://xrforests.your-domain.com

# S3 Configuration (use AWS S3 or compatible service)
S3_ENDPOINT=https://s3.amazonaws.com  # Or your S3 provider
S3_REGION=eu-central-1  # Choose region closest to VM
S3_BUCKET_NAME=xr-forests-production-pointclouds
S3_ACCESS_KEY_ID=<your AWS access key>
S3_SECRET_ACCESS_KEY=<your AWS secret key>

# External Services (real API endpoints)
ECOSENSE_API_URL=https://api.ecosense.com
ECOSENSE_API_KEY=<actual API key>
THREEDTREES_API_URL=https://api.3dtrees.com
THREEDTREES_API_KEY=<actual API key>
SILVA_MODEL_ENDPOINT=https://silva-model.your-domain.com
SILVA_MODEL_API_KEY=<actual API key>

# Logging (less verbose for production)
LOG_LEVEL=info
ENABLE_QUERY_LOGGING=false  # Only enable if debugging

# Auth (configure based on requirements)
ENABLE_SIGNUP=false  # Disable public signup
JWT_EXPIRY=3600  # 1 hour

# Backup (enable for production)
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"  # Daily at 2 AM
BACKUP_RETENTION_DAYS=30

# SSL/TLS (configure reverse proxy like Caddy or nginx)
# Point domain to your VM IP
# Use Let's Encrypt for free SSL certificates
```

**What you MUST change for production**:
- 🔐 All passwords and secrets (cryptographically secure)
- 🌐 All URLs (use your domain)
- ☁️ S3 credentials (real AWS/provider credentials)
- 🔑 External API keys (real keys from providers)
- 📧 Auth configuration (email provider, OAuth, etc.)
- 🔒 Disable public signup unless needed
- 📊 Enable backups and monitoring

**Production Security Checklist**:
- [ ] Use strong, unique passwords (32+ characters)
- [ ] Generate fresh JWT secrets (never reuse from development)
- [ ] Store `.env` securely (never commit to git)
- [ ] Use HTTPS/SSL for all external access
- [ ] Configure firewall rules on VM
- [ ] Set up database backups
- [ ] Enable monitoring and alerting
- [ ] Review RLS policies in `006_rls_policies.sql`
- [ ] Restrict service role key usage to backend only
- [ ] Configure CORS in Kong for specific domains

### **S3 Bucket Setup**

#### **For Testing (MinIO)**

Run MinIO locally for S3-compatible storage:

```bash
# Using Docker
docker run -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  quay.io/minio/minio server /data --console-address ":9001"

# Access MinIO console at http://localhost:9001
# Create bucket: test-pointclouds
```

Update `.env`:
```env
S3_ENDPOINT=http://localhost:9000
S3_BUCKET_NAME=test-pointclouds
S3_ACCESS_KEY_ID=minioadmin
S3_SECRET_ACCESS_KEY=minioadmin
```

#### **For Production (AWS S3)**

1. **Create S3 Bucket**:
   - Log in to AWS Console
   - Go to S3 service
   - Create bucket: `xr-forests-production-pointclouds`
   - Region: Choose closest to your VM (e.g., `eu-central-1`)
   - Block public access: Enable (use presigned URLs instead)
   - Versioning: Enable (prevents accidental deletion)
   - Encryption: Enable (AES-256 or KMS)

2. **Create IAM User**:
   - Go to IAM service
   - Create user: `supabase-storage-user`
   - Attach policy:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:PutObject",
           "s3:GetObject",
           "s3:DeleteObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::xr-forests-production-pointclouds",
           "arn:aws:s3:::xr-forests-production-pointclouds/*"
         ]
       }
     ]
   }
   ```
   - Generate access keys

3. **Update `.env`**:
   ```env
   S3_ENDPOINT=https://s3.amazonaws.com
   S3_REGION=eu-central-1
   S3_BUCKET_NAME=xr-forests-production-pointclouds
   S3_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
   S3_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   ```

### **Verifying Configuration**

After configuring `.env`, verify your setup:

```bash
# Start services
docker-compose up -d

# Check service health
docker-compose ps

# Test database connection
psql -h localhost -p 54322 -U postgres -d postgres

# Test REST API (replace with your anon key)
curl http://localhost:54321/rest/v1/ \
  -H "apikey: YOUR_ANON_KEY"

# Check Studio UI
open http://localhost:54323
```

If services fail to start, check logs:
```bash
docker-compose logs db
docker-compose logs rest
docker-compose logs kong
```

## **Current Implementation Status**

### ✅ **Supabase Implementation Complete** (Milestone 2 - DONE)

- Complete Supabase Docker Compose stack
- PostgreSQL + PostGIS with 5 specialized schemas
- 8 SQL migrations with seed data
- Row-level security policies
- PostgREST auto-generated APIs
- Real-time subscription support
- Edge Functions for business logic
- S3 integration for point cloud storage
- Comprehensive documentation

### 📋 **Production Deployment** (Milestone 3 - NEXT)

- VM server configuration and deployment
- Production environment variables
- S3 bucket setup and permissions
- SSL/TLS certificates for HTTPS
- External API connectivity for Logic Tier repositories
- Backup strategies and disaster recovery
- Monitoring and observability
- Performance optimization

**🎯 Target Deadline**: August 15, 2025 - Core database operational for VR integration

## **Development Workflow**

### Adding New Data
```bash
# Connect to PostgreSQL
psql -h localhost -p 54322 -U postgres

# Or use Supabase Studio UI
# Or use PostgREST API endpoints
```

### Updating Schemas
1. Create new migration file in `supabase/migrations/`
2. Restart database container:
```bash
docker-compose restart db
```

### Creating Edge Functions
1. Create function directory: `supabase/functions/my-function/`
2. Add `index.ts` with Deno/TypeScript code
3. Restart functions container:
```bash
docker-compose restart functions
```

### Testing APIs
```bash
# Get API key from .env or Studio
export SUPABASE_KEY="your_anon_key"

# Query trees
curl "http://localhost:54321/rest/v1/Trees?select=*" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY"
```

## **Integration with Logic Tier**

External repositories can consume the Supabase APIs:

### **The Grove** (Tree Asset Generation)
```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'http://your-vm-domain.com:54321',
  'your_anon_key'
)

// Fetch tree data for 3D model generation
const { data: trees } = await supabase
  .from('Trees')
  .select('*, Species(*), Stems(*)')
  .eq('LocationID', 15)
```

### **Potree Docker** (Point Cloud Processing)
```python
import requests

# Store processing results
response = requests.post(
    'http://your-vm-domain.com:54321/rest/v1/PointClouds',
    headers={'apikey': 'your_anon_key'},
    json={
        'ParentVariantID': 123,
        'VariantTypeID': 2,  # processed
        'ProcessingStatus': 'completed',
        'FilePath': 's3://bucket/processed.las'
    }
)
```

## **Benefits of Supabase Architecture**

| Feature | Traditional Stack | Supabase Stack |
|---------|------------------|----------------|
| REST API | Custom FastAPI/Flask | Auto-generated PostgREST |
| Real-time | Redis + WebSockets | Built-in Realtime |
| Authentication | Custom JWT/Auth | Built-in GoTrue |
| Security | Custom middleware | Row-Level Security (RLS) |
| API Gateway | nginx config | Kong (included) |
| Database UI | pgAdmin/DBeaver | Supabase Studio |
| Serverless | AWS Lambda/Cloud Functions | Edge Functions (Deno) |
| File Storage | Custom S3 integration | Built-in Storage API |
| Documentation | Manual API docs | Auto-generated OpenAPI |

## **Migration from FastAPI**

This repository previously used FastAPI + nginx + Redis. The migration to Supabase provides:

✅ **Simplified Stack**: 1 configuration file instead of multiple services
✅ **Less Code**: PostgREST replaces 1000s of lines of endpoint code
✅ **Better Security**: RLS policies instead of custom auth middleware
✅ **Real-time Built-in**: No Redis pub/sub configuration needed
✅ **Better DX**: Supabase Studio for visual database management
✅ **Production-Ready**: Battle-tested at scale by Supabase

## **Resources**

- **[Supabase Documentation](https://supabase.com/docs)**
- **[PostgREST API Reference](https://postgrest.org/)**
- **[PostGIS Documentation](https://postgis.net/)**
- **[Database ERD Viewer](https://dbdiagram.io/)** - Upload `docs/architecture/xr_forests_complete_erd.dbml`
- **[Edge Functions Guide](./supabase/functions/README.md)**

## **Support & Contributing**

For questions or issues:
1. Check documentation in `docs/` folder
2. Review existing GitHub issues
3. Create new issue with detailed description
4. Contact: University of Freiburg, Department of Forest Sciences

## **License**

[Specify your license here]

---

**Built with**: Supabase | PostgreSQL | PostGIS | Docker | Deno | Kong
