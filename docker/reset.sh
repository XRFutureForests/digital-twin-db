#!/bin/bash
set -e

echo "⚠️  WARNING: This will remove all containers, data, and volumes."
echo "    All database data will be permanently deleted!"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo "Stopping all services..."
docker compose down -v --remove-orphans

echo "Removing database data..."
rm -rf volumes/db/data

echo "Reset complete. Start fresh with: docker compose up -d"