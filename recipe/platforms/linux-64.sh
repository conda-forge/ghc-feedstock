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
FLAVOUR="release"

# ==============================================================================
# Platform Triple Configuration
# ==============================================================================

# Configure all triple variables (auto-detects native mode)
# Sets: ghc_build, ghc_host, ghc_target, ghc_triple, conda_*, *_arch
configure_triples

# ==============================================================================
# Phase 4b: Post-Configure (uses shared orchestrator for consistency)
# ==============================================================================

platform_post_configure_ghc() {
  # Use shared orchestrator (auto-detects native Linux and applies linker-flags + doc-placeholders)
  shared_post_configure_ghc "${ghc_triple}"
}

# ==============================================================================
# Stage Settings Hook (exe→patch→lib pattern)
# ==============================================================================

# Unified stage settings patch hook for consistent build flow
platform_patch_stage_settings() {
  local stage="$1"
  local settings_file="${SRC_DIR}/_build/${stage}/lib/settings"
  _patch_stage_linker_flags "${settings_file}"
}
