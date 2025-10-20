#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-unknown-linux"
  --host="x86_64-unknown-linux"
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
)
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

export CABFLAGS=(--enable-shared --enable-executable-dynamic -j)
for pkg in hadrian; do
  (cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" "${pkg}")
done

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release

export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -Wl,-L$ENV{BUILD_PREFIX}/lib -Wl,-L$ENV{PREFIX}/lib -Wl,-rpath,$ENV{BUILD_PREFIX}/lib -Wl,-rpath,$ENV{PREFIX}/lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -L$ENV{BUILD_PREFIX}/lib -L$ENV{PREFIX}/lib -rpath $ENV{PREFIX}/lib -rpath $ENV{BUILD_PREFIX}/lib#' "${settings_file}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release

perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -Wl,-L$ENV{BUILD_PREFIX}/lib -Wl,-L$ENV{PREFIX}/lib -Wl,-rpath,$ENV{BUILD_PREFIX}/lib -Wl,-rpath,$ENV{PREFIX}/lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -L$ENV{BUILD_PREFIX}/lib -L$ENV{PREFIX}/lib -rpath $ENV{PREFIX}/lib -rpath $ENV{BUILD_PREFIX}/lib#' "${settings_file}"

# export LD_PRELOAD="${PREFIX}/lib/libiconv.so.2 ${PREFIX}/lib/libgmp.so.10 ${PREFIX}/lib/libffi.so.8 ${PREFIX}/lib/libtinfow.so.6 ${PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1

settings_file="${SRC_DIR}"/_build/stage1/lib/settings
perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -Wl,-L$ENV{BUILD_PREFIX}/lib -Wl,-L$ENV{PREFIX}/lib -Wl,-rpath,$ENV{BUILD_PREFIX}/lib -Wl,-rpath,$ENV{PREFIX}/lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -L$ENV{BUILD_PREFIX}/lib -L$ENV{PREFIX}/lib -rpath $ENV{PREFIX}/lib -rpath $ENV{BUILD_PREFIX}/lib#' "${settings_file}"

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze1
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --freeze1 --freeze2 --flavour=release --docs=none

installed_settings="${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings
if [[ -f "${installed_settings}" ]]; then
  echo "Fixing installed settings file with RPATH..."
  perl -pi -e "s#(-Wl,-L${BUILD_PREFIX}/lib|-Wl,-L${PREFIX}/lib|-Wl,-rpath,${BUILD_PREFIX}/lib|-Wl,-rpath,${PREFIX}/lib)##g" "${settings_file}"
  perl -pi -e "s#(-L${BUILD_PREFIX}/lib|-L${PREFIX}/lib|-rpath ${PREFIX}/lib|-rpath ${BUILD_PREFIX}/lib)##g" "${settings_file}"
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-rpath,\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${installed_settings}"
  perl -pi -e "s#(ld flags\", \")#\$1-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -rpath \\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${installed_settings}"
  cat "${settings_file}"
fi

