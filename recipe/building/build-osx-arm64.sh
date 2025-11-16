#!/usr/bin/env bash
# ============================================================
# STANDARDIZED GHC BUILD SCRIPT - macOS x86_64 → arm64 Cross-Compile
# ============================================================
# Version: 1.0
# GHC Version: 9.10.2
# Last updated: 2025-11-13
#
# DESIGN PRINCIPLES:
# 1. Use lib module functions for consistency
# 2. Explicit Hadrian binary (prevents implicit rebuilds)
# 3. Race condition prevention for parallel builds
# 4. macOS cross-compile specifics (darwin vs osx, architecture defines)
# 5. Two-stage build: stage1 on BUILD, stage2 cross-compiled
# 6. Comprehensive documentation
# ============================================================

set -eu

# Add error trap to show exactly where failures occur
trap 'echo "ERROR: build-osx-arm64.sh failed at line $LINENO with exit code $?" >&2; exit 1' ERR

# Initialize logging index
_log_index=0

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

# ============================================================
# CROSS-COMPILATION ENVIRONMENT VARIABLES
# ============================================================
# BUILD machine: x86_64-apple-darwin (where we compile)
# TARGET machine: arm64-apple-darwin (what we compile for)
# ============================================================

conda_host="${build_alias}"
conda_target="${host_alias}"

unset host_alias
unset HOST

export target_alias="${conda_target}"
export host_platform="${build_platform}"

echo "=== Cross-Compilation Configuration ==="
echo "  BUILD (conda_host): ${conda_host}"
echo "  TARGET (conda_target): ${conda_target}"
echo "  host_platform: ${host_platform}"
echo "=========================="

# ============================================================
# BOOTSTRAP ENVIRONMENT SETUP (BUILD MACHINE)
# ============================================================
# Create osx-64 environment with bootstrap GHC and cabal
# This provides x86_64 tools needed to build the cross-compiler
# ============================================================

echo "=== Creating bootstrap environment (osx-64) ==="
conda create -y \
    -n osx64_env \
    --platform osx-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap==9.6.7

osx_64_env=$(conda info --envs | grep osx64_env | awk '{print $2}')
ghc_path="${osx_64_env}"/ghc-bootstrap/bin

echo "  Bootstrap environment: ${osx_64_env}"
echo "  Bootstrap GHC: ${ghc_path}/ghc"

export GHC="${ghc_path}"/ghc

# Recache package database
"${ghc_path}"/ghc-pkg recache

# Verify bootstrap GHC works
"${GHC}" --version || { echo "ERROR: Bootstrap GHC failed"; exit 1; }

# ============================================================
# CABAL ENVIRONMENT SETUP
# ============================================================

export CABAL="${osx_64_env}"/bin/cabal
export CABAL_DIR="${SRC_DIR}"/.cabal

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# ============================================================
# MACOS CROSS-COMPILATION SETUP
# ============================================================
# Configure stage0 tools and bootstrap settings for cross-compile
# ============================================================

# Use lib module function for macOS cross setup
setup_macos_cross_environment "${conda_host}" "${conda_target}"

# Fix bootstrap settings (ghc-bootstrap package has system references)
fix_macos_bootstrap_settings "${osx_64_env}" "${conda_host}" "${AR_STAGE0}"

# ============================================================
# GHC CONFIGURE (CROSS-COMPILE)
# ============================================================

SYSTEM_CONFIG=(
  --build="${conda_host}"
  --host="${conda_host}"
  --target="${conda_target}"
  --prefix="${PREFIX}"
)

# Build configure arguments using lib function (Bash 3.2 compatible)
declare -a CONFIGURE_ARGS
if type -t mapfile >/dev/null 2>&1; then
  mapfile -t CONFIGURE_ARGS < <(build_configure_args)
else
  while IFS= read -r arg; do
    CONFIGURE_ARGS+=("$arg")
  done < <(build_configure_args)
fi

