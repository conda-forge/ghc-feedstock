#!/usr/bin/env bash
# build.sh - DOMAIN SPLIT entry point
# Organized by WHAT (configure, build, install) not by WHO (platform)
# Each domain file contains ALL platform logic for its concern

set -eu

# Ensure Bash 5.2+
if [[ ${BASH_VERSINFO[0]} -lt 5 || (${BASH_VERSINFO[0]) -eq 5 && ${BASH_VERSINFO[1]} -lt 2) ]]; then
    # Use _BUILD_PREFIX (Unix format) for Windows compatibility
    bash_path="${_BUILD_PREFIX:-${BUILD_PREFIX}}/bin/bash"
    exec "${bash_path}" "$0" "$@"
fi

# Source support utilities
source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"

# Source domain modules (each handles ALL platforms for its concern)
source "${RECIPE_DIR}/domains/environment.sh"  # ALL environment setup
source "${RECIPE_DIR}/domains/configure.sh"    # ALL configure logic
source "${RECIPE_DIR}/domains/build.sh"        # ALL build logic
source "${RECIPE_DIR}/domains/settings.sh"     # ALL settings patching
source "${RECIPE_DIR}/domains/install.sh"      # ALL install logic

#=============================================================================
# MAIN BUILD FLOW
#=============================================================================
# Navigation tip: Want to understand configure?
#   → Open domains/configure.sh - EVERYTHING about configure is there
# Want to understand install?
#   → Open domains/install.sh - ALL platforms, ALL install logic

echo "===================================================================="
echo "  GHC ${PKG_VERSION} for ${target_platform}"
echo "  Style: DOMAIN SPLIT (organized by concern, not platform)"
echo "===================================================================="

setup_environment      # domains/environment.sh - ALL platform env setup
configure_ghc          # domains/configure.sh - ALL configure logic
post_configure_ghc     # domains/configure.sh - ALL post-configure
build_hadrian          # domains/build.sh - ALL Hadrian build
build_stage1           # domains/build.sh - ALL stage1 build
build_stage2           # domains/build.sh - ALL stage2 build
install_ghc            # domains/install.sh - ALL install
post_install_ghc       # domains/install.sh - ALL post-install

echo "  ✓ Build complete"
