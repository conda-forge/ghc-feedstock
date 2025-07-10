#!/usr/bin/env bash
set -eu

echo "=== Verifying Clock package fix ==="

# Check if the cabal store structure exists
CLOCK_HASH="e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0"
STORE_PATH="C:/cabal/store/ghc-9.10.1/clock-0.8.4-${CLOCK_HASH}"

echo "Checking for Clock package at: ${STORE_PATH}"

if [[ -d "${STORE_PATH}" ]]; then
    echo "✓ Clock package directory exists"
    
    if [[ -f "${STORE_PATH}/clock-0.8.4.cabal" ]]; then
        echo "✓ Clock package cabal file exists"
    else
        echo "✗ Clock package cabal file missing"
    fi
    
    if [[ -f "${STORE_PATH}/dist/build/System/Clock.hs" ]]; then
        echo "✓ Clock source file exists"
    else
        echo "✗ Clock source file missing"
    fi
    
    if [[ -f "${STORE_PATH}/lib/libHSclock-0.8.4-${CLOCK_HASH}.a" ]]; then
        echo "✓ Clock library archive exists"
    else
        echo "✗ Clock library archive missing"
    fi
    
    if [[ -f "${STORE_PATH}/package.conf" ]]; then
        echo "✓ Clock package configuration exists"
    else
        echo "✗ Clock package configuration missing"
    fi
else
    echo "✗ Clock package directory does not exist"
fi

# Check if cabal can find the package
if [[ -f "${SRC_DIR}/bootstrap-cabal/cabal.exe" ]]; then
    echo "Checking if cabal can find clock package..."
    "${SRC_DIR}/bootstrap-cabal/cabal.exe" list clock || echo "Cabal list failed"
fi

# Check if GHC can find the package
if [[ -f "${SRC_DIR}/bootstrap-ghc/bin/ghc-pkg.exe" ]]; then
    echo "Checking if ghc-pkg can find clock package..."
    "${SRC_DIR}/bootstrap-ghc/bin/ghc-pkg.exe" list clock || echo "GHC-pkg list failed"
fi

echo "Clock package verification completed"