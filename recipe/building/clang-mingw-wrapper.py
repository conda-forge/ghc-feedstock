# clang-mingw-wrapper.py
import os
import subprocess
import sys
import tempfile


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


def find_gcc_library(search_dirs):
    """Find GCC library in various formats (static or import library for DLL)."""
    # Try static libgcc.a first
    static_gcc = find_library_path('gcc', search_dirs)
    if static_gcc:
        print(f"[WRAPPER] Found static GCC library: {static_gcc}", file=sys.stderr)
        return static_gcc, False  # Found static library

    # Try import libraries for DLL - with more variations
    for lib_name in ['gcc_s_seh', 'gcc_s_dw2', 'gcc_s', 'gcc']:
        import_lib = find_library_path(lib_name, search_dirs)
        if import_lib:
            print(f"[WRAPPER] Found GCC import library: {import_lib}", file=sys.stderr)
            return import_lib, True  # Found import library

    # If we can't find the import library directly, try to find it based on the DLL path
    gcc_dll = find_gcc_dll(search_dirs)
    if gcc_dll:
        dll_dir = os.path.dirname(gcc_dll)
        dll_basename = os.path.basename(gcc_dll)
        # Extract the base name without extension
        base_name = os.path.splitext(dll_basename)[0]
        if base_name.startswith('lib'):
            base_name = base_name[3:]  # Remove 'lib' prefix
        # Remove version suffix if present (e.g., _seh-1)
        base_name = base_name.split('-')[0]

        # Try to find the import library in the same directory or lib directory
        potential_import_names = [
            f"lib{base_name}.a",
            f"lib{base_name}.dll.a",
            f"{base_name}.lib"
        ]

        for name in potential_import_names:
            for dir_path in [dll_dir, os.path.join(os.path.dirname(dll_dir), 'lib')]:
                if os.path.exists(dir_path):
                    lib_path = os.path.join(dir_path, name)
                    if os.path.exists(lib_path):
                        lib_path_escaped = lib_path.replace('\\', '\\\\')
                        print(f"[WRAPPER] Found GCC import library based on DLL: {lib_path_escaped}", file=sys.stderr)
                        return lib_path_escaped, True

    return None, False


def find_gcc_dll(search_dirs):
    """Find GCC DLL in the given search directories."""
    dll_patterns = [
        'libgcc_s_seh-1.dll',
        'libgcc_s_dw2-1.dll',
        'libgcc_s-1.dll',
        'libgcc_s.dll'
    ]

    for directory in search_dirs:
        if not os.path.exists(directory):
            continue

        for pattern in dll_patterns:
            path = os.path.join(directory, pattern)
            if os.path.exists(path):
                print(f"[WRAPPER] Found GCC DLL at {path}", file=sys.stderr)
                return path

    return None


def create_import_lib(dll_path, output_dir=None):
    """Create an import library for the given DLL using llvm-dlltool."""
    if not dll_path or not os.path.exists(dll_path):
        return None

    # Ensure output directory exists
    if not output_dir:
        output_dir = os.path.dirname(dll_path)

    # Create import library name
    dll_name = os.path.basename(dll_path)
    base_name = os.path.splitext(dll_name)[0]
    if base_name.startswith('lib'):
        base_name = base_name[3:]  # Remove 'lib' prefix

    # Remove version suffix if present
    base_name = base_name.split('-')[0]
    import_lib_name = f"lib{base_name}.dll.a"
    import_lib_path = os.path.join(output_dir, import_lib_name)

    # Skip if already exists
    if os.path.exists(import_lib_path):
        print(f"[WRAPPER] Import library already exists: {import_lib_path}", file=sys.stderr)
        return import_lib_path

    # Try to create import library using llvm-dlltool
    try:
        print(f"[WRAPPER] Attempting to create import library for {dll_path}", file=sys.stderr)
        result = subprocess.run(
            ["llvm-dlltool", "-d", dll_path, "-l", import_lib_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False
        )

        if result.returncode == 0 and os.path.exists(import_lib_path):
            print(f"[WRAPPER] Successfully created import library: {import_lib_path}", file=sys.stderr)
            return import_lib_path
        else:
            print(f"[WRAPPER] Failed to create import library: {result.stderr.decode()}", file=sys.stderr)
    except Exception as e:
        print(f"[WRAPPER] Error creating import library: {e}", file=sys.stderr)

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
def fix_build_prefix(path):
    """Replace %BUILD_PREFIX% with actual build prefix."""
    if '%BUILD_PREFIX%' in path:
        return path.replace('%BUILD_PREFIX%', build_prefix)
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
    os.path.join(build_prefix, 'Library', 'bin'),  # Sometimes import libs are next to DLLs
]

