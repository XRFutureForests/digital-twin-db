"""Health check router."""

from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "XR Future Forests Lab API", "version": "1.0.0"}
