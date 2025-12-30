#!/bin/bash

# Complete Frappe Framework & LMS Setup Script
# This script completes the setup by fixing database connections and installing LMS

set -e

echo "=========================================="
echo "Frappe Framework & LMS - Complete Setup"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -d "frappe-bench" ]; then
    echo "❌ Error: frappe-bench directory not found!"
    echo "   Please run this script from the project root directory."
    exit 1
fi

cd frappe-bench

# Activate Node.js v24
source ~/.nvm/nvm.sh 2>/dev/null || true
nvm use 24 2>/dev/null || echo "⚠️  Warning: Could not switch to Node v24"

# Check if MariaDB root password is needed
echo "📋 Checking MariaDB connection..."

# Try to get MariaDB root password
if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo ""
    echo "⚠️  MariaDB root password is required to complete the setup."
    echo ""
    read -sp "Enter MariaDB root password (or press Enter to skip): " MARIADB_ROOT_PASSWORD
    echo ""
fi

if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "⚠️  Skipping database setup. You'll need to manually configure the database."
    echo ""
    echo "To complete setup manually:"
    echo "  1. Drop existing site: bench drop-site localhost --force --db-root-password YOUR_PASSWORD"
    echo "  2. Create new site: bench new-site localhost --admin-password admin --mariadb-user-host-login-scope='%' --set-default --db-root-password YOUR_PASSWORD"
    echo "  3. Install LMS: bench --site localhost install-app lms"
    exit 0
fi

# Export password for bench commands
export MARIADB_ROOT_PASSWORD

echo ""
echo "✅ Step 1: Dropping existing site (if any)..."
bench drop-site localhost --force --db-root-password "$MARIADB_ROOT_PASSWORD" 2>/dev/null || echo "   Site doesn't exist or already dropped"

echo ""
echo "✅ Step 2: Creating new site..."
bench new-site localhost \
    --admin-password admin \
    --mariadb-user-host-login-scope='%' \
    --set-default \
    --db-root-password "$MARIADB_ROOT_PASSWORD"

echo ""
echo "✅ Step 3: Installing Frappe LMS app..."
bench --site localhost install-app lms

echo ""
echo "✅ Step 4: Building assets..."
bench build --app lms

echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "To start the development server, run:"
echo "  cd frappe-bench"
echo "  source ~/.nvm/nvm.sh && nvm use 24"
echo "  bench start"
echo ""
echo "Then access the application at:"
echo "  http://localhost:8000"
echo ""
echo "Login credentials:"
echo "  Username: Administrator"
echo "  Password: admin"
echo ""

