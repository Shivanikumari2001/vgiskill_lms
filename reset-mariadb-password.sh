#!/bin/bash

# Reset MariaDB root password
set -e

NEW_PASSWORD="vgiskill@2026#"

echo "Resetting MariaDB root password..."

# Stop MariaDB
brew services stop mariadb
sleep 2

# Start in safe mode
echo "Starting MariaDB in safe mode..."
mysqld_safe --skip-grant-tables --skip-networking > /tmp/mysql-safe.log 2>&1 &
MYSQL_SAFE_PID=$!
sleep 8

# Reset password using different methods
echo "Resetting password..."

# Method 1: For MariaDB 10.4+
mysql -u root << EOF 2>/dev/null || true
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '$NEW_PASSWORD';
FLUSH PRIVILEGES;
EOF

# Method 2: For older versions
mysql -u root << EOF 2>/dev/null || true
USE mysql;
UPDATE user SET password=PASSWORD('$NEW_PASSWORD') WHERE User='root' AND Host='localhost';
FLUSH PRIVILEGES;
EOF

# Method 3: Using authentication_string for newer versions
mysql -u root << EOF 2>/dev/null || true
USE mysql;
UPDATE user SET authentication_string=PASSWORD('$NEW_PASSWORD') WHERE User='root' AND Host='localhost';
UPDATE user SET plugin='mysql_native_password' WHERE User='root' AND Host='localhost';
FLUSH PRIVILEGES;
EOF

# Stop safe mode
kill $MYSQL_SAFE_PID 2>/dev/null || true
sleep 3

# Start MariaDB normally
echo "Starting MariaDB normally..."
brew services start mariadb
sleep 5

# Test the password
echo "Testing new password..."
if mysql -u root -p"$NEW_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ Password reset successful!"
    exit 0
else
    echo "❌ Password reset failed. Trying alternative method..."
    exit 1
fi

