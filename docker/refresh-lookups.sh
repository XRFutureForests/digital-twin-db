#!/bin/bash
# Refresh lookup tables from CSV files without full database rebuild
#
# Usage:
#   ./refresh-lookups.sh              # Refresh all lookup tables
#   ./refresh-lookups.sh species      # Refresh specific table
#   ./refresh-lookups.sh --list       # List available tables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Container name (don't source .env as it may have incompatible syntax)
CONTAINER_NAME="dftdb-db"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

show_help() {
    echo "Refresh Lookup Tables"
    echo ""
    echo "Usage:"
    echo "  $0              Refresh all lookup tables"
    echo "  $0 <table>      Refresh specific table"
    echo "  $0 --list       List available tables"
    echo "  $0 --help       Show this help"
    echo ""
    echo "Available tables:"
    echo "  species, locations, sensor_types, tree_status,"
    echo "  soil_types, climate_zones"
    echo ""
    echo "Examples:"
    echo "  $0 species      Refresh species from species.csv"
    echo "  $0 locations    Refresh locations from locations.csv"
}

list_tables() {
    echo "Available lookup tables:"
    echo ""
    echo "  Table Name       CSV File                    Description"
    echo "  ─────────────    ────────────────────────    ───────────────────────────"
    echo "  species          species.csv                 Tree species definitions"
    echo "  locations        locations.csv               Research plot locations"
    echo "  sensor_types     sensor_types.csv            Sensor type definitions"
    echo "  tree_status      tree_status.csv             Tree health status values"
    echo "  soil_types       soil_types.csv              USDA soil classification"
    echo "  climate_zones    climate_zones.csv           Köppen climate zones"
    echo ""
    echo "CSV files location: data/lookups/"
}

check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}Error: Database container '$CONTAINER_NAME' is not running${NC}"
        echo "Start the database with: docker compose up -d"
        exit 1
    fi
}

refresh_all() {
    echo -e "${YELLOW}Refreshing all lookup tables...${NC}"
    echo ""
    
    docker exec -i "$CONTAINER_NAME" psql -U postgres -c "SELECT * FROM shared.refresh_all_lookups();" 2>&1 | \
        grep -v "^$" | \
        sed 's/OK/\x1b[32mOK\x1b[0m/g' | \
        sed 's/ERROR/\x1b[31mERROR\x1b[0m/g'
    
    echo ""
    echo -e "${GREEN}Done!${NC} Edit CSV files in data/lookups/ and run again to update."
}

refresh_table() {
    local table="$1"
    echo -e "${YELLOW}Refreshing $table...${NC}"
    echo ""
    
    docker exec -i "$CONTAINER_NAME" psql -U postgres -c "SELECT * FROM shared.refresh_lookup('$table');" 2>&1 | \
        grep -v "^$" | \
        sed 's/OK/\x1b[32mOK\x1b[0m/g' | \
        sed 's/ERROR/\x1b[31mERROR\x1b[0m/g'
    
    echo ""
}

# Main
case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --list|-l)
        list_tables
        ;;
    "")
        check_container
        refresh_all
        ;;
    *)
        check_container
        refresh_table "$1"
        ;;
esac
