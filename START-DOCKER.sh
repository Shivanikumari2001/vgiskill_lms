#!/bin/bash

# Start Docker and run Frappe LMS

set -e

echo "=========================================="
echo "🐳 Starting Frappe LMS with Docker"
echo "=========================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running!"
    echo ""
    echo "Please start Docker Desktop and try again."
    echo "On macOS:"
    echo "  1. Open Docker Desktop application"
    echo "  2. Wait for it to start (whale icon in menu bar)"
    echo "  3. Run this script again"
    echo ""
    exit 1
fi

echo "✅ Docker is running"
echo ""

# Kill any processes using required ports
echo "🔧 Freeing up ports..."
lsof -ti :8000 | xargs kill -9 2>/dev/null || echo "  Port 8000 is free"
lsof -ti :9000 | xargs kill -9 2>/dev/null || echo "  Port 9000 is free"
lsof -ti :3306 | xargs kill -9 2>/dev/null || echo "  Port 3306 is free"
lsof -ti :6379 | xargs kill -9 2>/dev/null || echo "  Port 6379 is free"
pkill -f "bench start" 2>/dev/null || echo "  Bench processes stopped"
sleep 2

echo ""
echo "📦 Starting Docker containers..."
docker-compose down 2>/dev/null || true
docker-compose up -d --build

echo ""
echo "⏳ Waiting for services to start..."
sleep 15

echo ""
echo "📊 Container status:"
docker-compose ps

echo ""
echo "📋 Viewing logs (press Ctrl+C to exit)..."
echo ""
docker-compose logs -f frappe-lms
