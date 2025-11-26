#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: macOS x86_64 → arm64 Cross-Compile
# ==============================================================================
# Purpose: Cross-compile GHC from macOS x86_64 (build machine) to arm64 (target)
#
# This platform uses a custom build flow due to macOS cross-compilation complexity:
# - Separate osx-64 bootstrap environment (conda environment)
# - Custom Hadrian build with build_hadrian_cross
# - Subshell for stage1 build with toolchain overrides
# - Architecture defines fixing
# - Hadrian config patching
#
# Dependencies: common-hooks.sh, lib/70-macos.sh, lib/60-cross-compile.sh
# ==============================================================================

set -eu

# Load common hook defaults
source "${RECIPE_DIR}/building/config/common-hooks.sh"

# ==============================================================================
# PLATFORM METADATA
# ==============================================================================

PLATFORM_NAME="osx-arm64"
PLATFORM_TYPE="cross"
INSTALL_METHOD="native"  # Uses hadrian install, not bindist

# ==============================================================================
# ARCHITECTURE DETECTION
# ==============================================================================

platform_detect_architecture() {
  # macOS cross-compilation: x86_64 → arm64

  # Save original conda aliases before any manipulation
  local original_build_alias="${build_alias}"
  local original_host_alias="${host_alias}"

  # Conda's naming for cross-compilation
  conda_host="${original_build_alias}"      # x86_64-apple-darwin13.4.0
  conda_target="${original_host_alias}"     # arm64-apple-darwin20.0.0

  # Clean up conda variables that confuse GHC
  unset host_alias
  unset HOST

  # Set for GHC configure
  export target_alias="${conda_target}"
  export host_platform="${build_platform}"

  echo "  BUILD (conda_host): ${conda_host}"
  echo "  TARGET (conda_target): ${conda_target}"
}

# ==============================================================================
# BOOTSTRAP SETUP
# ==============================================================================

platform_setup_bootstrap() {
  # macOS arm64 cross-compile requires osx-64 bootstrap environment
  # Cannot use regular BUILD_PREFIX packages because we need x86_64 binaries

  echo "=== Creating bootstrap environment (osx-64) ==="
  conda create -y \
      -n osx64_env \
      --platform osx-64 \
      -c conda-forge \
      cabal==3.10.3.0 \
      ghc-bootstrap==9.6.7

  # Get environment path
  local osx_64_env
  osx_64_env=$(conda info --envs | grep osx64_env | awk '{print $2}')
  local ghc_path="${osx_64_env}/ghc-bootstrap/bin"

  echo "  Bootstrap environment: ${osx_64_env}"

  # Export bootstrap tools
  export GHC="${ghc_path}/ghc"
  export CABAL="${osx_64_env}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}/.cabal"

  # Add GHC to PATH so cabal can find it
  export PATH="${ghc_path}:${PATH}"

  # Recache and verify
  "${ghc_path}/ghc-pkg" recache
  "${GHC}" --version || {
    echo "ERROR: Bootstrap GHC failed"
    exit 1
  }

  echo "  Bootstrap GHC ready"

  # Store environment path for later hooks
  export OSX64_ENV="${osx_64_env}"
}

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

platform_setup_environment() {
  # macOS cross-compilation environment setup

  # Step 1: Set up cross-compilation environment (exports AR_STAGE0, CC_STAGE0, etc.)
  setup_macos_cross_environment "${conda_host}" "${conda_target}"

  # Step 2: Fix bootstrap GHC settings to use conda toolchain
  fix_macos_bootstrap_settings "${OSX64_ENV}" "${conda_host}" "${AR_STAGE0}"

  echo "=== macOS arm64 cross-compilation environment ready ==="
}

# ==============================================================================
# CABAL SETUP
# ==============================================================================

platform_setup_cabal() {
  # Initialize cabal in custom directory
  mkdir -p "${CABAL_DIR}"
  "${CABAL}" user-config init

  run_and_log "cabal-update" "${CABAL}" v2-update
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

platform_build_system_config() {
  # System configuration for cross-compilation
  SYSTEM_CONFIG=(
    --build="${conda_host}"
    --host="${conda_host}"
    --target="${conda_target}"
  )
}

platform_build_configure_args() {
  # Cross-compile specific autoconf variables
  local -n args="$1"

  # Start with common configure args
  build_configure_args args

  # Add cross-compile specific overrides
  args+=(
    ac_cv_lib_ffi_ffi_call=yes
    ac_cv_path_AR="${BUILD_PREFIX}/bin/${conda_target}-ar"
    ac_cv_path_AS="${BUILD_PREFIX}/bin/${conda_target}-as"
    ac_cv_path_CC="${BUILD_PREFIX}/bin/${conda_target}-clang"
    ac_cv_path_CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"
    ac_cv_path_LD="${BUILD_PREFIX}/bin/${conda_target}-ld"
    ac_cv_path_NM="${BUILD_PREFIX}/bin/${conda_target}-nm"
    ac_cv_path_RANLIB="${BUILD_PREFIX}/bin/${conda_target}-ranlib"
    ac_cv_path_LLC="${BUILD_PREFIX}/bin/${conda_target}-llc"
    ac_cv_path_OPT="${BUILD_PREFIX}/bin/${conda_target}-opt"
    CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CFLAGS:-}"
    CPPFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CPPFLAGS:-}"
    CXXFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CXXFLAGS:-}"
    LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
  )
}

# ==============================================================================
# POST-CONFIGURE SETUP
# ==============================================================================

