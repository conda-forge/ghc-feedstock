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
#   1. call_hook "pre_xxx"       - Pre-phase hook
#   2. common_xxx() if exists    - Common setup (always runs)
#   3. platform_xxx() OR default_xxx() - Implementation
#   4. call_hook "post_xxx"      - Post-phase hook
#
# The generic run_phase() executor handles all phases uniformly.
# Requires: helpers.sh (for run_and_log, build_*, call_hook)
#
# ==============================================================================
# SHARED ORCHESTRATORS (helpers.sh)
# ==============================================================================
# Use these unified orchestrators in platform scripts for consistency:
#
# Configure Phase:
#   shared_configure_ghc(build, host, [target])    - Native builds
#   shared_cross_configure_ghc(extra_ldflags)      - Cross-compile
#   shared_post_configure_ghc(toolchain_prefix)    - Post-configure patching
#
# Stage Build Phase:
#   cross_pre_stage1_standard()                    - Cross-compile pre-Stage1
#   build_stage_executables(stage, [extra_opts])   - Build exe targets
#   build_stage_libraries(stage, [extra_opts])     - Build lib targets
#
# Install Phase:
#   shared_install_ghc([target], [extra_args])     - Auto-detects native/cross
#   shared_post_install_ghc([target], [expect_fail]) - Post-install validation
#
# Platform scripts should prefer orchestrators over inline implementations.
# This ensures consistent behavior and simplifies maintenance.
# ==============================================================================

set -eu

# ==============================================================================
# Internal Helpers
# ==============================================================================
# (Previously contained _patch_stage_linker_flags - now unified in helpers.sh
# as shared_patch_stage_settings() which auto-detects platform)

# ==============================================================================
# Generic Phase Executor
# ==============================================================================
# Executes a build phase using the standard hook pattern.
# Reduces 10 nearly-identical phase functions to a single generic executor.
#
# Parameters:
#   $1 - phase_num: Phase number for display (1-10)
#   $2 - phase_name: Phase name (e.g., "setup_environment", "configure_ghc")
#   $3 - display_name: Human-readable name for output (optional)
#
# Flow:
#   1. call_hook "pre_${phase_name}"
#   2. common_${phase_name}() if exists
#   3. platform_${phase_name}() OR default_${phase_name}()
#   4. call_hook "post_${phase_name}"
#
# Usage:
#   run_phase 1 "setup_environment" "Environment Setup"
#
run_phase() {
  local phase_num="$1"
  local phase_name="$2"
  local display_name="${3:-${phase_name//_/ }}"

  echo ""
  echo "===================================================================="
  echo "  Phase ${phase_num}: ${display_name}"
  echo "===================================================================="

  # Pre-phase hook
  call_hook "pre_${phase_name}"

  # Run common setup if it exists (e.g., common_setup_environment)
  local common_func="common_${phase_name}"
  if type -t "${common_func}" >/dev/null 2>&1; then
    "${common_func}"
  fi

  # Run platform override or default
  local platform_func="platform_${phase_name}"
  local default_func="default_${phase_name}"
  if type -t "${platform_func}" >/dev/null 2>&1; then
    "${platform_func}"
  elif type -t "${default_func}" >/dev/null 2>&1; then
    "${default_func}"
  fi

  # Post-phase hook
  call_hook "post_${phase_name}"

  echo "  ✓ ${display_name} complete"
  echo ""
}

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

phase_setup_environment() { run_phase 1 "setup_environment" "Environment Setup"; }

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

phase_setup_bootstrap() { run_phase 2 "setup_bootstrap" "Bootstrap Setup"; }

default_setup_bootstrap() {
  # Find bootstrap GHC
  export GHC=$(which ghc 2>/dev/null || echo "")
  if [[ -z "${GHC}" ]]; then
    echo "ERROR: Bootstrap GHC not found in PATH"
    exit 1
  fi

  echo "  Bootstrap GHC found: ${GHC}"

  # Verify bootstrap GHC works
  "${GHC}" --version || {
    echo "ERROR: Bootstrap GHC failed"
    exit 1
  }
}

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

