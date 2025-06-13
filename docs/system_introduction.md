# Technology Stack and Data Flow Introduction

> **For newcomers to APIs, databases, and messaging systems**  
> **Related Documentation**: [Architecture](./architecture.md) | [Database Design](./database_design.md) | [Event Bus Alternatives](./event_bus_alternatives.md)

This document provides a beginner-friendly introduction to the key technologies in your XR Future Forests Lab system, explaining what they do, how they work together, and how data flows through the entire system.

---

## 🎯 **What Are We Building?**

Your XR Future Forests Lab is a system that:

1. **Collects** forest data from multiple sources:
   - **3DTrees Platform**: LiDAR point cloud data
   - **EcoSense Sensors**: Real-time environmental monitoring
   - **Climate/Weather Data**: External climate datasets
   - **Soil/Groundwater Data**: Soil composition and moisture monitoring
   - **Forest Inventory**: Traditional field survey measurements

2. **Processes** this data through sophisticated pipelines:
   - Tree segmentation and species classification from point clouds
   - Growth simulation using models like SILVA, BALANCE, and iLand
   - Environmental data aggregation and analysis

3. **Presents** results through immersive interfaces:
   - XR (Virtual/Augmented Reality) forest exploration
   - Web-based dashboards and analysis tools
   - Real-time monitoring and visualization

Think of it like a digital twin of a forest that researchers can explore and analyze in immersive 3D environments.

---

## 🧩 **Key Technologies Explained**

The XR Future Forests Lab follows a **three-tier architecture** that separates concerns across different layers:

- **🗄️ Data Tier**: Handles data storage and ingestion
- **⚙️ Logic Tier**: Processes data and runs simulations  
- **🖥️ Presentation Tier**: Provides user interfaces and visualization

Let's explore the key technologies in each tier:

### **Databases: Your Data Storage (Data Tier)**

A **database** is like a super-organized filing cabinet that can instantly find any piece of information you need.

#### **PostgreSQL** - Your Main Database

- **What it is**: A powerful, reliable database that stores structured data in tables (like Excel spreadsheets)
- **What it stores in your system**:
  - Tree information (species, location, measurements)
  - Sensor data (environmental readings, scan metadata)
  - Processing job status and results
  - User information and permissions

```
Think of it like this:
📊 Excel Spreadsheet = Database Table
📋 Row in Excel = Record in Database  
📝 Column in Excel = Field in Database
🗂️ Multiple Excel files = Multiple Database Tables
```

#### **Your Three Specialized Databases**

1. **Point Cloud Database**: Stores LiDAR scan metadata, processing job status, and results
   - Metadata about 3D forest scans (file references, processing status)
   - Tree segmentation and species classification results
   - Processing job tracking and quality metrics

2. **Tree Database**: Stores individual tree records, measurements, and modeling data
   - Tree identity, measurements (height, DBH, crown dimensions)
   - **Tree variants for scenario-based modeling**: Multiple versions of trees for different scenarios (growth simulations, species replacements, management interventions)
   - Detailed 3D structural data (branches, twigs, leaves)
   - Quality assessments and microhabitat features

3. **Environment Database**: Stores sensor readings and environmental data
   - Real-time sensor data (temperature, humidity, soil conditions)
   - Environmental snapshots for modeling
   - Site characteristics and spatial datasets

### **APIs: How Different Parts Talk to Each Other (Logic + Presentation Tier)**

An **API** (Application Programming Interface) is like a waiter in a restaurant - it takes your order, goes to the kitchen, and brings back your food. It's how different software components communicate.

The Logic Tier handles sophisticated processing through specialized components:

- **Point Cloud Processing Pipeline**: Tree segmentation, species classification, attribute extraction
- **Simulation Models**: SILVA, BALANCE, and iLand forest growth models  
- **Model Registry/Orchestrator**: Manages and coordinates different simulation models
- **Tree Model Service**: Generates 3D tree structures and handles growth simulation

#### **REST APIs** - Your Main Communication Method

- **What they are**: A standardized way for software to request and receive data
- **How they work**: Using HTTP requests (the same technology that loads web pages)

**Example API calls in your system:**

```http
GET /api/tree/{tree_id}           → "Get information about a specific tree"
POST /api/data-ingest/pointcloud  → "Upload LiDAR scan files"
POST /api/process/segment         → "Start tree segmentation job"
GET /api/process/status/{job_id}  → "Check processing job status"
PUT /api/tree/{tree_id}          → "Update tree measurements"
```

#### **Data Contracts** - The Rules for Communication

