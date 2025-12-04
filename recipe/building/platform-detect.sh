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

  # Determine platform configuration file based on target_platform
  # The platform config is named after the TARGET, not the build machine
  case "${target_platform}" in
    linux-64)
      platform_config="linux-64"
      PLATFORM_NAME="Linux x86_64 (native)"
      ;;
    linux-aarch64|linux-ppc64le)
      # Cross-compilation targets share linux-cross.sh
      platform_config="linux-cross"
      PLATFORM_NAME="Linux ${target_platform#linux-} (cross-compiled from ${build_platform})"
      ;;
    osx-64)
      platform_config="osx-64"
      PLATFORM_NAME="macOS x86_64 (native)"
      ;;
    osx-arm64)
      platform_config="osx-arm64"
      PLATFORM_NAME="macOS arm64 (cross-compiled from x86_64)"
      ;;
    win-64)
      platform_config="win-64"
      PLATFORM_NAME="Windows x86_64 (MinGW-w64 UCRT)"
      ;;
    *)
      echo "ERROR: Unknown target platform: ${target_platform}"
      exit 1
      ;;
  esac

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
