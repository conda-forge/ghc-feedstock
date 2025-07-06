#!/usr/bin/env bash
set -eu

# Set up binary directory
mkdir -p binary/bin _logs

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d

export MergeObjsCmd=${LD_GOLD:-${LD}}
export M4=${BUILD_PREFIX}/bin/m4
# export PYTHON=${BUILD_PREFIX}/bin/python
export PATH=$PWD/binary/bin:$PATH

# Install cabal-install
cp bootstrap-cabal/cabal* binary/bin/

# Fix for HSC tool crashes on Windows
if [[ "$target_platform" == win-* ]]; then
    # Pre-generate the clock package output to bypass HSC issues
    mkdir -p $PREFIX/bin
    cat > $PREFIX/bin/fix-hsc-direct.py << 'EOF'
#!/usr/bin/env python
import os
import sys
import glob
import re

def normalize_path(path):
    """Normalize path regardless of platform."""
    if path.startswith('%') and path.endswith('%'):
        return path  # Leave environment variables as is
    return os.path.normpath(path)

def search_directory(base_dir, pattern, max_depth=10):
    """Search for files/directories matching a pattern with max depth limit."""
    if not os.path.exists(base_dir):
        print(f"Path does not exist: {base_dir}")
        return []

    results = []
    pattern_re = re.compile(pattern.replace('*', '.*'))

    for root, dirs, files in os.walk(normalize_path(base_dir)):
        depth = root[len(normalize_path(base_dir)):].count(os.sep)
        if depth > max_depth:
            continue

        for item in dirs:
            if pattern_re.search(item):
                results.append(os.path.join(root, item))

    return results

def find_cabal_package(package_name, search_paths):
    """Find a specific Cabal package in the given paths."""
    print(f"Searching for {package_name} in:")
    results = []

    for base_dir in search_paths:
        print(f"  - {base_dir}")
        if not os.path.exists(normalize_path(base_dir)):
            print(f"    Path does not exist: {base_dir}")
            continue

        # Try direct glob patterns
        patterns = [
            f"**/{package_name}*",
            f"**/packages/{package_name}*",
            f"**/store/**/{package_name}*",
        ]

        for pattern in patterns:
            try:
                matches = glob.glob(os.path.join(normalize_path(base_dir), pattern), recursive=True)
                for match in matches:
                    if os.path.isdir(match):
                        print(f"    Found: {match}")
                        results.append(match)
            except Exception as e:
                print(f"    Error searching with pattern {pattern}: {e}")

        # Try manual directory search for deeply nested paths
        more_results = search_directory(base_dir, package_name)
        for result in more_results:
            if result not in results and os.path.isdir(result):
                print(f"    Found (deep search): {result}")
                results.append(result)

    return results

def create_clock_hs_file(hs_file):
    """Create a pre-processed System/Clock.hs file to bypass HSC processing."""
    print(f"Creating pre-processed {hs_file}")
    os.makedirs(os.path.dirname(hs_file), exist_ok=True)

    with open(hs_file, 'w') as f:
        f.write("""-- Auto-generated to bypass HSC processing
{-# LANGUAGE CPP, ForeignFunctionInterface, CApiFFI #-}

module System.Clock where

import Foreign.C.Types
import Foreign.Ptr
import Foreign.Storable
import Data.Int
import Data.Word

data TimeSpec = TimeSpec {
    sec :: {-# UNPACK #-} !Int64,
    nsec :: {-# UNPACK #-} !Int64
} deriving (Eq, Ord, Show)

instance Storable TimeSpec where
    sizeOf _ = 16  -- 8 bytes for each Int64
    alignment _ = 8
    peek ptr = do
        s <- peekByteOff ptr 0
        ns <- peekByteOff ptr 8
        return $ TimeSpec s ns
    poke ptr (TimeSpec s ns) = do
        pokeByteOff ptr 0 s
        pokeByteOff ptr 8 ns

data ClockID = Monotonic | Realtime | ProcessCPUTime | ThreadCPUTime
    deriving (Eq, Show)

foreign import capi unsafe "hs_clock_win32.c hs_clock_win32_gettime"
  c_clock_gettime :: ClockID -> Ptr TimeSpec -> IO CInt

getTime :: ClockID -> IO TimeSpec
getTime clock = alloca $ \\ptr -> do
    throwErrnoIfMinus1_ "clock_gettime" $ c_clock_gettime clock ptr
    peek ptr

getRes :: ClockID -> IO TimeSpec
getRes _ = return $ TimeSpec 0 1 -- 1 nanosecond resolution
""")

