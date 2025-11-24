#!/usr/bin/env bash
# ============================================================
# GHC Build Script - macOS x86_64 → arm64 Cross-Compile
# ============================================================
# Note: Uses custom flow due to cross-compile complexity
# ============================================================

set -eu

# Initialize logging index
_log_index=0

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

# ============================================================
# CROSS-COMPILATION ENVIRONMENT
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
echo "=========================="

# ============================================================
# BOOTSTRAP ENVIRONMENT (osx-64)
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
export GHC="${ghc_path}"/ghc

# Recache and verify
"${ghc_path}"/ghc-pkg recache
"${GHC}" --version || { echo "ERROR: Bootstrap GHC failed"; exit 1; }

# ============================================================
# CABAL SETUP
# ============================================================

export CABAL="${osx_64_env}"/bin/cabal
export CABAL_DIR="${SRC_DIR}"/.cabal

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# ============================================================
# MACOS CROSS-COMPILATION SETUP
# ============================================================

setup_macos_cross_environment "${conda_host}" "${conda_target}"
fix_macos_bootstrap_settings "${osx_64_env}" "${conda_host}" "${AR_STAGE0}"

# ============================================================
# CONFIGURE
# ============================================================

SYSTEM_CONFIG+=(
  --build="${conda_host}"
  --host="${conda_host}"
  --target="${conda_target}"
)

declare -a CONFIGURE_ARGS
build_configure_args CONFIGURE_ARGS

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
# HADRIAN CONFIG PATCHING (macOS cross-compile specific)
# ============================================================

echo "=== Patching Hadrian config for cross-compilation ==="
perl -pi -e "s#--target=arm64-apple-darwin[^\"]*#--target=${conda_host}#g" "${SRC_DIR}/hadrian/cfg/default.host.target"

settings_file="${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"

# ============================================================
# ARCHITECTURE DEFINES FIX (PRE-BUILD)
# ============================================================

echo "=== Fixing architecture defines in source tree ==="
fix_cross_architecture_defines "x86_64" "aarch64"

# ============================================================
# HADRIAN BUILD
# ============================================================

declare -a HADRIAN_BUILD
build_hadrian_binary HADRIAN_BUILD "${CABAL}" "${CC_FOR_BUILD}" "${AR_STAGE0}"

# ============================================================
# BUILD CONFIGURATION
# ============================================================

HADRIAN_FLAVOUR="release"

# ============================================================
# STAGE 1: CROSS-COMPILER (custom flow)
# ============================================================
# Build stage1 exe + tools with BUILD toolchain
# ============================================================

echo "=== Building Stage 1 (Cross-Compiler) ==="

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

  # Disable copy for cross-compilation
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' \
    "${SRC_DIR}"/hadrian/src/Rules/Program.hs

  # Build stage1 exe + tools
  echo "  Building stage 1 compiler binary"
  run_and_log "stage1_ghc-bin" "${HADRIAN_BUILD[@]}" stage1:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR}" || true

  echo "  Building stage 1 tools"
  run_and_log "stage1_ghc-pkg" "${HADRIAN_BUILD[@]}" stage1:exe:ghc-pkg --flavour="${HADRIAN_FLAVOUR}"
  run_and_log "stage1_hsc2hs" "${HADRIAN_BUILD[@]}" stage1:exe:hsc2hs --flavour="${HADRIAN_FLAVOUR}"
)

# Verify stage0 GHC
ghc=$(find "${SRC_DIR}"/_build/stage0/bin -name "*ghc" -type f | head -1)
"${ghc}" --version || { echo "ERROR: Stage0 GHC failed"; exit 1; }

# ============================================================
# ARCHITECTURE DEFINES FIX (POST-STAGE1)
# ============================================================

echo "=== Fixing architecture defines in build tree ==="
find "${SRC_DIR}/_build" -name "*.buildinfo" -o -name "setup-config" | while read -r file; do
  if [ -f "$file" ] && grep -q "x86_64_HOST_ARCH" "$file" 2>/dev/null; then
    perl -pi -e 's/-Dx86_64_HOST_ARCH=1/-Daarch64_HOST_ARCH=1/g' "$file"
    echo "  Fixed: $file"
  fi
done

# ============================================================
# STAGE 1: LIBRARIES (TARGET architecture)
# ============================================================

echo "=== Building Stage 1 Libraries (arm64) ==="
# Build libraries in dependency order (race condition prevention)
run_and_log "stage1_ghc-prim" "${HADRIAN_BUILD[@]}" stage1:lib:ghc-prim --flavour="${HADRIAN_FLAVOUR}"
run_and_log "stage1_ghc-bignum" "${HADRIAN_BUILD[@]}" stage1:lib:ghc-bignum --flavour="${HADRIAN_FLAVOUR}"
run_and_log "stage1_ghc-experimental" "${HADRIAN_BUILD[@]}" stage1:lib:ghc-experimental --flavour="${HADRIAN_FLAVOUR}"
run_and_log "stage1_lib" "${HADRIAN_BUILD[@]}" stage1:lib:ghc --flavour="${HADRIAN_FLAVOUR}"

# ============================================================
# STAGE 2: EXECUTABLE (TARGET architecture)
# ============================================================

echo "=== Building Stage 2 Executable (arm64) ==="
run_and_log "stage2_exe" "${HADRIAN_BUILD[@]}" stage2:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR}" --freeze1

# ============================================================
# RACE CONDITION PREVENTION: Cabal-syntax
# ============================================================

echo "=== Building Cabal-syntax explicitly (prevents Parsec.dyn_hi race) ==="
run_and_log "stage1_cabal-syntax" "${HADRIAN_BUILD[@]}" stage1:lib:Cabal-syntax --flavour="${HADRIAN_FLAVOUR}"

# ============================================================
# BUILD ALL AND INSTALL
# ============================================================

echo "=== Building all components ==="
run_and_log "build_all" "${HADRIAN_BUILD[@]}" --flavour="${HADRIAN_FLAVOUR}" --freeze1 --freeze2

echo "=== Installing to ${PREFIX} ==="
run_and_log "install" "${HADRIAN_BUILD[@]}" install \
  --prefix="${PREFIX}" \
  --flavour="${HADRIAN_FLAVOUR}" \
  --freeze1 \
  --freeze2 \
  --docs=none || true

# ============================================================
# POST-INSTALL: SYMLINKS AND NORMALIZATION
# ============================================================

echo "=== Creating symlinks for cross-compiled binaries ==="
pushd "${PREFIX}"/bin
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${conda_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${conda_target}-${bin}" "${bin}"
      echo "  Created symlink: ${bin} → ${conda_target}-${bin}"
    fi
  done
popd

if [[ -d "${PREFIX}"/lib/${conda_target}-ghc-"${PKG_VERSION}" ]]; then
  echo "=== Normalizing library directory ==="
  mv "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}"
fi

echo "=== Build completed successfully ==="
