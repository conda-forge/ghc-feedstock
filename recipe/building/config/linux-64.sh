#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux x86_64 Native Build
# ==============================================================================
# Purpose: Configuration for native Linux x86_64 GHC builds
#
# This is a simple native build with minimal customization.
# Most hooks use defaults from common-hooks.sh.
#
# Dependencies: common-hooks.sh (for defaults)
# ==============================================================================

set -eu

# Load common hook defaults
source "${RECIPE_DIR}/building/config/common-hooks.sh"

# ==============================================================================
# PLATFORM METADATA
# ==============================================================================

PLATFORM_NAME="linux-64"
PLATFORM_TYPE="native"
INSTALL_METHOD="native"

# ==============================================================================
# ARCHITECTURE DETECTION
# ==============================================================================

# Simple for native build - no cross-compilation complexity
platform_detect_architecture() {
  ghc_host="x86_64-unknown-linux"
  ghc_target="x86_64-unknown-linux"

  echo "  GHC host: ${ghc_host}"
  echo "  GHC target: ${ghc_target}"
}

# ==============================================================================
# BOOTSTRAP (uses BUILD_PREFIX tools - no-op)
# ==============================================================================

# platform_setup_bootstrap() - Use default (no-op)
# Bootstrap GHC and Cabal are already in BUILD_PREFIX

# ==============================================================================
# ENVIRONMENT (uses conda-build defaults - no-op)
# ==============================================================================

# platform_setup_environment() - Use default (no-op)
# Standard Linux environment from conda-build is sufficient

# ==============================================================================
# CABAL SETUP (uses default)
# ==============================================================================

# platform_setup_cabal() - Use default
# Sets CABAL="${BUILD_PREFIX}/bin/cabal" and CABAL_DIR="${SRC_DIR}/.cabal"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# System configuration: --build and --host
platform_build_system_config() {
  SYSTEM_CONFIG=(
    --build="${ghc_host}"
    --host="${ghc_host}"
  )
}

# Configure arguments: Use lib function for standard args
platform_build_configure_args() {
  build_configure_args CONFIGURE_ARGS
}

# ==============================================================================
# BUILD FLAVOUR
# ==============================================================================

# Select Hadrian flavour based on GHC version
platform_select_flavour() {
  # GHC 9.2.8 doesn't have 'release' flavour, must use 'quick'
  # GHC 9.4.8+ use 'release' for full optimization
  if [[ "${PKG_VERSION}" == "9.2.8"* ]]; then
    HADRIAN_FLAVOUR="quick"
  else
    HADRIAN_FLAVOUR="release"
  fi

  echo "  Selected flavour: ${HADRIAN_FLAVOUR}"
}

# ==============================================================================
# BUILD HOOKS (all use defaults - no customization needed)
# ==============================================================================

# platform_pre_configure() - Use default (no-op)
# platform_post_configure() - Use default (no-op)
# platform_build_hadrian() - Use default (calls build_hadrian_binary)
# platform_pre_stage1() - Use default (no-op)
# platform_post_stage1() - Use default (no-op)
# platform_pre_stage2() - Use default (no-op)
# platform_post_stage2() - Use default (no-op)

# ==============================================================================
# INSTALLATION (uses default native install)
# ==============================================================================

# platform_install_method() - Use default (sets INSTALL_METHOD="native")
# platform_install_native() - Use default (calls install_ghc)
# platform_post_install() - Use default (no-op)