if [[ ${#CONFIGURE_ARGS[@]} -eq 0 ]]; then
  echo "ERROR: build_configure_args returned no arguments"
  exit 1
fi

# Add cross-compile specific autoconf variables
CONFIGURE_ARGS+=(
  ac_cv_lib_ffi_ffi_call=yes
  ac_cv_path_AR="${BUILD_PREFIX}"/bin/"${conda_target}"-ar
  ac_cv_path_AS="${BUILD_PREFIX}"/bin/"${conda_target}"-as
  ac_cv_path_CC="${BUILD_PREFIX}"/bin/"${conda_target}"-clang
  ac_cv_path_CXX="${BUILD_PREFIX}"/bin/"${conda_target}"-clang++
  ac_cv_path_LD="${BUILD_PREFIX}"/bin/"${conda_target}"-ld
  ac_cv_path_NM="${BUILD_PREFIX}"/bin/"${conda_target}"-nm
  ac_cv_path_RANLIB="${BUILD_PREFIX}"/bin/"${conda_target}"-ranlib
  ac_cv_path_LLC="${BUILD_PREFIX}"/bin/"${conda_target}"-llc
  ac_cv_path_OPT="${BUILD_PREFIX}"/bin/"${conda_target}"-opt
  CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CFLAGS:-}"
  CPPFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CPPFLAGS:-}"
  CXXFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CXXFLAGS:-}"
  LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
)

run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }

# ============================================================
# HADRIAN CONFIG PATCHING (CROSS-COMPILE)
# ============================================================

# Fix default.host.target (host runs on BUILD machine, not TARGET)
echo "=== Patching Hadrian config for cross-compilation ==="
perl -pi -e "s#--target=arm64-apple-darwin[^\"]*#--target=${conda_host}#g" "${SRC_DIR}/hadrian/cfg/default.host.target"

# Fix host configuration to use BUILD toolchain, target uses TARGET toolchain
settings_file="${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"

echo "=== Hadrian system.config ==="
cat "${settings_file}"

# ============================================================
# ARCHITECTURE DEFINES FIX (PRE-BUILD)
# ============================================================
# CRITICAL: Fix x86_64_HOST_ARCH → aarch64_HOST_ARCH before building
# Configure sets wrong architecture for cross-compile target
# ============================================================

echo "=== Fixing architecture defines in source tree ==="
fix_cross_architecture_defines "x86_64" "aarch64"

# ============================================================
# HADRIAN BUILD (EXPLICIT BINARY PATTERN)
# ============================================================
# Build Hadrian with cabal and use explicit binary path
# This prevents implicit rebuilds during stage transitions
# ============================================================

echo "=== Building Hadrian with cabal ==="
pushd "${SRC_DIR}"/hadrian
  "${CABAL}" v2-build \
    --with-gcc="${CC_FOR_BUILD}" \
    --with-ar="${AR_STAGE0}" \
    -j \
    hadrian \
    2>&1 | tee "${SRC_DIR}"/cabal-verbose.log
  _cabal_exit_code=${PIPESTATUS[0]}

  if [[ $_cabal_exit_code -ne 0 ]]; then
    echo "=== Cabal build FAILED with exit code ${_cabal_exit_code} ==="
    exit 1
  else
    echo "=== Cabal build SUCCEEDED ==="
  fi
popd

# Find the built hadrian binary (BSD-compatible: -perm /111 works on both BSD and GNU)
_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f -perm +111 | head -1)

if [[ -z "${_hadrian_bin}" ]]; then
  echo "ERROR: Could not find hadrian binary after build"
  echo "Expected location: ${SRC_DIR}/hadrian/dist-newstyle/build/*/ghc-*/hadrian-*/*/build/hadrian/hadrian"
  exit 1
fi

echo "Found Hadrian binary: ${_hadrian_bin}"

# Use explicit binary with --directory flag
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ============================================================
# BUILD CONFIGURATION
# ============================================================

# Set Hadrian flavour (consistent across all stages)
HADRIAN_FLAVOUR="release"

echo "=== Build Configuration ==="
echo "  GHC Version: ${PKG_VERSION}"
echo "  Hadrian Flavour: ${HADRIAN_FLAVOUR}"
echo "  Hadrian Binary: ${_hadrian_bin}"
echo "  CPU Count: ${CPU_COUNT}"
echo "=========================="

# ============================================================
# STAGE 1: CROSS-COMPILER (BUILD MACHINE → TARGET MACHINE)
# ============================================================
# Build stage 1 compiler that runs on BUILD and produces TARGET code
# ============================================================

echo "=== Building Stage 1 (Cross-Compiler) ==="

