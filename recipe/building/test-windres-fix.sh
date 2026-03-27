#!/usr/bin/env bash
set -eu

echo "=== Testing windres gcc fix ==="

# Test 1: Check if gcc command is available
echo "Test 1: Checking if gcc is available..."
if which gcc.exe >/dev/null 2>&1; then
    echo "✓ gcc.exe found at: $(which gcc.exe)"
    echo "  gcc version: $(gcc.exe --version 2>/dev/null | head -1 || echo 'Version check failed')"
else
    echo "✗ gcc.exe not found in PATH"
fi

# Test 2: Basic environment check
if [[ -z "${CC:-}" ]]; then
    echo "Warning: CC environment variable not set"
fi

# Test 3: Check if windres can find a preprocessor
echo "Test 3: Testing windres..."
WINDRES_PATH=$(find "${BUILD_PREFIX}" -name "windres.exe" -type f | head -1)
if [[ -n "$WINDRES_PATH" ]]; then
    echo "Found windres at: $WINDRES_PATH"
    
    # Create a minimal test .rc file
    TEST_RC=$(mktemp --suffix=.rc)
    TEST_O=$(mktemp --suffix=.o)
    
    cat > "$TEST_RC" << 'EOF'
#include <windows.h>
1 VERSIONINFO
FILEVERSION 1,0,0,0
PRODUCTVERSION 1,0,0,0
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904B0"
        BEGIN
            VALUE "FileDescription", "Test"
            VALUE "FileVersion", "1.0.0.0"
        END
    END
END
EOF
    
    echo "Testing windres with minimal .rc file..."
    if "$WINDRES_PATH" --input="$TEST_RC" --output="$TEST_O" --output-format=coff 2>&1; then
        echo "✓ windres test successful"
        rm -f "$TEST_O"
    else
        echo "✗ windres test failed"
    fi
    
    rm -f "$TEST_RC"
else
    echo "windres.exe not found for testing"
fi

# Test 4: Check PATH
echo ""
echo "Test 4: Checking PATH for clang directory..."
CLANG_PATH=$(find "${BUILD_PREFIX}" -name "clang.exe" -type f | head -1)
if [[ -n "$CLANG_PATH" ]]; then
    CLANG_DIR=$(dirname "$CLANG_PATH")
    if echo "$PATH" | grep -q "$CLANG_DIR"; then
        echo "✓ Clang directory is in PATH: $CLANG_DIR"
    else
        echo "✗ Clang directory not in PATH: $CLANG_DIR"
    fi
else
    echo "clang.exe not found"
fi

echo ""
echo "Windres fix test completed"