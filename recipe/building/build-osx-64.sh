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

export CABFLAGS=(--enable-shared --disable-static --disable-library-vanilla --enable-executable-dynamic -j)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" random)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" hashable)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" primitive)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" directory)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" unordered-containers)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" extra)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" filepattern)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" directory)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" shake)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" random)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" QuickCheck)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" Cabal-syntax)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" Cabal)
(cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" hadrian)

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest
iconv_aliases="-L${PREFIX}/lib -Wl,-alias,_libiconv,_iconv"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_open,_iconv_open"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_close,_iconv_close"
settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{BUILD_REFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\$ENV{PREFIX}/lib -L\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"

export DYLD_INSERT_LIBRARIES=$(find "${PREFIX}" -name libtinfow.dylib)
export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
settings_file="${SRC_DIR}"/_build/stage1/lib/settings
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\$ENV{PREFIX}/lib -L\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none --progress-info=none
