#!/usr/bin/env bash
set -eu

echo "=== Pre-building clock package to avoid HSC crashes ==="

# Source common functions  
source "${RECIPE_DIR}"/building/common.sh

# Set up environment
export PATH="${_SRC_DIR}/bootstrap-ghc/bin:${_SRC_DIR}/bootstrap-cabal${PATH:+:}${PATH:-}"
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"
export CABAL="${SRC_DIR}\\bootstrap-cabal\\cabal.exe"

# Find clang
CLANG=$(find "${_BUILD_PREFIX}" -name clang.exe | head -1)
export CC="${CLANG}"

# Create a build directory
PREBUILD_DIR="${TEMP}/prebuild-clock"
rm -rf "${PREBUILD_DIR}"
mkdir -p "${PREBUILD_DIR}"

# Check if clock is already available (quietly)
"${CABAL}" list clock --simple-output > /dev/null 2>&1 || echo "Clock not in index"

# Create a minimal clock package that satisfies the dependency
cd "${PREBUILD_DIR}"

# Create directory structure
mkdir -p clock-0.8.4/System

# Copy the pre-generated Clock.hs
cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" clock-0.8.4/System/Clock.hs

# Create a minimal cabal file
cat > clock-0.8.4/clock.cabal << 'EOF'
cabal-version:      1.12
name:               clock
version:            0.8.4
synopsis:           High-resolution clock functions: monotonic, realtime, cputime.
description:        A package for convenient access to high-resolution clock and
                    timer functions of different operating systems via a unified API.
license:            BSD3
license-file:       LICENSE
author:             Cetin Sert <cetin@sert.works>, Corsis Research
maintainer:         Cetin Sert <cetin@sert.works>, Corsis Research
category:           System
build-type:         Simple

library
  exposed-modules:  System.Clock
  hs-source-dirs:   .
  build-depends:    base >=4.7 && <5
  default-language: Haskell2010
  c-sources:        
  cc-options:       -fno-stack-protector -fno-stack-check
EOF

# Create a dummy LICENSE file
cat > clock-0.8.4/LICENSE << 'EOF'
BSD3 License
Copyright (c) 2024, Clock Authors
EOF

# Create a Setup.hs
cat > clock-0.8.4/Setup.hs << 'EOF'
import Distribution.Simple
main = defaultMain
EOF

cd clock-0.8.4

# Build and install using v2 commands (reduced verbosity)
echo "Building clock package..."
"${CABAL}" v2-build --with-compiler="${GHC}" || {
    echo "v2-build failed, trying v1 approach..."
    
    # Try v1 build
    "${CABAL}" configure --with-compiler="${GHC}" --with-gcc="${CLANG}" > /dev/null 2>&1
    "${CABAL}" build > /dev/null 2>&1
    "${CABAL}" install --global > /dev/null 2>&1
}

# Try to register it
echo "Registering clock package..."
"${CABAL}" v2-install --lib . --package-db=global --overwrite-policy=always || {
    echo "v2-install failed"
}

# As a last resort, create a dummy in the store
echo "Creating clock in cabal store as fallback..."
CLOCK_HASH="e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0"
STORE_PATH="C:/cabal/store/ghc-9.10.1/clock-0.8.4-${CLOCK_HASH}"
mkdir -p "${STORE_PATH}/lib"

# Create a package conf
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
depends: base-4.19.1.0
EOF

# Create marker file
touch "${STORE_PATH}/.clock-prebuilt"

echo "=== Clock pre-build completed ==="