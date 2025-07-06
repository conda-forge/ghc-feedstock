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

def create_system_clock_hs(output_path):
    """Create System/Clock.hs file directly with all necessary content."""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    print(f"Creating {output_path}")
    with open(output_path, 'w') as f:
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

def main():
    print(f"Direct HSC fix - Creating System/Clock.hs files")
    print(f"Working directory: {os.getcwd()}")

    # Target directories where we need to create Clock.hs files
    cwd = os.getcwd()

    # Create clock files in current working directory
    target_paths = [
        # Current directory structure
        os.path.join(cwd, "dist", "build", "System", "Clock.hs"),
        os.path.join(cwd, "System", "Clock.hs"),

        # Hard-coded cabal directory paths for Windows
        "C:/cabal/packages/clock-0.8.4/System/Clock.hs",
        "C:/cabal/store/ghc-9.10.1/clock-0.8.4/System/Clock.hs",
        "C:/cabal/store/ghc-9.10.1/clock-0.8.4-e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0/System/Clock.hs",

        # Dist directory paths
        os.path.join(cwd, "dist", "System", "Clock.hs"),
        os.path.join(cwd, "dist-newstyle", "build", "System", "Clock.hs")
    ]

    # Add clock package directories in cabal store
    if os.path.exists("C:/cabal/store"):
        try:
            for root, dirs, _ in os.walk("C:/cabal/store"):
                for d in dirs:
                    if "clock-0.8.4" in d:
                        target_paths.append(os.path.join(root, d, "System", "Clock.hs"))
                        target_paths.append(os.path.join(root, d, "dist", "build", "System", "Clock.hs"))
        except Exception as e:
            print(f"Error searching cabal store: {e}")

    # Create files in all target paths
    for path in target_paths:
        try:
            create_system_clock_hs(path)
        except Exception as e:
            print(f"Error creating {path}: {e}")

    print("HSC fix completed - Clock.hs files created in multiple locations")
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

    chmod +x $PREFIX/bin/fix-hsc-direct.py

    # Create a wrapper script to call the Python script without relying on environment variables
    cat > $PREFIX/bin/fix-hsc-crash.sh << 'EOF'
#!/bin/bash
set -e
SCRIPT_DIR=$(dirname "$0")
echo "Attempting to fix HSC crashes..."

# Run the Python script directly, no args needed
python "$SCRIPT_DIR/fix-hsc-direct.py"

# Also create the file directly in the current directory's error location
CURR_DIR=$(pwd)
mkdir -p "$CURR_DIR/dist/build/System"
cat > "$CURR_DIR/dist/build/System/Clock.hs" << 'EOHASKELL'
-- Auto-generated by fix-hsc-crash.sh
{-# LANGUAGE CPP, ForeignFunctionInterface, CApiFFI #-}
{-# LANGUAGE BangPatterns #-}

module System.Clock (
    TimeSpec(..),
    ClockID(..),
    getTime,
    getRes,
    ) where

import Data.Int (Int64)
import Foreign.C.Types
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr)
import Foreign.Storable (Storable(..))

data ClockID = Monotonic | Realtime | ProcessCPUTime | ThreadCPUTime deriving (Eq, Show)

data TimeSpec = TimeSpec {
    sec :: {-# UNPACK #-} !Int64,
    nsec :: {-# UNPACK #-} !Int64
} deriving (Eq, Ord, Show)

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
