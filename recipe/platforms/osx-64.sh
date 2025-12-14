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
# Phase 1: Environment Setup
# ==============================================================================

platform_setup_environment() {
  echo "  Configuring macOS native environment..."

  # This is needed as it seems to interfere with configure scripts
  unset build_alias
  unset host_alias

  # Use shared macOS setup (creates iconv compat, sets AR, DYLD env, patches bootstrap)
  macos_complete_setup

  # Add BUILD_PREFIX/bin to PATH (ghc-bootstrap/bin already added by common_setup_environment)
  export PATH="${BUILD_PREFIX}/bin:${PATH}"

  echo "  ✓ macOS environment configured"
}

# ==============================================================================
# Phase 2: Bootstrap Setup
# ==============================================================================

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

platform_configure_ghc() {
  echo "  Configuring GHC for macOS x86_64..."

  # Build system config using nameref helper (native build: same triple for build/host)
  # Uses ${ghc_triple} from configure_native_triple() called at top level
  local -a system_config
  build_system_config system_config "${ghc_triple}" "${ghc_triple}" ""

  # Build standard configure args using nameref helper (--with-gmp, --with-ffi, etc.)
  local -a configure_args
  build_configure_args configure_args

  # Use unified helper for ac_cv_* variables
  set_autoconf_toolchain_vars --macos

  run_and_log "configure" ./configure "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured"
}

platform_post_configure_ghc() {
  # Use unified macOS system.config patching helper
  # Uses ${ghc_triple} from configure_native_triple() called at top level
  macos_patch_system_config "${ghc_triple}"
}

# ==============================================================================
# Phase 5: Build Hadrian - uses default (cabal v2-build)
# ==============================================================================

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

platform_build_stage1() {
  echo "  Building Stage 1 GHC for macOS..."

  run_and_log "stage1-exe" "${HADRIAN_CMD[@]}" stage1:exe:ghc-bin \
    --flavour="${FLAVOUR}" --docs=none --progress-info=none

  # Update stage0 settings with link flags (once after exe build)
  local settings_file="${SRC_DIR}/_build/stage0/lib/settings"
  if [[ -f "${settings_file}" ]]; then
    update_settings_link_flags "${settings_file}"
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
    echo "  Updated stage0 settings"
  fi

  # Build Stage 1 libraries
  run_and_log "stage1-lib" "${HADRIAN_CMD[@]}" stage1:lib:ghc \
    --flavour="${FLAVOUR}" --docs=none --progress-info=none

  echo "  ✓ Stage 1 GHC built"
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

platform_build_stage2() {
  echo "  Building Stage 2 GHC for macOS..."

  run_and_log "stage2-exe" "${HADRIAN_CMD[@]}" stage2:exe:ghc-bin \
    --flavour="${FLAVOUR}" --freeze1 --docs=none --progress-info=none

  # Update stage1 settings
  local settings_file="${SRC_DIR}/_build/stage1/lib/settings"
  if [[ -f "${settings_file}" ]]; then
    update_settings_link_flags "${settings_file}"
  fi

  run_and_log "stage2-lib" "${HADRIAN_CMD[@]}" stage2:lib:ghc \
    --flavour="${FLAVOUR}" --freeze1 --docs=none --progress-info=none

  echo "  ✓ Stage 2 GHC built"
}

# ==============================================================================
# Phase 8: Install GHC - uses default (bindist_install)
# ==============================================================================

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

platform_post_install() {
  echo "  Running macOS post-install..."

  # Update installed settings with relocatable paths
  # Uses ${ghc_triple} from configure_native_triple() called at top level
  update_installed_settings "${ghc_triple}"

  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  if [[ -f "${settings_file}" ]]; then
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
  fi

  install_bash_completion

  # Verify installation
  echo "  Verifying GHC installation..."
  "${PREFIX}/bin/ghc" --version || {
    echo "ERROR: Installed GHC failed to run"
    exit 1
  }

  echo "  ✓ macOS post-install complete"
}
