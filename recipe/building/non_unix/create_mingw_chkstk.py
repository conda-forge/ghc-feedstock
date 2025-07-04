#!/usr/bin/env python

import os
import sys
import subprocess
import tempfile
import platform


def main():
    """Create a custom MinGW chkstk_ms.obj file to provide ___chkstk_ms symbol."""

    print("Starting create_mingw_chkstk.py")
    print(f"Python version: {platform.python_version()}")
    print(f"Platform: {platform.system()} {platform.release()}")

    # Get build environment variables
    build_prefix = os.environ.get('BUILD_PREFIX', os.environ.get('_BUILD_PREFIX', ''))
    if not build_prefix:
        print("Error: BUILD_PREFIX environment variable not set")
        return 1

    print(f"Using build_prefix: {build_prefix}")

    # Fix path with double slashes and normalize
    build_prefix = build_prefix.replace('//', '/')

    # Convert Unix path to Windows if needed
    if build_prefix.startswith('/'):
        if len(build_prefix) > 2 and build_prefix[2] == '/':
            drive = build_prefix[1].lower()
            build_prefix = f"{drive}:{build_prefix[2:]}".replace('/', '\\')
        else:
            build_prefix = build_prefix.replace('/', '\\')
        print(f"Converted to Windows path: {build_prefix}")

    # Create output directory
    output_dir = os.path.join(build_prefix, 'Library', 'lib')
    print(f"Output directory: {output_dir}")

    try:
        os.makedirs(output_dir, exist_ok=True)
        print(f"Output directory created/exists: {output_dir}")
    except Exception as e:
        print(f"Error creating output directory: {e}")
        return 1

    output_file = os.path.join(output_dir, 'chkstk_mingw_ms.obj')
    print(f"Output file will be: {output_file}")

    # If output file already exists, we're done
    if os.path.exists(output_file):
        print(f"File already exists: {output_file}")
        return 0

    # Create a temporary file for the C source - use a more reliable method
    temp_dir = tempfile.mkdtemp()
    source_file = os.path.join(temp_dir, 'chkstk_ms.c')
    print(f"Created temporary source file: {source_file}")

    try:
        with open(source_file, 'w') as f:
            f.write("""
/* Simple implementation of __chkstk_ms for MinGW */
#include <stdint.h>
#define PAGE_SIZE 4096

void ___chkstk_ms(void) {
    unsigned char *probe;
    uintptr_t stack_ptr;
    __asm__("movq %%rsp, %0" : "=r" (stack_ptr));
    uintptr_t stack_size;
    __asm__("movq %%rax, %0" : "=r" (stack_size));
    
    if (stack_size <= PAGE_SIZE) {
        probe = (unsigned char*)(stack_ptr - stack_size);
        *probe = 0;
        return;
    }
    
    probe = (unsigned char*)(stack_ptr & ~(PAGE_SIZE - 1));
    while (stack_size > PAGE_SIZE) {
        probe -= PAGE_SIZE;
        *probe = 0;
        stack_size -= PAGE_SIZE;
    }
    probe -= stack_size;
    *probe = 0;
}

void __chkstk_ms(void) {
    ___chkstk_ms();
}
""")
    except Exception as e:
        print(f"Error writing source file: {e}")
        return 1

    # Find clang executable - try multiple paths
    clang_exe = None
    possible_paths = [
        os.path.join(build_prefix, 'Library', 'bin', 'clang.exe'),
        os.path.join(build_prefix, 'bin', 'clang.exe')
    ]

    for path in possible_paths:
        if os.path.exists(path):
            clang_exe = path
            print(f"Found clang at: {clang_exe}")
            break

    if not clang_exe:
        print("Error: Could not find clang.exe in standard locations, searching...")
        # Last resort - search for it
        for root, dirs, files in os.walk(build_prefix):
            for file in files:
                if file.lower() == 'clang.exe':
                    clang_exe = os.path.join(root, file)
                    print(f"Found clang at: {clang_exe}")
                    break
            if clang_exe:
                break

    if not clang_exe:
        print("Critical Error: Could not find clang.exe")
        return 1

    # Compile the source file
    cmd = [
        clang_exe,
        "-c", source_file,
        "-o", output_file,
        "--target=x86_64-w64-mingw32",
        "-O2"
    ]

    print(f"Running: {' '.join(cmd)}")
    try:
        process = subprocess.run(cmd, check=False, capture_output=True, text=True)
        print(f"Return code: {process.returncode}")
        print(f"Stdout: {process.stdout}")
        print(f"Stderr: {process.stderr}")

        if process.returncode != 0:
            print(f"Error: Failed to compile chkstk_ms implementation")
            return 1
    except Exception as e:
        print(f"Exception running compiler: {e}")
        return 1
    finally:
        # Clean up temporary directory
        try:
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
            print(f"Deleted temporary directory")
        except Exception as e:
            print(f"Error cleaning up temp dir: {e}")

    # Verify file was created
    if os.path.exists(output_file):
        print(f"Successfully created {output_file}")
        print(f"File size: {os.path.getsize(output_file)} bytes")
        return 0
    else:
        print(f"Error: Output file {output_file} was not created")
        return 1


if __name__ == "__main__":
    try:
        exit_code = main()
        print(f"Exiting with code: {exit_code}")
        sys.exit(exit_code)
    except Exception as e:
        print(f"Unhandled exception: {e}")
        sys.exit(1)
