#!/bin/bash
# Don't exit on error - we want to handle errors gracefully
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Frappe LMS Docker Container...${NC}"

# Set environment variables with defaults
export DB_HOST=${DB_HOST:-mariadb}
export DB_PORT=${DB_PORT:-3306}
export DB_ROOT_USER=${DB_ROOT_USER:-root}
export DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-vgiskill@2026#}
export SITE_NAME=${SITE_NAME:-localhost}
export ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
export REDIS_CACHE=${REDIS_CACHE:-redis://redis:6379}
export REDIS_QUEUE=${REDIS_QUEUE:-redis://redis:6379}
export REDIS_SOCKETIO=${REDIS_SOCKETIO:-redis://redis:6379}

cd /home/frappe/frappe-bench

# Wait for MariaDB to be ready
echo -e "${YELLOW}Waiting for MariaDB to be ready...${NC}"
MAX_RETRIES=30
RETRY_COUNT=0
until mysqladmin ping -h ${DB_HOST} -P ${DB_PORT} -u ${DB_ROOT_USER} -p${DB_ROOT_PASSWORD} --skip-ssl --silent 2>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo -e "${RED}MariaDB connection timeout!${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Waiting for MariaDB... (${RETRY_COUNT}/${MAX_RETRIES})${NC}"
    sleep 2
done
echo -e "${GREEN}MariaDB is ready!${NC}"

# Wait for Redis to be ready
echo -e "${YELLOW}Waiting for Redis to be ready...${NC}"
MAX_RETRIES=30
RETRY_COUNT=0
until redis-cli -u ${REDIS_CACHE} ping > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo -e "${RED}Redis connection timeout!${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Waiting for Redis... (${RETRY_COUNT}/${MAX_RETRIES})${NC}"
    sleep 2
done
echo -e "${GREEN}Redis is ready!${NC}"

# Configure bench for containerized environment
echo -e "${YELLOW}Configuring bench...${NC}"
cd /home/frappe/frappe-bench
bench set-mariadb-host ${DB_HOST} 2>/dev/null || echo "  (mariadb-host already set)"
bench set-redis-cache-host ${REDIS_CACHE} 2>/dev/null || echo "  (redis-cache already set)"
bench set-redis-queue-host ${REDIS_QUEUE} 2>/dev/null || echo "  (redis-queue already set)"
bench set-redis-socketio-host ${REDIS_SOCKETIO} 2>/dev/null || echo "  (redis-socketio already set)"

# Disable SSL in common site config BEFORE any site operations
echo -e "${YELLOW}Disabling SSL in common site config...${NC}"
python3 << 'PYEOF'
import json
import os

common_config_path = 'sites/common_site_config.json'
if os.path.exists(common_config_path):
    with open(common_config_path, 'r') as f:
        config = json.load(f)
    config['db_ssl_ca'] = ''
    config['db_ssl_cert'] = ''
    config['db_ssl_key'] = ''
    with open(common_config_path, 'w') as f:
        json.dump(config, f, indent=1)
PYEOF

# Function to disable SSL in site config
disable_ssl_in_site_config() {
    local config_path=$1
    if [ -f "$config_path" ]; then
        python3 << PYEOF
import json
config_path = "$config_path"
with open(config_path, 'r') as f:
    config = json.load(f)
config['db_ssl_ca'] = ''
config['db_ssl_cert'] = ''
config['db_ssl_key'] = ''
with open(config_path, 'w') as f:
    json.dump(config, f, indent=1)
PYEOF
    fi
}

# Function to disable PWA install prompt
disable_pwa_prompt() {
    local site_name=$1
    
    echo -e "${YELLOW}Disabling PWA install prompt...${NC}"
    cd /home/frappe/frappe-bench
    
    bench --site ${site_name} console << PYEOF 2>/dev/null || true
import frappe
try:
    frappe.connect(site='${site_name}')
    frappe.db.set_single_value('LMS Settings', 'disable_pwa', 1)
    frappe.db.commit()
    print('✅ PWA install prompt disabled')
except Exception as e:
    print(f'⚠️  Could not disable PWA: {e}')
PYEOF
}

# Function to configure sidebar settings for mobile navigation
configure_sidebar_settings() {
    local site_name=$1
    
    echo -e "${YELLOW}Configuring sidebar settings for mobile navigation...${NC}"
    cd /home/frappe/frappe-bench
    
    bench --site ${site_name} console << PYEOF 2>/dev/null || true
import frappe
try:
    frappe.connect(site='${site_name}')
    settings = frappe.get_single('LMS Settings')
    
    # Enable all sidebar items by default so navigation bar shows
    sidebar_fields = [
        'courses',
        'batches', 
        'certifications',
        'jobs',
        'statistics',
        'notifications',
        'programming_exercises'
    ]
    
    changed = False
    for field in sidebar_fields:
        current_value = getattr(settings, field, None)
        if current_value != 1:
            setattr(settings, field, 1)
            changed = True
    
    if changed:
        settings.save(ignore_permissions=True)
        frappe.db.commit()
        print('✅ Sidebar settings configured - navigation bar will show')
    else:
        print('✅ Sidebar settings already configured')
except Exception as e:
    print(f'⚠️  Could not configure sidebar settings: {e}')
PYEOF
}

# Function to configure site URL properly
configure_site_url() {
    local site_name=$1
    local site_url=$2
    
    if [ -z "$site_url" ]; then
        return
    fi
    
    echo -e "${YELLOW}Configuring site URL: ${site_url}${NC}"
    cd /home/frappe/frappe-bench
    
    # Parse the URL to extract domain and protocol
    python3 << PYEOF
import json
import re
import os

site_name = "$site_name"
site_url = "$site_url"

# Ensure URL has protocol
if not site_url.startswith(('http://', 'https://')):
    site_url = 'https://' + site_url

# Determine if SSL should be used
use_ssl = site_url.startswith('https://')

# Set host_name to the full URL with protocol (Frappe will use this directly)
# This ensures URLs are generated correctly without port numbers
print(f"Setting host_name to full URL: {site_url}")
os.system(f'bench --site {site_name} set-config host_name "{site_url}" 2>&1')

# Set use_ssl based on protocol
if use_ssl:
    print("Setting use_ssl to True")
    os.system(f'bench --site {site_name} set-config use_ssl 1 2>&1')
else:
    print("Setting use_ssl to False")
    os.system(f'bench --site {site_name} set-config use_ssl 0 2>&1')

# Remove webserver_port from site config to prevent port from being added to URLs
# This is important for production sites behind reverse proxies
print("Removing webserver_port from site config")
os.system(f'bench --site {site_name} set-config webserver_port "" 2>&1')

# Clear cache to ensure new settings are picked up
print("Clearing cache")
os.system(f'bench --site {site_name} clear-cache 2>&1')

print(f"✅ Site URL configured: {site_url} (use_ssl={use_ssl}, port excluded)")
PYEOF
}

# Function to check if database is initialized
check_db_initialized() {
    local site_name=$1
    cd /home/frappe/frappe-bench
    bench --site ${site_name} mariadb -e "SHOW TABLES LIKE 'tabUser';" 2>/dev/null | grep -q tabUser
}

# Function to check if assets exist
assets_exist() {
    local app_name=$1
    local bench_path="/home/frappe/frappe-bench"
    if [ "$app_name" = "frappe" ]; then
        [ -d "${bench_path}/sites/assets/frappe" ] && [ "$(ls -A ${bench_path}/sites/assets/frappe 2>/dev/null)" ]
    elif [ "$app_name" = "lms" ]; then
        [ -d "${bench_path}/sites/assets/lms/frontend/assets" ] && [ "$(ls -A ${bench_path}/sites/assets/lms/frontend/assets 2>/dev/null)" ]
    elif [ "$app_name" = "payments" ]; then
        [ -d "${bench_path}/sites/assets/payments" ] && [ "$(ls -A ${bench_path}/sites/assets/payments 2>/dev/null)" ]
    else
        false
    fi
}

# Function to build assets only if they don't exist (to save memory)
build_assets_if_needed() {
    cd /home/frappe/frappe-bench
    
    # Build Frappe assets if missing
    if ! assets_exist "frappe"; then
        echo -e "${YELLOW}Building Frappe assets...${NC}"
        cd apps/frappe && yarn build 2>&1 || echo -e "${YELLOW}Frappe asset build had warnings${NC}"
        cd /home/frappe/frappe-bench
    else
        echo -e "${GREEN}Frappe assets already exist, skipping build${NC}"
    fi
    
    # Build LMS assets if missing
    if ! assets_exist "lms"; then
        echo -e "${YELLOW}Building LMS assets...${NC}"
        cd apps/lms && yarn build 2>&1 || echo -e "${YELLOW}LMS asset build had warnings${NC}"
        cd /home/frappe/frappe-bench
        # Copy built assets to sites/assets/ (Frappe's expected location)
        if [ -d "apps/lms/lms/public/frontend" ]; then
            echo -e "${YELLOW}Copying LMS assets to sites/assets/...${NC}"
            mkdir -p sites/assets/lms/frontend
            cp -r apps/lms/lms/public/frontend/* sites/assets/lms/frontend/ 2>/dev/null || true
            echo -e "${GREEN}LMS assets copied to sites/assets/lms/frontend/${NC}"
        fi
    else
        echo -e "${GREEN}LMS assets already exist, skipping build${NC}"
    fi
    
    # Build Payments assets if missing
    if ! assets_exist "payments"; then
        echo -e "${YELLOW}Building Payments assets...${NC}"
        cd apps/payments && (yarn build 2>&1 || echo -e "${YELLOW}Payments asset build had warnings${NC}") || echo "Payments has no build script"
        cd /home/frappe/frappe-bench
    else
        echo -e "${GREEN}Payments assets already exist, skipping build${NC}"
    fi
}

# Ensure apps.txt exists in sites directory
if [ ! -f "sites/apps.txt" ]; then
    echo -e "${YELLOW}Creating apps.txt...${NC}"
    echo -e "frappe\nlms\npayments" > sites/apps.txt
    echo -e "${GREEN}apps.txt created!${NC}"
fi

# Check if site exists and is properly initialized
SITE_CONFIG="sites/${SITE_NAME}/site_config.json"
if [ ! -f "$SITE_CONFIG" ]; then
    echo -e "${YELLOW}Creating new site: ${SITE_NAME}...${NC}"
    
    # Try to create site
    SITE_CREATED=false
    cd /home/frappe/frappe-bench
    if bench new-site ${SITE_NAME} \
        --admin-password ${ADMIN_PASSWORD} \
        --mariadb-user-host-login-scope='%' \
        --set-default \
        --db-root-password ${DB_ROOT_PASSWORD} \
        --no-mariadb-socket \
        --force > /tmp/site-creation.log 2>&1; then
        SITE_CREATED=true
        echo -e "${GREEN}Site created successfully!${NC}"
    else
        echo -e "${YELLOW}Site creation had errors, checking if site was partially created...${NC}"
        cat /tmp/site-creation.log | tail -20
        
        # Check if site config was created
        if [ -f "$SITE_CONFIG" ]; then
            echo -e "${YELLOW}Site config exists, checking database...${NC}"
            # Disable SSL immediately
            disable_ssl_in_site_config "$SITE_CONFIG"
            
            # Check if database exists but is not initialized
            if check_db_initialized ${SITE_NAME}; then
                echo -e "${GREEN}Database is initialized!${NC}"
                SITE_CREATED=true
            else
                echo -e "${YELLOW}Database exists but is not initialized. Attempting to initialize...${NC}"
                # Try to run migrations to initialize database
                if bench --site ${SITE_NAME} migrate > /tmp/migrate.log 2>&1; then
                    if check_db_initialized ${SITE_NAME}; then
                        echo -e "${GREEN}Database initialized via migrations!${NC}"
                        SITE_CREATED=true
                    fi
                fi
            fi
        fi
    fi
    
    # If site config exists, ensure SSL is disabled
    if [ -f "$SITE_CONFIG" ]; then
        disable_ssl_in_site_config "$SITE_CONFIG"
    fi
    
    # If site was created or initialized, install LMS and Payments
    if [ "$SITE_CREATED" = true ] || check_db_initialized ${SITE_NAME}; then
        cd /home/frappe/frappe-bench
        
        # Set site URL if provided
        if [ ! -z "${SITE_URL}" ]; then
            configure_site_url ${SITE_NAME} "${SITE_URL}"
        fi
        
        echo -e "${YELLOW}Installing LMS app...${NC}"
        bench --site ${SITE_NAME} install-app lms 2>&1 || echo -e "${YELLOW}LMS app installation had warnings${NC}"
        
        # Configure sidebar settings and disable PWA after LMS installation
        configure_sidebar_settings ${SITE_NAME}
        disable_pwa_prompt ${SITE_NAME}
        
        echo -e "${YELLOW}Installing Payments app...${NC}"
        bench --site ${SITE_NAME} install-app payments 2>&1 || echo -e "${YELLOW}Payments app installation had warnings${NC}"
        
        # Build assets only if needed (saves memory)
        build_assets_if_needed
        
        echo -e "${GREEN}Site setup complete!${NC}"
    else
        echo -e "${RED}Failed to create or initialize site. Check logs above.${NC}"
        echo -e "${YELLOW}Attempting to continue anyway...${NC}"
    fi
else
    echo -e "${GREEN}Site ${SITE_NAME} already exists.${NC}"
    
    # Disable SSL in site config
    disable_ssl_in_site_config "$SITE_CONFIG"
    
    # Check if database is properly initialized
    if ! check_db_initialized ${SITE_NAME}; then
        echo -e "${YELLOW}Database not properly initialized. Attempting to fix...${NC}"
        
        # Try migrations first
        echo -e "${YELLOW}Running migrations to initialize database...${NC}"
        cd /home/frappe/frappe-bench
        if bench --site ${SITE_NAME} migrate > /tmp/migrate.log 2>&1; then
            if check_db_initialized ${SITE_NAME}; then
                echo -e "${GREEN}Database initialized via migrations!${NC}"
            else
                echo -e "${YELLOW}Migrations didn't initialize database. Dropping and recreating site...${NC}"
                cd /home/frappe/frappe-bench
                bench drop-site ${SITE_NAME} --force --db-root-password ${DB_ROOT_PASSWORD} 2>/dev/null || true
                
                # Recreate site
                cd /home/frappe/frappe-bench
                if bench new-site ${SITE_NAME} \
                    --admin-password ${ADMIN_PASSWORD} \
                    --mariadb-user-host-login-scope='%' \
                    --set-default \
                    --db-root-password ${DB_ROOT_PASSWORD} \
                    --no-mariadb-socket \
                    --force > /tmp/site-recreate.log 2>&1; then
                    echo -e "${GREEN}Site recreated successfully!${NC}"
                else
                    echo -e "${YELLOW}Site recreation had errors, but continuing...${NC}"
                    cat /tmp/site-recreate.log | tail -10
                fi
                
                # Disable SSL again after recreation
                disable_ssl_in_site_config "$SITE_CONFIG"
                
                # Try migrations again
                cd /home/frappe/frappe-bench
                bench --site ${SITE_NAME} migrate 2>&1 || true
            fi
        else
            echo -e "${YELLOW}Migrations failed, but continuing...${NC}"
        fi
        
        # Install LMS and Payments if database is now initialized
        if check_db_initialized ${SITE_NAME}; then
            cd /home/frappe/frappe-bench
            
            # Set site URL if provided
            if [ ! -z "${SITE_URL}" ]; then
                configure_site_url ${SITE_NAME} "${SITE_URL}"
            fi
            
            echo -e "${YELLOW}Installing LMS app...${NC}"
            bench --site ${SITE_NAME} install-app lms 2>&1 || echo -e "${YELLOW}LMS app installation had warnings${NC}"
            
            # Configure sidebar settings and disable PWA after LMS installation
            configure_sidebar_settings ${SITE_NAME}
            disable_pwa_prompt ${SITE_NAME}
            
            echo -e "${YELLOW}Installing Payments app...${NC}"
            bench --site ${SITE_NAME} install-app payments 2>&1 || echo -e "${YELLOW}Payments app installation had warnings${NC}"
            
            # Build assets only if needed (saves memory)
            build_assets_if_needed
        fi
    else
        echo -e "${GREEN}Database is properly initialized.${NC}"
        cd /home/frappe/frappe-bench
        
        # Set site URL if provided
        if [ ! -z "${SITE_URL}" ]; then
            configure_site_url ${SITE_NAME} "${SITE_URL}"
        fi
        
        # Check if LMS is installed
        if ! bench --site ${SITE_NAME} list-apps 2>/dev/null | grep -q lms; then
            echo -e "${YELLOW}Installing LMS app...${NC}"
            bench --site ${SITE_NAME} install-app lms 2>&1 || echo -e "${YELLOW}LMS app installation had warnings${NC}"
            # Configure sidebar settings and disable PWA after LMS installation
            configure_sidebar_settings ${SITE_NAME}
            disable_pwa_prompt ${SITE_NAME}
        else
            # Ensure settings are configured even if LMS is already installed
            configure_sidebar_settings ${SITE_NAME}
            disable_pwa_prompt ${SITE_NAME}
        fi
        # Check if Payments is installed
        if ! bench --site ${SITE_NAME} list-apps 2>/dev/null | grep -q payments; then
            echo -e "${YELLOW}Installing Payments app...${NC}"
            bench --site ${SITE_NAME} install-app payments 2>&1 || echo -e "${YELLOW}Payments app installation had warnings${NC}"
        fi
    fi
fi

# Update site configuration if needed
if [ -f "sites/${SITE_NAME}/site_config.json" ]; then
    echo -e "${GREEN}Site configuration found.${NC}"
    
    # Set site URL (host_name) if SITE_URL is provided
    if [ ! -z "${SITE_URL}" ]; then
        configure_site_url ${SITE_NAME} "${SITE_URL}"
        echo -e "${GREEN}Site URL configured!${NC}"
    fi
    
    # Ensure sidebar settings and PWA are configured (runs on every startup)
    if bench --site ${SITE_NAME} list-apps 2>/dev/null | grep -q lms; then
        configure_sidebar_settings ${SITE_NAME}
        disable_pwa_prompt ${SITE_NAME}
    fi
fi

# Build assets only if needed (saves memory - assets are already built in Docker image)
build_assets_if_needed

# Clear cache
echo -e "${YELLOW}Clearing cache...${NC}"
cd /home/frappe/frappe-bench
bench --site ${SITE_NAME} clear-cache || true

# Run migrations
echo -e "${YELLOW}Running migrations...${NC}"
cd /home/frappe/frappe-bench
bench --site ${SITE_NAME} migrate || true

# Fix workspace charts after migrations (ensures it runs on every start)
echo -e "${YELLOW}Fixing workspace charts...${NC}"
cd /home/frappe/frappe-bench
bench --site ${SITE_NAME} console << PYEOF 2>/dev/null || true
import frappe
import json

try:
    if frappe.db.exists("Workspace", "LMS"):
        workspace = frappe.get_doc("Workspace", "LMS")
        changed = False
        
        # Remove all charts from charts array
        if workspace.charts:
            workspace.charts = []
            changed = True
        
        # Remove chart blocks from content
        if workspace.content:
            try:
                content_blocks = json.loads(workspace.content)
                original_count = len(content_blocks)
                content_blocks = [b for b in content_blocks if b.get("type") != "chart"]
                if len(content_blocks) < original_count:
                    workspace.content = json.dumps(content_blocks)
                    changed = True
            except (json.JSONDecodeError, TypeError):
                pass
        
        if changed:
            workspace.save(ignore_permissions=True)
            frappe.db.commit()
            print("✅ Workspace charts fixed")
    else:
        print("Workspace LMS not found")
except Exception as e:
    print(f"Error fixing workspace: {e}")
PYEOF

echo -e "${GREEN}Starting Frappe server...${NC}"
echo ""

# Ensure we're in the bench directory before starting
cd /home/frappe/frappe-bench

# Set error handling back for the main command
set -e

# Execute the command
exec "$@"

