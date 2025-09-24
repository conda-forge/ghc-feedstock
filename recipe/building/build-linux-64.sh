#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export CABAL="${BUILD_PREFIX}/bin/cabal"

# Update cabal package database
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
settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

# $topdir expansion will not work for _build/bindist/... binaries, use LD_PRELOAD hack
export LD_LIBRARY_PATH="${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${PREFIX}/lib/libiconv.so.2 ${PREFIX}/lib/libgmp.so.10 ${PREFIX}/lib/libffi.so.8 ${PREFIX}/lib/libtinfow.so.6 ${PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"
settings_file="${SRC_DIR}"/_build/stage1/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none
