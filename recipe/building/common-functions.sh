#!/usr/bin/env bash
# ==============================================================================
# Common Build Functions - Default Implementations
# ==============================================================================
# Provides default behavior for all build phases.
# Platform configs can override by defining platform_xxx() functions.
#
# Hook Pattern:
#   Each phase calls:
#     1. platform_pre_xxx()  (if defined) - setup before phase
#     2. platform_xxx()      (if defined) - custom implementation
#        OR default_xxx()    (if platform_xxx not defined) - default
#     3. platform_post_xxx() (if defined) - cleanup/validation after phase
# ==============================================================================

set -eu

# ==============================================================================
# Logging Index (for run_and_log)
# ==============================================================================

_log_index=0

# ==============================================================================
# Helper Functions
# ==============================================================================

run_and_log() {
  local phase="$1"
  shift

  ((_log_index++)) || true
  mkdir -p "${SRC_DIR}/_logs"
  local log_file="${SRC_DIR}/_logs/$(printf "%02d" ${_log_index})-${phase}.log"

  echo "  Running: $*"
  echo "  Log: ${log_file}"

  "$@" > "${log_file}" 2>&1 || {
    echo "*** Command failed! Last 50 lines:"
    tail -50 "${log_file}"
    return 1
  }
  return ${PIPESTATUS[0]}
}

# ==============================================================================
# Settings Update Helpers
# ==============================================================================

# Update stage settings file with library paths and rpaths
# This is commonly needed between build phases to ensure proper linking
#
# Usage:
#   update_stage_settings "stage0"
#   update_stage_settings "stage1"
#
# Parameters:
#   $1 - stage: Which stage settings to update (stage0, stage1)
#
update_stage_settings() {
  local stage="$1"
  local settings_file="${SRC_DIR}/_build/${stage}/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: ${stage} settings file not found at ${settings_file}"
    return 0
  fi

  # Check if flags are already present (idempotent operation)
  if grep -q "Wl,-L\${PREFIX}/lib" "${settings_file}" 2>/dev/null || \
     grep -q "Wl,-L${PREFIX}/lib" "${settings_file}" 2>/dev/null; then
    echo "  ${stage} settings already have library paths, skipping update"
    return 0
  fi

  echo "  Updating ${stage} settings with library paths..."

  # Add library paths and rpath
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

  echo "  ${stage} settings after update:"
  grep -E "(C compiler link flags|ld flags)" "${settings_file}" 2>/dev/null || echo "  (no matching lines)"

  echo "  ✓ ${stage} settings updated"
}

# Update settings file with platform-specific link flags
# Used by platform scripts to patch GHC settings during build
#
# Usage:
#   update_settings_link_flags "${settings_file}"
#
# Parameters:
#   $1 - settings_file: Path to GHC settings file
#   $2 - toolchain: Toolchain prefix (optional, defaults to $CONDA_TOOLCHAIN_HOST)
#   $3 - prefix: Install prefix (optional, defaults to $PREFIX)
#
update_settings_link_flags() {
  local settings_file="$1"
  local toolchain="${2:-$CONDA_TOOLCHAIN_HOST}"
  local prefix="${3:-$PREFIX}"

  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"

    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${prefix}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${prefix}/lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${prefix}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${prefix}/lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-arm64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fuse-ld=lld -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
  fi

  # Update toolchain paths
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${settings_file}"
}

# ==============================================================================
# Cross-Compilation Helpers
# ==============================================================================

# Disable Hadrian's copy optimization for cross-compilation
# By default, Hadrian tries to copy the bootstrap GHC binary instead of building
# a new one. For cross-compilation, we need to force building the cross binary.
#
# Usage:
#   disable_copy_optimization
#
disable_copy_optimization() {
  echo "  Disabling copy optimization for cross-compilation..."

  # Force building the cross binary instead of copying
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' \
    "${SRC_DIR}/hadrian/src/Rules/Program.hs"

  echo "  ✓ Copy optimization disabled"
}

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

phase_setup_environment() {
  echo ""
  echo "===================================================================="
  echo "  Phase 1: Environment Setup"
  echo "===================================================================="

  call_hook "pre_setup_environment"

  if type -t platform_setup_environment >/dev/null 2>&1; then
    platform_setup_environment
  else
    default_setup_environment
  fi

  call_hook "post_setup_environment"

  echo "  ✓ Environment setup complete"
  echo ""
}

default_setup_environment() {
  # Common environment setup (Linux/macOS)
  export PATH="${BUILD_PREFIX}/bin:${BUILD_PREFIX}/ghc-bootstrap/bin:${PATH}"
  export M4="${BUILD_PREFIX}/bin/m4"
  export PYTHON="${BUILD_PREFIX}/bin/python"

  echo "  Standard environment configured"
}

# ==============================================================================
# Phase 2: Bootstrap Setup
# ==============================================================================

