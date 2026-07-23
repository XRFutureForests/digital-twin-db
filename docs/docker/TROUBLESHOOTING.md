# Troubleshooting Guide

This guide covers common issues and solutions for the Forest Digital Twin Database Docker setup, following [official Supabase self-hosting guidelines](https://github.com/supabase/supabase/tree/master/docker).

---

## Quick Health Check

```bash
cd docker
docker compose ps
```

All services should show `(healthy)` status. Services like `auth`, `realtime`, and `storage` may restart several times during initial setup - this is normal.

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f db
docker compose logs -f analytics
```

---

## Complete System Reset

### Method 1: Using reset.sh (Recommended)

The `reset.sh` script provides an interactive way to completely reset your installation:

```bash
cd docker
./reset.sh
```

This will:

1. Stop and remove all containers
2. Remove all volumes (⚠️ **deletes all data permanently**)
3. Clean up the `volumes/db/data` directory
4. Reset the `.env` file from `.env.example`

### Method 2: Manual Cleanup

```bash
cd docker

# Stop and remove containers + volumes
docker compose down -v --remove-orphans

# Remove persistent database directory
sudo rm -rf volumes/db/data

# Restart fresh
docker compose up -d
```

### Method 3: Cleanup Script (Preserves .env)

```bash
cd docker
./cleanup-volumes.sh
docker compose up -d
```

---

## Common Issues

### 1. Analytics Container Stuck or Unhealthy

**Symptoms:**

- `dftdb-analytics` shows unhealthy or waiting
- Logs show: `database "_supabase" does not exist`

**Cause:**  
Analytics requires the `_supabase` database. If initialization is incomplete, analytics will fail.

**Solution:**

```bash
cd docker
docker compose down -v
sudo rm -rf volumes/db/data
docker compose up -d
```

The fixed `docker-compose.yml` now ensures `_supabase` database is created before analytics starts.

### 2. Auth/Realtime/Storage Services Restarting

**Symptoms:**

- Containers show `Restarting (1)` status
- Logs show: `ERROR: must be owner of function uid`

**Cause:**  
Expected behavior - these services retry several times during first startup due to database migration timing.

**Solution:**

**Wait 2-3 minutes** for services to stabilize. They will eventually succeed.

If not stabilized after 5 minutes:

```bash
docker compose restart auth realtime storage
docker compose logs -f auth
```

### 3. Port Conflicts

**Symptoms:**

- Error: `Bind for 0.0.0.0:8000 failed: port is already allocated`

**Solution:**

```bash
# Find what's using the port
sudo lsof -i :8000
sudo lsof -i :5432

# Stop the conflicting service or change ports in docker-compose.yml
```

### 4. Database Won't Initialize

**Symptoms:**

- Logs show: `PostgreSQL Database directory appears to contain a database; Skipping initialization`
- Custom schemas not created

**Cause:**  
Old database exists in `volumes/db/data`

**Solution:**

```bash
cd docker
docker compose down -v
sudo rm -rf volumes/db/data
docker compose up -d
```

### 5. Permission Denied on volumes/db/data

**Symptoms:**

- Cannot delete `volumes/db/data`

**Cause:**  
PostgreSQL creates files owned by UID 105 (postgres user). This is expected.

**Solution:**

```bash
# Use sudo
sudo rm -rf docker/volumes/db/data

# Or use the cleanup script
cd docker
./cleanup-volumes.sh
```

### 6. Password Authentication Failed

**Symptoms:**

- Error: `password authentication failed for user supabase_admin`

**Cause:**  
Database was initialized with different credentials than current `.env` file.

**Solution:**

```bash
cd docker
docker compose down -v
sudo rm -rf volumes/db/data
docker compose up -d
```

PostgreSQL passwords are set during initial database creation. Changing `POSTGRES_PASSWORD` in `.env` after initialization doesn't update existing users.

### 7. Studio UI Won't Load

**Symptoms:**

- Browser shows "Cannot connect" at <http://localhost:54323>

**Cause:**  
Studio depends on analytics being healthy.

**Solution:**

```bash
# Check analytics health
docker compose ps analytics

# Restart studio after analytics is healthy
docker compose restart studio
```

---

## Advanced Troubleshooting

### Verify Database Initialization

```bash
# List databases (should show: postgres, _supabase)
docker exec dftdb-db psql -U postgres -c "\l"

# Check custom schemas
docker exec dftdb-db psql -U postgres -c "\dn"
# Should show: shared, pointclouds, trees, sensor, environments

# Verify _analytics schema exists
docker exec dftdb-db psql -U postgres -d _supabase -c "\dn"
# Should show: _analytics, _supavisor
```

### Monitor Resource Usage

```bash
# Docker resource usage
docker stats

# Container health status
docker inspect dftdb-db --format='{{.State.Health.Status}}'
```

### Extract Logs for Analysis

```bash
# Save all logs
docker compose logs > /tmp/supabase-logs.txt

# View database initialization
docker compose logs db | grep -E "(init|migration|script)"
```

---

## Emergency Recovery

### Backup Before Reset

```bash
# Backup database
docker exec dftdb-db pg_dump -U postgres -Fc postgres > backup.dump

# After reset, restore:
docker exec -i dftdb-db pg_restore -U postgres -d postgres < backup.dump
```

---

## Getting Help

If these solutions don't work:

1. **Check logs carefully** - Error messages usually indicate the root cause
2. **[GitHub Issues](https://github.com/supabase/supabase/issues?q=is%3Aissue+label%3Aself-hosted)** - Search known issues
3. **[Discord](https://discord.supabase.com/)** - Self-hosting channel
4. **[GitHub Discussions](https://github.com/orgs/supabase/discussions?discussions_q=is%3Aopen+label%3Aself-hosted)** - Community support

When asking for help, provide:

- Output of `docker compose ps`
- Relevant logs from `docker compose logs [service]`
- Docker version: `docker --version`
- OS and version

---

## Prevention Tips

1. **Always use `docker compose down -v`** for clean resets
2. **Wait for all services to be healthy** before accessing Studio
3. **Monitor logs during startup** - First 60 seconds reveal most issues
4. **Keep backups** if you have important data
5. **Don't modify running containers** - Make changes in `docker-compose.yml`

---

## Quick Command Reference

```bash
# Start
docker compose up -d

# Stop (keep data)
docker compose down

# Stop and remove everything
docker compose down -v && sudo rm -rf volumes/db/data

# Check status
docker compose ps

# View logs
docker compose logs -f [service]

# Restart service
docker compose restart [service]

# Connect to database
docker exec -it dftdb-db psql -U postgres

# Full reset
./reset.sh
```

---

## Best Practices

1. **Always use `docker compose down -v`** when resetting to ensure volumes are removed
2. **Pull latest changes** before starting if working with others
3. **Don't commit `.env`** - it's gitignored for security
4. **Use `.env.example`** as a reference
5. **For local development**, the current secrets are fine (not production-ready)
6. **Follow [official Supabase guidelines](https://supabase.com/docs/guides/self-hosting/docker)** for production deployments
