import os
import asyncio
import uvicorn
from fastapi import FastAPI, HTTPException, Depends, status, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import text
from contextlib import asynccontextmanager
import redis.asyncio as redis
from typing import List, Optional
from datetime import datetime, date
import json

from models import *
from schemas import *
from database import get_db, engine

# Redis connection
redis_client = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global redis_client
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    redis_client = redis.from_url(redis_url)
    yield
    # Shutdown
    if redis_client:
        await redis_client.close()


# FastAPI app
app = FastAPI(
    title="XR Future Forests Lab API",
    description="API for the XR Future Forests Lab system",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure as needed
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Health check endpoint
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Check database connection
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))

        # Check Redis connection
        await redis_client.ping()

        return {"status": "healthy", "timestamp": datetime.utcnow()}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Service unhealthy: {str(e)}")


# =====================================================
# LOCATION ENDPOINTS
# =====================================================


@app.get("/api/locations", response_model=List[LocationResponse])
async def get_locations(db: AsyncSession = Depends(get_db)):
    """Get all locations"""
    result = await db.execute(
        text(
            """
        SELECT id, location_name, description, elevation_m, 
               ST_AsGeoJSON(center_point) as center_point,
               created_at, updated_at
        FROM locations 
        ORDER BY location_name
    """
        )
    )
    locations = result.fetchall()

    return [
        LocationResponse(
            id=str(location.id),
            location_name=location.location_name,
            description=location.description,
            elevation_m=float(location.elevation_m) if location.elevation_m else None,
            center_point=(
                json.loads(location.center_point) if location.center_point else None
            ),
            created_at=location.created_at,
            updated_at=location.updated_at,
        )
        for location in locations
    ]


@app.get("/api/locations/{location_id}", response_model=LocationResponse)
async def get_location(location_id: str, db: AsyncSession = Depends(get_db)):
    """Get a specific location"""
    result = await db.execute(
        text(
            """
        SELECT id, location_name, description, elevation_m,
               ST_AsGeoJSON(center_point) as center_point,
               created_at, updated_at
        FROM locations 
        WHERE id = :location_id
    """
        ),
        {"location_id": location_id},
    )

    location = result.fetchone()
    if not location:
        raise HTTPException(status_code=404, detail="Location not found")

    return LocationResponse(
        id=str(location.id),
        location_name=location.location_name,
        description=location.description,
        elevation_m=float(location.elevation_m) if location.elevation_m else None,
        center_point=(
            json.loads(location.center_point) if location.center_point else None
        ),
        created_at=location.created_at,
        updated_at=location.updated_at,
    )


@app.post("/api/locations", response_model=LocationResponse)
async def create_location(location: LocationCreate, db: AsyncSession = Depends(get_db)):
    """Create a new location"""
    try:
        # Build the point geometry if coordinates are provided
        point_sql = "NULL"
        params = {
            "location_name": location.location_name,
            "description": location.description,
            "elevation_m": location.elevation_m,
        }

        if location.latitude and location.longitude:
            point_sql = "ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)"
            params["longitude"] = location.longitude
            params["latitude"] = location.latitude

        result = await db.execute(
            text(
                f"""
            INSERT INTO locations (location_name, description, elevation_m, center_point)
            VALUES (:location_name, :description, :elevation_m, {point_sql})
            RETURNING id, location_name, description, elevation_m,
                      ST_AsGeoJSON(center_point) as center_point,
                      created_at, updated_at
        """
            ),
            params,
        )

        await db.commit()
        location_data = result.fetchone()

        # Publish event to Redis
        await redis_client.publish(
            "location_events",
            json.dumps(
                {
                    "event_type": "location_created",
                    "location_id": str(location_data.id),
                    "timestamp": datetime.utcnow().isoformat(),
                }
            ),
        )

        return LocationResponse(
            id=str(location_data.id),
            location_name=location_data.location_name,
            description=location_data.description,
            elevation_m=(
                float(location_data.elevation_m) if location_data.elevation_m else None
            ),
            center_point=(
                json.loads(location_data.center_point)
                if location_data.center_point
                else None
            ),
            created_at=location_data.created_at,
            updated_at=location_data.updated_at,
        )
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=400, detail=str(e))


