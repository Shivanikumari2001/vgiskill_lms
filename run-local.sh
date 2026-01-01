#!/bin/bash

# ============================================
# VariPhi LMS - Local Development Setup
# ============================================
# This script sets up and runs the LMS application locally using Docker Compose
# Usage: ./run-local.sh

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SITE_NAME=${SITE_NAME:-localhost}
SITE_URL=${SITE_URL:-http://localhost:8000}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-vgiskill@2026#}

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}🚀 VariPhi LMS - Local Development${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# Function to verify Docker is fully operational
verify_docker_ready() {
    # Test multiple Docker operations to ensure it's fully ready
    if docker info > /dev/null 2>&1 && \
       docker ps > /dev/null 2>&1 && \
       docker version > /dev/null 2>&1; then
        # Try a simple image operation to ensure daemon is fully ready
        docker images > /dev/null 2>&1
        return $?
    fi
    return 1
}

# Function to ensure Docker is running
ensure_docker_running() {
    echo -e "${YELLOW}Step 1: Checking Docker...${NC}"
    
    # Check if Docker is already running and fully operational
    if verify_docker_ready; then
        echo -e "${GREEN}✅ Docker is running and ready${NC}"
        echo ""
        return 0
    fi
    
    # Docker is not running, try to start it
    echo -e "${YELLOW}⚠️  Docker Desktop is not running. Attempting to start it...${NC}"
    
    # Try to start Docker Desktop (macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open -a Docker 2>/dev/null || {
            echo -e "${RED}❌ Could not start Docker Desktop automatically.${NC}"
            echo ""
            echo "Please manually:"
            echo "1. Open Docker Desktop from Applications"
            echo "2. Wait for it to fully start (whale icon steady in menu bar)"
            echo "3. Run this script again: ./run-local.sh"
            exit 1
        }
    else
        # For Linux, try to start Docker service
        sudo systemctl start docker 2>/dev/null || {
            echo -e "${RED}❌ Could not start Docker service.${NC}"
            echo "Please start Docker manually and run this script again."
            exit 1
        }
    fi
    
    # Wait for Docker to be ready (with timeout)
    echo -e "${YELLOW}⏳ Waiting for Docker to start (this may take 30-60 seconds)...${NC}"
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if verify_docker_ready; then
            # Additional wait to ensure Docker daemon is fully initialized
            echo ""
            echo -e "${YELLOW}⏳ Verifying Docker daemon is fully ready...${NC}"
            sleep 5
            
            # Final verification
            if verify_docker_ready; then
                echo -e "${GREEN}✅ Docker is now running and fully operational!${NC}"
                echo ""
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        if [ $((attempt % 5)) -eq 0 ]; then
            echo -n " [${attempt}/${max_attempts}]"
        else
            echo -n "."
        fi
        sleep 2
    done
    
    echo ""
    echo -e "${RED}❌ Docker failed to start within timeout period (${max_attempts} attempts).${NC}"
    echo ""
    echo "Please:"
    echo "1. Check Docker Desktop is installed"
    echo "2. Manually open Docker Desktop"
    echo "3. Wait for it to fully start (whale icon steady in menu bar)"
    echo "4. Verify Docker is working: docker ps"
    echo "5. Run this script again: ./run-local.sh"
    exit 1
}

# Step 1: Ensure Docker is running
ensure_docker_running

# Step 2: Free up ports
echo -e "${YELLOW}Step 2: Freeing up ports (8000, 9000, 3306, 6379)...${NC}"
lsof -ti :8000 | xargs kill -9 2>/dev/null || true
lsof -ti :9000 | xargs kill -9 2>/dev/null || true
lsof -ti :3306 | xargs kill -9 2>/dev/null || true
lsof -ti :6379 | xargs kill -9 2>/dev/null || true
pkill -f "bench start" 2>/dev/null || true
sleep 2
echo -e "${GREEN}✅ Ports freed${NC}"
echo ""

# Step 3: Stop existing containers
echo -e "${YELLOW}Step 3: Stopping existing containers...${NC}"
docker-compose down 2>/dev/null || true
echo -e "${GREEN}✅ Containers stopped${NC}"
echo ""

