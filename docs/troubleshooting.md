# Troubleshooting Guide - XR Future Forests Lab Database

This guide helps you solve common problems when running the database locally.

---

## 🚨 Quick Fixes (Try These First!)

### The "Turn It Off and On Again" Method

90% of issues can be fixed by restarting:

```bash
# Navigate to docker directory first
cd docker

# Stop everything
docker compose down

# Wait 5 seconds

# Start again
docker compose up -d

# Check status
docker compose ps
```

If this doesn't work, keep reading!

---

## 📚 Common Problems

### 1. Docker Desktop Issues

#### Problem: "docker: command not found" or "docker compose: command not found"

**Cause**: Docker is not installed or not in your PATH.

**Solutions**:

```bash
# Check if Docker is installed
docker --version

# If not installed, download from:
# https://www.docker.com/products/docker-desktop/
```

#### Problem: "Cannot connect to the Docker daemon"

**Cause**: Docker Desktop is not running.

**Solutions**:

1. Start Docker Desktop application
2. Wait until the Docker icon shows "Docker is running"
3. Try your command again

---

### 2. Port Conflicts

#### Problem: "Port is already allocated" or "Address already in use"

**Cause**: Another program is using the same port.

**Common ports used**:

- `8000` - API Gateway (Kong HTTP)
- `8443` - API Gateway (Kong HTTPS)
- `5432` - PostgreSQL (via Supavisor pooler)
- `54323` - Supabase Studio

**Solutions**:

**Option A: Find and stop the conflicting service**

```bash
# On Linux/Mac
sudo lsof -i :8000
sudo lsof -i :5432
sudo lsof -i :54323

# On Windows (PowerShell as Administrator)
netstat -ano | findstr :8000
netstat -ano | findstr :5432
netstat -ano | findstr :54323
```

Then stop the process using that port.

**Option B: Change the ports in .env**

```bash
# Edit .env file
nano .env

# Change these lines:
KONG_HTTP_PORT=8000     # Change to different port if needed
POSTGRES_PORT=5432      # Change to different port if needed
STUDIO_PORT=54323       # Change to different port if needed

# Restart
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml up -d
```

Now access Studio at `http://localhost:55323` instead.

---

### 3. Service Won't Start

#### Problem: Services show "Exit" or "Restarting" status

**Cause**: Configuration error, resource limits, or dependency issues.

**Solutions**:

**Step 1: Check which service is failing**

```bash
docker compose -f docker/docker-compose.yml ps
```

**Step 2: View logs for that service**

```bash
# Replace 'db' with the failing service name
docker compose -f docker/docker-compose.yml logs db
docker compose -f docker/docker-compose.yml logs kong
docker compose -f docker/docker-compose.yml logs studio
```

**Step 3: Common service-specific fixes**

**Database (db) won't start:**

```bash
# Check disk space
df -h

# Check if there's a corrupted volume
docker compose -f docker/docker-compose.yml down -v
docker compose -f docker/docker-compose.yml up -d
```

⚠️ Warning: `-v` deletes all data!

**Kong won't start:**

```bash
# Usually a configuration issue
docker compose -f docker/docker-compose.yml logs kong

# Check kong.yml syntax
cat supabase/kong.yml

# Restart dependencies first
docker compose -f docker/docker-compose.yml restart db
docker compose -f docker/docker-compose.yml restart auth
docker compose -f docker/docker-compose.yml restart rest
docker compose -f docker/docker-compose.yml restart kong
```

**Studio won't start:**

```bash
# Check if meta service is running
docker compose -f docker/docker-compose.yml ps meta

# Restart both
docker compose -f docker/docker-compose.yml restart meta
docker compose -f docker/docker-compose.yml restart studio
```

---

### 4. Can't Access Supabase Studio

#### Problem: <http://localhost:54323> doesn't load

**Cause**: Studio not running, wrong port, or browser cache.

**Solutions**:

**Step 1: Check if Studio is running**

```bash
docker compose -f docker/docker-compose.yml ps studio
```

