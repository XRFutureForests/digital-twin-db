FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for PostgreSQL and PostGIS
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy pyproject.toml and install dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

# Copy source code and configuration
COPY src/ src/
COPY config/ config/

# Create data directory
RUN mkdir -p /app/data

# Expose port
EXPOSE 8000

# Command to run the application
CMD ["python", "-m", "xr_forests.api.main"]
