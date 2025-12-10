# Operations Guide

Comprehensive guide for running and maintaining the Digital Forest Twin Database in production and development.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Starting & Stopping Services](#starting--stopping-services)
- [Database Backup & Recovery](#database-backup--recovery)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Edge Functions Management](#edge-functions-management)
- [Common Issues & Solutions](#common-issues--solutions)
- [Scaling Considerations](#scaling-considerations)
- [Security Operations](#security-operations)

## Pre-Deployment Checklist

### Before Production Deployment

- [ ] **Regenerate all secrets** - Do NOT use development values
  ```bash
  # Generate new secure values
  openssl rand -base64 32  # PostgreSQL password
  openssl rand -base64 32  # JWT secret
  openssl rand -base64 32  # Service role key
  openssl rand -base64 32  # Secret key base
  openssl rand -hex 16     # Vault encryption key
  ```

- [ ] **Update `.env` file** with production values
  - `POSTGRES_PASSWORD` - Strong random password
  - `JWT_SECRET` - Cryptographically secure key
  - `SERVICE_ROLE_KEY` - Never expose this publicly
  - `ANON_KEY` - Generate from JWT_SECRET
  - All other sensitive values (SMTP, API keys, etc.)

- [ ] **Configure external services**
  - [ ] Aquarius API credentials (`AQUARIUS_HOSTNAME`, `AQUARIUS_USERNAME`, `AQUARIUS_PASSWORD`)
  - [ ] Backup storage location (S3, GCS, etc.)
  - [ ] Email/notification service (SMTP settings)
  - [ ] Monitoring service (Sentry, DataDog, etc.)

- [ ] **Set environment-specific variables**
  ```bash
  DISABLE_SIGNUP=true              # Prevent public registration
  FUNCTIONS_VERIFY_JWT=true        # Enable JWT verification for functions
  API_EXTERNAL_URL=<production_url> # Set to actual domain
  SUPABASE_PUBLIC_URL=<production_url>
  ```

- [ ] **Configure SSL/TLS**
  - Set up reverse proxy (nginx, Caddy, Traefik)
  - Enable HTTPS on all external connections
  - Configure certificate auto-renewal (Let's Encrypt)

- [ ] **Database backups**
  - [ ] Set up automated daily backups
  - [ ] Test backup restoration procedure
  - [ ] Store backups in geographically separate location
  - [ ] Document recovery time objective (RTO) and recovery point objective (RPO)

- [ ] **Resource allocation**
  - [ ] Adequate storage (database, point cloud data)
  - [ ] CPU/memory for concurrent requests
  - [ ] Network bandwidth for data import/export

- [ ] **Monitoring & alerting**
  - [ ] Health check endpoints configured
  - [ ] CPU/memory alerts set
  - [ ] Database connection pool alerts
  - [ ] Disk space alerts
  - [ ] Error rate monitoring

## Starting & Stopping Services

### Start All Services

```bash
cd docker
docker compose up -d

# Monitor startup
docker compose logs -f
```

Services start in dependency order:
1. Database (`db`) - must be healthy first
2. Analytics (`analytics`) - required by other services
3. REST API (`rest`), Auth (`auth`), etc. - start once database is ready
4. Functions (`functions`) - starts last
5. Kong (`kong`) - reverse proxy

### Stop Services

```bash
# Graceful stop (preserves data)
docker compose down

# Stop without removing containers
docker compose stop

# Stop specific service
docker compose stop functions
```

### Restart Individual Service

```bash
# Restart function runtime (useful for reloading code)
docker compose restart functions

# Restart database
docker compose restart db
# WARNING: Ensure backups are current before restarting database
```

### View Service Status

```bash
docker compose ps

# Detailed status
docker compose ps --format "table {{.Names}}\t{{.Status}}"

# Check service health
docker compose ps | grep healthy
```

### Check Service Logs

```bash
# All services
docker compose logs -f

# Specific service (last 100 lines)
docker compose logs -f --tail=100 functions

# Time-filtered logs (last hour)
docker compose logs --since 1h functions

# Search in logs
docker compose logs functions | grep "error"
```

## Database Backup & Recovery

### Automated Backups

Ensure backups are configured in your backup service (automated via cron or cloud provider):

```bash
# Daily backup example
0 2 * * * /home/user/digital_twin_db/scripts/backup.sh >> /var/log/backup.log 2>&1
```

### Manual Backup

```bash
# Create backup
docker exec dftdb-db pg_dump -U postgres > backup_$(date +%Y%m%d_%H%M%S).sql

# Compressed backup
docker exec dftdb-db pg_dump -U postgres | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz

# With verbosity
docker exec dftdb-db pg_dump -U postgres -v > backup_$(date +%Y%m%d_%H%M%S).sql
```

### Restore from Backup

```bash
# WARNING: This REPLACES all database data

# Stop the application
docker compose down

# Remove current database volume
docker volume rm dftdb-volumes-db

# Start database (creates fresh volume)
docker compose up -d db

# Wait for database to be ready
sleep 30

# Restore backup
cat backup_20240115_020000.sql | docker exec -i dftdb-db psql -U postgres

# Restart all services
docker compose up -d
```

### Backup Verification

After each backup, verify it's valid:

```bash
# Check backup file size (should not be 0)
ls -lh backup_*.sql

# Verify backup is readable
head -20 backup_*.sql  # Should show SQL schema

# Test restore to development environment
psql -h localhost -U postgres < backup_*.sql
```

## Monitoring & Health Checks

### Health Check Endpoints

All services expose health check endpoints:

```bash
# Functions runtime
curl http://localhost:9000/health

# REST API
curl -s http://localhost:3000/rest/v1/ | head -20

# Database (via psql)
docker exec dftdb-db psql -U postgres -c "SELECT version();"
```

### Key Metrics to Monitor

**Database**
- Connection pool usage: `SELECT count(*) FROM pg_stat_activity`
- Slow queries: Enable `log_min_duration_statement`
- Table bloat: `SELECT pg_total_relation_size(schemaname||'.'||tablename) FROM pg_tables`
- Replication lag (if applicable)

**API**
- Response time (95th percentile should be <500ms)
- Error rate (5xx should be <0.1%)
- Request rate (requests/second)
- Cache hit ratio

**Functions**
- Cold start time (<3 seconds)
- Execution time distribution
- Memory usage
- Error count and types

**Disk Space**
```bash
# Database volume usage
docker exec dftdb-db du -sh /var/lib/postgresql/data

# Total disk usage
docker system df

# Cleanup unused volumes
docker volume prune
```

### Set Up Monitoring

Monitor these logs for errors:

```bash
# Database errors
docker compose logs db 2>&1 | grep -i error

# API errors
docker compose logs rest 2>&1 | grep -i error

# Function errors
docker compose logs functions 2>&1 | grep -i error
```

## Edge Functions Management

### Reload Functions (Development)

Functions auto-reload on file changes during development:

```bash
# Manual reload (if needed)
docker compose restart functions

# Monitor reload
docker compose logs -f functions | grep "loaded\|error"
```

### Deploy Function Update

1. Edit function file: `/docker/volumes/functions/my-function/index.ts`
2. Functions automatically reload within seconds
3. Test via API endpoint
4. No service restart needed

### Function Troubleshooting

```bash
# Check if function runtime is healthy
curl http://localhost:9000/health

# View function logs
docker compose logs functions -f

# Test function directly
curl -X POST http://localhost:8000/functions/v1/ecosense-ingest \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
```

### Update TypeScript/Deno Dependencies

If Deno standard library versions need updating:

1. Update imports in affected functions
2. Test locally: `docker compose down && docker compose up -d`
3. Verify all functions still work
4. Document changes in CHANGELOG.md

## Common Issues & Solutions

### Database Won't Start

**Symptom**: `docker compose logs db` shows connection errors

**Solutions**:
```bash
# Check database volume health
docker exec dftdb-db pg_isready

# Check logs for specific errors
docker compose logs db | grep -i error

# Reset database (WARNING: data loss)
docker compose down -v
docker compose up -d db
```

### Functions Not Responding

**Symptom**: curl to function endpoint times out or returns 502

**Solutions**:
```bash
# Restart functions
docker compose restart functions

# Check if listening on port 9000
docker exec dftdb-edge-functions curl localhost:9000/health

# Check logs
docker compose logs functions | tail -50

# Insufficient memory?
docker system df
docker stats dftdb-edge-functions
```

### High Disk Usage

**Symptom**: `docker system df` shows low available space

**Solutions**:
```bash
# Clean up unused volumes
docker volume prune

# Remove old containers
docker container prune

# Check database size
docker exec dftdb-db psql -U postgres \
  -c "SELECT pg_size_pretty(pg_database_size('postgres'));"
```

### Slow API Responses

**Symptom**: Queries take >1 second

**Solutions**:
1. Check database connection pool: are connections maxed out?
2. Enable query logging: `log_statement = 'all'` in postgres config
3. Check for missing indexes
4. Analyze slow queries: `EXPLAIN ANALYZE SELECT ...`

### Service Dependencies Not Met

**Symptom**: "service X depends on service Y"

**Solutions**:
```bash
# Full restart with explicit wait
docker compose up -d

# Monitor startup sequence
docker compose logs | grep "healthy\|starting"

# Increase service startup time in docker-compose.yml if needed
# (adjust `start_period` in healthcheck)
```

## Scaling Considerations

### Horizontal Scaling (Multiple Instances)

For production scale, consider:

1. **Load Balancer**
   - Use Kong (already in stack) or external (nginx, HAProxy)
   - Configure sticky sessions if needed
   - Enable health checks

2. **Database Pooling**
   - Supavisor is already configured
   - Adjust `POOLER_DEFAULT_POOL_SIZE` if needed
   - Monitor pool exhaustion: check `pg_stat_database.numbackends`

3. **Caching**
   - Consider Redis for session/cache
   - Cache Aquarius sensor metadata (doesn't change often)
   - Implement cache invalidation strategy

4. **Read Replicas**
   - For heavy read workloads
   - Configure logical replication
   - Distribute read queries across replicas

### Vertical Scaling (Larger Single Instance)

1. **Increase container resource limits**
   ```yaml
   services:
     db:
       deploy:
         resources:
           limits:
             cpus: '4'
             memory: 16G
   ```

2. **Tune PostgreSQL**
   ```sql
   -- In postgresql.conf
   shared_buffers = 4GB
   effective_cache_size = 12GB
   work_mem = 50MB
   maintenance_work_mem = 1GB
   ```

3. **Optimize connection pool**
   ```
   POOLER_DEFAULT_POOL_SIZE = 50  # from 20
   POOLER_MAX_CLIENT_CONN = 200   # from 100
   ```

## Security Operations

### API Key Rotation

**Schedule**: Every 90 days or after suspected compromise

```bash
# 1. Generate new keys
NEW_ANON=$(openssl rand -base64 32)
NEW_SERVICE_ROLE=$(openssl rand -base64 32)

# 2. Update .env
sed -i "s/ANON_KEY=.*/ANON_KEY=$NEW_ANON/" docker/.env
sed -i "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$NEW_SERVICE_ROLE/" docker/.env

# 3. Restart services
docker compose restart

# 4. Update clients with new keys

# 5. Document rotation in audit log
```

### Password Rotation

```bash
# 1. Generate new database password
NEW_PG_PASSWORD=$(openssl rand -base64 32)

# 2. Update in .env
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$NEW_PG_PASSWORD/" docker/.env

# 3. Update in database
docker exec dftdb-db psql -U postgres \
  -c "ALTER USER postgres WITH PASSWORD '$NEW_PG_PASSWORD';"

# 4. Restart database
docker compose restart db
```

### Access Control Audit

```bash
# Check who created data (audit trail)
SELECT DISTINCT CreatedBy FROM shared.Species;
SELECT DISTINCT CreatedBy FROM trees.Trees;

# View recent changes
SELECT * FROM shared.Processes ORDER BY CreatedAt DESC LIMIT 10;

# Check for unauthorized access attempts
docker compose logs kong | grep "401\|403"
```

### Backup Encryption

Ensure backups are encrypted at rest:

```bash
# Encrypt backup before storage
openssl enc -aes-256-cbc -salt -in backup.sql -out backup.sql.enc

# Decrypt when restoring
openssl enc -d -aes-256-cbc -in backup.sql.enc -out backup.sql
```

## Performance Tuning

### Connection Pool Optimization

Monitor current usage:
```bash
SELECT sum(numbackends) FROM pg_stat_database;
```

Adjust if consistently near max:
```bash
# docker/.env
POOLER_DEFAULT_POOL_SIZE=30  # increase from 20
POOLER_MAX_CLIENT_CONN=150   # increase from 100
```

### Query Optimization

Identify slow queries:
```sql
SELECT query, calls, mean_time, total_time
FROM pg_stat_statements
ORDER BY mean_time DESC LIMIT 10;
```

Add indexes for frequently accessed columns:
```sql
CREATE INDEX idx_trees_species_id ON trees.Trees(SpeciesID);
CREATE INDEX idx_sensors_location_id ON sensor.Sensors(LocationID);
CREATE INDEX idx_readings_timestamp ON sensor.SensorReadings(Timestamp);
```

### Memory Management

For large sensor data syncs:
- Batch size is configurable in `ecosense-ingest/index.ts`
- Default: 5000 readings per batch
- Reduce if OOM errors occur, increase if memory available

## Disaster Recovery

### Recovery Time Objectives (RTO)

- **Critical failure**: < 1 hour to restore
- **Data corruption**: < 4 hours to identify and restore
- **Gradual degradation**: < 8 hours to identify and fix

### Recovery Point Objectives (RPO)

- Daily backups = 24-hour RPO
- Configure more frequent backups if better RPO needed

### Recovery Steps

1. **Identify failure type**: corruption, hardware, config, etc.
2. **Determine data loss tolerance**: use most recent good backup?
3. **Stop current services**: prevent further damage
4. **Restore from backup**: follow backup restoration procedure
5. **Verify data integrity**: run consistency checks
6. **Resume operations**: restart services
7. **Document incident**: for future prevention

### Testing Recovery

Periodically test recovery procedures:
```bash
# On development/staging environment:
# 1. Restore latest backup
# 2. Run integration tests
# 3. Verify all data present and consistent
# 4. Document any issues
```

---

**Last Updated**: 2024-12-01
**Maintained By**: Digital Forest Twin Team
**Escalation Contact**: See SUPPORT.md
