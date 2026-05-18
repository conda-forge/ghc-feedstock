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
# Hooks Using Smart Defaults (cross-helpers.sh, phases.sh)
# ==============================================================================
# The following hooks are handled by smart defaults:
#
#   configure_ghc         → default_cross_configure_ghc() (shared_cross_configure_ghc)
#   post_configure_ghc    → default_post_configure_ghc() auto-detects cross
#   pre_build_hadrian     → default_pre_build_hadrian() calls cross_setup_hadrian_environment
#   pre_build_stage1      → default_pre_build_stage1() calls cross_pre_stage1_standard
#   patch_stage_settings  → default_build_stage1/2() uses patch_settings dispatcher
#   install_ghc           → default_install_ghc() uses shared_install_ghc() (auto-detects cross)
#   post_install          → default_post_install() uses shared_post_install_ghc_auto()
# ==============================================================================
