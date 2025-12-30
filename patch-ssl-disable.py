#!/usr/bin/env python3
"""
Patch Frappe database connection to disable SSL when SSL config is empty
"""
import os
import re

def patch_file(file_path):
    """Patch a file to disable SSL when SSL config is empty"""
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return False
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Check if already patched
    if 'DISABLE_SSL_PATCH' in content:
        print(f"File already patched: {file_path}")
        return True
    
    modified = False
    
    # Pattern 1: Replace SSL check to also verify it's not empty
    pattern1 = r'if frappe\.conf\.db_ssl_ca:'
    replacement1 = 'if frappe.conf.db_ssl_ca and frappe.conf.db_ssl_ca.strip():  # DISABLE_SSL_PATCH'
    
    if re.search(pattern1, content):
        content = re.sub(pattern1, replacement1, content)
        modified = True
        print(f"Applied SSL check patch in {file_path}")
    
    # Pattern 2: Also ensure ssl is not set in conn_settings if SSL config is empty
    # Look for where ssl_config is set and add a check
    pattern2 = r'(\s+if frappe\.conf\.db_ssl_cert and frappe\.conf\.db_ssl_key:\s+ssl_config\.update\(\{"cert": frappe\.conf\.db_ssl_cert, "key": frappe\.conf\.db_ssl_key\}\)\s+conn_settings\["ssl"\] = ssl_config)'
    replacement2 = r'''\1
		# DISABLE_SSL_PATCH: Only set SSL if config is not empty
		if not (frappe.conf.db_ssl_ca and frappe.conf.db_ssl_ca.strip()):
			conn_settings.pop("ssl", None)'''
    
    if re.search(pattern2, content, re.MULTILINE):
        content = re.sub(pattern2, replacement2, content)
        modified = True
        print(f"Applied SSL removal patch in {file_path}")
    
    # Ensure SSL is removed from conn_settings if SSL config is empty
    # Find where conn_settings["ssl"] is set and add removal logic AFTER the if block
    if 'conn_settings["ssl"] = ssl_config' in content and 'DISABLE_SSL_PATCH: Remove SSL' not in content:
        lines = content.split('\n')
        new_lines = []
        i = 0
        while i < len(lines):
            line = lines[i]
            new_lines.append(line)
            
            # Look for the line with conn_settings["ssl"] = ssl_config
            if 'conn_settings["ssl"] = ssl_config' in line:
                # Find the end of the if block by looking for the next line at same or less indentation
                # that's not a comment or blank
                current_indent = len(line) - len(line.lstrip())
                j = i + 1
                block_end = i + 1
                
                # Find where the if block ends
                while j < len(lines):
                    next_line = lines[j]
                    if not next_line.strip() or next_line.strip().startswith('#'):
                        j += 1
                        continue
                    next_indent = len(next_line) - len(next_line.lstrip())
                    if next_indent <= current_indent:
                        block_end = j
                        break
                    j += 1
                
                # Insert the SSL removal code after the if block
                # Use tabs for indentation (Frappe uses tabs)
                indent_char = '\t' if line.startswith('\t') else ' '
                indent_level = len(line) - len(line.lstrip())
                
                # Insert after the if block ends
                new_lines.append(indent_char * indent_level + '# DISABLE_SSL_PATCH: Remove SSL if config is empty')
                new_lines.append(indent_char * indent_level + 'if not (frappe.conf.db_ssl_ca and frappe.conf.db_ssl_ca.strip()):')
                new_lines.append(indent_char * (indent_level + 1) + 'conn_settings.pop("ssl", None)')
                modified = True
                i = block_end - 1  # Skip to end of block (will be incremented)
            
            i += 1
        
        if modified:
            content = '\n'.join(new_lines)
            print(f"Applied SSL removal patch in {file_path}")
    
    if modified:
        with open(file_path, 'w') as f:
            f.write(content)
        print(f"Successfully patched: {file_path}")
        return True
    
    print(f"No changes needed or patch failed: {file_path}")
    return False

def patch_db_manager(file_path):
    """Patch db_manager.py to add --skip-ssl to mysql commands"""
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return False
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    if '--skip-ssl' in content or 'DISABLE_SSL_PATCH_DB_MANAGER' in content:
        print(f"File already patched: {file_path}")
        return True
    
    # Find where command list ends and add --skip-ssl
    lines = content.split('\n')
    new_lines = []
    modified = False
    
    for i, line in enumerate(lines):
        new_lines.append(line)
        # Look for mysql command in the line
        if "'mysql'" in line or '"mysql"' in line:
            # Find the closing bracket of the command list
            j = i
            bracket_count = 0
            found_opening = False
            while j < len(lines):
                current_line = lines[j]
                bracket_count += current_line.count('[') - current_line.count(']')
                if '[' in current_line:
                    found_opening = True
                if found_opening and bracket_count == 0 and ']' in current_line:
                    # Found the closing bracket, add --skip-ssl before it
                    indent = len(current_line) - len(current_line.lstrip())
                    # Insert before the closing bracket
                    if current_line.strip() == ']':
                        new_lines[-1] = ' ' * indent + "'--skip-ssl',  # DISABLE_SSL_PATCH_DB_MANAGER"
                        new_lines.append(current_line)
                        modified = True
                    elif current_line.rstrip().endswith(']'):
                        # Bracket is on same line, insert before it
                        new_lines[-1] = current_line.rstrip()[:-1] + ", '--skip-ssl']  # DISABLE_SSL_PATCH_DB_MANAGER"
                        modified = True
                    break
                j += 1
    
    if modified:
        with open(file_path, 'w') as f:
            f.write('\n'.join(new_lines))
        print(f"Patched db_manager.py: {file_path}")
        return True
    
    print(f"Could not find mysql command to patch in {file_path}")
    return False

def main():
    bench_path = os.environ.get('BENCH_PATH', '/home/frappe/frappe-bench')
    
    files_to_patch = [
        f'{bench_path}/apps/frappe/frappe/database/mariadb/database.py',
        f'{bench_path}/apps/frappe/frappe/database/mariadb/mysqlclient.py',
    ]
    
    for file_path in files_to_patch:
        patch_file(file_path)
    
    # Also patch db_manager.py to add --skip-ssl to mysql commands
    db_manager_path = f'{bench_path}/apps/frappe/frappe/database/db_manager.py'
    patch_db_manager(db_manager_path)
    
    # Patch get_command to add --skip-ssl
    db_init_path = f'{bench_path}/apps/frappe/frappe/database/__init__.py'
    patch_get_command(db_init_path)

def patch_get_command(file_path):
    """Patch get_command function to add --skip-ssl to mysql args"""
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return False
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    if 'DISABLE_SSL_PATCH_GET_COMMAND' in content:
        print(f"File already patched: {file_path}")
        return True
    
    # Simple string replacement - add --skip-ssl after command.append(db_name)
    old_pattern = "command.append(db_name)\n\n\t\tif extra:"
    new_pattern = "command.append(db_name)\n\t\tcommand.append('--skip-ssl')  # DISABLE_SSL_PATCH_GET_COMMAND\n\n\t\tif extra:"
    
    if old_pattern in content:
        content = content.replace(old_pattern, new_pattern)
        with open(file_path, 'w') as f:
            f.write(content)
        print(f"Patched get_command in {file_path}")
        return True
    
    print(f"Could not find pattern to patch in {file_path}")
    return False

if __name__ == '__main__':
    main()

