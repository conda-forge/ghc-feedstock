#!/usr/bin/env python

import os
import sys
import subprocess
import tempfile
import platform


def unix_to_win_path(unix_path):
    """Convert a Unix-style path to Windows format."""
    if unix_path.startswith('/') and (len(unix_path) > 2 and unix_path[2] == '/'):
        drive = unix_path[1].lower()
        return f"{drive}:{unix_path[2:]}".replace('/', '\\')
    
    # Default case: just replace slashes
    return unix_path.replace('/', '\\')


def format_path_for_response_file(path):
    """Format a path for inclusion in a response file with proper escaping."""
    if not path:
        return path

    # For paths with spaces, use quotes and double backslashes for response files
    if ' ' in path:
        # Double backslashes inside the path
        escaped_path = path.replace('\\', '\\\\')
        # Wrap in quotes
        return f'"{escaped_path}"'
    else:
        # For paths without spaces, just ensure proper escaping of backslashes
        return path.replace('\\', '\\\\')


def find_clang_version(build_prefix):
    """Find the installed clang version by looking at the directory structure."""
    clang_dir = os.path.join(build_prefix, 'Lib', 'clang')
    if os.path.exists(clang_dir):
        # Look for version directories (e.g., 18, 19, 20)
        version_dirs = [d for d in os.listdir(clang_dir) if os.path.isdir(os.path.join(clang_dir, d)) and d.isdigit()]
        if version_dirs:
            # Sort numerically and get the latest version
            return sorted(version_dirs, key=int)[-1]

    # Default to 19 if we can't find it
    print("[WRAPPER] Warning: Could not determine clang version, defaulting to 19", file=sys.stderr)
    return "19"


# Fix %BUILD_PREFIX% in search paths
def fix_build_prefix(path, build_prefix, build_prefix_escaped, for_response_file=False):
    """Replace %BUILD_PREFIX% with actual build prefix."""
    if not path:
        return path

    if '%BUILD_PREFIX%' in path:
        # Use properly escaped backslashes when needed
        replacement = build_prefix_escaped if for_response_file else build_prefix
        return path.replace('%BUILD_PREFIX%', replacement)

    return path


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

# Determine clang version
clang_version = find_clang_version(build_prefix)
print(f"[WRAPPER] Detected clang version: {clang_version}", file=sys.stderr)

# Get chkstk object paths from environment variables
chkstk_obj_path = os.environ.get('CHKSTK_OBJ')
if chkstk_obj_path:
    print(f"[WRAPPER] Using chkstk.obj from CHKSTK_OBJ env: {chkstk_obj_path}", file=sys.stderr)
    # Format for response file inclusion
    chkstk_obj_path_formatted = format_path_for_response_file(chkstk_obj_path)
    print(f"[WRAPPER] Using chkstk.obj at: {chkstk_obj_path_formatted}", file=sys.stderr)

# Get pre-created MinGW chkstk_ms.obj path
mingw_chkstk_ms_path = os.path.join(build_prefix, 'Library', 'lib', 'chkstk_mingw_ms.obj')
if os.path.exists(mingw_chkstk_ms_path):
    mingw_chkstk_ms_path_formatted = format_path_for_response_file(mingw_chkstk_ms_path)
    print(f"[WRAPPER] Using MinGW chkstk_ms.obj at: {mingw_chkstk_ms_path_formatted}", file=sys.stderr)