phase_setup_bootstrap() {
  echo ""
  echo "===================================================================="
  echo "  Phase 2: Bootstrap Setup"
  echo "===================================================================="

  call_hook "pre_setup_bootstrap"

  if type -t platform_setup_bootstrap >/dev/null 2>&1; then
    platform_setup_bootstrap
  else
    default_setup_bootstrap
  fi

  call_hook "post_setup_bootstrap"

  # Verify bootstrap GHC
  if [[ -n "${GHC:-}" ]]; then
    echo "  Bootstrap GHC: ${GHC}"
    "${GHC}" --version || {
      echo "ERROR: Bootstrap GHC failed"
      exit 1
    }
  fi

  echo "  ✓ Bootstrap setup complete"
  echo ""
}

default_setup_bootstrap() {
  # Find bootstrap GHC
  export GHC=$(which ghc 2>/dev/null || echo "")
  if [[ -z "${GHC}" ]]; then
    echo "ERROR: Bootstrap GHC not found in PATH"
    exit 1
  fi

  echo "  Bootstrap GHC found: ${GHC}"
}

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

phase_setup_cabal() {
  echo ""
  echo "===================================================================="
  echo "  Phase 3: Cabal Setup"
  echo "===================================================================="

  call_hook "pre_setup_cabal"

  if type -t platform_setup_cabal >/dev/null 2>&1; then
    platform_setup_cabal
  else
    default_setup_cabal
  fi

  call_hook "post_setup_cabal"

  echo "  ✓ Cabal setup complete"
  echo ""
}

default_setup_cabal() {
  export CABAL="${BUILD_PREFIX}/bin/cabal"
  export CABAL_DIR="${HOME}/.cabal"

  mkdir -p "${CABAL_DIR}"

  # Initialize cabal if config doesn't exist
  if [[ ! -f "${CABAL_DIR}/config" ]]; then
    "${CABAL}" user-config init
  fi

  # Update package index
  run_and_log "cabal-update" "${CABAL}" v2-update
}

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

phase_configure_ghc() {
  echo ""
  echo "===================================================================="
  echo "  Phase 4: Configure GHC"
  echo "===================================================================="

  call_hook "pre_configure_ghc"

  if type -t platform_configure_ghc >/dev/null 2>&1; then
    platform_configure_ghc
  else
    default_configure_ghc
  fi

  call_hook "post_configure_ghc"

  echo "  ✓ GHC configure complete"
  echo ""
}

default_configure_ghc() {
  # Build configure arguments
  local configure_args=(
    --prefix="${PREFIX}"
    --enable-distro-toolchain
    --with-intree-gmp=no
    --with-gmp-includes="${PREFIX}/include"
    --with-gmp-libraries="${PREFIX}/lib"
    --with-ffi-includes="${PREFIX}/include"
    --with-ffi-libraries="${PREFIX}/lib"
    --with-iconv-includes="${PREFIX}/include"
    --with-iconv-libraries="${PREFIX}/lib"
    --with-curses-includes="${PREFIX}/include"
    --with-curses-libraries="${PREFIX}/lib"
  )

  # Add platform-specific args if provided
  if type -t platform_add_configure_args >/dev/null 2>&1; then
    platform_add_configure_args configure_args
  fi

  # Run configure
  pushd "${SRC_DIR}" >/dev/null
  run_and_log "configure" ./configure "${configure_args[@]}"
  popd >/dev/null
}

# ==============================================================================
# Phase 5: Build Hadrian
# ==============================================================================

phase_build_hadrian() {
  echo ""
  echo "===================================================================="
  echo "  Phase 5: Build Hadrian"
  echo "===================================================================="

  call_hook "pre_build_hadrian"

  if type -t platform_build_hadrian >/dev/null 2>&1; then
    platform_build_hadrian
  else
    default_build_hadrian
  fi

  call_hook "post_build_hadrian"

  echo "  Hadrian command: ${HADRIAN_CMD[*]}"
  echo "  ✓ Hadrian build complete"
  echo ""
}

default_build_hadrian() {
  pushd "${SRC_DIR}/hadrian" >/dev/null
    run_and_log "build-hadrian" "${CABAL}" v2-build hadrian
  popd >/dev/null

  # Find Hadrian binary
  local hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle -name hadrian -type f | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  # Set up Hadrian command array
  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT:-1}" "--directory" "${SRC_DIR}")
  HADRIAN_FLAVOUR="${HADRIAN_FLAVOUR:-release}"
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

phase_build_stage1() {
  echo ""
  echo "===================================================================="
  echo "  Phase 6: Build Stage 1"
  echo "===================================================================="

  call_hook "pre_build_stage1"

  if type -t platform_build_stage1 >/dev/null 2>&1; then
    platform_build_stage1
  else
    default_build_stage1
  fi

  call_hook "post_build_stage1"

  echo "  ✓ Stage 1 build complete"
  echo ""
}

