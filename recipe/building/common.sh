#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Common Function Library
# ==============================================================================
# This file sources modular function libraries from lib/ directory
# Functions are organized by purpose for easier maintenance
#
# Module loading order:
#   00-logging.sh       - Basic infrastructure (run_and_log)
#   10-settings.sh      - Settings file patching
#   20-autoconf.sh      - Autoconf variable management
#   30-configure.sh     - Configure argument builders
#   40-architecture.sh  - Architecture calculation
#   50-hadrian.sh       - Hadrian configuration
#   60-cross-compile.sh - Cross-compilation helpers
#   70-macos.sh         - macOS-specific functions
# ==============================================================================

set -eu

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source modules in order
for module in "${LIB_DIR}"/*.sh; do
  if [[ -f "$module" ]]; then
    source "$module"
  fi
done

# Validate critical functions are loaded
if ! type -t run_and_log >/dev/null; then
  echo "ERROR: run_and_log function not found - logging module failed to load"
  exit 1
fi

# Export functions for use in build scripts
export -f run_and_log
export -f set_macos_conda_ar_ranlib
export -f patch_macos_settings
export -f update_settings_link_flags
export -f update_installed_settings
export -f update_linux_link_flags
export -f update_osx_link_flags
export -f set_autoconf_toolchain_vars
export -f set_autoconf_macos_vars
export -f build_configure_args
export -f build_system_config
export -f calculate_build_architecture
export -f update_hadrian_system_config
export -f setup_cross_build_env
export -f build_hadrian_cross
export -f build_iconv_compat_dylib
export -f setup_macos_native_environment
export -f setup_macos_cross_environment
export -f fix_cross_architecture_defines
export -f fix_macos_bootstrap_settings

# Build orchestrator functions (lib/80-build-orchestrator.sh)
export -f build_hadrian_binary
export -f configure_ghc
export -f build_stage1
export -f build_stage2
export -f install_ghc
export -f create_bindist
export -f install_bindist

################################################################################
# Usage examples for build scripts (Bash 5.2+ required):
#
# 1. Source common.sh:
#    source "${RECIPE_DIR}"/building/common.sh
#
# 2. Set up build arrays:
#    declare -a SYSTEM_CONFIG=(--prefix="${PREFIX}")
#    declare -a CONFIGURE_ARGS
#    build_configure_args CONFIGURE_ARGS
#
# 3. Build using orchestrator (simple flow):
#    declare -a HADRIAN_BUILD
#    build_hadrian_binary HADRIAN_BUILD
#    configure_ghc SYSTEM_CONFIG CONFIGURE_ARGS
#    build_stage1 HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
#    build_stage2 HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
#    install_ghc HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
#
# 4. Platform-specific setup (before orchestrator):
#    setup_macos_native_environment  # macOS only
#    setup_cross_build_env "linux-64" "env_name"  # Cross-compile only
################################################################################
