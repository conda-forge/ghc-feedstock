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

# Stage 1: Build with settings patching
echo "=== Building Stage 1 ==="
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
run_and_log "stage1_exe" "${HADRIAN_BUILD[@]}" stage1:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR}"

# Patch settings file for macOS (ar/ranlib + link flags)
settings_file="${SRC_DIR}/_build/stage0/lib/settings"
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# Build stage1 libs and tools
build_stage1_libs HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
build_stage1_tools HADRIAN_BUILD "${HADRIAN_FLAVOUR}"

# Patch settings again
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# Stage 2: Build with settings patching
echo "=== Building Stage 2 ==="
build_stage2_libs HADRIAN_BUILD "${HADRIAN_FLAVOUR}"

run_and_log "stage2_exe" "${HADRIAN_BUILD[@]}" stage2:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR}" --freeze1

# Patch stage 1 settings (used by stage 2 compiler)
settings_file="${SRC_DIR}/_build/stage1/lib/settings"
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

run_and_log "stage2_lib" "${HADRIAN_BUILD[@]}" stage2:lib:ghc --flavour="${HADRIAN_FLAVOUR}" --freeze1

# ============================================================
# BUILD XHTML (macOS race condition prevention)
# ============================================================
# Build xhtml explicitly to prevent .dyn_hi race with install
# ============================================================

echo "=== Building xhtml library explicitly (prevents Internals.dyn_hi race) ==="
run_and_log "stage1_xhtml" "${HADRIAN_BUILD[@]}" stage1:lib:xhtml --flavour="${HADRIAN_FLAVOUR}" --freeze1

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

settings_file=$(find "${PREFIX}"/lib/ -name settings | head -n 1)

if [[ -z "${settings_file}" ]]; then
  echo "ERROR: Could not find installed settings file"
  exit 1
fi

echo "=== Updating installed settings ==="
update_installed_settings
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

echo "=== Build completed successfully ==="
