#!/usr/bin/env python
"""
Direct fix for HSC tool crashes in Windows GHC build.
This script replaces problematic HSC-generated files with pre-generated versions.
"""
import os
import sys
import glob
import re
import shutil

# Pre-generated content for System/Clock.hs (fixed escape sequences)
CLOCK_HS_CONTENT = r'''
{-# LANGUAGE CPP, ForeignFunctionInterface #-}

-- Pre-generated version of Clock.hs to avoid HSC2HS tool crashes on Windows

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

data Clock
    = Monotonic
    -- ^ A monotonic, non-adjustable clock that is not affected by
    -- discontinuous jumps in the system time. This is often the
    -- system's best clock for performance measurement.
    | ProcessCPUTime
    -- ^ The CPU time used by the calling process.
    | ThreadCPUTime
    -- ^ The CPU time used by the calling thread.
    | RealTime
    -- ^ The system's real-time clock. This clock can be affected by
    -- discontinuous jumps in the system time.
    deriving (Eq, Enum, Show)

data TimeSpec = TimeSpec
    { sec  :: {-# UNPACK #-} !Int64
    -- ^ Number of seconds.
    , nsec :: {-# UNPACK #-} !Int64
    -- ^ Number of nanoseconds.
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

-- | Returns the number of nanoseconds in the 'TimeSpec'.
toNanoSecs :: TimeSpec -> Int64
toNanoSecs (TimeSpec s ns) = s * 1000000000 + ns

-- | Constructs a 'TimeSpec' from a number of nanoseconds.
fromNanoSecs :: Int64 -> TimeSpec
fromNanoSecs ns =
    TimeSpec (ns `quot` 1000000000) (ns `rem` 1000000000)

-- Windows implementation
#ifdef mingw32_HOST_OS
import Data.Word
import Foreign.C.String

-- Windows time functions
foreign import ccall unsafe "windows.h GetSystemTimeAsFileTime"
    c_GetSystemTimeAsFileTime :: Ptr FileTime -> IO ()

foreign import ccall unsafe "windows.h QueryPerformanceCounter"
    c_QueryPerformanceCounter :: Ptr Int64 -> IO CInt

foreign import ccall unsafe "windows.h QueryPerformanceFrequency"
    c_QueryPerformanceFrequency :: Ptr Int64 -> IO CInt

foreign import ccall unsafe "process.h clock"
    c_clock :: IO Clock_t

-- Windows data types
type FileTime = Word64
type Clock_t = Int32

-- | Get the current value of the given 'Clock'.
getTime :: Clock -> IO TimeSpec
getTime clock = 
    case clock of
        Monotonic -> do
            alloca $ \p -> do
                _ <- c_QueryPerformanceCounter p
                counter <- peek p
                alloca $ \p' -> do
                    _ <- c_QueryPerformanceFrequency p'
                    frequency <- peek p'
                    let (s, n) = counter `divMod` frequency
                    return $ TimeSpec (fromIntegral s) (fromIntegral $ n * 1000000000 `div` frequency)
        ProcessCPUTime -> do
            clk <- c_clock
            let s = fromIntegral clk `div` 1000
            let n = (fromIntegral clk `mod` 1000) * 1000000
            return $ TimeSpec s n
        ThreadCPUTime -> error "ThreadCPUTime not implemented on Windows"
        RealTime -> do
            alloca $ \p -> do
                c_GetSystemTimeAsFileTime p
                ft <- peek p
                -- Windows file time is 100ns intervals since 1601-01-01
                -- Need to convert to unix epoch (1970-01-01)
                let ft' = ft - 116444736000000000
                let s = ft' `div` 10000000
                let n = (ft' `mod` 10000000) * 100
                return $ TimeSpec (fromIntegral s) (fromIntegral n)

-- | Get the resolution of the given 'Clock'.
getRes :: Clock -> IO TimeSpec
getRes clock =
    case clock of
        Monotonic -> do
            alloca $ \p -> do
                _ <- c_QueryPerformanceFrequency p
                frequency <- peek p
                return $ TimeSpec 0 (1000000000 `div` frequency)
        ProcessCPUTime -> return $ TimeSpec 0 1000000  -- millisecond resolution
        ThreadCPUTime -> error "ThreadCPUTime not implemented on Windows"
        RealTime -> return $ TimeSpec 0 100  -- 100ns resolution

#else
-- POSIX implementation
import Foreign.C.Error

-- POSIX clock values
monotonic, process_cputime, thread_cputime, realtime :: CInt
monotonic = 1
process_cputime = 2
thread_cputime = 3
realtime = 0

foreign import ccall unsafe "clock_gettime"
    c_clock_gettime :: CInt -> Ptr TimeSpec -> IO CInt

foreign import ccall unsafe "clock_getres"
    c_clock_getres :: CInt -> Ptr TimeSpec -> IO CInt

-- | Get the current value of the given 'Clock'.
getTime :: Clock -> IO TimeSpec
getTime clock =
    alloca $ \p -> do
        throwErrnoIfMinus1_ "clock_gettime" $
            c_clock_gettime (clockToCId clock) p
        peek p

-- | Get the resolution of the given 'Clock'.
getRes :: Clock -> IO TimeSpec
getRes clock =
    alloca $ \p -> do
        throwErrnoIfMinus1_ "clock_getres" $
            c_clock_getres (clockToCId clock) p
        peek p

clockToCId :: Clock -> CInt
clockToCId Monotonic = monotonic
clockToCId ProcessCPUTime = process_cputime
clockToCId ThreadCPUTime = thread_cputime
clockToCId RealTime = realtime
#endif
'''