Think of these as "conversation rules" that ensure everyone speaks the same language.

**Example - When uploading a new tree measurement:**

```json
{
  "tree_id": "T_001_2025",
  "species_id": "FASY-15",
  "measurements": {
    "height_m": 25.05,
    "dbh_cm": 12.3,
    "crown_width_m": 8.2,
    "height_quality": {
      "overall_grade": "A",
      "confidence_score": 0.95,
      "measurement_source": "Point_Cloud_Derived"
    }
  },
  "location": {
    "latitude": 47.1234,
    "longitude": 8.5678,
    "coordinate_system": "EPSG:4326"
  },
  "measurement_date": "2025-06-13T14:30:00Z"
}
```

This contract says: "When you send tree data, it must include these exact fields with these data types."

### **API Types and Interface Patterns in Your System**

Now that you understand the basics of APIs, let's look at the different types of APIs your XR Future Forests Lab system uses:

#### **Key Elements of an API**

- **Endpoints**: URLs or paths for accessing specific functions or data
- **Methods**: Operations like GET (retrieve), POST (create), PUT (update), DELETE (remove)
- **Request/Response Formats**: Data structures (often JSON) for communication
- **Parameters/Headers**: Additional data for filtering, authentication, etc.
- **Status Codes**: Indicate the result of a request (e.g., 200 OK, 404 Not Found)

#### **1. Data Ingestion API** - Getting Data Into Your System

**Purpose**: Handles the intake of new data from external sources (sensors, field uploads, external datasets)

**How it works**: Provides endpoints for batch uploads (CSV, LAS/LAZ files) and streaming data (sensor feeds)

**Example Endpoints**:

```
POST /api/data-ingest/pointcloud    → Upload LiDAR scan files
POST /api/data-ingest/sensor-data   → Real-time sensor readings
POST /api/data-ingest/field-data    → Manual field measurements
```

#### **2. Processing Pipeline API** - Managing Background Tasks

**Purpose**: Manages the submission, monitoring, and results of data processing tasks (tree segmentation, classification)

**How it works**: Submit jobs, check status, and retrieve results with asynchronous processing

**Example Endpoints**:

```
POST /api/process/segment           → Submit new tree segmentation job
GET /api/process/status/{job_id}    → Check job progress
GET /api/process/result/{job_id}    → Download processing results
```

#### **3. Database Update API** - Modifying Your Data

**Purpose**: Allows authorized components to create, update, or delete records in the databases

**How it works**: CRUD operations (Create, Read, Update, Delete) on database records

**Example Endpoints**:

```
PUT /api/tree/{id}                  → Update tree measurements
POST /api/tree                     → Add new tree to database
DELETE /api/environment/{id}       → Remove environmental record
```

#### **4. Model/Simulation Control API** - Running Forest Simulations

**Purpose**: Allows clients to trigger, pause, or modify model runs and simulations

**How it works**: Control forest growth simulations and climate modeling

**Example Endpoints**:

```
POST /api/model/run                 → Start forest growth simulation
GET /api/model/status/{job_id}      → Check simulation progress
POST /api/model/control             → Pause/resume simulation
```

#### **5. Event Bus** - Real-Time Notifications

**Purpose**: Enables real-time, asynchronous communication between components

**How it works**: Components subscribe to topics and receive messages as events occur

**Example Topics**:

```
sensor-updates          → New temperature/humidity readings
tree-updates           → Tree growth or health changes
simulation-progress    → Model execution updates
system-alerts          → Important system notifications
```

#### **6. REST/GraphQL API** - General Data Access

**Purpose**: Provides standardized web-based access to backend services and data for clients

**How it works**:

- **REST**: Uses HTTP methods and endpoints for each resource
- **GraphQL**: Allows clients to specify exactly what data they need

**Examples**:

```
REST:     GET /api/tree/123 → Get all data for tree #123
GraphQL:  query { tree(id: 123) { species, height, health } } → Get only specific fields
```

#### **API Type Comparison**

| API Type | Purpose | When to Use | Example |
|----------|---------|-------------|---------|
| **Data Ingestion** | Import new data | Uploading files, sensor data | Upload LiDAR scans |
| **Processing Pipeline** | Manage background jobs | Heavy computation tasks | Tree identification |
| **Database Update** | Modify stored data | Data corrections, updates | Fix tree measurements |
| **Simulation Control** | Run forest models | Scientific modeling | Growth predictions |
| **Event Bus** | Real-time notifications | Live updates, monitoring | Sensor alerts |
| **REST/GraphQL** | General data access | Web/mobile apps, XR clients | Display tree data |

