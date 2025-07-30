# Tech Stack - XR Future Forests Lab

## Overview

The XR Future Forests Lab uses a modern, scalable tech stack designed for handling large spatial datasets, real-time sensor data, and complex forest modeling workflows. The architecture emphasizes performance, reliability, and developer productivity.

## Core Technologies

### **PostgreSQL with PostGIS**

**Role**: Primary database and spatial data engine

**Functionality**:

- **Spatial Database**: PostGIS extension enables native handling of geometric data (tree positions, location boundaries, sensor locations)
- **ACID Compliance**: Ensures data integrity across complex forest monitoring transactions
- **Advanced Indexing**: Spatial indexes (GiST) optimize queries on forest plots and point cloud boundaries
- **Schema Organization**: Five specialized schemas (`shared`, `pointclouds`, `trees`, `sensor`, `environments`) organize domain data
- **Variant Lineage**: Self-referencing foreign keys track data processing chains and modifications

**Key Features for Forest Monitoring**:

- Native geometry types for plot boundaries and tree positions
- Spatial queries for proximity analysis and area calculations
- Time-series optimization for sensor readings
- Junction tables for explicit polymorphic relationships

---

### **nginx**

**Role**: Reverse proxy, API gateway, and static file server

**Functionality**:

- **API Gateway**: Routes `/api/*` requests to FastAPI backend with load balancing
- **Large File Handling**: Optimized for LiDAR point cloud uploads (up to 2GB files)
- **Static Content**: Serves web applications and processed point cloud files
- **Caching**: Implements intelligent caching strategies for point cloud downloads
- **SSL Termination**: Handles HTTPS encryption and certificate management

**Forest-Specific Features**:

- Upload progress tracking for large LiDAR files
- Efficient serving of processed point clouds with range request support
- Compression for web assets and API responses

---

### **Redis**

**Role**: Caching layer and event bus

**Functionality**:

- **API Response Caching**: Caches expensive spatial queries and point cloud metadata
- **Session Management**: Stores user authentication and application state
- **Real-time Events**: Pub/Sub messaging for processing status updates
- **Background Job Queue**: Manages async point cloud processing tasks

**Use Cases**:

- Cache tree search results by location/species
- Store point cloud processing progress
- Real-time notifications for completed analysis
- Session data for field app users

---

### **FastAPI**

**Role**: REST API backend framework

**Functionality**:

- **Async/Await**: Non-blocking operations for database and file system access
- **Automatic Documentation**: OpenAPI/Swagger docs generated from code
- **Pydantic Validation**: Type-safe request/response models with data validation
- **Dependency Injection**: Clean separation of concerns and testability

**API Structure**:

```
/api/pointclouds/     # LiDAR data management
/api/trees/           # Tree measurements and simulations  
/api/sensors/         # Environmental sensor data
/api/environments/    # Environmental condition variants
/api/audit/           # Change tracking and history
```

---

### **Python Ecosystem**

**Role**: Primary programming language and runtime

**Core Libraries**:

- **SQLAlchemy**: ORM with async support for database operations
- **AsyncPG**: High-performance PostgreSQL adapter
- **Pydantic**: Data validation and settings management
- **Alembic**: Database migration management

**Scientific Libraries** (planned):

- **GeoPandas**: Spatial data analysis and manipulation
- **Rasterio**: Raster data processing for elevation models
- **Shapely**: Geometric operations and spatial analysis
- **NumPy/SciPy**: Numerical computing for growth models

---

### **SQLAlchemy**

**Role**: Object-Relational Mapping (ORM) and database toolkit

**Functionality**:

- **Async Support**: Non-blocking database operations with asyncpg
- **Schema Reflection**: Automatic mapping of PostgreSQL schemas to Python models
- **Query Builder**: Type-safe query construction with relationship loading
- **Connection Pooling**: Efficient database connection management

**Forest Data Patterns**:

- Variant base classes with inheritance for Trees, PointClouds, Environments
- Spatial data types integration with PostGIS
- Junction table relationships for ProcessParameters and AuditLog
- Optimized queries for time-series sensor data

---

## Data Flow Example: LiDAR Point Cloud Processing

Let's trace how a LiDAR point cloud flows through the entire system, from upload to tree detection results:

### 1. **File Upload**

```
User uploads 500MB LAS file via 3DTrees web interface
↓
nginx receives upload at /uploads/plot_001_scan_20250703.las
├─ Handles large file efficiently (no FastAPI blocking)
├─ Stores in /var/uploads/ with progress tracking
└─ Returns upload confirmation with file ID
```

### 2. **Metadata Creation**

