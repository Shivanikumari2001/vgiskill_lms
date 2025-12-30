#!/bin/bash

# Diagnose Docker container issues

set -e

echo "=========================================="
echo "🔍 Diagnosing Frappe LMS Container"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

# Check Docker
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running!"
    echo "   Please start Docker Desktop first."
    exit 1
fi

echo "✅ Docker is running"
echo ""

# Check containers
echo "📊 Container Status:"
docker-compose ps
echo ""

# Check frappe-lms container specifically
if docker ps -a | grep -q frappe-lms-app; then
    echo "📋 Frappe LMS Container Details:"
    docker inspect frappe-lms-app --format='{{.State.Status}} - {{.State.ExitCode}}' 2>/dev/null || echo "Container not found"
    echo ""
    
    echo "📜 Last 50 lines of logs:"
    docker-compose logs --tail=50 frappe-lms
    echo ""
    
    if [ "$(docker inspect frappe-lms-app --format='{{.State.Status}}' 2>/dev/null)" != "running" ]; then
        echo "⚠️  Container is not running!"
        echo ""
        echo "🔍 Exit code: $(docker inspect frappe-lms-app --format='{{.State.ExitCode}}' 2>/dev/null)"
        echo ""
        echo "📋 Full error logs:"
        docker-compose logs frappe-lms | tail -100
    fi
else
    echo "❌ frappe-lms-app container does not exist"
    echo "   Run: docker-compose up -d"
fi

echo ""
echo "🔍 Checking dependencies:"
echo ""

# Check MariaDB
if docker ps | grep -q frappe-lms-mariadb; then
    echo "✅ MariaDB container is running"
    docker-compose exec -T mariadb mysqladmin ping -h localhost -u root -pvgiskill@2026# --silent 2>/dev/null && \
        echo "   ✅ MariaDB is responding" || \
        echo "   ⚠️  MariaDB is not responding"
else
    echo "❌ MariaDB container is not running"
fi

# Check Redis
if docker ps | grep -q frappe-lms-redis; then
    echo "✅ Redis container is running"
    docker-compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG && \
        echo "   ✅ Redis is responding" || \
        echo "   ⚠️  Redis is not responding"
else
    echo "❌ Redis container is not running"
fi

echo ""
echo "🌐 Checking port availability:"
for port in 8000 9000 3306 6379; do
    if lsof -i :$port > /dev/null 2>&1; then
        echo "   ⚠️  Port $port is in use"
        lsof -i :$port | head -2
    else
        echo "   ✅ Port $port is free"
    fi
done

echo ""
echo "=========================================="
echo "💡 To fix issues, run:"
echo "   ./docker-fix.sh"
echo "=========================================="