### **Event Buses: Real-Time Communication**

An **event bus** is like a notification system that tells different parts of your system when something important happens.

#### **Redis** - Your Recommended Event Bus

- **What it is**: A fast, in-memory data store that can also handle messaging
- **What it does**: Sends instant notifications between different parts of your system
- **Communication protocols**: Supports Redis Streams, MQTT topics for sensor data, and WebSocket connections for real-time XR updates

**Example events in your system:**

```text
"Processing job completed" → Notify XR client to update display
"New sensor reading" → Trigger analysis algorithms  
"Tree model updated" → Refresh simulation display
"System alert" → Notify administrators of issues
```

**Real-time communication channels:**

- **MQTT Topics**: `ecosense/sensor/reading` for EcoSense sensor data
- **WebSocket**: `/ws/sensor-stream` for live sensor feeds to XR clients
- **Redis Streams**: Internal event coordination between services

### **Docker: Packaging Your Software**

**Docker** is like shipping containers for software - it packages everything needed to run a piece of software into a portable container.

#### **Docker Compose** - Running Multiple Containers

- **What it is**: A tool that starts and connects multiple Docker containers
- **In your system**: Runs PostgreSQL, Redis, your API server, and other services together

```yaml
# docker-compose.yml - Like a recipe for your entire system
services:
  database:          # PostgreSQL container
  redis:             # Redis container  
  api-server:        # Your FastAPI application
  web-client:        # Your web interface
```

---

## 🌊 **Data Flow Through Your System**

Let's trace how data moves through your XR Future Forests Lab system with a real example:

### **Scenario: Processing a New LiDAR Forest Scan**

#### **Step 1: Data Collection**

```
🌲 Forest → 📡 LiDAR Scanner → 💾 Point Cloud File (.las)
```

- Researcher scans forest section with LiDAR
- Creates a 3D point cloud file (millions of 3D points)

#### **Step 2: Data Upload**

```
📱 Researcher's App → 🌐 REST API → 🗄️ PostgreSQL Database
```

**API Call:**

```http
POST /api/point-clouds
Content-Type: application/json

{
  "file_path": "/data/scans/forest_section_A_2025_06_13.las",
  "scan_date": "2025-06-13T14:30:00Z",
  "location_id": 5,
  "sensor_type": "UAV_LiDAR",
  "quality_metrics": {
    "point_density": 150.5,
    "coverage_area": 2500.0
  }
}
```

**Database Storage:**

```sql
-- New record created in PointClouds table
INSERT INTO PointClouds (FilePath, ScanDate, LocationID, SensorTypeID, ProcessingStatusTypeID)
VALUES ('/data/scans/forest_section_A_2025_06_13.las', '2025-06-13 14:30:00', 5, 2, 1);
```

#### **Step 3: Processing Job Creation**

```
🗄️ Database → 📨 Event Bus → ⚙️ Processing Pipeline
```

**Event Published to Redis:**

```json
{
  "event_type": "new_scan_uploaded",
  "point_cloud_id": 1523,
  "priority": "normal",
  "timestamp": "2025-06-13T14:31:00Z"
}
```

**Processing Job Created:**

```sql
-- New job record in ProcessingJobs table
INSERT INTO processing_jobs (job_type, status, input_data, created_at)
VALUES ('tree_segmentation', 'queued', 
        '{"point_cloud_id": 1523}', NOW());
```

#### **Step 4: Background Processing**

```
⚙️ Processing Service → 🧠 AI Algorithms → 🌳 Tree Identification
```

**Processing steps:**

1. **Tree Segmentation**: AI algorithms identify and isolate individual trees from the point cloud
2. **Species Classification**: Machine learning models analyze tree morphology to identify species
3. **Tree Attribute Extraction**: Extract biometric measurements (height, DBH, crown dimensions) and health indicators
4. **Data Quality Assessment**: Evaluate measurement confidence and assign quality grades
5. **Database Updates**: Store results in Tree Database with full lineage tracking

#### **Step 5: Results Storage**

```
🌳 Processing Results → 🗄️ Database → 📨 Event Notifications
```

**New tree records created:**

