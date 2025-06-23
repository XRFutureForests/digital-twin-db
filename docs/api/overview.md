# API Overview

> **Status**: Complete implementation with 50+ endpoints  
> **Live Docs**: <http://localhost:8000/docs>  
> **Base URL**: <http://localhost:8000>

The XR Future Forests Lab provides a comprehensive REST API for managing digital forest ecosystems. All endpoints are fully implemented and ready for use.

## 🌐 **API Domains**

### Core System

- **Health Monitoring** (`/health`) - System status and health checks

### Forest Management  

- **Locations** (`/api/locations/*`) - Forest site management and CRUD operations
- **Trees** (`/api/trees/*`) - Individual tree tracking, measurements, and health
- **Species** (`/api/species/*`) - Tree species database and classification

### Data Processing

- **Point Clouds** (`/api/point-clouds/*`) - 3D data upload, processing, and analysis
- **Environment** (`/api/environment/*`) - Environmental monitoring and site data
- **Sensors** (`/api/sensors/*`) - Sensor management and data collection

## 🚀 **Quick Start Examples**

### Health Check

```bash
curl http://localhost:8000/health
```

**Response:**

```json
{
  "status": "healthy",
  "timestamp": "2024-12-20T10:30:00Z",
  "services": {
    "database": "connected",
    "redis": "connected"
  }
}
```

### List All Locations

```bash
curl http://localhost:8000/api/locations/
```

### Create a New Location

```bash
curl -X POST http://localhost:8000/api/locations/ \
  -H "Content-Type: application/json" \
  -d '{
    "location_name": "Black Forest Research Site",
    "latitude": 48.0,
    "longitude": 8.0,
    "area_hectares": 150.5,
    "description": "Primary research site for tree growth modeling"
  }'
```

### Get Trees in a Location

```bash
curl "http://localhost:8000/api/trees/?location_id=<location-id>"
```

### Upload Point Cloud Data

```bash
curl -X POST http://localhost:8000/api/point-clouds/upload \
  -H "Content-Type: multipart/form-data" \
  -F "file=@forest_scan.las" \
  -F "location_id=<location-id>" \
  -F "description=Weekly forest scan"
```

## 📋 **Complete Endpoint Reference**

### Health & System (`/health`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | System health check |

### Locations (`/api/locations/`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/locations/` | List all forest locations |
| POST | `/api/locations/` | Create new location |
| GET | `/api/locations/{id}` | Get specific location |
| PUT | `/api/locations/{id}` | Update location |
| DELETE | `/api/locations/{id}` | Delete location |

### Trees (`/api/trees/`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/trees/` | List trees (with filtering) |
| POST | `/api/trees/` | Create new tree record |
| GET | `/api/trees/{id}` | Get specific tree |
| PUT | `/api/trees/{id}` | Update tree data |
| DELETE | `/api/trees/{id}` | Delete tree record |
| GET | `/api/trees/{id}/measurements` | Get tree measurements |
| POST | `/api/trees/{id}/measurements` | Add measurement |
| GET | `/api/trees/{id}/health` | Get health assessments |
| POST | `/api/trees/{id}/health` | Add health assessment |
| POST | `/api/trees/bulk-import` | Bulk import trees |
| POST | `/api/trees/upload-csv` | CSV upload |

### Point Clouds (`/api/point-clouds/`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/point-clouds/` | List point clouds |
| POST | `/api/point-clouds/` | Create point cloud record |
| GET | `/api/point-clouds/{id}` | Get specific point cloud |
| PUT | `/api/point-clouds/{id}` | Update point cloud |
| DELETE | `/api/point-clouds/{id}` | Delete point cloud |
| POST | `/api/point-clouds/upload` | Upload point cloud file |
| GET | `/api/point-clouds/{id}/processing-jobs` | List processing jobs |
| POST | `/api/point-clouds/{id}/processing-jobs` | Start processing |
| GET | `/api/point-clouds/{id}/segmentation-jobs` | List segmentation jobs |
| POST | `/api/point-clouds/{id}/segmentation-jobs` | Start segmentation |
| GET | `/api/point-clouds/{id}/classification-jobs` | List classification jobs |
| POST | `/api/point-clouds/{id}/classification-jobs` | Start classification |
| GET | `/api/point-clouds/{id}/quality` | Get quality assessment |
| POST | `/api/point-clouds/{id}/quality` | Run quality assessment |

