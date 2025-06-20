"""Point cloud service layer."""

from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from ..schemas.point_cloud import (
    PointCloudCreate,
    PointCloudResponse,
    PointCloudUpdate,
    PointCloudQuery,
    ProcessingJobCreate,
    ProcessingJobResponse,
    QualityAssessmentResponse,
)
from ...database.repositories.point_cloud import PointCloudRepository
from ...core.models.point_cloud import PointClouds
from .base import BaseService


class PointCloudService(
    BaseService[PointClouds, PointCloudCreate, PointCloudUpdate, PointCloudResponse]
):
    """Service layer for point cloud operations."""

    def __init__(self):
        super().__init__(PointCloudRepository(), "point_cloud")
        # Keep reference to typed repository for specialized methods
        self._pc_repository = PointCloudRepository()

    async def get_point_clouds_with_filter(
        self, db: AsyncSession, query: PointCloudQuery
    ) -> List[PointCloudResponse]:
        """Get point clouds with filtering."""
        point_clouds = await self._pc_repository.get_with_filter(db, query)
        return [self._to_response(pc) for pc in point_clouds]

    async def get_point_cloud_by_id(
        self, db: AsyncSession, point_cloud_id: str
    ) -> Optional[PointCloudResponse]:
        """Get point cloud by ID."""
        # Use base service method
        return await super().get_by_id(db, point_cloud_id)

    async def create_point_cloud(
        self, db: AsyncSession, point_cloud_data: PointCloudCreate
    ) -> PointCloudResponse:
        """Create a new point cloud."""
        # Use base service method
        return await super().create(db, point_cloud_data)

    async def update_point_cloud(
        self, db: AsyncSession, point_cloud_id: str, point_cloud_data: PointCloudUpdate
    ) -> Optional[PointCloudResponse]:
        """Update an existing point cloud."""
        point_cloud_dict = point_cloud_data.dict(exclude_unset=True)
        point_cloud = await self.repository.update(db, UUID(point_cloud_id), point_cloud_dict)
        return self._to_response(point_cloud) if point_cloud else None

    async def delete_point_cloud(self, db: AsyncSession, point_cloud_id: str) -> bool:
        """Delete a point cloud."""
        return await self.repository.delete(db, UUID(point_cloud_id))

    async def upload_point_cloud_file(
        self, db: AsyncSession, content: bytes, filename: str, location_id: str, capture_method: str
    ) -> PointCloudResponse:
        """Upload and process a point cloud file."""
        # In a real implementation, this would:
        # 1. Save the file to storage (S3, local filesystem, etc.)
        # 2. Extract metadata from the file
        # 3. Create the database record
        # 4. Potentially trigger processing jobs

        point_cloud_data = PointCloudCreate(
            location_id=int(location_id),
            file_path=f"/uploads/{filename}",
            file_name=filename,
            file_size_bytes=len(content),
            capture_method=capture_method,
            capture_date=datetime.now(),
            point_count=0,  # Would be extracted from file
            processing_status="uploaded",
        )

        return await self.create_point_cloud(db, point_cloud_data)

    async def get_processing_jobs(
        self, db: AsyncSession, point_cloud_id: str
    ) -> List[ProcessingJobResponse]:
        """Get processing jobs for a point cloud."""
        jobs = await self._pc_repository.get_processing_jobs(db, UUID(point_cloud_id))
        return [self._processing_job_to_response(job) for job in jobs]

    async def create_processing_job(
        self, db: AsyncSession, point_cloud_id: str, job_data: ProcessingJobCreate
    ) -> ProcessingJobResponse:
        """Create a processing job for a point cloud."""
        job_dict = job_data.dict(exclude_unset=True)
        job_dict["point_cloud_id"] = UUID(point_cloud_id)
        job = await self._pc_repository.create_processing_job(db, job_dict)
        return self._processing_job_to_response(job)

    async def get_segmentation_jobs(self, db: AsyncSession, point_cloud_id: str):
        """Get segmentation jobs for a point cloud."""
        # Implementation would depend on segmentation job repository
        return []

    async def create_segmentation_job(self, db: AsyncSession, point_cloud_id: str, job_data):
        """Create a segmentation job for a point cloud."""
        # Implementation would depend on segmentation job repository
        pass

    async def get_classification_jobs(self, db: AsyncSession, point_cloud_id: str):
        """Get classification jobs for a point cloud."""
        # Implementation would depend on classification job repository
        return []

    async def create_classification_job(self, db: AsyncSession, point_cloud_id: str, job_data):
        """Create a classification job for a point cloud."""
        # Implementation would depend on classification job repository
        pass

    async def get_quality_assessment(
        self, db: AsyncSession, point_cloud_id: str
    ) -> Optional[QualityAssessmentResponse]:
        """Get quality assessment for a point cloud."""
        assessment = await self._pc_repository.get_quality_assessment(db, UUID(point_cloud_id))
        return self._quality_assessment_to_response(assessment) if assessment else None

    async def run_quality_assessment(
        self, db: AsyncSession, point_cloud_id: str
    ) -> QualityAssessmentResponse:
        """Run quality assessment for a point cloud."""
        # In a real implementation, this would trigger quality assessment algorithms
        assessment_data = {
            "point_cloud_id": UUID(point_cloud_id),
            "assessment_date": datetime.now(),
            "overall_quality_score": 85.0,
            "completeness_score": 90.0,
            "accuracy_score": 80.0,
            "density_score": 85.0,
            "noise_level": 5.0,
            "assessment_method": "automated",
        }

        assessment = await self._pc_repository.create_quality_assessment(db, assessment_data)
        return self._quality_assessment_to_response(assessment)

    def _to_response(self, resource: PointClouds) -> PointCloudResponse:
        """Convert model to response schema."""
        return PointCloudResponse(
            id=str(resource.id),
            location_id=resource.location_id,
            file_path=resource.file_path,
            file_name=resource.file_name,
            file_size_bytes=resource.file_size_bytes,
            capture_method=resource.capture_method,
            capture_date=resource.capture_date,
            point_count=resource.point_count,
            processing_status=resource.processing_status,
            metadata=resource.metadata,
            created_at=resource.created_at,
            updated_at=resource.updated_at,
        )

    def _processing_job_to_response(self, job) -> ProcessingJobResponse:
        """Convert processing job model to response schema."""
        return ProcessingJobResponse(
            id=str(job.id),
            point_cloud_id=str(job.point_cloud_id),
            job_type=job.job_type,
            status=job.status,
            parameters=job.parameters,
            start_time=job.start_time,
            end_time=job.end_time,
            error_message=job.error_message,
            results=job.results,
            created_at=job.created_at,
        )

    def _quality_assessment_to_response(self, assessment) -> QualityAssessmentResponse:
        """Convert quality assessment model to response schema."""
        return QualityAssessmentResponse(
            id=str(assessment.id),
            point_cloud_id=str(assessment.point_cloud_id),
            assessment_date=assessment.assessment_date,
            overall_quality_score=assessment.overall_quality_score,
            completeness_score=assessment.completeness_score,
            accuracy_score=assessment.accuracy_score,
            density_score=assessment.density_score,
            noise_level=assessment.noise_level,
            assessment_method=assessment.assessment_method,
            detailed_metrics=assessment.detailed_metrics,
            created_at=assessment.created_at,
        )
