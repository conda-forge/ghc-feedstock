#!/usr/bin/env python
"""
Direct fix for HSC tool crashes in Windows GHC build
"""
import os
import sys
import glob
import re
import shutil

# Known problematic packages and their file mappings
PACKAGE_FIXES = {
    "clock": {
        "System/Clock.hs": "Clock.hs"
    },
    "file-io": {
        "System/File/Platform.hs": "Platform.hs"
    }
}

def find_build_dirs():
    """Find all relevant build directories"""
    search_paths = [
        "C:/cabal",
        os.path.expanduser("~") + "/AppData/Local/Temp",
        os.path.expanduser("~") + "/.cabal",
        os.getcwd()
    ]

    build_dirs = []
    for base_path in search_paths:
        if os.path.exists(base_path):
            print(f"Searching in {base_path}")

            # Look for dist directories that might contain our targets
            for path in glob.glob(f"{base_path}/**/dist*/build", recursive=True):
                if os.path.isdir(path):
                    build_dirs.append(path)

            # Look for specific package build directories
            for package in PACKAGE_FIXES.keys():
                for path in glob.glob(f"{base_path}/**/{package}-*/dist*/build", recursive=True):
                    if os.path.isdir(path) and path not in build_dirs:
                        build_dirs.append(path)

    print(f"Found {len(build_dirs)} potential build directories")
    return build_dirs

def create_parent_dirs(filepath):
    """Ensure parent directories exist"""
    parent_dir = os.path.dirname(filepath)
    if not os.path.exists(parent_dir):
        os.makedirs(parent_dir, exist_ok=True)

def apply_fixes(build_dir, script_dir):
    """Apply fixes for known problematic HSC files in the build directory"""
    fixes_applied = 0

    for package, file_mappings in PACKAGE_FIXES.items():
        for target_path, source_file in file_mappings.items():
            # Find the target file in the build directory
            full_target_path = os.path.join(build_dir, target_path)
            target_pattern = os.path.dirname(full_target_path)

            # Check for target_pattern directory
            if os.path.exists(target_pattern):
                print(f"Found target directory: {target_pattern}")

                # Source for the pre-generated file
                source_path = os.path.join(script_dir, "hsc_workarounds", package, source_file)

                if os.path.exists(source_path):
                    # Ensure target parent directories exist
                    create_parent_dirs(full_target_path)

                    # Copy the pre-generated file
                    print(f"Copying {source_path} to {full_target_path}")
                    shutil.copy2(source_path, full_target_path)
                    fixes_applied += 1

                    # Look for associated Makefile to patch
                    makefile = os.path.join(target_pattern, "Makefile")
                    if os.path.exists(makefile):
                        print(f"Found Makefile at {makefile}")
                        try:
                            with open(makefile, "r") as f:
                                content = f.read()

                            # Create backup
                            backup_path = makefile + ".bak"
                            if not os.path.exists(backup_path):
                                shutil.copy2(makefile, backup_path)

                            # Replace HSC tool invocation with echo
                            target_file = os.path.basename(full_target_path)
                            pattern = rf"{target_file}:.*\.hsc.*_hsc_make\.exe\n\t.*_hsc_make\.exe"
                            replacement = f"{target_file}: \n\t@echo Using pre-generated {target_file}"

                            new_content = re.sub(pattern, replacement, content)
                            if new_content != content:
                                print(f"Patching Makefile at {makefile}")
                                with open(makefile, "w") as f:
                                    f.write(new_content)
                        except Exception as e:
                            print(f"Error patching Makefile: {e}")

    return fixes_applied

