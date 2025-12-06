#!/bin/bash
# Helper script to run CSV importer in Docker
# Automatically detects docker-compose network and environment

set -e

# Get the absolute path to the project root (two levels up from this script)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKER_COMPOSE_DIR="$PROJECT_ROOT/docker"

# Check if docker-compose is running
if ! docker ps --format '{{.Names}}' | grep -q 'dftdb-'; then
    echo "❌ Error: Supabase stack is not running"
    echo "   Start it with: cd $DOCKER_COMPOSE_DIR && docker compose up -d"
    exit 1
fi

# Auto-detect docker-compose network
NETWORK=$(docker ps --filter name='dftdb-' --format '{{json .Networks}}' | head -1 | jq -r 'keys[0]' 2>/dev/null || echo "")
if [[ -z "$NETWORK" ]]; then
    # Fallback: try to find the network by service name
    NETWORK=$(docker inspect dftdb-db -f '{{json .HostConfig.NetworkMode}}' 2>/dev/null | jq -r '.' | sed 's/"//g')
fi

# Use default if detection failed
if [[ -z "$NETWORK" ]] || [[ "$NETWORK" == "host" ]]; then
    NETWORK="digital_forest_twin_db_default"
fi

echo "Detected Docker network: $NETWORK"

# Check if .env file exists
if [[ ! -f "$DOCKER_COMPOSE_DIR/.env" ]]; then
    echo "❌ Error: .env file not found at $DOCKER_COMPOSE_DIR/.env"
    exit 1
fi

# Check if data directory exists
if [[ ! -d "$PROJECT_ROOT/data" ]]; then
    echo "⚠️  Creating data directory at $PROJECT_ROOT/data"
    mkdir -p "$PROJECT_ROOT/data"
fi

# Build the importer image if it doesn't exist
if [[ "$(docker images -q dftdb-csv-importer 2> /dev/null)" == "" ]]; then
    echo "Building CSV importer Docker image..."
    docker build -t dftdb-csv-importer "$DOCKER_COMPOSE_DIR/../scripts/import-data"
fi

# Run the importer with mounted data directory and .env file
docker run --rm \
    --network "$NETWORK" \
    -v "$PROJECT_ROOT/data:/data" \
    -v "$DOCKER_COMPOSE_DIR/.env:/app/.env:ro" \
    dftdb-csv-importer "$@"