# Step 4: Export environment variables
echo -e "${YELLOW}Step 4: Setting environment variables...${NC}"
export DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
export SITE_NAME=${SITE_NAME}
export SITE_URL=${SITE_URL}
export ADMIN_PASSWORD=${ADMIN_PASSWORD}
echo -e "   SITE_NAME: ${SITE_NAME}"
echo -e "   SITE_URL: ${SITE_URL}"
echo -e "   ADMIN_PASSWORD: ${ADMIN_PASSWORD}"
echo -e "${GREEN}✅ Environment variables set${NC}"
echo ""

# Step 5: Verify Docker is still ready before building
echo -e "${YELLOW}Step 5: Verifying Docker is ready...${NC}"
if ! verify_docker_ready; then
    echo -e "${RED}❌ Docker became unavailable. Attempting to reconnect...${NC}"
    ensure_docker_running
fi
echo -e "${GREEN}✅ Docker is ready${NC}"
echo ""

# Step 6: Build and start containers
echo -e "${YELLOW}Step 6: Building and starting containers...${NC}"
echo -e "${BLUE}   This may take 5-10 minutes on first run...${NC}"
echo ""

# Retry docker-compose with exponential backoff if it fails
max_retries=3
retry_count=0
while [ $retry_count -lt $max_retries ]; do
    if docker-compose up -d --build 2>&1; then
        break
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
        echo ""
        echo -e "${YELLOW}⚠️  Docker-compose failed. Retrying in 5 seconds... (${retry_count}/${max_retries})${NC}"
        # Verify Docker is still ready
        if ! verify_docker_ready; then
            echo -e "${YELLOW}Reconnecting to Docker...${NC}"
            ensure_docker_running
        fi
        sleep 5
    else
        echo ""
        echo -e "${RED}❌ Failed to start containers after ${max_retries} attempts.${NC}"
        echo ""
        echo "Please check:"
        echo "1. Docker Desktop is running: docker ps"
        echo "2. Docker has enough resources allocated"
        echo "3. Try manually: docker-compose up -d --build"
        exit 1
    fi
done

echo ""
echo -e "${GREEN}✅ Containers started!${NC}"
echo ""

# Step 7: Wait for services to initialize
echo -e "${YELLOW}Step 7: Waiting for services to initialize (30 seconds)...${NC}"
sleep 30
echo -e "${GREEN}✅ Services initialized${NC}"
echo ""

# Step 7: Show status
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}📊 Container Status${NC}"
echo -e "${BLUE}===========================================${NC}"
docker-compose ps
echo ""

# Step 8: Show logs
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}📋 Recent Logs${NC}"
echo -e "${BLUE}===========================================${NC}"
docker-compose logs --tail=20 frappe-lms
echo ""

# Step 9: Health check
echo -e "${YELLOW}Step 8: Checking application health...${NC}"
sleep 10
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ | grep -q "200\|302\|404"; then
    echo -e "${GREEN}✅ Application is responding${NC}"
else
    echo -e "${YELLOW}⚠️  Application is still starting...${NC}"
fi
echo ""

# Step 10: Final information
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}✅ Local Development Setup Complete!${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""
echo -e "${GREEN}🌐 Access your application:${NC}"
echo -e "   Main Site: ${SITE_URL}"
echo -e "   LMS App: ${SITE_URL}/lms"
echo ""
echo -e "${GREEN}👤 Default Credentials:${NC}"
echo -e "   Username: Administrator"
echo -e "   Password: ${ADMIN_PASSWORD}"
echo ""
echo -e "${YELLOW}📋 Useful Commands:${NC}"
echo -e "   View logs:        ${BLUE}docker-compose logs -f frappe-lms${NC}"
echo -e "   Stop containers:  ${BLUE}docker-compose down${NC}"
echo -e "   Restart:          ${BLUE}docker-compose restart frappe-lms${NC}"
echo -e "   Check status:     ${BLUE}docker-compose ps${NC}"
echo -e "   Shell access:     ${BLUE}docker exec -it frappe-lms-app bash${NC}"
echo ""
echo -e "${YELLOW}🔧 Database Access:${NC}"
echo -e "   Host: localhost"
echo -e "   Port: 3306"
echo -e "   User: root"
echo -e "   Password: ${DB_ROOT_PASSWORD}"
echo ""
echo -e "${YELLOW}📦 Redis Access:${NC}"
echo -e "   Host: localhost"
echo -e "   Port: 6379"
echo ""

