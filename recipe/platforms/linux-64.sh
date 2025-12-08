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
  # Use standardized system.config patching
  patch_system_config_linker_flags
}
