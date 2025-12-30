#!/usr/bin/env python3.14
"""
Script to fix MariaDB database connection for Frappe site
This script attempts to fix database user permissions
"""

import subprocess
import sys
import json
import os

def run_command(cmd, input_text=None):
    """Run a shell command"""
    try:
        if input_text:
            result = subprocess.run(
                cmd,
                input=input_text,
                shell=True,
                capture_output=True,
                text=True
            )
        else:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True
            )
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def main():
    print("=" * 50)
    print("Frappe Database Connection Fixer")
    print("=" * 50)
    print()
    
    # Read site config
    site_config_path = "frappe-bench/sites/localhost/site_config.json"
    if not os.path.exists(site_config_path):
        print(f"❌ Site config not found: {site_config_path}")
        return 1
    
    with open(site_config_path, 'r') as f:
        site_config = json.load(f)
    
    db_name = site_config.get('db_name')
    db_user = site_config.get('db_user')
    db_password = site_config.get('db_password')
    
    print(f"Database: {db_name}")
    print(f"User: {db_user}")
    print()
    
    # Get MariaDB root password
    root_password = os.environ.get('MARIADB_ROOT_PASSWORD')
    if not root_password:
        print("⚠️  MARIADB_ROOT_PASSWORD environment variable not set")
        print("   Please set it: export MARIADB_ROOT_PASSWORD='your_password'")
        print()
        root_password = input("Enter MariaDB root password (or press Enter to skip): ").strip()
        if not root_password:
            print("❌ Root password required to fix database permissions")
            return 1
    
    # Try to fix database user permissions
    print("🔧 Attempting to fix database user permissions...")
    
    sql_commands = f"""
GRANT ALL PRIVILEGES ON `{db_name}`.* TO '{db_user}'@'localhost' IDENTIFIED BY '{db_password}';
FLUSH PRIVILEGES;
"""
    
    success, stdout, stderr = run_command(
        f"mysql -u root -p'{root_password}' -e \"{sql_commands}\""
    )
    
    if success:
        print("✅ Database permissions fixed!")
        print()
        print("Testing connection...")
        success, stdout, stderr = run_command(
            f"mysql -u {db_user} -p'{db_password}' -e 'USE {db_name}; SELECT 1;'"
        )
        if success:
            print("✅ Database connection successful!")
            return 0
        else:
            print(f"⚠️  Connection test failed: {stderr}")
    else:
        print(f"❌ Failed to fix permissions: {stderr}")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())

