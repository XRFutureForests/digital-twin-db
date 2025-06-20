"""Tree service layer."""

from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from uuid import UUID, uuid4
from datetime import datetime
import io
import csv

from ..schemas.tree import (
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
from ...database.repositories.tree import TreeRepository


class TreeService:
    """Service layer for tree operations."""

    def __init__(self):
        self.repository = TreeRepository()

    async def get_trees_with_filter(self, db: AsyncSession, query: TreeQuery) -> List[TreeResponse]:
        """Get trees with filtering."""
        trees = await self.repository.get_with_filter(db, query)
        return [self._to_response(tree) for tree in trees]

    async def get_tree_by_id(self, db: AsyncSession, tree_id: str) -> Optional[TreeResponse]:
        """Get tree by ID."""
        tree = await self.repository.get_by_id(db, UUID(tree_id))
        return self._to_response(tree) if tree else None

    async def create_tree(self, db: AsyncSession, tree_data: TreeCreate) -> TreeResponse:
        """Create a new tree."""
        tree_dict = tree_data.dict(exclude_unset=True)

        # Handle coordinate conversion to PostGIS geometry if coordinates provided
        if tree_data.latitude is not None and tree_data.longitude is not None:
            # Remove lat/lon from dict and add position geometry
            tree_dict.pop("latitude", None)
            tree_dict.pop("longitude", None)
            tree_dict.pop("elevation_m", None)
            # Position will be handled by the database model if it supports PostGIS

        tree = await self.repository.create(db, tree_dict)
        return self._to_response(tree)

    async def update_tree(
        self, db: AsyncSession, tree_id: str, tree_data: TreeUpdate
    ) -> Optional[TreeResponse]:
        """Update an existing tree."""
        tree_dict = tree_data.dict(exclude_unset=True)
        tree = await self.repository.update(db, UUID(tree_id), tree_dict)
        return self._to_response(tree) if tree else None

    async def delete_tree(self, db: AsyncSession, tree_id: str) -> bool:
        """Delete a tree."""
        return await self.repository.delete(db, UUID(tree_id))

    async def get_tree_measurements(
        self, db: AsyncSession, tree_id: str
    ) -> List[TreeMeasurementResponse]:
        """Get all measurements for a tree."""
        measurements = await self.repository.get_measurements(db, UUID(tree_id))
        return [self._measurement_to_response(m) for m in measurements]

    async def create_tree_measurement(
        self, db: AsyncSession, tree_id: str, measurement_data: TreeMeasurementCreate
    ) -> TreeMeasurementResponse:
        """Create a new measurement for a tree."""
        measurement_dict = measurement_data.dict(exclude_unset=True)
        measurement_dict["tree_id"] = UUID(tree_id)
        measurement = await self.repository.create_measurement(db, measurement_dict)
        return self._measurement_to_response(measurement)

    async def get_tree_health_assessments(
        self, db: AsyncSession, tree_id: str
    ) -> List[TreeHealthAssessmentResponse]:
        """Get all health assessments for a tree."""
        assessments = await self.repository.get_health_assessments(db, UUID(tree_id))
        return [self._health_assessment_to_response(a) for a in assessments]

    async def create_tree_health_assessment(
        self, db: AsyncSession, tree_id: str, assessment_data: TreeHealthAssessmentCreate
    ) -> TreeHealthAssessmentResponse:
        """Create a new health assessment for a tree."""
        assessment_dict = assessment_data.dict(exclude_unset=True)
        assessment_dict["tree_id"] = UUID(tree_id)
        assessment = await self.repository.create_health_assessment(db, assessment_dict)
        return self._health_assessment_to_response(assessment)

    async def bulk_import_trees(
        self, db: AsyncSession, import_data: TreeBulkImportCreate
    ) -> TreeBulkImportResponse:
        """Bulk import trees."""
        try:
            imported_trees = []
            errors = []

            for tree_data in import_data.trees:
                try:
                    tree = await self.create_tree(db, tree_data)
                    imported_trees.append(str(tree.id))
                except Exception as e:
                    errors.append(f"Error creating tree: {str(e)}")

            return TreeBulkImportResponse(
                import_id=str(uuid4()),  # Use uuid4() instead of UUID()
                total_trees=len(import_data.trees),
                successful_imports=len(imported_trees),
                failed_imports=len(errors),
                errors=errors,
                imported_tree_ids=imported_trees,
                import_timestamp=datetime.now(),
            )
        except Exception as e:
            raise Exception(f"Bulk import failed: {str(e)}")

    async def import_trees_from_csv(
        self, db: AsyncSession, csv_content: bytes, location_id: str
    ) -> TreeBulkImportResponse:
        """Import trees from CSV content."""
        try:
            # Parse CSV content
            csv_string = csv_content.decode("utf-8")
            csv_reader = csv.DictReader(io.StringIO(csv_string))

            trees_data = []
            for row in csv_reader:
                # Helper function to safely convert to float
                def safe_float(value):
                    if value and str(value).strip():
                        try:
                            return float(value)
                        except (ValueError, TypeError):
                            return None
                    return None

                tree_data = TreeCreate(
                    location_id=int(location_id),
                    species_id=int(row.get("species_id", 1)),
                    tree_tag=row.get("tree_tag"),  # Add tree_tag support
                    latitude=safe_float(row.get("latitude")),
                    longitude=safe_float(row.get("longitude")),
                    elevation_m=safe_float(row.get("elevation_m")),
                    initial_height_m=safe_float(row.get("height_m")),
                    initial_dbh_cm=safe_float(row.get("dbh_cm")),
                    initial_crown_width_m=safe_float(row.get("crown_width_m")),
                    initial_volume_m3=safe_float(row.get("volume_m3")),
                )
                trees_data.append(tree_data)

            import_request = TreeBulkImportCreate(
                trees=trees_data, location_id=location_id, import_source="csv_upload"
            )

            return await self.bulk_import_trees(db, import_request)

        except Exception as e:
            raise Exception(f"CSV import failed: {str(e)}")

    def _to_response(self, tree) -> TreeResponse:
        """Convert model to response schema."""
        return TreeResponse(
            id=str(tree.id),  # Convert to string to align with documentation
            location_id=tree.location_id,
            species_id=tree.species_id,
            tree_tag=getattr(tree, "tree_tag", None),  # Handle optional tree_tag
            latitude=getattr(tree, "latitude", None),
            longitude=getattr(tree, "longitude", None),
            elevation_m=getattr(tree, "elevation_m", None),
            initial_capture_date=tree.initial_capture_date,
            initial_height_m=tree.initial_height_m,
            initial_dbh_cm=tree.initial_dbh_cm,
            initial_crown_width_m=tree.initial_crown_width_m,
            initial_volume_m3=tree.initial_volume_m3,
            health_status_id=tree.health_status_id,
            point_cloud_id=tree.point_cloud_id,
            created_at=tree.created_at,
            updated_at=tree.updated_at,
        )

    def _measurement_to_response(self, measurement) -> TreeMeasurementResponse:
        """Convert measurement model to response schema."""
        return TreeMeasurementResponse(
            id=str(measurement.id),
            measurement_date=measurement.measurement_date,
            height_m=measurement.height_m,
            dbh_cm=measurement.dbh_cm,
            crown_width_m=measurement.crown_width_m,
            crown_height_m=measurement.crown_height_m,
            health_status=measurement.health_status,
            measurement_method=measurement.measurement_method,
            measurement_quality=measurement.measurement_quality,
            notes=measurement.notes,
            measured_by=measurement.measured_by,
            created_at=measurement.created_at,
        )

    def _health_assessment_to_response(self, assessment) -> TreeHealthAssessmentResponse:
        """Convert health assessment model to response schema."""
        return TreeHealthAssessmentResponse(
            id=str(assessment.id),
            assessment_date=assessment.assessment_date,
            health_status=assessment.health_status,
            health_score=assessment.health_score,
            disease_indicators=assessment.disease_indicators or [],
            pest_indicators=assessment.pest_indicators or [],
            environmental_stress_indicators=assessment.environmental_stress_indicators or [],
            assessment_method=assessment.assessment_method,
            assessed_by=assessment.assessed_by,
            notes=assessment.notes,
            created_at=assessment.created_at,
        )
