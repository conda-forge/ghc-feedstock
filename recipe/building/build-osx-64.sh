#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# This is needed as in seems to interfere with configure scripts
unset build_alias
unset host_alias

# Update cabal package database
run_and_log "cabal-update" cabal v2-update --allow-newer --minimize-conflict-set

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
run_and_log "configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -L\$topdir/../../../../lib#' "${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(ld flags", "[^"]*)#$1 -L\$topdir/../../../../lib #' "${SRC_DIR}"/_build/stage0/lib/settings
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1  -Wl,-L\$topdir/../../../../lib#' "${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(ld flags", "[^"]*)#$1 -L\$topdir/../../../../lib#' "${SRC_DIR}"/_build/stage0/lib/settings

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quickest

export DYLD_LIBRARY_PATH="${PREFIX}/lib:${BUILD_PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
settings_file="${SRC_DIR}"/_build/stage1/lib/settings
iconv_aliases="-L${PREFIX}/lib -Wl,-alias,_libiconv,_iconv"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_open,_iconv_open"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_close,_iconv_close"
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=quickest

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=quickest --docs=none --progress-info=none
