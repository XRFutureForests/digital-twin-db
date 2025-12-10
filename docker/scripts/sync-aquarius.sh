#!/bin/bash
# Sync sensor data from Aquarius API
# Requires: University VPN connection for Aquarius access

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$DOCKER_DIR/.env" ]; then
    source "$DOCKER_DIR/.env"
fi

# Default values
DAYS_BACK=${1:-30}
API_URL="${SUPABASE_PUBLIC_URL:-http://localhost:8000}"

echo "========================================"
echo "Aquarius Data Sync"
echo "========================================"
echo "API URL: $API_URL"
echo "Days back: $DAYS_BACK"
echo ""

# Check if services are running
if ! docker compose -f "$DOCKER_DIR/docker-compose.yml" ps --quiet kong &>/dev/null; then
    echo "Error: Kong API gateway is not running"
    echo "Start services with: docker compose up -d"
    exit 1
fi

# Check VPN connectivity to Aquarius (optional warning)
if ! curl -s --connect-timeout 5 "${AQUARIUS_HOSTNAME:-http://fuhys006.public.ads.uni-freiburg.de}/AQUARIUS/" >/dev/null 2>&1; then
    echo "Warning: Cannot reach Aquarius server"
    echo "Make sure you are connected to the university VPN"
    echo ""
fi

echo "Calling ecosense-ingest function..."
echo ""

# Call the edge function
RESPONSE=$(curl -s -X POST \
    "${API_URL}/functions/v1/ecosense-ingest?days_back=${DAYS_BACK}" \
    -H "Authorization: Bearer ${SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json")

# Check if response is valid JSON
if echo "$RESPONSE" | jq . >/dev/null 2>&1; then
    echo "$RESPONSE" | jq .
    
    # Check for success
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false')
    if [ "$SUCCESS" = "true" ]; then
        COUNT=$(echo "$RESPONSE" | jq -r '.count // 0')
        SENSORS=$(echo "$RESPONSE" | jq -r '.sensors // 0')
        echo ""
        echo "========================================"
        echo "Sync completed successfully!"
        echo "Sensors: $SENSORS"
        echo "Readings: $COUNT"
        echo "========================================"
    else
        ERROR=$(echo "$RESPONSE" | jq -r '.error // .message // "Unknown error"')
        echo ""
        echo "Error: $ERROR"
        exit 1
    fi
else
    echo "Error: Invalid response from API"
    echo "$RESPONSE"
    exit 1
fi
