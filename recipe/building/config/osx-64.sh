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
  # Patch settings file for macOS before stage1 build
  local settings_file="${SRC_DIR}/_build/stage0/lib/settings"
  echo "  Patching stage0 settings..."
  patch_macos_settings "${settings_file}"
}

platform_post_stage1() {
  # Patch settings again after stage1 (may get overwritten)
  local settings_file="${SRC_DIR}/_build/stage0/lib/settings"
  echo "  Re-patching stage0 settings..."
  patch_macos_settings "${settings_file}"
}

platform_pre_stage2() {
  # Patch stage1 settings before stage2 build
  local settings_file="${SRC_DIR}/_build/stage1/lib/settings"
  echo "  Patching stage1 settings..."
  patch_macos_settings "${settings_file}"
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
