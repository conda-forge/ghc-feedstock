#!/usr/bin/env bash
set -eux

echo "=== Clock Package Diagnostic Build Script ==="
echo "This script builds the clock package separately to diagnose HSC tool issues"

# Set up environment variables
export PATH="${_SRC_DIR}/bootstrap-ghc/bin:${_SRC_DIR}/bootstrap-cabal${PATH:+:}${PATH:-}"
export CABAL="${SRC_DIR}\\bootstrap-cabal\\cabal.exe"
export CC="${CLANG}"
export CXX="${CLANGXX}"
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"

# Create a temporary directory for the build
DIAG_DIR="${TEMP}/clock-diagnosis"
mkdir -p "${DIAG_DIR}"
cd "${DIAG_DIR}"

echo "=== Downloading clock package ==="
cabal get clock-0.8.4 -v3

cd clock-0.8.4

echo "=== Configuring clock package with maximum verbosity ==="
cabal configure -v3 \
  --with-compiler="${GHC}" \
  --with-gcc="${CLANG_WRAPPER}" \
  --extra-include-dirs="${PREFIX}/include" \
  --extra-lib-dirs="${PREFIX}/lib" 2>&1 | tee configure.log

echo "=== Attempting to build clock package with maximum verbosity ==="
# Try to build and capture all output
cabal build -v3 2>&1 | tee build.log || {
    echo "=== Build failed, checking for HSC tool crash details ==="
    
    # Look for the HSC command that failed
    echo "=== Searching for HSC command in build output ==="
    grep -E "(hsc2hs|_hsc_make\.exe)" build.log || true
    
    # Check if we can find the generated HSC executable
    echo "=== Looking for generated HSC executables ==="
    find . -name "*_hsc_make.exe" -type f 2>/dev/null | while read hsc_exe; do
        echo "Found HSC executable: ${hsc_exe}"
        echo "File details:"
        ls -la "${hsc_exe}"
        
        # Try to run it directly to see the error
        echo "=== Attempting to run HSC executable directly ==="
        "${hsc_exe}" --help 2>&1 || {
            exit_code=$?
            echo "HSC executable failed with exit code: ${exit_code}"
            
            # Check dependencies
            echo "=== Checking HSC executable dependencies ==="
            if command -v ldd >/dev/null 2>&1; then
                ldd "${hsc_exe}" || echo "ldd failed"
            fi
            
            if command -v dumpbin >/dev/null 2>&1; then
                dumpbin /dependents "${hsc_exe}" || echo "dumpbin failed"
            fi
        }
    done
    
    # Look for the HSC source file
    echo "=== Looking for Clock.hsc source file ==="
    find . -name "Clock.hsc" -type f 2>/dev/null | while read hsc_file; do
        echo "Found HSC source: ${hsc_file}"
        echo "First 20 lines:"
        head -20 "${hsc_file}"
    done
    
    # Check the actual error from the log
    echo "=== Extracting error details from build log ==="
    tail -50 build.log
}

echo "=== Checking Cabal build directory structure ==="
find dist -type f -name "*.exe" 2>/dev/null | head -20

echo "=== Saving diagnostic information ==="
# Copy logs to a place where we can examine them
cp -f *.log "${SRC_DIR}/_logs/" 2>/dev/null || true

echo "=== Diagnostic complete ==="
echo "Check the following files for details:"
echo "- ${DIAG_DIR}/clock-0.8.4/configure.log"
echo "- ${DIAG_DIR}/clock-0.8.4/build.log"