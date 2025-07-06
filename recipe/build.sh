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

def main():
    print(f"DEBUG: Starting HSC fix script")
    print(f"DEBUG: Working directory: {os.getcwd()}")

    # Create files directly in the current working directory structure
    cwd = os.getcwd()

    # Create Clock.hs
    clock_path = os.path.join(cwd, "dist", "build", "System", "Clock.hs")
    try:
        print(f"DEBUG: Creating directory for {clock_path}")
        os.makedirs(os.path.dirname(clock_path), exist_ok=True)

        print(f"DEBUG: Writing Clock.hs to {clock_path}")
        with open(clock_path, 'w') as f:
            f.write("""-- Auto-generated to bypass HSC processing
{-# LANGUAGE CPP, ForeignFunctionInterface, CApiFFI #-}

module System.Clock (
    TimeSpec(..),
    ClockID(..),
    getTime,
    getRes,
    fromNanoSecs,
    toNanoSecs,
    diffTimeSpec,
    timeSpecAsNanoSecs,
    ) where

import Data.Int (Int64)
import Foreign.C.Types (CInt)
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr)
import Foreign.Storable (Storable(..))

data ClockID = Monotonic | Realtime | ProcessCPUTime | ThreadCPUTime
    deriving (Eq, Ord, Show, Read)

data TimeSpec = TimeSpec
    { sec  :: {-# UNPACK #-} !Int64
    , nsec :: {-# UNPACK #-} !Int64
    } deriving (Eq, Ord, Show, Read)

instance Storable TimeSpec where
    sizeOf _ = 16
    alignment _ = 8
    peek ptr = do
        s <- peekByteOff ptr 0
        ns <- peekByteOff ptr 8
        return $ TimeSpec s ns
    poke ptr (TimeSpec s ns) = do
        pokeByteOff ptr 0 s
        pokeByteOff ptr 8 ns

foreign import capi unsafe "hs_clock_win32.c hs_clock_win32_gettime"
    c_clock_gettime :: ClockID -> Ptr TimeSpec -> IO CInt

getTime :: ClockID -> IO TimeSpec
getTime clock = alloca $ \\ptr -> do
    res <- c_clock_gettime clock ptr
    if res == -1
        then error "clock_gettime failed"
        else peek ptr

getRes :: ClockID -> IO TimeSpec
getRes _ = return $ TimeSpec 0 1

fromNanoSecs :: Int64 -> TimeSpec
fromNanoSecs ns = TimeSpec (ns `div` 1000000000) (ns `mod` 1000000000)

toNanoSecs :: TimeSpec -> Int64
toNanoSecs (TimeSpec s ns) = s * 1000000000 + ns

diffTimeSpec :: TimeSpec -> TimeSpec -> TimeSpec
diffTimeSpec (TimeSpec s1 ns1) (TimeSpec s2 ns2) =
    fromNanoSecs (toNanoSecs (TimeSpec s1 ns1) - toNanoSecs (TimeSpec s2 ns2))

timeSpecAsNanoSecs :: TimeSpec -> Int64
timeSpecAsNanoSecs = toNanoSecs
""")

        print(f"DEBUG: Successfully created {clock_path}")
        if os.path.exists(clock_path):
            print(f"DEBUG: File size: {os.path.getsize(clock_path)} bytes")

    except Exception as e:
        print(f"DEBUG: Error creating Clock.hs: {e}")
        import traceback
        traceback.print_exc()

    # Create Platform.hs
    platform_path = os.path.join(cwd, "dist", "build", "System", "File", "Platform.hs")
    try:
        print(f"DEBUG: Creating directory for {platform_path}")
        os.makedirs(os.path.dirname(platform_path), exist_ok=True)

        print(f"DEBUG: Writing Platform.hs to {platform_path}")
        with open(platform_path, 'w') as f:
            f.write("""-- Auto-generated to bypass HSC processing
{-# LANGUAGE CPP #-}

module System.File.Platform (
    PlatformPath,
    pathSeparator,
    isPathSeparator,
    searchPathSeparator,
    extSeparator,
    isExtSeparator,
    ) where

type PlatformPath = String

pathSeparator :: Char
pathSeparator = '\\\\'

isPathSeparator :: Char -> Bool
isPathSeparator c = c == '\\\\' || c == '/'

searchPathSeparator :: Char
searchPathSeparator = ';'

extSeparator :: Char
extSeparator = '.'

isExtSeparator :: Char -> Bool
isExtSeparator c = c == '.'
""")

        print(f"DEBUG: Successfully created {platform_path}")
        if os.path.exists(platform_path):
            print(f"DEBUG: File size: {os.path.getsize(platform_path)} bytes")

    except Exception as e:
        print(f"DEBUG: Error creating Platform.hs: {e}")
        import traceback
        traceback.print_exc()

    print("DEBUG: HSC fix completed")
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

    chmod +x $PREFIX/bin/fix-hsc-direct.py

    # Create a wrapper script that calls the Python script without arguments
    cat > $PREFIX/bin/fix-hsc-crash.sh << 'EOF'
