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

