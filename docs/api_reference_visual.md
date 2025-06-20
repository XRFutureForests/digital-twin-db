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
        L2[GET /api/locations/{id}<br/>🔍 Get specific location]
        L3[POST /api/locations/<br/>➕ Create new location]
    end
    
    subgraph FUTURE["🔄 Coming Soon"]
        F1[GET /api/trees/<br/>🌳 Tree management]
        F2[GET /api/sensors/<br/>📊 Sensor data]
        F3[GET /api/point-clouds/<br/>☁️ Point cloud data]
        F4[WebSocket /ws<br/>📡 Real-time events]
    end
    
    BASE --> HEALTH
    BASE --> LOCATIONS
    BASE -.-> FUTURE
    
    classDef api fill:#e8f5e8,stroke:#2e7d2e,stroke-width:3px
    classDef implemented fill:#d4edda,stroke:#155724,stroke-width:2px
    classDef future fill:#fff3cd,stroke:#856404,stroke-width:2px,stroke-dasharray: 5 5
    
    class API api
    class HEALTH,LOCATIONS implemented
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

## 🔄 **Response Status Codes**

| Status Code | Meaning | When It Occurs |
|-------------|---------|----------------|
| **200** | OK | Successful GET request |
| **201** | Created | Successful POST request (resource created) |
| **400** | Bad Request | Invalid request data or malformed JSON |
| **404** | Not Found | Requested resource (location) doesn't exist |
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
