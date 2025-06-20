# API Reference - Visual Overview

> **Quick Reference**: Visual overview of all available API endpoints  
> **Interactive Version**: <http://localhost:8000/docs> (when system is running)  
> **Related**: [Developer Guide](./developer_guide.md) | [System Introduction](./system_introduction.md)

This document provides a quick visual reference for all API endpoints in the XR Future Forests Lab system.

## 🌐 **API Endpoint Overview**

### **Current Implemented Endpoints**

```mermaid
flowchart TB
    subgraph API["🚀 XR Future Forests Lab API"]
        BASE[Base URL: http://localhost:8000]
    end
    
    subgraph HEALTH["💚 Health & Status"]
        H1[GET /health<br/>🔍 System health check]
    end
    
    subgraph LOCATIONS["📍 Forest Locations"]
        L1[GET /api/locations/<br/>📋 List all locations]
        L2[GET /api/locations/id/<br/>🔍 Get specific location]
        L3[POST /api/locations/<br/>➕ Create new location]
    end
    
    subgraph TREES["🌳 Tree Management"]
        T1[GET /api/trees/<br/>📋 List trees with filtering]
        T2[GET /api/trees/id/<br/>🔍 Get specific tree]
        T3[POST /api/trees/<br/>➕ Create new tree]
        T4[PUT /api/trees/id/<br/>✏️ Update tree]
        T5[DELETE /api/trees/id/<br/>🗑️ Delete tree]
        T6[GET /api/trees/id/measurements<br/>📏 Get tree measurements]
        T7[POST /api/trees/id/measurements<br/>➕ Add measurement]
        T8[GET /api/trees/id/health<br/>🩺 Get health assessments]
        T9[POST /api/trees/id/health<br/>➕ Add health assessment]
        T10[POST /api/trees/bulk-import<br/>📦 Bulk import trees]
        T11[POST /api/trees/upload-csv<br/>📄 Upload CSV]
    end
    
    subgraph FUTURE["🔄 Coming Soon"]
        F1[GET /api/sensors/<br/>📊 Sensor data]
        F2[GET /api/point-clouds/<br/>☁️ Point cloud data]
        F3[WebSocket /ws<br/>📡 Real-time events]
    end
    
    BASE --> HEALTH
    BASE --> LOCATIONS
    BASE --> TREES
    BASE -.-> FUTURE
    
    classDef api fill:#8cdbc0,stroke:#265e4d,stroke-width:3px
    classDef implemented fill:#71a897,stroke:#183029,stroke-width:2px
    classDef future fill:#e59778,stroke:#612515,stroke-width:2px,stroke-dasharray: 5 5
    
    class API api
    class HEALTH,LOCATIONS,TREES implemented
    class FUTURE future
```

## 📋 **Endpoint Details**

### **Health Check Endpoints**

| Method | Endpoint | Description | Response |
|--------|----------|-------------|----------|
| GET | `/health` | System status check | `{"status": "healthy", "service": "XR Future Forests Lab API", "version": "1.0.0"}` |

**Example Usage:**

```bash
curl http://localhost:8000/health
```

### **Location Management Endpoints**

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/api/locations/` | Get all forest locations | None | Array of location objects |
| GET | `/api/locations/{id}` | Get specific location by ID | None | Single location object |
| POST | `/api/locations/` | Create new location | Location data (JSON) | Created location object |

#### **Location Data Structure**

**Request Schema (POST /api/locations/)**:

```json
{
  "location_name": "string",
  "description": "string (optional)",
  "plot_boundary": {
    "type": "Polygon",
    "coordinates": [[[longitude, latitude], ...]]
  },
  "center_point": {
    "type": "Point", 
    "coordinates": [longitude, latitude]
  }
}
```

**Response Schema**:

```json
{
  "id": "uuid",
  "location_name": "string",
  "description": "string",
  "plot_boundary": {
    "type": "Polygon",
    "coordinates": [[[longitude, latitude], ...]]
  },
  "center_point": {
    "type": "Point",
    "coordinates": [longitude, latitude]
  },
  "created_at": "datetime",
  "updated_at": "datetime"
}
```

### **Tree Management Endpoints**

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/api/trees/` | List trees with optional filtering | None | Array of tree objects |
| GET | `/api/trees/{id}` | Get specific tree by ID | None | Single tree object |
| POST | `/api/trees/` | Create new tree record | Tree data (JSON) | Created tree object |
| PUT | `/api/trees/{id}` | Update existing tree | Tree update data (JSON) | Updated tree object |
| DELETE | `/api/trees/{id}` | Delete tree record | None | Success message |
| GET | `/api/trees/{id}/measurements` | Get all measurements for a tree | None | Array of measurement objects |
| POST | `/api/trees/{id}/measurements` | Add new measurement | Measurement data (JSON) | Created measurement object |
| GET | `/api/trees/{id}/health` | Get health assessments for a tree | None | Array of health assessment objects |
| POST | `/api/trees/{id}/health` | Add new health assessment | Health assessment data (JSON) | Created assessment object |
| POST | `/api/trees/bulk-import` | Import multiple trees | Bulk import data (JSON) | Import result summary |
| POST | `/api/trees/upload-csv` | Upload trees from CSV file | CSV file + location_id | Import result summary |

