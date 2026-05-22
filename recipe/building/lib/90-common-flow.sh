#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Common Build Flow
# ==============================================================================
# Purpose: Standardized build flow used by all platforms
#
# This module defines the common build sequence that all platforms follow.
# Platform-specific behavior is customized via hook functions implemented
# in platform config files (building/config/*.sh).
#
# Dependencies:
#   - 00-logging.sh (run_and_log)
#   - 80-build-orchestrator.sh (build functions)
#   - Platform config with hook implementations
#
# Usage:
#   source lib/90-common-flow.sh
#   common_flow_initialize
#   common_flow_detect_architecture
#   # ... etc
# ==============================================================================

set -eu

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Initialize common flow
# - Reset logging index
# - Load common modules
# - Display platform banner
#
common_flow_initialize() {
  echo "===================================================================="
  echo "  GHC Conda-Forge Build"
  echo "  Platform: ${PLATFORM_NAME:-detecting...}"
  echo "  Type: ${PLATFORM_TYPE:-detecting...}"
  echo "  GHC Version: ${PKG_VERSION}"
  echo "===================================================================="

  # Initialize logging index
  _log_index=0

  # Common modules already loaded via build.sh → common.sh
  # Just verify they're available
  if ! type -t run_and_log >/dev/null 2>&1; then
    echo "ERROR: run_and_log function not found"
    echo "  Ensure common.sh has been sourced"
    return 1
  fi
}

# ==============================================================================
# ARCHITECTURE DETECTION
# ==============================================================================

# Detect architecture and set variables
# Calls: platform_detect_architecture hook
#
common_flow_detect_architecture() {
  echo ""
  echo "=== Architecture Detection ==="
  platform_detect_architecture
  echo "  Detection complete"
  echo ""
}

# ==============================================================================
# BOOTSTRAP SETUP
# ==============================================================================

# Set up bootstrap environment (GHC, Cabal, etc.)
# Calls: platform_setup_bootstrap hook
#
common_flow_setup_bootstrap() {
  echo ""
  echo "=== Bootstrap Setup ==="
  platform_setup_bootstrap

  # Verify bootstrap GHC if set
  if [[ -n "${GHC:-}" ]]; then
    echo "  Bootstrap GHC: ${GHC}"
    "${GHC}" --version || {
      echo "ERROR: Bootstrap GHC failed"
      return 1
    }
  fi
  echo ""
}

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

# Set up platform-specific environment
# Calls: platform_setup_environment hook
#
common_flow_setup_environment() {
  echo ""
  echo "=== Platform Environment Setup ==="
  platform_setup_environment
  echo "  Environment configured"
  echo ""
}

# ==============================================================================
# CABAL SETUP
# ==============================================================================

