"""Tree router."""

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from uuid import UUID

from ...core.schemas.tree import (
    TreeCreate,
    TreeResponse,
    TreeUpdate,
    TreeQuery,
    TreeMeasurementCreate,
    TreeMeasurementResponse,
    TreeHealthAssessmentCreate,
    TreeHealthAssessmentResponse,
    TreeBulkImportCreate,
    TreeBulkImportResponse,
)
from ...core.services.tree_service import TreeService
from ...database.connection import get_db

router = APIRouter(prefix="/api/trees", tags=["trees"])


@router.get("/", response_model=List[TreeResponse])
async def get_trees(
    location_id: Optional[str] = Query(None, description="Filter by location ID"),
    species_name: Optional[str] = Query(None, description="Filter by species name"),
    min_dbh: Optional[float] = Query(None, description="Minimum DBH in cm"),
    max_dbh: Optional[float] = Query(None, description="Maximum DBH in cm"),
    min_height: Optional[float] = Query(None, description="Minimum height in meters"),
    max_height: Optional[float] = Query(None, description="Maximum height in meters"),
    health_status: Optional[str] = Query(None, description="Filter by health status"),
    limit: int = Query(100, description="Maximum number of results"),
    offset: int = Query(0, description="Number of results to skip"),
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Get trees with optional filtering."""
    query_params = TreeQuery(
        location_id=location_id,
        species_name=species_name,
        min_dbh=min_dbh,
        max_dbh=max_dbh,
        min_height=min_height,
        max_height=max_height,
        health_status=health_status,
        limit=limit,
        offset=offset,
    )
    return await tree_service.get_trees_with_filter(db, query_params)


@router.get("/{tree_id}", response_model=TreeResponse)
async def get_tree(
    tree_id: str,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Get a specific tree."""
    tree = await tree_service.get_tree_by_id(db, tree_id)
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    return tree


@router.post("/", response_model=TreeResponse)
async def create_tree(
    tree: TreeCreate,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Create a new tree."""
    return await tree_service.create_tree(db, tree)


@router.put("/{tree_id}", response_model=TreeResponse)
async def update_tree(
    tree_id: str,
    tree_update: TreeUpdate,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Update an existing tree."""
    tree = await tree_service.update_tree(db, tree_id, tree_update)
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    return tree


@router.delete("/{tree_id}")
async def delete_tree(
    tree_id: str,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Delete a tree."""
    success = await tree_service.delete_tree(db, tree_id)
    if not success:
        raise HTTPException(status_code=404, detail="Tree not found")
    return {"message": "Tree deleted successfully"}


# Tree Measurements endpoints
@router.get("/{tree_id}/measurements", response_model=List[TreeMeasurementResponse])
async def get_tree_measurements(
    tree_id: str,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Get all measurements for a specific tree."""
    return await tree_service.get_tree_measurements(db, tree_id)


@router.post("/{tree_id}/measurements", response_model=TreeMeasurementResponse)
async def create_tree_measurement(
    tree_id: str,
    measurement: TreeMeasurementCreate,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Create a new measurement for a tree."""
    return await tree_service.create_tree_measurement(db, tree_id, measurement)


# Tree Health Assessment endpoints
@router.get("/{tree_id}/health", response_model=List[TreeHealthAssessmentResponse])
async def get_tree_health_assessments(
    tree_id: str,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Get all health assessments for a specific tree."""
    return await tree_service.get_tree_health_assessments(db, tree_id)


@router.post("/{tree_id}/health", response_model=TreeHealthAssessmentResponse)
async def create_tree_health_assessment(
    tree_id: str,
    health_assessment: TreeHealthAssessmentCreate,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Create a new health assessment for a tree."""
    return await tree_service.create_tree_health_assessment(db, tree_id, health_assessment)


# Bulk operations
@router.post("/bulk-import", response_model=TreeBulkImportResponse)
async def bulk_import_trees(
    import_data: TreeBulkImportCreate,
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Bulk import trees from provided data."""
    return await tree_service.bulk_import_trees(db, import_data)


@router.post("/upload-csv", response_model=TreeBulkImportResponse)
async def upload_trees_csv(
    file: UploadFile = File(...),
    location_id: str = Query(..., description="Location ID for all trees in the CSV"),
    db: AsyncSession = Depends(get_db),
    tree_service: TreeService = Depends(TreeService),
):
    """Upload trees from a CSV file."""
    if not file.filename.endswith(".csv"):
        raise HTTPException(status_code=400, detail="File must be a CSV")

    content = await file.read()
    return await tree_service.import_trees_from_csv(db, content, location_id)