# Set BUILD machine toolchain for stage1 compilation
(
  export AR="${AR_STAGE0}"
  export AS="${BUILD_PREFIX}/bin/${conda_host}-as"
  export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"

  # Create symlinks for stage1 build
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ar" "${BUILD_PREFIX}"/bin/ar
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-as" "${BUILD_PREFIX}"/bin/as
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ld" "${BUILD_PREFIX}"/bin/ld

  # CRITICAL: Disable copy for cross-compilation
  # Force building the cross binary instead of copying
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs

  # ============================================================
  # RACE CONDITION PREVENTION (STAGE 1)
  # Build explicitly to prevent Hadrian parallel build races
  # ============================================================
  echo "  Building stage 1 compiler binary"
  run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin \
    --flavour="${HADRIAN_FLAVOUR}" \
    --progress-info=none || true

  echo "  Building stage 1 tools (race condition prevention)"
  run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg \
    --flavour="${HADRIAN_FLAVOUR}" \
    --docs=none \
    --progress-info=none

  run_and_log "stage1_hsc2hs" "${_hadrian_build[@]}" stage1:exe:hsc2hs \
    --flavour="${HADRIAN_FLAVOUR}" \
    --docs=none \
    --progress-info=none
)

# Verify stage0 GHC works
ghc=$(find "${SRC_DIR}"/_build/stage0/bin -name "*ghc" -type f | head -1)
echo "=== Stage0 GHC verification ==="
echo "  GHC binary: ${ghc}"
"${ghc}" --version || { echo "ERROR: Stage0 GHC failed to report version"; exit 1; }

# ============================================================
# ARCHITECTURE DEFINES FIX (POST-STAGE1)
# ============================================================
# Fix any buildinfo files generated during stage1 build
# ============================================================

echo "=== Fixing architecture defines in build tree ==="
find "${SRC_DIR}/_build" -name "*.buildinfo" -o -name "setup-config" | while read -r file; do
  if [ -f "$file" ] && grep -q "x86_64_HOST_ARCH" "$file" 2>/dev/null; then
    perl -pi -e 's/-Dx86_64_HOST_ARCH=1/-Daarch64_HOST_ARCH=1/g' "$file"
    echo "  Fixed: $file"
  fi
done

# ============================================================
# STAGE 1: LIBRARIES (TARGET ARCHITECTURE)
# ============================================================
# Build stage 1 libraries with race condition prevention
# These libraries are for the TARGET architecture (arm64)
# ============================================================

echo "=== Building Stage 1 Libraries (arm64) ==="

# ============================================================
# RACE CONDITION PREVENTION (STAGE 1)
# Build libraries explicitly in correct order
# ============================================================
echo "  Building libraries explicitly (race condition prevention)"
run_and_log "stage1_ghc-prim" "${_hadrian_build[@]}" stage1:lib:ghc-prim \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none

run_and_log "stage1_ghc-bignum" "${_hadrian_build[@]}" stage1:lib:ghc-bignum \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc \
  --flavour="${HADRIAN_FLAVOUR}" \
  --docs=none \
  --progress-info=none
# ============================================================

# ============================================================
# STAGE 2: EXECUTABLE (TARGET ARCHITECTURE)
# ============================================================
# Build stage 2 compiler binary for TARGET (arm64)
# ============================================================

echo "=== Building Stage 2 Executable (arm64) ==="

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --docs=none \
  --progress-info=none

# ============================================================
# FINAL BUILD AND INSTALL
# ============================================================
# Build all remaining components and install
# ============================================================

echo "=== Building all components ==="
run_and_log "build_all" "${_hadrian_build[@]}" \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --freeze2 \
  --docs=no-sphinx-pdfs \
  --progress-info=none

echo "=== Installing to ${PREFIX} ==="
run_and_log "install" "${_hadrian_build[@]}" install \
  --prefix="${PREFIX}" \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --freeze2 \
  --docs=none \
  --progress-info=none || true

# ============================================================
# POST-INSTALL: SYMLINK CREATION
# ============================================================
# Create <triplet>-xxx → xxx symlinks for cross-compiled binaries
# ============================================================

echo "=== Creating symlinks for cross-compiled binaries ==="
ls -l1 "${PREFIX}"/{bin,lib}/*

pushd "${PREFIX}"/bin
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${conda_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${conda_target}-${bin}" "${bin}"
      echo "  Created symlink: ${bin} → ${conda_target}-${bin}"
    fi
  done
popd

# ============================================================
# POST-INSTALL: LIBRARY DIRECTORY NORMALIZATION
# ============================================================
# Move <triplet>-ghc-<version> → ghc-<version>
# ============================================================

if [[ -d "${PREFIX}"/lib/${conda_target}-ghc-"${PKG_VERSION}" ]]; then
  echo "=== Normalizing library directory ==="
  mv "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}"
  echo "  Moved: ${conda_target}-ghc-${PKG_VERSION} → ghc-${PKG_VERSION}"
  echo "  Created symlink: ${conda_target}-ghc-${PKG_VERSION} → ghc-${PKG_VERSION}"
fi

echo "=== Build completed successfully ==="
