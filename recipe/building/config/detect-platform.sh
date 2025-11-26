#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Platform Detection
# ==============================================================================
# Purpose: Detect build platform and load appropriate configuration
#
# This script determines which platform config to load based on conda-build
# environment variables. It supports version-specific overrides if needed.
#
# Usage:
#   source "${RECIPE_DIR}/building/config/detect-platform.sh"
#   detect_and_load_platform_config
#
# Platform Detection Logic:
#   1. Check if cross-compiling (build_platform != target_platform)
#   2. Check for macOS (darwin/osx in platform string)
#   3. Determine platform config file
#   4. Check for version-specific override
#   5. Load configuration
# ==============================================================================

set -eu

# Detect platform and load appropriate configuration
#
# Sets global variables:
#   PLATFORM_CONFIG_FILE - Path to loaded config file
#   PLATFORM_NAME - Descriptive platform name (set by config)
#   PLATFORM_TYPE - "native" or "cross" (set by config)
#
detect_and_load_platform_config() {
  local config_dir="${RECIPE_DIR}/building/config"
  local platform_config=""

  # Default build_platform to target_platform if not set (native builds)
  # build_platform is only set by conda-build during cross-compilation
  : "${build_platform:=${target_platform}}"

  echo "=== Platform Detection ==="
  echo "  build_platform: ${build_platform}"
  echo "  target_platform: ${target_platform}"

  # Determine if cross-compiling
  if [[ "${build_platform}" == "${target_platform}" ]]; then
    local is_cross="false"
  else
    local is_cross="true"
  fi

  # Detect platform configuration file
  if [[ "${is_cross}" == "true" ]]; then
    # Cross-compilation builds
    if [[ "${target_platform}" =~ darwin|osx ]]; then
      platform_config="osx-arm64"
      echo "  Detected: macOS cross-compile (x86_64 → arm64)"
      echo "  WARNING: osx-arm64 unified config not yet implemented"
      echo "  Falling back to original build-osx-arm64.sh script"
      # Source original script and return
      source "${RECIPE_DIR}/building/build-osx-arm64.sh"
      exit 0
    else
      platform_config="linux-cross"
      echo "  Detected: Linux cross-compile (${build_platform} → ${target_platform})"
    fi
  else
    # Native builds
    if [[ "${build_platform}" =~ darwin|osx ]]; then
      platform_config="osx-64"
      echo "  Detected: macOS native (x86_64)"
    elif [[ "${build_platform}" =~ linux ]]; then
      platform_config="linux-64"
      echo "  Detected: Linux native (x86_64)"
    else
      echo "ERROR: Unknown build platform: ${build_platform}"
      return 1
    fi
  fi

  # Check for version-specific override
  # Example: config/linux-64-v9.2.8.sh for GHC 9.2.8 specific changes
  local version_config="${config_dir}/${platform_config}-v${PKG_VERSION}.sh"
  local base_config="${config_dir}/${platform_config}.sh"

  if [[ -f "${version_config}" ]]; then
    echo "  Loading version-specific config: ${version_config}"
    PLATFORM_CONFIG_FILE="${version_config}"
    source "${version_config}"
  elif [[ -f "${base_config}" ]]; then
    echo "  Loading platform config: ${base_config}"
    PLATFORM_CONFIG_FILE="${base_config}"
    source "${base_config}"
  else
    echo "ERROR: Platform config not found: ${base_config}"
    echo "  Available configs:"
    ls -1 "${config_dir}"/*.sh 2>/dev/null || echo "  (none)"
    return 1
  fi

  echo "  Platform: ${PLATFORM_NAME}"
  echo "  Type: ${PLATFORM_TYPE}"
  echo "=========================="

  return 0
}
