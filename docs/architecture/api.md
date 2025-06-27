# API Architecture

The XR Future Forests Lab implements a comprehensive API layer that enables seamless data flow between the three architectural tiers. This API layer abstracts database operations and provides standardized interfaces for all system components.

## API Overview

```mermaid
%%{
init: {
'theme': 'base',
'themeVariables': {
'fontSize': '14px',
'secondaryColor': '#ababab'
}
}
}%%
flowchart LR

subgraph API_LAYER["API Layer"]
API1[Point Cloud API]
API2[Tree API]
API3[Sensor API]  
API4[Environment API]
API5[Simulation API]
API6[Audit API]
end

subgraph SCHEMAS["Database Schemas"]
SC1[pointclouds schema]
SC2[trees schema]
SC3[monitoring schema]
SC4[environments schema]
SC5[shared schema]
end

subgraph CONSUMERS["API Consumers"]
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
API6 <--> SC5

C1 --> API1
C1 --> API2
C1 --> API3
C1 --> API4
C1 --> API5
C1 --> API6
C2 --> API1
C2 --> API2
C2 --> API3
C2 --> API6
C3 --> API1
C3 --> API2
C3 --> API4
C3 --> API5
C3 --> API6
C4 --> API1
C4 --> API2
C4 --> API3
C4 --> API4
C4 --> API6

%% Subgraph styling
classDef apiLayer fill:#566b8a,stroke:#181d26,stroke-width:2px,color:#e8e8e8
classDef schemaLayer fill:#e8e8e8,stroke:#4f4f4f,stroke-width:2px,color:#242424
classDef consumerLayer fill:#5CB89C,stroke:#19392f,stroke-width:2px,color:#19392f

%% Node styling
classDef apiNode fill:#313D4F,stroke:#181d26,stroke-width:2px,color:#e8e8e8
classDef schemaNode fill:#797979,stroke:#4f4f4f,stroke-width:2px,color:#e8e8e8
classDef consumerNode fill:#38806a,stroke:#19392f,stroke-width:2px,color:#e8e8e8

class API_LAYER apiLayer
class API1,API2,API3,API4,API5,API6 apiNode
class SCHEMAS schemaLayer
class SC1,SC2,SC3,SC4,SC5 schemaNode
class CONSUMERS consumerLayer
class C1,C2,C3,C4 consumerNode

linkStyle 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26 stroke:#313D4F,stroke-width:2px
```

## Core APIs

### Audit API

The Audit API provides field-level change tracking and history management across all variant tables, complementing the variant-based versioning system.

**Key Functionality**:

- **Recording field changes** automatically during PATCH operations
- **Retrieving change history** for specific records with filtering options
- **Reverting field modifications** using audit log data
- **User attribution tracking** for all modifications
- **Bulk change operations** with consolidated audit entries

### Point Cloud API

The Point Cloud API manages all LiDAR data operations, providing endpoints for:

- **Creating base `PointCloud` records** upon file upload
- **Managing `PointCloudVariants`** with processing status tracking
- **PATCH /api/pointclouds/{variant_id}** - Update processing parameters with audit trail
- **GET /api/pointclouds/{variant_id}/history** - Track processing parameter changes
- **Querying point clouds** by location, date range, or processing status
- **Retrieving processing results** and confidence scores

### Tree API

The Tree API serves as the primary interface for forest inventory data, supporting:

- **CRUD operations on `TreeVariants`** with full lineage tracking
- **PATCH /api/trees/{variant_id}** - Update specific fields with automatic audit logging
- **GET /api/trees/{variant_id}/history** - Retrieve complete change history
- **POST /api/trees/{variant_id}/revert** - Revert specific field changes
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
- **PATCH /api/environments/{variant_id}** - Update environmental measurements with audit trail
- **GET /api/environments/{variant_id}/history** - Track environmental parameter changes
- **Supporting scenario-based environmental modeling**
- **Providing environmental context** for growth simulations
- **Integrating user-defined environmental parameters** with change tracking

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
- **Field-Level Audit Integration**: Automatic change tracking for all PATCH operations across variant tables
- **Cross-Schema Integration**: Tree and Environment APIs can access shared schema data for location and species information
- **Multi-Consumer Support**: APIs serve diverse clients from XR components to data ingestion pipelines
- **Temporal Data Handling**: Support for variant-based data with full temporal tracking and lineage
- **Audit Trail Management**: Complete change history with user attribution and revert capabilities
- **Real-time Capabilities**: High-throughput sensor data ingestion with streaming support
- **Spatial Query Support**: Geographic filtering and spatial operations for forest inventory queries

### API Response Formats

All PATCH operations return responses including audit information:

```json
{
  "variant_id": 123,
  "fields_updated": ["Height_m", "DBH_cm"],
  "audit_entries": [
    {
      "audit_id": 456,
      "field_name": "Height_m",
      "old_value": 14.2,
      "new_value": 15.5,
      "timestamp": "2025-06-27T10:30:00Z"
    }
  ],
  "message": "Updated 2 fields with audit logging"
}
```

### Future Considerations

- **OpenAPI Specification**: Consider creating detailed OpenAPI/Swagger specifications for each API
- **Authentication & Authorization**: Implement role-based access control for different user types
- **Rate Limiting**: Add throttling for high-volume operations like sensor data ingestion
- **Caching Strategy**: Implement intelligent caching for frequently accessed tree and environment data
- **Versioning**: Plan API versioning strategy to support evolution while maintaining backward compatibility
