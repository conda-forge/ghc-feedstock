#!/usr/bin/env bash
# ==============================================================================
# Linux Cross-Compilation Platform Configuration
# ==============================================================================
# GHC cross-compilation for Linux (build on x86_64, target aarch64/ppc64le/etc)
# Uses libc 2.17 sysroot for maximum compatibility
#
# Build Strategy:
# - Stage 1: Build cross-compiler using bootstrap GHC
# - Stage 2: Use Stage 1 to build cross-compiled binaries
# - Binary Distribution: Create and install relocatable package
# ==============================================================================

set -eu

# Platform metadata
PLATFORM_NAME="Linux aarch64 (native)"

# ==============================================================================
# Architecture Configuration
# ==============================================================================

# Map conda arch names to GHC arch names
conda_host="${build_alias}"
conda_target="${host_alias}"
host_arch="${build_alias%%-*}"
target_arch="${host_alias%%-*}"

ghc_host="${host_arch}-unknown-linux-gnu"
ghc_target="${target_arch}-unknown-linux-gnu"

# Override build/host aliases for GHC configure
_build_alias=${build_alias}
_host_alias=${host_alias}
export build_alias="${ghc_host}"
export host_alias="${ghc_host}"

echo "Cross-compilation configuration:"
echo "  Build arch: ${host_arch} (${conda_host})"
echo "  Target arch: ${target_arch} (${conda_target})"
echo "  GHC host: ${ghc_host}"
echo "  GHC target: ${ghc_target}"

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

platform_setup_environment() {
  echo "  Setting up Linux cross-compilation environment..."

  # Create libc2.17 environment for cross-compilation
  echo "  Creating libc2.17 environment for cross-compilation libraries..."
  conda create -y \
    -n libc2.17_env \
    --platform linux-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap=="${PKG_VERSION}" \
    sysroot_linux-64==2.17

  # Get environment path and export for later phases
  export libc2_17_env=$(conda info --envs | grep libc2.17_env | awk '{print $2}')
  ghc_path="${libc2_17_env}/ghc-bootstrap/bin"

  if [[ -z "${libc2_17_env}" ]]; then
    echo "ERROR: Failed to find libc2.17_env"
    conda info --envs
    exit 1
  fi
  echo "  libc2.17 environment: ${libc2_17_env}"

  export CABAL="${libc2_17_env}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}/.cabal"
  export GHC="${ghc_path}/ghc"
  export PATH="${ghc_path}:${PATH:-}"

  echo "  Bootstrap GHC: ${GHC}"
  "${GHC}" --version
  "${ghc_path}/ghc-pkg" recache

  echo "  CABAL: ${CABAL}"

  # Create cabal directory
  mkdir -p "${CABAL_DIR}"
  "${CABAL}" user-config init

  # Disable statx (libc 2.20+) since we target libc 2.17
  export AR_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export CC_STAGE0="${CC_FOR_BUILD}"
  export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

  export ac_cv_func_statx=no
  export ac_cv_have_decl_statx=no
  export ac_cv_lib_ffi_ffi_call=yes

  echo "  ✓ Linux cross-compilation environment ready"
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

  # Debug: verify CABAL is set
  if [[ -z "${CABAL:-}" ]]; then
    echo "ERROR: CABAL not set"
    echo "  libc2_17_env=${libc2_17_env:-NOT SET}"
    exit 1
  fi
  echo "  CABAL: ${CABAL}"

  # Ensure logs directory exists
  mkdir -p "${SRC_DIR}/_logs"

  # Run cabal update with error details
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

platform_configure() {
  echo "  Configuring GHC for cross-compilation..."

  SYSTEM_CONFIG=(
    --target="${ghc_target}"
    --prefix="${PREFIX}"
  )

  CONFIGURE_ARGS=(
    --disable-numa
    --with-system-libffi=yes
    --with-curses-includes="${PREFIX}/include"
    --with-curses-libraries="${PREFIX}/lib"
    --with-ffi-includes="${PREFIX}/include"
    --with-ffi-libraries="${PREFIX}/lib"
    --with-gmp-includes="${PREFIX}/include"
    --with-gmp-libraries="${PREFIX}/lib"
    --with-iconv-includes="${PREFIX}/include"
    --with-iconv-libraries="${PREFIX}/lib"

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

    LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
  )

  run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured"
}

# ==============================================================================
# Phase 5: Patch System Config
# ==============================================================================

patch_system_config() {
  echo "  Patching hadrian system.config for cross-compilation..."

  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  # Remove BUILD_PREFIX from tool paths
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"

  # Add target prefix to tools (ar, clang, etc.)
  perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"

  # Add library paths and rpath to linker flags
  perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"

  echo "  Patched system.config:"
  cat "${settings_file}"

  echo "  ✓ System config patched"
}

platform_post_configure() {
  patch_system_config
}

# ==============================================================================
# Phase 6: Build Hadrian
# ==============================================================================

platform_build_hadrian() {
  echo "  Building Hadrian for cross-compilation..."

  pushd "${SRC_DIR}/hadrian" >/dev/null

  # Set CFLAGS and LDFLAGS for hadrian build
  export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include -fdebug-prefix-map=${SRC_DIR}=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
  export LDFLAGS="-L${libc2_17_env}/${conda_host}/lib -L${libc2_17_env}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"

  # Build hadrian and its dependencies with explicit package list
  "${CABAL}" v2-build \
    --with-ar="${AR_STAGE0}" \
    --with-gcc="${CC_STAGE0}" \
    --with-ghc="${GHC}" \
    --with-ld="${LD_STAGE0}" \
    --enable-shared \
    --enable-executable-dynamic \
    -j${CPU_COUNT} \
    clock \
    file-io \
    heaps \
    js-dgtable \
    js-flot \
    js-jquery \
    directory \
    os-string \
    splitmix \
    utf8-string \
    hashable \
    process \
    primitive \
    random \
    QuickCheck \
    unordered-containers \
    extra \
    Cabal-syntax \
    filepattern \
    Cabal \
    shake \
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
  HADRIAN_FLAVOUR="quickest"

  echo "  Hadrian binary: ${hadrian_bin}"
  echo "  ✓ Hadrian built"
}

# ==============================================================================
# Phase 7: Build Stage 1
# ==============================================================================

disable_copy_optimization() {
  echo "  Disabling copy optimization for cross-compilation..."

  # Force building the cross binary instead of copying
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}/hadrian/src/Rules/Program.hs"

  echo "  ✓ Copy optimization disabled"
}

