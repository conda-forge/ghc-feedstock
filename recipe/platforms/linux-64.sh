#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux x86_64 (Native)
# ==============================================================================
# Linux-specific build behavior.
# Most phases use defaults from common-functions.sh
# ==============================================================================

set -eu

# Source common hook defaults (provides no-op implementations)
source "${RECIPE_DIR}/lib/common-hooks.sh"

# Platform metadata
PLATFORM_NAME="Linux x86_64 (native)"
PLATFORM_TYPE="native"
INSTALL_METHOD="bindist"

# ==============================================================================
# Platform Triple Configuration
# ==============================================================================

# Use standardized native triple configuration
# Sets: ghc_triple, build_alias, host_alias
configure_native_triple

# ==============================================================================
# Phase 4b: Post-Configure (patch Hadrian system.config)
# ==============================================================================

platform_post_configure_ghc() {
  local config_file="${SRC_DIR}/hadrian/cfg/system.config"

  # Use standardized system.config patching
  patch_system_config_linker_flags

  if [[ -f "${config_file}" ]]; then
    # Apply version-specific fixes using the version-fixes library
    # This handles intree-gmp bug, touchy.exe bug, and PIE relocation issues
    # based on the GHC version being built
    apply_version_specific_fixes "${config_file}" "linux-64"
  fi
}
