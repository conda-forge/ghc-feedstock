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

# Use standardized cross-compilation triple configuration
# Sets: conda_host, conda_target, host_arch, target_arch, ghc_host, ghc_target
# Exports: build_alias, host_alias, target_alias, host_platform
configure_cross_triples

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
  echo "  Configuring GHC for ${target_arch} cross-compilation..."

  # Build system config using nameref helper
  local -a system_config
  build_system_config system_config "${ghc_host}" "${ghc_host}" "${ghc_target}"

  # Build standard configure args using nameref helper (--with-gmp, --with-ffi, etc.)
  local -a configure_args
  build_configure_args configure_args "-L${PREFIX}/lib ${LDFLAGS:-}"

  # Add cross-compilation toolchain args (target tools + STAGE0 tools + sysroot)
  # Uses direct variable assignment (CC=, AR=, etc.) per configure.ac API
  cross_build_toolchain_args configure_args "${conda_target}" "${conda_host}" "--sysroot"

  run_and_log "configure" ./configure -v "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured"
}

# ==============================================================================
# Phase 5: Patch System Config - uses shared cross_patch_system_config()
# ==============================================================================

platform_post_configure_ghc() {
  cross_patch_system_config "${conda_target}"
}

# ==============================================================================
# Phase 6: Build Hadrian - uses default with cross-compile flags
# ==============================================================================

platform_pre_build_hadrian() {
  # Set CFLAGS and LDFLAGS for hadrian build
  export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include -fdebug-prefix-map=${SRC_DIR}=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
  export LDFLAGS="-L${BUILD_PREFIX}/${conda_host}/lib -L${BUILD_PREFIX}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"

  # Set up Hadrian cabal flags using cross-compile helper
  cross_setup_hadrian_flags
}

# ==============================================================================
# Phase 7: Build Stage 1
# ==============================================================================

platform_pre_build_stage1() {
  disable_copy_optimization
}

platform_post_build_stage1() {
  echo "  Updating Hadrian binary reference..."

  # Find executable hadrian (after Stage1 build may have created new one)
  local hadrian_bin=$(find "${SRC_DIR}/hadrian/dist-newstyle/build" -name hadrian -type f -executable | head -1)

  if [[ -f "${hadrian_bin}" ]]; then
    HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")
    echo "  Updated HADRIAN_CMD to: ${hadrian_bin}"
  fi

  # Update GHC to Stage1 for Stage2 build
  export GHC="${SRC_DIR}/_build/ghc-stage1"
  echo "  GHC for Stage2: ${GHC}"

  echo "  ✓ Stage1 post-build complete"
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
