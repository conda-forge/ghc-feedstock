#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux Cross-Compilation (aarch64, ppc64le)
# ==============================================================================
# GHC cross-compilation for Linux targets (build on x86_64)
# Uses ghc-bootstrap 9.2.8 from BUILD_PREFIX
#
# Build Strategy:
# - Stage 1: Build cross-compiler using x86_64 bootstrap GHC
# - Stage 2: Use Stage 1 to build target-arch binaries
# - Binary Distribution: Create and install relocatable package
#
# Supported targets: linux-aarch64, linux-ppc64le
# ==============================================================================

set -eu

# Source common hook defaults (provides no-op implementations)
source "${RECIPE_DIR}/lib/common-hooks.sh"

# Platform metadata
PLATFORM_NAME="Linux cross-compilation"
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
  echo "  Setting up Linux ${target_arch} cross-compilation environment..."

  # GHC, PATH already set by common_setup_environment
  export CONDA_BUILD_SYSROOT="${BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot"

  # Disable statx (libc 2.20+) since we target libc 2.17
  export AR_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export CC_STAGE0="${CC_FOR_BUILD}"
  export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

  export ac_cv_func_statx=no
  export ac_cv_have_decl_statx=no
  export ac_cv_lib_ffi_ffi_call=yes

  # CRITICAL: Tell autoconf configure scripts we're cross-compiling
  # This prevents them from trying to run test programs (which would fail
  # because the target binaries can't execute on the build host)
  export cross_compiling=yes

  echo "  ✓ Linux ${target_arch} cross-compilation environment ready"
}

# ==============================================================================
# Phase 2: Bootstrap Setup
# ==============================================================================

platform_setup_bootstrap() {
  # Bootstrap GHC already configured in platform_setup_environment
  # Just verify it's available
  if [[ -z "${GHC:-}" ]]; then
    echo "ERROR: GHC not set by platform_setup_environment"
    exit 1
  fi
  echo "  Bootstrap GHC already configured: ${GHC}"
}

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

platform_setup_cabal() {
  echo "  Setting up Cabal for cross-compilation..."

  # CABAL and CABAL_DIR already set by common_setup_cabal
  echo "  CABAL: ${CABAL}"
  echo "  CABAL_DIR: ${CABAL_DIR}"

  # Initialize cabal directory
  mkdir -p "${CABAL_DIR}"
  "${CABAL}" user-config init

  # Ensure logs directory exists
  mkdir -p "${SRC_DIR}/_logs"

  # Run cabal update with detailed error logging
  "${CABAL}" v2-update 2>&1 | tee "${SRC_DIR}/_logs/01-cabal-update.log" || {
    echo "ERROR: Cabal update failed"
    tail -50 "${SRC_DIR}/_logs/01-cabal-update.log"
    exit 1
  }

  echo "  ✓ Cabal setup complete"
}

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

platform_configure_ghc() {
  echo "  Configuring GHC for ${target_arch} cross-compilation..."

  # Build system config using nameref helper
  local -a system_config
  build_system_config system_config "${ghc_host}" "${ghc_host}" "${ghc_target}"

  # Build standard configure args using nameref helper (--with-gmp, --with-ffi, etc.)
  local -a configure_args
  build_configure_args configure_args "-L${PREFIX}/lib ${LDFLAGS:-}"

  # Add cross-compilation specific toolchain paths
  configure_args+=(
    ac_cv_path_AR="${BUILD_PREFIX}/bin/${conda_target}-ar"
    ac_cv_path_AS="${BUILD_PREFIX}/bin/${conda_target}-as"
    ac_cv_path_CC="${BUILD_PREFIX}/bin/${conda_target}-clang"
    ac_cv_path_CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"
    ac_cv_path_LD="${BUILD_PREFIX}/bin/${conda_target}-ld"
    ac_cv_path_NM="${BUILD_PREFIX}/bin/${conda_target}-nm"
    ac_cv_path_OBJDUMP="${BUILD_PREFIX}/bin/${conda_target}-objdump"
    ac_cv_path_RANLIB="${BUILD_PREFIX}/bin/${conda_target}-ranlib"
    ac_cv_path_LLC="${BUILD_PREFIX}/bin/${conda_target}-llc"
    ac_cv_path_OPT="${BUILD_PREFIX}/bin/${conda_target}-opt"
  )

  run_and_log "configure" ./configure -v "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured"
}

# ==============================================================================
# Phase 5: Patch System Config
# ==============================================================================

platform_post_configure_ghc() {
  echo "  Patching hadrian system.config for cross-compilation..."

  # Use standardized helpers for cross-compilation
  strip_build_prefix_from_tools "python"  # Exclude python from stripping
  add_toolchain_prefix_to_tools "${conda_target}"
  fix_python_path_for_cross
  patch_system_config_linker_flags

  echo "  Patched system.config:"
  cat "${SRC_DIR}/hadrian/cfg/system.config"

  echo "  ✓ System config patched"
}

# ==============================================================================
# Phase 6: Build Hadrian
# ==============================================================================

