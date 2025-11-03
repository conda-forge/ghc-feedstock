#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

conda_host="${build_alias}"
conda_target="${host_alias}"

host_arch="${conda_host%%-*}"
target_arch="${conda_target%%-*}"

ghc_host="${conda_host/darwin*/darwin}"
ghc_target="${conda_target/darwin*/darwin}"

export build_alias="${conda_host}"
export host_alias="${conda_host}"
export target_alias="${conda_target}"
export host_platform="${build_platform}"

# Create environment and get library paths
echo "Creating environment for cross-compilation libraries..."
conda create -y \
    -n osx64_env \
    --platform osx-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap==9.6.7

osx_64_env=$(conda info --envs | grep osx64_env | awk '{print $2}')
ghc_path="${osx_64_env}"/ghc-bootstrap/bin

export GHC="${ghc_path}"/ghc

"${ghc_path}"/ghc-pkg recache

export CABAL="${osx_64_env}"/bin/cabal
export CABAL_DIR="${SRC_DIR}"/.cabal

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# Configure and build GHC
export AR_STAGE0=$(find "${BUILD_PREFIX}" -name llvm-ar | head -1)

# Export STAGE0 tools as environment variables (needed by GHC configure and sub-packages)
# These ensure stage0 (bootstrap) binaries are built for the BUILD platform (x86_64)
export CC_STAGE0="${CC_FOR_BUILD}"
export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"
export AS_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-as"

SYSTEM_CONFIG=(
  --target="${target_alias}"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  --with-system-libffi=yes
  --with-curses-includes="${PREFIX}"/include
  --with-curses-libraries="${PREFIX}"/lib
  --with-ffi-includes="${PREFIX}"/include
  --with-ffi-libraries="${PREFIX}"/lib
  --with-gmp-includes="${PREFIX}"/include
  --with-gmp-libraries="${PREFIX}"/lib
  --with-iconv-includes="${PREFIX}"/include
  --with-iconv-libraries="${PREFIX}"/lib

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

(
  run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }
)

# Fix default.host.target (defines host platform configuration)
perl -pi -e "s#--target=(${conda_target}|${target_alias}|arm64[^ \"]*)##g" "${SRC_DIR}/hadrian/cfg/default.host.target"

# CRITICAL: Fix architecture defines for cross-compilation
# During cross-compile from x86_64 to ARM64, configure sets x86_64_HOST_ARCH
# but we need arm64/aarch64 defines for the target architecture
find "${SRC_DIR}" -name "*.buildinfo" -o -name "setup-config" | while read -r file; do
  if [ -f "$file" ]; then
    perl -pi -e 's/-Dx86_64_HOST_ARCH=1/-Daarch64_HOST_ARCH=1/g' "$file"
  fi
done

# Fix host configuration to use x86_64, target cross
(
  settings_file="${SRC_DIR}"/hadrian/cfg/system.config
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
  perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"

  cat "${settings_file}"
)

# Bug in ghc-bootstrap for libiconv2
(
  bootstrap_settings="${osx_64_env}"/ghc-bootstrap/lib/ghc-9.6.7/lib/settings
  perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${bootstrap_settings}"
  # CRITICAL: Add --target flag to force C compiler to target x86_64, not arm64
  perl -pi -e "s#(C compiler flags\", \")#\$1-v -fno-lto --target=${conda_host} #" "${bootstrap_settings}"
  perl -pi -e "s#(C\\+\\+ compiler flags\", \")#\$1-fno-lto --target=${conda_host} #" "${bootstrap_settings}"
  # Don't add -fuse-ld=lld during build (bootstrap compiler doesn't support it)
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto --target=${conda_host}#" "${bootstrap_settings}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR_STAGE0}#" "${bootstrap_settings}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1llvm-ranlib#" "${bootstrap_settings}"
  perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${conda_host}-\$2#" "${bootstrap_settings}"
  cat "${bootstrap_settings}"
)
# Build hadrian with cabal outside script
(
  pushd "${SRC_DIR}"/hadrian
    # export CABFLAGS=(--enable-shared --enable-executable-dynamic -j)
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
)

_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ---| Stage 1: Cross-compiler |---

# Disable copy for cross-compilation - force building the cross binary
# Change the cross-compile copy condition to never match
(
  export AR="${AR_STAGE0}"
  export AS="${BUILD_PREFIX}/bin/${conda_host}-as"
  export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"

  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ar" "${BUILD_PREFIX}"/bin/ar
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-as" "${BUILD_PREFIX}"/bin/as
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ld" "${BUILD_PREFIX}"/bin/ld
  
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs
  
  set +e
  run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --progress-info=none || true
  set -e
  
  echo ".";echo ".";echo ".";echo ".";
  rm -f "${SRC_DIR}"/_build/stageBoot/utils/hsc2hs/build/c/cbits/utils.o
  ls -l "${BUILD_PREFIX}/bin/${conda_host}-clang"
  ls -l "${BUILD_PREFIX}/bin/clang-19"
  ls -l "${BUILD_PREFIX}/bin/${conda_host}-ld"
  ls -l "${BUILD_PREFIX}/bin/ld"
  "${BUILD_PREFIX}/bin/${conda_host}-clang" -v
  "${BUILD_PREFIX}/bin/clang-19" -v
  echo "${CFLAGS}"
  echo "${CPPFLAGS}"
  echo "${CXXFLAGS}"
  "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV --flavour=quickest --progress-info=unicorn
  echo ".";echo ".";echo ".";echo ".";
  run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quickest --docs=none --progress-info=none
  run_and_log "stage1_hsc2hs"  "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quickest --docs=none --progress-info=none
)

"${SRC_DIR}"/_build/stage0/bin/arm64-apple-darwin20.0.0-ghc --version || { echo "Stage0 GHC failed to report version"; exit 1; }

# CRITICAL: Fix architecture defines in all generated config files before building libraries
# The time library and others will generate setup-config files with wrong HOST_ARCH
echo "Fixing architecture defines in build files..."
find "${SRC_DIR}/_build" -name "*.buildinfo" -o -name "setup-config" | while read -r file; do
  if [ -f "$file" ] && grep -q "x86_64_HOST_ARCH" "$file" 2>/dev/null; then
    perl -pi -e 's/-Dx86_64_HOST_ARCH=1/-Daarch64_HOST_ARCH=1/g' "$file"
    echo "Fixed architecture defines in: $file"
  fi
done

# 9.12+: export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
# export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release --docs=none --progress-info=none

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all" "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none || true

ls -l1 "${PREFIX}"/{bin,lib}/*

# Create links of <triplet>-xxx to xxx
pushd "${PREFIX}"/bin
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${conda_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${conda_target}-${bin}" "${bin}"
    fi
  done
popd

if [[ -d "${PREFIX}"/lib/${conda_target}-ghc-"${PKG_VERSION}" ]]; then
  # $PREFIX/lib/cross-conda-linux-gnu-ghc-9.12.2 -> $PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}"
fi