phase_setup_cabal() { run_phase 3 "setup_cabal" "Cabal Setup"; }

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

phase_configure_ghc() { run_phase 4 "configure_ghc" "Configure GHC"; }

default_configure_ghc() {
  # Auto-detect native vs cross-compile and delegate appropriately
  if is_cross_compile; then
    default_cross_configure_ghc
  else
    shared_configure_ghc "${ghc_triple}" "${ghc_triple}"
  fi
}

# Smart default: Auto-detect toolchain prefix for post-configure patching
# Eliminates platform_post_configure_ghc() from linux-64, linux-cross, osx-64, osx-arm64
default_post_configure_ghc() {
  local toolchain_prefix
  if is_cross_compile; then
    toolchain_prefix="${conda_target:-${ghc_target}}"
  else
    toolchain_prefix="${ghc_triple}"
  fi
  shared_post_configure_ghc "${toolchain_prefix}"
}

# ==============================================================================
# Phase 5: Build Hadrian
# ==============================================================================

phase_build_hadrian() {
  run_phase 5 "build_hadrian" "Build Hadrian"
  # Display Hadrian command after phase completes (useful for debugging)
  echo "  Hadrian command: ${HADRIAN_CMD[*]}"
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

phase_build_stage1() { run_phase 6 "build_stage1" "Build Stage 1"; }

# Smart default: Auto-detect cross-compile for pre-stage1 setup
# Eliminates platform_pre_build_stage1() from linux-cross, osx-arm64
default_pre_build_stage1() {
  if is_cross_compile; then
    cross_pre_stage1_standard
  fi
  # Native builds: no-op
}

default_build_stage1() {
  # Build Stage 1 GHC executables (ghc-bin, ghc-pkg, hsc2hs)
  build_stage_executables 1

  # Unified stage settings patching (auto-detects platform)
  # - Linux: adds library paths and rpath
  # - macOS: uses llvm-ar and platform link flags
  # - Windows: no-op (uses granular hooks via build_stage_executables)
  shared_patch_stage_settings "stage0"

  # Build Stage 1 libraries (Hadrian handles dependency order internally)
  build_stage_libraries 1
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

phase_build_stage2() { run_phase 7 "build_stage2" "Build Stage 2"; }

default_build_stage2() {
  # Build Stage 2 GHC executables (--freeze1 ensures Stage 1 is not rebuilt)
  build_stage_executables 2 --freeze1

  # Unified stage settings patching (auto-detects platform)
  # - Linux: adds library paths and rpath
  # - macOS: uses llvm-ar and platform link flags
  # - Windows: no-op (uses granular hooks via build_stage_executables)
  shared_patch_stage_settings "stage1"

  # Build Stage 2 libraries (Hadrian handles dependency order internally)
  build_stage_libraries 2 --freeze1
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

phase_install_ghc() { run_phase 8 "install_ghc" "Install GHC"; }

default_install_ghc() {
  # Use shared bindist_install helper (native build - no target triple)
  bindist_install
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

phase_post_install() { run_phase 9 "post_install" "Post-Install"; }

default_post_install() {
  # Verify all expected binaries exist
  verify_installed_binaries || exit 1

  # Verify GHC runs (uses helper from helpers.sh)
  verify_installed_ghc || exit 1

  # Install bash completion (uses helper from helpers.sh)
  install_bash_completion

  echo "  GHC installed successfully"
}

# ==============================================================================
# Phase 10: Activation
# ==============================================================================

phase_activation() { run_phase 10 "activation" "Activation"; }

default_activation() {
  echo "  Setting up activation scripts..."

  local sh_ext
  sh_ext=$(get_script_extension)

  mkdir -p "${PREFIX}/etc/conda/activate.d"
  cp "${RECIPE_DIR}/scripts/activate.${sh_ext}" "${PREFIX}/etc/conda/activate.d/ghc_activate.${sh_ext}"
  echo "  Activation scripts installed"
}
