#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build - Unified Build Script
# ==============================================================================
# This script orchestrates the complete GHC build process for all platforms.
#
# BUILD PHASES (in order):
#   1. Environment Setup    - Paths, compilers, flags
#   2. Bootstrap Setup      - Bootstrap GHC configuration
#   3. Cabal Setup          - Cabal package manager
#   4. Configure GHC        - GHC build system configuration
#   5. Build Hadrian        - Build the Hadrian build tool
#   6. Build Stage 1        - Build Stage 1 GHC compiler
#   7. Build Stage 2        - Build Stage 2 GHC libraries
#   8. Install GHC          - Install GHC to PREFIX
#   9. Post-Install         - Verification and cleanup
#
# Platform-specific behavior is customized via functions in:
#   building/platforms/xxx.sh
#
# Each platform can override any phase by defining:
#   platform_xxx()          - Replace default implementation
#   platform_pre_xxx()      - Hook before phase
#   platform_post_xxx()     - Hook after phase
# ==============================================================================

set -eu

# ==============================================================================
# CRITICAL: Ensure we're using conda bash 5.2+, not system bash
# ==============================================================================
if [[ ${BASH_VERSINFO[0]} -lt 5 || (${BASH_VERSINFO[0]} -eq 5 && ${BASH_VERSINFO[1]} -lt 2) ]]; then
  echo "re-exec with conda bash..."
  if [[ -x "${BUILD_PREFIX}/bin/bash" ]]; then
    exec "${BUILD_PREFIX}/bin/bash" "$0" "$@"
  else
    echo "ERROR: Could not find conda bash at ${BUILD_PREFIX}/bin/bash"
    exit 1
  fi
fi

# ==============================================================================
# FRAMEWORK SETUP
# ==============================================================================

# Set up directories
mkdir -p _logs

# Load framework modules
source "${RECIPE_DIR}/building/platform-detect.sh"
source "${RECIPE_DIR}/building/common-functions.sh"

# Detect platform and load configuration
# This sets PLATFORM_NAME and sources building/platforms/xxx.sh
detect_platform

# ==============================================================================
# BUILD EXECUTION
# ==============================================================================

echo ""
echo "===================================================================="
echo "  GHC ${PKG_VERSION} Build"
echo "  Platform: ${PLATFORM_NAME}"
echo "===================================================================="
echo ""

# ----------------------------------------------------------------------------
# Phase 1: Environment Setup
# ----------------------------------------------------------------------------
# Configure build environment: paths, compilers, flags
# Platform hooks:
#   - platform_pre_setup_environment()
#   - platform_setup_environment()        [or default_setup_environment()]
#   - platform_post_setup_environment()

phase_setup_environment

# ----------------------------------------------------------------------------
# Phase 2: Bootstrap Setup
# ----------------------------------------------------------------------------
# Configure bootstrap GHC compiler
# Platform hooks:
#   - platform_pre_setup_bootstrap()
#   - platform_setup_bootstrap()          [or default_setup_bootstrap()]
#   - platform_post_setup_bootstrap()

phase_setup_bootstrap

# ----------------------------------------------------------------------------
# Phase 3: Cabal Setup
# ----------------------------------------------------------------------------
# Configure Cabal package manager
# Platform hooks:
#   - platform_pre_setup_cabal()
#   - platform_setup_cabal()              [or default_setup_cabal()]
#   - platform_post_setup_cabal()

phase_setup_cabal

# ----------------------------------------------------------------------------
# Phase 4: Configure GHC
# ----------------------------------------------------------------------------
# Run GHC's configure script
# Platform hooks:
#   - platform_pre_configure_ghc()
#   - platform_configure_ghc()            [or default_configure_ghc()]
#   - platform_add_configure_args()       (modifies configure args)
#   - platform_post_configure_ghc()

phase_configure_ghc

# ----------------------------------------------------------------------------
# Phase 5: Build Hadrian
# ----------------------------------------------------------------------------
# Build the Hadrian build tool
# Platform hooks:
#   - platform_pre_build_hadrian()
#   - platform_build_hadrian()            [or default_build_hadrian()]
#   - platform_post_build_hadrian()

phase_build_hadrian

# ----------------------------------------------------------------------------
# Phase 6: Build Stage 1
# ----------------------------------------------------------------------------
# Build Stage 1 GHC compiler
# Platform hooks:
#   - platform_pre_build_stage1()
#   - platform_build_stage1()             [or default_build_stage1()]
#   - platform_post_build_stage1()        ⭐ Windows: touchy rebuild here

phase_build_stage1

# ----------------------------------------------------------------------------
# Phase 7: Build Stage 2
# ----------------------------------------------------------------------------
# Build Stage 2 GHC libraries
# Platform hooks:
#   - platform_pre_build_stage2()         ⭐ Windows: fake mingw here
#   - platform_build_stage2()             [or default_build_stage2()]
#   - platform_post_build_stage2()

phase_build_stage2

# ----------------------------------------------------------------------------
# Phase 8: Install GHC
# ----------------------------------------------------------------------------
# Install GHC to PREFIX
# Platform hooks:
#   - platform_pre_install_ghc()
#   - platform_install_ghc()              [or default_install_ghc()]
#   - platform_post_install_ghc()

phase_install_ghc

# ----------------------------------------------------------------------------
# Phase 9: Post-Install
# ----------------------------------------------------------------------------
# Verification and cleanup
# Platform hooks:
#   - platform_pre_post_install()
#   - platform_post_install()             [or default_post_install()]
#   - platform_post_post_install()

phase_post_install

# ==============================================================================
# BUILD COMPLETE
# ==============================================================================

echo ""
echo "===================================================================="
echo "  ✓ GHC ${PKG_VERSION} Build Complete"
echo "  Platform: ${PLATFORM_NAME}"
echo "  Installed to: ${PREFIX}"
echo "===================================================================="
echo ""