# Pre-generated content for System/File/Platform.hs
PLATFORM_HS_CONTENT = r'''
{-# LANGUAGE CPP, ForeignFunctionInterface #-}

-- Pre-generated version of Platform.hs to avoid HSC2HS tool crashes on Windows

module System.File.Platform where

import Foreign.C.Error
import Foreign.C.Types
import Foreign.Marshal.Alloc
import Foreign.Ptr
import Foreign.Storable
import System.Posix.Internals
import System.File.Types

#ifdef mingw32_HOST_OS
import Data.Word
import Data.Bits
import Foreign.C.String

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

-- | File mode for open.
open_RDONLY, open_WRONLY, open_RDWR :: Word32
open_RDONLY = 0x80000000  -- FILE_GENERIC_READ
open_WRONLY = 0x40000000  -- FILE_GENERIC_WRITE
open_RDWR   = open_RDONLY .|. open_WRONLY

-- | File open actions.
open_CREAT, open_EXCL, open_TRUNC :: Word32
open_CREAT  = 2  -- FILE_CREATE
open_EXCL   = 1  -- FILE_CREATE_NEW
open_TRUNC  = 5  -- FILE_OVERWRITE_IF

-- | Seek modes.
seek_SET, seek_CUR, seek_END :: Word32
seek_SET = 0  -- FILE_BEGIN
seek_CUR = 1  -- FILE_CURRENT
seek_END = 2  -- FILE_END

-- | Share modes.
share_DELETE, share_READ, share_WRITE :: Word32
share_DELETE = 0x00000004  -- FILE_SHARE_DELETE
share_READ   = 0x00000001  -- FILE_SHARE_READ
share_WRITE  = 0x00000002  -- FILE_SHARE_WRITE

-- | File attributes.
attr_ARCHIVE, attr_ENCRYPTED, attr_HIDDEN, attr_NORMAL,
  attr_NOT_CONTENT_INDEXED, attr_OFFLINE, attr_READONLY,
  attr_SYSTEM, attr_TEMPORARY :: Word32
attr_ARCHIVE            = 0x00000020  -- FILE_ATTRIBUTE_ARCHIVE
attr_ENCRYPTED          = 0x00004000  -- FILE_ATTRIBUTE_ENCRYPTED
attr_HIDDEN             = 0x00000002  -- FILE_ATTRIBUTE_HIDDEN
attr_NORMAL             = 0x00000080  -- FILE_ATTRIBUTE_NORMAL
attr_NOT_CONTENT_INDEXED = 0x00002000  -- FILE_ATTRIBUTE_NOT_CONTENT_INDEXED
attr_OFFLINE            = 0x00001000  -- FILE_ATTRIBUTE_OFFLINE
attr_READONLY           = 0x00000001  -- FILE_ATTRIBUTE_READONLY
attr_SYSTEM             = 0x00000004  -- FILE_ATTRIBUTE_SYSTEM
attr_TEMPORARY          = 0x00000100  -- FILE_ATTRIBUTE_TEMPORARY

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

-- | File mode for open.
open_RDONLY, open_WRONLY, open_RDWR :: CInt
open_RDONLY = 0  -- O_RDONLY
open_WRONLY = 1  -- O_WRONLY
open_RDWR   = 2  -- O_RDWR

-- | File open actions.
open_CREAT, open_EXCL, open_TRUNC :: CInt
open_CREAT  = 64    -- O_CREAT
open_EXCL   = 128   -- O_EXCL
open_TRUNC  = 512   -- O_TRUNC

-- | Seek modes.
seek_SET, seek_CUR, seek_END :: CInt
seek_SET = 0  -- SEEK_SET
seek_CUR = 1  -- SEEK_CUR
seek_END = 2  -- SEEK_END
#endif
'''