#!/bin/bash
set -e
echo "DEBUG: Starting HSC crash fix script"

# Get current directory
CURR_DIR=$(pwd)
echo "DEBUG: Current directory: $CURR_DIR"

# Create directories first
mkdir -p "$CURR_DIR/dist/build/System"
mkdir -p "$CURR_DIR/dist/build/System/File"

# Call the Python script directly without arguments
SCRIPT_DIR=$(dirname "$0")
if [ -f "$SCRIPT_DIR/fix-hsc-direct.py" ]; then
    echo "DEBUG: Running Python script..."
    python "$SCRIPT_DIR/fix-hsc-direct.py"
else
    echo "DEBUG: Python script not found, creating files directly"

    # Fallback: create files directly in bash
    cat > "$CURR_DIR/dist/build/System/Clock.hs" << 'EOHASKELL'
-- Auto-generated by fix-hsc-crash.sh
{-# LANGUAGE CPP, ForeignFunctionInterface, CApiFFI #-}

module System.Clock (
    TimeSpec(..),
    ClockID(..),
    getTime,
    getRes,
    ) where

import Data.Int (Int64)
import Foreign.C.Types (CInt)
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr)
import Foreign.Storable (Storable(..))

data ClockID = Monotonic | Realtime | ProcessCPUTime | ThreadCPUTime
    deriving (Eq, Ord, Show, Read)

data TimeSpec = TimeSpec
    { sec  :: {-# UNPACK #-} !Int64
    , nsec :: {-# UNPACK #-} !Int64
    } deriving (Eq, Ord, Show, Read)

instance Storable TimeSpec where
    sizeOf _ = 16
    alignment _ = 8
    peek ptr = do
        s <- peekByteOff ptr 0
        ns <- peekByteOff ptr 8
        return $ TimeSpec s ns
    poke ptr (TimeSpec s ns) = do
        pokeByteOff ptr 0 s
        pokeByteOff ptr 8 ns

foreign import capi unsafe "hs_clock_win32.c hs_clock_win32_gettime"
    c_clock_gettime :: ClockID -> Ptr TimeSpec -> IO CInt

getTime :: ClockID -> IO TimeSpec
getTime clock = alloca $ \ptr -> do
    res <- c_clock_gettime clock ptr
    if res == -1
        then error "clock_gettime failed"
        else peek ptr

getRes :: ClockID -> IO TimeSpec
getRes _ = return $ TimeSpec 0 1
EOHASKELL

    cat > "$CURR_DIR/dist/build/System/File/Platform.hs" << 'EOHASKELL'
-- Auto-generated by fix-hsc-crash.sh
{-# LANGUAGE CPP #-}

module System.File.Platform (
    PlatformPath,
    pathSeparator,
    isPathSeparator,
    searchPathSeparator,
    extSeparator,
    isExtSeparator,
    ) where

type PlatformPath = String

pathSeparator :: Char
pathSeparator = '\\'

isPathSeparator :: Char -> Bool
isPathSeparator c = c == '\\' || c == '/'

searchPathSeparator :: Char
searchPathSeparator = ';'

extSeparator :: Char
extSeparator = '.'

isExtSeparator :: Char -> Bool
isExtSeparator c = c == '.'
EOHASKELL

    echo "DEBUG: Created files directly in bash"
fi

echo "DEBUG: HSC crash fix script completed"
EOF

    chmod +x $PREFIX/bin/fix-hsc-crash.sh
fi

"${RECIPE_DIR}"/building/build-"${target_platform}".sh

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