Should show "Up". If not:

```bash
docker compose -f docker/docker-compose.yml restart studio
docker compose -f docker/docker-compose.yml logs studio
```

**Step 2: Try different browsers/methods**

```bash
# Try in incognito/private mode
# Try different browser (Chrome, Firefox, Edge)
# Try the IP address instead
http://127.0.0.1:54323
```

**Step 3: Check if port is correct**

```bash
# View your configuration
grep STUDIO_PORT .env
```

**Step 4: Test if Studio is responding**

```bash
curl http://localhost:54323
```

If this returns HTML, Studio is working but might be a browser issue.

---

### 5. Environment Configuration Issues

#### Problem: "SUPABASE_JWT_SECRET is invalid" or authentication errors

**Cause**: Missing or invalid keys in `.env` file.

**Solutions**:

**Step 1: Check if .env exists**

```bash
ls -la .env
```

If it doesn't exist, copy from the example:

```bash
cp docker/.env.example docker/.env
# Then edit with your own values
nano docker/.env
```

**Step 2: Verify keys are set**

```bash
grep SUPABASE_JWT_SECRET .env
grep SUPABASE_ANON_KEY .env
```

Both should have long strings, not placeholders.

**Step 3: Regenerate if needed**

```bash
# Backup current .env
cp docker/.env docker/.env.backup

# Generate new keys with openssl
cd docker
openssl rand -base64 32  # Use for JWT_SECRET
openssl rand -base64 32  # Use for other secrets

# Edit .env and paste new keys
nano .env

# Restart services
docker compose restart
```

---

### 6. API Connection Issues

#### Problem: API returns "401 Unauthorized" or "403 Forbidden"

**Cause**: Incorrect API key or missing headers.

**Solutions**:

**Step 1: Get your API key**

```bash
grep SUPABASE_ANON_KEY .env
```

**Step 2: Test with curl**

```bash
# Replace YOUR_KEY with actual key from above
curl "http://localhost:8000/rest/v1/species?select=*" \
  -H "apikey: YOUR_KEY" \
  -H "Authorization: Bearer YOUR_KEY"
```

**Step 3: Check both headers are set**

- You need BOTH `apikey` header AND `Authorization` header
- They should have the same value (your anon key)

**Step 4: Make sure you're using the ANON key, not SERVICE_ROLE key**

```bash
# Wrong - using service role key
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...

# Right - using anon key
SUPABASE_ANON_KEY=eyJhbGc...
```

---

### 7. Database Connection Errors

#### Problem: Can't connect with psql or database tools

**Cause**: Wrong credentials or database not ready.

**Solutions**:

**Step 1: Check database is healthy**

```bash
docker compose -f docker/docker-compose.yml ps db
```

Should show "Up (healthy)". If not healthy:

```bash
docker compose -f docker/docker-compose.yml logs db
docker compose -f docker/docker-compose.yml restart db
```

**Step 2: Verify credentials**

```bash
# View your database password
grep POSTGRES_PASSWORD .env
```

**Step 3: Test connection from inside container**

```bash
# This should always work
docker exec -it dftdb-db psql -U postgres

# If this works, the database is fine
# The problem is with your external connection
```

**Step 4: Connection details**

```
Host: localhost (or 127.0.0.1)
Port: 5432 (check POSTGRES_PORT in .env)
Database: postgres
Username: postgres
Password: (from POSTGRES_PASSWORD in .env)
```

---

### 8. Slow Performance

#### Problem: Database is running slowly

**Cause**: Insufficient resources or too many containers.

**Solutions**:

**Step 1: Check resource usage**

```bash
docker stats
```

**Step 2: Increase Docker resources**

1. Open Docker Desktop
2. Go to Settings → Resources
3. Increase:
   - **Memory**: At least 8GB (16GB recommended)
   - **CPUs**: At least 4 cores
   - **Disk**: At least 20GB
4. Click "Apply & Restart"

**Step 3: Stop other containers**

```bash
# List all running containers
docker ps

# Stop unneeded ones
docker stop <container-name>
```

