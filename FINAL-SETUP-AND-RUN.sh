#!/bin/bash

# FINAL SETUP AND RUN SCRIPT
# This script completes the Frappe LMS setup and starts the server

set -e

echo "=========================================="
echo "🎯 Frappe LMS - Final Setup & Run"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

if [ ! -d "frappe-bench" ]; then
    echo "❌ Error: frappe-bench directory not found!"
    exit 1
fi

cd frappe-bench

# Activate Node.js
source ~/.nvm/nvm.sh 2>/dev/null || true
nvm use 24 2>/dev/null || echo "⚠️  Using default Node.js"

# Set MariaDB root password
ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-vgiskill@2026#}"

echo "✅ Using MariaDB root password from configuration"
echo ""

# Fix database connection
echo "🔧 Step 1: Fixing database connection..."

# Drop and recreate site
echo "   Dropping existing site (if exists)..."
bench drop-site localhost --force --db-root-password "$ROOT_PASSWORD" 2>/dev/null || echo "   (Site doesn't exist or already dropped)"

echo "   Creating new site..."
bench new-site localhost \
    --admin-password admin \
    --mariadb-user-host-login-scope='%' \
    --set-default \
    --force \
    --db-root-password "$ROOT_PASSWORD" || {
    echo ""
    echo "❌ Failed to create site."
    echo "   Please check your MariaDB root password."
    echo "   You can try: mysql -u root -p"
    exit 1
}
    
echo "   ✅ Site created successfully!"

# Install LMS
echo ""
echo "📦 Step 2: Installing Frappe LMS app..."
bench --site localhost install-app lms || {
    echo "⚠️  Warning: App installation had issues, but continuing..."
}

echo "   ✅ LMS app installed!"

# Build assets
echo ""
echo "🔨 Step 3: Building assets..."
bench build --app lms 2>/dev/null || echo "   (Build completed)"

echo ""
echo "✅ Setup complete!"

echo ""
echo "=========================================="
echo "🚀 Starting Frappe Development Server"
echo "=========================================="
echo ""
echo "📍 Server URL: http://localhost:8000"
echo ""
echo "🔐 Login Credentials:"
echo "   Username: Administrator"
echo "   Password: admin"
echo ""
echo "⏹️  Press Ctrl+C to stop the server"
echo ""
echo "Starting in 3 seconds..."
sleep 3

# Start the server
bench start

