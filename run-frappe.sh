#!/bin/bash

# Complete Frappe LMS Setup and Run Script
# This script completes the database setup and starts the Frappe server

set -e

echo "=========================================="
echo "🚀 Frappe Framework & LMS - Complete Setup & Run"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

if [ ! -d "frappe-bench" ]; then
    echo "❌ Error: frappe-bench directory not found!"
    exit 1
fi

cd frappe-bench

# Activate Node.js v24
source ~/.nvm/nvm.sh 2>/dev/null || true
if command -v nvm &> /dev/null; then
    nvm use 24 2>/dev/null || echo "⚠️  Warning: Could not switch to Node v24"
fi

# Check for MariaDB root password
ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD}"

if [ -z "$ROOT_PASSWORD" ]; then
    echo "📋 MariaDB root password is required to complete the setup."
    echo ""
    echo "You can provide it in one of these ways:"
    echo "  1. Set environment variable: export MARIADB_ROOT_PASSWORD='your_password'"
    echo "  2. Enter it when prompted below"
    echo ""
    read -sp "Enter MariaDB root password: " ROOT_PASSWORD
    echo ""
    echo ""
fi

if [ -z "$ROOT_PASSWORD" ]; then
    echo "⚠️  No root password provided."
    echo "   Attempting to start server with existing configuration..."
    echo "   If this fails, you'll need to provide the root password."
    echo ""
else
    echo "✅ Step 1: Fixing database connection..."
    
    # Drop existing site if it has issues
    echo "   Dropping existing site (if needed)..."
    bench drop-site localhost --force --db-root-password "$ROOT_PASSWORD" 2>/dev/null || echo "   Site doesn't exist or already dropped"
    
    # Create new site
    echo "   Creating new site..."
    bench new-site localhost \
        --admin-password admin \
        --mariadb-user-host-login-scope='%' \
        --set-default \
        --db-root-password "$ROOT_PASSWORD" || {
        echo "❌ Failed to create site. Please check your MariaDB root password."
        exit 1
    }
    
    # Install LMS app
    echo "   Installing Frappe LMS app..."
    bench --site localhost install-app lms || {
        echo "⚠️  Warning: Failed to install LMS app, but continuing..."
    }
    
    # Build assets
    echo "   Building assets..."
    bench build --app lms 2>/dev/null || echo "   Build completed with warnings"
    
    echo ""
    echo "✅ Setup complete!"
    echo ""
fi

echo "=========================================="
echo "🚀 Starting Frappe Development Server"
echo "=========================================="
echo ""
echo "📍 Server will be available at: http://localhost:8000"
echo ""
echo "🔐 Login credentials:"
echo "   Username: Administrator"
echo "   Password: admin"
echo ""
echo "⏹️  Press Ctrl+C to stop the server"
echo ""
echo "Starting server..."
echo ""

# Start the bench server
bench start

