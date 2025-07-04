#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PATH="${_SRC_DIR}/bootstrap-ghc/bin:${_SRC_DIR}/bootstrap-cabal${PATH:+:}${PATH:-}"

# Prepare python environment
export PYTHON=$(find "${BUILD_PREFIX}" -name python.exe | head -1)
export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

# Set up temp variables
export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# ...existing code...

# Create a custom Cabal config to help with HSC tool issues
cp "${RECIPE_DIR}/building/custom.cabal.config" "${HOME}/.cabal/config"

# ...existing code...

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

# Create a script to help if HSC tools crash
cat > "${_BUILD_PREFIX}/bin/fix-hsc-crash.sh" << 'EOF'
#!/bin/bash
echo "Attempting to fix HSC crash for clock package..."
"${RECIPE_DIR}/building/patch-clock-build.py"
EOF
chmod +x "${_BUILD_PREFIX}/bin/fix-hsc-crash.sh"

_hadrian_build=("${_SRC_DIR}"/hadrian/build.bat)

# Configure and build GHC
# ...existing code...

# Try the build and apply workaround if it fails
"${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn || {
    echo "*** First build attempt failed - trying to fix HSC crash ***"
    # If the build failed, try to patch the clock package
    "${_BUILD_PREFIX}/bin/fix-hsc-crash.sh"

    # And try again
    "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
      --flavour=quickest \
      --docs=none \
      --progress-info=unicorn
  }

echo "*** Stage 1 GHC build clock logs. ***"
cat C:/cabal/logs/ghc-9.10.1/clock-0.8.4*.log
echo "*** Stage 1 GHC build clock logs. ***"

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=release --freeze1 --docs=none

