#!/usr/bin/env bash
# Wrapper for ld.bfd that automatically adds crt2.o for console applications
# This solves the GUI vs console startup conflict on Windows

# Find the real ld.bfd
REAL_LD="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.bfd"
if [ ! -f "${REAL_LD}" ]; then
    REAL_LD="${BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.bfd"
fi

# CRT startup file
CRT2_OBJ="${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib/crt2.o"
if [ ! -f "${CRT2_OBJ}" ]; then
    CRT2_OBJ="${BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib/crt2.o"
fi

# Check if this is a link operation (not just generating object files)
# Link operations typically have -o <output> and various libraries
IS_LINK=0
for arg in "$@"; do
    case "$arg" in
        -l*|*.a|*.lib) IS_LINK=1; break ;;
    esac
done

if [ "$IS_LINK" -eq 1 ]; then
    # For link operations, prepend crt2.o to ensure console startup
    exec "${REAL_LD}" "${CRT2_OBJ}" "$@"
else
    # For other operations, pass through unchanged
    exec "${REAL_LD}" "$@"
fi
