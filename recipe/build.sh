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

BUILD_START_TIME=$(date +%s)

echo ""
echo "===================================================================="
echo "  GHC ${PKG_VERSION} Build"
echo "  Platform: ${PLATFORM_NAME}"
echo "  CPU_COUNT: ${CPU_COUNT:-unknown}"
echo "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "===================================================================="
echo ""

# Phase 1: Environment Setup
phase_setup_environment

# Phase 2: Bootstrap Setup
phase_setup_bootstrap

# Phase 3: Cabal Setup
phase_setup_cabal

# Phase 4: Configure GHC
phase_configure_ghc

# Phase 5: Build Hadrian
phase_build_hadrian

# Phase 6: Build Stage 1
phase_build_stage1

# Phase 7: Build Stage 2
phase_build_stage2

# Phase 8: Install GHC
phase_install_ghc

# Phase 9: Post-Install
phase_post_install

# Phase 10: Activation
phase_activation

# ==============================================================================
# BUILD COMPLETE
# ==============================================================================

BUILD_END_TIME=$(date +%s)
BUILD_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))
BUILD_HOURS=$((BUILD_DURATION / 3600))
BUILD_MINUTES=$(((BUILD_DURATION % 3600) / 60))
BUILD_SECONDS=$((BUILD_DURATION % 60))

echo ""
echo "===================================================================="
echo "  ✓ GHC ${PKG_VERSION} Build Complete"
echo "===================================================================="
echo "  Platform:   ${PLATFORM_NAME}"
echo "  CPU_COUNT:  ${CPU_COUNT:-unknown}"
echo "  Installed:  ${PREFIX}"
echo "  Total time: ${BUILD_HOURS}h ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
echo "===================================================================="
echo "(Per-phase timings shown above after each '✓ ... completed in')"
echo ""
