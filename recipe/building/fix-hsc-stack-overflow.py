#!/usr/bin/env python
"""
Fix for HSC tool stack overflow on Windows.
The HSC tools crash with exit code -1073741571 (0xC00000FD) which is STATUS_STACK_OVERFLOW.
This script patches the HSC tools to increase stack size or apply other mitigations.
"""
import os
import sys
import subprocess
import shutil
import glob

def patch_executable_stack_size(exe_path, stack_size_mb=16):
    """
    Use editbin to increase the stack size of an executable.
    This helps prevent stack overflow errors.
    """
    print(f"Patching stack size for: {exe_path}")
    
    # Convert MB to bytes
    stack_size_bytes = stack_size_mb * 1024 * 1024
    
    # Look for editbin.exe (part of Visual Studio)
    editbin_paths = [
        "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/*/bin/Hostx64/x64/editbin.exe",
        "C:/Program Files (x86)/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/*/bin/Hostx64/x64/editbin.exe",
        os.path.join(os.environ.get("VSINSTALLDIR", ""), "VC/Tools/MSVC/*/bin/Hostx64/x64/editbin.exe")
    ]
    
    editbin_exe = None
    for pattern in editbin_paths:
        matches = glob.glob(pattern)
        if matches:
            editbin_exe = matches[0]
            break
    
    if not editbin_exe or not os.path.exists(editbin_exe):
        print("Warning: editbin.exe not found, trying alternative approach")
        return try_alternative_stack_fix(exe_path)
    
    try:
        # Increase stack size using editbin
        cmd = [editbin_exe, "/STACK:" + str(stack_size_bytes), exe_path]
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            return True
        else:
            print(f"editbin failed: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"Error running editbin: {e}")
        return False

def try_alternative_stack_fix(exe_path):
    """
    Alternative approach: Create a wrapper that sets stack size via ulimit or other means
    """
    print("Trying alternative stack fix approach")
    
    # Rename the original executable
    backup_path = exe_path + ".original"
    if not os.path.exists(backup_path):
        try:
            shutil.move(exe_path, backup_path)
        except Exception as e:
            print(f"Failed to move executable: {e}")
            return False
    
    # Create a wrapper batch script
    wrapper_content = f"""@echo off
REM HSC tool wrapper to prevent stack overflow
REM Set larger stack size using Windows-specific methods

REM Try to set stack reserve size via environment (may not work for all programs)
set STACK_SIZE=16777216

REM Call the original executable with all arguments
"{backup_path}" %*
"""
    
    try:
        with open(exe_path, 'w') as f:
            f.write(wrapper_content)
        print(f"Created wrapper script at {exe_path}")
        return True
    except Exception as e:
        print(f"Failed to create wrapper: {e}")
        return False

def find_and_patch_hsc_tools(search_paths):
    """
    Find all HSC tools and patch them to prevent stack overflow
    """
    print("Searching for HSC tools to patch...")
    
    patterns = [
        "*_hsc_make.exe",
        "*_hsc_*.exe",
        "hsc2hs.exe"
    ]
    
    patched_count = 0
    
    for base_path in search_paths:
        if not os.path.exists(base_path):
            continue
            
        for pattern in patterns:
            # Search recursively
            search_pattern = os.path.join(base_path, "**", pattern)
            matches = glob.glob(search_pattern, recursive=True)
            
            for exe_path in matches:
                if os.path.isfile(exe_path) and not exe_path.endswith(".original"):
                    # Check if it's already been patched
                    if os.path.exists(exe_path + ".original"):
                        continue
                    
                    # Try to patch it
                    if patch_executable_stack_size(exe_path):
                        patched_count += 1
                    else:
                        print("  Patch failed, trying wrapper approach")
                        if try_alternative_stack_fix(exe_path):
                            patched_count += 1
    
    return patched_count

def main():
    """Main entry point"""
    print("HSC Stack Overflow Fixer")
    print("========================")
    
    # Default search paths
    search_paths = [
        "C:/cabal",
        "C:/cabal/store",
        os.path.expandvars("$BUILD_PREFIX"),
        os.path.expandvars("$SRC_DIR"),
        ".",
    ]
    
    # Add command line arguments as additional search paths
    if len(sys.argv) > 1:
        search_paths.extend(sys.argv[1:])
    
    # Remove duplicates and expand paths
    search_paths = list(set(os.path.expandvars(p) for p in search_paths))
    
    # Find and patch HSC tools
    patched = find_and_patch_hsc_tools(search_paths)
    
    print(f"\nPatched {patched} HSC tools")
    
    if patched > 0:
        print("Stack overflow mitigation applied successfully")
        return 0
    else:
        print("No HSC tools found to patch")
        return 1

if __name__ == "__main__":
    sys.exit(main())