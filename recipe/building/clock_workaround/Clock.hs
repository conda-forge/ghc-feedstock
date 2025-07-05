{-# LANGUAGE CPP, ForeignFunctionInterface #-}

-- This is a pre-generated version of Clock.hs to work around HSC2HS build issues on Windows

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
            alloca $ \ptr -> do
                _ <- c_QueryPerformanceFrequency ptr
                frequency <- peek ptr
                return $ TimeSpec 0 (1000000000 `div` frequency)
        ProcessCPUTime -> return $ TimeSpec 0 1000000  -- millisecond resolution
        ThreadCPUTime -> error "ThreadCPUTime not implemented on Windows"
        RealTime -> return $ TimeSpec 0 100  -- 100ns resolution

#else
-- POSIX implementation (included for completeness but won't be used on Windows)
-- ...implementation for POSIX clocks would go here...
#endif

