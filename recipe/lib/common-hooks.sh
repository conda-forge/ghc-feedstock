#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Common Hook Defaults
# ==============================================================================
# Purpose: Provide no-op default implementations for platform hooks that need
# defaults. Hooks that are never overridden have been removed - call_hook()
# safely handles missing hooks.
#
# Platform configs can source this file and override only the hooks they need.
#
# Hook Pattern:
#   - platform_xxx() overrides default_xxx() completely
#   - platform_pre_xxx() runs before the phase (via call_hook "pre_xxx")
#   - platform_post_xxx() runs after the phase (via call_hook "post_xxx")
#
# Usage:
#   source "${RECIPE_DIR}/lib/common-hooks.sh"
#
#   # Override only what you need:
#   platform_setup_environment() {
#     export MY_VAR="value"
#   }
#
# HOOK INVENTORY:
#   Defined here (with no-op defaults):
#     - Environment, Configure, Hadrian, Stage1, Stage2, Install, Post-Install
#   Not defined (never overridden, call_hook handles gracefully):
#     - Bootstrap, Cabal pre/post, Activation
#
# ==============================================================================
# VARIABLE NAMING CONVENTIONS
# ==============================================================================
# Both sets populated by configure_triples() from triple-helpers.sh:
#
# ghc_* variables (GHC format):
#   ghc_build, ghc_host, ghc_target, ghc_triple
#   Use for: ./configure arguments, display
#
# conda_* variables (Conda format):
#   conda_build, conda_host, conda_target
#   Use for: Toolchain paths (CC=../${conda_target}-clang), sysroots
#
# ==============================================================================
# SMART DEFAULTS (phases.sh, cross-helpers.sh)
# ==============================================================================
# The following hooks now have smart defaults that auto-detect platform:
#
#   default_post_configure_ghc()     - Auto-detects native/cross toolchain prefix
#   default_pre_build_stage1()       - Calls cross_pre_stage1_standard() for cross
#   default_build_stage1/2()         - Uses patch_settings dispatcher for Linux/macOS
#   default_cross_configure_ghc()    - Standard cross-compile configure
#
# Platforms only need to override if they have genuinely different behavior.
# ==============================================================================

set -eu

# ==============================================================================
# PHASE 1: ENVIRONMENT SETUP
# ==============================================================================
# Used by: linux-64 (default), linux-cross, osx-64, osx-arm64, win-64
# Overrides: platform_setup_environment()

# ==============================================================================
# PHASE 4: CONFIGURE GHC
# ==============================================================================
# Used by: linux-cross (configure + post), osx-64 (configure + post),
#          osx-arm64 (configure + post), win-64 (pre + default)
# Overrides: platform_pre_configure_ghc(), platform_configure_ghc(),
#            platform_post_configure_ghc()

platform_post_configure_ghc() {
  # Call smart default which auto-detects platform and applies appropriate patches
  default_post_configure_ghc
}

# ==============================================================================
# PHASE 5: BUILD HADRIAN
# ==============================================================================
# Used by: linux-cross (pre), osx-arm64 (pre), win-64 (build)
# Overrides: platform_pre_build_hadrian(), platform_build_hadrian()

# ==============================================================================
# PHASE 6-7: STAGE BUILD HOOKS
# ==============================================================================
# Used by: All platforms for unified exe→patch→lib build flow
#
# Hook Sequence for Stage Builds:
#   1. platform_pre_stage{1,2}_executables() - Before any executables
#   2. build ghc-bin
#   3. platform_post_stage{1,2}_ghc_bin() - After ghc-bin, before pkg/hsc2hs
#   4. build ghc-pkg, hsc2hs
#   5. platform_post_stage{1,2}_executables() - After all executables
#   6. platform_patch_stage_settings() - Between exe and lib builds
#   7. platform_pre_stage{1,2}_libraries() - Before libraries
#   8. build libraries (or platform_build_stage{1,2}_libraries() if defined)
#   9. platform_post_stage{1,2}_libraries() - After libraries
#
# Granular Hook (after ghc-bin):
#   platform_post_stage{1,2}_ghc_bin() - Called after ghc-bin build, before ghc-pkg
#   Use this for Windows settings patching between executable builds.
#
# Libraries Override Hook:
#   platform_build_stage{1,2}_libraries() - Completely replace library build
#   Use this for Windows which has different error handling.
#
# Example (Windows):
#   platform_post_stage1_ghc_bin() {
#     patch_windows_settings "${_SRC_DIR}/_build/stage0/lib/settings" --include-paths
#   }
#
# Stage settings patch hook - called between executables and libraries build
# Override to apply platform-specific settings patches (linker flags, llvm-ar, etc.)
#
# Parameters:
#   $1 - stage: "stage0" (during stage1 build) or "stage1" (during stage2 build)
#
# Example:
#   platform_patch_stage_settings() {
#     _patch_stage_linker_flags "${SRC_DIR}/_build/$1/lib/settings"
#   }
#
platform_patch_stage_settings() {
  : # No-op default - platforms override to add custom patches
}

# ==============================================================================
# PHASE 8: INSTALL GHC
# ==============================================================================
# Used by: linux-cross, osx-arm64, win-64
# Overrides: platform_install_ghc()

# ==============================================================================
# PHASE 9: POST-INSTALL
# ==============================================================================
# Used by: linux-cross, osx-64, osx-arm64, win-64
# Overrides: platform_post_install()

# ==============================================================================
# METADATA VARIABLES (optional, for documentation)
# ==============================================================================
# Platform configs can set these for self-documentation:
#
# PLATFORM_NAME="linux-64"       # Human-readable platform name
# PLATFORM_TYPE="native"         # "native" or "cross"
# INSTALL_METHOD="bindist"       # "native" (hadrian install) or "bindist"