update_stage0_link_flags() {
  echo "  Updating Stage0 settings link flags..."

  local settings_file="${SRC_DIR}/_build/stage0/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "WARNING: Stage0 settings file not found at ${settings_file}"
    return 1
  fi

  # Add library paths and rpath
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

  echo "  Stage0 settings after updating link flags:"
  grep -E "(C compiler link flags|ld flags)" "${settings_file}" || echo "  (grep failed)"

  echo "  ✓ Stage0 link flags updated"
}

platform_pre_build_stage1() {
  disable_copy_optimization
}

platform_build_stage1() {
  echo "  Building Stage 1 cross-compiler..."

  # Build Stage 1 GHC compiler
  run_and_log "stage1-ghc" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage1:exe:ghc-bin --docs=none --progress-info=none

  # Build Stage 1 supporting tools
  run_and_log "stage1-pkg" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage1:exe:ghc-pkg --docs=none --progress-info=none
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage1:exe:hsc2hs --docs=none --progress-info=none

  # Update link flags before building libraries
  update_stage0_link_flags

  # Build Stage 1 libraries
  run_and_log "stage1-lib" "${HADRIAN_CMD[@]}" -VV --flavour="${HADRIAN_FLAVOUR}" stage1:lib:ghc --docs=none --progress-info=none

  # Update link flags again after library build
  update_stage0_link_flags

  echo "  ✓ Stage 1 cross-compiler built"
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
# Phase 8: Build Stage 2
# ==============================================================================

platform_build_stage2() {
  echo "  Building Stage 2 cross-compiled binaries..."

  HADRIAN_FLAVOUR="release"

  # Build Stage 2 executables
  run_and_log "stage2-ghc" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage2:exe:ghc-bin --docs=none --progress-info=none
  run_and_log "stage2-pkg" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage2:exe:ghc-pkg --docs=none --progress-info=none
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage2:exe:hsc2hs --docs=none --progress-info=none

  # Note: stage2:lib:ghc not needed for cross-compilation
  # The _build/stage1 libs are already cross-compiled

  echo "  ✓ Stage 2 cross-compiled binaries built"
}

# ==============================================================================
# Phase 9: Create Binary Distribution
# ==============================================================================

platform_create_bindist() {
  echo "  Creating binary distribution..."

  run_and_log "bindist" "${HADRIAN_CMD[@]}" binary-dist \
    --prefix="${PREFIX}" \
    --flavour=release \
    --freeze1 \
    --freeze2 \
    --docs=none \
    --progress-info=none

  echo "  ✓ Binary distribution created"
}

# ==============================================================================
# Phase 10: Install
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

  # Fix tool paths to use target prefix
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|opt)\"#\"${conda_target}-\$1\"#" "${settings_file}"

  echo "  Final settings file:"
  cat "${settings_file}"

  echo "  ✓ Final settings patched"
}

create_symlinks() {
  echo "  Creating symlinks for cross-compiled tools..."

  # Create links: ${ghc_target}-ghc -> ghc, etc.
  pushd "${PREFIX}/bin" >/dev/null

  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${ghc_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${ghc_target}-${bin}" "${bin}"
      echo "    ${ghc_target}-${bin} -> ${bin}"
    fi
  done

  popd >/dev/null

  # Create directory symlink for libraries
  if [[ -d "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}" ]]; then
    mv "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}" "${PREFIX}/lib/ghc-${PKG_VERSION}"
    ln -sf "${PREFIX}/lib/ghc-${PKG_VERSION}" "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}"
    echo "    ${ghc_target}-ghc-${PKG_VERSION} -> ghc-${PKG_VERSION}"
  fi

  echo "  ✓ Symlinks created"
}

platform_install() {
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
  ac_cv_path_CC="${BUILD_PREFIX}/bin/${conda_host}-clang" \
  ac_cv_path_CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++" \
  ./configure --prefix="${PREFIX}" --target="${ghc_target}" || {
    cat config.log
    popd >/dev/null
    return 1
  }

  # Install (update_package_db fails due to cross ghc-pkg)
  run_and_log "make-install" make install_bin install_lib install_man

  popd >/dev/null

  echo "  ✓ Installation complete"
}

platform_post_install() {
  patch_final_settings
  create_symlinks
}
