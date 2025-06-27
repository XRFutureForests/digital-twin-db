# API Architecture

The XR Future Forests Lab implements a comprehensive API layer that enables seamless data flow between the three architectural tiers. This API layer abstracts database operations and provides standardized interfaces for all system components.

## API Overview

```mermaid
%%{
init: {
'theme': 'base',
'themeVariables': {
'fontSize': '14px',
'secondaryColor': '#d2d2d2'
}
}
}%%
flowchart LR

subgraph API_LAYER["🔌 API Layer"]
API1[Point Cloud API]
API2[Tree API]
API3[Sensor API]  
API4[Environment API]
API5[Simulation API]
end

subgraph SCHEMAS["🗄️ Database Schemas"]
SC1[pointclouds schema]
SC2[trees schema]
SC3[sensors schema]
SC4[environments schema]
SC5[shared schema]
end

subgraph CONSUMERS["📱 API Consumers"]
C1[XR Lab Components]
C2[Web Interfaces]
C3[Logic Tier Services]
C4[Data Ingestion Pipeline]
end

API1 <--> SC1
API2 <--> SC2
API3 <--> SC3
API4 <--> SC4
API2 <--> SC5
API4 <--> SC5

C1 --> API1
C1 --> API2
C1 --> API3
C1 --> API4
C1 --> API5
C2 --> API1
C2 --> API2
C2 --> API3
C3 --> API1
C3 --> API2
C3 --> API4
C3 --> API5
C4 --> API1
C4 --> API2
C4 --> API3
C4 --> API4

classDef apiLayer fill:#f9f,stroke:#333,stroke-width:2px
classDef schemaLayer fill:#bbf,stroke:#333,stroke-width:2px
classDef consumerLayer fill:#bfb,stroke:#333,stroke-width:2px

class API_LAYER apiLayer
class SCHEMAS schemaLayer
class CONSUMERS consumerLayer
```

## Core APIs

### Point Cloud API

The Point Cloud API manages all LiDAR data operations, providing endpoints for:

- **Creating base `PointCloud` records** upon file upload
- **Managing `PointCloudVariants`** with processing status tracking
- **Querying point clouds** by location, date range, or processing status
- **Retrieving processing results** and confidence scores

### Tree API

The Tree API serves as the primary interface for forest inventory data, supporting:

- **CRUD operations on `TreeVariants`** with full lineage tracking
- **QR code-based tree lookup** for field applications
- **Growth simulation result storage** and retrieval
- **Species and location-based queries** with spatial filtering

### Sensor API

The Sensor API handles environmental monitoring infrastructure:

- **Managing `Sensors`** installation records and metadata
- **High-throughput ingestion** of `SensorReadings` time-series data
- **Real-time sensor status monitoring** and alerting
- **Historical data aggregation** and statistical queries

### Environment API

The Environment API consolidates environmental context data:

- **Creating and managing `EnvironmentVariants`** from sensor aggregations
- **Supporting scenario-based environmental modeling**
- **Providing environmental context** for growth simulations
- **Integrating user-defined environmental parameters**

### Simulation API

The Simulation API orchestrates growth modeling workflows:

- **Interfacing with external models** (SILVA, BALANCE)
- **Managing simulation parameter sets** and scenarios
- **Coordinating data flow** between Tree and Environment APIs
- **Tracking simulation progress** and storing results as TreeVariants

## API Design Principles

This API architecture ensures consistent data access patterns while maintaining the flexibility needed for diverse use cases across XR visualization, web interfaces, and scientific modeling applications.

### Key Design Features

- **Schema Abstraction**: Each API directly maps to specific database schemas while hiding implementation details
- **Cross-Schema Integration**: Tree and Environment APIs can access shared schema data for location and species information
- **Multi-Consumer Support**: APIs serve diverse clients from XR components to data ingestion pipelines
- **Temporal Data Handling**: Support for variant-based data with full temporal tracking and lineage
- **Real-time Capabilities**: High-throughput sensor data ingestion with streaming support
- **Spatial Query Support**: Geographic filtering and spatial operations for forest inventory queries

### Future Considerations

- **OpenAPI Specification**: Consider creating detailed OpenAPI/Swagger specifications for each API
- **Authentication & Authorization**: Implement role-based access control for different user types
- **Rate Limiting**: Add throttling for high-volume operations like sensor data ingestion
- **Caching Strategy**: Implement intelligent caching for frequently accessed tree and environment data
- **Versioning**: Plan API versioning strategy to support evolution while maintaining backward compatibility
