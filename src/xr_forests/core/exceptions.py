"""Custom exceptions for the XR Forests application."""

from typing import Optional, Any, Dict


class XRForestsException(Exception):
    """Base exception for XR Forests application."""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None):
        self.message = message
        self.details = details or {}
        super().__init__(self.message)


class NotFoundError(XRForestsException):
    """Exception raised when a resource is not found."""

    def __init__(self, resource: str, identifier: str, details: Optional[Dict[str, Any]] = None):
        message = f"{resource} with ID '{identifier}' not found"
        super().__init__(message, details)
        self.resource = resource
        self.identifier = identifier


class ValidationError(XRForestsException):
    """Exception raised when data validation fails."""

    def __init__(
        self, field: str, value: Any, message: str, details: Optional[Dict[str, Any]] = None
    ):
        full_message = f"Validation error for field '{field}': {message}"
        super().__init__(full_message, details)
        self.field = field
        self.value = value


class DatabaseError(XRForestsException):
    """Exception raised when database operations fail."""

    def __init__(self, operation: str, message: str, details: Optional[Dict[str, Any]] = None):
        full_message = f"Database {operation} failed: {message}"
        super().__init__(full_message, details)
        self.operation = operation


class ImportError(XRForestsException):
    """Exception raised when import operations fail."""

    def __init__(
        self,
        import_type: str,
        message: str,
        errors: Optional[list] = None,
        details: Optional[Dict[str, Any]] = None,
    ):
        full_message = f"{import_type} import failed: {message}"
        super().__init__(full_message, details)
        self.import_type = import_type
        self.errors = errors or []


class ProcessingError(XRForestsException):
    """Exception raised when processing operations fail."""

    def __init__(self, process_type: str, message: str, details: Optional[Dict[str, Any]] = None):
        full_message = f"{process_type} processing failed: {message}"
        super().__init__(full_message, details)
        self.process_type = process_type


class ConfigurationError(XRForestsException):
    """Exception raised when configuration is invalid."""

    def __init__(self, config_item: str, message: str, details: Optional[Dict[str, Any]] = None):
        full_message = f"Configuration error for '{config_item}': {message}"
        super().__init__(full_message, details)
        self.config_item = config_item
