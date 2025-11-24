#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Architecture Calculation Module
# ==============================================================================
# Purpose: Calculate and export architecture variables for GHC build
#
# Functions:
#   calculate_build_architecture(debug)       - Detect cross-compile status
#   get_bootstrap_settings_path()             - Find bootstrap compiler settings
#
# Dependencies: None for calculate_build_architecture
#               Requires ${GHC} for get_bootstrap_settings_path
#
# Usage:
#   source lib/40-architecture.sh
#   calculate_build_architecture
#   bootstrap_settings=$(get_bootstrap_settings_path)
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

# Get the settings file path for the bootstrap GHC compiler
#
# This function dynamically finds the bootstrap compiler's settings file,
# avoiding hardcoded paths like '/ghc-bootstrap/'. This allows flexibility
# in choosing bootstrap compilers (ghc-bootstrap package, previous GHC version, etc.).
#
# Returns (stdout): Path to bootstrap settings file (e.g., /path/to/lib/settings)
# Returns (exit): 0 on success, 1 if settings not found
#
# Usage:
#   bootstrap_settings=$(get_bootstrap_settings_path)
#   if [[ $? -eq 0 ]]; then
#     echo "Bootstrap settings: ${bootstrap_settings}"
#   fi
#
# Dependencies: Requires ${GHC} to be set (bootstrap GHC executable)
#
get_bootstrap_settings_path() {
  if [[ -z "${GHC:-}" ]]; then
    echo "ERROR: GHC variable not set - cannot find bootstrap settings" >&2
    return 1
  fi

  # Ask GHC where its library directory is
  local ghc_libdir
  ghc_libdir=$("${GHC}" --print-libdir 2>/dev/null)
  if [[ $? -ne 0 || -z "${ghc_libdir}" ]]; then
    echo "ERROR: Could not get libdir from ${GHC}" >&2
    return 1
  fi

  # Settings file is always at libdir/settings
  local settings_file="${ghc_libdir}/settings"
  if [[ ! -f "${settings_file}" ]]; then
    echo "ERROR: Settings file not found at ${settings_file}" >&2
    return 1
  fi

  # Return the path
  echo "${settings_file}"
  return 0
}