# =====================================================
# TREE ENDPOINTS
# =====================================================


@app.get("/api/trees", response_model=List[TreeResponse])
async def get_trees(
    location_id: Optional[str] = None,
    species_code: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    """Get all trees with optional filtering"""
    where_conditions = []
    params = {}

    if location_id:
        where_conditions.append("t.location_id = :location_id")
        params["location_id"] = location_id

    if species_code:
        where_conditions.append("s.species_code = :species_code")
        params["species_code"] = species_code

    where_clause = "WHERE " + " AND ".join(where_conditions) if where_conditions else ""

    result = await db.execute(
        text(
            f"""
        SELECT t.id, t.tree_tag, t.discovery_date, t.discovery_method,
               ST_AsGeoJSON(t.position) as position,
               s.scientific_name, s.common_name, s.species_code,
               l.location_name,
               t.created_at, t.updated_at
        FROM trees t
        LEFT JOIN species s ON t.species_id = s.id
        LEFT JOIN locations l ON t.location_id = l.id
        {where_clause}
        ORDER BY t.tree_tag
    """
        ),
        params,
    )

    trees = result.fetchall()

    return [
        TreeResponse(
            id=str(tree.id),
            tree_tag=tree.tree_tag,
            species_scientific_name=tree.scientific_name,
            species_common_name=tree.common_name,
            species_code=tree.species_code,
            location_name=tree.location_name,
            position=json.loads(tree.position) if tree.position else None,
            discovery_date=tree.discovery_date,
            discovery_method=tree.discovery_method,
            created_at=tree.created_at,
            updated_at=tree.updated_at,
        )
        for tree in trees
    ]


@app.get("/api/trees/{tree_id}", response_model=TreeDetailResponse)
async def get_tree(tree_id: str, db: AsyncSession = Depends(get_db)):
    """Get detailed information about a specific tree"""
    # Get tree basic info
    tree_result = await db.execute(
        text(
            """
        SELECT t.id, t.tree_tag, t.discovery_date, t.discovery_method,
               ST_AsGeoJSON(t.position) as position,
               s.scientific_name, s.common_name, s.species_code,
               l.location_name, l.id as location_id,
               t.created_at, t.updated_at
        FROM trees t
        LEFT JOIN species s ON t.species_id = s.id
        LEFT JOIN locations l ON t.location_id = l.id
        WHERE t.id = :tree_id
    """
        ),
        {"tree_id": tree_id},
    )

    tree = tree_result.fetchone()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")

    # Get measurements
    measurements_result = await db.execute(
        text(
            """
        SELECT tm.id, tm.measurement_date, tm.height_m, tm.dbh_cm, 
               tm.crown_width_m, tm.crown_height_m, tm.measurement_method,
               tm.measurement_quality, tm.notes, tm.measured_by,
               hs.status_name as health_status,
               tm.created_at
        FROM tree_measurements tm
        LEFT JOIN health_status_types hs ON tm.health_status_id = hs.id
        WHERE tm.tree_id = :tree_id
        ORDER BY tm.measurement_date DESC
    """
        ),
        {"tree_id": tree_id},
    )

    measurements = measurements_result.fetchall()

    return TreeDetailResponse(
        id=str(tree.id),
        tree_tag=tree.tree_tag,
        species_scientific_name=tree.scientific_name,
        species_common_name=tree.common_name,
        species_code=tree.species_code,
        location_name=tree.location_name,
        location_id=str(tree.location_id),
        position=json.loads(tree.position) if tree.position else None,
        discovery_date=tree.discovery_date,
        discovery_method=tree.discovery_method,
        measurements=[
            TreeMeasurementResponse(
                id=str(m.id),
                measurement_date=m.measurement_date,
                height_m=float(m.height_m) if m.height_m else None,
                dbh_cm=float(m.dbh_cm) if m.dbh_cm else None,
                crown_width_m=float(m.crown_width_m) if m.crown_width_m else None,
                crown_height_m=float(m.crown_height_m) if m.crown_height_m else None,
                health_status=m.health_status,
                measurement_method=m.measurement_method,
                measurement_quality=m.measurement_quality,
                notes=m.notes,
                measured_by=m.measured_by,
                created_at=m.created_at,
            )
            for m in measurements
        ],
        created_at=tree.created_at,
        updated_at=tree.updated_at,
    )


@app.post("/api/trees", response_model=TreeResponse)
async def create_tree(tree: TreeCreate, db: AsyncSession = Depends(get_db)):
    """Create a new tree"""
    try:
        # Build the point geometry
        point_sql = "ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)"
        params = {
            "location_id": tree.location_id,
            "tree_tag": tree.tree_tag,
            "species_id": tree.species_id,
            "longitude": tree.longitude,
            "latitude": tree.latitude,
            "discovery_method": tree.discovery_method,
        }

        result = await db.execute(
            text(
                f"""
            INSERT INTO trees (location_id, tree_tag, species_id, position, discovery_method)
            VALUES (:location_id, :tree_tag, :species_id, {point_sql}, :discovery_method)
            RETURNING id, tree_tag, discovery_date, discovery_method,
                      ST_AsGeoJSON(position) as position, created_at, updated_at
        """
            ),
            params,
        )

        await db.commit()
        tree_data = result.fetchone()

        # Get species and location info
        info_result = await db.execute(
            text(
                """
            SELECT s.scientific_name, s.common_name, s.species_code, l.location_name
            FROM species s, locations l
            WHERE s.id = :species_id AND l.id = :location_id
        """
            ),
            {"species_id": tree.species_id, "location_id": tree.location_id},
        )

        info = info_result.fetchone()

        # Publish event to Redis
        await redis_client.publish(
            "tree_events",
            json.dumps(
                {
                    "event_type": "tree_created",
                    "tree_id": str(tree_data.id),
                    "tree_tag": tree_data.tree_tag,
                    "timestamp": datetime.utcnow().isoformat(),
                }
            ),
        )

        return TreeResponse(
            id=str(tree_data.id),
            tree_tag=tree_data.tree_tag,
            species_scientific_name=info.scientific_name if info else None,
            species_common_name=info.common_name if info else None,
            species_code=info.species_code if info else None,
            location_name=info.location_name if info else None,
            position=json.loads(tree_data.position) if tree_data.position else None,
            discovery_date=tree_data.discovery_date,
            discovery_method=tree_data.discovery_method,
            created_at=tree_data.created_at,
            updated_at=tree_data.updated_at,
        )
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/api/trees/{tree_id}/measurements", response_model=TreeMeasurementResponse)
async def add_tree_measurement(
    tree_id: str, measurement: TreeMeasurementCreate, db: AsyncSession = Depends(get_db)
):
    """Add a new measurement for a tree"""
    try:
        # Get health status ID if provided
        health_status_id = None
        if measurement.health_status:
            health_result = await db.execute(
                text(
                    """
                SELECT id FROM health_status_types WHERE status_name = :status_name
            """
                ),
                {"status_name": measurement.health_status},
            )
            health_row = health_result.fetchone()
            if health_row:
                health_status_id = health_row.id

        params = {
            "tree_id": tree_id,
            "height_m": measurement.height_m,
            "dbh_cm": measurement.dbh_cm,
            "crown_width_m": measurement.crown_width_m,
            "crown_height_m": measurement.crown_height_m,
            "health_status_id": health_status_id,
            "measurement_method": measurement.measurement_method,
            "measurement_quality": measurement.measurement_quality,
            "notes": measurement.notes,
            "measured_by": measurement.measured_by,
            "measurement_date": measurement.measurement_date or datetime.utcnow(),
        }

        result = await db.execute(
            text(
                """
            INSERT INTO tree_measurements 
            (tree_id, measurement_date, height_m, dbh_cm, crown_width_m, crown_height_m,
             health_status_id, measurement_method, measurement_quality, notes, measured_by)
            VALUES (:tree_id, :measurement_date, :height_m, :dbh_cm, :crown_width_m, 
                    :crown_height_m, :health_status_id, :measurement_method, 
                    :measurement_quality, :notes, :measured_by)
            RETURNING id, measurement_date, height_m, dbh_cm, crown_width_m, crown_height_m,
                      measurement_method, measurement_quality, notes, measured_by, created_at
        """
            ),
            params,
        )

        await db.commit()
        measurement_data = result.fetchone()

        # Publish event to Redis
        await redis_client.publish(
            "tree_events",
            json.dumps(
                {
                    "event_type": "tree_measurement_added",
                    "tree_id": tree_id,
                    "measurement_id": str(measurement_data.id),
                    "timestamp": datetime.utcnow().isoformat(),
                }
            ),
        )

        return TreeMeasurementResponse(
            id=str(measurement_data.id),
            measurement_date=measurement_data.measurement_date,
            height_m=(
                float(measurement_data.height_m) if measurement_data.height_m else None
            ),
            dbh_cm=float(measurement_data.dbh_cm) if measurement_data.dbh_cm else None,
            crown_width_m=(
                float(measurement_data.crown_width_m)
                if measurement_data.crown_width_m
                else None
            ),
            crown_height_m=(
                float(measurement_data.crown_height_m)
                if measurement_data.crown_height_m
                else None
            ),
            health_status=measurement.health_status,
            measurement_method=measurement_data.measurement_method,
            measurement_quality=measurement_data.measurement_quality,
            notes=measurement_data.notes,
            measured_by=measurement_data.measured_by,
            created_at=measurement_data.created_at,
        )
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=400, detail=str(e))


