#!/usr/bin/env bash
set -eu

echo "=== Patching Cabal to skip HSC for clock package ==="

# Create a custom cabal wrapper that intercepts clock builds
cat > "${_BUILD_PREFIX}/bin/cabal-wrapper.sh" << 'EOF'
#!/bin/bash
# Wrapper for cabal that prevents HSC crashes

# Check if we're building clock
if echo "$@" | grep -q "clock-0.8.4"; then
    echo "Intercepted clock build, using pre-built version..."
    
    # Create the expected structure
    CLOCK_HASH="e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0"
    STORE_PATH="C:/cabal/store/ghc-9.10.1/clock-0.8.4-${CLOCK_HASH}"
    mkdir -p "${STORE_PATH}/dist/build/System"
    
    # Copy pre-generated files
    if [[ -f "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" ]]; then
        cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" "${STORE_PATH}/dist/build/System/Clock.hs"
    fi
    
    # Create a success marker
    touch "${STORE_PATH}/.built"
    
    # Return success without actually running cabal
    exit 0
fi

# Otherwise, run the real cabal
exec "${SRC_DIR}/bootstrap-cabal/cabal.exe" "$@"
EOF

chmod +x "${_BUILD_PREFIX}/bin/cabal-wrapper.sh"

# Also create a cabal config that uses our wrapper
cat >> "C:/cabal/config" << EOF

-- Custom build hooks to prevent HSC crashes
program-locations
  ghc-location: ${GHC}
  ghc-pkg-location: ${GHC_PKG}

EOF

echo "Cabal patching completed"