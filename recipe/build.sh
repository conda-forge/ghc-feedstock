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
import shutil

def create_system_clock_hs(output_dir):
    """Create System/Clock.hs file directly with all necessary content."""
    os.makedirs(output_dir, exist_ok=True)
    system_dir = os.path.join(output_dir, "System")
    os.makedirs(system_dir, exist_ok=True)
    output_file = os.path.join(system_dir, "Clock.hs")

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

def find_dist_dirs(start_dir):
    """Find all dist and dist-newstyle dirs under start_dir."""
    result = []
    try:
        for root, dirs, _ in os.walk(start_dir):
            if "dist" in dirs:
                result.append(os.path.join(root, "dist"))
            if "dist-newstyle" in dirs:
                result.append(os.path.join(root, "dist-newstyle"))
    except Exception as e:
        print(f"Error searching for dist dirs: {e}")
    return result

def create_clock_files_everywhere():
    """Create Clock.hs files in multiple locations to ensure they're found."""
    # Current directory and its dist folder
    create_system_clock_hs(".")
    create_system_clock_hs("./dist")
    create_system_clock_hs("./dist/build")

    # Direct creation in the error path
    cwd = os.getcwd()
    dist_build_system = os.path.join(cwd, "dist", "build", "System")
    os.makedirs(dist_build_system, exist_ok=True)
    with open(os.path.join(dist_build_system, "Clock.hs"), "w") as f:
        f.write("""-- Auto-generated direct replacement
module System.Clock where

import Data.Int
import Foreign.C.Types
import Foreign.Ptr
import Foreign.Storable
import Foreign.Marshal.Alloc

data TimeSpec = TimeSpec {
    sec :: Int64,
    nsec :: Int64
} deriving (Eq, Ord, Show)

data ClockID = Monotonic | Realtime | ProcessCPUTime | ThreadCPUTime deriving (Eq, Show)

instance Storable TimeSpec where
    sizeOf _ = 16
    alignment _ = 8
    peek ptr = do
        s <- peekByteOff ptr 0 :: IO Int64
        ns <- peekByteOff ptr 8 :: IO Int64
        return $ TimeSpec s ns
    poke ptr (TimeSpec s ns) = do
        pokeByteOff ptr 0 (s :: Int64)
        pokeByteOff ptr 8 (ns :: Int64)

foreign import capi unsafe "hs_clock_win32.c hs_clock_win32_gettime"
  c_clock_gettime :: ClockID -> Ptr TimeSpec -> IO CInt

getTime :: ClockID -> IO TimeSpec
getTime clock = alloca $ \\ptr -> do
    c_clock_gettime clock ptr
    peek ptr

getRes :: ClockID -> IO TimeSpec
getRes _ = return $ TimeSpec 0 1
""")

    # Search for cabal directories
    cabal_dirs = []
    for path in ["C:/cabal", "C:/cabal/packages", "C:/cabal/store"]:
        if os.path.exists(path):
            cabal_dirs.append(path)
            # Find any clock-0.8.4 directories
            try:
                for root, dirs, _ in os.walk(path):
                    for d in dirs:
                        if "clock-0.8.4" in d:
                            clock_dir = os.path.join(root, d)
                            print(f"Found clock package: {clock_dir}")
                            create_system_clock_hs(clock_dir)
                            # Also create in dist/build
                            create_system_clock_hs(os.path.join(clock_dir, "dist"))
                            create_system_clock_hs(os.path.join(clock_dir, "dist", "build"))
            except Exception as e:
                print(f"Error searching in {path}: {e}")

    # Try to locate any directories with dist/build/System
    for cabal_dir in cabal_dirs:
        try:
            for root, dirs, _ in os.walk(cabal_dir):
                if "build" in dirs and "System" in os.listdir(os.path.join(root, "build")):
                    print(f"Found build/System directory: {os.path.join(root, 'build')}")
                    create_system_clock_hs(os.path.join(root))
        except Exception as e:
            print(f"Error searching for build/System: {e}")

if __name__ == "__main__":
    print(f"Direct HSC fix - Creating System/Clock.hs files")
    print(f"Working directory: {os.getcwd()}")
    print(f"Command line arguments: {sys.argv}")

    # Create Clock.hs files in multiple locations
    create_clock_files_everywhere()

    # Try to find the problematic directory from the error message
    rsp_file_pattern = "dist\\\\build\\\\System\\\\hsc*.rsp"
    output_file_pattern = "dist\\\\build\\\\System\\\\Clock.hs"

    # Create any parent directories
    os.makedirs("dist/build/System", exist_ok=True)

    print("HSC fix completed - Clock.hs files created in multiple locations")
EOF

    chmod +x $PREFIX/bin/fix-hsc-direct.py

    # Create a wrapper script to call the Python script
    cat > $PREFIX/bin/fix-hsc-crash.sh << 'EOF'
#!/bin/bash
set -e
SCRIPT_DIR=$(dirname "$0")
echo "Attempting to fix HSC crashes..."
python "$SCRIPT_DIR/fix-hsc-direct.py"
# Also create the file directly in the error location
CURR_DIR=$(pwd)
mkdir -p "$CURR_DIR/dist/build/System"
cat > "$CURR_DIR/dist/build/System/Clock.hs" << 'EOHASKELL'
-- Auto-generated by fix-hsc-crash.sh
module System.Clock where

import Data.Int
import Foreign.C.Types
import Foreign.Ptr
import Foreign.Storable
import Foreign.Marshal.Alloc

data TimeSpec = TimeSpec {
    sec :: Int64,
    nsec :: Int64
} deriving (Eq, Ord, Show)

data ClockID = Monotonic | Realtime | ProcessCPUTime | ThreadCPUTime deriving (Eq, Show)

instance Storable TimeSpec where
    sizeOf _ = 16
    alignment _ = 8
    peek ptr = do
        s <- peekByteOff ptr 0 :: IO Int64
        ns <- peekByteOff ptr 8 :: IO Int64
        return $ TimeSpec s ns
    poke ptr (TimeSpec s ns) = do
        pokeByteOff ptr 0 (s :: Int64)
        pokeByteOff ptr 8 (ns :: Int64)

foreign import capi unsafe "hs_clock_win32.c hs_clock_win32_gettime"
  c_clock_gettime :: ClockID -> Ptr TimeSpec -> IO CInt

getTime :: ClockID -> IO TimeSpec
getTime clock = alloca $ \ptr -> do
    c_clock_gettime clock ptr
    peek ptr

getRes :: ClockID -> IO TimeSpec
getRes _ = return $ TimeSpec 0 1
EOHASKELL
echo "Created direct Clock.hs file in $CURR_DIR/dist/build/System/"
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