```
FastAPI /api/pointclouds/ endpoint called
↓
Pydantic validates request data:
├─ LocationID: 15 (Forest Plot A)
├─ SensorModel: "Leica BLK360"
├─ ScanDate: "2025-07-03T14:30:00Z"
└─ FilePath: "/uploads/plot_001_scan_20250703.las"
↓
SQLAlchemy creates PointCloud record:
├─ VariantID: 1001 (auto-generated)
├─ VariantTypeID: 1 ("original")
├─ ProcessingStatus: NULL (original scan)
└─ PostgreSQL stores with spatial index on ScanBounds
```

### 3. **Processing Initiation**

```
Background job queued in Redis:
├─ Job: "process_pointcloud"
├─ VariantID: 1001
└─ Priority: "normal"
↓
Point Cloud Processing Service starts:
├─ Creates processing variant (VariantID: 1002)
├─ ParentVariantID: 1001 (lineage tracking)
├─ ProcessingStatus: "processing"
└─ ProcessID: 25 ("LiDAR_Tree_Segmentation_v2.1")
```

### 4. **Tree Segmentation**

```
Processing algorithm analyzes point cloud:
├─ Identifies 47 individual trees
├─ Confidence scores: 0.85-0.98
└─ Generates tree centroids and boundaries
↓
Creates Tree variants for each detection:
├─ TreeVariant 2001: Fagus sylvatica (Beech)
│   ├─ PointCloudVariantID: 1002 (source reference)
│   ├─ Position: POINT(125.3 78.9) (plot coordinates)
│   ├─ Height_m: 24.7
│   └─ Volume_m3: 2.15
├─ TreeVariant 2002: Quercus robur (Oak)
└─ ... (45 more trees)
```

### 5. **Process Parameters Tracking**

```
Junction tables record algorithm settings:
shared.ProcessParameters_PointClouds:
├─ ParameterID: 301 ("min_points_per_tree")
├─ VariantID: 1002
└─ ParameterValue: "100"

shared.ProcessParameters_Trees:
├─ ParameterID: 302 ("height_threshold_m")  
├─ VariantID: 2001
└─ ParameterValue: "2.0"
```

### 6. **Caching and Optimization**

```
Redis caches expensive queries:
├─ Key: "trees:location:15:species:fagus"
├─ Value: [2001, 2015, 2023, ...] (Tree IDs)
└─ TTL: 1 hour

nginx caches processed files:
├─ /pointclouds/plot_001_processed.las
├─ Cache-Control: "public, max-age=86400"
└─ Accept-Ranges: bytes (for partial downloads)
```

### 7. **Real-time Updates**

```
Processing completion triggers events:
├─ Redis pub/sub: "pointcloud:1002:completed"
├─ WebSocket notification to connected clients
└─ Email notification to forest manager
↓
PostgreSQL updates:
├─ ProcessingStatus: "completed"
├─ PointCount: 15,847,239
└─ UpdatedAt: NOW()
```

### 8. **API Access and Visualization**

```
Field researcher queries via QR code scan:
GET /api/trees/2001
↓
FastAPI handler:
├─ SQLAlchemy loads TreeVariant with relationships
├─ Includes Species, TreeStatus, Stems data
├─ Spatial query for nearby trees
└─ Pydantic serializes response

Web visualization requests processed point cloud:
GET /pointclouds/plot_001_processed.las
↓
nginx serves file:
├─ Range request support for large files
├─ Gzip compression if supported
└─ Cache headers for browser optimization
```

### 9. **Audit Trail**

```
Field measurement update triggers audit:
PUT /api/trees/2001 {"Height_m": 24.9}
↓
Audit system records change:
shared.AuditLog:
├─ AuditID: 5001
├─ FieldName: "Height_m"
├─ OldValue: "24.7"
├─ NewValue: "24.9"
├─ UserID: "forester@university.edu"
└─ ChangeReason: "Field verification measurement"

shared.AuditLog_Trees:
├─ AuditID: 5001
└─ VariantID: 2001
```

## Performance Characteristics

### **Scalability**

- **Horizontal**: nginx load balancing across multiple FastAPI instances
- **Database**: PostgreSQL read replicas for heavy query workloads
- **Storage**: Distributed file storage for large point cloud archives

### **Throughput**

- **Point Cloud Processing**: 100-500MB files in 2-10 minutes
- **API Requests**: 1000+ requests/second with Redis caching
- **Sensor Data**: Real-time ingestion of 1000+ sensors at 1Hz

### **Reliability**

- **Database ACID**: Transaction integrity across complex forest data
- **File Integrity**: Checksums and backup verification for LiDAR data
- **Error Recovery**: Automatic retry and graceful degradation

This tech stack provides a robust foundation for the XR Future Forests Lab, enabling efficient processing of large spatial datasets while maintaining flexibility for future research requirements.
