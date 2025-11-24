#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Architecture Calculation Module
# ==============================================================================
# Purpose: Calculate and export architecture variables for GHC build
#
# Functions:
#   calculate_build_architecture(debug)
#
# Dependencies: None
#
# Usage:
#   source lib/40-architecture.sh
#   calculate_build_architecture
#   echo "Building GHC for: ${target_platform}"
# ==============================================================================

set -eu

# Calculate and export architecture variables for GHC build
#
# GHC uses different architecture naming conventions than conda.
# This function standardizes the calculation based solely on target_platform.
#
# Sets these global variables:
#   IS_CROSS_COMPILE             - "true" or "false" (derived from conda variables)
#
# Note: This module intentionally does NOT set build_alias, host_alias, target_alias
#       to avoid confusion. Use target_platform consistently instead.
#
# Usage:
#   calculate_build_architecture
#   echo "Building GHC for: ${target_platform}"
#
# Parameters:
#   $1 - debug: Set to "true" to print calculated values (default: "false")
#
calculate_build_architecture() {
  local debug="${1:-false}"

  # Determine if cross-compiling based on conda's build_platform and target_platform
  # Note: build_platform may not be defined for native builds
  export IS_CROSS_COMPILE="false"
  if [[ -n "${build_platform:-}" && "${build_platform}" != "${target_platform}" ]]; then
    IS_CROSS_COMPILE="true"
  fi

  if [[ "$debug" == "true" ]]; then
    echo "=== Build Architecture ==="
    echo "  Target platform: ${target_platform}"
    echo "  Cross-compile: ${IS_CROSS_COMPILE}"
    echo "=========================="
  fi
}
