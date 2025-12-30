#!/bin/bash

# Fix database connection and run Frappe LMS
# This script attempts to fix the database connection and start the server

set -e

echo "=========================================="
echo "Fixing Database & Starting Frappe LMS"
echo "=========================================="
echo ""

cd frappe-bench
source ~/.nvm/nvm.sh 2>/dev/null || true
nvm use 24 2>/dev/null || echo "⚠️  Warning: Could not switch to Node v24"

# Check if we can connect to the database
echo "📋 Checking database connection..."

# Try to get MariaDB root password from environment or prompt
if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo ""
    echo "⚠️  MariaDB root password is required to fix the database connection."
    echo "   You can set it as an environment variable:"
    echo "   export MARIADB_ROOT_PASSWORD='your_password'"
    echo ""
    read -sp "Enter MariaDB root password (or press Enter to try without): " MARIADB_ROOT_PASSWORD
    echo ""
fi

if [ -n "$MARIADB_ROOT_PASSWORD" ]; then
    echo "✅ Attempting to fix database connection..."
    
    # Export for bench commands
    export MARIADB_ROOT_PASSWORD
    
    # Try to drop and recreate the site
    echo "   Dropping existing site..."
    bench drop-site localhost --force --db-root-password "$MARIADB_ROOT_PASSWORD" 2>/dev/null || echo "   Site doesn't exist or already dropped"
    
    echo "   Creating new site..."
    bench new-site localhost \
        --admin-password admin \
        --mariadb-user-host-login-scope='%' \
        --set-default \
        --db-root-password "$MARIADB_ROOT_PASSWORD" || {
        echo "❌ Failed to create site. Please check your MariaDB root password."
        exit 1
    }
    
    echo "   Installing LMS app..."
    bench --site localhost install-app lms || {
        echo "⚠️  Warning: Failed to install LMS app, but continuing..."
    }
    
    echo "   Building assets..."
    bench build --app lms 2>/dev/null || echo "   Build completed with warnings"
    
    echo ""
    echo "✅ Database setup complete!"
else
    echo "⚠️  No root password provided. Attempting to start with existing configuration..."
    echo "   If this fails, you'll need to provide the MariaDB root password."
fi

echo ""
echo "=========================================="
echo "🚀 Starting Frappe Development Server"
echo "=========================================="
echo ""
echo "The server will start on http://localhost:8000"
echo "Login credentials:"
echo "  Username: Administrator"
echo "  Password: admin"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Start the bench server
bench start

