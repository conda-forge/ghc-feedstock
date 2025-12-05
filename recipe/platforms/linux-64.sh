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
    # Force system GMP (in case configure still defaults to intree)
    echo "  Ensuring system GMP is used (not intree)..."
    perl -pi -e "s#^intree-gmp\s*=\s*.*#intree-gmp = NO#" "${config_file}"
    echo "  ✓ intree-gmp = NO set in system.config"

    # Fix touch command (GHC 9.2.8 bug: --enable-distro-toolchain sets touchy.exe even on Linux)
    echo "  Fixing touch command (touchy.exe -> touch)..."
    perl -pi -e 's#\$\$topdir/bin/touchy\.exe#touch#' "${config_file}"
    echo "  ✓ settings-touch-command = touch"

    # Add -fPIC to C compiler flags for PIE compatibility
    # Modern Linux toolchains default to PIE, so C code needs -fPIC
    echo "  Adding -fPIC to C compiler flags for PIE compatibility..."
    # Process each stage separately to avoid regex issues
    for stage in 0 1 2 3; do
      perl -pi -e "s#^(conf-cc-args-stage${stage}\\s*=\\s*)#\$1-fPIC #" "${config_file}"
    done
    perl -pi -e 's#^(settings-c-compiler-flags\s*=\s*)#$1-fPIC #' "${config_file}"
    echo "  ✓ -fPIC added to C compiler flags"
  fi
}