# Add LIBRARY_BIN to search paths for DLLs
bin_search_paths = lib_search_paths.copy()
# Try to construct LIBRARY_BIN path
potential_bin = os.path.join(build_prefix, 'Library', 'bin')
if os.path.exists(potential_bin):
    bin_search_paths.insert(0, potential_bin)

# Add path with mingw DLLs to search paths
mingw_bin = os.path.join(build_prefix, 'Library', 'mingw-w64', 'bin')
if os.path.exists(mingw_bin):
    bin_search_paths.insert(0, mingw_bin)

print(f"[WRAPPER] DLL search paths: {list(bin_search_paths)}", file=sys.stderr)

# Find GCC DLL first
gcc_dll_path = find_gcc_dll(bin_search_paths)
if gcc_dll_path:
    # Fix %BUILD_PREFIX% if present
    gcc_dll_path = fix_build_prefix(gcc_dll_path)
    gcc_dll_dir = os.path.dirname(gcc_dll_path)
    # Add to PATH if not already there
    if gcc_dll_dir not in os.environ.get('PATH', '').split(os.pathsep):
        os.environ['PATH'] = f"{gcc_dll_dir}{os.pathsep}{os.environ.get('PATH', '')}"
        print(f"[WRAPPER] Added GCC DLL directory to PATH: {gcc_dll_dir}", file=sys.stderr)

# Now find or create GCC import library
gcc_lib_path, is_dynamic_gcc = find_gcc_library(lib_search_paths + bin_search_paths)

# If we couldn't find the import library but have the DLL, try to create one
if not gcc_lib_path and gcc_dll_path:
    temp_dir = tempfile.gettempdir()
    import_lib = create_import_lib(gcc_dll_path, temp_dir)
    if import_lib:
        gcc_lib_path = import_lib
        is_dynamic_gcc = True
        print(f"[WRAPPER] Created and will use import library: {gcc_lib_path}", file=sys.stderr)

# If we still don't have an import library, we'll need to use the DLL directly
if not gcc_lib_path and gcc_dll_path:
    print(f"[WRAPPER] No import library found or created, will try to link DLL directly: {gcc_dll_path}", file=sys.stderr)
    gcc_lib_path = gcc_dll_path
    is_dynamic_gcc = True

# Additional fallback: if GCC is not found at all, try to use direct implib name pattern
if not gcc_lib_path:
    print("[WRAPPER] No GCC library found, trying direct import library name patterns", file=sys.stderr)
    # Try some common patterns for import libraries
    for lib_dir in lib_search_paths:
        if not os.path.exists(lib_dir):
            continue

        potential_libs = [
            os.path.join(lib_dir, "libgcc_s.a"),
            os.path.join(lib_dir, "libgcc_s_seh-1.a"),
            os.path.join(lib_dir, "libgcc_s_seh.a"),
            os.path.join(lib_dir, "libgcc_s_dw2-1.a"),
            os.path.join(lib_dir, "libgcc_s_dw2.a"),
            os.path.join(lib_dir, "libgcc.a"),
        ]

        for lib in potential_libs:
            if os.path.exists(lib):
                gcc_lib_path = lib
                print(f"[WRAPPER] Found GCC library through direct pattern match: {gcc_lib_path}", file=sys.stderr)
                break

        if gcc_lib_path:
            break

