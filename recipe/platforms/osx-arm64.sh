#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: macOS arm64 (Cross-compiled from x86_64)
# ==============================================================================
# macOS cross-compilation from x86_64 to arm64.
#
# Build Strategy:
# - Stage 1: Build cross-compiler using x86_64 bootstrap GHC
# - Stage 2: Use Stage 1 to build arm64-targeted binaries
#
# Key implementation details:
# - Uses bootstrap GHC from BUILD_PREFIX (no separate env needed)
# - Disables copy optimization to force cross binary compilation
# - Uses llvm-ar for Apple ld64 compatibility
# - Applies -fno-lto to prevent ABI mismatches
# ==============================================================================

set -eu

# Source common hook defaults (provides no-op implementations)
source "${RECIPE_DIR}/lib/common-hooks.sh"
source "${RECIPE_DIR}/lib/cross-helpers.sh"
source "${RECIPE_DIR}/lib/macos-common.sh"

# Platform metadata
PLATFORM_NAME="macOS arm64 (cross-compiled from x86_64)"
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
  echo "  Setting up macOS cross-compilation environment..."

  # GHC, PATH already set by common_setup_environment

  # Use shared macOS setup for LLVM ar (skip iconv compat - arm64 uses different approach)
  macos_setup_llvm_ar

  # Create symlinks for host tools (needed for stage1 build)
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ar" "${BUILD_PREFIX}/bin/ar" 2>/dev/null || true
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-as" "${BUILD_PREFIX}/bin/as" 2>/dev/null || true
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ld" "${BUILD_PREFIX}/bin/ld" 2>/dev/null || true

  echo "  ✓ macOS cross-compilation environment ready"
}

# ==============================================================================
# Phase 2: Bootstrap Setup - uses default (phases.sh verifies GHC automatically)
# ==============================================================================

# ==============================================================================
# Phase 3: Cabal Setup - uses default
# ==============================================================================

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

platform_configure_ghc() {
  echo "  Configuring GHC for cross-compilation..."

  # Build system config using nameref helper (cross-compile: only target, no build/host)
  local -a system_config
  build_system_config system_config "" "" "${target_alias}"

  # Build standard configure args using nameref helper (--with-gmp, --with-ffi, etc.)
  local -a configure_args
  build_configure_args configure_args "-L${PREFIX}/lib ${LDFLAGS:-}"

  # Set autoconf variables (macOS + cross-compile LLVM tools)
  set_autoconf_toolchain_vars --macos --cross

  # Add cross-compilation specific toolchain paths
  configure_args+=(
    CC_STAGE0="${CC_FOR_BUILD}"
    LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

    AR="${BUILD_PREFIX}/bin/${conda_target}-ar"
    AS="${BUILD_PREFIX}/bin/${conda_target}-as"
    CC="${BUILD_PREFIX}/bin/${conda_target}-clang"
    CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"
    LD="${BUILD_PREFIX}/bin/${conda_target}-ld"
    NM="${BUILD_PREFIX}/bin/${conda_target}-nm"
    OBJDUMP="${BUILD_PREFIX}/bin/${conda_target}-objdump"
    RANLIB="${BUILD_PREFIX}/bin/${conda_target}-ranlib"

    CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CFLAGS:-}"
    CPPFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CPPFLAGS:-}"
    CXXFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CXXFLAGS:-}"
  )

  run_and_log "configure" ./configure -v "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured"
}

platform_post_configure_ghc() {
  echo "  Patching system.config for cross-compilation..."

  # Use standardized cross-compile patching from cross-helpers.sh
  # This handles: strip BUILD_PREFIX, fix python path, add toolchain prefix, linker flags
  cross_patch_system_config "${conda_target}" "ar clang clang++ llc nm objdump opt ranlib"

  # Apply macOS-specific cross-compile patches from macos-common.sh
  # This handles: system-ar, ffi/iconv lib dirs, stage0 flags, ar command, objdump fix
  macos_cross_system_config_patches "${conda_host}" "${conda_target}"

  # Use shared helper for bootstrap settings (cross-compile mode)
  macos_patch_bootstrap_settings "${conda_host}" "cross"

  echo "  ✓ System config patched"
}

# ==============================================================================
# Phase 5: Build Hadrian - uses default with cross-compile flags
# ==============================================================================

platform_pre_build_hadrian() {
  # Set up Hadrian cabal flags using cross-compile helper
  cross_setup_hadrian_flags
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

platform_pre_build_stage1() {
  disable_copy_optimization

  # Set up build environment for stage1 (using build-host tools)
  export AR="${AR_STAGE0}"
  export AS="${BUILD_PREFIX}/bin/${conda_host}-as"
  export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  # Note: Symlinks for host tools created in platform_setup_environment
}

platform_build_stage1() {
  echo "  Building Stage 1 cross-compiler..."

  # Build Stage 1 GHC compiler
  run_and_log "stage1-ghc" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" \
    stage1:exe:ghc-bin --docs=none --progress-info=none

  # Build Stage 1 supporting tools
  run_and_log "stage1-pkg" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" \
    stage1:exe:ghc-pkg --docs=none --progress-info=none
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" \
    stage1:exe:hsc2hs --docs=none --progress-info=none

  # Verify Stage0 GHC works
  "${SRC_DIR}/_build/stage0/bin/${ghc_target}-ghc" --version || {
    echo "WARNING: Stage0 GHC failed to report version"
  }

  # Build libraries with release flavour (for full ways: vanilla, profiling, dynamic)
  run_and_log "stage1-lib" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" \
    stage1:lib:ghc --docs=none --progress-info=none

  echo "  ✓ Stage 1 cross-compiler built"
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

platform_build_stage2() {
  echo "  Building Stage 2 cross-compiled binaries..."

  run_and_log "stage2-exe" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" \
    stage2:exe:ghc-bin --freeze1 --docs=none --progress-info=none

  run_and_log "build-all" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" \
    --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none

  echo "  ✓ Stage 2 cross-compiled binaries built"
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

platform_install_ghc() {
  # Use shared bindist_install helper (cross-compile to arm64)
  bindist_install "${conda_target}"
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

platform_post_install() {
  # Use cross-helpers for symlink creation (conda_target is set by configure_cross_triples)
  # Note: macOS doesn't need wrapper script fixes like Linux does
  cross_create_symlinks "${conda_target}"
  install_bash_completion

  # Verify installation
  echo "  Verifying GHC installation..."
  "${PREFIX}/bin/ghc" --version || {
    echo "WARNING: Installed GHC failed to run (expected for cross-compiled binary)"
  }

  echo "  ✓ macOS arm64 post-install complete"
}
