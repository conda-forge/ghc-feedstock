#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

# This is needed as it seems to interfere with configure scripts
unset build_alias
unset host_alias

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
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
)

export ac_cv_path_ac_pt_CC=""
export ac_cv_path_ac_pt_CXX=""
export ac_cv_prog_AR="${AR}"
export ac_cv_prog_CC="${CC}"
export ac_cv_prog_CXX="${CXX}"
export ac_cv_prog_LD="${LD}"
export ac_cv_prog_RANLIB="${RANLIB}"
export ac_cv_path_AR="${AR}"
export ac_cv_path_CC="${CC}"
export ac_cv_path_CXX="${CXX}"
export ac_cv_path_LD="${LD}"
export ac_cv_path_RANLIB="${RANLIB}"
export DEVELOPER_DIR=""

settings_file=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -n 1)
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{BUILD_PREFIX}/lib -Wl,-L$ENV{PREFIX}/lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{BUILD_PREFIX}/lib -L$ENV{PREFIX}/lib#' "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

run_and_log "configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

export CABFLAGS=(--enable-shared --enable-executable-dynamic -j)
for pkg in hadrian; do
  (cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" "${pkg}")
done

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release

export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${DYLD_LIBRARY_PATH:+:}${DYLD_LIBRARY_PATH:-}"

iconv_aliases="-Wl,-alias,_libiconv,_iconv"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_open,_iconv_open"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_close,_iconv_close"
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
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-rpath,\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${installed_settings}"
  perl -pi -e "s#(ld flags\", \")#\$1-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -rpath \\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${installed_settings}"
fi

