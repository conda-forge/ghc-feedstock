#!/usr/bin/env python

import os
import sys
import subprocess
import tempfile


def main():
    """Create a custom MinGW chkstk_ms.obj file to provide ___chkstk_ms symbol."""

    print("Creating MinGW chkstk_ms.obj file...")

    # Get build environment variables
    build_prefix = os.environ.get('BUILD_PREFIX', os.environ.get('_BUILD_PREFIX', ''))
    if not build_prefix:
        print("Error: BUILD_PREFIX environment variable not set")
        return 1

    # Convert Unix path to Windows if needed
    if build_prefix.startswith('/'):
        if len(build_prefix) > 2 and build_prefix[2] == '/':
            drive = build_prefix[1].lower()
            build_prefix = f"{drive}:{build_prefix[2:]}".replace('/', '\\')
        else:
            build_prefix = build_prefix.replace('/', '\\')

    # Create output directory
    output_dir = os.path.join(build_prefix, 'Library', 'lib')
    os.makedirs(output_dir, exist_ok=True)

    output_file = os.path.join(output_dir, 'chkstk_mingw_ms.obj')

    # If output file already exists, we're done
    if os.path.exists(output_file):
        print(f"File already exists: {output_file}")
        return 0

    # Create a temporary file for the C source
    with tempfile.NamedTemporaryFile(suffix='.c', delete=False, mode='w') as f:
        source_file = f.name
        # Write C code for ___chkstk_ms implementation compatible with LLVM
        f.write("""
/* 
 * Custom implementation of __chkstk_ms for MinGW to work with clang
 * This is simplified and doesn't use naked functions 
 */
#include <stdint.h>

/* Get the page size for this platform */
#define PAGE_SIZE 4096

void ___chkstk_ms(void) {
    /* Simplified stack probing implementation */
    register unsigned char *probe;
    register uintptr_t stack_ptr;
    
    /* Get current stack pointer */
    __asm__("movq %%rsp, %0" : "=r" (stack_ptr));
    
    /* Get the stack size requested in bytes from rax */
    uintptr_t stack_size;
    __asm__("movq %%rax, %0" : "=r" (stack_size));
    
    /* If size < PAGE_SIZE, only probe once */
    if (stack_size <= PAGE_SIZE) {
        probe = (unsigned char*)(stack_ptr - stack_size);
        *probe = 0;  /* Probe the page */
        return;
    }
    
    /* For large allocations, probe every page */
    probe = (unsigned char*)(stack_ptr & ~(PAGE_SIZE - 1)); /* Round down to page boundary */
    while (stack_size > PAGE_SIZE) {
        probe -= PAGE_SIZE;
        *probe = 0;  /* Probe the page */
        stack_size -= PAGE_SIZE;
    }
    
    /* Probe the final page */
    probe -= stack_size;
    *probe = 0;  /* Probe the page */
}

/* Create an alias for __chkstk_ms which some code might use */
void __chkstk_ms(void) {
    ___chkstk_ms();  /* Just call the real implementation */
}
""")

    # Compile the source file
    clang_exe = os.path.join(build_prefix, 'Library', 'bin', 'clang.exe')
    if not os.path.exists(clang_exe):
        print(f"Error: Clang not found at {clang_exe}")
        return 1

    cmd = [
        clang_exe,
        "-c", source_file,
        "-o", output_file,
        "--target=x86_64-w64-mingw32",
        "-O2"
    ]

    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd)

    # Clean up source file
    os.unlink(source_file)

    if result.returncode != 0:
        print(f"Error: Failed to compile chkstk_ms implementation, returncode={result.returncode}")
        return 1

    print(f"Successfully created {output_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
