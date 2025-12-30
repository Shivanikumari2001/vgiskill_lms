#!/bin/bash

# Fix and restart Frappe LMS Docker container

set -e

echo "=========================================="
echo "🔧 Fixing Frappe LMS Docker Container"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running!"
    echo ""
    echo "Please start Docker Desktop first:"
    echo "  1. Open Docker Desktop application"
    echo "  2. Wait for it to fully start"
    echo "  3. Run this script again"
    echo ""
    exit 1
fi

echo "✅ Docker is running"
echo ""

# Stop and remove existing containers
echo "🛑 Stopping existing containers..."
docker-compose down 2>/dev/null || true

# Kill any processes using required ports
echo "🔧 Freeing up ports..."
lsof -ti :8000 | xargs kill -9 2>/dev/null || echo "  Port 8000 is free"
lsof -ti :9000 | xargs kill -9 2>/dev/null || echo "  Port 9000 is free"
sleep 2

# Remove old containers and volumes if needed
echo "🧹 Cleaning up..."
docker-compose rm -f 2>/dev/null || true

# Rebuild and start
echo ""
echo "🔨 Rebuilding and starting containers..."
docker-compose up -d --build

echo ""
echo "⏳ Waiting for services to initialize..."
sleep 20

echo ""
echo "📊 Container status:"
docker-compose ps

echo ""
echo "📋 Recent logs from frappe-lms container:"
docker-compose logs --tail=50 frappe-lms

echo ""
echo "=========================================="
echo "✅ Containers started!"
echo "=========================================="
echo ""
echo "🌐 Access at: http://localhost:8000"
echo "👤 Login: Administrator / admin"
echo ""
echo "📋 To view live logs:"
echo "   docker-compose logs -f frappe-lms"
echo ""
echo "🔍 To check container status:"
echo "   docker-compose ps"
echo ""

