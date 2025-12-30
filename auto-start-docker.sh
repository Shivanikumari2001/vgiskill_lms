#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Auto-Starting Docker Setup...${NC}"
echo ""

# Check if Docker is running
echo -e "${YELLOW}Checking Docker status...${NC}"
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker Desktop is not running!${NC}"
    echo ""
    echo "Please:"
    echo "1. Open Docker Desktop application"
    echo "2. Wait for it to fully start (whale icon in menu bar should be steady)"
    echo "3. Run this script again: ./auto-start-docker.sh"
    echo ""
    echo "Or start Docker Desktop and run: docker-compose up -d --build"
    exit 1
fi

echo -e "${GREEN}✅ Docker is running${NC}"
echo ""

# Free up ports
echo -e "${YELLOW}Freeing up ports...${NC}"
lsof -ti :8000 | xargs kill -9 2>/dev/null || true
lsof -ti :9000 | xargs kill -9 2>/dev/null || true
pkill -f "bench start" 2>/dev/null || true
sleep 2
echo -e "${GREEN}✅ Ports freed${NC}"
echo ""

# Stop existing containers
echo -e "${YELLOW}Stopping existing containers...${NC}"
docker-compose down 2>/dev/null || true
echo -e "${GREEN}✅ Containers stopped${NC}"
echo ""

# Build and start
echo -e "${YELLOW}Building and starting containers...${NC}"
echo "This may take 5-10 minutes on first run..."
echo ""
docker-compose up -d --build

echo ""
echo -e "${GREEN}✅ Containers started!${NC}"
echo ""

# Wait a bit for services to initialize
echo -e "${YELLOW}Waiting for services to initialize...${NC}"
sleep 15

# Show status
echo ""
echo -e "${GREEN}📊 Container Status:${NC}"
docker-compose ps

echo ""
echo -e "${YELLOW}📋 Recent logs from frappe-lms container:${NC}"
docker-compose logs --tail=30 frappe-lms

echo ""
echo -e "${GREEN}🌐 Server should be accessible at: http://localhost:8000${NC}"
echo ""
echo -e "${YELLOW}To view logs in real-time:${NC}"
echo "  docker-compose logs -f frappe-lms"
echo ""
echo -e "${YELLOW}To check status:${NC}"
echo "  docker-compose ps"
echo ""

