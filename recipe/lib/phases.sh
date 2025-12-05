#!/usr/bin/env bash
# ==============================================================================
# GHC Build Phases - Build Flow Orchestration
# ==============================================================================
# Provides the 10-phase build flow for GHC:
#   1. Environment Setup    6. Build Stage 1
#   2. Bootstrap Setup      7. Build Stage 2
#   3. Cabal Setup          8. Install GHC
#   4. Configure GHC        9. Post-Install
#   5. Build Hadrian       10. Activation
#
# Each phase follows the hook pattern:
#   1. platform_pre_xxx()  - Hook before phase
#   2. platform_xxx() OR default_xxx() - Implementation
#   3. platform_post_xxx() - Hook after phase
#
# Requires: helpers.sh (for run_and_log, build_*, call_hook)
# ==============================================================================

set -eu

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

phase_setup_environment() {
  echo ""
  echo "===================================================================="
  echo "  Phase 1: Environment Setup"
  echo "===================================================================="

  call_hook "pre_setup_environment"

  # Always set common environment first
  common_setup_environment

  # Platform can override/extend, otherwise use default
  if type -t platform_setup_environment >/dev/null 2>&1; then
    platform_setup_environment
  else
    default_setup_environment
  fi

  call_hook "post_setup_environment"

  echo "  ✓ Environment setup complete"
  echo ""
}

# Common environment variables - always runs before platform-specific setup
common_setup_environment() {
  # Standard tool paths (can be overridden by platform_setup_environment if needed)
  export M4="${BUILD_PREFIX}/bin/m4"
  export PYTHON="${BUILD_PREFIX}/bin/python"

  # Bootstrap GHC setup (Windows handles this differently in platform_setup_environment)
  if [[ "${target_platform}" != "win-64" ]]; then
    ghc_path="${BUILD_PREFIX}/ghc-bootstrap/bin"
    export GHC="${ghc_path}/ghc"
    export PATH="${ghc_path}:${PATH:-}"

    echo "  Bootstrap GHC: ${GHC}"
    "${GHC}" --version
    "${ghc_path}/ghc-pkg" recache
  fi

  echo "  Common environment configured"
}

default_setup_environment() {
  # Default PATH setup for Unix platforms (Linux/macOS native)
  # Called only if no platform_setup_environment exists
  export PATH="${BUILD_PREFIX}/bin:${BUILD_PREFIX}/ghc-bootstrap/bin:${PATH}"

  echo "  Default PATH configured"
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

  # Always set common cabal environment first
  common_setup_cabal

  # Platform can override/extend, otherwise use default
  if type -t platform_setup_cabal >/dev/null 2>&1; then
    platform_setup_cabal
  else
    default_setup_cabal
  fi

  call_hook "post_setup_cabal"

  echo "  ✓ Cabal setup complete"
  echo ""
}

# Common Cabal variables - always runs before platform-specific setup
common_setup_cabal() {
  # Use SRC_DIR for isolation (not HOME which pollutes user directory)
  # Platform scripts can override CABAL path if needed (e.g., Windows, cross-compile envs)
  export CABAL="${CABAL:-${BUILD_PREFIX}/bin/cabal}"
  export CABAL_DIR="${CABAL_DIR:-${SRC_DIR}/.cabal}"

  echo "  CABAL=${CABAL}"
  echo "  CABAL_DIR=${CABAL_DIR}"
}

default_setup_cabal() {
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
  echo "  DEBUG: Entering default_configure_ghc"

  # Build system config using nameref helper (native build: no target triple)
  echo "  DEBUG: Building system_config..."
  local -a system_config
  build_system_config system_config "" "" ""
  echo "  DEBUG: system_config: ${system_config[*]:-EMPTY}"

  # Build configure arguments using nameref helper
  # NOTE: Do NOT pass --with-intree-gmp=no! GHC 9.2.8's configure has a bug
  # where ANY value passed to --with-intree-gmp triggers GMP_FORCE_INTREE=YES.
  # Without this option, configure defaults to GMP_FORCE_INTREE=NO and uses
  # system GMP from --with-gmp-includes and --with-gmp-libraries.
  local -a configure_args=(
    --enable-distro-toolchain
  )

  # Add standard library paths (--with-gmp, --with-ffi, etc.)
  # Skip for Windows - it uses platform_add_configure_args with different paths
  echo "  DEBUG: target_platform=${target_platform:-UNSET}"
  if [[ "${target_platform:-}" != "win-64" ]]; then
    echo "  DEBUG: Calling build_configure_args..."
    build_configure_args configure_args
  else
    echo "  DEBUG: Skipping build_configure_args for Windows"
  fi

  # Add platform-specific args if provided (legacy callback pattern)
  if type -t platform_add_configure_args >/dev/null 2>&1; then
    echo "  DEBUG: Calling platform_add_configure_args..."
    platform_add_configure_args configure_args
  fi

  echo "  DEBUG: configure_args count: ${#configure_args[@]}"
  echo "  DEBUG: Calling run_and_log configure..."

  # Run configure
  pushd "${SRC_DIR}" >/dev/null
  run_and_log "configure" ./configure "${system_config[@]}" "${configure_args[@]}"
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
  local hadrian_bin
  hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle -name hadrian -type f -perm /111 | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  # Set up Hadrian command array using nameref helper
  # HADRIAN_CMD is global so it can be used by subsequent phases
  declare -ga HADRIAN_CMD  # Global array
  build_hadrian_cmd HADRIAN_CMD "${hadrian_bin}"
  HADRIAN_FLAVOUR="${HADRIAN_FLAVOUR:-quick}"
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
  local -a options=(--flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=none)
  run_and_log    "stage1-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:exe:ghc-bin
  run_and_log    "stage1-pkg" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:exe:ghc-pkg
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:exe:hsc2hs

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
  # Build Stage 2 GHC executables and libraries
  # --freeze1 ensures Stage 1 compiler is not rebuilt
  local -a options=(--flavour="${HADRIAN_FLAVOUR}" --freeze1 --docs=none --progress-info=none)
  run_and_log    "stage2-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-bin
  run_and_log    "stage2-pkg" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-pkg
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:hsc2hs

  # Update stage1 settings before building libraries (if helper available)
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage1"
  fi

  # Build Stage 2 libraries in staggered order to avoid race conditions
  run_and_log   "stage2-lib-prim" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-prim
  run_and_log "stage2-lib-bignum" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-bignum
  run_and_log   "stage2-lib-base" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:base
  run_and_log     "stage2-lib-th" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:template-haskell
  run_and_log   "stage2-lib-ghci" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghci
  run_and_log    "stage2-lib-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc

  # Update stage1 settings again after library build
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage1"
  fi
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
  # Available targets: install_bin install_lib install_includes install_docs update_package_db
  # (no install_man in GHC 9.2.8)
  pushd "${bindist_dir}" >/dev/null
    ./configure --prefix="${PREFIX}" || { cat config.log; exit 1; }
    run_and_log "make-install" make install_bin install_lib install_includes
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

  echo "  ✓ Activation complete"
  echo ""
}

default_activation() {
  echo "  Setting up activation scripts..."

  local sh_ext
  sh_ext=$(get_script_extension)

  mkdir -p "${PREFIX}/etc/conda/activate.d"
  cp "${RECIPE_DIR}/scripts/activate.${sh_ext}" "${PREFIX}/etc/conda/activate.d/ghc_activate.${sh_ext}"
  echo "  Activation scripts installed"
}