def find_target_files(search_paths, clock_content, platform_content, verbose=True):
    """Find all target files in the given search paths"""
    # Target files to look for
    targets = {
        "System/Clock.hs": clock_content,
        "System/File/Platform.hs": platform_content
    }

    if verbose:
        print(f"Searching for target files: {list(targets.keys())}")

    results = []
    seen_dirs = set()  # Track directories we've already found
    
    for search_path in search_paths:
        # Replace environment variables
        expanded_path = os.path.expandvars(search_path)
        if not os.path.exists(expanded_path):
            if verbose:
                print(f"Path does not exist: {expanded_path}")
            continue

        if verbose:
            print(f"Searching in: {expanded_path}")

        # Look for build directories that might contain our targets
        for target_file in targets.keys():
            # Try to find the target file or its parent directory
            target_patterns = [
                # Standard dist/build patterns
                os.path.join(expanded_path, "**", "dist*", "build", target_file),
                os.path.join(expanded_path, "**", "dist*", "build", "*", target_file),
                os.path.join(expanded_path, "**", "build", target_file),
                os.path.join(expanded_path, "**", "build", "*", target_file),
                # Also look for the parent directory
                os.path.join(expanded_path, "**", "dist*", "build", os.path.dirname(target_file)),
                os.path.join(expanded_path, "**", "build", os.path.dirname(target_file)),
                # Look specifically in clock and file-io package directories
                os.path.join(expanded_path, "**", "clock-*", "**", target_file),
                os.path.join(expanded_path, "**", "file-io-*", "**", target_file),
                # More specific Cabal store patterns
                os.path.join(expanded_path, "clock-*", "dist", "build", target_file),
                os.path.join(expanded_path, "file-io-*", "dist", "build", target_file),
                os.path.join(expanded_path, "clock-*", "dist", "build", "System", "Clock.hs"),
                os.path.join(expanded_path, "file-io-*", "dist", "build", "System", "File", "Platform.hs"),
            ]

            for pattern in target_patterns:
                matches = glob.glob(pattern, recursive=True)
                for match in matches:
                    # For matches that are directories, check if they're the right ones
                    if os.path.isdir(match):
                        if os.path.basename(match) in ["System", "File"]:
                            # Found a parent directory - use it to create the full path
                            file_path = os.path.join(match, os.path.basename(target_file))
                            dir_path = match
                            norm_dir = os.path.normpath(dir_path).lower()
                            
                            if norm_dir in seen_dirs:
                                continue
                            seen_dirs.add(norm_dir)
                            
                            if verbose:
                                print(f"Found target directory: {dir_path}")

                            if os.path.exists(file_path):
                                if verbose:
                                    print(f"Target file already exists: {file_path}")

                            # The parent directory exists, add it to the results
                            results.append((target_file, dir_path, targets[target_file]))
                    elif os.path.exists(match):
                        # Found the exact file
                        dir_path = os.path.dirname(match)
                        norm_dir = os.path.normpath(dir_path).lower()
                        
                        if norm_dir in seen_dirs:
                            continue
                        seen_dirs.add(norm_dir)
                        
                        if verbose:
                            print(f"Found existing target file: {match}")
                        results.append((target_file, dir_path, targets[target_file]))

    return results

