#!/bin/bash
# Diagnostic script to test ar/ld permutations and identify real issue
# Run this on the macOS runner after build starts failing

set -x

echo "=== Testing ar/ld permutations ==="

# Locate the tools
CONDA_AR="${BUILD_PREFIX}/bin/x86_64-apple-darwin13.4.0-ar"
CONDA_LD="${BUILD_PREFIX}/bin/x86_64-apple-darwin13.4.0-ld"
SYSTEM_AR="/usr/bin/ar"
SYSTEM_LD="/usr/bin/ld"
CC="${BUILD_PREFIX}/bin/x86_64-apple-darwin13.4.0-clang"

# Create test object file
cat > /tmp/permtest.c << 'EOF'
int test_function(void) { return 42; }
EOF

${CC} -c /tmp/permtest.c -o /tmp/permtest.o -mmacosx-version-min=10.13

echo "=== Test 1: CONDA ar + CONDA ld ==="
${CONDA_AR} rcs /tmp/test_conda_conda.a /tmp/permtest.o
file /tmp/test_conda_conda.a
head -c 80 /tmp/test_conda_conda.a | od -An -tx1
${CONDA_LD} -dylib -arch x86_64 -o /tmp/test_conda_conda.dylib /tmp/test_conda_conda.a 2>&1 | head -10
echo "Exit code: $?"

echo "=== Test 2: SYSTEM ar + CONDA ld ==="
${SYSTEM_AR} rcs /tmp/test_system_conda.a /tmp/permtest.o
file /tmp/test_system_conda.a
head -c 80 /tmp/test_system_conda.a | od -An -tx1
${CONDA_LD} -dylib -arch x86_64 -o /tmp/test_system_conda.dylib /tmp/test_system_conda.a 2>&1 | head -10
echo "Exit code: $?"

echo "=== Test 3: CONDA ar + SYSTEM ld ==="
${SYSTEM_LD} -dylib -arch x86_64 -o /tmp/test_conda_system.dylib /tmp/test_conda_conda.a 2>&1 | head -10
echo "Exit code: $?"

echo "=== Test 4: SYSTEM ar + SYSTEM ld ==="
${SYSTEM_LD} -dylib -arch x86_64 -o /tmp/test_system_system.dylib /tmp/test_system_conda.a 2>&1 | head -10
echo "Exit code: $?"

echo "=== Now test with FAILING archive from cabal store ==="
FAILING_AR="/Users/runner/.local/state/cabal/store/ghc-9.6.7/tf8-strng-1.0.2-7159478e/lib/libHStf8-strng-1.0.2-7159478e.a"

if [[ -f "$FAILING_AR" ]]; then
    echo "=== Analyzing failing archive: $FAILING_AR ==="
    file "$FAILING_AR"
    head -c 80 "$FAILING_AR" | od -An -tx1
    ${CONDA_AR} -t "$FAILING_AR" | head -10

    echo "=== Compare with WORKING archive ==="
    WORKING_AR="/Users/runner/.local/state/cabal/store/ghc-9.6.7/shk-0.19.8-75e1853c/lib/libHSshk-0.19.8-75e1853c.a"
    if [[ -f "$WORKING_AR" ]]; then
        file "$WORKING_AR"
        head -c 80 "$WORKING_AR" | od -An -tx1
        ${CONDA_AR} -t "$WORKING_AR" | head -10
    fi

    echo "=== Extract and rebuild failing archive with conda ar ==="
    mkdir -p /tmp/repack
    cd /tmp/repack
    ${SYSTEM_AR} -x "$FAILING_AR" 2>&1 || ${CONDA_AR} -x "$FAILING_AR" 2>&1
    ls -la
    ${CONDA_AR} rcs /tmp/repacked.a *.o 2>&1
    file /tmp/repacked.a

    echo "=== Try linking repacked archive ==="
    ${CONDA_LD} -dylib -arch x86_64 -o /tmp/repacked.dylib /tmp/repacked.a 2>&1 | head -10
    echo "Exit code: $?"
fi

echo "=== End of permutation testing ==="
