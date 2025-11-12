#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

conda_host="${build_alias}"
conda_target="${host_alias}"

# Try using the conda environment vars again
# host_arch="${conda_host%%-*}"
# target_arch="${conda_target%%-*}"

# ghc_host="${conda_host/darwin*/darwin}"
# ghc_target="${conda_target/darwin*/darwin}"

# export build_alias="${conda_host}"
# export host_alias="${conda_host}"

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

SYSTEM_CONFIG=(
  --build="${build_alias}"
  --host="${build_alias}"
  --target="${host_alias}"
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

# Fix host configuration to use x86_64, target cross
(
  settings_file="${SRC_DIR}"/hadrian/cfg/system.config
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
  perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|objdump|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"
  perl -pi -e "s#(system-ar\s*?=\s).*#\$1${AR_STAGE0}#" "${settings_file}"
  perl -pi -e "s#(conf-cc-args-stage0\s*?=\s).*#\$1--target=${conda_host}#" "${settings_file}"
  perl -pi -e "s#(conf-gcc-linker-args-stage0\s*?=\s).*#\$1--target=${conda_host}#" "${settings_file}"
  perl -pi -e "s#(conf-gcc-linker-args-stage[12]\s*?=\s)#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12]\s*?=\s)#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-c-compiler-link-flags\s*?=\s)#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-ar-command\s*?=\s).*#\$1${conda_target}-ar#" "${settings_file}"
  perl -pi -e "s#(settings-ld-flags\s*?=\s)#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"

  perl -pi -e "s#${conda_target}-(objdump)#\$1#" "${settings_file}"

  cat "${settings_file}"
)

# Bug in ghc-bootstrap for libiconv2
(
  bootstrap_settings="${osx_64_env}"/ghc-bootstrap/lib/ghc-9.6.7/lib/settings
  perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${bootstrap_settings}"
  perl -pi -e "s#(C compiler flags\", \")#\$1-v -fno-lto #" "${bootstrap_settings}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${bootstrap_settings}"
  # Don't add -fuse-ld=lld during build (bootstrap compiler doesn't support it)
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto#" "${bootstrap_settings}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR_STAGE0}#" "${bootstrap_settings}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1llvm-ranlib#" "${bootstrap_settings}"
  perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${conda_host}-\$2#" "${bootstrap_settings}"
  cat "${bootstrap_settings}"
)
# Build hadrian with cabal outside script
(
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
  
  run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release+no_profiled_libs --progress-info=none || true
  run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=release+no_profiled_libs --docs=none --progress-info=none
  run_and_log "stage1_hsc2hs"  "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=release+no_profiled_libs --docs=none --progress-info=none
)

ghc=$(find "${SRC_DIR}"/_build/stage0/bin -name "*ghc" -type f | head -1)
echo "${ghc}" && "${ghc}" --version || { echo "Stage0 GHC failed to report version"; exit 1; }

# 9.12+: export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
# export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
# Build core dependencies FIRST to avoid race conditions with parallel builds
run_and_log "stage1_ghc-prim" "${_hadrian_build[@]}" stage1:lib:ghc-prim --flavour=release+no_profiled_libs
run_and_log "stage1_ghc-bignum" "${_hadrian_build[@]}" stage1:lib:ghc-bignum --flavour=release+no_profiled_libs
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release+no_profiled_libs --docs=none --progress-info=none

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release+no_profiled_libs --freeze1 --docs=none --progress-info=none
run_and_log "bindist"    "${_hadrian_build[@]}" binary-dist --prefix="${PREFIX}" --flavour=release+no_profiled_libs --freeze1 --freeze2 --docs=none --progress-info=none

ls -l1 "${PREFIX}"/{bin,lib}/*

# Now manually install from the bindist with correct configure arguments
bindist_dir=$(find "${SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)
if [[ -n "${bindist_dir}" ]]; then
  pushd "${bindist_dir}"
    # Configure the binary distribution with proper cross-compilation settings
    ac_cv_path_CC="${BUILD_PREFIX}"/bin/"${conda_host}"-clang \
    ac_cv_path_CXX="${BUILD_PREFIX}"/bin/"${conda_host}"-clang++ \
    ./configure --prefix="${PREFIX}" --target="${ghc_target}" || { cat config.log; exit 1; }
 
    # Install (update_package_db fails due to cross ghc-pkg)
    run_and_log "make_install" make install_bin install_lib install_man
  popd
else
  echo "Error: Could not find binary distribution directory"
  exit 1
fi

# Correct CC/CXX
settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
if [[ -f "${settings_file}" ]]; then
  perl -pi -e "s#${host_arch}(-[^ \"]*)#${target_arch}\$1#g" "${settings_file}"
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|opt)\"#\"${conda_target}-\$1\"#" "${settings_file}"
  cat "${settings_file}"
else
  echo "Error: Could not find settins file"
  exit 1
fi

# Create links of cross-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${ghc_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${ghc_target}-${bin}" "${bin}"
    fi
  done
popd

if [[ -d "${PREFIX}"/lib/${ghc_target}-ghc-"${PKG_VERSION}" ]]; then
  # $PREFIX/lib/cross-conda-linux-gnu-ghc-9.12.2 -> $PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}"
fi
