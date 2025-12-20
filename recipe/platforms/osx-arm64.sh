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

# Configure all triple variables (auto-detects cross mode)
# Sets: ghc_build, ghc_host, ghc_target, ghc_triple, conda_*, *_arch
configure_triples

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
# Hooks Using Smart Defaults (cross-helpers.sh, phases.sh)
# ==============================================================================
# The following hooks are handled by smart defaults:
#
#   configure_ghc         → default_cross_configure_ghc() (shared_cross_configure_ghc)
#   post_configure_ghc    → default_post_configure_ghc() auto-detects cross
#   pre_build_stage1      → default_pre_build_stage1() calls cross_pre_stage1_standard
# ==============================================================================

# ==============================================================================
# Phase 5: Build Hadrian - uses default with cross-compile flags
# ==============================================================================

platform_pre_build_hadrian() {
  # Set up Hadrian cabal flags using cross-compile helper
  cross_setup_hadrian_flags
}

# ==============================================================================
# Phase 6-7: Stage Builds
# ==============================================================================
# Stage settings patching is now handled by shared_patch_stage_settings() which
# auto-detects macOS and calls macos_update_stage_settings(). No override needed.

# Hook called after building stage executables (ghc-bin, ghc-pkg, hsc2hs)
platform_post_stage1_executables() {
  # Verify Stage0 GHC works (optional - doesn't block build)
  "${SRC_DIR}/_build/stage0/bin/${ghc_target}-ghc" --version || {
    echo "WARNING: Stage0 GHC failed to report version"
  }
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

platform_install_ghc() {
  # Use shared cross-compile bindist install with macOS-specific C++ std lib skip
  # (avoids configure failing on libc++ link test which runs x86_64 tests)
  cross_bindist_install "${conda_target}" "CXX_STD_LIB_LIBS='c++ c++abi'"
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

platform_post_install() {
  # Use shared cross-compile post-install (macOS doesn't need wrapper fixes)
  cross_post_install "${conda_target}" "no-wrapper-fix"

  # Update installed settings with llvm-ar (required for Apple ld64)
  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  [[ -f "${settings_file}" ]] && patch_settings "${settings_file}" --macos-ar-ranlib="${CONDA_TOOLCHAIN_BUILD}"

  # Verify installation (cross-compiled binary may fail to run - that's expected)
  verify_installed_ghc "true"

  echo "  ✓ macOS arm64 post-install complete"
}