def fix_clock_hsc(src_dir, cabal_dir, cabal_home, build_prefix, ghc_store):
    print("Direct HSC Fixer - Bypassing HSC tools")

    # Use more search paths to find the package
    search_paths = [
        cabal_dir,
        os.path.join(cabal_home, "packages"),
        os.path.join(os.path.expanduser("~"), ".cabal", "packages"),
        ghc_store,
        src_dir,
        build_prefix,
        os.path.join(build_prefix, "Library", cabal_home),
        ".",
        "..",
        os.path.join(os.getcwd(), "dist"),
        os.path.join(os.getcwd(), "dist-newstyle")
    ]

    # Create fixed versions in the current directory as a fallback
    fallback_dir = os.path.join(os.getcwd(), "dist", "build", "System")
    os.makedirs(fallback_dir, exist_ok=True)
    create_clock_hs_file(os.path.join(fallback_dir, "Clock.hs"))

    # Look for clock package directories
    clock_dirs = find_cabal_package("clock-0.8.4", search_paths)

    if not clock_dirs:
        print("Could not find clock-0.8.4 package. Creating fallback files.")
        # Create a fallback file in the current directory
        return

    for clock_dir in clock_dirs:
        print(f"Processing clock package at: {clock_dir}")

        # Look for System directory
        system_dir = os.path.join(clock_dir, "System")
        if not os.path.isdir(system_dir):
            system_dir = os.path.join(clock_dir, "dist", "build", "System")
            if not os.path.isdir(system_dir):
                print(f"  No System directory found in {clock_dir}")
                os.makedirs(system_dir, exist_ok=True)

        # Check for HSC file
        hsc_file = os.path.join(system_dir, "Clock.hsc")
        if os.path.isfile(hsc_file):
            print(f"  Modifying HSC file: {hsc_file}")
            with open(hsc_file, 'r') as f:
                content = f.read()

            # Add CApiFFI language pragma
            if '{-# LANGUAGE CApiFFI #-}' not in content:
                content = content.replace(
                    '{-# LANGUAGE CPP, ForeignFunctionInterface #-}',
                    '{-# LANGUAGE CPP, ForeignFunctionInterface, CApiFFI #-}'
                )

            # Replace ccall with capi for Windows imports
            content = content.replace(
                'foreign import ccall unsafe "hs_clock_win32.c hs_clock_win32_gettime"',
                'foreign import capi unsafe "hs_clock_win32.c hs_clock_win32_gettime"'
            )

            with open(hsc_file, 'w') as f:
                f.write(content)
        else:
            print(f"  HSC file not found: {hsc_file}")

        # Create or update the HS file
        hs_file = os.path.join(system_dir, "Clock.hs")
        create_clock_hs_file(hs_file)

        # Create HS file in dist/build if it exists
        dist_build_dir = os.path.join(clock_dir, "dist", "build", "System")
        if not os.path.isdir(dist_build_dir):
            os.makedirs(dist_build_dir, exist_ok=True)

        create_clock_hs_file(os.path.join(dist_build_dir, "Clock.hs"))

if __name__ == "__main__":
    print(f"Arguments: {sys.argv}")
    if len(sys.argv) >= 6:
        fix_clock_hsc(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    else:
        print("Usage: fix-hsc-direct.py SRC_DIR CABAL_DIR CABAL_HOME BUILD_PREFIX GHC_STORE")
        sys.exit(1)
EOF

    chmod +x $PREFIX/bin/fix-hsc-direct.py

    # Create a wrapper script to call the Python script
    cat > $PREFIX/bin/fix-hsc-crash.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR=$(dirname "$0")
echo "Attempting to fix HSC crashes..."
python $SCRIPT_DIR/fix-hsc-direct.py "${SRC_DIR}" "${PWD}" "${HOME}/.cabal" "${BUILD_PREFIX}" "${PREFIX}/store/ghc-${PKG_VERSION}"
EOF

    chmod +x $PREFIX/bin/fix-hsc-crash.sh
fi

"${RECIPE_DIR}"/building/build-"${target_platform}.sh"

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache
find "${PREFIX}"/lib/ghc-"${PKG_VERSION}" -name '*_p.a' -delete
find "${PREFIX}"/lib/ghc-"${PKG_VERSION}" -name '*.p_o' -delete

# Clean up package cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"
