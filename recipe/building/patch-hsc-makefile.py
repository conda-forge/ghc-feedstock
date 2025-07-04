#!/usr/bin/env python
"""
Patch HSC Makefiles to use our wrapper for improved stack handling
"""
import os
import sys
import glob
import re

def patch_hsc_makefile(makefile_path):
    """Modify HSC makefile to use our wrapper"""
    if not os.path.exists(makefile_path):
        print(f"Error: Makefile not found at {makefile_path}")
        return False

    print(f"Patching HSC makefile: {makefile_path}")
    with open(makefile_path, 'r') as f:
        content = f.read()

    # Check if the makefile contains HSC2HS rules
    if 'Clock_hsc_make' not in content and '_hsc_make' not in content:
        print(f"Not an HSC makefile: {makefile_path}")
        return False

    # Get the HSC wrapper path from environment
    hsc_wrapper = os.environ.get('HSC_WRAPPER', '')
    if not hsc_wrapper:
        print("Warning: HSC_WRAPPER environment variable not set")
        return False

    # Escape backslashes for Makefile syntax
    hsc_wrapper_esc = hsc_wrapper.replace('\\', '\\\\')

    # Modify HSC tool execution to use our wrapper
    modified = re.sub(
        r'(\s*)([^\s]+_hsc_make\.exe)(\s+)',
        r'\1"' + hsc_wrapper_esc + r'" \2\3',
        content
    )

    if modified == content:
        print(f"No changes needed in {makefile_path}")
        return False

    # Write the modified content back
    with open(makefile_path, 'w') as f:
        f.write(modified)

    print(f"Successfully patched {makefile_path}")
    return True

def main():
    """Find and patch all HSC makefiles"""
    if len(sys.argv) > 1:
        # Patch specific makefile
        return patch_hsc_makefile(sys.argv[1])

    # Find all makefiles in the current directory and subdirectories
    count = 0
    for root, _, files in os.walk('.'):
        for filename in files:
            if filename == 'Makefile':
                makefile_path = os.path.join(root, filename)
                if patch_hsc_makefile(makefile_path):
                    count += 1

    print(f"Patched {count} HSC makefiles")
    return True

if __name__ == "__main__":
    sys.exit(0 if main() else 1)

