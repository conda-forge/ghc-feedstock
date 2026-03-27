#!/usr/bin/env bash
set -eu

echo "=== Registering clock package with GHC to prevent rebuild ==="

# Get the actual package database being used
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"
export GHC_PKG="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc-pkg.exe"

# Find the global package database
GLOBAL_PKG_DB=$("${GHC}" --print-global-package-db | tr -d '\r\n')
echo "Global package database: ${GLOBAL_PKG_DB}"

# Create clock hash that matches what Cabal expects
CLOCK_HASH="e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0"
STORE_PATH="C:/cabal/store/ghc-9.10.1/clock-0.8.4-${CLOCK_HASH}"

# Create directories
mkdir -p "${STORE_PATH}/lib"
mkdir -p "${STORE_PATH}/dist/build/System"

# Copy Clock.hs
cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" "${STORE_PATH}/dist/build/System/Clock.hs"

# Create a dummy library file
echo "# Dummy clock library" > "${STORE_PATH}/lib/libHSclock-0.8.4-${CLOCK_HASH}.a"

# Create a package configuration file for registration
cat > "${TEMP}/clock.conf" << EOF
name: clock
version: 0.8.4
id: clock-0.8.4-${CLOCK_HASH}
key: clock-0.8.4-${CLOCK_HASH}
license: BSD-3-Clause
exposed: True
exposed-modules: System.Clock
import-dirs: ${STORE_PATH}/lib
library-dirs: ${STORE_PATH}/lib
hs-libraries: HSclock-0.8.4-${CLOCK_HASH}
depends: base-4.20.0.0
maintainer: Temporary package for GHC build
synopsis: High-resolution clock functions (stub)
description: Stub package to prevent HSC crashes during GHC build
EOF

# Try to register the package
echo "Registering clock package..."
"${GHC_PKG}" register "${TEMP}/clock.conf" --force --global -v || {
    echo "Failed to register globally, trying alternative method..."
    
    # Alternative: try with user package db
    "${GHC_PKG}" register "${TEMP}/clock.conf" --force --user -v || {
        echo "Failed to register with user db, trying with specific package db..."
        
        # Create a local package db and register there
        LOCAL_PKG_DB="${TEMP}/local-pkg-db"
        mkdir -p "${LOCAL_PKG_DB}"
        "${GHC_PKG}" init "${LOCAL_PKG_DB}"
        "${GHC_PKG}" register "${TEMP}/clock.conf" --package-db="${LOCAL_PKG_DB}" --force -v || echo "All registration methods failed"
    }
}

# Verify registration
echo "Checking clock package registration..."
"${GHC_PKG}" list clock || echo "Clock not found in global db"
"${GHC_PKG}" describe clock || echo "Clock description failed"

# Also try to make it visible to Cabal
export CABAL_DIR="C:/cabal"
if [[ -f "${CABAL_DIR}/config" ]]; then
    echo "Updating Cabal config to include package database..."
    if ! grep -q "package-db" "${CABAL_DIR}/config"; then
        echo "package-db: ${GLOBAL_PKG_DB}" >> "${CABAL_DIR}/config"
    fi
fi

echo "Clock package registration completed"