platform_build_hadrian() {
  echo "  Building Hadrian for cross-compilation..."

  pushd "${SRC_DIR}/hadrian" >/dev/null

  # Set CFLAGS and LDFLAGS for hadrian build
  export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include -fdebug-prefix-map=${SRC_DIR}=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
  export LDFLAGS="-L${BUILD_PREFIX}/${conda_host}/lib -L${BUILD_PREFIX}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"

  # Build hadrian - let cabal resolve dependencies automatically
  # Hadrian is a temporary build tool, no special linking flags needed
  run_and_log "build-hadrian" "${CABAL}" v2-build \
    --with-ar="${AR_STAGE0}" \
    --with-gcc="${CC_STAGE0}" \
    --with-ghc="${GHC}" \
    --with-ld="${LD_STAGE0}" \
    -j${CPU_COUNT} \
    hadrian

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
  HADRIAN_FLAVOUR="release"

  echo "  Hadrian binary: ${hadrian_bin}"
  echo "  ✓ Hadrian built"
}

# ==============================================================================
# Phase 7: Build Stage 1
# ==============================================================================

platform_pre_build_stage1() {
  disable_copy_optimization
}

platform_post_build_stage1() {
  echo "  Updating Hadrian binary reference..."

  # Find executable hadrian (after Stage1 build may have created new one)
  local hadrian_bin=$(find "${SRC_DIR}/hadrian/dist-newstyle/build" -name hadrian -type f -executable | head -1)

  if [[ -f "${hadrian_bin}" ]]; then
    HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")
    echo "  Updated HADRIAN_CMD to: ${hadrian_bin}"
  fi

  # Update GHC to Stage1 for Stage2 build
  export GHC="${SRC_DIR}/_build/ghc-stage1"
  echo "  GHC for Stage2: ${GHC}"

  echo "  ✓ Stage1 post-build complete"
}

# ==============================================================================
# Phase 9: Install
# ==============================================================================

patch_final_settings() {
  echo "  Patching final settings file..."

  local settings_file=$(find "${PREFIX}/lib/" -name settings | head -1)

  if [[ ! -f "${settings_file}" ]]; then
    echo "ERROR: Could not find settings file in ${PREFIX}/lib/"
    return 1
  fi

  # Fix architecture references
  perl -pi -e "s#${host_arch}(-[^ \"]*)#${target_arch}\$1#g" "${settings_file}"

  # Add relocatable library paths
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"

  # Fix tool paths to use target prefix (strip absolute BUILD_PREFIX paths)
  # Pattern: Match full quoted path, capture the target prefix (e.g., aarch64-conda-linux-gnu-)
  # and tool name, then replace with just prefix+tool (no absolute path)
  perl -pi -e "s#\"[^\"]*/([^/]*-)(ar|as|clang|clang\+\+|ld|nm|objdump|ranlib|llc|opt)\"#\"\$1\$2\"#g" "${settings_file}"

  echo "  Final settings file:"
  cat "${settings_file}"

  echo "  ✓ Final settings patched"
}

fix_wrapper_scripts() {
  echo "  Fixing wrapper scripts..."

  # GHC bindist Makefile uses 'find . ! -type d' to list wrapper files,
  # which outputs './ghci' instead of 'ghci'. This "./" gets embedded in:
  #   exeprog="./ghci"
  #   executablename="/path/to/lib/bin/./ghci"
  # causing paths like: $libdir/bin/./target-ghci-9.6.7
  #
  # GHC installs TWO sets of wrapper scripts:
  # 1. Target-prefixed: $PREFIX/bin/${ghc_target}-ghci
  # 2. Short-name: $PREFIX/bin/ghci
  # Both may have the bug and both need fixing
  pushd "${PREFIX}/bin" >/dev/null

  for wrapper in ghc ghci ghc-pkg runghc runhaskell haddock hp2ps hsc2hs hpc; do
    # Fix target-prefixed wrapper
    local target_wrapper="${ghc_target}-${wrapper}"
    if [[ -f "${target_wrapper}" ]]; then
      # Fix both exeprog and executablename - both can have "./" prefix from find
      perl -pi -e 's#^(exeprog=")\./#$1#' "${target_wrapper}"
      perl -pi -e 's#(/bin/)\./#$1#' "${target_wrapper}"  # Fix executablename path
    fi
    # Fix short-name wrapper (may be script or symlink - only fix if script)
    if [[ -f "${wrapper}" ]] && [[ ! -L "${wrapper}" ]]; then
      perl -pi -e 's#^(exeprog=")\./#$1#' "${wrapper}"
      perl -pi -e 's#(/bin/)\./#$1#' "${wrapper}"  # Fix executablename path
    fi
  done

  popd >/dev/null
  echo "  ✓ Wrapper scripts fixed"
}

