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

# Source common hook defaults (provides no-op implementations)
source "${RECIPE_DIR}/lib/common-hooks.sh"

# Platform metadata
PLATFORM_NAME="macOS x86_64 (native)"
PLATFORM_TYPE="native"
INSTALL_METHOD="bindist"

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

platform_setup_environment() {
  echo "  Configuring macOS native environment..."

  # This is needed as it seems to interfere with configure scripts
  unset build_alias
  unset host_alias

  # Build iconv compatibility library for conda-forge libiconv
  # This resolves issues with missing _iconv_open when linking
  echo "  Building libiconv_compat.dylib..."
  mkdir -p "${PREFIX}/lib/ghc-${PKG_VERSION}/lib"
  ${CC} -dynamiclib -o "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib" \
    "${RECIPE_DIR}/support/osx_iconv_compat.c" \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -mmacosx-version-min=10.13 \
    -install_name "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"
  echo "  Created: ${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"

  # Preload CONDA libraries to override system libraries
  export DYLD_INSERT_LIBRARIES="${PREFIX}/lib/libiconv.dylib:${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"
  export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"

  # Use LLVM ar - only archiver that resolves odd mismatched arch when linking
  export AR=llvm-ar

  # Add BUILD_PREFIX/bin to PATH (ghc-bootstrap/bin already added by common_setup_environment)
  export PATH="${BUILD_PREFIX}/bin:${PATH}"

  echo "  Environment variables:"
  echo "    AR=${AR}"
  echo "    DYLD_INSERT_LIBRARIES=${DYLD_INSERT_LIBRARIES}"

  echo "  Patching bootstrap settings..."
  local settings_file=$(find "${BUILD_PREFIX}/ghc-bootstrap" -name settings | head -n 1)
  if [[ -n "${settings_file}" ]]; then
    update_settings_link_flags "${settings_file}"
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
    echo "  Patched: ${settings_file}"
  fi

  echo "  ✓ macOS environment configured"
}

# ==============================================================================
# Phase 2: Bootstrap Setup
# ==============================================================================

# Uses default_setup_bootstrap from common-functions.sh

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

# Uses default - common_setup_cabal + default_setup_cabal provide identical behavior

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

platform_configure_ghc() {
  echo "  Configuring GHC for macOS x86_64..."

  local osx_triple="x86_64-apple-darwin13.4.0"

  # Build system config using nameref helper (native build: same triple for build/host)
  local -a system_config
  build_system_config system_config "${osx_triple}" "${osx_triple}" ""

  # Build standard configure args using nameref helper (--with-gmp, --with-ffi, etc.)
  local -a configure_args
  build_configure_args configure_args

  # Override ac_cv variables for toolchain (environment variables)
  export ac_cv_path_ac_pt_CC=""
  export ac_cv_path_ac_pt_CXX=""
  export ac_cv_prog_AR="${AR}"
  export ac_cv_prog_CC="${CC}"
  export ac_cv_prog_CXX="${CXX}"
  export ac_cv_prog_LD="${LD}"
  export ac_cv_prog_RANLIB="${RANLIB}"
  export ac_cv_path_AR="${AR}"
  export ac_cv_path_CC="${CC}"
  export ac_cv_path_CXX="${CXX}"
  export ac_cv_path_LD="${LD}"
  export ac_cv_path_RANLIB="${RANLIB}"
  export DEVELOPER_DIR=""

  run_and_log "configure" ./configure "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured"
}

platform_post_configure_ghc() {
  echo "  Patching system.config for macOS..."

  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  # Use standardized helpers
  strip_build_prefix_from_tools

  # Use llvm-ar (Apple ld64 compatible) - macOS-specific
  perl -pi -e 's#(=\s+)(ar)$#$1llvm-$2#' "${settings_file}"

  # Add toolchain prefix to tools
  add_toolchain_prefix_to_tools "x86_64-apple-darwin13.4.0"

  # Add library paths and rpath
  patch_system_config_linker_flags

  echo "  ✓ system.config patched"
}

# ==============================================================================
# Phase 5: Build Hadrian
# ==============================================================================

platform_build_hadrian() {
  echo "  Building Hadrian for macOS (cabal-built)..."

  pushd "${SRC_DIR}/hadrian" >/dev/null

  # Build Hadrian with cabal (consistent with other platforms)
  # Hadrian is a temporary build tool, no special linking flags needed
  run_and_log "build-hadrian" "${CABAL}" v2-build -j${CPU_COUNT} hadrian

  popd >/dev/null

  # Find Hadrian binary
  local hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle -name hadrian -type f | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  # Set up Hadrian command array
  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")
  HADRIAN_FLAVOUR="release"

  echo "  Hadrian binary: ${hadrian_bin}"
  echo "  ✓ Hadrian built (cabal-built)"
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

platform_build_stage1() {
  echo "  Building Stage 1 GHC for macOS..."

  run_and_log "stage1-exe" "${HADRIAN_CMD[@]}" stage1:exe:ghc-bin \
    --flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=none

  # Update stage0 settings with link flags
  local settings_file="${SRC_DIR}/_build/stage0/lib/settings"
  if [[ -f "${settings_file}" ]]; then
    update_settings_link_flags "${settings_file}"
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
    echo "  Updated stage0 settings"
  fi

  # Build Stage 1 libraries
  run_and_log "stage1-lib" "${HADRIAN_CMD[@]}" stage1:lib:ghc \
    --flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=none

  # Update settings again after lib build
  if [[ -f "${settings_file}" ]]; then
    update_settings_link_flags "${settings_file}"
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
  fi

  echo "  ✓ Stage 1 GHC built"
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

platform_build_stage2() {
  echo "  Building Stage 2 GHC for macOS..."

  run_and_log "stage2-exe" "${HADRIAN_CMD[@]}" stage2:exe:ghc-bin \
    --flavour="${HADRIAN_FLAVOUR}" --freeze1 --docs=none --progress-info=none

  # Update stage1 settings
  local settings_file="${SRC_DIR}/_build/stage1/lib/settings"
  if [[ -f "${settings_file}" ]]; then
    update_settings_link_flags "${settings_file}"
  fi

  run_and_log "stage2-lib" "${HADRIAN_CMD[@]}" stage2:lib:ghc \
    --flavour="${HADRIAN_FLAVOUR}" --freeze1 --docs=none --progress-info=none

  echo "  ✓ Stage 2 GHC built"
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

platform_install_ghc() {
  echo "  Installing GHC for macOS..."

  run_and_log "install" "${HADRIAN_CMD[@]}" install \
    --prefix="${PREFIX}" \
    --flavour="${HADRIAN_FLAVOUR}" \
    --freeze1 --freeze2 \
    --docs=none --progress-info=none

  echo "  ✓ GHC installed"
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

platform_post_install() {
  echo "  Running macOS post-install..."

  # Update installed settings with relocatable paths
  update_installed_settings "${CONDA_TOOLCHAIN_HOST:-x86_64-apple-darwin13.4.0}"

  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  if [[ -f "${settings_file}" ]]; then
    set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
    echo "  Final settings:"
    cat "${settings_file}"
  fi

  # Verify installation
  echo "  Verifying GHC installation..."
  "${PREFIX}/bin/ghc" --version || {
    echo "ERROR: Installed GHC failed to run"
    exit 1
  }

  echo "  ✓ macOS post-install complete"
}
