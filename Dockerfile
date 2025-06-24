FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for PostgreSQL
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code and scripts
COPY src/ src/
COPY create_tables.py .
COPY start.sh .
RUN chmod +x start.sh

# Set Python path
ENV PYTHONPATH=/app/src

# Expose port
EXPOSE 8000

# Command to run the application
CMD ["./start.sh"]