create_symlinks() {
  echo "  Creating symlinks for cross-compiled tools..."

  pushd "${PREFIX}/bin" >/dev/null

  # GHC bindist installs versioned wrappers like:
  #   powerpc64le-unknown-linux-gnu-ghci-9.6.7
  # But the ghci symlink points to:
  #   powerpc64le-unknown-linux-gnu-ghci (without version)
  # Create the missing intermediate symlinks:
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs haddock hpc runghc; do
    local versioned="${ghc_target}-${bin}-${PKG_VERSION}"
    local unversioned="${ghc_target}-${bin}"
    # Create unversioned -> versioned symlink if needed
    if [[ -f "${versioned}" ]] && [[ ! -e "${unversioned}" ]]; then
      ln -sf "${versioned}" "${unversioned}"
      echo "    ${versioned} -> ${unversioned}"
    fi
    # Create short name -> unversioned symlink if needed
    if [[ -e "${unversioned}" ]] && [[ ! -e "${bin}" ]]; then
      ln -sf "${unversioned}" "${bin}"
      echo "    ${unversioned} -> ${bin}"
    fi
  done

  popd >/dev/null

  # Create directory symlink for libraries
  if [[ -d "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}" ]]; then
    mv "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}" "${PREFIX}/lib/ghc-${PKG_VERSION}"
    ln -sf "${PREFIX}/lib/ghc-${PKG_VERSION}" "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}"
    echo "    ${ghc_target}-ghc-${PKG_VERSION} -> ghc-${PKG_VERSION}"
  fi

  # CRITICAL: Create symlinks inside lib/ghc-${version}/bin/ for wrapper scripts
  # The wrapper scripts in ${PREFIX}/bin/ reference binaries like "ghc-9.4.8"
  # but cross-compiled binaries are named "aarch64-unknown-linux-gnu-ghc-9.4.8"
  local lib_bin_dir="${PREFIX}/lib/ghc-${PKG_VERSION}/bin"
  if [[ -d "${lib_bin_dir}" ]]; then
    pushd "${lib_bin_dir}" >/dev/null
    for bin in ghc ghci ghc-pkg hp2ps hsc2hs haddock hpc runghc unlit; do
      local target_versioned="${ghc_target}-${bin}-${PKG_VERSION}"
      local short_versioned="${bin}-${PKG_VERSION}"
      # Create short-versioned -> target-versioned symlink if target exists
      if [[ -f "${target_versioned}" ]] && [[ ! -e "${short_versioned}" ]]; then
        ln -sf "${target_versioned}" "${short_versioned}"
        echo "    lib/bin: ${target_versioned} -> ${short_versioned}"
      fi
    done
    popd >/dev/null
  fi

  echo "  ✓ Symlinks created"
}

platform_install_ghc() {
  echo "  Creating binary distribution..."

  # Create binary distribution first
  run_and_log "bindist" "${HADRIAN_CMD[@]}" binary-dist \
    --prefix="${PREFIX}" \
    --flavour=release \
    --freeze1 \
    --freeze2 \
    --docs=none \
    --progress-info=none

  echo "  Installing from binary distribution..."

  local bindist_dir=$(find "${SRC_DIR}/_build/bindist" -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)

  if [[ -z "${bindist_dir}" ]]; then
    echo "ERROR: Could not find binary distribution directory"
    ls -la "${SRC_DIR}/_build/bindist/" || true
    return 1
  fi

  echo "  Binary distribution: ${bindist_dir}"

  pushd "${bindist_dir}" >/dev/null

  # Configure the binary distribution
  # Must use BUILD machine compiler (x86_64) with clean flags - not target compiler
  # Use ac_cv_path_* to properly cache paths for wrapper script generation
  ac_cv_path_CC="${BUILD_PREFIX}/bin/${conda_host}-clang" \
  ac_cv_path_CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++" \
  CFLAGS="" \
  CXXFLAGS="" \
  LDFLAGS="" \
  run_and_log "configure-install" ./configure --prefix="${PREFIX}" --target="${ghc_target}" || {
    cat config.log
    popd >/dev/null
    return 1
  }

  # Install (update_package_db fails due to cross ghc-pkg)
  run_and_log "make-install" make install_bin install_lib install_man

  popd >/dev/null

  echo "  ✓ Installation complete"
}

fix_ghci_wrapper() {
  echo "  Fixing ghci wrapper to call ghc --interactive..."

  # For cross-compiled GHC, ghci is NOT a separate binary - it's just ghc --interactive.
  # The bindist install creates a broken wrapper pointing to a non-existent ghci binary.
  # Replace it with a simple script that calls ghc --interactive.

  local ghci_wrapper="${PREFIX}/bin/${ghc_target}-ghci"
  if [[ -f "${ghci_wrapper}" ]]; then
    cat > "${ghci_wrapper}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
    chmod +x "${ghci_wrapper}"
    echo "    Fixed ${ghc_target}-ghci"
  fi

  # Also fix the short-name ghci if it's a script (not symlink)
  local short_ghci="${PREFIX}/bin/ghci"
  if [[ -f "${short_ghci}" ]] && [[ ! -L "${short_ghci}" ]]; then
    cat > "${short_ghci}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
    chmod +x "${short_ghci}"
    echo "    Fixed ghci"
  fi

  echo "  ✓ ghci wrapper fixed"
}

platform_post_install() {
  patch_final_settings
  fix_wrapper_scripts
  fix_ghci_wrapper
  create_symlinks
  install_bash_completion
}
