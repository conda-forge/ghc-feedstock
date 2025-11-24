#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux Cross-Compilation
# ==============================================================================
# Purpose: Cross-compile GHC from x86_64 to aarch64 or ppc64le
#
# Targets: linux-aarch64, linux-ppc64le
#
# Dependencies: common-hooks.sh (for defaults)
# ==============================================================================

set -eu

# Load common hook defaults
source "${RECIPE_DIR}/building/config/common-hooks.sh"

# ==============================================================================
# PLATFORM METADATA
# ==============================================================================

PLATFORM_NAME="linux-cross"
PLATFORM_TYPE="cross"
INSTALL_METHOD="bindist"

# ==============================================================================
# ARCHITECTURE DETECTION
# ==============================================================================

platform_detect_architecture() {
  # Save original conda aliases
  local original_build_alias="${build_alias}"
  local original_host_alias="${host_alias}"

  # Extract architectures
  conda_host="${original_build_alias}"      # e.g., x86_64-conda-linux-gnu (BUILD)
  conda_target="${original_host_alias}"     # e.g., aarch64-conda-linux-gnu (TARGET)
  host_arch="${original_build_alias%%-*}"   # e.g., x86_64 (BUILD)
  target_arch="${original_host_alias%%-*}"  # e.g., aarch64 (TARGET)

  # GHC triples
  ghc_host="${host_arch}-unknown-linux-gnu"
  ghc_target="${target_arch}-unknown-linux-gnu"

  echo "  BUILD:  ${conda_host} -> ${ghc_host}"
  echo "  TARGET: ${conda_target} -> ${ghc_target}"

  # Override autoconf variables for GHC configure
  export build_alias="${ghc_host}"
  export host_alias="${ghc_host}"
}

# ==============================================================================
# BOOTSTRAP
# ==============================================================================

platform_setup_bootstrap() {
  setup_cross_build_env "linux-64" "libc2.17_env" "sysroot_linux-64==2.17"

  echo "  Bootstrap GHC: ${GHC}"
  "${GHC}" --version
}

# ==============================================================================
# CABAL SETUP (override for cross-compile)
# ==============================================================================

platform_setup_cabal() {
  # For cross-compile, cabal is in the bootstrap environment, not BUILD_PREFIX
  # setup_cross_build_env already set CABAL, CABAL_DIR, and ran cabal init + update

  # Verify they're set
  if [[ -z "${CABAL:-}" ]]; then
    echo "ERROR: CABAL not set by setup_cross_build_env"
    return 1
  fi

  if [[ -z "${CABAL_DIR:-}" ]]; then
    echo "ERROR: CABAL_DIR not set by setup_cross_build_env"
    return 1
  fi

  echo "  Using bootstrap cabal: ${CABAL}"
  echo "  Cabal already initialized by setup_cross_build_env"

  # Skip common flow's cabal init and update (already done)
  export CABAL_SKIP_INIT=true
}

# ==============================================================================
# ENVIRONMENT
# ==============================================================================

