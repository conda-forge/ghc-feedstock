#!/usr/bin/env bash

set -eu

# Initialize logging index
_log_index=0

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update
run_and_log "build-hadrian" sh -c "cd '${SRC_DIR}/hadrian' && ${CABAL} v2-build -j hadrian"

_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f -executable | head -1)

if [[ -z "${_hadrian_bin}" ]]; then
  echo "ERROR: Could not find hadrian binary after build"
  echo "Expected location: ${SRC_DIR}/hadrian/dist-newstyle/build/*/ghc-*/hadrian-*/*/build/hadrian/hadrian"
  exit 1
fi

_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")
"${_hadrian_bin}" --version

SYSTEM_CONFIG+=(
  --build="x86_64-unknown-linux"
  --host="x86_64-unknown-linux"
)

run_and_log "ghc-configure" "${SRC_DIR}"/configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# ============================================================
# BUILD CONFIGURATION
# ============================================================

# Set Hadrian flavour (consistent across all stages to prevent RTS reconfiguration)
#   9.2.8: GHC does not have 'release' flavour, must use 'quick'
#   9.4.8+: Use 'release' for consistency and full optimization
if [[ "${PKG_VERSION}" == "9.2.8"* ]]; then
  HADRIAN_FLAVOUR="quick"  # Only option for 9.2.8
else
  HADRIAN_FLAVOUR="release"  # All other versions (9.10.2 uses this)
fi

echo "=== Build Configuration ==="
echo "  GHC Version: ${PKG_VERSION}"
echo "  Hadrian Flavour: ${HADRIAN_FLAVOUR}"
echo "  Hadrian Binary: ${_hadrian_bin}"
echo "  CPU Count: ${CPU_COUNT}"
echo "=========================="

# ============================================================
# STAGE 1: EXECUTABLE
# ============================================================
# Build the stage 1 compiler executable
# This compiler can compile Haskell code but uses bootstrap libraries
# ============================================================

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR}"

# Patch settings file to inject conda library paths and toolchain
update_settings_link_flags "${SRC_DIR}"/_build/stage0/lib/settings

# ============================================================
# STAGE 1: LIBRARIES AND ESSENTIAL TOOLS
# ============================================================
# Build stage 1 libraries with explicit LIBRARY_PATH
# Required for successful linking against conda dependencies
# Also build essential tools (ghc-pkg, hsc2hs) needed by stage2
# ============================================================

# Export library paths for stage 1 library build
# This ensures GHC finds conda libraries during library compilation
export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"

echo "=== Building Stage 1 Libraries and Tools ==="
echo "  LIBRARY_PATH: ${LIBRARY_PATH}"
echo "  LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"

run_and_log "stage1_ghc-prim" "${_hadrian_build[@]}" stage1:lib:ghc-prim --flavour="${HADRIAN_FLAVOUR}"
run_and_log "stage1_ghc-bignum" "${_hadrian_build[@]}" stage1:lib:ghc-bignum --flavour="${HADRIAN_FLAVOUR}"
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour="${HADRIAN_FLAVOUR}"

run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour="${HADRIAN_FLAVOUR}"
run_and_log "stage1_hsc2hs" "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour="${HADRIAN_FLAVOUR}"

# ============================================================

# Patch settings again after library build
update_settings_link_flags "${SRC_DIR}"/_build/stage0/lib/settings

# ============================================================
# STAGE 2: LIBRARIES (BUILD BEFORE EXECUTABLE)
# ============================================================
# Build stage 2 libraries first to avoid potential rebuilds
# Use --freeze1 to prevent stage 1 from being rebuilt
# ============================================================

echo "=== Building Stage 2 Libraries ==="

# ============================================================
# RACE CONDITION PREVENTION (ALL VERSIONS)
# Same as stage 1 - explicit builds for reliability
# ============================================================
echo "  Building libraries explicitly (race condition prevention)"
run_and_log "stage2_ghc-prim" "${_hadrian_build[@]}" stage2:lib:ghc-prim --flavour="${HADRIAN_FLAVOUR}" --freeze1
run_and_log "stage2_ghc-bignum" "${_hadrian_build[@]}" stage2:lib:ghc-bignum --flavour="${HADRIAN_FLAVOUR}" --freeze1
# ============================================================

# ============================================================
# STAGE 2: EXECUTABLE
# ============================================================
# Build the stage 2 compiler executable
# This is the final optimized compiler we'll install
# Use --freeze1 to prevent stage 1 rebuilds
# ============================================================

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR}" --freeze1

# Patch stage 1 settings (used by stage 2 compiler)
update_settings_link_flags "${SRC_DIR}"/_build/stage1/lib/settings

# ============================================================
# STAGE 2: LIBRARY
# ============================================================
# Build stage 2 ghc library (used by ghci and plugins)
# Use --freeze1 to prevent stage 1 rebuilds
# ============================================================

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour="${HADRIAN_FLAVOUR}" --freeze1

# ============================================================
# INSTALL
# ============================================================
# Install the stage 2 compiler to ${PREFIX}
# Use --freeze1 and --freeze2 to prevent any rebuilds
# Use --docs=none to skip documentation generation (faster)
# ============================================================

run_and_log "install" \
  "${_hadrian_build[@]}" install \
  --prefix="${PREFIX}" \
  --freeze1 \
  --freeze2 \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none

# ============================================================
# POST-INSTALL SETTINGS PATCHING
# ============================================================
# Update installed settings file to:
# 1. Replace absolute paths with $topdir variables
# 2. Add conda library paths
# 3. Configure conda toolchain
# 4. Platform-specific flags (Linux: standard flags)
# ============================================================

settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)

if [[ -z "${settings_file}" ]]; then
  echo "ERROR: Could not find installed settings file"
  exit 1
fi

echo "=== Updating installed settings ==="
echo "  Settings file: ${settings_file}"

update_installed_settings

# Display final settings for verification
echo "=== Final settings file ==="
cat "${settings_file}"

echo "=== Build completed successfully ==="
