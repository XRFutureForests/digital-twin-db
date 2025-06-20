"""Point cloud repository."""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from typing import List, Optional, Any
from uuid import UUID

from .base import BaseRepository
from ...core.models.point_cloud import PointClouds, ProcessingJobs
from ...core.schemas.point_cloud import PointCloudQuery


class PointCloudRepository(BaseRepository[PointClouds]):
    """Repository for point cloud operations."""

    def __init__(self):
        super().__init__(PointClouds)

    async def get_with_filter(self, db: AsyncSession, query: PointCloudQuery) -> List[PointClouds]:
        """Get point clouds with filtering."""
        stmt = select(self.model)

        filters = []
        if query.location_id:
            filters.append(self.model.location_id == int(query.location_id))
        if query.capture_method:
            filters.append(self.model.capture_method == query.capture_method)
        if query.processing_status:
            filters.append(self.model.processing_status == query.processing_status)
        if query.min_file_size:
            filters.append(self.model.file_size_bytes >= query.min_file_size)
        if query.max_file_size:
            filters.append(self.model.file_size_bytes <= query.max_file_size)

        if filters:
            stmt = stmt.where(and_(*filters))

        stmt = stmt.offset(query.offset).limit(query.limit)

        result = await db.execute(stmt)
        return result.scalars().all()

    async def get_processing_jobs(
        self, db: AsyncSession, point_cloud_id: UUID
    ) -> List[ProcessingJobs]:
        """Get processing jobs for a point cloud."""
        stmt = select(ProcessingJobs).where(ProcessingJobs.point_cloud_id == point_cloud_id)
        result = await db.execute(stmt)
        return result.scalars().all()

    async def create_processing_job(self, db: AsyncSession, job_data: dict) -> ProcessingJobs:
        """Create a processing job."""
        job = ProcessingJobs(**job_data)
        db.add(job)
        await db.commit()
        await db.refresh(job)
        return job

    async def get_quality_assessment(self, db: AsyncSession, point_cloud_id: UUID) -> Optional[Any]:
        """Get quality assessment for a point cloud."""
        # Placeholder - would need QualityAssessment model
        return None

    async def create_quality_assessment(self, db: AsyncSession, assessment_data: dict):
        """Create a quality assessment."""
        # Placeholder - would need QualityAssessment model
        pass
