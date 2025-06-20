"""Point cloud router."""

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional

from ...core.schemas.point_cloud import (
    PointCloudCreate,
    PointCloudResponse,
    PointCloudUpdate,
    PointCloudQuery,
    ProcessingJobCreate,
    ProcessingJobResponse,
    SegmentationJobCreate,
    SegmentationJobResponse,
    ClassificationJobCreate,
    ClassificationJobResponse,
    QualityAssessmentResponse,
)
from ...core.services.point_cloud_service import PointCloudService
from ...database.connection import get_db

router = APIRouter(prefix="/api/point-clouds", tags=["point-clouds"])


@router.get("/", response_model=List[PointCloudResponse])
async def get_point_clouds(
    location_id: Optional[str] = Query(None, description="Filter by location ID"),
    capture_method: Optional[str] = Query(None, description="Filter by capture method"),
    processing_status: Optional[str] = Query(None, description="Filter by processing status"),
    min_file_size: Optional[int] = Query(None, description="Minimum file size in bytes"),
    max_file_size: Optional[int] = Query(None, description="Maximum file size in bytes"),
    limit: int = Query(100, description="Maximum number of results"),
    offset: int = Query(0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Get point clouds with optional filtering."""
    query_params = PointCloudQuery(
        location_id=location_id,
        capture_method=capture_method,
        processing_status=processing_status,
        min_file_size=min_file_size,
        max_file_size=max_file_size,
        limit=limit,
        offset=offset,
    )
    return await pc_service.get_point_clouds_with_filter(db, query_params)


@router.get("/{point_cloud_id}", response_model=PointCloudResponse)
async def get_point_cloud(
    point_cloud_id: str,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Get a specific point cloud."""
    point_cloud = await pc_service.get_point_cloud_by_id(db, point_cloud_id)
    if not point_cloud:
        raise HTTPException(status_code=404, detail="Point cloud not found")
    return point_cloud


@router.post("/", response_model=PointCloudResponse)
async def create_point_cloud(
    point_cloud: PointCloudCreate,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Create a new point cloud record."""
    return await pc_service.create_point_cloud(db, point_cloud)


@router.put("/{point_cloud_id}", response_model=PointCloudResponse)
async def update_point_cloud(
    point_cloud_id: str,
    point_cloud_update: PointCloudUpdate,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Update an existing point cloud."""
    point_cloud = await pc_service.update_point_cloud(db, point_cloud_id, point_cloud_update)
    if not point_cloud:
        raise HTTPException(status_code=404, detail="Point cloud not found")
    return point_cloud


@router.delete("/{point_cloud_id}")
async def delete_point_cloud(
    point_cloud_id: str,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Delete a point cloud."""
    success = await pc_service.delete_point_cloud(db, point_cloud_id)
    if not success:
        raise HTTPException(status_code=404, detail="Point cloud not found")
    return {"message": "Point cloud deleted successfully"}


@router.post("/upload", response_model=PointCloudResponse)
async def upload_point_cloud_file(
    file: UploadFile = File(...),
    location_id: str = Query(..., description="Location ID for the point cloud"),
    capture_method: str = Query(..., description="Method used to capture the point cloud"),
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Upload a point cloud file."""
    # Validate file type
    allowed_extensions = [".las", ".laz", ".ply", ".pcd", ".xyz"]
    if not any(file.filename.lower().endswith(ext) for ext in allowed_extensions):
        raise HTTPException(
            status_code=400,
            detail=f"File must have one of these extensions: {', '.join(allowed_extensions)}",
        )

    content = await file.read()
    return await pc_service.upload_point_cloud_file(
        db, content, file.filename, location_id, capture_method
    )


# Processing Jobs endpoints
@router.get("/{point_cloud_id}/processing-jobs", response_model=List[ProcessingJobResponse])
async def get_processing_jobs(
    point_cloud_id: str,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Get all processing jobs for a point cloud."""
    return await pc_service.get_processing_jobs(db, point_cloud_id)


@router.post("/{point_cloud_id}/processing-jobs", response_model=ProcessingJobResponse)
async def create_processing_job(
    point_cloud_id: str,
    job: ProcessingJobCreate,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Create a new processing job for a point cloud."""
    return await pc_service.create_processing_job(db, point_cloud_id, job)


# Segmentation Jobs endpoints
@router.get("/{point_cloud_id}/segmentation-jobs", response_model=List[SegmentationJobResponse])
async def get_segmentation_jobs(
    point_cloud_id: str,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Get all segmentation jobs for a point cloud."""
    return await pc_service.get_segmentation_jobs(db, point_cloud_id)


@router.post("/{point_cloud_id}/segmentation-jobs", response_model=SegmentationJobResponse)
async def create_segmentation_job(
    point_cloud_id: str,
    job: SegmentationJobCreate,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Create a new segmentation job for a point cloud."""
    return await pc_service.create_segmentation_job(db, point_cloud_id, job)


# Classification Jobs endpoints
@router.get("/{point_cloud_id}/classification-jobs", response_model=List[ClassificationJobResponse])
async def get_classification_jobs(
    point_cloud_id: str,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Get all classification jobs for a point cloud."""
    return await pc_service.get_classification_jobs(db, point_cloud_id)


@router.post("/{point_cloud_id}/classification-jobs", response_model=ClassificationJobResponse)
async def create_classification_job(
    point_cloud_id: str,
    job: ClassificationJobCreate,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Create a new classification job for a point cloud."""
    return await pc_service.create_classification_job(db, point_cloud_id, job)


# Quality Assessment endpoints
@router.get("/{point_cloud_id}/quality", response_model=QualityAssessmentResponse)
async def get_quality_assessment(
    point_cloud_id: str,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Get quality assessment for a point cloud."""
    quality = await pc_service.get_quality_assessment(db, point_cloud_id)
    if not quality:
        raise HTTPException(status_code=404, detail="Quality assessment not found")
    return quality


@router.post("/{point_cloud_id}/quality", response_model=QualityAssessmentResponse)
async def run_quality_assessment(
    point_cloud_id: str,
    db: AsyncSession = Depends(get_db),
    pc_service: PointCloudService = Depends(PointCloudService),
):
    """Run quality assessment for a point cloud."""
    return await pc_service.run_quality_assessment(db, point_cloud_id)
