#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: macOS x86_64 Native Build
# ==============================================================================
# Purpose: Configuration for native macOS x86_64 GHC builds
#
# macOS-specific quirks:
# - build_alias/host_alias must be unset (interfere with configure)
# - Requires libiconv compatibility library
# - Uses llvm-ar instead of system ar
# - Extensive settings file patching required
#
# Dependencies: common-hooks.sh (for defaults)
# ==============================================================================

set -eu

# Load common hook defaults
source "${RECIPE_DIR}/building/config/common-hooks.sh"

# ==============================================================================
# PLATFORM METADATA
# ==============================================================================

PLATFORM_NAME="osx-64"
PLATFORM_TYPE="native"
INSTALL_METHOD="native"

# ==============================================================================
# ARCHITECTURE DETECTION
# ==============================================================================

platform_detect_architecture() {
  ghc_host="x86_64-apple-darwin13.4.0"
  ghc_target="x86_64-apple-darwin13.4.0"

  echo "  GHC host: ${ghc_host}"
  echo "  GHC target: ${ghc_target}"
}

# ==============================================================================
# BOOTSTRAP (uses BUILD_PREFIX tools - no-op)
# ==============================================================================

# platform_setup_bootstrap() - Use default (no-op)

# ==============================================================================
# ENVIRONMENT
# ==============================================================================

platform_setup_environment() {
  # CRITICAL: Unset build_alias and host_alias
  # These interfere with configure scripts on macOS
  unset build_alias
  unset host_alias

  # Set up complete macOS environment (libiconv, DYLD, llvm-ar, etc.)
  setup_macos_native_environment
}

# ==============================================================================
# CABAL SETUP (uses default)
# ==============================================================================

# platform_setup_cabal() - Use default

# ==============================================================================
# CONFIGURATION
# ==============================================================================

platform_build_system_config() {
  SYSTEM_CONFIG=(
    --build="${ghc_host}"
    --host="${ghc_host}"
    --prefix="${PREFIX}"
  )
}

platform_build_configure_args() {
  build_configure_args CONFIGURE_ARGS

  # Set macOS-specific autoconf variables
  set_autoconf_macos_vars "false"

  # Clear DEVELOPER_DIR (prevents Xcode interference)
  export DEVELOPER_DIR=""
}

# ==============================================================================
# BUILD HOOKS
# ==============================================================================

# platform_pre_configure() - Use default (no-op)

platform_post_configure() {
  # Patch Hadrian config files to use llvm-ar and conda toolchain
  # Must happen AFTER configure but BEFORE building Hadrian
  echo "  Patching Hadrian config for llvm-ar..."
  set_macos_conda_ar_ranlib "${SRC_DIR}/hadrian/cfg/default.host.target" "${CONDA_TOOLCHAIN_BUILD}"
  set_macos_conda_ar_ranlib "${SRC_DIR}/hadrian/cfg/default.target" "${CONDA_TOOLCHAIN_BUILD}"
}

# platform_build_hadrian() - Use default

platform_select_flavour() {
  # macOS uses release+no_profiled_libs (profiled libs cause issues)
  HADRIAN_FLAVOUR="release+no_profiled_libs"

  echo "  Selected flavour: ${HADRIAN_FLAVOUR}"
}

platform_pre_stage1() {
  # Patch bootstrap compiler settings before building stage1
  # Bootstrap (stage0) compiler is used to build stage1
  # Use helper function to find settings dynamically (future-proof for different bootstrap sources)
  local bootstrap_settings
  bootstrap_settings=$(get_bootstrap_settings_path)
  if [[ $? -ne 0 ]]; then
    echo "  ERROR: Could not find bootstrap settings file"
    return 1
  fi

  echo "  Patching bootstrap (stage0) settings at ${bootstrap_settings}..."
  patch_macos_settings "${bootstrap_settings}"
}

platform_post_stage1() {
  # Patch stage1 compiler settings after it's built
  # Stage1 lives in _build/stage0/ (built BY stage0)
  # These settings will be used to build stage2
  local stage1_settings="${SRC_DIR}/_build/stage0/lib/settings"

  echo "  Patching stage1 settings (in _build/stage0/)..."
  if [[ -f "${stage1_settings}" ]]; then
    patch_macos_settings "${stage1_settings}"
  else
    echo "  WARNING: stage1 settings not found at ${stage1_settings}"
  fi
}

platform_pre_stage2() {
  # Re-patch stage1 settings before stage2 build (if Hadrian regenerated them)
  # Stage1 compiler (in _build/stage0/) will be used to build stage2
  local stage1_settings="${SRC_DIR}/_build/stage0/lib/settings"
  echo "  Re-patching stage1 settings..."
  if [[ -f "${stage1_settings}" ]]; then
    patch_macos_settings "${stage1_settings}"
  fi
}

# platform_post_stage2() - Use default (no-op)

# ==============================================================================
# INSTALLATION
# ==============================================================================

# platform_install_method() - Use default (sets INSTALL_METHOD="native")

platform_install_native() {
  # macOS uses custom install command (not the orchestrator default)
  # Needs explicit --docs=none and uses raw Hadrian command

  echo "  Installing GHC to ${PREFIX}..."
  run_and_log "install" \
    "${HADRIAN_BUILD[@]}" install \
    --prefix="${PREFIX}" \
    --flavour="${HADRIAN_FLAVOUR}" \
    --freeze1 \
    --freeze2 \
    --docs=none
}

platform_post_install() {
  echo "  Updating installed settings..."
  update_installed_settings

  # Patch ar/ranlib for installed settings
  local settings_file
  settings_file=$(find "${PREFIX}"/lib/ -name settings | head -n 1)
  if [[ -n "${settings_file}" ]]; then
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
  fi
}
