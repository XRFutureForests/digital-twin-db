#!/bin/bash
# Sync sensor data from Aquarius API
# Requires: University VPN connection for Aquarius access
# Runs inside a Docker container - no host dependencies needed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$DOCKER_DIR/.env" ]; then
    export SERVICE_ROLE_KEY=$(grep -E "^SERVICE_ROLE_KEY=" "$DOCKER_DIR/.env" | cut -d '=' -f2-)
    export AQUARIUS_HOSTNAME=$(grep -E "^AQUARIUS_HOSTNAME=" "$DOCKER_DIR/.env" | cut -d '=' -f2-)
fi

# Default values
DAYS_BACK=${1:-30}
# Use internal Docker network URL for container-to-container communication
API_URL="http://kong:8000"

echo "========================================"
echo "Aquarius Data Sync"
echo "========================================"
echo "Days back: $DAYS_BACK"
echo ""

# Check if services are running
if ! docker compose -f "$DOCKER_DIR/docker-compose.yml" ps --quiet kong &>/dev/null; then
    echo "Error: Kong API gateway is not running"
    echo "Start services with: docker compose up -d"
    exit 1
fi

# Check VPN connectivity to Aquarius from edge-functions container
echo "Checking Aquarius connectivity..."
if ! docker exec dftdb-edge-functions sh -c "wget -q --spider --timeout=5 '${AQUARIUS_HOSTNAME:-http://fuhys006.public.ads.uni-freiburg.de}/AQUARIUS/'" 2>/dev/null; then
    echo "Warning: Cannot reach Aquarius server from container"
    echo "Make sure you are connected to the university VPN"
    echo ""
fi

echo "Calling ecosense-ingest function..."
echo ""

# Get the Docker network name (matches docker-compose project)
NETWORK_NAME=$(docker network ls --format '{{.Name}}' | grep -E "digital.*forest.*twin.*default|dftdb.*default" | head -1)
if [ -z "$NETWORK_NAME" ]; then
    # Fallback: try to get network from running kong container
    NETWORK_NAME=$(docker inspect dftdb-kong --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null | head -1)
fi

if [ -z "$NETWORK_NAME" ]; then
    echo "Error: Could not determine Docker network name"
    exit 1
fi

# Run curl inside a container connected to the Docker network
RESPONSE=$(docker run --rm --network "$NETWORK_NAME" \
    curlimages/curl:latest \
    -s -X POST \
    "${API_URL}/functions/v1/ecosense-ingest?days_back=${DAYS_BACK}" \
    -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json")

# Parse JSON using grep/sed (no jq dependency)
parse_json_field() {
    echo "$1" | grep -o "\"$2\":[^,}]*" | sed 's/.*://' | tr -d ' "' 
}

# Pretty print JSON using Python (available in most systems) or fallback to raw
pretty_print_json() {
    if command -v python3 &>/dev/null; then
        echo "$1" | python3 -m json.tool 2>/dev/null || echo "$1"
    elif command -v python &>/dev/null; then
        echo "$1" | python -m json.tool 2>/dev/null || echo "$1"
    else
        echo "$1"
    fi
}

# Check if response contains success field (valid JSON response)
if echo "$RESPONSE" | grep -q '"success"'; then
    pretty_print_json "$RESPONSE"
    
    # Check for success
    SUCCESS=$(parse_json_field "$RESPONSE" "success")
    if [ "$SUCCESS" = "true" ]; then
        COUNT=$(parse_json_field "$RESPONSE" "count")
        SENSORS=$(parse_json_field "$RESPONSE" "sensors")
        echo ""
        echo "========================================"
        echo "Sync completed successfully!"
        echo "Sensors: $SENSORS"
        echo "Readings: $COUNT"
        echo "========================================"
    else
        ERROR=$(parse_json_field "$RESPONSE" "error")
        [ -z "$ERROR" ] && ERROR=$(parse_json_field "$RESPONSE" "message")
        echo ""
        echo "Error: ${ERROR:-Unknown error}"
        exit 1
    fi
else
    echo "Error: Invalid response from API"
    echo "$RESPONSE"
    exit 1
fi
