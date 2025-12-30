#!/bin/bash

# Quick build and test script for Docker

set -e

echo "=========================================="
echo "🐳 Building Frappe LMS Docker Image"
echo "=========================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Build the image
echo "📦 Building Docker image..."
docker build -t frappe-lms:latest .

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Docker image built successfully!"
    echo ""
    echo "📋 Image details:"
    docker images frappe-lms:latest
    echo ""
    echo "🚀 To run with docker-compose:"
    echo "   docker-compose up -d"
    echo ""
    echo "🚀 Or run standalone:"
    echo "   docker run -d --name frappe-lms -p 8000:8000 frappe-lms:latest"
    echo ""
else
    echo ""
    echo "❌ Build failed. Check the errors above."
    exit 1
fi

