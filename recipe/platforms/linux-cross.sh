#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux Cross-Compilation (aarch64, ppc64le)
# ==============================================================================
# GHC cross-compilation for Linux targets (build on x86_64)
# Uses ghc-bootstrap 9.2.8 from BUILD_PREFIX
#
# Build Strategy:
# - Stage 1: Build cross-compiler using x86_64 bootstrap GHC
# - Stage 2: Use Stage 1 to build target-arch binaries
# - Binary Distribution: Create and install relocatable package
#
# Supported targets: linux-aarch64, linux-ppc64le
# ==============================================================================

set -eu

source "${RECIPE_DIR}/lib/common-hooks.sh"
source "${RECIPE_DIR}/lib/cross-helpers.sh"

# Platform metadata
PLATFORM_NAME="Linux cross-compilation"
PLATFORM_TYPE="cross"
INSTALL_METHOD="bindist"
FLAVOUR="release"

# ==============================================================================
# Architecture Configuration
# ==============================================================================

# Configure all triple variables (auto-detects cross mode)
# Sets: ghc_build, ghc_host, ghc_target, ghc_triple, conda_*, *_arch
configure_triples

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

platform_setup_environment() {
  echo "  Setting up Linux ${target_arch} cross-compilation environment..."

  # GHC, PATH already set by common_setup_environment
  export CONDA_BUILD_SYSROOT="${BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot"

  # Set autoconf variables (statx=no for glibc 2.17, LLVM tools for cross)
  set_autoconf_toolchain_vars --linux --cross

  # CRITICAL: Tell autoconf we're cross-compiling (prevents running test programs)
  export cross_compiling=yes

  echo "  ✓ Linux ${target_arch} cross-compilation environment ready"
}

# ==============================================================================
# Phase 2: Bootstrap Setup - uses default (phases.sh verifies GHC automatically)
# ==============================================================================

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

platform_configure_ghc() {
  shared_cross_configure_ghc "-L${PREFIX}/lib ${LDFLAGS:-}"
}

# ==============================================================================
# Phase 5: Patch System Config - uses shared cross_patch_system_config()
# ==============================================================================

platform_post_configure_ghc() {
  # Use unified post-configure orchestrator (auto-detects Linux cross-compile)
  shared_post_configure_ghc "${conda_target}"
}

# ==============================================================================
# Phase 6: Build Hadrian - uses default with cross-compile flags
# ==============================================================================

platform_pre_build_hadrian() {
  # Linux cross-compile needs explicit sysroot and library paths for GCC toolchain.
  # (macOS Clang handles this automatically via SDK - see osx-arm64.sh for contrast)
  export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include -fdebug-prefix-map=${SRC_DIR}=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
  export LDFLAGS="-L${BUILD_PREFIX}/${conda_host}/lib -L${BUILD_PREFIX}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"

  # Set up Hadrian cabal flags using cross-compile helper
  cross_setup_hadrian_flags
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

platform_pre_build_stage1() {
  # Use shared cross-compile pre-Stage1 setup (disables copy optimization)
  cross_pre_stage1_standard
}

# Unified stage settings patch hook for consistent exe→patch→lib flow
platform_patch_stage_settings() {
  local stage="$1"
  local settings_file="${SRC_DIR}/_build/${stage}/lib/settings"
  _patch_stage_linker_flags "${settings_file}"
}

# ==============================================================================
# Phase 9: Install
# ==============================================================================

patch_final_settings() {
  echo "  Patching final settings file..."

  local settings_file=$(find "${PREFIX}/lib/" -name settings | head -1)

  if [[ ! -f "${settings_file}" ]]; then
    echo "ERROR: Could not find settings file in ${PREFIX}/lib/"
    return 1
  fi

  # Fix architecture references
  perl -pi -e "s#${host_arch}(-[^ \"]*)#${target_arch}\$1#g" "${settings_file}"

  # Add relocatable library paths
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"

  # Fix tool paths to use target prefix (strip absolute BUILD_PREFIX paths)
  # Pattern: Match full quoted path, capture the target prefix (e.g., aarch64-conda-linux-gnu-)
  # and tool name, then replace with just prefix+tool (no absolute path)
  perl -pi -e "s#\"[^\"]*/([^/]*-)(ar|as|clang|clang\+\+|ld|nm|objdump|ranlib|llc|opt)\"#\"\$1\$2\"#g" "${settings_file}"

  echo "  ✓ Final settings patched"
}

platform_install_ghc() {
  # Use shared cross-compile bindist install helper
  cross_bindist_install "${ghc_target}"
}

platform_post_install() {
  patch_final_settings
  # Use shared cross-compile post-install (wrapper fixes, ghci fix, symlinks, bash completion)
  cross_post_install "${ghc_target}"
}
