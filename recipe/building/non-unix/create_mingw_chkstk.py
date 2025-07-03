#!/usr/bin/env python3
# create_mingw_chkstk.py - Creates the MinGW ___chkstk_ms object file
import os
import subprocess
import sys
import tempfile


def unix_to_win_path(unix_path):
    """Convert a Unix-style path to Windows format."""
    if unix_path.startswith('/') and (len(unix_path) > 2 and unix_path[2] == '/'):
        drive = unix_path[1].lower()
        return f"{drive}:{unix_path[2:]}".replace('/', '\\')

    # Default case: just replace slashes
    return unix_path.replace('/', '\\')


def create_mingw_chkstk_ms_obj(build_prefix):
    """Create a simple object file with the ___chkstk_ms symbol for MinGW."""
    # Define the target object file path
    obj_path = os.path.join(build_prefix, 'Library', 'lib', 'chkstk_mingw_ms.obj')
    obj_path_dir = os.path.dirname(obj_path)

    # If the object file already exists, just return its path
    if os.path.exists(obj_path):
        print(f"[SETUP] Found existing MinGW chkstk_ms.obj at {obj_path}", file=sys.stderr)
        return obj_path

    print(f"[SETUP] Creating MinGW chkstk_ms.obj at {obj_path}", file=sys.stderr)

    # Make sure the directory exists
    os.makedirs(obj_path_dir, exist_ok=True)

    # Create a temporary C file with the MinGW ___chkstk_ms implementation
    temp_c_file = os.path.join(tempfile.gettempdir(), "chkstk_mingw_ms.c")
    with open(temp_c_file, 'w') as f:
        f.write("""
// MinGW-specific implementation of ___chkstk_ms for Windows
// Based on mingw-w64 implementation

#include <stdint.h>

// MinGW ___chkstk_ms implementation
// This function allocates stack space in 4K chunks
__attribute__((used)) void ___chkstk_ms(void)
{
    // Get the stack pointer and requested allocation size from the registers
    register unsigned char *stack_ptr;
    register uintptr_t allocation_size;

    // Using inline assembly to get RAX (allocation size) and save necessary registers
    __asm__ __volatile__ (
        "movq %%rsp, %0\\n\\t"   // stack_ptr = RSP
        "movq %%rax, %1\\n\\t"   // allocation_size = RAX
        : "=r" (stack_ptr), "=r" (allocation_size)
        :
        // No clobber list needed as we're just reading registers
    );

    // Round allocation size to a page multiple if necessary
    uintptr_t page_size = 4096; // 4K page size
    uintptr_t rounded = allocation_size + (page_size - 1) & ~(page_size - 1);

    // Ensure we touch each page to trigger the guard page mechanism
    unsigned char *check_ptr = stack_ptr - rounded;
    unsigned char *guard_ptr = stack_ptr - page_size;

    while (check_ptr <= guard_ptr) {
        guard_ptr -= page_size;
        *guard_ptr = 0; // Touch the page to commit it
    }

    // No need to modify RAX as it already contains the original allocation size
    return;
}
        """)

    # Compile it to an object file
    try:
        clang_exe = os.path.join(build_prefix, 'Library', 'bin', 'clang.exe')
        result = subprocess.run(
            [clang_exe, "--target=x86_64-w64-mingw32", "-c", temp_c_file, "-o", obj_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False
        )
        if result.returncode == 0 and os.path.exists(obj_path):
            print(f"[SETUP] Successfully created MinGW chkstk_ms.obj with ___chkstk_ms symbol at: {obj_path}",
                  file=sys.stderr)
            return obj_path
        else:
            print(f"[SETUP] Failed to compile MinGW chkstk_ms.obj: {result.stderr.decode()}", file=sys.stderr)
            return None
    except Exception as e:
        print(f"[SETUP] Error compiling MinGW chkstk_ms.obj: {e}", file=sys.stderr)
        return None


if __name__ == "__main__":
    # Get build prefix from environment variables
    _build_prefix = os.environ.get('_BUILD_PREFIX', '')
    build_prefix_raw = os.environ.get('BUILD_PREFIX', '')

    # Determine which build prefix to use
    if _build_prefix:
        # Convert Unix path to Windows with single backslashes for os.path operations
        build_prefix = unix_to_win_path(_build_prefix)
        print(f"[SETUP] Using _BUILD_PREFIX (converted): {build_prefix}", file=sys.stderr)
    elif build_prefix_raw:
        build_prefix = build_prefix_raw
        print(f"[SETUP] Using BUILD_PREFIX: {build_prefix}", file=sys.stderr)
    else:
        print("[SETUP] Error: No build prefix environment variable found", file=sys.stderr)
        sys.exit(1)

    if obj_path := create_mingw_chkstk_ms_obj(build_prefix):
        print(f"[SETUP] Successfully created or found chkstk_mingw_ms.obj at {obj_path}", file=sys.stderr)
        sys.exit(0)
    else:
        print("[SETUP] Failed to create chkstk_mingw_ms.obj", file=sys.stderr)
        sys.exit(1)