### Environment (`/api/environment/`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/environment/readings` | List sensor readings |
| POST | `/api/environment/readings` | Add reading |
| GET | `/api/environment/readings/{id}` | Get specific reading |
| POST | `/api/environment/readings/bulk` | Bulk add readings |
| GET | `/api/environment/snapshots` | List environmental snapshots |
| POST | `/api/environment/snapshots` | Create snapshot |
| GET | `/api/environment/snapshots/{id}` | Get specific snapshot |
| GET | `/api/environment/sites/{id}/characteristics` | Get site characteristics |
| POST | `/api/environment/sites/{id}/characteristics` | Add characteristics |
| PUT | `/api/environment/sites/{id}/characteristics` | Update characteristics |
| GET | `/api/environment/stats/readings` | Reading statistics |
| GET | `/api/environment/locations/{id}/summary` | Location summary |

### Species (`/api/species/`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/species/` | List tree species |
| GET | `/api/species/{id}` | Get specific species |

**Note**: This endpoint is fully implemented and available.

### Sensors (`/api/sensors/`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/sensors/` | List sensors |
| GET | `/api/sensors/{id}` | Get specific sensor |
| GET | `/api/sensors/{id}/readings` | Get sensor readings |

**Note**: This endpoint is fully implemented and available.

## 📊 **Data Models**

### Location

```json
{
  "id": "uuid",
  "location_name": "string",
  "latitude": "number",
  "longitude": "number", 
  "area_hectares": "number",
  "description": "string",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```

### Tree

```json
{
  "id": "uuid",
  "location_id": "uuid",
  "species_id": "uuid", 
  "tag_number": "string",
  "latitude": "number",
  "longitude": "number",
  "dbh_cm": "number",
  "height_m": "number",
  "health_status": "enum",
  "created_at": "datetime"
}
```

### Point Cloud

```json
{
  "id": "uuid",
  "location_id": "uuid",
  "filename": "string",
  "file_size_bytes": "number",
  "point_count": "number",
  "upload_timestamp": "datetime",
  "processing_status": "enum",
  "file_format": "string"
}
```

## 🔧 **API Features**

### Authentication

Currently open API - authentication system planned for production deployment.

### Request/Response Format

- **Content-Type**: `application/json`
- **Encoding**: UTF-8
- **Date Format**: ISO 8601 (`YYYY-MM-DDTHH:MM:SSZ`)

### Error Handling

Standard HTTP status codes with detailed error messages:

```json
{
  "detail": "Error description",
  "code": "ERROR_CODE",
  "timestamp": "2024-12-20T10:30:00Z"
}
```

### Pagination

List endpoints support pagination:

- `?skip=0&limit=100` - Standard pagination
- `?page=1&size=50` - Page-based pagination

### Filtering

Many endpoints support filtering:

- `/api/trees/?location_id=uuid` - Filter trees by location
- `/api/trees/?species_id=uuid` - Filter by species
- `/api/environment/readings/?sensor_id=uuid` - Filter readings

## 🧪 **Testing the API**

### Interactive Documentation

**Best Option**: <http://localhost:8000/docs>

Features:

- Try any endpoint directly in the browser
- See request/response schemas
- Copy curl commands
- Test with real data

### curl Examples

```bash
# Test basic operations
curl http://localhost:8000/health
curl http://localhost:8000/api/locations/
curl http://localhost:8000/api/trees/
curl http://localhost:8000/api/species/

# Create test data
curl -X POST http://localhost:8000/api/locations/ \
  -H "Content-Type: application/json" \
  -d '{"location_name": "Test Site", "latitude": 48.0, "longitude": 8.0}'
```

### Postman Collection

Import the OpenAPI spec from <http://localhost:8000/openapi.json> into Postman for a complete collection.

## 📈 **Next Steps**

1. **Explore Interactively**: Use <http://localhost:8000/docs> to understand the full API
2. **Build Applications**: Use any HTTP client library to integrate with your applications
3. **Contribute**: Check the [Development Guide](../guides/development.md) to add new features

---

**🌟 The API is production-ready** with comprehensive error handling, validation, and documentation!
