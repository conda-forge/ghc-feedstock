#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux x86_64 (Native)
# ==============================================================================
# Linux-specific build behavior.
# Most phases use defaults from phases.sh (call_hook falls back to default_*)
# ==============================================================================

set -eu

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
# Hooks Using Smart Defaults
# ==============================================================================
# The following hooks are handled by smart defaults in phases.sh:
#
#   post_configure_ghc    → default_post_configure_ghc() auto-detects native
#   patch_stage_settings  → default_build_stage1/2() uses patch_settings dispatcher
#
# No platform overrides needed - Linux native uses all defaults.
# ==============================================================================
