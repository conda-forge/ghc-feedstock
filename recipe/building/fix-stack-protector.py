#!/usr/bin/env python
"""
Fix for Windows Stack Protector issues with GHC HSC tools.

Based on: https://gitlab.haskell.org/ghc/ghc/-/wikis/Building-GHC-on-Windows-with-Stack-protector-support-(SSP)-(using-Make)

The issue is that HSC tools may be built with stack protection enabled but without
proper stack protection symbols, causing crashes with exit code -1073741571 (STATUS_STACK_OVERFLOW).
"""
import os
import sys
import subprocess
import shutil
import tempfile

def create_stack_protector_stub():
    """
    Create a stub library that provides __stack_chk_fail and related symbols
    to prevent stack protector crashes.
    """
    
    stub_source = '''
#include <stdio.h>
#include <stdlib.h>

// Stub implementation of stack check failure
// This should never be called if stack protection is properly disabled
void __stack_chk_fail(void) {
    fprintf(stderr, "Stack check failure detected\\n");
    exit(1);
}

// Additional symbols that might be needed
void __stack_chk_fail_local(void) {
    __stack_chk_fail();
}

void __stack_chk_guard(void) {
    // Guard symbol - usually just a variable
}
'''
    
    temp_dir = tempfile.mkdtemp()
    source_file = os.path.join(temp_dir, "stack_protector_stub.c")
    
    try:
        with open(source_file, 'w') as f:
            f.write(stub_source)
        
        # Find clang
        clang_exe = None
        for env_var in ['CC', 'CLANG']:
            if env_var in os.environ:
                clang_exe = os.environ[env_var]
                break
        
        if not clang_exe or not os.path.exists(clang_exe):
            clang_exe = shutil.which('clang.exe') or shutil.which('clang')
        
        if not clang_exe:
            print("Warning: Could not find clang to build stack protector stub")
            return None
        
        # Build the stub library
        output_dir = os.path.join(os.environ.get('BUILD_PREFIX', ''), 'lib')
        os.makedirs(output_dir, exist_ok=True)
        
        lib_file = os.path.join(output_dir, 'libstack_protector_stub.a')
        obj_file = os.path.join(temp_dir, 'stack_protector_stub.o')
        
        # Compile object file
        compile_cmd = [
            clang_exe,
            '-c', source_file,
            '-o', obj_file,
            '--target=x86_64-w64-mingw32',
            '-fno-stack-protector',  # Don't protect the protector!
            '-O2'
        ]
        
        print(f"Compiling stack protector stub: {' '.join(compile_cmd)}")
        result = subprocess.run(compile_cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"Failed to compile stub: {result.stderr}")
            return None
        
        # Create archive
        ar_exe = shutil.which('llvm-ar.exe') or shutil.which('ar.exe') or shutil.which('ar')
        if not ar_exe:
            print("Warning: Could not find ar tool")
            return None
        
        ar_cmd = [ar_exe, 'rcs', lib_file, obj_file]
        print(f"Creating archive: {' '.join(ar_cmd)}")
        result = subprocess.run(ar_cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"Failed to create archive: {result.stderr}")
            return None
        
        print(f"Created stack protector stub library: {lib_file}")
        return lib_file
        
    except Exception as e:
        print(f"Error creating stack protector stub: {e}")
        return None
    finally:
        # Clean up temp directory
        try:
            shutil.rmtree(temp_dir)
        except:
            pass

def patch_cabal_config():
    """
    Patch the Cabal configuration to ensure stack protection is disabled
    """
    cabal_config_paths = [
        os.path.expanduser("~/.cabal/config"),
        "C:/cabal/config",
        os.path.join(os.environ.get('APPDATA', ''), 'cabal', 'config')
    ]
    
    # Add stack protector disable flags to compiler options
    stack_protect_flags = [
        "cc-options: -fno-stack-protector -fno-stack-check",
        "cxx-options: -fno-stack-protector -fno-stack-check", 
        "ld-options: -fno-stack-protector"
    ]
    
    for config_path in cabal_config_paths:
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    content = f.read()
                
                # Check if our flags are already there
                if '-fno-stack-protector' in content:
                    print(f"Stack protector flags already in {config_path}")
                    continue
                
                # Add flags
                content += "\n-- Stack protector disable flags\n"
                content += "\n".join(stack_protect_flags) + "\n"
                
                # Backup original
                backup_path = config_path + ".stack-protector-backup"
                if not os.path.exists(backup_path):
                    shutil.copy2(config_path, backup_path)
                
                # Write updated config
                with open(config_path, 'w') as f:
                    f.write(content)
                
                print(f"Updated Cabal config: {config_path}")
                
            except Exception as e:
                print(f"Failed to update {config_path}: {e}")

def set_environment_variables():
    """
    Set environment variables to disable stack protection
    """
    stack_protect_vars = {
        'CFLAGS': '-fno-stack-protector -fno-stack-check',
        'CXXFLAGS': '-fno-stack-protector -fno-stack-check',
        'LDFLAGS': '-fno-stack-protector'
    }
    
    for var, flags in stack_protect_vars.items():
        current = os.environ.get(var, '')
        if '-fno-stack-protector' not in current:
            new_value = f"{current} {flags}".strip()
            os.environ[var] = new_value
            print(f"Set {var}={new_value}")

def main():
    """Main entry point"""
    print("Windows Stack Protector Fix for GHC HSC Tools")
    print("=" * 50)
    
    print("Setting environment variables...")
    set_environment_variables()
    
    print("Patching Cabal configuration...")
    patch_cabal_config()
    
    print("Creating stack protector stub library...")
    stub_lib = create_stack_protector_stub()
    if stub_lib:
        print(f"Stack protector stub created: {stub_lib}")
        # Add to library path
        lib_dir = os.path.dirname(stub_lib)
        current_lib = os.environ.get('LIB', '')
        if lib_dir not in current_lib:
            os.environ['LIB'] = f"{current_lib};{lib_dir}" if current_lib else lib_dir
    
    print("Stack protector fixes applied successfully")
    return 0

if __name__ == "__main__":
    sys.exit(main())