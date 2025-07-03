# clang-mingw-wrapper.py
import os
import subprocess
import sys
import tempfile
import re


def find_library_path(lib_name, search_dirs):
    """Find a library in the given search directories."""
    # Try different library file patterns
    patterns = [
        f"lib{lib_name}.a",     # GCC-style static lib
        f"{lib_name}.lib",      # MSVC-style static lib
        f"lib{lib_name}.dll.a", # GCC-style import lib
        f"{lib_name}.dll.lib",  # MSVC-style import lib
    ]
    
    for directory in search_dirs:
        if not os.path.exists(directory):
            continue
        
        for pattern in patterns:
            path = os.path.join(directory, pattern)
            if os.path.exists(path):
                # Convert backslashes to double backslashes for clang
                path_escaped = path.replace('\\', '\\\\')
                print(f"[WRAPPER] Found library '{lib_name}' at {path_escaped}", file=sys.stderr)
                return path_escaped
    
    print(f"[WRAPPER] Could not find library '{lib_name}' in any search paths", file=sys.stderr)
    return None


def check_symbol_in_lib(lib_path, symbol):
    """Check if a symbol exists in a .lib file using llvm-nm."""
    try:
        result = subprocess.run(
            ["llvm-nm", lib_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            encoding="utf-8",
            check=True
        )
        for line in result.stdout.splitlines():
            if symbol in line:
                print(f"[WRAPPER] Symbol '{symbol}' found in {lib_path}", file=sys.stderr)
                return True
        print(f"[WRAPPER] Symbol '{symbol}' NOT found in {lib_path}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"[WRAPPER] Error running llvm-nm on {lib_path}: {e}", file=sys.stderr)
        return False


def unix_to_win_path(unix_path):
    """Convert a Unix-style path to Windows format."""
    if unix_path.startswith('/') and (len(unix_path) > 2 and unix_path[2] == '/'):
        drive = unix_path[1].lower()
        return f"{drive}:{unix_path[2:]}".replace('/', '\\')
    
    # Default case: just replace slashes
    return unix_path.replace('/', '\\')


def ensure_chkstk_ms_object(build_prefix):
    """Create or find a chkstk_ms object file containing the ___chkstk_ms symbol."""
    # Define the target object file path
    obj_path = os.path.join(build_prefix, 'Library', 'lib', 'chkstk_ms.obj')
    obj_path_dir = os.path.dirname(obj_path)

    # If the object file already exists, just return its path
    if os.path.exists(obj_path):
        print(f"[WRAPPER] Found existing chkstk_ms.obj at {obj_path}", file=sys.stderr)
        return obj_path

    # Make sure the directory exists
    os.makedirs(obj_path_dir, exist_ok=True)

    # Create a temporary C file with proper ___chkstk_ms implementation
    temp_c_file = os.path.join(tempfile.gettempdir(), "chkstk_ms.c")
    with open(temp_c_file, 'w') as f:
        f.write("""
// Implementation of ___chkstk_ms for Windows x64
#ifdef _WIN64
__attribute__((naked))
void ___chkstk_ms(void)
{
    __asm__(
        "push   %%rcx                  \\n\\t"
        "push   %%rax                  \\n\\t"
        "cmp    $0x1000, %%rax         \\n\\t"
        "lea    24(%%rsp), %%rcx       \\n\\t"
        "jb     1f                     \\n\\t"
    "0:                                \\n\\t"
        "sub    $0x1000, %%rcx         \\n\\t"
        "test   %%rcx, (%%rcx)         \\n\\t"
        "sub    $0x1000, %%rax         \\n\\t"
        "cmp    $0x1000, %%rax         \\n\\t"
        "ja     0b                     \\n\\t"
    "1:                                \\n\\t"
        "sub    %%rax, %%rcx           \\n\\t"
        "test   %%rcx, (%%rcx)         \\n\\t"
        "pop    %%rax                  \\n\\t"
        "pop    %%rcx                  \\n\\t"
        "ret                           \\n\\t"
    );
}
#else
// 32-bit version if needed
void ___chkstk_ms(void)
{
    // Simplified implementation for 32-bit
    // Not implemented here as we're targeting 64-bit
}
#endif
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
            print(f"[WRAPPER] Created chkstk_ms.obj with ___chkstk_ms symbol at: {obj_path}", file=sys.stderr)
            return obj_path
        else:
            print(f"[WRAPPER] Failed to compile chkstk_ms.obj: {result.stderr.decode()}", file=sys.stderr)
            return None
    except Exception as e:
        print(f"[WRAPPER] Error compiling chkstk_ms.obj: {e}", file=sys.stderr)
        return None

print("[WRAPPER] Starting clang-mingw-wrapper", file=sys.stderr)
print("[WRAPPER] Arguments:", sys.argv[1:], file=sys.stderr)

# Get build prefix from environment variables
_build_prefix = os.environ.get('_BUILD_PREFIX', '')
build_prefix_raw = os.environ.get('BUILD_PREFIX', '')

# If _BUILD_PREFIX is available, convert from Unix to Windows path format
if _build_prefix:
    # Convert Unix path to Windows with single backslashes for os.path operations
    build_prefix = unix_to_win_path(_build_prefix)
    # Create escaped version with double backslashes for string replacement in response file
    build_prefix_escaped = build_prefix.replace('\\', '\\\\')
    print(f"[WRAPPER] Using _BUILD_PREFIX (converted): {build_prefix}", file=sys.stderr)
    print(f"[WRAPPER] Escaped for response file: {build_prefix_escaped}", file=sys.stderr)
elif build_prefix_raw:
    build_prefix = build_prefix_raw
    build_prefix_escaped = build_prefix.replace('\\', '\\\\')
    print(f"[WRAPPER] Using BUILD_PREFIX: {build_prefix}", file=sys.stderr)
else:
    print("[WRAPPER] Error: No build prefix environment variable found", file=sys.stderr)
    sys.exit(1)

# Fix %BUILD_PREFIX% in search paths
def fix_build_prefix(path, for_response_file=False):
    """
    Replace %BUILD_PREFIX% with actual build prefix.

    Args:
        path: The path string to process
        for_response_file: Whether the path is intended for a response file (needs double backslashes)
    """
    if not path:
        return path

    if '%BUILD_PREFIX%' in path:
        # Use properly escaped backslashes when needed
        replacement = build_prefix_escaped if for_response_file else build_prefix
        return path.replace('%BUILD_PREFIX%', replacement)

    return path

# Helper to ensure paths have correct format
def format_path_for_response_file(path):
    """Format a path for inclusion in a response file with proper escaping."""
    if not path:
        return path

    # Replace %BUILD_PREFIX% with properly escaped build prefix
    if '%BUILD_PREFIX%' in path:
        path = path.replace('%BUILD_PREFIX%', build_prefix_escaped)

    # Ensure backslashes are properly escaped for response files
    if '\\' in path and '\\\\' not in path:
        path = path.replace('\\', '\\\\')

    return path

# Library search paths - single backslashes for os.path operations
lib_search_paths = [
    os.path.join(build_prefix, 'Library', 'x86_64-w64-mingw32', 'sysroot', 'usr', 'lib'),
    # Add more potential locations for MinGW libs
    os.path.join(build_prefix, 'Library', 'lib'),
    os.path.join(build_prefix, 'lib'),
    os.path.join(build_prefix, 'Library', 'mingw-w64', 'lib64'),
    os.path.join(build_prefix, 'mingw64', 'lib'),
    os.path.join(build_prefix, 'Library', 'mingw-w64', 'lib'),
    os.path.join(build_prefix, 'Library', 'x86_64-w64-mingw32', 'lib'),
]

# Create or find the chkstk_ms.obj file
chkstk_obj_path = ensure_chkstk_ms_object(build_prefix)

# Format the chkstk_ms.obj path for response file inclusion
if chkstk_obj_path:
    chkstk_obj_path_formatted = format_path_for_response_file(chkstk_obj_path)
    print(f"[WRAPPER] Using chkstk_ms.obj at: {chkstk_obj_path_formatted}", file=sys.stderr)

filtered_args = []

# Process all arguments
for arg in sys.argv[1:]:
    # Handle response files (starting with @)
    if arg.startswith('@'):
        resp_file = arg[1:]
        print(f"[WRAPPER] Found response file: {resp_file}", file=sys.stderr)

        # Create a temporary filtered response file
        fd, temp_resp = tempfile.mkstemp(prefix='filtered_rsp_', suffix='.txt')
        os.close(fd)
        print(f"[WRAPPER] Creating filtered response file: {temp_resp}", file=sys.stderr)

        if os.path.exists(resp_file):
            with open(resp_file, 'r') as in_file, open(temp_resp, 'w') as temp_file:
                processed_libs = set()
                clang_rt_added = False
                chkstk_added = False
                # Create a list to track all lines for later manipulation
                all_lines = []

                # First pass: read all lines and detect what's already there
                for line in in_file:
                    line = line.strip()
                    all_lines.append(line)

                    # Track if clang_rt.builtins-x86_64 is present
                    if ("clang_rt.builtins-x86_64" in line or "-lclang_rt.builtins-x86_64" in line):
                        clang_rt_added = True

                    # Check if chkstk_ms.obj is already present
                    if 'chkstk_ms.obj' in line:
                        chkstk_added = True
                        print(f"[WRAPPER] chkstk_ms.obj already included in response file: {line}", file=sys.stderr)

                # Make sure chkstk_ms.obj is added BEFORE clang_rt.builtins to resolve symbols correctly
                # Find the index where clang_rt is added if present
                clang_rt_index = -1
                for i, line in enumerate(all_lines):
                    if "clang_rt.builtins-x86_64" in line:
                        clang_rt_index = i
                        break

                # Write out all lines, inserting chkstk_ms.obj at the right position if needed
                for i, line in enumerate(all_lines):
                    # Skip bootstrap-ghc mingw paths
                    if (line.startswith('-I') or line.startswith('-L')) and \
                       'bootstrap-ghc' in line and 'mingw' in line:
                        print(f"[WRAPPER] Skipping line from response file: {line}", file=sys.stderr)
                        continue

                    # Skip linking with the MSVC runtime library
                    if line.endswith('libcmt.lib') or 'libcmt.lib' in line:
                        print(f"[WRAPPER] Skipping MSVC runtime library: {line}", file=sys.stderr)
                        continue

                    # Fix %BUILD_PREFIX% in the line if present
                    if '%BUILD_PREFIX%' in line:
                        line = line.replace('%BUILD_PREFIX%', build_prefix)

                    # Handle library references to avoid duplicates
                    if line.startswith('-l'):
                        lib_name = line[2:]
                        if lib_name in processed_libs:
                            print(f"[WRAPPER] Skipping duplicate library reference: {line}", file=sys.stderr)
                            continue
                        processed_libs.add(lib_name)

                        # For specific problematic libraries, try to find them directly
                        if lib_name in ['mingw32', 'mingwex', 'm', 'pthread']:
                            lib_path = find_library_path(lib_name, lib_search_paths)
                            if lib_path:
                                # Use non-escaped path here - the library path from find_library_path already has escaped backslashes
                                temp_file.write(f"{lib_path}\n")
                                continue

                    # Replace %BUILD_PREFIX% with actual escaped path
                    if '%BUILD_PREFIX%' in line:
                        line = line.replace('%BUILD_PREFIX%', build_prefix_escaped)

                    # Handle path prefixes with -I or -L
                    if line.startswith('-I') or line.startswith('-L'):
                        prefix = line[:2]
                        path = line[2:]
                        # Replace %BUILD_PREFIX% in the path
                        if '%BUILD_PREFIX%' in path:
                            path = path.replace('%BUILD_PREFIX%', build_prefix_escaped)
                        # Handle _BUILD_PREFIX if present
                        if _build_prefix and _build_prefix in path:
                            path = path.replace(_build_prefix, build_prefix_escaped)
                        # Make sure backslashes are escaped
                        if '\\\\' not in path:  # Only escape once
                            path = path.replace('\\', '\\\\')
                        line = f"{prefix}{path}"

                    # Handle _BUILD_PREFIX if it exists in the line
                    if _build_prefix and _build_prefix in line:
                        line = line.replace(_build_prefix, build_prefix_escaped)

                    # If we're at the position just before clang_rt and we need to add chkstk_ms.obj,
                    # insert it here to ensure proper symbol resolution order
                    if i == clang_rt_index - 1:
                        # Add chkstk_ms.obj first (before clang_rt)
                        if not chkstk_added and chkstk_obj_path:
                            print(f"[WRAPPER] Adding chkstk_ms.obj before clang_rt: {chkstk_obj_path_formatted}", file=sys.stderr)
                            temp_file.write(f"{chkstk_obj_path_formatted}\n")
                            chkstk_added = True

                    # Write the processed line
                    temp_file.write(f"{line}\n")

                # --- Add chkstk_ms.obj if not already present ---
                if not chkstk_added and chkstk_obj_path:
                    print(f"[WRAPPER] Adding chkstk_ms.obj at end of response file: {chkstk_obj_path_formatted}", file=sys.stderr)
                    temp_file.write(f"{chkstk_obj_path_formatted}\n")
                    chkstk_added = True

                # --- Ensure clang_rt.builtins-x86_64 is present ---
                if not clang_rt_added:
                    clang_lib_base = os.path.join(build_prefix, 'Lib', 'clang')
                    if os.path.exists(clang_lib_base):
                        try:
                            version_dirs = [d for d in os.listdir(clang_lib_base) 
                                            if os.path.isdir(os.path.join(clang_lib_base, d))]
                            if version_dirs:
                                latest_version = sorted(version_dirs)[-1]
                                clang_rt_path = os.path.join(clang_lib_base, latest_version, 'lib', 'windows')
                                if os.path.exists(clang_rt_path):
                                    clang_rt_lib = os.path.join(clang_rt_path, 'clang_rt.builtins-x86_64.lib')
                                    # Fix any %BUILD_PREFIX% in the path
                                    clang_rt_lib = fix_build_prefix(clang_rt_lib)
                                    clang_rt_path_escaped = clang_rt_path.replace('\\', '\\\\')
                                    clang_rt_lib_escaped = clang_rt_lib.replace('\\', '\\\\')
                                    print(f"[WRAPPER] Forcing clang runtime: {clang_rt_lib_escaped}", file=sys.stderr)
                                    temp_file.write(f"-L{clang_rt_path_escaped}\n")
                                    temp_file.write(f"{clang_rt_lib_escaped}\n")
                                    temp_file.write("-lclang_rt.builtins-x86_64\n")

                                    # Check if clang_rt has the required symbol
                                    check_symbol_in_lib(clang_rt_lib, "___chkstk_ms")
                        except (OSError, IndexError) as e:
                            print(f"[WRAPPER] Error finding clang runtime: {e}", file=sys.stderr)

                # Debug: Print content of filtered response file
                print(f"[WRAPPER] Content of filtered response file {temp_resp}:", file=sys.stderr)
                with open(temp_resp, 'r') as f:
                    for i, line in enumerate(f):
                        print(f"[WRAPPER] Line {i+1}: {line.strip()}", file=sys.stderr)

            filtered_args.append(f"@{temp_resp}")
        else:
            print(f"[WRAPPER] Warning: Response file {resp_file} not found", file=sys.stderr)
            filtered_args.append(arg)
    else:
        # Handle normal arguments
        skip = False
        # Only skip arguments that contain both bootstrap-ghc AND mingw
        if (arg.startswith('-I') or arg.startswith('-L')) and \
           'bootstrap-ghc' in arg and 'mingw' in arg:
            skip = True
            print(f"[WRAPPER] Skipping argument: {arg}", file=sys.stderr)

        if not skip:
            # Replace %BUILD_PREFIX% in arguments if present
            if '%BUILD_PREFIX%' in arg:
                arg = arg.replace('%BUILD_PREFIX%', build_prefix_escaped)
            # Replace _BUILD_PREFIX in arguments if present
            if _build_prefix and _build_prefix in arg:
                arg = arg.replace(_build_prefix, build_prefix_escaped)
            filtered_args.append(arg)

# Add conda mingw paths with escaped backslashes
mingw_include = os.path.join(build_prefix, 'Library', 'mingw-w64', 'include').replace('\\', '\\\\')
mingw_lib = os.path.join(build_prefix, 'Library', 'mingw-w64', 'lib').replace('\\', '\\\\')
if os.path.exists(mingw_include.replace('\\\\', '\\')):
    filtered_args.append(f"-I{mingw_include}")
if os.path.exists(mingw_lib.replace('\\\\', '\\')):
    filtered_args.append(f"-L{mingw_lib}")

# Prepare final command with escaped backslashes for file paths but not for the exe itself
clang_exe = os.path.join(build_prefix, 'Library', 'bin', 'clang.exe')

# Add flags to explicitly control runtime libraries and avoid MSVC CRT
runtime_flags = [
    # Use MinGW mode for clang to avoid automatic inclusion of MSVC runtime
    '--target=x86_64-w64-mingw32',
    '-fuse-ld=lld',
    # Pass linker options directly rather than with -Wl prefix
    # Handle duplicate symbols
    '-Xlinker', '/FORCE:MULTIPLE',
    # Add specific libraries needed
    '-lmsvcrt',  # MinGW's msvcrt implementation
    '-lucrt'     # Universal CRT
]

# If we haven't added the chkstk_ms.obj file, add it directly to the command
if chkstk_obj_path and not locals().get('chkstk_added', False):
    chkstk_obj_path_cmd = fix_build_prefix(chkstk_obj_path, for_response_file=False)
    print(f"[WRAPPER] Adding chkstk_ms.obj directly to command line: {chkstk_obj_path_cmd}", file=sys.stderr)
    filtered_args.append(chkstk_obj_path_cmd)

final_cmd = [clang_exe] + filtered_args + runtime_flags

print(f"[WRAPPER] Final command: {' '.join(final_cmd)}", file=sys.stderr)

# Execute clang with the filtered arguments
exit_code = subprocess.call(final_cmd)
sys.exit(exit_code)
