#!/usr/bin/env python3
"""Create Frappe site with SSL disabled"""
import os
import sys
import subprocess

# Set environment to skip SSL
os.environ['MYSQL_SSL'] = '0'

# Change to bench directory
os.chdir('/Users/shivam/Downloads/variphi-lms-app/frappe-bench')

# Create site command
cmd = [
    sys.executable, '-m', 'frappe', 'new-site',
    'localhost',
    '--admin-password', 'admin',
    '--mariadb-user-host-login-scope=%',
    '--set-default',
    '--force',
    '--db-root-password', 'vgiskill@2026#'
]

# Run with SSL disabled by patching mysql command
env = os.environ.copy()
env['MYSQL_SSL'] = '0'

# Try to patch the mysql command to skip SSL
import shutil
mysql_path = shutil.which('mysql')
if mysql_path:
    # Create a wrapper script
    wrapper = '/tmp/mysql_no_ssl.sh'
    with open(wrapper, 'w') as f:
        f.write(f'''#!/bin/bash
{mysql_path} --skip-ssl "$@"
''')
    os.chmod(wrapper, 0o755)
    # Prepend to PATH
    env['PATH'] = '/tmp:' + env.get('PATH', '')

result = subprocess.run(cmd, env=env, capture_output=True, text=True)
print(result.stdout)
if result.stderr:
    print(result.stderr, file=sys.stderr)
sys.exit(result.returncode)

