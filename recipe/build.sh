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
import subprocess
import tempfile

def find_files(start_dir, filename_pattern, max_depth=15):
    """Find files matching pattern starting from start_dir with max depth."""
    found_files = []

    try:
        for root, dirs, files in os.walk(start_dir):
            # Calculate current depth
            depth = root[len(start_dir):].count(os.sep)
            if depth > max_depth:
                continue

            # Check for matching files
            for name in files:
                if filename_pattern in name:
                    found_files.append(os.path.join(root, name))

    except Exception as e:
        print(f"Error searching {start_dir}: {e}")

    return found_files

def create_system_clock_hs(output_dir):
    """Create System/Clock.hs file directly with all necessary content."""
    os.makedirs(os.path.join(output_dir, "System"), exist_ok=True)
    output_file = os.path.join(output_dir, "System", "Clock.hs")

    print(f"Creating {output_file}")
    with open(output_file, 'w') as f:
        f.write("""-- Auto-generated to bypass HSC processing
{-# LANGUAGE CPP, ForeignFunctionInterface, CApiFFI #-}
{-# LANGUAGE BangPatterns #-}

module System.Clock (
    -- * Timespec
    TimeSpec(..),
    -- * Clock identifiers
    ClockID(..),
    -- * Clock operations
    getTime,
    getRes,
    ) where

import Data.Int (Int64)
import Data.Word (Word64)
import Foreign.C.Types
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr)
import Foreign.Storable (Storable(..))
import Control.Exception (throwIO)
import System.IO.Error (IOError, mkIOError, illegalOperationErrorType)

-- | Clock identifier
data ClockID
    = Monotonic       -- ^ Monotonic time since some unspecified starting point
    | Realtime        -- ^ System clock, time since epoch
    | ProcessCPUTime  -- ^ Per-process CPU time
    | ThreadCPUTime   -- ^ Per-thread CPU time
    deriving (Eq, Show)

-- | Time in seconds and nanoseconds
data TimeSpec = TimeSpec {
    sec  :: {-# UNPACK #-} !Int64,  -- ^ seconds
    nsec :: {-# UNPACK #-} !Int64   -- ^ nanoseconds
    } deriving (Eq, Ord, Show)

instance Storable TimeSpec where
    sizeOf _ = 16  -- 8 bytes for each Int64
    alignment _ = 8
    peek ptr = do
        s <- peekByteOff ptr 0 :: IO Int64
        ns <- peekByteOff ptr 8 :: IO Int64
        return $ TimeSpec s ns
    poke ptr (TimeSpec s ns) = do
        pokeByteOff ptr 0 (s :: Int64)
        pokeByteOff ptr 8 (ns :: Int64)

#if defined(_WIN32)
-- | Windows implementation using capi for better foreign call handling
foreign import capi unsafe "hs_clock_win32.c hs_clock_win32_gettime"
  c_clock_gettime :: ClockID -> Ptr TimeSpec -> IO CInt
#else
-- | POSIX implementation
foreign import ccall unsafe "time.h clock_gettime"
  c_clock_gettime :: ClockID -> Ptr TimeSpec -> IO CInt
#endif

-- | Get the time from a clock
getTime :: ClockID -> IO TimeSpec
getTime clockid = alloca $ \\ptr -> do
    throwErrnoIfMinus1_ "clock_gettime" $ c_clock_gettime clockid ptr
    peek ptr

-- | Get the resolution from a clock
getRes :: ClockID -> IO TimeSpec
getRes Monotonic = return $ TimeSpec 0 1  -- 1 nanosecond resolution
getRes Realtime = return $ TimeSpec 0 1   -- 1 nanosecond resolution
getRes _ = return $ TimeSpec 0 1000       -- 1 microsecond resolution

-- Helper for error handling
throwErrnoIfMinus1_ :: String -> IO CInt -> IO ()
throwErrnoIfMinus1_ str action = do
    res <- action
    if res == -1
        then throwIO $ mkIOError illegalOperationErrorType str Nothing Nothing
        else return ()
""")
    return output_file

def inject_prebuilt_files(cabal_dir, build_dir):
    """Inject pre-built Clock.hs file into key locations."""
    # Main locations to check
    dist_build_dir = os.path.join(build_dir, "dist", "build")
    if not os.path.exists(dist_build_dir):
        os.makedirs(dist_build_dir, exist_ok=True)

    # Create prebuilt Clock.hs
    create_system_clock_hs(dist_build_dir)

    # Also try to find any clock-0.8.4 directories and place the file there
    if os.path.exists(cabal_dir):
        clock_dirs = []
        for root, dirs, _ in os.walk(cabal_dir):
            for d in dirs:
                if "clock-0.8.4" in d:
                    clock_dirs.append(os.path.join(root, d))

        for cdir in clock_dirs:
            print(f"Found clock dir: {cdir}")
            # Put file in dist/build/System
            dist_path = os.path.join(cdir, "dist", "build")
            create_system_clock_hs(dist_path)

    # Save the file to current directory as well
    current_dir = os.getcwd()
    create_system_clock_hs(os.path.join(current_dir, "dist", "build"))

    # Also inject in the directories Cabal mentions in the error
    error_path = os.path.join(current_dir, "dist", "build", "System")
    os.makedirs(error_path, exist_ok=True)
    with open(os.path.join(error_path, "Clock.hs"), 'w') as f:
        f.write("-- Auto-generated placeholder Clock.hs\n")
        f.write("module System.Clock where\n")

if __name__ == "__main__":
    print(f"Arguments: {sys.argv}")

    # Use current directory as fallback
    current_dir = os.getcwd()
    cabal_dir = sys.argv[2] if len(sys.argv) > 2 else current_dir
    build_dir = current_dir

    print(f"Current directory: {current_dir}")
    print(f"Cabal directory: {cabal_dir}")

    # Inject prebuilt Clock.hs files
    inject_prebuilt_files(cabal_dir, build_dir)

    # Search for any Clock.hsc files and patch them as well
    hsc_files = find_files(cabal_dir, "Clock.hsc")
    print(f"Found HSC files: {hsc_files}")

    for hsc_file in hsc_files:
        print(f"Patching {hsc_file}")
        try:
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

            # Also try to create the .hs file directly from the .hsc file
            hs_file = hsc_file.replace('.hsc', '.hs')
            create_system_clock_hs(os.path.dirname(os.path.dirname(hsc_file)))

        except Exception as e:
            print(f"Error patching {hsc_file}: {e}")

    print("HSC fix completed")
EOF

    chmod +x $PREFIX/bin/fix-hsc-direct.py

    # Create a wrapper script to call the Python script
    cat > $PREFIX/bin/fix-hsc-crash.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR=$(dirname "$0")
echo "Attempting to fix HSC crashes..."
# Use explicit paths and PWD instead of relying on environment variables
python "$SCRIPT_DIR/fix-hsc-direct.py" "$PWD" "C:/cabal"
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