def patch_makefile(dir_path, target_file, verbose=True):
    """Patch the Makefile to skip HSC tool execution"""
    # Look for Makefile in the directory
    makefile = os.path.join(dir_path, "Makefile")
    if not os.path.exists(makefile):
        if verbose:
            print(f"No Makefile found at {makefile}")
        return False

    target_base = os.path.basename(target_file)
    hsc_file = target_base.replace(".hs", ".hsc")
    hsc_tool = target_base.replace(".hs", "_hsc_make.exe")

    if verbose:
        print(f"Patching Makefile at {makefile} for {target_file}")

    try:
        with open(makefile, "r", errors="replace") as f:
            content = f.read()

        # Create backup if it doesn't exist
        backup_path = f"{makefile}.bak"
        if not os.path.exists(backup_path):
            shutil.copy2(makefile, backup_path)
            if verbose:
                print(f"Created backup: {backup_path}")

        # Try to find the HSC rule
        patterns = [
            f"{target_base}: {hsc_file} {hsc_tool}\n\t{hsc_tool}",
            f"{target_base}: {hsc_file} {hsc_tool}\r\n\t{hsc_tool}",
            f"{target_base}: {hsc_file} {hsc_tool}\n\t./{hsc_tool}",
            f"{target_base}: {hsc_file} {hsc_tool}\r\n\t./{hsc_tool}",
        ]

        replacement = f"{target_base}: {hsc_file}\n\t@echo Using pre-generated {target_base}"
        modified = False

        for pattern in patterns:
            if pattern in content:
                content = content.replace(pattern, replacement)
                modified = True
                break

        # If the exact pattern wasn't found, try a regex approach
        if not modified:
            pattern = re.escape(f"{target_base}: {hsc_file} {hsc_tool}") + r'\s*\n\s*' + re.escape(hsc_tool)
            new_content = re.sub(pattern, replacement, content)
            if new_content != content:
                content = new_content
                modified = True

        if modified:
            with open(makefile, "w") as f:
                f.write(content)
            if verbose:
                print(f"Successfully patched {makefile}")
            return True
        else:
            if verbose:
                print(f"No matching HSC rule found in {makefile}")
            return False
    except Exception as e:
        if verbose:
            print(f"Error patching Makefile {makefile}: {e}")
        return False

def create_file(target_file, dir_path, content, verbose=True):
    """Create the target file with the given content"""
    full_path = os.path.join(dir_path, os.path.basename(target_file))
    try:
        if verbose:
            print(f"Creating {full_path}")
        with open(full_path, "w", encoding="utf-8") as f:
            f.write(content.strip())
        return True
    except Exception as e:
        if verbose:
            print(f"Error creating {full_path}: {e}")
        return False

