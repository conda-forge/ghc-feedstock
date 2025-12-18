#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: macOS x86_64 (Native)
# ==============================================================================
# macOS-specific native build behavior.
#
# Key implementation details:
# - Creates libiconv_compat.dylib for conda libiconv compatibility
# - Uses DYLD_INSERT_LIBRARIES for library preloading
# - Uses llvm-ar for Apple ld64 compatibility
# - Applies -fno-lto to prevent ABI mismatches
# ==============================================================================

set -eu

source "${RECIPE_DIR}/lib/common-hooks.sh"
source "${RECIPE_DIR}/lib/macos-common.sh"

# Platform metadata
PLATFORM_NAME="macOS x86_64 (native)"
PLATFORM_TYPE="native"
INSTALL_METHOD="bindist"
FLAVOUR="release+omit_pragmas"

# ==============================================================================
# Platform Triple Configuration
# ==============================================================================

# Use standardized native triple configuration (sets ghc_triple)
# This enables consistent usage of ${ghc_triple} in configure phases
configure_native_triple

# ==============================================================================
# Platform Hooks
# ==============================================================================

platform_setup_environment() {
  unset build_alias host_alias  # Interferes with configure scripts
  macos_complete_setup          # Creates iconv compat, sets AR, DYLD env, patches bootstrap
  export PATH="${BUILD_PREFIX}/bin:${PATH}"
}

platform_configure_ghc() {
  local -a system_config configure_args
  build_system_config system_config "${ghc_triple}" "${ghc_triple}" ""
  build_configure_args configure_args
  set_autoconf_toolchain_vars --macos
  run_and_log "configure" ./configure "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log; return 1
  }
}

platform_post_configure_ghc() {
  macos_patch_system_config "${ghc_triple}"
}

# Stage build hooks - update settings after executables are built
platform_post_stage1_executables() {
  local settings_file="${SRC_DIR}/_build/stage0/lib/settings"
  [[ -f "${settings_file}" ]] && {
    update_settings_link_flags "${settings_file}"
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
  }
}

platform_post_stage2_executables() {
  local settings_file="${SRC_DIR}/_build/stage1/lib/settings"
  [[ -f "${settings_file}" ]] && {
    update_settings_link_flags "${settings_file}"
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
  }
}

platform_post_install() {
  update_installed_settings "${ghc_triple}"
  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  [[ -f "${settings_file}" ]] && set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
  install_bash_completion
  "${PREFIX}/bin/ghc" --version || { echo "ERROR: Installed GHC failed"; exit 1; }
}
