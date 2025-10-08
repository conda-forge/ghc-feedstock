#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

_build_alias=${build_alias}
_host_alias=${host_alias}
_ghc_host="x86_64-conda-linux-gnu"

export build_alias="${_ghc_host}"
export host_alias="${_ghc_host}"
export BUILD=${build_alias}
export HOST=${host_alias}

# Create aarch64 environment and get library paths
echo "Creating aarch64 environment for cross-compilation libraries..."
conda create -y \
    -n libc2.17_env \
    --platform linux-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap==9.6.7 \
    sysroot_linux-64==2.17

$(conda info --envs | grep libc2.17_env | awk '{print $2}')/ghc-bootstrap/bin/ghc-pkg recache
export GHC=$(conda info --envs | grep libc2.17_env | awk '{print $2}')/ghc-bootstrap/bin/ghc
  export CONDA_BUILD_SYSROOT=$(conda info --envs | grep libc2.17_env | awk '{print $2}')/x86_64-conda-linux-gnu/sysroot
  export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT}"
  export CXXFLAGS="--sysroot=${CONDA_BUILD_SYSROOT}"
  export LDFLAGS="--sysroot=${CONDA_BUILD_SYSROOT}"

export CABAL=$(conda info --envs | grep libc2.17_env | awk '{print $2}')/bin/cabal
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-unknown-linux-gnu"
  --host="x86_64-unknown-linux-gnu"
  --target="aarch64-unknown-linux-gnu"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  --disable-numa
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
)

# env
# find ${BUILD_PREFIX} ${PREFIX} -name "libffi.*"

MergeObjsCmd=aarch64-conda-linux-gnu-ld.gold \
AR=aarch64-conda-linux-gnu-ar \
AS=aarch64-conda-linux-gnu-as \
CC=aarch64-conda-linux-gnu-clang \
CXX=aarch64-conda-linux-gnu-clang++ \
NM=aarch64-conda-linux-gnu-nm \
RANLIB=aarch64-conda-linux-gnu-ranlib \
LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}" \
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# Fix host configuration to use x86_64, target aarch64
settings_file="${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
perl -pi -e 's#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)$#$1aarch64-conda-linux-gnu-$2#' "${settings_file}"
perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -v -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -v -L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release --docs=none --progress-info=none

perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -v -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -v -L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

# GHC build ghc-pkg with '-fno-use-rpaths' but it requires libiconv.so.2
# _build/stage1/bin/ghc-pkg: error while loading shared libraries: libiconv.so.2
export LIBRARY_PATH="${PREFIX}/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${BUILD_PREFIX}/lib/libiconv.so.2 ${BUILD_PREFIX}/lib/libgmp.so.10 ${BUILD_PREFIX}/lib/libffi.so.8 ${BUILD_PREFIX}/lib/libtinfow.so.6 ${BUILD_PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"
run_and_log "bindist" "${_hadrian_build[@]}" binary-dist --prefix="${PREFIX}" --flavour=release --docs=none --progress-info=none

# Now manually install from the bindist with correct configure arguments
BINDIST_DIR=$(find "${SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-aarch64-*-linux-gnu" -type d | head -1)
if [[ -n "${BINDIST_DIR}" ]]; then
  pushd "${BINDIST_DIR}"
 
  # Configure the binary distribution with proper cross-compilation settings
  MergeObjsCmd=aarch64-conda-linux-gnu-ld.gold \
  AR=aarch64-conda-linux-gnu-ar \
  AS=aarch64-conda-linux-gnu-as \
  CC=aarch64-conda-linux-gnu-clang \
  CXX=aarch64-conda-linux-gnu-clang++ \
  NM=aarch64-conda-linux-gnu-nm \
  RANLIB=aarch64-conda-linux-gnu-ranlib \
  LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}" \
  ./configure --prefix="${PREFIX}" --build=x86_64-unknown-linux-gnu --host=x86_64-unknown-linux-gnu --target=aarch64-unknown-linux-gnu
 
  # Install
  make install
 
  popd
else
  echo "Error: Could not find binary distribution directory"
  exit 1
fi

# Create links of aarch64-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  for bin in aarch64-conda-linux-gnu-*; do
    ln -s "${bin}" "${bin#aarch64-conda-linux-gnu-}"
  done
popd

if [[ -d "${PREFIX}"/lib/aarch64-conda-linux-gnu-ghc-"${PKG_VERSION}" ]]; then
  # $PREFIX/lib/aarch64-conda-linux-gnu-ghc-9.12.2 -> $PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/aarch64-conda-linux-gnu-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/aarch64-conda-linux-gnu-ghc-"${PKG_VERSION}"
fi
