"""Environment service layer."""

from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from ..schemas.environment import (
    SensorReadingCreate,
    SensorReadingResponse,
    SiteCharacteristicsCreate,
    SiteCharacteristicsResponse,
    EnvironmentalQuery,
    SensorReadingBulkCreate,
    SensorReadingBulkResponse,
)
from ...database.repositories.environment import EnvironmentRepository
from ...core.models.environment import SensorReadings
from .base import BaseService


class EnvironmentService(
    BaseService[SensorReadings, SensorReadingCreate, SensorReadingCreate, SensorReadingResponse]
):
    """Service layer for environment operations."""

    def __init__(self):
        super().__init__(EnvironmentRepository(), "sensor_reading")
        # Keep reference to typed repository for specialized methods
        self._env_repository = EnvironmentRepository()

    async def get_sensor_readings_with_filter(
        self, db: AsyncSession, query: EnvironmentalQuery
    ) -> List[SensorReadingResponse]:
        """Get sensor readings with filtering."""
        readings = await self._env_repository.get_sensor_readings_with_filter(db, query)
        return [self._to_response(reading) for reading in readings]

    async def create_sensor_reading(
        self, db: AsyncSession, reading_data: SensorReadingCreate
    ) -> SensorReadingResponse:
        """Create a new sensor reading."""
        # Use base service create method
        return await super().create(db, reading_data)

    async def bulk_create_sensor_readings(
        self, db: AsyncSession, readings_data: SensorReadingBulkCreate
    ) -> SensorReadingBulkResponse:
        """Bulk create sensor readings."""
        try:
            created_readings = []
            errors = []

            for reading_data in readings_data.readings:
                try:
                    reading = await self.create_sensor_reading(db, reading_data)
                    created_readings.append(str(reading.id))
                except Exception as e:
                    errors.append(f"Error creating reading: {str(e)}")

            return SensorReadingBulkResponse(
                total_readings=len(readings_data.readings),
                successful_imports=len(created_readings),
                failed_imports=len(errors),
                errors=errors,
                created_reading_ids=created_readings,
                import_timestamp=datetime.now(),
            )
        except Exception as e:
            raise Exception(f"Bulk import failed: {str(e)}")

    async def get_environment_snapshots(
        self,
        db: AsyncSession,
        location_id: Optional[str],
        start_date: Optional[datetime],
        end_date: Optional[datetime],
        limit: int,
        offset: int,
    ):
        """Get environment snapshots."""
        snapshots = await self._env_repository.get_environment_snapshots(
            db, location_id, start_date, end_date, limit, offset
        )
        return [self._environment_snapshot_to_response(snapshot) for snapshot in snapshots]

    async def get_environment_snapshot_by_id(self, db: AsyncSession, snapshot_id: str):
        """Get environment snapshot by ID."""
        snapshot = await self._env_repository.get_environment_snapshot_by_id(db, UUID(snapshot_id))
        return self._environment_snapshot_to_response(snapshot) if snapshot else None

    async def create_environment_snapshot(self, db: AsyncSession, snapshot_data):
        """Create environment snapshot."""
        snapshot_dict = snapshot_data.dict(exclude_unset=True)
        snapshot = await self._env_repository.create_environment_snapshot(db, snapshot_dict)
        return self._environment_snapshot_to_response(snapshot)

    async def get_site_characteristics(
        self, db: AsyncSession, location_id: str
    ) -> Optional[SiteCharacteristicsResponse]:
        """Get site characteristics for a location."""
        characteristics = await self._env_repository.get_site_characteristics(db, int(location_id))
        return self._site_characteristics_to_response(characteristics) if characteristics else None

    async def create_site_characteristics(
        self, db: AsyncSession, location_id: str, characteristics_data: SiteCharacteristicsCreate
    ) -> SiteCharacteristicsResponse:
        """Create site characteristics for a location."""
        characteristics_dict = characteristics_data.dict(exclude_unset=True)
        characteristics_dict["location_id"] = int(location_id)
        characteristics = await self._env_repository.create_site_characteristics(
            db, characteristics_dict
        )
        return self._site_characteristics_to_response(characteristics)

    async def update_site_characteristics(
        self, db: AsyncSession, location_id: str, characteristics_data: SiteCharacteristicsCreate
    ) -> Optional[SiteCharacteristicsResponse]:
        """Update site characteristics for a location."""
        characteristics_dict = characteristics_data.dict(exclude_unset=True)
        characteristics = await self._env_repository.update_site_characteristics(
            db, int(location_id), characteristics_dict
        )
        return self._site_characteristics_to_response(characteristics) if characteristics else None

    async def get_sensor_reading_statistics(
        self,
        db: AsyncSession,
        location_id: Optional[str],
        sensor_type: Optional[str],
        parameter_type: Optional[str],
        start_time: Optional[datetime],
        end_time: Optional[datetime],
        aggregation: str,
    ):
        """Get sensor reading statistics."""
        return await self._env_repository.get_sensor_reading_statistics(
            db, location_id, sensor_type, parameter_type, start_time, end_time, aggregation
        )

    async def get_location_environment_summary(
        self,
        db: AsyncSession,
        location_id: str,
        start_date: Optional[datetime],
        end_date: Optional[datetime],
    ):
        """Get environmental summary for a location."""
        return await self._env_repository.get_location_environment_summary(
            db, int(location_id), start_date, end_date
        )

    def _to_response(self, resource: SensorReadings) -> SensorReadingResponse:
        """Convert sensor reading model to response schema."""
        return SensorReadingResponse(
            id=str(resource.id),
            location_id=resource.location_id,
            sensor_type=resource.sensor_type,
            parameter_type=resource.parameter_type,
            reading_value=resource.reading_value,
            unit=resource.unit,
            reading_timestamp=resource.reading_timestamp,
            quality_flag=resource.quality_flag,
            calibration_status=resource.calibration_status,
            metadata=resource.metadata,
            created_at=resource.created_at,
        )

    def _sensor_reading_to_response(self, reading) -> SensorReadingResponse:
        """Convert sensor reading model to response schema."""
        return SensorReadingResponse(
            id=str(reading.id),
            location_id=reading.location_id,
            sensor_type=reading.sensor_type,
            parameter_type=reading.parameter_type,
            reading_value=reading.reading_value,
            unit=reading.unit,
            reading_timestamp=reading.reading_timestamp,
            quality_flag=reading.quality_flag,
            calibration_status=reading.calibration_status,
            metadata=reading.metadata,
            created_at=reading.created_at,
        )

    def _environment_snapshot_to_response(self, snapshot):
        """Convert environment snapshot model to response schema."""
        # Implementation depends on the exact snapshot model structure
        return {
            "id": str(snapshot.id),
            "location_id": snapshot.location_id,
            "snapshot_date": snapshot.snapshot_date,
            # Add other fields as needed
        }

    def _site_characteristics_to_response(self, characteristics) -> SiteCharacteristicsResponse:
        """Convert site characteristics model to response schema."""
        return SiteCharacteristicsResponse(
            id=str(characteristics.id),
            location_id=characteristics.location_id,
            soil_type=characteristics.soil_type,
            slope_degree=characteristics.slope_degree,
            aspect_degree=characteristics.aspect_degree,
            dominant_tree_species=characteristics.dominant_tree_species,
            forest_type=characteristics.forest_type,
            management_type=characteristics.management_type,
            disturbance_history=characteristics.disturbance_history,
            site_index=characteristics.site_index,
            climate_zone=characteristics.climate_zone,
            moisture_regime=characteristics.moisture_regime,
            nutrient_regime=characteristics.nutrient_regime,
            created_at=characteristics.created_at,
            updated_at=characteristics.updated_at,
        )