else:
    print(f"[WRAPPER] Warning: MinGW chkstk_ms.obj not found at {mingw_chkstk_ms_path}", file=sys.stderr)
    mingw_chkstk_ms_path = None

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
                mingw_chkstk_ms_added = False
                # Create a list to track all lines for later manipulation
                all_lines = []

                # First pass: read all lines and detect what's already there
                for line in in_file:
                    line = line.strip()
                    all_lines.append(line)

                    # Track if clang_rt.builtins-x86_64 is present
                    if ("clang_rt.builtins-x86_64" in line or "-lclang_rt.builtins-x86_64" in line):
                        clang_rt_added = True

                    # Check if chkstk.obj is already present
                    if 'chkstk.obj' in line:
                        chkstk_added = True
                        print(f"[WRAPPER] chkstk.obj already included in response file: {line}", file=sys.stderr)

                    # Check if our MinGW chkstk_ms.obj is already present
                    if 'chkstk_mingw_ms.obj' in line:
                        mingw_chkstk_ms_added = True
                        print(f"[WRAPPER] MinGW chkstk_ms.obj already included in response file: {line}", file=sys.stderr)

                # Make sure chkstk.obj is added BEFORE clang_rt.builtins to resolve symbols correctly
                # Find the index where clang_rt is added if present
                clang_rt_index = -1
                for i, line in enumerate(all_lines):
                    if "clang_rt.builtins-x86_64" in line:
                        clang_rt_index = i
                        break

                # Write out all lines, inserting objects at the right position if needed
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
                        line = fix_build_prefix(line, build_prefix, build_prefix_escaped, True)

                    # Handle library references to avoid duplicates
                    if line.startswith('-l'):
                        lib_name = line[2:]
                        if lib_name in processed_libs:
                            print(f"[WRAPPER] Skipping duplicate library reference: {line}", file=sys.stderr)
                            continue
                        processed_libs.add(lib_name)

                    # Handle path prefixes with -I or -L
                    if line.startswith('-I') or line.startswith('-L'):
                        prefix = line[:2]
                        path = line[2:]
                        # Replace %BUILD_PREFIX% in the path
                        if '%BUILD_PREFIX%' in path:
                            path = fix_build_prefix(path, build_prefix, build_prefix_escaped, True)
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

                    # If we're at the position just before clang_rt and we need to add our objects,
                    # insert them here to ensure proper symbol resolution order
                    if i == clang_rt_index - 1:
                        # Add MinGW chkstk_ms.obj first (before clang_rt) to provide ___chkstk_ms
                        if not mingw_chkstk_ms_added and mingw_chkstk_ms_path:
                            print(f"[WRAPPER] Adding MinGW chkstk_ms.obj before clang_rt: {mingw_chkstk_ms_path_formatted}", file=sys.stderr)
                            temp_file.write(f"{mingw_chkstk_ms_path_formatted}\n")
                            mingw_chkstk_ms_added = True

                        # Add regular chkstk.obj if needed
                        if not chkstk_added and chkstk_obj_path:
                            print(f"[WRAPPER] Adding chkstk.obj before clang_rt: {chkstk_obj_path_formatted}", file=sys.stderr)
                            temp_file.write(f"{chkstk_obj_path_formatted}\n")
                            chkstk_added = True

                    # Write the processed line
                    temp_file.write(f"{line}\n")

                # --- Add MinGW chkstk_ms.obj if not already present ---
                if not mingw_chkstk_ms_added and mingw_chkstk_ms_path:
                    print(f"[WRAPPER] Adding MinGW chkstk_ms.obj at end of response file: {mingw_chkstk_ms_path_formatted}", file=sys.stderr)
                    temp_file.write(f"{mingw_chkstk_ms_path_formatted}\n")
                    mingw_chkstk_ms_added = True

                # --- Add regular chkstk.obj if not already present ---
                if not chkstk_added and chkstk_obj_path:
                    print(f"[WRAPPER] Adding chkstk.obj at end of response file: {chkstk_obj_path_formatted}", file=sys.stderr)
                    temp_file.write(f"{chkstk_obj_path_formatted}\n")
                    chkstk_added = True

                # --- Ensure clang_rt.builtins-x86_64 is present ---
                if not clang_rt_added:
                    # Create proper Windows path with backslashes for the clang runtime
                    clang_rt_path = os.path.join(build_prefix, "Lib", "clang", clang_version, "lib", "windows", "clang_rt.builtins-x86_64.lib")
                    clang_rt_path_formatted = format_path_for_response_file(clang_rt_path)

                    # Create properly formatted lib directory path
                    lib_dir = os.path.join(build_prefix, "Lib", "clang", clang_version, "lib", "windows")
                    lib_dir_formatted = format_path_for_response_file(lib_dir)

                    print(f"[WRAPPER] Forcing clang runtime: {clang_rt_path}", file=sys.stderr)
                    temp_file.write(f"-L{lib_dir_formatted}\n")
                    temp_file.write(f"{clang_rt_path_formatted}\n")
                    temp_file.write("-lclang_rt.builtins-x86_64\n")

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
                arg = fix_build_prefix(arg, build_prefix, build_prefix_escaped, False)
            # Replace _BUILD_PREFIX in arguments if present
            if _build_prefix and _build_prefix in arg:
                arg = arg.replace(_build_prefix, build_prefix_escaped)
            filtered_args.append(arg)

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

final_cmd = [clang_exe] + filtered_args + runtime_flags

print(f"[WRAPPER] Final command: {' '.join(final_cmd)}", file=sys.stderr)

# Execute clang with the filtered arguments
exit_code = subprocess.call(final_cmd)
sys.exit(exit_code)
