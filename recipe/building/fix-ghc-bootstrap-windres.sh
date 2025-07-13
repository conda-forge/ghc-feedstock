#!/usr/bin/env bash
set -eu

echo "=== Fixing windres for GHC bootstrap build ==="

# Find clang
CLANG_PATH=$(find "${BUILD_PREFIX}" -name "clang.exe" -type f | head -1)
if [[ -z "$CLANG_PATH" ]]; then
    echo "Error: clang.exe not found"
    exit 1
fi

echo "Using clang at: $CLANG_PATH"

# Method 1: Add clang directory to PATH and create gcc symlink
CLANG_DIR=$(dirname "$CLANG_PATH")
export PATH="${CLANG_DIR}:${PATH}"

# Create gcc.exe in the clang directory if it doesn't exist
if [[ ! -f "${CLANG_DIR}/gcc.exe" ]]; then
    echo "Creating gcc.exe symlink to clang.exe"
    ln -sf "$(basename "$CLANG_PATH")" "${CLANG_DIR}/gcc.exe" || {
        # If symlink fails, create a wrapper script
        cat > "${CLANG_DIR}/gcc.exe" << EOF
#!/bin/bash
exec "${CLANG_PATH}" "\$@"
EOF
        chmod +x "${CLANG_DIR}/gcc.exe"
    }
fi

# Method 2: Set environment variables that windres will use
export CC="${CLANG_PATH}"
export CPP="${CLANG_PATH} -E"

# Method 3: Create platform-specific gcc symlinks
ln -sf "$(basename "$CLANG_PATH")" "${CLANG_DIR}/x86_64-w64-mingw32-gcc.exe" 2>/dev/null || true
ln -sf "$(basename "$CLANG_PATH")" "${CLANG_DIR}/mingw32-gcc.exe" 2>/dev/null || true

# Method 4: Create gcc in commonly searched locations
mkdir -p "${BUILD_PREFIX}/bin"
if [[ ! -f "${BUILD_PREFIX}/bin/gcc.exe" ]]; then
    ln -sf "${CLANG_PATH}" "${BUILD_PREFIX}/bin/gcc.exe" || {
        cat > "${BUILD_PREFIX}/bin/gcc.exe" << EOF
#!/bin/bash
exec "${CLANG_PATH}" "\$@"
EOF
        chmod +x "${BUILD_PREFIX}/bin/gcc.exe"
    }
fi

# Method 5: Create a wrapper that can be sourced before GHC operations
cat > "${BUILD_PREFIX}/bin/ghc-bootstrap-env.sh" << EOF
#!/bin/bash
# Environment setup for GHC bootstrap builds

# Add clang to PATH
export PATH="${CLANG_DIR}:\${PATH}"

# Set compiler environment variables
export CC="${CLANG_PATH}"
export CXX="${CLANG_PATH}++"
export CPP="${CLANG_PATH} -E"

# Set windres-specific environment variables
export WINDRES_CC="${CLANG_PATH}"
export WINDRES_CPP="${CLANG_PATH} -E"

echo "GHC bootstrap environment configured:"
echo "  CC=\$CC"
echo "  CPP=\$CPP"
echo "  PATH includes: ${CLANG_DIR}"
EOF

chmod +x "${BUILD_PREFIX}/bin/ghc-bootstrap-env.sh"

echo "GHC bootstrap windres fix completed!"
echo ""
echo "Solutions applied:"
echo "1. Added clang directory to PATH: ${CLANG_DIR}"
echo "2. Created gcc.exe -> clang.exe symlink/wrapper"
echo "3. Set CC and CPP environment variables"
echo "4. Created platform-specific gcc symlinks"
echo "5. Created environment setup script: ${BUILD_PREFIX}/bin/ghc-bootstrap-env.sh"
echo ""
echo "To verify, run: which gcc"
echo "Should show: ${CLANG_DIR}/gcc.exe"