platform_post_configure() {
  # Patch Hadrian config for cross-compilation
  echo "=== Patching Hadrian config for cross-compilation ==="

  # Fix default.host.target
  perl -pi -e "s#--target=arm64-apple-darwin[^\"]*#--target=${conda_host}#g" \
    "${SRC_DIR}/hadrian/cfg/default.host.target"

  # Fix system.config to use target-prefixed tools
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
  perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"

  # Fix architecture defines in source tree
  echo "=== Fixing architecture defines in source tree ==="
  fix_cross_architecture_defines "x86_64" "aarch64"
}

# ==============================================================================
# HADRIAN BUILD
# ==============================================================================

platform_build_hadrian() {
  # Use cross-compile Hadrian builder (different from orchestrator's build_hadrian_binary)
  local hadrian_path
  hadrian_path=$(build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}")

  # Build command array
  HADRIAN_BUILD=("${hadrian_path}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

  echo "  Hadrian command: ${HADRIAN_BUILD[*]}"
}

# ==============================================================================
# STAGE 1 BUILD (CUSTOM FLOW)
# ==============================================================================

platform_build_stage1() {
  # Custom stage1 flow with toolchain overrides in subshell
  local -n hadrian_cmd="$1"
  local flavour="$2"

  echo "=== Building Stage 1 (Cross-Compiler) ==="

  (
    # Override toolchain for BUILD architecture
    export AR="${AR_STAGE0}"
    export AS="${BUILD_PREFIX}/bin/${conda_host}-as"
    export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
    export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
    export LD="${LD_STAGE0}"
    export NM="${BUILD_PREFIX}/bin/${conda_host}-nm"
    export RANLIB="${BUILD_PREFIX}/bin/${conda_host}-ranlib"
    export STRIP="${BUILD_PREFIX}/bin/${conda_host}-strip"

    # Build stage1 exe + tools
    echo "  Building stage 1 compiler binary"
    run_and_log "stage1_ghc-bin" "${hadrian_cmd[@]}" stage1:exe:ghc-bin --flavour="${flavour}" || true

    echo "  Building stage 1 tools"
    run_and_log "stage1_ghc-pkg" "${hadrian_cmd[@]}" stage1:exe:ghc-pkg --flavour="${flavour}"
    run_and_log "stage1_hsc2hs" "${hadrian_cmd[@]}" stage1:exe:hsc2hs --flavour="${flavour}"
  )

  # Verify stage0 GHC
  local ghc
  ghc=$(find "${SRC_DIR}/_build/stage0/bin" -name "*ghc" -type f | head -1)
  "${ghc}" --version || {
    echo "ERROR: Stage0 GHC failed"
    exit 1
  }

  echo "  Stage0 GHC verified"
}

# ==============================================================================
# STAGE 1 LIBRARIES (TARGET ARCHITECTURE)
# ==============================================================================

platform_build_stage1_libs() {
  # Build stage1 libraries for TARGET architecture (arm64)
  local -n hadrian_cmd="$1"
  local flavour="$2"

  echo "=== Building Stage 1 Libraries (arm64) ==="

  # Build libraries in dependency order (race condition prevention)
  run_and_log "stage1_ghc-prim" "${hadrian_cmd[@]}" stage1:lib:ghc-prim --flavour="${flavour}"
  run_and_log "stage1_ghc-bignum" "${hadrian_cmd[@]}" stage1:lib:ghc-bignum --flavour="${flavour}"
  run_and_log "stage1_ghc-experimental" "${hadrian_cmd[@]}" stage1:lib:ghc-experimental --flavour="${flavour}"
  run_and_log "stage1_lib" "${hadrian_cmd[@]}" stage1:lib:ghc --flavour="${flavour}"
}

# ==============================================================================
# STAGE 2 BUILD
# ==============================================================================

platform_build_stage2() {
  # Build stage2 executable for TARGET architecture
  local -n hadrian_cmd="$1"
  local flavour="$2"

  echo "=== Building Stage 2 Executable (arm64) ==="
  run_and_log "stage2_exe" "${hadrian_cmd[@]}" stage2:exe:ghc-bin --flavour="${flavour}" --freeze1
}

# ==============================================================================
# RACE CONDITION PREVENTION
# ==============================================================================

platform_build_cabal_syntax() {
  # Explicit Cabal-syntax build to prevent Parsec.dyn_hi race
  local -n hadrian_cmd="$1"
  local flavour="$2"

  echo "=== Building Cabal-syntax explicitly (prevents Parsec.dyn_hi race) ==="
  run_and_log "stage1_cabal-syntax" "${hadrian_cmd[@]}" stage1:lib:Cabal-syntax --flavour="${flavour}"
}

# ==============================================================================
# FINAL BUILD AND INSTALL
# ==============================================================================

platform_install() {
  # Build all components and install
  local -n hadrian_cmd="$1"
  local flavour="$2"

  echo "=== Building all components ==="
  run_and_log "build_all" "${hadrian_cmd[@]}" --flavour="${flavour}" --freeze1 --freeze2

  echo "=== Installing to ${PREFIX} ==="
  run_and_log "install" "${hadrian_cmd[@]}" install \
    --prefix="${PREFIX}" \
    --flavour="${flavour}" \
    --freeze1 \
    --freeze2
}

# Export all functions
export -f platform_detect_architecture
export -f platform_setup_bootstrap
export -f platform_setup_environment
export -f platform_setup_cabal
export -f platform_build_system_config
export -f platform_build_configure_args
export -f platform_post_configure
export -f platform_build_hadrian
export -f platform_build_stage1
export -f platform_build_stage1_libs
export -f platform_build_stage2
export -f platform_build_cabal_syntax
export -f platform_install