```sql
-- TreeVariants created from point cloud processing
INSERT INTO TreeVariants (TreeVariantID, TreeID, SpeciesID, ScenarioID, Height_m, DBH_cm, VariantTimestamp)
VALUES 
  ('TV_A_001_2025', 'T_A_001_2025', 15, 1, 24.55, 18.2, NOW()),
  ('TV_A_002_2025', 'T_A_002_2025', 23, 1, 19.83, 14.7, NOW()),
  ('TV_A_003_2025', 'T_A_003_2025', 15, 1, 31.21, 22.9, NOW());

-- Update processing job status
UPDATE ProcessingJobs 
SET ProcessingStatusTypeID = 3, CompletedAt = NOW()
WHERE ProcessingJobID = 1089;
```

**Event published:**

```json
{
  "event_type": "processing_completed",
  "job_id": 1089,
  "trees_found": 23,
  "processing_time_seconds": 145
}
```

#### **Step 6: Real-Time Updates**

```
📨 Redis Event → 🌐 WebSocket → 🥽 XR Client → 👤 Researcher
```

**WebSocket message to XR client:**

```json
{
  "type": "scan_processed",
  "location_id": 5,
  "new_trees": 23,
  "scan_id": 1523,
  "message": "Forest section A scan completed - 23 trees identified"
}
```

#### **Step 7: XR Visualization**

```
🥽 XR Headset → 🌐 API Request → 🗄️ Database → 🌲 3D Forest Visualization
```

**API request for XR display:**

```http
GET /api/locations/5/trees?include_3d_models=true
```

**Response with tree data:**

```json
{
  "location": {
    "id": 5,
    "name": "Forest Section A",
    "center_point": {"lat": 47.1234, "lng": 8.5678}
  },
  "trees": [
    {
      "id": "T_A_001_2025",
      "species": "Norway Spruce",
      "height_cm": 245.5,
      "position": {"x": 123.4, "y": 0.0, "z": 567.8},
      "model_url": "/3d-models/norway_spruce_adult.gltf"
    }
  ]
}
```

---

## 🔄 **System Communication Patterns**

### **Synchronous Communication (API Calls)**

- **When**: Getting data, updating records, user interactions
- **How**: Direct HTTP requests and responses
- **Example**: User clicks "Show tree details" → API call → Database query → Response

### **Asynchronous Communication (Events)**

- **When**: Background processing, real-time updates, notifications
- **How**: Messages sent through Redis event bus
- **Example**: File upload completes → Event published → Processing starts automatically

### **Data Persistence Layers**

#### **Hot Data** (Frequently Accessed)

- **Storage**: PostgreSQL database
- **Examples**: Current tree measurements, active processing jobs
- **Access pattern**: Direct SQL queries through APIs

#### **Warm Data** (Occasionally Accessed)

- **Storage**: File system with database references
- **Examples**: 3D point cloud files, processed imagery
- **Access pattern**: Database metadata + file system retrieval

#### **Cold Data** (Archive/Historical)

- **Storage**: Cloud storage or archive systems
- **Examples**: Old scans, historical measurements
- **Access pattern**: Database pointers + cloud/archive retrieval

---

## 🔧 **Technology Stack Summary**

### **Your System Uses:**

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Database** | PostgreSQL | Store structured data (trees, measurements, jobs) |
| **Event Bus** | Redis Streams | Real-time messaging between components |
| **API Framework** | FastAPI (Python) | Handle HTTP requests and responses |
| **3D Visualization** | Three.js / WebGL | Render 3D forest models in browsers/XR |
| **Containerization** | Docker + Docker Compose | Package and run all services together |
| **Processing** | Python + AI/ML libraries | Analyze point clouds and identify trees |

### **Why These Choices?**

1. **PostgreSQL**: Excellent for complex queries, handles spatial data (forest locations)
2. **Redis**: Super fast for real-time notifications, perfect for XR responsiveness  
3. **FastAPI**: Python-based, automatic API documentation, async support
4. **Docker**: Consistent environment across development and production

---

## 🚀 **Next Steps**

Now that you understand the basics:

1. **Explore the code**: Look at the FastAPI endpoints in your API server
2. **Check the database**: Use a tool like pgAdmin to browse your PostgreSQL tables
3. **Monitor events**: Use Redis CLI or Redis Commander to see events flowing
4. **Test APIs**: Use tools like Postman or curl to make API calls

The beauty of this architecture is that each component has a clear, single responsibility, making the system easier to understand, develop, and maintain!

---

## 💡 **Key Takeaways**

- **Databases** store your data permanently
- **APIs** let different parts of your system talk to each other
- **Event buses** handle real-time notifications and background processing
- **Docker** packages everything together consistently
- **Your system** follows a clear data flow from collection → processing → storage → visualization

Each technology solves a specific problem, and together they create a robust system for forest research and XR visualization!
