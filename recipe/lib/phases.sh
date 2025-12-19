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
  # Build system config using nameref helper (native build: no target triple)
  local -a system_config
  build_system_config system_config "" "" ""

  # Build configure arguments using nameref helper
  local -a configure_args=(
    --enable-distro-toolchain
    --with-intree-gmp=no
  )

  # Add standard library paths (--with-gmp, --with-ffi, etc.)
  # build_configure_args handles Windows vs Unix path differences automatically
  build_configure_args configure_args

  # Add platform-specific args if provided (for any extra platform-specific flags)
  if type -t platform_add_configure_args >/dev/null 2>&1; then
    platform_add_configure_args configure_args
  fi

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

  # Build cabal command with optional platform-specific flags
  # Platforms can set HADRIAN_CABAL_FLAGS array before this phase
  local -a cabal_args=(-j${CPU_COUNT} hadrian)
  if [[ -n "${HADRIAN_CABAL_FLAGS[*]:-}" ]]; then
    cabal_args=("${HADRIAN_CABAL_FLAGS[@]}" "${cabal_args[@]}")
  fi

  run_and_log "build-hadrian" "${CABAL}" v2-build "${cabal_args[@]}"

  popd >/dev/null

  # Find Hadrian binary (check for .exe on Windows)
  local hadrian_bin
  hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle \( -name "hadrian" -o -name "hadrian.exe" \) -type f -perm /111 2>/dev/null | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  # Set up Hadrian command array using nameref helper
  # HADRIAN_CMD is global so it can be used by subsequent phases
  declare -ga HADRIAN_CMD  # Global array
  build_hadrian_cmd HADRIAN_CMD "${hadrian_bin}"
  FLAVOUR="${FLAVOUR:-release}"

  echo "  Hadrian binary: ${hadrian_bin}"
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
  # Build Stage 1 GHC executables (ghc-bin, ghc-pkg, hsc2hs)
  build_stage_executables 1

  # Update stage0 settings before building libraries
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage0"
  fi

  # Build Stage 1 libraries (Hadrian handles dependency order internally)
  build_stage_libraries 1
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
  # Build Stage 2 GHC executables (--freeze1 ensures Stage 1 is not rebuilt)
  build_stage_executables 2 --freeze1

  # Update stage1 settings before building libraries
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage1"
  fi

  # Build Stage 2 libraries (Hadrian handles dependency order internally)
  build_stage_libraries 2 --freeze1
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
  # Use shared bindist_install helper (native build - no target triple)
  bindist_install
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

  # Install bash completion (uses helper from helpers.sh)
  install_bash_completion

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

  call_hook "pre_activation"

  if type -t platform_activation >/dev/null 2>&1; then
    platform_activation
  else
    default_activation
  fi

  call_hook "post_activation"

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
