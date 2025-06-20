# Setup Guide

> **Goal**: Get the XR Future Forests Lab system running in 5 minutes  
> **Prerequisites**: Docker and Docker Compose installed  
> **Result**: Full API access and interactive documentation

## 🚀 **Quick Start**

### 1. Clone and Setup

```bash
# Clone the repository
git clone <repository-url>
cd xr-future-forests-lab

# Run the setup script (creates .env files, checks dependencies)
./setup.sh
```

### 2. Start the Services

```bash
# Start all services in detached mode
docker-compose up -d

# Check all services are running
docker-compose ps
```

You should see output like:

```text
NAME                    IMAGE                     STATUS
xr_forests_api         xr-future-forests-lab     Up
xr_forests_db          postgis/postgis:15-3.3    Up
xr_forests_redis       redis:7-alpine            Up
```

### 3. Verify System Health

```bash
# Check API health
curl http://localhost:8000/health

# Expected response:
# {"status": "healthy", "timestamp": "...", "services": {...}}
```

### 4. Access the API

**Interactive Documentation**: <http://localhost:8000/docs>

This gives you:

- Complete API reference
- Interactive endpoint testing
- Request/response examples
- Schema documentation

## 🛠️ **System Components**

### FastAPI Application (Port 8000)

- **URL**: <http://localhost:8000>
- **Docs**: <http://localhost:8000/docs>
- **Health**: <http://localhost:8000/health>

### PostgreSQL Database (Port 5432)

- **Host**: localhost
- **Port**: 5432
- **Database**: xr_forests_lab
- **User**: forests_user

```bash
# Connect to database
docker exec -it xr_forests_db psql -U forests_user -d xr_forests_lab

# List tables
\dt

# Exit
\q
```

### Redis (Port 6379)

- **Host**: localhost
- **Port**: 6379

```bash
# Connect to Redis
docker exec -it xr_forests_redis redis-cli

# Test Redis
ping
# Should return: PONG

# Exit
exit
```

## 📊 **Test the API**

### Using the Interactive Docs

1. Open <http://localhost:8000/docs>
2. Try the `/health` endpoint first
3. Explore the `/api/locations/` endpoints
4. Create a test location using POST

### Using curl

```bash
# Health check
curl http://localhost:8000/health

# List locations
curl http://localhost:8000/api/locations/

# Create a location
curl -X POST http://localhost:8000/api/locations/ \
  -H "Content-Type: application/json" \
  -d '{"location_name": "Test Forest", "latitude": 48.0, "longitude": 8.0}'
```

## 🔧 **Development Setup**

If you plan to develop, also install Python dependencies:

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install development dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Check code formatting
black src/
isort src/

# Type checking
mypy src/
```

## 🐛 **Troubleshooting**

### Services Won't Start

```bash
# Check for port conflicts
lsof -i :8000  # API port
lsof -i :5432  # PostgreSQL port
lsof -i :6379  # Redis port

# Check Docker logs
docker-compose logs api
docker-compose logs postgres
docker-compose logs redis
```

### Database Connection Issues

```bash
# Check PostgreSQL is ready
docker exec -it xr_forests_db pg_isready -U forests_user

# Restart database
docker-compose restart postgres

# Check database logs
docker-compose logs postgres
```

### API Not Responding

```bash
# Check API logs
docker-compose logs api

# Restart API
docker-compose restart api

# Rebuild if needed
docker-compose up --build api
```

### Reset Everything

```bash
# Stop all services
docker-compose down

# Remove volumes (this deletes all data!)
docker-compose down -v

# Restart fresh
docker-compose up -d
```

## 📈 **Next Steps**

After setup:

1. **Explore the API**: Use <http://localhost:8000/docs> to understand available endpoints
2. **Read the guides**: Check [Project Overview](./project-overview.md) to understand the system
3. **Start developing**: Follow the [Development Guide](./development.md) for contributing

## 🔗 **Quick Reference**

| Service | URL/Command | Purpose |
|---------|-------------|---------|
| **API Docs** | <http://localhost:8000/docs> | Interactive API testing |
| **Health Check** | <http://localhost:8000/health> | System status |
| **Database** | `docker exec -it xr_forests_db psql -U forests_user -d xr_forests_lab` | Direct DB access |
| **Redis** | `docker exec -it xr_forests_redis redis-cli` | Event bus access |
| **Logs** | `docker-compose logs [service]` | Service debugging |
| **Restart** | `docker-compose restart [service]` | Service management |

---

**✅ System ready!** You now have a fully functional XR Future Forests Lab environment.
