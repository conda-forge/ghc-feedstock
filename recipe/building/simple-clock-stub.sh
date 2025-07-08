#!/usr/bin/env bash
set -eu

echo "=== Creating simple clock stub ==="

# Create the cabal store structure for clock
CLOCK_HASH="e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0"
STORE_PATH="C:/cabal/store/ghc-9.10.1/clock-0.8.4-${CLOCK_HASH}"
BUILD_PATH="${STORE_PATH}/dist/build/System"

echo "Creating clock directories..."
mkdir -p "${BUILD_PATH}"
mkdir -p "${STORE_PATH}/lib"

# Copy the pre-generated Clock.hs
echo "Installing Clock.hs..."
cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" "${BUILD_PATH}/Clock.hs"

# Create a minimal package config
cat > "${STORE_PATH}/lib/package.conf" << EOF
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
EOF

# Create dummy library file
touch "${STORE_PATH}/lib/HSclock-0.8.4-${CLOCK_HASH}.a"

# Create marker files
touch "${STORE_PATH}/.clock-stubbed"
touch "${BUILD_PATH}/.hs-generated"

echo "Clock stub created at ${STORE_PATH}"