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
                print(f"[WRAPPER] Found library '{lib_name}' at {path}", file=sys.stderr)
                return path
    
    # If not found, try recursive search in BUILD_PREFIX
    build_prefix = os.environ.get('BUILD_PREFIX', '')
    if build_prefix and os.path.exists(build_prefix):
        for root, dirs, files in os.walk(build_prefix):
            for pattern in patterns:
                if pattern in files:
                    path = os.path.join(root, pattern)
                    print(f"[WRAPPER] Found library '{lib_name}' at {path} through recursive search", file=sys.stderr)
                    # Add this directory to search paths for future searches
                    search_dirs.append(root)
                    return path
    
    print(f"[WRAPPER] Could not find library '{lib_name}' in any search paths", file=sys.stderr)
    return None


def expand_env_vars(path):
    """Expand environment variables in a path string."""
    # Handle %VAR% format
    if '%' in path:
        for env_var, value in os.environ.items():
            placeholder = f"%{env_var}%"
            if placeholder in path:
                path = path.replace(placeholder, value)

    # Handle $VAR format
    import re
    path = re.sub(r'\$([a-zA-Z0-9_]+)', lambda m: os.environ.get(m.group(1), m.group(0)), path)

    return path


print("[WRAPPER] Starting clang-mingw-wrapper", file=sys.stderr)
print("[WRAPPER] Arguments:", sys.argv[1:], file=sys.stderr)

filtered_args = []
build_prefix = os.environ.get('BUILD_PREFIX', '')

# Prepare search paths for libraries
# Add more potential library locations
lib_search_paths = [
    os.path.join(build_prefix, 'Library', 'mingw-w64', 'lib'),
    os.path.join(build_prefix, 'Library', 'mingw-w64', 'x86_64-w64-mingw32', 'lib'),
    os.path.join(build_prefix, 'Library', 'lib'),
    os.path.join(build_prefix, 'lib'),
    os.path.join(build_prefix, 'Library', 'usr', 'lib'),
    os.path.join(build_prefix, 'mingw-w64', 'lib'),  # Additional potential location
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
            with (open(resp_file, 'r') as in_file, open(temp_resp, 'w') as temp_file):
                # Extract all -L paths to add to our search paths
                content = in_file.read()
                l_path_matches = re.findall(r'-L([^\s]+)', content)
                for path in l_path_matches:
                    path = path.replace('\\\\', '\\')  # Fix double backslashes in paths
                    path = expand_env_vars(path).replace('\\', '\\\\')  # Expand environment variables
                    if os.path.exists(path) and path not in lib_search_paths and 'bootstrap-ghc' not in path:
                        lib_search_paths.append(path)

                # Reset file pointer to beginning
                in_file.seek(0)

                # Track libraries we've already processed to avoid duplicates
                processed_libs = set()

                # Process the response file content
                filtered_lines = []
                for line in in_file:
                    line = line.strip()

                    # Skip bootstrap-ghc mingw paths
                    if (line.startswith('-I') or line.startswith('-L')) and \
                       'bootstrap-ghc' in line and '/mingw/' in line:
                        print(f"[WRAPPER] Skipping line from response file: {line}", file=sys.stderr)
                        continue

                    # Handle library references to avoid duplicates
                    if line.startswith('-l'):
                        lib_name = line[2:]
                        if lib_name in processed_libs:
                            print(f"[WRAPPER] Skipping duplicate library reference: {line}", file=sys.stderr)
                            continue

                        processed_libs.add(lib_name)

                        # For specific problematic libraries, try to find them directly
                        if lib_name in ['mingw32', 'mingwex', 'm', 'pthread']:
                            if lib_path := find_library_path(
                                lib_name, lib_search_paths
                            ):
                                # Use quotes around the path to handle spaces
                                filtered_lines.append(f'"{lib_path}"')
                                continue

                    # Handle paths that might contain environment variables
                    if line.startswith('-I') or line.startswith('-L'):
                        prefix = line[:2]
                        path = line[2:]
                        path = expand_env_vars(path)
                        filtered_lines.append(f"{prefix}{path}")
                        continue

                    # Handle direct file paths with environment variables
                    if '%' in line or '$' in line:
                        expanded_line = expand_env_vars(line)
                        # Use quotes to handle spaces in paths
                        if ' ' in expanded_line:
                            filtered_lines.append(f'"{expanded_line}"')
                        else:
                            filtered_lines.append(expanded_line)
                        continue

                    # Keep all other lines
                    filtered_lines.append(line)

                # Add the path to clang_rt.builtins-x86_64.lib with dynamic version detection
                clang_lib_base = os.path.join(build_prefix, 'Lib', 'clang')
                if os.path.exists(clang_lib_base):
                    try:
                        if version_dirs := [
                            d
                            for d in os.listdir(clang_lib_base)
                            if os.path.isdir(os.path.join(clang_lib_base, d))
                        ]:
                            latest_version = sorted(version_dirs, key=lambda v: 
                                                   [int(x) if x.isdigit() else 0 for x in v.split('.')])[-1]
                            clang_rt_path = os.path.join(clang_lib_base, latest_version, 'lib', 'windows')
                            print(f"[WRAPPER] Using clang runtime from: {clang_rt_path}", file=sys.stderr)
                            if os.path.exists(clang_rt_path):
                                # Add path to search paths
                                if clang_rt_path not in lib_search_paths:
                                    lib_search_paths.append(clang_rt_path.replace('\\', '\\\\'))

                                # Add -L path if not already present
                                l_path_line = f"-L{clang_rt_path}"
                                if l_path_line not in filtered_lines:
                                    filtered_lines.append(l_path_line.replace('\\', '\\\\'))

                                # Add clang runtime library if not already present
                                if "clang_rt.builtins-x86_64" not in processed_libs:
                                    filtered_lines.append("-lclang_rt.builtins-x86_64")
                                    processed_libs.add("clang_rt.builtins-x86_64")
                    except (OSError, IndexError) as e:
                        print(f"[WRAPPER] Error finding clang runtime: {e}", file=sys.stderr)

                # Write the filtered lines to the temporary response file
                for line in filtered_lines:
                    temp_file.write(f"{line}\n")

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

# Prepare final command
clang_exe = os.path.join(build_prefix, 'Library', 'bin', 'clang.exe')
final_cmd = [clang_exe] + filtered_args

print(f"[WRAPPER] Final command: {' '.join(final_cmd)}", file=sys.stderr)

# Execute clang with the filtered arguments
exit_code = subprocess.call(final_cmd)
sys.exit(exit_code)