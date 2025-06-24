"""
Main FastAPI application for XR Future Forests Lab MVP
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from xr_forests.api.routers import trees, locations

# Create FastAPI application
app = FastAPI(
    title="XR Future Forests Lab API",
    description="A simple MVP for forest research and management",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(trees.router)
app.include_router(locations.router)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "message": "XR Future Forests Lab API is running"}


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "message": "Welcome to XR Future Forests Lab API",
        "documentation": "/docs",
        "health": "/health",
        "version": "0.1.0",
    }