**Step 4: Clean up Docker**

```bash
# Remove unused images and volumes
docker system prune -a

# Be careful with -v flag (deletes all volumes!)
```

---

### 9. Data Issues

#### Problem: "No data in tables" or "Tables not found"

**Cause**: Migrations didn't run or database was reset.

**Solutions**:

**Step 1: Check if schemas exist**

```bash
docker exec -it dftdb-db psql -U postgres -c "\dn"
```

Should show: `shared`, `trees`, `pointclouds`, `sensor`, `environments`

**Step 2: Check if tables exist**

```bash
docker exec -it dftdb-db psql -U postgres -c "\dt shared.*"
```

**Step 3: If schemas/tables are missing, run migrations**

```bash
# Stop and remove containers (keeps migrations)
docker compose -f docker/docker-compose.yml down

# Start fresh (migrations run automatically on first start)
docker compose -f docker/docker-compose.yml up -d

# Wait 30 seconds for database to initialize

# Check tables again
docker exec -it dftdb-db psql -U postgres -c "\dt shared.*"
```

**Step 4: If reference data is missing**

```bash
# Check if seed migration ran
docker compose logs db | grep "18a-seed-lookup"

# If it didn't run, apply it manually
docker exec -it dftdb-db psql -U postgres -f /docker-entrypoint-initdb.d/migrations/18a-seed-lookup-data.sql
```

---

### 10. Windows-Specific Issues

#### Problem: Line ending errors or script won't run

**Cause**: Git converts line endings on Windows.

**Solutions**:

**For shell scripts (.sh files):**

```bash
# Convert line endings (in Git Bash or WSL)
dos2unix supabase/*.sh

# Or configure git
git config --global core.autocrlf input
```

**For .env file:**

```bash
# Edit in a proper text editor (VS Code, Notepad++, NOT Notepad)
# Make sure it saves with LF line endings, not CRLF
```

---

### 11. WSL2-Specific Issues (Windows)

#### Problem: Can't access localhost:54323 from Windows browser

**Cause**: WSL2 networking configuration.

**Solutions**:

**Option 1: Use localhost (usually works automatically)**

```
http://localhost:54323
```

**Option 2: Find your WSL2 IP address**

```bash
# In WSL2 terminal
hostname -I
# Use this IP from Windows: http://YOUR_WSL_IP:54323
```

**Option 3: Configure port forwarding (PowerShell as Administrator)**

```powershell
# Forward Studio port
netsh interface portproxy add v4tov4 listenport=54323 listenaddress=0.0.0.0 connectport=54323 connectaddress=YOUR_WSL_IP

# Check port forwards
netsh interface portproxy show all

# Remove if needed
netsh interface portproxy delete v4tov4 listenport=54323 listenaddress=0.0.0.0
```

**Option 4: Windows Firewall**

```powershell
# Allow inbound on port 54323
New-NetFirewallRule -DisplayName "Supabase Studio" -Direction Inbound -LocalPort 54323 -Protocol TCP -Action Allow
```

#### Problem: DNS issues in WSL2

**Solutions**:

```bash
# Create or edit /etc/wsl.conf
sudo nano /etc/wsl.conf

# Add:
[network]
generateResolvConf = false

# Then edit resolv.conf
sudo rm /etc/resolv.conf
sudo nano /etc/resolv.conf

# Add:
nameserver 8.8.8.8
nameserver 8.8.4.4

# Restart WSL2 (from PowerShell)
wsl --shutdown
```

---

### 12. Mac-Specific Issues

#### Problem: "Permission denied" errors

**Cause**: Docker Desktop permissions or file ownership.

**Solutions**:

```bash
# Make sure Docker has access to your directories
# Go to: Docker Desktop → Preferences → Resources → File Sharing
# Add your project directory

# Fix file permissions
chmod +x supabase/*.sh
chmod 644 .env
```

---

### 13. Linux-Specific Issues

#### Problem: "Permission denied" when running Docker commands

