#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: macOS x86_64 (Native)
# ==============================================================================
# macOS-specific native build behavior.
#
# Key implementation details:
# - Creates libiconv_compat.dylib for conda libiconv compatibility
# - Uses DYLD_INSERT_LIBRARIES for library preloading
# - Uses llvm-ar for Apple ld64 compatibility
# - Applies -fno-lto to prevent ABI mismatches
# ==============================================================================

set -eu

source "${RECIPE_DIR}/lib/common-hooks.sh"
source "${RECIPE_DIR}/lib/macos-common.sh"

# Platform metadata
PLATFORM_NAME="macOS x86_64 (native)"
PLATFORM_TYPE="native"
INSTALL_METHOD="bindist"
FLAVOUR="release+omit_pragmas"

# ==============================================================================
# Platform Triple Configuration
# ==============================================================================

# Configure all triple variables (auto-detects native mode)
# Sets: ghc_build, ghc_host, ghc_target, ghc_triple, conda_*, *_arch
configure_triples

# ==============================================================================
# Platform Hooks
# ==============================================================================

platform_setup_environment() {
  unset build_alias host_alias  # Interferes with configure scripts
  macos_complete_setup          # Creates iconv compat, sets AR, DYLD env, patches bootstrap
  export PATH="${BUILD_PREFIX}/bin:${PATH}"
}

# ==============================================================================
# Hooks Using Smart Defaults
# ==============================================================================
# The following hooks are now handled by smart defaults:
#
#   configure_ghc         → default_configure_ghc() delegates to shared_configure_ghc()
#   post_configure_ghc    → default_post_configure_ghc() auto-detects native macOS
#   patch_stage_settings  → shared_patch_stage_settings() auto-detects macOS
#
# No platform overrides needed - macOS native uses all defaults except environment.

platform_post_install() {
  shared_post_install_ghc "${ghc_triple}"
}