platform_setup_environment() {
  # PowerPC64LE ABI v2 configuration
  if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
    echo "  PowerPC64LE detected: Configuring ABI v2"
    export CFLAGS="${CFLAGS:-} -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"
    export CXXFLAGS="${CXXFLAGS:-} -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"
  fi
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

platform_build_system_config() {
  SYSTEM_CONFIG=(
    --target="${ghc_target}"
  )
}

platform_build_configure_args() {
  # Build standard configure args
  build_configure_args CONFIGURE_ARGS

  # Add cross-compilation specific autoconf variables
  CONFIGURE_ARGS+=(
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

  # Set autoconf toolchain variables
  set_autoconf_toolchain_vars "${conda_target}" "false"
}

# ==============================================================================
# BUILD HOOKS
# ==============================================================================

platform_pre_configure() {
  # PowerPC64LE: Patch Hadrian config BEFORE configure
  if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
    echo "  Patching Hadrian config for PowerPC64LE..."
    for config_file in "${SRC_DIR}"/hadrian/cfg/default.target "${SRC_DIR}"/hadrian/cfg/*.ghc-toolchain; do
      if [[ -f "${config_file}" ]]; then
        perl -pi -e 's/"-Qunused-arguments"/"-mabi=elfv2","-Dpowerpc64le_HOST_ARCH","-Dlinux_HOST_OS","-Qunused-arguments"/g' "${config_file}"
      fi
    done
  fi
}

platform_post_configure() {
  # Update Hadrian system.config for cross-compilation
  update_hadrian_system_config "${conda_target}" "false"
}

platform_build_hadrian() {
  local var_name="$1"

  echo "  Building Hadrian with BUILD machine toolchain..."

  # Stage 0 tools (BUILD machine)
  export AR_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export CC_STAGE0="${CC_FOR_BUILD}"
  export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

  # Build machine flags
  local build_cflags="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include"
  local build_ldflags="-L${CROSS_ENV_PATH}/${conda_host}/lib -L${CROSS_ENV_PATH}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"

  # Build Hadrian with cross-compile toolchain
  build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}" "${build_cflags}" "${build_ldflags}"

  # Set up Hadrian command array
  local -n hadrian_array="$var_name"
  hadrian_array=("${HADRIAN_BIN}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")
}

platform_select_flavour() {
  # Using release for both stages for consistency and full optimization
  HADRIAN_FLAVOUR_STAGE1="release"
  HADRIAN_FLAVOUR_STAGE2="release"

  echo "  Stage 1: ${HADRIAN_FLAVOUR_STAGE1} (cross-compiler)"
  echo "  Stage 2: ${HADRIAN_FLAVOUR_STAGE2} (target binaries)"
}

platform_pre_stage1() {
  # Disable copy optimization (force cross-compiler build)
  echo "  Disabling copy optimization for cross-compilation..."
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' \
    "${SRC_DIR}"/hadrian/src/Rules/Program.hs
}

platform_post_stage1() {
  # PowerPC64LE: Patch ghcplatform.h AFTER stage1 build
  if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
    echo "  Patching ghcplatform.h for PowerPC64LE..."
    local ghcplatform_stage1="${SRC_DIR}/_build/stage1/rts/build/include/ghcplatform.h"

    if [[ -f "${ghcplatform_stage1}" ]] && ! grep -q "^#define powerpc64le_HOST_ARCH" "${ghcplatform_stage1}"; then
      perl -pi -e 's/(#define powerpc64_HOST_ARCH\s+1)/$1\n#define powerpc64le_HOST_ARCH  1/' "${ghcplatform_stage1}"
      echo "  Successfully patched: ${ghcplatform_stage1}"
    fi
  fi

  # Set GHC to use stage1 compiler for stage2 build
  export GHC="${SRC_DIR}/_build/ghc-stage1"
  echo "  Using stage1 compiler: ${GHC}"
}

# platform_pre_stage2() - Use default (no-op)
# platform_post_stage2() - Use default (no-op)

# ==============================================================================
# INSTALLATION
# ==============================================================================

platform_install_method() {
  INSTALL_METHOD="bindist"
}

platform_install_bindist() {
  echo "  Creating binary distribution..."

  # Create bindist
  local BINDIST_PATH=""
  create_bindist HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE2}" BINDIST_PATH

  echo "  Binary distribution: ${BINDIST_PATH}"

  # Configure bindist with BUILD machine tools
  # IMPORTANT: Do NOT pass --target! The bindist configure is for installation,
  # not for building. The installed compiler already knows its target.
  local BINDIST_CONFIG=(
    --prefix="${PREFIX}"
    --build="${ghc_host}"
    --host="${ghc_host}"
  )

  # Install bindist
  install_bindist "${BINDIST_PATH}" BINDIST_CONFIG "${conda_host}" "${target_arch}"
}

# platform_post_install() - Use default (no-op)
