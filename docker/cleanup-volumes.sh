#!/bin/bash

# Helper script to clean up Docker volumes with proper permissions
# This uses Docker itself to handle permission issues

echo "Cleaning up database volumes..."

# Stop containers first
docker compose down

# Use a temporary container with the same postgres image to clean up
# This ensures we have the right permissions
docker run --rm \
  -v "$(pwd)/volumes/db/data:/data" \
  supabase/postgres:15.8.1.085 \
  bash -c "rm -rf /data/*" 2>/dev/null || echo "Data directory already clean or doesn't exist"

echo "Cleanup complete! You can now run: docker compose up"
