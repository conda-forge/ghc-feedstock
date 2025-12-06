#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: macOS arm64 (Cross-compiled from x86_64)
# ==============================================================================
# macOS cross-compilation from x86_64 to arm64.
#
# Build Strategy:
# - Stage 1: Build cross-compiler using x86_64 bootstrap GHC
# - Stage 2: Use Stage 1 to build arm64-targeted binaries
#
# Key implementation details:
# - Uses bootstrap GHC from BUILD_PREFIX (no separate env needed)
# - Disables copy optimization to force cross binary compilation
# - Uses llvm-ar for Apple ld64 compatibility
# - Applies -fno-lto to prevent ABI mismatches
# ==============================================================================

set -eu

# Source common hook defaults (provides no-op implementations)
source "${RECIPE_DIR}/lib/common-hooks.sh"

# Platform metadata
PLATFORM_NAME="macOS arm64 (cross-compiled from x86_64)"
PLATFORM_TYPE="cross"
INSTALL_METHOD="bindist"

# ==============================================================================
# Architecture Configuration
# ==============================================================================

# Use standardized cross-compilation triple configuration
# Sets: conda_host, conda_target, host_arch, target_arch, ghc_host, ghc_target
# Exports: build_alias, host_alias, target_alias, host_platform
configure_cross_triples

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

platform_setup_environment() {
  echo "  Setting up macOS cross-compilation environment..."

  # GHC, PATH already set by common_setup_environment

  # Find llvm-ar (required for Apple ld64 compatibility)
  export AR_STAGE0=$(find "${BUILD_PREFIX}" -name llvm-ar | head -1)
  echo "  AR_STAGE0: ${AR_STAGE0}"

  echo "  ✓ macOS cross-compilation environment ready"
}

# ==============================================================================
# Phase 2: Bootstrap Setup
# ==============================================================================

platform_setup_bootstrap() {
  # Bootstrap GHC already configured in platform_setup_environment
  if [[ -z "${GHC:-}" ]]; then
    echo "ERROR: GHC not set by platform_setup_environment"
    exit 1
  fi
  echo "  Bootstrap GHC already configured: ${GHC}"
}

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

# Uses default - common_setup_cabal + default_setup_cabal provide standard behavior

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

platform_configure_ghc() {
  echo "  Configuring GHC for cross-compilation..."

  # Build system config using nameref helper (cross-compile: only target, no build/host)
  local -a system_config
  build_system_config system_config "" "" "${target_alias}"

  # For cross-compilation, we manually build configure args instead of using
  # build_configure_args. This is because:
  # - Stage0 runs on build machine (x86_64) and needs libs from BUILD_PREFIX
  # - Stage1/2 target arm64 and need libs from PREFIX
  # - But system.config lib-dirs are shared across all stages
  #
  # Solution: Don't pass --with-ffi-libraries or --with-iconv-libraries to configure.
  # This prevents them from being set in system.config's ffi-lib-dir/iconv-lib-dir.
  # Instead, we'll add -L flags to stage-specific linker args later.
  local -a configure_args
  configure_args+=(--with-system-libffi=yes)
  configure_args+=("--with-curses-includes=${PREFIX}/include")
  # NOTE: Skip --with-curses-libraries, --with-ffi-libraries, --with-iconv-libraries
  # These would set lib-dirs in system.config used by ALL stages, causing
  # stage0 (x86_64) to try linking arm64 libs from PREFIX.
  configure_args+=("--with-ffi-includes=${PREFIX}/include")
  configure_args+=("--with-gmp-includes=${PREFIX}/include")
  configure_args+=("--with-gmp-libraries=${PREFIX}/lib")
  configure_args+=("--with-iconv-includes=${PREFIX}/include")
  # GMP is statically linked, so it's OK to point to PREFIX

  # Add cross-compilation specific toolchain overrides
  configure_args+=(
    ac_cv_lib_ffi_ffi_call=yes

    ac_cv_prog_AR="${AR}"
    ac_cv_prog_AS="${AS}"
    ac_cv_prog_CC="${CC}"
    ac_cv_prog_CXX="${CXX}"
    ac_cv_prog_LD="${LD}"
    ac_cv_prog_NM="${NM}"
    ac_cv_prog_RANLIB="${RANLIB}"

    ac_cv_path_ac_pt_AR="${AR}"
    ac_cv_path_ac_pt_NM="${NM}"
    ac_cv_path_ac_pt_RANLIB="${RANLIB}"

    ac_cv_prog_ac_ct_LLC="${conda_target}-llc"
    ac_cv_prog_ac_ct_OPT="${conda_target}-opt"

    CC_STAGE0="${CC_FOR_BUILD}"
    LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

    AR="${BUILD_PREFIX}/bin/${conda_target}-ar"
    AS="${BUILD_PREFIX}/bin/${conda_target}-as"
    CC="${BUILD_PREFIX}/bin/${conda_target}-clang"
    CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"
    LD="${BUILD_PREFIX}/bin/${conda_target}-ld"
    NM="${BUILD_PREFIX}/bin/${conda_target}-nm"
    OBJDUMP="${BUILD_PREFIX}/bin/${conda_target}-objdump"
    RANLIB="${BUILD_PREFIX}/bin/${conda_target}-ranlib"

    CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CFLAGS:-}"
    CPPFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CPPFLAGS:-}"
    CXXFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CXXFLAGS:-}"
  )

  run_and_log "configure" ./configure -v "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured"
}