**Cause**: User not in docker group.

**Solutions**:

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and log back in
# Or run:
newgrp docker

# Test
docker ps
```

---

## 🔍 Advanced Debugging

### View All Logs

```bash
# All services
docker compose -f docker/docker-compose.yml logs

# Follow logs in real-time
docker compose -f docker/docker-compose.yml logs -f

# Last 100 lines
docker compose -f docker/docker-compose.yml logs --tail=100

# Specific service
docker compose -f docker/docker-compose.yml logs db
docker compose -f docker/docker-compose.yml logs kong
docker compose -f docker/docker-compose.yml logs studio
```

### Check Docker Health

```bash
# System info
docker info

# Container details
docker inspect dftdb-db

# Check networks
docker network ls
docker network inspect xr_forests_network
```

### Database Debugging

```bash
# Connect to database
docker exec -it dftdb-db psql -U postgres

# Inside psql:
\l                    # List databases
\dn                   # List schemas
\dt shared.*          # List tables in 'shared'
\d shared.species     # Describe 'species' table
\q                    # Quit

# Check database size
docker exec -it dftdb-db psql -U postgres -c "SELECT pg_size_pretty(pg_database_size('postgres'));"
```

### Network Debugging

```bash
# Test if services can talk to each other
docker exec -it xr_forests_studio ping meta
docker exec -it xr_forests_kong ping db

# Test API endpoint from inside Kong
docker exec -it xr_forests_kong curl http://rest:3000
```

---

## 🆘 Still Having Problems?

### Nuclear Option: Complete Reset

⚠️ **Warning**: This deletes everything and starts fresh!

```bash
cd docker

# 1. Stop all containers
docker compose down -v

# 2. Remove persistent database directory
sudo rm -rf volumes/db/data

# 3. Clean Docker system (optional)
docker system prune -a --volumes

# 4. Verify .env has proper keys (regenerate if needed)
cat .env | grep JWT_SECRET

# 5. Start fresh
docker compose up -d
```

### Gather Information for Help

Before asking for help, gather this information:

```bash
# System info
uname -a                  # Linux/Mac
systeminfo               # Windows

# Docker info
docker --version
docker compose --version
docker info

# Service status
docker compose -f docker/docker-compose.yml ps

# Logs
docker compose -f docker/docker-compose.yml logs > logs.txt

# Your configuration (remove sensitive keys first!)
cat .env | grep -v SECRET | grep -v KEY | grep -v PASSWORD
```

### Get Help

1. **Check existing issues**: Someone might have had the same problem
2. **Search Supabase docs**: <https://supabase.com/docs>
3. **Ask your team lead**: They might have seen this before
4. **Post in team chat**: Include the information from above

---

## ✅ Verification Checklist

Use this to verify everything is working:

```bash
# From the docker directory:
cd docker

# 1. Docker is running
docker ps
# Should list 10+ containers

# 2. All services are up
docker compose ps
# All should show "Up" or "Up (healthy)"

# 3. Studio is accessible
curl http://localhost:54323
# Should return HTML

# 4. API is accessible
curl http://localhost:8000/rest/v1/
# Should return JSON

# 5. Database is accessible
docker exec -it dftdb-db psql -U postgres -c "SELECT version();"
# Should return PostgreSQL version

# 6. Schemas exist
docker exec -it dftdb-db psql -U postgres -c "\dn"
# Should show: shared, trees, pointclouds, sensor, environments

# 7. Reference data exists
docker exec -it dftdb-db psql -U postgres -c "SELECT COUNT(*) FROM shared.species;"
# Should return: 13+ (species reference data)
```

All checks pass? You're good to go! 🎉

---

## 📚 Related Documentation

- [../README.md](../README.md) - Project overview and setup instructions
- [supabase/setup-guide.md](supabase/setup-guide.md) - Detailed production deployment guide
- [VERIFICATION_GUIDE.md](VERIFICATION_GUIDE.md) - Testing and verification

---

**Still stuck? Don't hesitate to ask for help! 🤝**
