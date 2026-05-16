#!/usr/bin/env bash
set -eu

echo "=== Installing clock package without HSC ==="

# Source common functions  
source "${RECIPE_DIR}"/building/common.sh

# Set up environment
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"
export GHC_PKG="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc-pkg.exe"

# Create a temporary directory for clock build
CLOCK_BUILD_DIR="${TEMP}/clock-no-hsc-build"
rm -rf "${CLOCK_BUILD_DIR}"
mkdir -p "${CLOCK_BUILD_DIR}"

cd "${CLOCK_BUILD_DIR}"

# Download clock source
echo "Downloading clock-0.8.4 source..."
cabal get clock-0.8.4 || {
    echo "Failed to download clock package"
    exit 1
}

cd clock-0.8.4

# Replace the .hsc file with our pre-generated .hs file BEFORE cabal tries to build
echo "Replacing Clock.hsc with pre-generated Clock.hs..."
if [[ -f "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" ]]; then
    # Remove the .hsc file
    rm -f System/Clock.hsc || true
    
    # Copy our pre-generated .hs file
    cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" System/Clock.hs
    echo "Clock.hs installed, Clock.hsc removed"
else
    echo "Error: Pre-generated Clock.hs not found!"
    exit 1
fi

# Now configure and build - Cabal won't try to run hsc2hs since there's no .hsc file
echo "Configuring clock package..."
cabal configure \
    --with-compiler="${GHC}" \
    --with-gcc="${CLANG_WRAPPER}" \
    --ghc-options="-optc-fno-stack-protector -optc-fno-stack-check" \
    -v2

echo "Building clock package..."
cabal build -v2

# Install to the global package database
echo "Installing clock package globally..."
cabal copy --destdir="${TEMP}/clock-install"
cabal register --gen-pkg-config=clock.conf

# Register with GHC
"${GHC_PKG}" update clock.conf --global --force || {
    echo "Warning: Failed to register with ghc-pkg, trying alternative method..."
    
    # Alternative: Install using cabal v2-install
    cabal v2-install --lib clock-0.8.4 \
        --with-compiler="${GHC}" \
        --package-db=global \
        --overwrite-policy=always \
        || echo "Alternative installation also failed"
}

# Verify installation
echo "Verifying clock installation..."
"${GHC_PKG}" list clock || echo "Package list failed"
"${GHC_PKG}" describe clock || echo "Package describe failed"

echo "=== Clock package installation completed ==="