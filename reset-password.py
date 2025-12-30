#!/usr/bin/env python3.14
"""Reset MariaDB root password using Python"""

import subprocess
import time
import sys
import os

NEW_PASSWORD = "vgiskill@2026#"

def run_cmd(cmd, check=True):
    """Run a command"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if check and result.returncode != 0:
            print(f"Error: {result.stderr}")
            return False
        return True, result.stdout, result.stderr
    except Exception as e:
        print(f"Exception: {e}")
        return False, "", str(e)

print("=" * 50)
print("Resetting MariaDB Root Password")
print("=" * 50)
print()

# Stop MariaDB
print("Step 1: Stopping MariaDB...")
run_cmd("brew services stop mariadb", check=False)
time.sleep(3)

# Start in safe mode
print("Step 2: Starting MariaDB in safe mode...")
proc = subprocess.Popen(
    ["mysqld_safe", "--skip-grant-tables", "--skip-networking"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)
time.sleep(8)

# Reset password using Python MySQL connector
print("Step 3: Resetting password...")
try:
    import MySQLdb
    
    # Connect without password in safe mode
    conn = MySQLdb.connect(host='127.0.0.1', user='root', db='mysql')
    cursor = conn.cursor()
    
    # Try different methods
    methods = [
        f"ALTER USER 'root'@'localhost' IDENTIFIED BY '{NEW_PASSWORD}'",
        f"SET PASSWORD FOR 'root'@'localhost' = PASSWORD('{NEW_PASSWORD}')",
        f"UPDATE mysql.user SET password=PASSWORD('{NEW_PASSWORD}') WHERE User='root' AND Host='localhost'",
        f"UPDATE mysql.user SET authentication_string=PASSWORD('{NEW_PASSWORD}'), plugin='mysql_native_password' WHERE User='root' AND Host='localhost'"
    ]
    
    for method in methods:
        try:
            cursor.execute("FLUSH PRIVILEGES;")
            cursor.execute(method)
            cursor.execute("FLUSH PRIVILEGES;")
            conn.commit()
            print(f"   ✅ Password reset using: {method[:50]}...")
            break
        except Exception as e:
            print(f"   ⚠️  Method failed: {str(e)[:50]}")
            continue
    
    cursor.close()
    conn.close()
    
except ImportError:
    print("   ⚠️  MySQLdb not available, trying command line method...")
    # Fallback to command line
    run_cmd(f"mysql -u root -e \"FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '{NEW_PASSWORD}'; FLUSH PRIVILEGES;\"", check=False)
except Exception as e:
    print(f"   ❌ Error: {e}")

# Stop safe mode
print("Step 4: Stopping safe mode...")
proc.terminate()
proc.wait()
time.sleep(3)

# Start MariaDB normally
print("Step 5: Starting MariaDB normally...")
run_cmd("brew services start mariadb", check=False)
time.sleep(5)

# Test password
print("Step 6: Testing new password...")
try:
    conn = MySQLdb.connect(host='127.0.0.1', user='root', password=NEW_PASSWORD, db='mysql')
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()
    cursor.close()
    conn.close()
    print("   ✅ Password reset successful!")
    print()
    print(f"   New root password: {NEW_PASSWORD}")
    sys.exit(0)
except Exception as e:
    print(f"   ❌ Password test failed: {e}")
    print()
    print("   Please manually reset the password:")
    print("   1. Stop MariaDB: brew services stop mariadb")
    print("   2. Start safe mode: mysqld_safe --skip-grant-tables &")
    print("   3. Connect: mysql -u root")
    print(f"   4. Run: ALTER USER 'root'@'localhost' IDENTIFIED BY '{NEW_PASSWORD}';")
    print("   5. Run: FLUSH PRIVILEGES;")
    sys.exit(1)

