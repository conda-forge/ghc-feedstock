# clang-mingw-wrapper.py
import sys
import os
import tempfile
import subprocess


print("[WRAPPER] Starting clang-mingw-wrapper", file=sys.stderr)
print("[WRAPPER] Arguments:", sys.argv[1:], file=sys.stderr)

filtered_args = []

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
                build_prefix = os.environ.get('BUILD_PREFIX', '')
                for line in in_file:
                    line = line.strip()
                    skip_line = False

                    # Only skip lines that contain both bootstrap-ghc AND mingw
                    if (line.startswith('-I') or line.startswith('-L')) and \
                       'bootstrap-ghc' in line and '/mingw/' in line:
                        skip_line = True
                        print(f"[WRAPPER] Skipping line from response file: {line}", file=sys.stderr)

                    if not skip_line:
                        temp_file.write(f"{line}\n")

                # Add the required libraries for stack checking
                temp_file.write(f"-L{os.path.join(build_prefix, 'Library', 'mingw-w64', 'lib')}\n")
                temp_file.write("-lmingw32\n")
                temp_file.write("-lmingwex\n")

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
build_prefix = os.environ.get('BUILD_PREFIX', '')
filtered_args.extend(
    (
        f"-I{build_prefix}\\Library\\mingw-w64\\include",
        f"-L{build_prefix}\\Library\\mingw-w64\\lib",
    )
)

# Prepare final command
clang_exe = f"{build_prefix}\\Library\\bin\\clang.exe"
final_cmd = [clang_exe] + filtered_args + [
    '--target=x86_64-w64-mingw32',
    '-fuse-ld=lld',
    '-rtlib=compiler-rt',
    # Add reference to mingwex and mingw32 here as well to ensure stack checking functions are found
    '-lmingwex',
    '-lmingw32',
    '-lclang_rt.builtins-x86_64'
]

print(f"[WRAPPER] Final command: {' '.join(final_cmd)}", file=sys.stderr)

# Execute clang with the filtered arguments
exit_code = subprocess.call(final_cmd)
sys.exit(exit_code)