default_build_stage1() {
  # Build Stage 1 GHC executables
  options=(--flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=none)
  run_and_log    "stage1-ghc" "${HADRIAN_CMD[@]}" ${options[@]} stage1:exe:ghc-bin
  run_and_log    "stage1-pkg" "${HADRIAN_CMD[@]}" ${options[@]} stage1:exe:ghc-pkg
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" ${options[@]} stage1:exe:hsc2hs

  # Update stage0 settings before building libraries (if helper available)
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage0"
  fi

  # Build Stage 1 libraries in staggered order to avoid race conditions
  run_and_log   "stage1-lib-prim" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc-prim
  run_and_log "stage1-lib-bignum" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc-bignum
  run_and_log   "stage1-lib-base" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:base
  run_and_log     "stage1-lib-th" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:template-haskell
  run_and_log   "stage1-lib-ghci" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghci
  run_and_log    "stage1-lib-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc

  # Update stage0 settings again after library build
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage0"
  fi
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

phase_build_stage2() {
  echo ""
  echo "===================================================================="
  echo "  Phase 7: Build Stage 2"
  echo "===================================================================="

  call_hook "pre_build_stage2"

  if type -t platform_build_stage2 >/dev/null 2>&1; then
    platform_build_stage2
  else
    default_build_stage2
  fi

  call_hook "post_build_stage2"

  echo "  ✓ Stage 2 build complete"
  echo ""
}

default_build_stage2() {
  # Build Stage 2 GHC libraries
  options=(--flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=none)
  run_and_log    "stage2-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-bin
  run_and_log    "stage2-pkg" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-pkg
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:hsc2hs

  # Build Stage 1 libraries in staggered order to avoid race conditions
  run_and_log   "stage2-lib-prim" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-prim
  run_and_log "stage2-lib-bignum" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-bignum
  run_and_log   "stage2-lib-base" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:base
  run_and_log     "stage2-lib-th" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:template-haskell
  run_and_log   "stage2-lib-ghci" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghci
  run_and_log    "stage2-lib-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

phase_install_ghc() {
  echo ""
  echo "===================================================================="
  echo "  Phase 8: Install GHC"
  echo "===================================================================="

  call_hook "pre_install_ghc"

  if type -t platform_install_ghc >/dev/null 2>&1; then
    platform_install_ghc
  else
    default_install_ghc
  fi

  call_hook "post_install_ghc"

  echo "  ✓ GHC installation complete"
  echo ""
}

default_install_ghc() {
  # Create binary distribution
  run_and_log "binary-dist" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" binary-dist --prefix="${PREFIX}"

  # Find bindist directory
  local bindist_dir=$(find "${SRC_DIR}"/_build/bindist -type d -name "ghc-${PKG_VERSION}-*" | head -1)

  if [[ -z "${bindist_dir}" ]]; then
    echo "ERROR: Binary distribution directory not found"
    exit 1
  fi

  echo "  Installing from: ${bindist_dir}"

  # Install from bindist
  pushd "${bindist_dir}" >/dev/null
    ./configure --prefix="${PREFIX}" || { cat config.log; exit 1; }
    run_and_log "make-install" make install
  popd >/dev/null
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

phase_post_install() {
  echo ""
  echo "===================================================================="
  echo "  Phase 9: Post-Install"
  echo "===================================================================="

  call_hook "pre_post_install"

  if type -t platform_post_install >/dev/null 2>&1; then
    platform_post_install
  else
    default_post_install
  fi

  call_hook "post_post_install"

  echo "  ✓ Post-install complete"
  echo ""
}

default_post_install() {
  # Verify installation
  echo "  Verifying GHC installation..."
  "${PREFIX}/bin/ghc" --version || {
    echo "ERROR: Installed GHC failed to run"
    exit 1
  }

  case "${target_platform}" in
    linux-64|linux-aarch64|linux-ppc64le|osx-64|osx-arm64)
      sh_ext="sh"
      ;;
    *)
      sh_ext="bat"
      ;;
  esac
  
  cp ${RECIPE_DIR}/activate.${sh_ext} ${PREFIX}/etc/conda/activate.d/ghc_activate.${sh_ext}
  echo "  GHC installed successfully"
}

# ==============================================================================
# Phase 10: Activation
# ==============================================================================

phase_activation() {
  echo ""
  echo "===================================================================="
  echo "  Phase 10: Activation"
  echo "===================================================================="

  if type -t platform_activation >/dev/null 2>&1; then
    platform_activation
  else
    default_activation
  fi

  echo "  ✓ Post-install complete"
  echo ""
}

default_activation() {
  # Verify installation
  echo "  Activation GHC installation..."

  case "${target_platform}" in
    linux-64|linux-aarch64|linux-ppc64le|osx-64|osx-arm64)
      sh_ext="sh"
      ;;
    *)
      sh_ext="bat"
      ;;
  esac
  
  cp ${RECIPE_DIR}/activate.${sh_ext} ${PREFIX}/etc/conda/activate.d/ghc_activate.${sh_ext}
  echo "  GHC installed successfully"
}

# ==============================================================================
# Hook Execution Helper
# ==============================================================================

call_hook() {
  local hook_name="platform_$1"
  if type -t "${hook_name}" >/dev/null 2>&1; then
    "${hook_name}"
  fi
}