# =====================================================
# POINT CLOUD ENDPOINTS
# =====================================================


@app.get("/api/point-clouds", response_model=List[PointCloudResponse])
async def get_point_clouds(
    location_id: Optional[str] = None,
    status: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    """Get all point clouds with optional filtering"""
    where_conditions = []
    params = {}

    if location_id:
        where_conditions.append("pc.location_id = :location_id")
        params["location_id"] = location_id

    if status:
        where_conditions.append("pst.status_name = :status")
        params["status"] = status

    where_clause = "WHERE " + " AND ".join(where_conditions) if where_conditions else ""

    result = await db.execute(
        text(
            f"""
        SELECT pc.id, pc.file_name, pc.scan_date, pc.point_count, pc.file_size_mb,
               pc.scan_resolution_m, pc.created_at,
               pst.status_name as processing_status,
               st.sensor_name,
               l.location_name
        FROM point_clouds pc
        LEFT JOIN processing_status_types pst ON pc.processing_status_id = pst.id
        LEFT JOIN sensor_types st ON pc.sensor_type_id = st.id
        LEFT JOIN locations l ON pc.location_id = l.id
        {where_clause}
        ORDER BY pc.scan_date DESC
    """
        ),
        params,
    )

    point_clouds = result.fetchall()

    return [
        PointCloudResponse(
            id=str(pc.id),
            file_name=pc.file_name,
            scan_date=pc.scan_date,
            processing_status=pc.processing_status,
            sensor_name=pc.sensor_name,
            location_name=pc.location_name,
            point_count=pc.point_count,
            file_size_mb=float(pc.file_size_mb) if pc.file_size_mb else None,
            scan_resolution_m=(
                float(pc.scan_resolution_m) if pc.scan_resolution_m else None
            ),
            created_at=pc.created_at,
        )
        for pc in point_clouds
    ]


# =====================================================
# ENVIRONMENTAL ENDPOINTS
# =====================================================


@app.get("/api/sensors", response_model=List[SensorResponse])
async def get_sensors(
    location_id: Optional[str] = None, db: AsyncSession = Depends(get_db)
):
    """Get all environmental sensors"""
    where_clause = "WHERE es.location_id = :location_id" if location_id else ""
    params = {"location_id": location_id} if location_id else {}

    result = await db.execute(
        text(
            f"""
        SELECT es.id, es.sensor_name, es.installation_date, es.status, es.last_reading_at,
               ST_AsGeoJSON(es.position) as position,
               est.sensor_name as sensor_type, est.measurement_unit,
               l.location_name
        FROM environment_sensors es
        LEFT JOIN environment_sensor_types est ON es.sensor_type_id = est.id
        LEFT JOIN locations l ON es.location_id = l.id
        {where_clause}
        ORDER BY es.sensor_name
    """
        ),
        params,
    )

    sensors = result.fetchall()

    return [
        SensorResponse(
            id=str(sensor.id),
            sensor_name=sensor.sensor_name,
            sensor_type=sensor.sensor_type,
            measurement_unit=sensor.measurement_unit,
            location_name=sensor.location_name,
            position=json.loads(sensor.position) if sensor.position else None,
            installation_date=sensor.installation_date,
            status=sensor.status,
            last_reading_at=sensor.last_reading_at,
        )
        for sensor in sensors
    ]


@app.get(
    "/api/sensors/{sensor_id}/readings", response_model=List[SensorReadingResponse]
)
async def get_sensor_readings(
    sensor_id: str, limit: int = 100, db: AsyncSession = Depends(get_db)
):
    """Get recent readings from a sensor"""
    result = await db.execute(
        text(
            """
        SELECT sr.id, sr.reading_timestamp, sr.value, sr.quality_flag, sr.created_at,
               es.sensor_name, est.measurement_unit
        FROM sensor_readings sr
        JOIN environment_sensors es ON sr.sensor_id = es.id
        JOIN environment_sensor_types est ON es.sensor_type_id = est.id
        WHERE sr.sensor_id = :sensor_id
        ORDER BY sr.reading_timestamp DESC
        LIMIT :limit
    """
        ),
        {"sensor_id": sensor_id, "limit": limit},
    )

    readings = result.fetchall()

    return [
        SensorReadingResponse(
            id=str(reading.id),
            sensor_name=reading.sensor_name,
            reading_timestamp=reading.reading_timestamp,
            value=float(reading.value),
            measurement_unit=reading.measurement_unit,
            quality_flag=reading.quality_flag,
            created_at=reading.created_at,
        )
        for reading in readings
    ]


# =====================================================
# SPECIES ENDPOINTS
# =====================================================


@app.get("/api/species", response_model=List[SpeciesResponse])
async def get_species(db: AsyncSession = Depends(get_db)):
    """Get all species"""
    result = await db.execute(
        text(
            """
        SELECT id, scientific_name, common_name, species_code, 
               max_height_m, longevity_years, created_at
        FROM species
        ORDER BY common_name
    """
        )
    )

    species = result.fetchall()

    return [
        SpeciesResponse(
            id=str(sp.id),
            scientific_name=sp.scientific_name,
            common_name=sp.common_name,
            species_code=sp.species_code,
            max_height_m=float(sp.max_height_m) if sp.max_height_m else None,
            longevity_years=sp.longevity_years,
            created_at=sp.created_at,
        )
        for sp in species
    ]


# =====================================================
# WEBSOCKET FOR REAL-TIME UPDATES
# =====================================================

from fastapi import WebSocket


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()

    # Subscribe to Redis channels
    pubsub = redis_client.pubsub()
    await pubsub.subscribe("tree_events", "location_events", "sensor_events")

    try:
        async for message in pubsub.listen():
            if message["type"] == "message":
                # Forward Redis messages to WebSocket client
                await websocket.send_text(message["data"].decode())
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        await pubsub.unsubscribe("tree_events", "location_events", "sensor_events")
        await pubsub.close()


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=os.getenv("API_HOST", "0.0.0.0"),
        port=int(os.getenv("API_PORT", 8000)),
        reload=os.getenv("ENVIRONMENT") == "development",
    )
