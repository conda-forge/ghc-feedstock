# clang-mingw-wrapper.py
import sys
import os
import tempfile
import subprocess
import glob
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
                return path

    return None


print("[WRAPPER] Starting clang-mingw-wrapper", file=sys.stderr)
print("[WRAPPER] Arguments:", sys.argv[1:], file=sys.stderr)

filtered_args = []
build_prefix = os.environ.get('BUILD_PREFIX', '')

# Prepare search paths for libraries
# Use forward slashes for consistency
lib_search_paths = [
    os.path.join(build_prefix, 'Library', 'mingw-w64', 'lib').replace('\\', '/'),
    os.path.join(build_prefix, 'Library', 'lib').replace('\\', '/'),
    os.path.join(build_prefix, 'lib').replace('\\', '/')
]
print(f"[WRAPPER] Library search paths: {lib_search_paths}", file=sys.stderr)

# Process all arguments
for arg in sys.argv[1:]:
    # Handle response files (starting with @)
    if arg.startswith('@'):
        resp_file = arg[1:]
        print(f"[WRAPPER] Found response file: {resp_file}", file=sys.stderr)

        # Create a temporary filtered response file
        fd, temp_resp = tempfile.mkstemp(prefix='filtered_rsp_', suffix='.txt')
        print(f"[WRAPPER] Creating filtered response file: {temp_resp}", file=sys.stderr)

        if os.path.exists(resp_file):
            with open(resp_file, 'r') as in_file, open(temp_resp, 'w') as temp_file:
                # Extract all -L paths to add to our search paths
                content = in_file.read()
                l_path_matches = re.findall(r'-L([^\s]+)', content)
                for path in l_path_matches:
                    if os.path.exists(path) and path not in lib_search_paths and 'bootstrap-ghc' not in path:
                        lib_search_paths.append(path.replace('\\', '/'))

                # Reset file pointer to beginning
                in_file.seek(0)

                # Find all -l flags to resolve their paths
                lib_flags = re.findall(r'-l([^\s]+)', content)
                lib_paths = {}  # Store resolved paths

                # Find paths for all libraries
                for lib in lib_flags:
                    if lib == 'clang_rt.builtins-x86_64':  # Skip clang runtime, we'll handle it specially
                        continue

                    lib_path = find_library_path(lib, lib_search_paths)
                    if lib_path:
                        print(f"[WRAPPER] Found library '{lib}' at {lib_path}", file=sys.stderr)
                        lib_paths[lib] = lib_path
                    else:
                        print(f"[WRAPPER] Could not find library '{lib}' in search paths", file=sys.stderr)

                # Reset file pointer to beginning
                in_file.seek(0)

                # Process the response file content
                for line in in_file:
                    line = line.strip()

                    # Skip bootstrap-ghc mingw paths
                    if (line.startswith('-I') or line.startswith('-L')) and \
                       'bootstrap-ghc' in line and '/mingw/' in line:
                        print(f"[WRAPPER] Skipping line from response file: {line}", file=sys.stderr)
                        continue

                    # Replace -l flags with actual file paths when we found them
                    if line.startswith('-l'):
                        lib = line[2:]
                        if lib in lib_paths:
                            # Replace with the actual library path
                            temp_file.write(f"{lib_paths[lib]}\n")
                            continue

                    # Keep all other lines
                    temp_file.write(f"{line}\n")

                # Add the path to clang_rt.builtins-x86_64.lib with dynamic version detection
                clang_lib_base = os.path.join(build_prefix, 'Lib', 'clang')
                if os.path.exists(clang_lib_base):
                    try:
                        version_dirs = [d for d in os.listdir(clang_lib_base)
                                      if os.path.isdir(os.path.join(clang_lib_base, d))]
                        if version_dirs:
                            latest_version = sorted(version_dirs, key=lambda v:
                                                  [int(x) if x.isdigit() else 0 for x in v.split('.')])[-1]
                            clang_rt_path = os.path.join(clang_lib_base, latest_version, 'lib', 'windows')
                            print(f"[WRAPPER] Using clang runtime from: {clang_rt_path}", file=sys.stderr)
                            if os.path.exists(clang_rt_path):
                                # Add path to search paths
                                lib_search_paths.append(clang_rt_path.replace('\\', '/'))
                                temp_file.write(f"-L{clang_rt_path}\n")
                                temp_file.write("-lclang_rt.builtins-x86_64\n")

                                # Also try direct file path as fallback
                                rt_lib_path = os.path.join(clang_rt_path, "clang_rt.builtins-x86_64.lib")
                                if os.path.exists(rt_lib_path):
                                    temp_file.write(f"{rt_lib_path}\n")
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
            filtered_args.append(arg)

# Add conda mingw paths
print("[WRAPPER] Adding conda mingw paths", file=sys.stderr)
filtered_args.extend([
    f"-I{os.path.join(build_prefix, 'Library', 'mingw-w64', 'include')}".replace('\\', '/'),
    f"-L{os.path.join(build_prefix, 'Library', 'mingw-w64', 'lib')}".replace('\\', '/')
])

# Prepare final command
clang_exe = os.path.join(build_prefix, 'Library', 'bin', 'clang.exe').replace('\\', '/')
final_cmd = [clang_exe] + filtered_args

print(f"[WRAPPER] Final command: {' '.join(final_cmd)}", file=sys.stderr)

# Execute clang with the filtered arguments
exit_code = subprocess.call(final_cmd)
sys.exit(exit_code)