# Set up Cabal environment and update package index
# Calls: platform_setup_cabal hook
#
common_flow_setup_cabal() {
  echo ""
  echo "=== Cabal Setup ==="
  platform_setup_cabal

  # Standard cabal initialization (unless platform overrides)
  if [[ -z "${CABAL_SKIP_INIT:-}" ]]; then
    if [[ -n "${CABAL:-}" && -n "${CABAL_DIR:-}" ]]; then
      mkdir -p "${CABAL_DIR}"

      # Only init if config doesn't exist (avoid "already exists" error)
      if [[ ! -f "${CABAL_DIR}/config" ]]; then
        "${CABAL}" user-config init
      else
        echo "  Cabal config already exists, skipping init"
      fi

      run_and_log "cabal-update" "${CABAL}" v2-update
    else
      echo "WARNING: CABAL or CABAL_DIR not set, skipping initialization"
    fi
  fi
  echo ""
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Configure GHC build system
# Calls: platform_build_system_config, platform_build_configure_args,
#        platform_pre_configure, configure_ghc, platform_post_configure
#
common_flow_configure() {
  echo ""
  echo "=== Configuration Phase ==="

  # Build config arrays
  echo "  Building system config..."
  declare -a SYSTEM_CONFIG
  platform_build_system_config

  echo "  Building configure arguments..."
  declare -a CONFIGURE_ARGS
  platform_build_configure_args

  # Pre-configure hook
  echo "  Running pre-configure hook..."
  platform_pre_configure

  # Run configure
  echo "  Running GHC configure..."
  configure_ghc SYSTEM_CONFIG CONFIGURE_ARGS

  # Post-configure hook
  echo "  Running post-configure hook..."
  platform_post_configure

  echo "  Configuration complete"
  echo ""
}

# ==============================================================================
# HADRIAN BUILD
# ==============================================================================

# Build Hadrian binary
# Calls: platform_build_hadrian hook
#
common_flow_build_hadrian() {
  echo ""
  echo "=== Hadrian Build ==="

  # Declare HADRIAN_BUILD as global (no 'local', accessible to other functions)
  HADRIAN_BUILD=()

  # Platform can override with custom args
  platform_build_hadrian HADRIAN_BUILD

  echo "  Hadrian command: ${HADRIAN_BUILD[*]}"
  echo ""
}

# ==============================================================================
# BUILD STAGES
# ==============================================================================

# Build GHC stage 1 and stage 2
# Calls: platform_select_flavour, platform_pre_stage1, build_stage1,
#        platform_post_stage1, platform_pre_stage2, build_stage2,
#        platform_post_stage2
#
# Platform can override by providing platform_build_stage1/platform_build_stage2
#
common_flow_build_stages() {
  echo ""
  echo "=== Build Stages ==="

  # Select flavour(s)
  echo "  Selecting build flavour..."
  platform_select_flavour

  # Stage 1
  echo ""
  echo "  --- Stage 1 ---"
  echo "  Flavour: ${HADRIAN_FLAVOUR_STAGE1:-${HADRIAN_FLAVOUR}}"

  platform_pre_stage1

  # Check if platform provides custom stage1 build
  if type -t platform_build_stage1 >/dev/null 2>&1; then
    echo "  Using platform-specific stage1 build"
    platform_build_stage1 HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE1:-${HADRIAN_FLAVOUR}}"

    # Check for additional platform hooks (e.g., osx-arm64 libs)
    if type -t platform_build_stage1_libs >/dev/null 2>&1; then
      platform_build_stage1_libs HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE1:-${HADRIAN_FLAVOUR}}"
    fi
  else
    build_stage1 HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE1:-${HADRIAN_FLAVOUR}}"
  fi

  platform_post_stage1

  # Stage 2
  echo ""
  echo "  --- Stage 2 ---"
  echo "  Flavour: ${HADRIAN_FLAVOUR_STAGE2:-${HADRIAN_FLAVOUR}}"

  platform_pre_stage2

  # Check if platform provides custom stage2 build
  if type -t platform_build_stage2 >/dev/null 2>&1; then
    echo "  Using platform-specific stage2 build"
    platform_build_stage2 HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE2:-${HADRIAN_FLAVOUR}}"
  else
    build_stage2 HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE2:-${HADRIAN_FLAVOUR}}"
  fi

  # Check for additional platform hooks (e.g., osx-arm64 Cabal-syntax race prevention)
  if type -t platform_build_cabal_syntax >/dev/null 2>&1; then
    platform_build_cabal_syntax HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE2:-${HADRIAN_FLAVOUR}}"
  fi

  platform_post_stage2

  echo ""
  echo "  Build stages complete"
  echo ""
}

# ==============================================================================
# INSTALLATION
# ==============================================================================

# Install GHC to PREFIX
# Calls: platform_install_method, platform_install_native or
#        platform_install_bindist, platform_post_install
#
# Platform can override by providing platform_install function
#
common_flow_install() {
  echo ""
  echo "=== Installation Phase ==="

  # Check if platform provides custom install
  if type -t platform_install >/dev/null 2>&1; then
    echo "  Using platform-specific installation"
    platform_install HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
  else
    # Determine installation method
    platform_install_method
    echo "  Installation method: ${INSTALL_METHOD}"

    # Execute installation
    if [[ "${INSTALL_METHOD}" == "native" ]]; then
      echo "  Installing using native method..."
      platform_install_native
    elif [[ "${INSTALL_METHOD}" == "bindist" ]]; then
      echo "  Installing using bindist method..."
      platform_install_bindist
    else
      echo "ERROR: Unknown INSTALL_METHOD: ${INSTALL_METHOD}"
      return 1
    fi
  fi

  # Post-install hook
  echo "  Running post-install hook..."
  platform_post_install

  echo "  Installation complete"
  echo ""
}

# ==============================================================================
# COMPLETE FLOW
# ==============================================================================

# Execute complete build flow (all phases)
# This is a convenience function that runs all phases in order
#
common_flow_execute_all() {
  common_flow_initialize
  common_flow_detect_architecture
  common_flow_setup_bootstrap
  common_flow_setup_environment
  common_flow_setup_cabal
  common_flow_configure
  common_flow_build_hadrian
  common_flow_build_stages
  common_flow_install

  echo "===================================================================="
  echo "  BUILD COMPLETED SUCCESSFULLY"
  echo "  Platform: ${PLATFORM_NAME}"
  echo "  GHC ${PKG_VERSION} installed to: ${PREFIX}"
  echo "===================================================================="
}