#### **Tree Data Structure**

**Request Schema (POST /api/trees/)**:

```json
{
  "location_id": "integer",
  "species_id": "integer", 
  "tree_tag": "string (optional)",
  "latitude": "number (optional)",
  "longitude": "number (optional)",
  "elevation_m": "number (optional)",
  "initial_height_m": "number (optional)",
  "initial_dbh_cm": "number (optional)",
  "initial_crown_width_m": "number (optional)",
  "initial_volume_m3": "number (optional)",
  "initial_capture_date": "datetime (optional)"
}
```

**Tree Query Parameters (GET /api/trees/)**:

- `location_id`: Filter by location ID
- `species_name`: Filter by species name
- `min_dbh`, `max_dbh`: DBH range filtering
- `min_height`, `max_height`: Height range filtering
- `health_status`: Filter by health status
- `limit`: Maximum results (default: 100)
- `offset`: Results to skip (default: 0)

**Tree Measurement Schema (POST /api/trees/{id}/measurements)**:

```json
{
  "measurement_date": "datetime (optional, defaults to now)",
  "height_m": "number (optional)",
  "dbh_cm": "number (optional)",
  "crown_width_m": "number (optional)",
  "crown_height_m": "number (optional)",
  "health_status": "string (optional)",
  "measurement_method": "string (optional)",
  "measurement_quality": "string (optional)",
  "notes": "string (optional)",
  "measured_by": "string (optional)"
}
```

## 🧪 **Quick Testing Examples**

### **Test Health Endpoint**

```bash
# Using curl
curl -X GET http://localhost:8000/health

# Expected response
{
  "status": "healthy",
  "service": "XR Future Forests Lab API", 
  "version": "1.0.0"
}
```

### **Test Location Endpoints**

#### **Get All Locations**

```bash
curl -X GET http://localhost:8000/api/locations/
```

#### **Create a New Location**

```bash
curl -X POST "http://localhost:8000/api/locations/" \
  -H "Content-Type: application/json" \
  -d '{
    "location_name": "Test Forest Plot",
    "description": "A test forest location for API demonstration",
    "plot_boundary": {
      "type": "Polygon",
      "coordinates": [[[7.8516, 48.0089], [7.8520, 48.0089], [7.8520, 48.0092], [7.8516, 48.0092], [7.8516, 48.0089]]]
    },
    "center_point": {
      "type": "Point",
      "coordinates": [7.8518, 48.0090]
    }
  }'
```

#### **Get Specific Location**

```bash
# Replace {location_id} with actual UUID from creation response
curl -X GET http://localhost:8000/api/locations/{location_id}
```

### **Test Tree Endpoints**

#### **List All Trees**

```bash
curl -X GET http://localhost:8000/api/trees/
```

#### **Create a New Tree**

```bash
curl -X POST "http://localhost:8000/api/trees/" \
  -H "Content-Type: application/json" \
  -d '{
    "location_id": 1,
    "species_id": 2,
    "tree_tag": "TFP-001",
    "latitude": 48.0090,
    "longitude": 7.8518,
    "elevation_m": 150.5,
    "initial_height_m": 1.2,
    "initial_dbh_cm": 2.5,
    "initial_crown_width_m": 0.8,
    "initial_volume_m3": 0.3,
    "initial_capture_date": "2023-10-01T10:00:00Z"
  }'
```

#### **Get Specific Tree**