# Last resort: try to extract the directory of libgcc from gcc command
if not gcc_lib_path:
    try:
        print("[WRAPPER] Trying to find libgcc.a using gcc -print-libgcc-file-name", file=sys.stderr)
        gcc_path = os.path.join(build_prefix, 'Library', 'bin', 'gcc.exe')
        if os.path.exists(gcc_path):
            result = subprocess.run(
                [gcc_path, "-print-libgcc-file-name"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if result.returncode == 0 and result.stdout:
                gcc_lib_path = result.stdout.strip()
                print(f"[WRAPPER] Found libgcc using gcc: {gcc_lib_path}", file=sys.stderr)
        else:
            print(f"[WRAPPER] GCC not found at {gcc_path}", file=sys.stderr)
    except Exception as e:
        print(f"[WRAPPER] Error running gcc: {e}", file=sys.stderr)

# If we still don't have the library path, create a stub with ___chkstk_ms
if not gcc_lib_path:
    print("[WRAPPER] Could not find or create GCC library, creating minimal stub for ___chkstk_ms", file=sys.stderr)
    # Create a minimal C file with __chkstk_ms implementation
    temp_c_file = os.path.join(tempfile.gettempdir(), "chkstk_ms.c")
    with open(temp_c_file, 'w') as f:
        f.write("""
// Simplified implementation of ___chkstk_ms
__attribute__((used))
void ___chkstk_ms(unsigned long size) {
    // Simple implementation that does nothing
    // This is just a stub to satisfy the linker
    (void)size;
}
        """)

    # Compile it to an object file
    temp_obj_file = os.path.join(tempfile.gettempdir(), "chkstk_ms.o")
    try:
        clang_exe = os.path.join(build_prefix, 'Library', 'bin', 'clang.exe')
        result = subprocess.run(
            [clang_exe, "--target=x86_64-w64-mingw32", "-c", temp_c_file, "-o", temp_obj_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False
        )
        if result.returncode == 0 and os.path.exists(temp_obj_file):
            gcc_lib_path = temp_obj_file
            print(f"[WRAPPER] Created stub object file with ___chkstk_ms: {gcc_lib_path}", file=sys.stderr)
        else:
            print(f"[WRAPPER] Failed to compile stub: {result.stderr.decode()}", file=sys.stderr)
    except Exception as e:
        print(f"[WRAPPER] Error compiling stub: {e}", file=sys.stderr)

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
                libgcc_added = False
                # Create a list to track all lines for later manipulation
                all_lines = []

                # First pass: read all lines and detect what's already there
                for line in in_file:
                    line = line.strip()
                    all_lines.append(line)

                    # Track if clang_rt.builtins-x86_64 is present
                    if ("clang_rt.builtins-x86_64" in line or "-lclang_rt.builtins-x86_64" in line):
                        clang_rt_added = True

                    # Check if libgcc.a or related import libraries are already present
                    if any(name in line for name in ['libgcc.a', 'libgcc_s.a', '-lgcc', 'gcc_s']):
                        libgcc_added = True
                        print(f"[WRAPPER] GCC library already included in response file: {line}", file=sys.stderr)

                # Make sure libgcc is added BEFORE clang_rt.builtins to resolve symbols correctly
                # Find the index where clang_rt is added if present
                clang_rt_index = -1
                for i, line in enumerate(all_lines):
                    if "clang_rt.builtins-x86_64" in line:
                        clang_rt_index = i
                        break

                # Write out all lines, inserting libgcc at the right position if needed
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

                    # If we're at the position just before clang_rt and we need to add libgcc,
                    # insert it here to ensure proper symbol resolution order
                    if i == clang_rt_index - 1 and not libgcc_added and gcc_lib_path:
                        print(f"[WRAPPER] Adding GCC library before clang_rt: {gcc_lib_path}", file=sys.stderr)
                        temp_file.write(f"{gcc_lib_path}\n")
                        libgcc_added = True

                    # Write the processed line
                    temp_file.write(f"{line}\n")

                # --- Add libgcc if not already present and no insertion point was found ---
                if not libgcc_added and gcc_lib_path:
                    print(f"[WRAPPER] Adding GCC library at end of response file: {gcc_lib_path}", file=sys.stderr)
                    temp_file.write(f"{gcc_lib_path}\n")
                    libgcc_added = True

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

# If we still haven't added libgcc and it's needed, add it directly to the command line
if gcc_lib_path and not libgcc_added:
    print("[WRAPPER] Adding GCC library directly to command line", file=sys.stderr)
    filtered_args.append(gcc_lib_path)

# If we're using a direct reference to the DLL, tell the linker it's ok
if is_dynamic_gcc and gcc_dll_path and gcc_lib_path == gcc_dll_path:
    print("[WRAPPER] Adding special flags for linking directly with DLL", file=sys.stderr)
    filtered_args.extend(["-Wl,--allow-shlib-undefined"])

final_cmd = [clang_exe] + filtered_args + runtime_flags

print(f"[WRAPPER] Final command: {' '.join(final_cmd)}", file=sys.stderr)

# Execute clang with the filtered arguments
exit_code = subprocess.call(final_cmd)
sys.exit(exit_code)
