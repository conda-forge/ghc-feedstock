#!/usr/bin/env bash
# ============================================================
# GHC Build Script - macOS x86_64 Native
# ============================================================
# Simplified using build orchestrator
# ============================================================

set -eu

# Initialize logging index
_log_index=0

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

# ============================================================
# MACOS-SPECIFIC ENVIRONMENT SETUP
# ============================================================

# CRITICAL: Unset build_alias and host_alias
# These interfere with configure scripts on macOS
unset build_alias
unset host_alias

# Set up complete macOS environment (libiconv, DYLD, llvm-ar, etc.)
setup_macos_native_environment

# ============================================================
# CABAL SETUP
# ============================================================

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# ============================================================
# CONFIGURE
# ============================================================

SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --prefix="${PREFIX}"
)

declare -a CONFIGURE_ARGS
build_configure_args CONFIGURE_ARGS

# Set macOS-specific autoconf variables
set_autoconf_macos_vars "false"

# Clear DEVELOPER_DIR (prevents Xcode interference)
export DEVELOPER_DIR=""

configure_ghc SYSTEM_CONFIG CONFIGURE_ARGS

# ============================================================
# HADRIAN CONFIG PATCHING (macOS-specific)
# ============================================================
# Patch Hadrian config files to use llvm-ar and conda toolchain
# Must happen BEFORE building Hadrian
# ============================================================

set_macos_conda_ar_ranlib "${SRC_DIR}/hadrian/cfg/default.host.target" "${CONDA_TOOLCHAIN_BUILD}"
set_macos_conda_ar_ranlib "${SRC_DIR}/hadrian/cfg/default.target" "${CONDA_TOOLCHAIN_BUILD}"

# ============================================================
# HADRIAN BUILD
# ============================================================

declare -a HADRIAN_BUILD
build_hadrian_binary HADRIAN_BUILD

# ============================================================
# BUILD FLAVOUR
# ============================================================

HADRIAN_FLAVOUR="release+no_profiled_libs"

echo "=== Build Configuration ==="
echo "  GHC Version: ${PKG_VERSION}"
echo "  Hadrian Flavour: ${HADRIAN_FLAVOUR}"
echo "  CPU Count: ${CPU_COUNT}"
echo "=========================="

# ============================================================
# BUILD STAGES
# ============================================================

# Stage 1: Build
echo "=== Building Stage 1 ==="

# Patch settings file for macOS before build
settings_file="${SRC_DIR}/_build/stage0/lib/settings"
patch_macos_settings "${settings_file}"

# Build stage1 (will patch link flags internally before libs)
build_stage1 HADRIAN_BUILD "${HADRIAN_FLAVOUR}" "${settings_file}"

# Patch again after build (settings may get overwritten)
patch_macos_settings "${settings_file}"

# Stage 2: Build
echo "=== Building Stage 2 ==="

# Patch stage1 settings before build
settings_file="${SRC_DIR}/_build/stage1/lib/settings"
patch_macos_settings "${settings_file}"

# Build stage2 (will patch link flags internally if needed)
build_stage2 HADRIAN_BUILD "${HADRIAN_FLAVOUR}" "${settings_file}"

# ============================================================
# INSTALL
# ============================================================

run_and_log "install" \
  "${HADRIAN_BUILD[@]}" install \
  --prefix="${PREFIX}" \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --freeze2 \
  --docs=none

# ============================================================
# POST-INSTALL SETTINGS PATCHING
# ============================================================

echo "=== Updating installed settings ==="
update_installed_settings

# Patch ar/ranlib for installed settings
settings_file=$(find "${PREFIX}"/lib/ -name settings | head -n 1)
if [[ -n "${settings_file}" ]]; then
  set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
fi

echo "=== Build completed successfully ==="