```bash
# Replace {tree_id} with actual ID from creation response
curl -X GET http://localhost:8000/api/trees/{tree_id}
```

## 🔄 **Response Status Codes**

| Status Code | Meaning | When It Occurs |
|-------------|---------|----------------|
| **200** | OK | Successful GET request |
| **201** | Created | Successful POST request (resource created) |
| **400** | Bad Request | Invalid request data or malformed JSON |
| **404** | Not Found | Requested resource (location/tree) doesn't exist |
| **422** | Validation Error | Request data doesn't match expected schema |
| **500** | Internal Server Error | Server-side error (database connection, etc.) |

## 🛠️ **Interactive API Testing**

### **Using Swagger UI (Recommended)**

1. **Start the system**: `docker-compose up -d`
2. **Open browser**: <http://localhost:8000/docs>
3. **Interactive testing**: Click on any endpoint to test it directly

### **Using Postman**

1. **Import** the API base URL: `http://localhost:8000`
2. **Create requests** for each endpoint
3. **Set headers**: `Content-Type: application/json` for POST requests

### **Using Python Requests**

```python
import requests
import json

# Base URL
BASE_URL = "http://localhost:8000"

# Test health endpoint
response = requests.get(f"{BASE_URL}/health")
print(response.json())

# Test location creation
location_data = {
    "location_name": "Python Test Location",
    "description": "Created via Python requests",
    "plot_boundary": {
        "type": "Polygon",
        "coordinates": [[[7.8516, 48.0089], [7.8520, 48.0089], [7.8520, 48.0092], [7.8516, 48.0092], [7.8516, 48.0089]]]
    },
    "center_point": {
        "type": "Point",
        "coordinates": [7.8518, 48.0090]
    }
}

response = requests.post(
    f"{BASE_URL}/api/locations/",
    json=location_data,
    headers={"Content-Type": "application/json"}
)
print(response.status_code)
print(response.json())

# Test tree creation
tree_data = {
    "location_id": 1,
    "species_id": 2,
    "tree_tag": "TP-001",
    "latitude": 48.0090,
    "longitude": 7.8518,
    "elevation_m": 150.5,
    "initial_height_m": 1.2,
    "initial_dbh_cm": 2.5,
    "initial_crown_width_m": 0.8,
    "initial_volume_m3": 0.3,
    "initial_capture_date": "2023-10-01T10:00:00Z"
}

response = requests.post(
    f"{BASE_URL}/api/trees/",
    json=tree_data,
    headers={"Content-Type": "application/json"}
)
print(response.status_code)
print(response.json())
```

## 🚀 **Future API Endpoints (In Development)**

### **Tree Management**

```bash
# Planned endpoints
GET    /api/trees/                    # List all trees
GET    /api/trees/{id}                # Get specific tree
POST   /api/trees/                    # Create new tree record
PUT    /api/trees/{id}                # Update tree data
DELETE /api/trees/{id}                # Remove tree record
GET    /api/trees/location/{loc_id}   # Get trees by location
```

### **Sensor Data**

```bash
# Planned endpoints  
GET    /api/sensors/                  # List all sensors
GET    /api/sensors/{id}/data         # Get sensor readings
POST   /api/sensors/{id}/data         # Add new sensor reading
GET    /api/sensors/location/{loc_id} # Get sensors by location
```

### **Point Cloud Data**

```bash
# Planned endpoints
GET    /api/point-clouds/             # List point cloud files
POST   /api/point-clouds/             # Upload new point cloud
GET    /api/point-clouds/{id}         # Get point cloud metadata
POST   /api/point-clouds/{id}/process # Trigger processing
```

### **Real-time Events**

```bash
# Planned WebSocket endpoints
WebSocket /ws/events                  # Real-time event stream
WebSocket /ws/location/{id}/updates   # Location-specific updates
WebSocket /ws/sensors/{id}/stream     # Live sensor data stream
```

## 📚 **Related Documentation**

- **[Interactive API Docs](http://localhost:8000/docs)**: Live, testable API documentation
- **[Developer Guide](./developer_guide.md)**: How to extend and modify APIs  
- **[System Introduction](./system_introduction.md)**: Understanding the technology stack
- **[Database Design](./database_design.md)**: Data models and relationships

---

**💡 Quick Tip**: Always test new endpoints using the interactive documentation at `/docs` before integrating them into your applications!