def load_workaround_file(relative_path):
    """Load content from workaround file in recipe directory"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Try multiple potential locations for the workaround files
    potential_paths = [
        # Same directory as script (original location)
        os.path.join(script_dir, "hsc_workarounds", relative_path),
        # Recipe directory (when script is copied elsewhere)
        os.path.join(os.path.expandvars("${RECIPE_DIR}"), "building", "hsc_workarounds", relative_path),
        # Fallback to environment variable
        os.path.join(os.environ.get("RECIPE_DIR", ""), "building", "hsc_workarounds", relative_path)
    ]
    
    for workaround_path in potential_paths:
        if os.path.exists(workaround_path):
            print(f"Loading workaround file from: {workaround_path}")
            with open(workaround_path, "r", encoding="utf-8") as f:
                return f.read()
    
    print(f"Warning: Workaround file not found in any of these paths:")
    for path in potential_paths:
        print(f"  - {path}")
    return None

def main():
    """Main entry point"""
    print("Direct HSC Fixer - Bypassing HSC tools")

    # Load workaround files from recipe directory
    clock_content = load_workaround_file("clock/System/Clock.hs")
    platform_content = load_workaround_file("file-io/System/File/Platform.hs")
    
    if not clock_content:
        print("Using fallback Clock.hs content")
        clock_content = CLOCK_HS_CONTENT
    if not platform_content:
        print("Using fallback Platform.hs content") 
        platform_content = PLATFORM_HS_CONTENT

    # Use the loaded content from workaround files

    # Default search paths - more comprehensive search
    search_paths = [
        "C:/cabal",
        "C:/cabal/store",
        "C:/cabal/store/ghc-9.10.1",
        os.path.expanduser("~") + "/AppData/Local/Temp",
        os.path.expandvars("%APPDATA%") + "/cabal",
        os.path.expandvars("%SRC_DIR%"),
        os.path.expandvars("%BUILD_PREFIX%"),
        os.path.expandvars("%BUILD_PREFIX%") + "/../work",
        ".",
        "..",
        # More comprehensive Cabal store search
        "C:/cabal/store/ghc-9.10.1/clock-0.8.4*",
        "C:/cabal/store/ghc-9.10.1/file-io-0.1.4*",
    ]

    # Add command-line arguments as search paths
    if len(sys.argv) > 1:
        search_paths.extend(sys.argv[1:])

    # Find all target files in the search paths
    targets = find_target_files(search_paths, clock_content, platform_content)

    if not targets:
        print("No target files found! Here are more details about the search paths:")
        for path in search_paths:
            expanded = os.path.expandvars(path)
            if os.path.exists(expanded):
                print(f"Path exists: {expanded}")
                contents = os.listdir(expanded)
                print(f"  Contents: {contents[:5]}{'...' if len(contents) > 5 else ''}")
            else:
                print(f"Path does not exist: {expanded}")

        # Last resort - try direct paths and also search dynamically
        print("Searching for Cabal store directories dynamically...")
        direct_paths = []
        
        # First try to find the actual Cabal store directories
        cabal_store_base = "C:/cabal/store/ghc-9.10.1"
        if os.path.exists(cabal_store_base):
            for item in os.listdir(cabal_store_base):
                if item.startswith("clock-"):
                    clock_path = os.path.join(cabal_store_base, item, "dist", "build", "System")
                    direct_paths.append(clock_path)
                    print(f"Found clock directory: {clock_path}")
                elif item.startswith("file-io-"):
                    file_io_path = os.path.join(cabal_store_base, item, "dist", "build", "System", "File")
                    direct_paths.append(file_io_path)
                    print(f"Found file-io directory: {file_io_path}")
        
        # Also try the known paths from hadrian plan
        direct_paths.extend([
            "C:/cabal/store/ghc-9.10.1/clock-0.8.4-eb0ebbe55e474fb9e033017098f5e645eb60d91a974ed9850a52ed14211e031d/dist/build/System",
            "C:/cabal/store/ghc-9.10.1/file-io-0.1.4-2900bd4050e8ac2583e3044a5989d1df306fdce7/dist/build/System/File"
        ])

        print("Trying direct paths:")
        for path in direct_paths:
            try:
                # Create the directory if it doesn't exist
                if not os.path.exists(path):
                    print(f"Creating directory: {path}")
                    os.makedirs(path, exist_ok=True)
                
                print(f"Processing path: {path}")
                if "clock" in path.lower():
                    success = create_file("Clock.hs", path, clock_content)
                    if success:
                        print(f"Successfully created Clock.hs in {path}")
                        patch_makefile(path, "Clock.hs")
                elif "file-io" in path.lower():
                    success = create_file("Platform.hs", path, platform_content)
                    if success:
                        print(f"Successfully created Platform.hs in {path}")
                        patch_makefile(path, "Platform.hs")
            except Exception as e:
                print(f"Error processing {path}: {e}")
                continue

        return 1

    # Apply fixes - deduplicate by directory path
    fixes_applied = 0
    processed_paths = set()
    
    for target_file, dir_path, content in targets:
        # Normalize the path to avoid duplicates
        norm_path = os.path.normpath(dir_path).lower()
        
        if norm_path in processed_paths:
            print(f"Skipping duplicate: {target_file} in {dir_path} (already processed)")
            continue
            
        processed_paths.add(norm_path)
        print(f"Fixing {target_file} in {dir_path}")

        # Create the file
        if create_file(target_file, dir_path, content):
            fixes_applied += 1

            # Patch the Makefile to skip HSC tool execution
            patch_makefile(dir_path, target_file)

    if fixes_applied > 0:
        print(f"Successfully applied {fixes_applied} HSC fixes")
        return 0
    else:
        print("No fixes were applied.")
        return 1

if __name__ == "__main__":
    sys.exit(main())

