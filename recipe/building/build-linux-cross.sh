#!/usr/bin/env bash
# ============================================================
# GHC Build Script - Linux Cross-Compilation
# ============================================================
# Targets: aarch64, powerpc64le
# Simplified using build orchestrator
# ============================================================

set -eu

# Initialize logging index
_log_index=0

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

# ============================================================
# ARCHITECTURE CALCULATION
# ============================================================

# Save original conda aliases
original_build_alias="${build_alias}"
original_host_alias="${host_alias}"

# Extract architectures
conda_host="${original_build_alias}"      # e.g., x86_64-conda-linux-gnu (BUILD)
conda_target="${original_host_alias}"     # e.g., aarch64-conda-linux-gnu (TARGET)
host_arch="${original_build_alias%%-*}"   # e.g., x86_64 (BUILD)
target_arch="${original_host_alias%%-*}"  # e.g., aarch64 (TARGET)

# GHC triples
ghc_host="${host_arch}-unknown-linux-gnu"
ghc_target="${target_arch}-unknown-linux-gnu"

echo "=== Cross-Compilation Architecture ==="
echo "  BUILD:  ${conda_host} -> ${ghc_host}"
echo "  TARGET: ${conda_target} -> ${ghc_target}"
echo "======================================="

# Override autoconf variables for GHC configure
export build_alias="${ghc_host}"
export host_alias="${ghc_host}"

# ============================================================
# BOOTSTRAP ENVIRONMENT
# ============================================================

setup_cross_build_env "linux-64" "libc2.17_env" "sysroot_linux-64==2.17"

echo "  Bootstrap GHC: ${GHC}"
"${GHC}" --version

# ============================================================
# POWERPC64LE ABI V2 CONFIGURATION
# ============================================================

if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
  echo "=== PowerPC64LE detected: Configuring ABI v2 ==="

  export CFLAGS="${CFLAGS:-} -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"
  export CXXFLAGS="${CXXFLAGS:-} -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"

  echo "  Added ABI flags to CFLAGS/CXXFLAGS"
fi

# ============================================================
# CONFIGURE
# ============================================================

SYSTEM_CONFIG+=(
  --target="${ghc_target}"
)

declare -a CONFIGURE_ARGS
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

set_autoconf_toolchain_vars "${conda_target}" "false"

configure_ghc SYSTEM_CONFIG CONFIGURE_ARGS

# ============================================================
# POWERPC64LE: HADRIAN CONFIG PATCHING
# ============================================================

if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
  echo "=== Patching Hadrian config for PowerPC64LE ==="

  for config_file in "${SRC_DIR}"/hadrian/cfg/default.target "${SRC_DIR}"/hadrian/cfg/*.ghc-toolchain; do
    if [[ -f "${config_file}" ]]; then
      perl -pi -e 's/"-Qunused-arguments"/"-mabi=elfv2","-Dpowerpc64le_HOST_ARCH","-Dlinux_HOST_OS","-Qunused-arguments"/g' "${config_file}"
    fi
  done
fi

# ============================================================
# HADRIAN SYSTEM.CONFIG UPDATE
# ============================================================

update_hadrian_system_config "${conda_target}" "false"

# ============================================================
# BUILD HADRIAN (BUILD machine toolchain)
# ============================================================

# Stage 0 tools (BUILD machine)
export AR_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ar"
export CC_STAGE0="${CC_FOR_BUILD}"
export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

# Build machine flags
build_cflags="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include"
build_ldflags="-L${CROSS_ENV_PATH}/${conda_host}/lib -L${CROSS_ENV_PATH}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"

build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}" "${build_cflags}" "${build_ldflags}"

# Set up Hadrian command array
declare -a HADRIAN_BUILD=("${HADRIAN_BIN}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ============================================================
# BUILD FLAVOURS
# ============================================================

HADRIAN_FLAVOUR_STAGE1="quickest"
HADRIAN_FLAVOUR_STAGE2="release"

echo "=== Build Configuration ==="
echo "  Stage 1: ${HADRIAN_FLAVOUR_STAGE1} (cross-compiler)"
echo "  Stage 2: ${HADRIAN_FLAVOUR_STAGE2} (target binaries)"
echo "=========================="

# ============================================================
# STAGE 1: CROSS-COMPILER
# ============================================================

echo "=== Building Stage 1 Cross-Compiler ==="

# Disable copy optimization (force cross-compiler build)
perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' \
  "${SRC_DIR}"/hadrian/src/Rules/Program.hs

# Build stage1 compiler executable first
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
run_and_log "stage1_exe" "${HADRIAN_BUILD[@]}" stage1:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR_STAGE1}"

# Build stage1 tools (using orchestrator)
build_stage1_tools HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE1}"

# Patch settings file after tools
settings_file="${SRC_DIR}/_build/stage0/lib/settings"
update_linux_link_flags "${settings_file}"

# Build stage1 libraries (using orchestrator)
build_stage1_libs HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE1}" "${settings_file}"

# ============================================================
# POWERPC64LE: GHCPLATFORM.H PATCHING
# ============================================================

if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
  echo "=== Patching ghcplatform.h for PowerPC64LE ==="

  ghcplatform_stage1="${SRC_DIR}/_build/stage1/rts/build/include/ghcplatform.h"

  if [[ -f "${ghcplatform_stage1}" ]] && ! grep -q "^#define powerpc64le_HOST_ARCH" "${ghcplatform_stage1}"; then
    perl -pi -e 's/(#define powerpc64_HOST_ARCH\s+1)/$1\n#define powerpc64le_HOST_ARCH  1/' "${ghcplatform_stage1}"
    echo "  Successfully patched: ${ghcplatform_stage1}"
  fi
fi

# ============================================================
# STAGE 2: TARGET BINARIES
# ============================================================

echo "=== Building Stage 2 Target Binaries ==="

export GHC="${SRC_DIR}/_build/ghc-stage1"

# Build stage2 using orchestrator (libraries then executable)
build_stage2 HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE2}"

# ============================================================
# BINARY DISTRIBUTION
# ============================================================

BINDIST_PATH=""
create_bindist HADRIAN_BUILD "${HADRIAN_FLAVOUR_STAGE2}" BINDIST_PATH

echo "  Binary distribution: ${BINDIST_PATH}"

# ============================================================
# INSTALL FROM BINDIST
# ============================================================

# Extract bindist
bindist_dir="${SRC_DIR}/ghc-bindist"
mkdir -p "${bindist_dir}"
tar -xf "${BINDIST_PATH}" -C "${bindist_dir}" --strip-components=1

# Configure bindist with BUILD machine tools
BINDIST_CONFIG=(
  --prefix="${PREFIX}"
  --build="${ghc_host}"
  --host="${ghc_host}"
  --target="${ghc_target}"
)

install_bindist "${BINDIST_PATH}" BINDIST_CONFIG "${conda_host}" "${target_arch}"

echo "=== Build completed successfully ==="
