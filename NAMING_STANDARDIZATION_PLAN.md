# Naming Standardization Plan

## Principles

1. **Singular nouns only** - All classes, models, schemas use singular forms
2. **No unnecessary suffixes** - Remove `Types`, `Status`, etc. unless absolutely necessary
3. **Simple, implicit naming** - Use the most obvious, shortest name
4. **Consistent patterns** - Same pattern across models, schemas, services, repositories

## Standardization Map

### Models (Database Tables → Code Models)

| Current Model Name | Database Table | New Model Name | Reason |
|-------------------|----------------|----------------|---------|
| `Locations` | `locations` | `Location` | Singular form |
| `Trees` | `trees` | `Tree` | Singular form |
| `Species` | `species` | `Species` | Already correct |
| `PointClouds` | `point_clouds` | `PointCloud` | Singular form |
| `Sensors` | `environment_sensors` | `Sensor` | Simplified, singular |
| `SensorReadings` | `sensor_readings` | `Reading` | Simplified, context clear |
| `EnvironmentalSnapshots` | `environmental_snapshots` | `Snapshot` | Simplified |
| `EnvironmentSensorTypes` | `environment_sensor_types` | `SensorType` | Simplified |
| `HealthStatusTypes` | `health_status_types` | `HealthStatus` | Remove redundant "Types" |
| `ProcessingStatusTypes` | `processing_status_types` | `ProcessingStatus` | Remove redundant "Types" |

### Schemas

| Current | New | Reason |
|---------|-----|---------|
| `LocationCreate` | `LocationCreate` | Keep (clear purpose) |
| `LocationUpdate` | `LocationUpdate` | Keep (clear purpose) |
| `LocationResponse` | `LocationResponse` | Keep (clear purpose) |
| `LocationQuery` | `LocationQuery` | Keep (clear purpose) |

### Services

| Current | New | Reason |
|---------|-----|---------|
| `LocationService` | `LocationService` | Keep (clear) |
| `TreeService` | `TreeService` | Keep (clear) |

### Repositories

| Current | New | Reason |
|---------|-----|---------|
| `LocationRepository` | `LocationRepository` | Keep (clear) |
| `TreeRepository` | `TreeRepository` | Keep (clear) |

## Implementation Order

1. Update base models (Location, Tree, Species, etc.)
2. Update dependent schemas and services
3. Update repositories
4. Update API routers
5. Update imports throughout codebase
6. Test all endpoints