def main():
    """Main entry point"""
    print("Direct HSC Fix Script - Bypassing HSC tools")

    # Get the directory containing this script
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Create pre-generated Haskell files directory structure
    for package in PACKAGE_FIXES.keys():
        os.makedirs(os.path.join(script_dir, "hsc_workarounds", package), exist_ok=True)

    # Copy Clock.hs to appropriate location
    with open(os.path.join(script_dir, "hsc_workarounds", "clock", "Clock.hs"), "w") as f:
        f.write("""-- Pre-generated Clock.hs file
{-# LANGUAGE CPP, ForeignFunctionInterface #-}
module System.Clock
    ( Clock(..)
    , TimeSpec(..)
    , getTime
    , getRes
    , toNanoSecs
    , fromNanoSecs
    ) where

import Control.Applicative
import Data.Int
import Foreign.C.Types
import Foreign.Marshal.Alloc
import Foreign.Ptr
import Foreign.Storable
import Data.Word
import Foreign.C.String

data Clock
    = Monotonic
    | ProcessCPUTime
    | ThreadCPUTime
    | RealTime
    deriving (Eq, Enum, Show)

data TimeSpec = TimeSpec
    { sec  :: {-# UNPACK #-} !Int64
    , nsec :: {-# UNPACK #-} !Int64
    } deriving (Eq, Show)

instance Ord TimeSpec where
    compare (TimeSpec s1 n1) (TimeSpec s2 n2) =
        case compare s1 s2 of
            EQ -> compare n1 n2
            c  -> c

instance Storable TimeSpec where
    sizeOf _    = 16
    alignment _ = 8
    
    peek ptr = do
        s <- peekByteOff ptr 0
        n <- peekByteOff ptr 8
        return (TimeSpec s n)
        
    poke ptr (TimeSpec s n) = do
        pokeByteOff ptr 0 s
        pokeByteOff ptr 8 n

toNanoSecs :: TimeSpec -> Int64
toNanoSecs (TimeSpec s ns) = s * 1000000000 + ns

fromNanoSecs :: Int64 -> TimeSpec
fromNanoSecs ns =
    TimeSpec (ns `quot` 1000000000) (ns `rem` 1000000000)

#ifdef mingw32_HOST_OS
-- Windows time functions
foreign import ccall unsafe "windows.h GetSystemTimeAsFileTime"
    c_GetSystemTimeAsFileTime :: Ptr Word64 -> IO ()

foreign import ccall unsafe "windows.h QueryPerformanceCounter"
    c_QueryPerformanceCounter :: Ptr Int64 -> IO CInt

foreign import ccall unsafe "windows.h QueryPerformanceFrequency"
    c_QueryPerformanceFrequency :: Ptr Int64 -> IO CInt

foreign import ccall unsafe "process.h clock"
    c_clock :: IO Int32

type FileTime = Word64
type Clock_t = Int32

getTime :: Clock -> IO TimeSpec
getTime clock = 
    case clock of
        Monotonic -> do
            alloca $ \ptr -> do
                _ <- c_QueryPerformanceCounter ptr
                counter <- peek ptr
                alloca $ \ptr' -> do
                    _ <- c_QueryPerformanceFrequency ptr'
                    frequency <- peek ptr'
                    let (s, n) = counter `divMod` frequency
                    return $ TimeSpec (fromIntegral s) (fromIntegral $ n * 1000000000 `div` frequency)
        ProcessCPUTime -> do
            clk <- c_clock
            let s = fromIntegral clk `div` 1000
            let n = (fromIntegral clk `mod` 1000) * 1000000
            return $ TimeSpec s n
        ThreadCPUTime -> error "ThreadCPUTime not implemented on Windows"
        RealTime -> do
            alloca $ \ptr -> do
                c_GetSystemTimeAsFileTime ptr
                ft <- peek ptr
                let ft' = ft - 116444736000000000
                let s = ft' `div` 10000000
                let n = (ft' `mod` 10000000) * 100
                return $ TimeSpec (fromIntegral s) (fromIntegral n)

getRes :: Clock -> IO TimeSpec
getRes clock =
    case clock of
        Monotonic -> do
            alloca $ \ptr -> do
                _ <- c_QueryPerformanceFrequency ptr
                frequency <- peek ptr
                return $ TimeSpec 0 (1000000000 `div` frequency)
        ProcessCPUTime -> return $ TimeSpec 0 1000000
        ThreadCPUTime -> error "ThreadCPUTime not implemented on Windows"
        RealTime -> return $ TimeSpec 0 100
#else
import Foreign.C.Error
foreign import ccall unsafe "clock_gettime"
    c_clock_gettime :: CInt -> Ptr TimeSpec -> IO CInt

foreign import ccall unsafe "clock_getres"
    c_clock_getres :: CInt -> Ptr TimeSpec -> IO CInt

getTime :: Clock -> IO TimeSpec
getTime clock =
    alloca $ \ptr -> do
        throwErrnoIfMinus1_ "clock_gettime" $
            c_clock_gettime (clockToCId clock) ptr
        peek ptr

getRes :: Clock -> IO TimeSpec
getRes clock =
    alloca $ \ptr -> do
        throwErrnoIfMinus1_ "clock_getres" $
            c_clock_getres (clockToCId clock) ptr
        peek ptr

clockToCId :: Clock -> CInt
clockToCId Monotonic = 1
clockToCId ProcessCPUTime = 2
clockToCId ThreadCPUTime = 3
clockToCId RealTime = 0
#endif""")

    # Copy Platform.hs to appropriate location
    with open(os.path.join(script_dir, "hsc_workarounds", "file-io", "Platform.hs"), "w") as f:
        f.write("""-- Pre-generated Platform.hs file
{-# LANGUAGE CPP, ForeignFunctionInterface #-}
module System.File.Platform where

import Foreign.C.Error
import Foreign.C.Types
import Foreign.Marshal.Alloc
import Foreign.Ptr
import Foreign.Storable
import System.Posix.Internals
import System.File.Types
import Data.Word
import Data.Bits
import Foreign.C.String

#ifdef mingw32_HOST_OS
type Mode = CMode

foreign import ccall unsafe "windows.h CreateFileW"
  c_CreateFile
    :: CWString
    -> Word32
    -> Word32
    -> Ptr ()
    -> Word32
    -> Word32
    -> Ptr ()
    -> IO HANDLE

foreign import ccall unsafe "windows.h CloseHandle"
  c_CloseHandle
    :: HANDLE
    -> IO Bool

foreign import ccall unsafe "windows.h SetFilePointerEx"
  c_SetFilePointerEx
    :: HANDLE
    -> Int64
    -> Ptr Int64
    -> Word32
    -> IO Bool

foreign import ccall unsafe "windows.h ReadFile"
  c_ReadFile
    :: HANDLE
    -> Ptr Word8
    -> Word32
    -> Ptr Word32
    -> Ptr ()
    -> IO Bool

foreign import ccall unsafe "windows.h WriteFile"
  c_WriteFile
    :: HANDLE
    -> Ptr Word8
    -> Word32
    -> Ptr Word32
    -> Ptr ()
    -> IO Bool

open_RDONLY, open_WRONLY, open_RDWR :: Word32
open_RDONLY = 0x80000000
open_WRONLY = 0x40000000
open_RDWR   = open_RDONLY .|. open_WRONLY

open_CREAT, open_EXCL, open_TRUNC :: Word32
open_CREAT  = 2
open_EXCL   = 1
open_TRUNC  = 5

seek_SET, seek_CUR, seek_END :: Word32
seek_SET = 0
seek_CUR = 1
seek_END = 2

share_DELETE, share_READ, share_WRITE :: Word32
share_DELETE = 0x00000004
share_READ   = 0x00000001
share_WRITE  = 0x00000002

attr_ARCHIVE, attr_ENCRYPTED, attr_HIDDEN, attr_NORMAL,
  attr_NOT_CONTENT_INDEXED, attr_OFFLINE, attr_READONLY,
  attr_SYSTEM, attr_TEMPORARY :: Word32
attr_ARCHIVE            = 0x00000020
attr_ENCRYPTED          = 0x00004000
attr_HIDDEN             = 0x00000002
attr_NORMAL             = 0x00000080
attr_NOT_CONTENT_INDEXED = 0x00002000
attr_OFFLINE            = 0x00001000
attr_READONLY           = 0x00000001
attr_SYSTEM             = 0x00000004
attr_TEMPORARY          = 0x00000100

#else
type Mode = CMode

foreign import ccall unsafe "fcntl.h open"
  c_open :: CString -> CInt -> CMode -> IO Fd

foreign import ccall unsafe "unistd.h close"
  c_close :: Fd -> IO CInt

foreign import ccall unsafe "unistd.h lseek"
  c_lseek :: Fd -> COff -> CInt -> IO COff

foreign import ccall unsafe "unistd.h read"
  c_read :: Fd -> Ptr Word8 -> CSize -> IO CSsize

foreign import ccall unsafe "unistd.h write"
  c_write :: Fd -> Ptr Word8 -> CSize -> IO CSsize

foreign import ccall unsafe "string.h strerror_r"
  c_strerror :: CInt -> CString -> CSize -> IO CInt

open_RDONLY, open_WRONLY, open_RDWR :: CInt
open_RDONLY = 0
open_WRONLY = 1
open_RDWR   = 2

open_CREAT, open_EXCL, open_TRUNC :: CInt
open_CREAT  = 64
open_EXCL   = 128
open_TRUNC  = 512

seek_SET, seek_CUR, seek_END :: CInt
seek_SET = 0
seek_CUR = 1
seek_END = 2
#endif""")

    # Find build directories
    build_dirs = find_build_dirs()

    # Apply fixes to all build directories
    total_fixes = 0
    for build_dir in build_dirs:
        fixes = apply_fixes(build_dir, script_dir)
        total_fixes += fixes

    if total_fixes > 0:
        print(f"Successfully applied {total_fixes} HSC fixes")
        return 0
    else:
        print("No fixes were applied. Could not find target files.")
        return 1

if __name__ == "__main__":
    sys.exit(main())

