#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Common Hook Defaults
# ==============================================================================
# Purpose: Provide no-op default implementations for all platform hooks
#
# Platform configs can source this file and override only the hooks they need.
# All hooks have no-op defaults so platforms only implement what's necessary.
#
# Usage:
#   source "${RECIPE_DIR}/building/config/common-hooks.sh"
#   # Override only what you need:
#   platform_setup_environment() {
#     export MY_VAR="value"
#   }
# ==============================================================================

set -eu

# ==============================================================================
# ARCHITECTURE HOOKS
# ==============================================================================

# Detect and set architecture variables
# Sets: conda_host, conda_target, ghc_host, ghc_target
platform_detect_architecture() {
  : # No-op: platforms should implement this
}

# ==============================================================================
# BOOTSTRAP HOOKS
# ==============================================================================

# Set up bootstrap environment (GHC, Cabal, etc.)
# Sets: GHC, CABAL, bootstrap paths
platform_setup_bootstrap() {
  : # No-op: many platforms use BUILD_PREFIX tools
}

# ==============================================================================
# ENVIRONMENT HOOKS
# ==============================================================================

# Set up platform-specific environment variables
# Examples: DYLD_LIBRARY_PATH, sysroot, cross-compile flags
platform_setup_environment() {
  : # No-op: many platforms use conda-build defaults
}

# Set up Cabal environment
# Sets: CABAL, CABAL_DIR
platform_setup_cabal() {
  export CABAL="${BUILD_PREFIX}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}/.cabal"
}

# ==============================================================================
# CONFIGURATION HOOKS
# ==============================================================================

# Build system config array (--build, --host, --target)
# Sets: SYSTEM_CONFIG array
platform_build_system_config() {
  SYSTEM_CONFIG=()  # Empty default
}

# Build configure arguments array (--with-*, autoconf vars)
# Sets: CONFIGURE_ARGS array
platform_build_configure_args() {
  build_configure_args CONFIGURE_ARGS
}

# Select Hadrian build flavour
# Sets: HADRIAN_FLAVOUR (and optionally HADRIAN_FLAVOUR_STAGE1/STAGE2)
platform_select_flavour() {
  HADRIAN_FLAVOUR="release"
}

# ==============================================================================
# BUILD PHASE HOOKS
# ==============================================================================

# Pre-configure hook (before ./configure)
platform_pre_configure() {
  : # No-op
}

# Post-configure hook (after ./configure)
platform_post_configure() {
  : # No-op
}

# Build Hadrian binary (can override for custom toolchain)
# Sets: HADRIAN_BUILD array via nameref $1
platform_build_hadrian() {
  # Pass through the variable name directly to avoid circular nameref
  build_hadrian_binary "$1"
}

# Pre-stage1 hook (before stage1 build)
platform_pre_stage1() {
  : # No-op
}

# Post-stage1 hook (after stage1 build)
platform_post_stage1() {
  : # No-op
}

# Pre-stage2 hook (before stage2 build)
platform_pre_stage2() {
  : # No-op
}

# Post-stage2 hook (after stage2 build)
platform_post_stage2() {
  : # No-op
}

# ==============================================================================
# INSTALLATION HOOKS
# ==============================================================================

# Set installation method
# Sets: INSTALL_METHOD ("native" or "bindist")
platform_install_method() {
  INSTALL_METHOD="native"
}

# Install using native method (hadrian install)
platform_install_native() {
  install_ghc HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
}

# Install using bindist method (cross-compile)
platform_install_bindist() {
  echo "ERROR: Bindist installation not implemented for this platform"
  return 1
}

# Post-install hook (after installation complete)
platform_post_install() {
  : # No-op
}
