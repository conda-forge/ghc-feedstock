#!/usr/bin/env bash
# ==============================================================================
# Platform Detection - Simple and Clear
# ==============================================================================
# Detects build platform and loads appropriate configuration.
# Sets PLATFORM_NAME and sources the platform-specific config file.
# ==============================================================================

set -eu

detect_platform() {
  local platform_config=""

  # Default build_platform to target_platform if not set (native builds)
  : "${build_platform:=${target_platform}}"

  echo "===================================================================="
  echo "  Platform Detection"
  echo "===================================================================="
  echo "  Build platform:  ${build_platform}"
  echo "  Target platform: ${target_platform}"

  # Determine platform configuration file
  if [[ "${build_platform}" != "${target_platform}" ]]; then
    # Cross-compilation
    if [[ "${target_platform}" =~ darwin|osx ]]; then
      platform_config="osx-arm64"
      PLATFORM_NAME="macOS arm64 (cross-compiled from x86_64)"
    else
      platform_config="linux-cross"
      PLATFORM_NAME="Linux cross-compile (${build_platform} → ${target_platform})"
    fi
  else
    # Native builds
    if [[ "${build_platform}" =~ darwin|osx ]]; then
      platform_config="osx-64"
      PLATFORM_NAME="macOS x86_64 (native)"
    elif [[ "${build_platform}" =~ win ]]; then
      platform_config="win-64"
      PLATFORM_NAME="Windows x86_64 (MinGW-w64 UCRT)"
    else
      platform_config="linux-64"
      PLATFORM_NAME="Linux x86_64 (native)"
    fi
  fi

  # Load platform configuration
  local config_file="${RECIPE_DIR}/building/platforms/${platform_config}.sh"

  if [[ ! -f "${config_file}" ]]; then
    echo "ERROR: Platform config not found: ${config_file}"
    echo "  Available configs:"
    ls -1 "${RECIPE_DIR}/building/platforms/"*.sh 2>/dev/null || echo "  (none)"
    exit 1
  fi

  echo "  Platform: ${PLATFORM_NAME}"
  echo "  Loading:  ${config_file}"
  echo "===================================================================="
  echo ""

  source "${config_file}"
}
