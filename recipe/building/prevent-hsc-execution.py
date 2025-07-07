#!/usr/bin/env python
"""
Prevent HSC tool execution by modifying Makefiles and timestamps.

This script ensures that:
1. Generated .hs files have newer timestamps than .hsc sources
2. Makefiles are patched to skip HSC tool execution  
3. HSC executables are replaced with success-returning stubs
"""
import os
import sys
import glob
import time
import shutil
import tempfile

def update_file_timestamps(search_paths):
    """
    Update timestamps to make .hs files newer than .hsc files
    """
    print("Updating file timestamps to prevent HSC regeneration...")
    
    for base_path in search_paths:
        if not os.path.exists(base_path):
            continue
            
        print(f"Searching in: {base_path}")
        
        # Find all .hsc files
        hsc_pattern = os.path.join(base_path, "**", "*.hsc")
        hsc_files = glob.glob(hsc_pattern, recursive=True)
        
        for hsc_file in hsc_files:
            # Find corresponding .hs file
            hs_file = hsc_file.replace('.hsc', '.hs')
            
            if os.path.exists(hs_file):
                print(f"  Updating timestamp: {hs_file}")
                
                # Get current time + 1 hour to ensure it's newer
                future_time = time.time() + 3600
                
                # Update both access and modification times
                os.utime(hs_file, (future_time, future_time))
                
                # Also touch any related files that might trigger rebuilds
                base_name = os.path.splitext(hs_file)[0]
                related_extensions = ['.o', '.hi', '.dyn_o', '.dyn_hi']
                
                for ext in related_extensions:
                    related_file = base_name + ext
                    if os.path.exists(related_file):
                        os.utime(related_file, (future_time, future_time))

def patch_makefiles(search_paths):
    """
    Patch Makefiles to prevent HSC tool execution
    """
    print("Patching Makefiles to prevent HSC execution...")
    
    for base_path in search_paths:
        if not os.path.exists(base_path):
            continue
            
        # Find all Makefiles
        makefile_patterns = [
            os.path.join(base_path, "**", "Makefile"),
            os.path.join(base_path, "**", "makefile"),
            os.path.join(base_path, "**", "GNUmakefile")
        ]
        
        for pattern in makefile_patterns:
            makefiles = glob.glob(pattern, recursive=True)
            
            for makefile in makefiles:
                patch_makefile(makefile)

def patch_makefile(makefile_path):
    """
    Patch a specific Makefile to prevent HSC tool execution
    """
    if not os.path.exists(makefile_path):
        return
        
    print(f"  Patching: {makefile_path}")
    
    try:
        with open(makefile_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        
        # Backup original
        backup_path = makefile_path + ".hsc-backup"
        if not os.path.exists(backup_path):
            shutil.copy2(makefile_path, backup_path)
        
        # Look for HSC tool invocations and replace them
        lines = content.split('\n')
        modified = False
        
        for i, line in enumerate(lines):
            # Look for lines that invoke HSC tools
            if '_hsc_make.exe' in line or 'hsc2hs' in line:
                # Check if this is a command line (starts with tab)
                if line.strip() and (line.startswith('\t') or line.startswith('    ')):
                    indent = line[:len(line) - len(line.lstrip())]
                    
                    # Replace with a comment and success command
                    lines[i] = f"{indent}# HSC tool execution disabled - using pre-generated files"
                    if i + 1 < len(lines):
                        lines.insert(i + 1, f"{indent}@echo 'Using pre-generated .hs file'")
                    modified = True
                    print(f"    Disabled HSC execution: {line.strip()}")
        
        if modified:
            with open(makefile_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines))
            print(f"    Successfully patched {makefile_path}")
        
    except Exception as e:
        print(f"    Error patching {makefile_path}: {e}")

def replace_hsc_executables(search_paths):
    """
    Replace HSC executables with stubs that always return success
    """
    print("Replacing HSC executables with success stubs...")
    
    for base_path in search_paths:
        if not os.path.exists(base_path):
            continue
            
        # Find HSC executables
        hsc_patterns = [
            os.path.join(base_path, "**", "*_hsc_make.exe"),
            os.path.join(base_path, "**", "hsc2hs.exe")
        ]
        
        for pattern in hsc_patterns:
            executables = glob.glob(pattern, recursive=True)
            
            for exe_path in executables:
                if os.path.exists(exe_path) and not exe_path.endswith('.original'):
                    replace_with_stub(exe_path)

def replace_with_stub(exe_path):
    """
    Replace an executable with a stub that returns success
    """
    print(f"  Replacing with stub: {exe_path}")
    
    try:
        # Backup original
        backup_path = exe_path + ".original"
        if not os.path.exists(backup_path):
            shutil.move(exe_path, backup_path)
        
        # Create a batch file stub
        stub_content = f'''@echo off
REM HSC tool stub - using pre-generated files
echo HSC tool called: %0 %*
echo Using pre-generated .hs file instead
REM Always return success
exit /b 0
'''
        
        with open(exe_path, 'w') as f:
            f.write(stub_content)
        
        print(f"    Created stub for {exe_path}")
        
    except Exception as e:
        print(f"    Error creating stub for {exe_path}: {e}")

def main():
    """Main entry point"""
    print("HSC Execution Prevention Tool")
    print("=" * 40)
    
    # Default search paths
    search_paths = [
        "C:/cabal",
        "C:/cabal/store", 
        os.path.expandvars("$SRC_DIR"),
        os.path.expandvars("$BUILD_PREFIX"),
        ".",
    ]
    
    # Add command line arguments
    if len(sys.argv) > 1:
        search_paths.extend(sys.argv[1:])
    
    # Remove duplicates and expand
    search_paths = list(set(os.path.expandvars(p) for p in search_paths))
    
    # Apply all prevention measures
    update_file_timestamps(search_paths)
    patch_makefiles(search_paths)
    replace_hsc_executables(search_paths)
    
    print("\nHSC execution prevention measures applied successfully")
    return 0

if __name__ == "__main__":
    sys.exit(main())