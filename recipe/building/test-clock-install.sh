#!/usr/bin/env bash
set -eu

echo "=== Testing Clock package installation ==="

CLOCK_HASH="e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0"
STORE_PATH="C:/cabal/store/ghc-9.10.1/clock-0.8.4-${CLOCK_HASH}"

echo "Testing cabal list for clock..."
if "${SRC_DIR}/bootstrap-cabal/cabal.exe" list clock 2>&1 | grep -q "Installed versions:.*0.8.4"; then
    echo "✓ Cabal recognizes Clock as installed"
else
    echo "✗ Cabal does not recognize Clock as installed"
    echo "Cabal output:"
    "${SRC_DIR}/bootstrap-cabal/cabal.exe" list clock || true
fi

echo ""
echo "Testing ghc-pkg for clock..."
if "${SRC_DIR}/bootstrap-ghc/bin/ghc-pkg.exe" list clock 2>&1 | grep -q "clock-0.8.4"; then
    echo "✓ GHC-pkg recognizes Clock package"
else
    echo "✗ GHC-pkg does not recognize Clock package"
    echo "GHC-pkg output:"
    "${SRC_DIR}/bootstrap-ghc/bin/ghc-pkg.exe" list clock || true
fi

echo ""
echo "Testing Clock package structure..."
if [[ -f "${STORE_PATH}/dist/build/System/Clock.hs" ]]; then
    echo "✓ Clock.hs exists at expected location"
    echo "  File size: $(stat -c%s "${STORE_PATH}/dist/build/System/Clock.hs" 2>/dev/null || echo "unknown") bytes"
else
    echo "✗ Clock.hs missing from expected location: ${STORE_PATH}/dist/build/System/Clock.hs"
fi

if [[ -f "${STORE_PATH}/lib/libHSclock-0.8.4-${CLOCK_HASH}.a" ]]; then
    echo "✓ Clock library archive exists"
else
    echo "✗ Clock library archive missing"
fi

if [[ -f "${STORE_PATH}/dist/installed-pkg-config" ]]; then
    echo "✓ Package configuration exists"
else
    echo "✗ Package configuration missing"
fi

echo ""
echo "Testing cabal build dry-run..."
cd "${SRC_DIR}"
if "${SRC_DIR}/bootstrap-cabal/cabal.exe" v2-build --dry-run clock 2>&1 | grep -q "Up to date"; then
    echo "✓ Cabal considers Clock up to date"
elif "${SRC_DIR}/bootstrap-cabal/cabal.exe" v2-build --dry-run clock 2>&1 | grep -q "In order.*clock.*already installed"; then
    echo "✓ Cabal recognizes Clock as already installed"
else
    echo "✗ Cabal still wants to build Clock"
    echo "Dry-run output:"
    "${SRC_DIR}/bootstrap-cabal/cabal.exe" v2-build --dry-run clock 2>&1 | head -10 || true
fi

echo ""
echo "Clock installation test completed"