platform_post_configure_ghc() {
  echo "  Patching system.config for cross-compilation..."

  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  # Use standardized helpers for cross-compilation
  strip_build_prefix_from_tools "python"  # Exclude python from stripping
  fix_python_path_for_cross
  add_toolchain_prefix_to_tools "${conda_target}" "ar clang clang++ llc nm objdump opt ranlib"
  patch_system_config_linker_flags

  # Force system GMP (in case configure still defaults to intree)
  if [[ -f "${settings_file}" ]]; then
    echo "  Ensuring system GMP is used (not intree)..."
    perl -pi -e "s#^intree-gmp\s*=\s*.*#intree-gmp = NO#" "${settings_file}"
    echo "  ✓ intree-gmp = NO set in system.config"

    # Fix touch command (GHC 9.2.8 bug: --enable-distro-toolchain sets touchy.exe even on macOS)
    echo "  Fixing touch command (touchy.exe -> touch)..."
    perl -pi -e 's#\$\$topdir/bin/touchy\.exe#touch#' "${settings_file}"
    echo "  ✓ settings-touch-command = touch"

    # CROSS-COMPILATION LIB-DIRS STRATEGY:
    # We did NOT pass --with-ffi-libraries or --with-iconv-libraries to configure.
    # This means ffi-lib-dir and iconv-lib-dir are NOT set in system.config.
    # This is intentional because:
    # - Stage0 runs on build machine (x86_64), needs libs from BUILD_PREFIX
    # - Stage1/2 target arm64, need libs from PREFIX
    # - But system.config lib-dirs are shared across ALL stages
    #
    # Solution: Keep ffi-lib-dir/iconv-lib-dir empty (not set by configure).
    # Stage0 gets -L flags via conf-gcc-linker-args-stage0 (set below).
    # Stage1/2 get -L flags via conf-gcc-linker-args-stage1/2 (from patch_system_config_linker_flags).
    #
    # We also need to set curses-lib-dir for stage1/2 packages that need ncurses.
    echo "  Setting curses-lib-dir for stage1/2 (haskeline)..."
    echo "curses-lib-dir = ${PREFIX}/lib" >> "${settings_file}"
    echo "  ✓ lib-dirs strategy applied (ffi/iconv via linker args, curses via lib-dir)"
  fi

  # macOS-specific: Set system-ar to llvm-ar for stage0
  # Use [ \t]* instead of \s* to avoid matching newlines
  perl -pi -e 's#^(system-ar[ \t]*=[ \t]*).*$#$1'"${AR_STAGE0}"'#' "${settings_file}"

  # macOS-specific: Set stage0 compiler flags for host targeting
  # CRITICAL: Stage0 runs on build machine (x86_64), so it needs BUILD_PREFIX libraries, NOT PREFIX (arm64)
  # Use [ \t]* instead of \s* to avoid matching newlines, and anchor with $ for end of line
  perl -pi -e 's#^(conf-cc-args-stage0[ \t]*=[ \t]*).*$#$1--target='"${conda_host}"'#' "${settings_file}"
  perl -pi -e 's#^(conf-gcc-linker-args-stage0[ \t]*=[ \t]*).*$#$1--target='"${conda_host}"' -Wl,-L'"${BUILD_PREFIX}"'/lib -Wl,-rpath,'"${BUILD_PREFIX}"'/lib#' "${settings_file}"
  perl -pi -e 's#^(conf-ld-linker-args-stage0[ \t]*=[ \t]*).*$#$1-L'"${BUILD_PREFIX}"'/lib -rpath '"${BUILD_PREFIX}"'/lib#' "${settings_file}"

  # macOS-specific: Override ar command in settings
  perl -pi -e 's#^(settings-ar-command[ \t]*=[ \t]*).*$#$1'"${conda_target}"'-ar#' "${settings_file}"

  # macOS-specific: objdump doesn't need prefix (undo the prefix we just added)
  perl -pi -e "s#${conda_target}-(objdump)#\$1#" "${settings_file}"

  echo "  Patched system.config:"
  cat "${settings_file}"

  # macOS-specific: Patch bootstrap settings
  echo "  Patching bootstrap settings..."
  local bootstrap_settings="${BUILD_PREFIX}/ghc-bootstrap/lib/ghc-${PKG_VERSION}/lib/settings"
  if [[ -f "${bootstrap_settings}" ]]; then
    # Remove problematic libiconv2 reference
    perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${bootstrap_settings}"
    # Add -fno-lto to compiler flags
    perl -pi -e "s#(C compiler flags\", \")#\$1-v -fno-lto #" "${bootstrap_settings}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${bootstrap_settings}"
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto#" "${bootstrap_settings}"
    # Fix ar and ranlib commands
    perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR_STAGE0}#" "${bootstrap_settings}"
    perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1llvm-ranlib#" "${bootstrap_settings}"
    # Fix tool commands with host prefix
    perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${conda_host}-\$2#" "${bootstrap_settings}"

    # CRITICAL: Replace any $PREFIX paths with $BUILD_PREFIX in linker flags
    # Stage0 (bootstrap) runs on build machine (x86_64), needs x86_64 libs from BUILD_PREFIX
    # NOT arm64 libs from PREFIX
    echo "  Fixing library paths in bootstrap settings (PREFIX -> BUILD_PREFIX)..."
    perl -pi -e "s#-L${PREFIX}/lib#-L${BUILD_PREFIX}/lib#g" "${bootstrap_settings}"
    perl -pi -e "s#-rpath,${PREFIX}/lib#-rpath,${BUILD_PREFIX}/lib#g" "${bootstrap_settings}"
    perl -pi -e "s#-rpath ${PREFIX}/lib#-rpath ${BUILD_PREFIX}/lib#g" "${bootstrap_settings}"

    echo "  Patched bootstrap settings"
    cat "${bootstrap_settings}"
  fi

  echo "  ✓ System config patched"
}

