#!/usr/bin/env bash
# ============================================================
# STANDARDIZED GHC BUILD SCRIPT - macOS 64-bit Native
# ============================================================
# Version: 1.0
# GHC Version: 9.10.2
# Last updated: 2025-11-13
#
# DESIGN PRINCIPLES:
# 1. Use lib module functions for consistency
# 2. Explicit Hadrian binary (prevents implicit rebuilds)
# 3. Race condition prevention for parallel builds
# 4. macOS-specific setup (libiconv, DYLD, llvm-ar)
# 5. Comprehensive documentation
# ============================================================

set -eu

# Initialize logging index
_log_index=0

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

# ============================================================
# MACOS-SPECIFIC ENVIRONMENT SETUP
# ============================================================
# Configure all macOS-specific requirements:
# - Build libiconv_compat.dylib
# - Set DYLD variables
# - Configure llvm-ar
# - Patch bootstrap settings
# ============================================================

# CRITICAL: Unset build_alias and host_alias
# These interfere with configure scripts on macOS
unset build_alias
unset host_alias

# Set up complete macOS environment
setup_macos_native_environment

# ============================================================
# CABAL ENVIRONMENT SETUP
# ============================================================
export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# ============================================================
# GHC CONFIGURE
# ============================================================
# System triple configuration
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --prefix="${PREFIX}"
)

# Library paths configuration (Bash 3.2 compatible)
# Use mapfile/readarray if available (Bash 4+), otherwise while loop
declare -a CONFIGURE_ARGS
if type -t mapfile >/dev/null 2>&1; then
  mapfile -t CONFIGURE_ARGS < <(build_configure_args)
else
  while IFS= read -r arg; do
    CONFIGURE_ARGS+=("$arg")
  done < <(build_configure_args)
fi

if [[ ${#CONFIGURE_ARGS[@]} -eq 0 ]]; then
  echo "ERROR: build_configure_args returned no arguments"
  exit 1
fi

# Set macOS-specific autoconf variables
set_autoconf_macos_vars "false"

# Clear DEVELOPER_DIR (prevents Xcode interference)
export DEVELOPER_DIR=""

run_and_log "configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# ============================================================
# HADRIAN CONFIG PATCHING (macOS)
# ============================================================
# Patch Hadrian config files to use llvm-ar and conda toolchain
# ============================================================

set_macos_conda_ar_ranlib "${SRC_DIR}/hadrian/cfg/default.host.target" "${CONDA_TOOLCHAIN_BUILD}"
set_macos_conda_ar_ranlib "${SRC_DIR}/hadrian/cfg/default.target" "${CONDA_TOOLCHAIN_BUILD}"

# ============================================================
# HADRIAN BUILD (EXPLICIT BINARY PATTERN)
# ============================================================
# CRITICAL: Build Hadrian with cabal and use explicit binary
# This prevents implicit rebuilds during stage transitions
# ============================================================

echo "=== Building Hadrian with cabal ==="
pushd "${SRC_DIR}"/hadrian
  "${CABAL}" v2-build -j hadrian 2>&1 | tee "${SRC_DIR}"/cabal-verbose.log
  _cabal_exit_code=${PIPESTATUS[0]}

  if [[ $_cabal_exit_code -ne 0 ]]; then
    echo "=== Cabal build FAILED with exit code ${_cabal_exit_code} ==="
    exit 1
  else
    echo "=== Cabal build SUCCEEDED ==="
  fi
popd

# Find the built hadrian binary (robust dynamic discovery)
_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f -executable | head -1)

if [[ -z "${_hadrian_bin}" ]]; then
  echo "ERROR: Could not find hadrian binary after build"
  echo "Expected location: ${SRC_DIR}/hadrian/dist-newstyle/build/*/ghc-*/hadrian-*/*/build/hadrian/hadrian"
  exit 1
fi

echo "Found Hadrian binary: ${_hadrian_bin}"

# Use explicit binary with --directory flag
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ============================================================
# BUILD CONFIGURATION
# ============================================================

# Set Hadrian flavour (consistent across all stages)
HADRIAN_FLAVOUR="release+no_profiled_libs"

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
# ============================================================

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none

# Patch settings file for macOS
settings_file="${SRC_DIR}/_build/stage0/lib/settings"
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# ============================================================
# STAGE 1: LIBRARIES AND ESSENTIAL TOOLS
# ============================================================
# Build stage 1 libraries with race condition prevention
# ============================================================

echo "=== Building Stage 1 Libraries and Tools ==="

# ============================================================
# RACE CONDITION PREVENTION (ALL VERSIONS)
# Build libraries explicitly to prevent Hadrian parallel build races
# ============================================================
echo "  Building libraries explicitly (race condition prevention)"
run_and_log "stage1_ghc-prim" "${_hadrian_build[@]}" stage1:lib:ghc-prim \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none

run_and_log "stage1_ghc-bignum" "${_hadrian_build[@]}" stage1:lib:ghc-bignum \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none

echo "  Building tools explicitly (race condition prevention)"
run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none

run_and_log "stage1_hsc2hs" "${_hadrian_build[@]}" stage1:exe:hsc2hs \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none
# ============================================================

# Patch settings again after library build
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# ============================================================
# STAGE 2: LIBRARIES (BUILD BEFORE EXECUTABLE)
# ============================================================
# Build stage 2 libraries first to avoid potential rebuilds
# ============================================================

echo "=== Building Stage 2 Libraries ==="

# ============================================================
# RACE CONDITION PREVENTION (ALL VERSIONS)
# ============================================================
echo "  Building libraries explicitly (race condition prevention)"
run_and_log "stage2_ghc-prim" "${_hadrian_build[@]}" stage2:lib:ghc-prim \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --docs=none \
  --progress-info=none

run_and_log "stage2_ghc-bignum" "${_hadrian_build[@]}" stage2:lib:ghc-bignum \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --docs=none \
  --progress-info=none
# ============================================================

# ============================================================
# STAGE 2: EXECUTABLE
# ============================================================
# Build the stage 2 compiler executable
# ============================================================

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --docs=none \
  --progress-info=none

# Patch stage 1 settings (used by stage 2 compiler)
settings_file="${SRC_DIR}/_build/stage1/lib/settings"
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# ============================================================
# STAGE 2: LIBRARY
# ============================================================
# Build stage 2 ghc library
# ============================================================

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --docs=none \
  --progress-info=none

# ============================================================
# INSTALL
# ============================================================
# Install the stage 2 compiler to ${PREFIX}
# ============================================================

run_and_log "install" "${_hadrian_build[@]}" install \
  --prefix="${PREFIX}" \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --freeze2 \
  --docs=none \
  --progress-info=none

# ============================================================
# POST-INSTALL SETTINGS PATCHING
# ============================================================
# Update installed settings file for macOS
# ============================================================

settings_file=$(find "${PREFIX}"/lib/ -name settings | head -n 1)

if [[ -z "${settings_file}" ]]; then
  echo "ERROR: Could not find installed settings file"
  exit 1
fi

echo "=== Updating installed settings ==="
echo "  Settings file: ${settings_file}"

update_installed_settings
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# Display final settings for verification
echo "=== Final settings file ==="
cat "${settings_file}"

echo "=== Build completed successfully ==="
