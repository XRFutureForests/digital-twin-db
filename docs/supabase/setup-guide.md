# Supabase Setup Guide - XR Future Forests Lab

This guide provides step-by-step instructions for deploying the Supabase-based digital twin database backend for local development and production environments.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Production Deployment](#production-deployment)
5. [Environment Configuration](#environment-configuration)
6. [Database Migrations](#database-migrations)
7. [Troubleshooting](#troubleshooting)

## Architecture Overview

The Supabase stack replaces the previous FastAPI + nginx + Redis architecture with:

- **PostgreSQL + PostGIS**: Spatial database with 5 forest-specific schemas
- **PostgREST**: Auto-generated REST API from database schema
- **Kong**: API gateway for routing and authentication
- **GoTrue**: Built-in authentication service
- **Realtime**: WebSocket server for live subscriptions
- **Storage API**: S3-compatible storage (connects to external S3)
- **Edge Functions**: Deno-based serverless functions
- **Supabase Studio**: Web-based database management UI

## Prerequisites

### For Local Development

- **Docker**: Version 20.10+ ([Install Docker](https://docs.docker.com/get-docker/))
- **Docker Compose**: Version 2.0+ (included with Docker Desktop)
- **System Requirements**:
  - 8GB+ RAM (16GB recommended)
  - 20GB+ free disk space
  - Multi-core CPU (4+ cores recommended)

### For Production Deployment

- **Linux Server** (Ubuntu 22.04 LTS recommended)
- **8GB+ RAM** (16GB+ for production workloads)
- **100GB+ Storage** (SSD recommended)
- **Docker** and **Docker Compose** installed
- **Domain name** with DNS configured
- **S3 Bucket** (AWS S3, MinIO, or compatible service)
- **SSL/TLS Certificate** (Let's Encrypt recommended)

## Local Development Setup

### 1. Clone Repository

```bash
git clone https://github.com/your-org/digital-twin.git
cd digital-twin
```

### 2. Configure Environment Variables

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env  # or vim, code, etc.
```

**Required Variables**:
```bash
# Database
POSTGRES_PASSWORD=your_secure_password_here

# JWT Secret (generate with: openssl rand -base64 32)
SUPABASE_JWT_SECRET=your_jwt_secret_here

# API Keys (generate with: openssl rand -base64 32)
SUPABASE_ANON_KEY=your_anon_key_here
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key_here

# S3 Configuration
S3_ENDPOINT=https://s3.amazonaws.com
S3_REGION=us-east-1
S3_BUCKET_NAME=xr-forests-pointclouds
S3_ACCESS_KEY_ID=your_s3_access_key
S3_SECRET_ACCESS_KEY=your_s3_secret_key
```

### 3. Start Supabase Stack

```bash
# Start all services in detached mode
docker-compose up -d

# View logs
docker-compose logs -f

# Check service status
docker-compose ps
```

### 4. Verify Services

Services should be running at:

| Service | URL | Description |
|---------|-----|-------------|
| Supabase Studio | http://localhost:54323 | Database management UI |
| REST API | http://localhost:54321/rest/v1 | PostgREST endpoints |
| Auth API | http://localhost:54321/auth/v1 | Authentication |
| Realtime | http://localhost:54321/realtime/v1 | WebSocket subscriptions |
| Edge Functions | http://localhost:54321/functions/v1 | Serverless functions |
| PostgreSQL | localhost:54322 | Direct database access |

### 5. Access Supabase Studio

1. Open http://localhost:54323 in your browser
2. Connect to database:
   - **Host**: `db`
   - **Port**: `5432`
   - **Database**: `postgres`
   - **User**: `postgres`
   - **Password**: (from your `.env` file)

### 6. Load Sample Data

Sample data is automatically loaded from `supabase/migrations/008_seed_data.sql`:
- 3 forest plot locations
- 5 tree species
- Sample point clouds
- 4 detected trees
- Environmental sensors
- Sensor readings (last 24 hours simulated)

### 7. Test API Access

```bash
# Set your API key
export SUPABASE_KEY="your_anon_key_from_env_file"

# Test REST API
curl "http://localhost:54321/rest/v1/Trees?select=*" \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY"

# Should return sample trees as JSON
```

## Production Deployment

### 1. Server Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sudo sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Clone and Configure

```bash
# Clone on server
cd /opt
sudo git clone https://github.com/your-org/digital-twin.git
cd digital-twin

# Create production .env
sudo cp .env.example .env
sudo nano .env
```

**Production Environment Variables**:
```bash
# Production API URL (your domain)
API_EXTERNAL_URL=https://api.your-domain.com

# Strong passwords and keys
POSTGRES_PASSWORD=$(openssl rand -base64 32)
SUPABASE_JWT_SECRET=$(openssl rand -base64 32)
SUPABASE_ANON_KEY=$(openssl rand -base64 32)
SUPABASE_SERVICE_ROLE_KEY=$(openssl rand -base64 32)

# Production S3
S3_ENDPOINT=https://s3.amazonaws.com
S3_REGION=us-east-1
S3_BUCKET_NAME=your-production-bucket
S3_ACCESS_KEY_ID=your_production_key
S3_SECRET_ACCESS_KEY=your_production_secret

# Environment
ENVIRONMENT=production
```

### 3. Configure SSL/TLS

#### Option A: Use nginx Reverse Proxy with Let's Encrypt

```bash
# Install nginx
sudo apt install nginx certbot python3-certbot-nginx -y

# Create nginx configuration
sudo nano /etc/nginx/sites-available/supabase
```

**nginx Configuration**:
```nginx
server {
    listen 80;
    server_name api.your-domain.com;

    location / {
        proxy_pass http://localhost:54321;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Get SSL certificate
sudo certbot --nginx -d api.your-domain.com
```

#### Option B: Use Kong with SSL (update docker-compose.yml)

Add SSL configuration to Kong service in `docker-compose.yml`.

### 4. Start Production Stack

```bash
# Start services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### 5. Set Up Backups

#### Automated Database Backups

```bash
# Create backup script
sudo nano /opt/backup-database.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/backup/database"
DATE=$(date +%Y%m%d_%H%M%S)
CONTAINER="xr_forests_db"

mkdir -p $BACKUP_DIR

docker exec $CONTAINER pg_dump -U postgres postgres | gzip > $BACKUP_DIR/backup_$DATE.sql.gz

# Keep only last 30 days
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +30 -delete
```

```bash
# Make executable
sudo chmod +x /opt/backup-database.sh

# Add to crontab (daily at 2 AM)
sudo crontab -e
# Add line:
0 2 * * * /opt/backup-database.sh
```

### 6. Configure Firewall

```bash
# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow SSH (if not already)
sudo ufw allow 22/tcp

# Enable firewall
sudo ufw enable
```

### 7. Set Up Monitoring

#### Basic Health Checks

```bash
# Create health check script
sudo nano /opt/health-check.sh
```

```bash
#!/bin/bash
SERVICES="studio kong auth rest realtime storage db"

for SERVICE in $SERVICES; do
    if docker-compose ps | grep $SERVICE | grep -q Up; then
        echo "✓ $SERVICE is running"
    else
        echo "✗ $SERVICE is DOWN"
        # Send alert (email, Slack, etc.)
    fi
done
```

## Environment Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_PASSWORD` | PostgreSQL root password | `your_secure_password` |
| `SUPABASE_JWT_SECRET` | JWT signing secret | `32+ character random string` |
| `SUPABASE_ANON_KEY` | Public API key | `32+ character random string` |
| `SUPABASE_SERVICE_ROLE_KEY` | Admin API key | `32+ character random string` |
| `S3_BUCKET_NAME` | S3 bucket for point clouds | `xr-forests-pointclouds` |
| `S3_ACCESS_KEY_ID` | S3 access key | Your S3 credentials |
| `S3_SECRET_ACCESS_KEY` | S3 secret key | Your S3 credentials |
| `API_EXTERNAL_URL` | Public API URL | `https://api.your-domain.com` |

### Optional Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_PORT` | PostgreSQL port | `54322` |
| `KONG_HTTP_PORT` | API gateway HTTP port | `54321` |
| `STUDIO_PORT` | Studio UI port | `54323` |
| `S3_REGION` | AWS region | `us-east-1` |
| `S3_ENDPOINT` | S3 endpoint URL | `https://s3.amazonaws.com` |
| `JWT_EXPIRY` | JWT expiration (seconds) | `3600` |
| `LOG_LEVEL` | Logging level | `info` |

## Database Migrations

### Running Migrations

Migrations run automatically on first database startup from `supabase/migrations/`:

1. `001_shared_schema.sql` - Core reference tables
2. `002_pointclouds_schema.sql` - Point cloud structure
3. `003_trees_schema.sql` - Tree measurements
4. `004_sensor_schema.sql` - Environmental sensors
5. `005_environments_schema.sql` - Environmental conditions
6. `006_rls_policies.sql` - Row-level security
7. `007_audit_functions_triggers.sql` - Audit logging
8. `008_seed_data.sql` - Sample data

### Creating New Migrations

```bash
# Create new migration file
touch supabase/migrations/009_your_migration_name.sql

# Add SQL commands
nano supabase/migrations/009_your_migration_name.sql

# Restart database to apply
docker-compose restart db
```

### Manual Migration Execution

```bash
# Connect to database
docker exec -it xr_forests_db psql -U postgres

# Run SQL commands
\i /docker-entrypoint-initdb.d/009_your_migration_name.sql

# Verify changes
\dt shared.*
\dt trees.*
```

## Troubleshooting

### Services Won't Start

```bash
# Check Docker status
docker ps -a

# View service logs
docker-compose logs db
docker-compose logs kong
docker-compose logs rest

# Check disk space
df -h

# Check memory
free -h
```

### Database Connection Errors

```bash
# Check database health
docker exec xr_forests_db pg_isready -U postgres

# View database logs
docker-compose logs db

# Test connection
docker exec -it xr_forests_db psql -U postgres -c "SELECT version();"
```

### API Returns 500 Errors

```bash
# Check PostgREST logs
docker-compose logs rest

# Verify database schemas
docker exec -it xr_forests_db psql -U postgres -c "\dn"

# Check RLS policies
docker exec -it xr_forests_db psql -U postgres -c "
  SELECT schemaname, tablename, policyname
  FROM pg_policies
  WHERE schemaname IN ('shared', 'pointclouds', 'trees', 'sensor', 'environments');
"
```

### S3 Connection Issues

```bash
# Test S3 credentials from Edge Function
docker-compose logs functions

# Verify S3 bucket access
aws s3 ls s3://your-bucket-name --region us-east-1

# Check environment variables
docker exec xr_forests_functions env | grep S3
```

### Studio Won't Load

```bash
# Check Studio logs
docker-compose logs studio

# Verify Studio can reach database
docker exec xr_forests_studio curl http://meta:8080

# Check network connectivity
docker network inspect xr_forests_network
```

### Performance Issues

```bash
# Check resource usage
docker stats

# Increase container resources (edit docker-compose.yml)
services:
  db:
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2'

# Restart services
docker-compose restart
```

## Maintenance

### Updating Services

```bash
# Pull latest images
docker-compose pull

# Restart with new images
docker-compose up -d

# Verify updates
docker-compose ps
```

### Backup and Restore

#### Backup
```bash
# Backup database
docker exec xr_forests_db pg_dump -U postgres postgres > backup.sql

# Backup volumes
docker run --rm -v xr_forests_db_data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/db_data_backup.tar.gz /data
```

#### Restore
```bash
# Restore database
docker exec -i xr_forests_db psql -U postgres < backup.sql

# Restore volumes
docker run --rm -v xr_forests_db_data:/data -v $(pwd):/backup \
  ubuntu tar xzf /backup/db_data_backup.tar.gz -C /
```

## Next Steps

- [S3 Integration Guide](./s3-integration.md) - Configure point cloud storage
- [API Reference](./api-reference.md) - Learn PostgREST query syntax
- [RLS Policies](./rls-policies.md) - Understand security model
- [Development Guide](./development.md) - Local development workflow

## Support

For issues or questions:
1. Check [Supabase Documentation](https://supabase.com/docs)
2. Review GitHub Issues
3. Contact: University of Freiburg, Department of Forest Sciences