# ==============================================================================
# Phase 5: Build Hadrian
# ==============================================================================

platform_build_hadrian() {
  echo "  Building Hadrian for cross-compilation..."

  pushd "${SRC_DIR}/hadrian" >/dev/null

  # Build hadrian - let cabal resolve dependencies automatically
  # Hadrian is a temporary build tool, no special linking flags needed
  "${CABAL}" v2-build \
    --with-ghc="${GHC}" \
    --with-gcc="${CC_FOR_BUILD}" \
    --with-ar="${AR_STAGE0}" \
    -j${CPU_COUNT} \
    hadrian \
    2>&1 | tee "${SRC_DIR}/cabal-verbose.log"

  local cabal_exit_code=${PIPESTATUS[0]}

  if [[ ${cabal_exit_code} -ne 0 ]]; then
    echo "ERROR: Cabal build FAILED with exit code ${cabal_exit_code}"
    popd >/dev/null
    return 1
  fi

  popd >/dev/null

  # Find hadrian binary
  local hadrian_bin=$(find "${SRC_DIR}/hadrian/dist-newstyle/build" -name hadrian -type f | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found"
    return 1
  fi

  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")
  HADRIAN_FLAVOUR="quick"

  echo "  Hadrian binary: ${hadrian_bin}"
  echo "  ✓ Hadrian built"
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

platform_pre_build_stage1() {
  disable_copy_optimization

  # Set up build environment for stage1
  export AR="${AR_STAGE0}"
  export AS="${BUILD_PREFIX}/bin/${conda_host}-as"
  export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"

  # Create symlinks for host tools
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ar" "${BUILD_PREFIX}/bin/ar" 2>/dev/null || true
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-as" "${BUILD_PREFIX}/bin/as" 2>/dev/null || true
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ld" "${BUILD_PREFIX}/bin/ld" 2>/dev/null || true
}

platform_build_stage1() {
  echo "  Building Stage 1 cross-compiler..."

  # Build Stage 1 GHC compiler
  run_and_log "stage1-ghc" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" \
    stage1:exe:ghc-bin --docs=none --progress-info=none

  # Build Stage 1 supporting tools
  run_and_log "stage1-pkg" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" \
    stage1:exe:ghc-pkg --docs=none --progress-info=none
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" \
    stage1:exe:hsc2hs --docs=none --progress-info=none

  # Verify Stage0 GHC works
  "${SRC_DIR}/_build/stage0/bin/${ghc_target}-ghc" --version || {
    echo "WARNING: Stage0 GHC failed to report version"
  }

  echo "  ✓ Stage 1 cross-compiler built"
}

platform_post_build_stage1() {
  echo "  Building Stage 1 libraries..."

  # Build libraries with quick flavour (for full ways: vanilla, profiling, dynamic)
  run_and_log "stage1-lib" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" \
    stage1:lib:ghc --docs=none --progress-info=none

  echo "  ✓ Stage 1 libraries built"
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

platform_build_stage2() {
  echo "  Building Stage 2 cross-compiled binaries..."

  run_and_log "stage2-exe" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" \
    stage2:exe:ghc-bin --freeze1 --docs=none --progress-info=none

  run_and_log "build-all" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" \
    --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none

  echo "  ✓ Stage 2 cross-compiled binaries built"
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

platform_install_ghc() {
  echo "  Installing from binary distribution..."

  run_and_log "install" "${HADRIAN_CMD[@]}" install \
    --prefix="${PREFIX}" \
    --flavour="${HADRIAN_FLAVOUR}" \
    --freeze1 --freeze2 \
    --docs=none --progress-info=none || true

  echo "  Contents of ${PREFIX}/bin and ${PREFIX}/lib:"
  ls -l1 "${PREFIX}"/{bin,lib}/* || true

  echo "  ✓ Installation complete"
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

create_symlinks() {
  echo "  Creating symlinks for cross-compiled tools..."

  # Create links: triplet-bin -> bin
  pushd "${PREFIX}/bin" >/dev/null
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${conda_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${conda_target}-${bin}" "${bin}"
      echo "    ${conda_target}-${bin} -> ${bin}"
    fi
  done
  popd >/dev/null

  # Create directory symlink for libraries
  if [[ -d "${PREFIX}/lib/${conda_target}-ghc-${PKG_VERSION}" ]]; then
    mv "${PREFIX}/lib/${conda_target}-ghc-${PKG_VERSION}" "${PREFIX}/lib/ghc-${PKG_VERSION}"
    ln -sf "${PREFIX}/lib/ghc-${PKG_VERSION}" "${PREFIX}/lib/${conda_target}-ghc-${PKG_VERSION}"
    echo "    ${conda_target}-ghc-${PKG_VERSION} -> ghc-${PKG_VERSION}"
  fi

  echo "  ✓ Symlinks created"
}

platform_post_install() {
  create_symlinks

  # Verify installation
  echo "  Verifying GHC installation..."
  "${PREFIX}/bin/ghc" --version || {
    echo "WARNING: Installed GHC failed to run (expected for cross-compiled binary)"
  }

  echo "  ✓ macOS arm64 post-install complete"
}
