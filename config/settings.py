"""Centralized settings management using Pydantic."""

import os
from typing import Optional, List
from pydantic import field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings with environment variable support."""

    # Database Configuration
    database_url: str = (
        "postgresql+asyncpg://forests_user:forests_password@localhost:5432/xr_forests_lab"
    )
    database_echo: bool = False
    database_pool_size: int = 10
    database_max_overflow: int = 20

    # Redis Configuration
    redis_url: str = "redis://localhost:6379/0"
    redis_socket_timeout: int = 5
    redis_connection_pool_max_connections: int = 50

    # API Configuration
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_reload: bool = False
    api_workers: int = 1

    # Environment and Debug
    environment: str = "development"
    debug: bool = False
    testing: bool = False

    # Security
    secret_key: Optional[str] = None
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30

    # CORS
    cors_origins: List[str] = ["*"]
    cors_allow_credentials: bool = True
    cors_allow_methods: List[str] = ["*"]
    cors_allow_headers: List[str] = ["*"]

    # Logging
    log_level: str = "INFO"
    log_format: str = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

    # Data Processing
    max_file_size: int = 100 * 1024 * 1024  # 100MB
    upload_dir: str = "data/uploads"
    processed_dir: str = "data/processed"
    export_dir: str = "data/exports"

    @field_validator("environment")
    @classmethod
    def validate_environment(cls, v):
        """Validate environment setting."""
        valid_environments = ["development", "testing", "staging", "production"]
        if v not in valid_environments:
            raise ValueError(f"Environment must be one of: {valid_environments}")
        return v

    @field_validator("database_echo")
    @classmethod
    def set_database_echo(cls, v, info):
        """Auto-enable database echo in development."""
        if info.data.get("environment") == "development":
            return True
        return v

    @field_validator("api_reload")
    @classmethod
    def set_api_reload(cls, v, info):
        """Auto-enable reload in development."""
        if info.data.get("environment") == "development":
            return True
        return v

    @field_validator("debug")
    @classmethod
    def set_debug(cls, v, info):
        """Auto-enable debug in development."""
        if info.data.get("environment") == "development":
            return True
        return v

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False
        env_prefix = "XR_FORESTS_"


class DevelopmentSettings(Settings):
    """Development-specific settings."""

    environment: str = "development"
    debug: bool = True
    database_echo: bool = True
    api_reload: bool = True
    log_level: str = "DEBUG"


class TestingSettings(Settings):
    """Testing-specific settings."""

    environment: str = "testing"
    testing: bool = True
    database_url: str = (
        "postgresql+asyncpg://forests_user:forests_password@localhost:5432/xr_forests_test"
    )
    redis_url: str = "redis://localhost:6379/1"  # Different Redis DB for testing


class ProductionSettings(Settings):
    """Production-specific settings."""

    environment: str = "production"
    debug: bool = False
    database_echo: bool = False
    api_reload: bool = False
    cors_origins: List[str] = []  # Should be configured specifically for production
    log_level: str = "WARNING"


def get_settings() -> Settings:
    """Get settings based on environment."""
    env = os.getenv("XR_FORESTS_ENVIRONMENT", "development").lower()

    if env == "development":
        return DevelopmentSettings()
    elif env == "testing":
        return TestingSettings()
    elif env == "production":
        return ProductionSettings()
    else:
        return Settings()


# Global settings instance
settings = get_settings()
