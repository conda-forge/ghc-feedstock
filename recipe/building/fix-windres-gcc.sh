#!/usr/bin/env bash
set -eu

echo "=== Fixing windres.exe to use clang instead of gcc ==="

# Find the windres.exe location
WINDRES_PATH=$(find "${PREFIX}" -name "windres.exe" -type f | head -1)
if [[ -z "$WINDRES_PATH" ]]; then
    echo "windres.exe not found in PREFIX, checking BUILD_PREFIX..."
    WINDRES_PATH=$(find "${BUILD_PREFIX}" -name "windres.exe" -type f | head -1)
fi

if [[ -z "$WINDRES_PATH" ]]; then
    echo "windres.exe not found, looking in common locations..."
    WINDRES_PATH=$(find "/c" -name "windres.exe" -type f 2>/dev/null | grep -E "(mingw|gcc|llvm)" | head -1 || echo "")
fi

if [[ -n "$WINDRES_PATH" ]]; then
    echo "Found windres.exe at: $WINDRES_PATH"
    WINDRES_DIR=$(dirname "$WINDRES_PATH")
else
    echo "windres.exe not found, using default location"
    WINDRES_DIR="${BUILD_PREFIX}/Library/x86_64-w64-mingw32/bin"
fi

# Find clang.exe location
CLANG_PATH=$(find "${BUILD_PREFIX}" -name "clang.exe" -type f | head -1)
if [[ -z "$CLANG_PATH" ]]; then
    echo "Error: clang.exe not found in BUILD_PREFIX"
    exit 1
fi

echo "Found clang.exe at: $CLANG_PATH"
CLANG_DIR=$(dirname "$CLANG_PATH")

# Method 1: Create a gcc.exe symlink/wrapper that points to clang
echo "Creating gcc.exe wrapper that calls clang..."
cat > "${WINDRES_DIR}/gcc.exe" << EOF
#!/bin/bash
# GCC wrapper that calls clang for windres compatibility
exec "${CLANG_PATH}" "\$@"
EOF

# Also create it as a batch file for Windows compatibility
cat > "${WINDRES_DIR}/gcc.bat" << 'EOF'
@echo off
REM GCC wrapper that calls clang for windres compatibility
"%CLANG_PATH%" %*
EOF

chmod +x "${WINDRES_DIR}/gcc.exe"

# Method 2: Create a custom windres wrapper that sets the preprocessor
echo "Creating windres wrapper that explicitly uses clang..."
mv "${WINDRES_PATH}" "${WINDRES_PATH}.original" 2>/dev/null || true

cat > "${WINDRES_PATH}" << EOF
#!/bin/bash
# Windres wrapper that uses clang as preprocessor

# Set environment variables to force windres to use clang
export CC="${CLANG_PATH}"
export CPP="${CLANG_PATH} -E"

# Call the original windres with clang as preprocessor
exec "${WINDRES_PATH}.original" --preprocessor="${CLANG_PATH} -E -xc-header -DRC_INVOKED" "\$@"
EOF

chmod +x "${WINDRES_PATH}"

# Method 3: Set environment variables globally
echo "Setting global environment variables for windres..."
export CC="${CLANG_PATH}"
export CPP="${CLANG_PATH} -E"

# Create a script to set these environment variables for the build
cat > "${BUILD_PREFIX}/bin/set-windres-env.sh" << EOF
#!/bin/bash
# Set environment variables for windres to use clang
export CC="${CLANG_PATH}"
export CPP="${CLANG_PATH} -E"
export WINDRES_CC="${CLANG_PATH}"
export WINDRES_CPP="${CLANG_PATH} -E"

# Also set PATH to include clang directory first
export PATH="${CLANG_DIR}:\$PATH"

echo "Environment configured for windres to use clang"
echo "CC=\$CC"
echo "CPP=\$CPP"
EOF

chmod +x "${BUILD_PREFIX}/bin/set-windres-env.sh"

# Method 4: Create a comprehensive PATH setup
echo "Adding clang directory to PATH and creating additional symlinks..."

# Create additional symlinks in the windres directory
ln -sf "${CLANG_PATH}" "${WINDRES_DIR}/x86_64-w64-mingw32-gcc.exe" 2>/dev/null || true
ln -sf "${CLANG_PATH}" "${WINDRES_DIR}/mingw32-gcc.exe" 2>/dev/null || true

# Add clang directory to PATH
export PATH="${CLANG_DIR}:${PATH}"

echo "Windres gcc fix completed successfully!"
echo "Methods applied:"
echo "1. Created gcc.exe wrapper in windres directory: ${WINDRES_DIR}/gcc.exe"
echo "2. Created windres wrapper that uses clang: ${WINDRES_PATH}"
echo "3. Set CC and CPP environment variables"
echo "4. Created additional gcc symlinks for different architectures"
echo ""
echo "To use these fixes, source the environment script:"
echo "source ${BUILD_PREFIX}/bin/set-windres-env.sh"