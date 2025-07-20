#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-conda-linux-gnu"
  --host="x86_64-conda-linux-gnu"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --enable-ignore-build-platform-mismatch=yes
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
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

export LD_PRELOAD="${PREFIX}/lib/libiconv.so.2 ${PREFIX}/lib/libgmp.so.10 ${PREFIX}/lib/libffi.so.8 ${PREFIX}/lib/libtinfow.so.6 ${PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none
