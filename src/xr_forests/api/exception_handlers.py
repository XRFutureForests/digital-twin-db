"""Global exception handlers for the API."""

from fastapi import Request
from fastapi.responses import JSONResponse

from ..core.exceptions import (
    NotFoundError,
    DatabaseError,
    ValidationError,
    ImportError,
    ProcessingError,
    ConfigurationError,
)


async def not_found_exception_handler(request: Request, exc: NotFoundError) -> JSONResponse:
    """Handle NotFoundError exceptions."""
    return JSONResponse(
        status_code=404,
        content={
            "detail": str(exc),
            "type": "not_found",
            "resource": exc.resource,
            "resource_id": exc.identifier,
        },
    )


async def database_exception_handler(request: Request, exc: DatabaseError) -> JSONResponse:
    """Handle DatabaseError exceptions."""
    return JSONResponse(
        status_code=500,
        content={
            "detail": str(exc),
            "type": "database_error",
            "operation": exc.operation,
        },
    )


async def validation_exception_handler(request: Request, exc: ValidationError) -> JSONResponse:
    """Handle ValidationError exceptions."""
    return JSONResponse(
        status_code=422,
        content={
            "detail": str(exc),
            "type": "validation_error",
            "field": exc.field,
            "value": str(exc.value),
        },
    )


async def import_exception_handler(request: Request, exc: ImportError) -> JSONResponse:
    """Handle ImportError exceptions."""
    return JSONResponse(
        status_code=400,
        content={
            "detail": str(exc),
            "type": "import_error",
            "import_type": exc.import_type,
            "errors": exc.errors,
        },
    )


async def processing_exception_handler(request: Request, exc: ProcessingError) -> JSONResponse:
    """Handle ProcessingError exceptions."""
    return JSONResponse(
        status_code=500,
        content={
            "detail": str(exc),
            "type": "processing_error",
            "process_type": exc.process_type,
        },
    )


async def configuration_exception_handler(
    request: Request, exc: ConfigurationError
) -> JSONResponse:
    """Handle ConfigurationError exceptions."""
    return JSONResponse(
        status_code=500,
        content={
            "detail": str(exc),
            "type": "configuration_error",
            "config_item": exc.config_item,
        },
    )


# Dictionary mapping exception types to their handlers
EXCEPTION_HANDLERS = {
    NotFoundError: not_found_exception_handler,
    DatabaseError: database_exception_handler,
    ValidationError: validation_exception_handler,
    ImportError: import_exception_handler,
    ProcessingError: processing_exception_handler,
    ConfigurationError: configuration_exception_handler,
}
