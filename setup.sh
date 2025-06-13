#!/bin/bash

# XR Future Forests Lab - Quick Setup Script
# This script builds and starts the Docker Compose services

set -e

echo "🌲 XR Future Forests Lab - Setup Starting..."

# Check if Docker and Docker Compose are installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is available (either as plugin or standalone)
if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not available. Please install Docker Compose."
    exit 1
fi

# Determine which compose command to use
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

# Create environment file if it doesn't exist
if [ ! -f .env ]; then
    echo "📄 Creating environment file from template..."
    cp .env.example .env
fi

# Create data directory if it doesn't exist
if [ ! -d data ]; then
    echo "📁 Creating data directory..."
    mkdir -p data
fi

echo "🔨 Building Docker images..."
$COMPOSE_CMD build

echo "🚀 Starting services..."
$COMPOSE_CMD up -d

echo "⏳ Waiting for services to be ready..."
sleep 10

# Check if services are healthy
echo "🔍 Checking service health..."

# Check PostgreSQL
if docker exec xr_forests_db pg_isready -U forests_user -d xr_forests_lab; then
    echo "✅ PostgreSQL is ready"
else
    echo "❌ PostgreSQL is not ready"
    docker logs xr_forests_db
    exit 1
fi

# Check Redis
if docker exec xr_forests_redis redis-cli ping | grep -q PONG; then
    echo "✅ Redis is ready"
else
    echo "❌ Redis is not ready"
    docker logs xr_forests_redis
    exit 1
fi

# Check API
if curl -f http://localhost:8000/health > /dev/null 2>&1; then
    echo "✅ API is ready"
else
    echo "❌ API is not ready"
    docker logs xr_forests_api
    exit 1
fi

echo ""
echo "🎉 XR Future Forests Lab is ready!"
echo ""
echo "📚 Available services:"
echo "   - API Documentation: http://localhost:8000/docs"
echo "   - API Health Check: http://localhost:8000/health"
echo "   - PostgreSQL: localhost:5432 (user: forests_user, db: xr_forests_lab)"
echo "   - Redis: localhost:6379"
echo ""
echo "🔧 Useful commands:"
echo "   - View logs: $COMPOSE_CMD logs -f"
echo "   - Stop services: $COMPOSE_CMD down"
echo "   - Connect to database: docker exec -it xr_forests_db psql -U forests_user -d xr_forests_lab"
echo "   - Connect to Redis: docker exec -it xr_forests_redis redis-cli"
echo ""
echo "📖 Check README.md for API usage examples and next steps."
