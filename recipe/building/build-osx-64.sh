#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  run_and_log "bs-configure" bash configure --prefix="${SRC_DIR}"/binary
  run_and_log "bs-make-install" make install
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update --allow-newer --minimize-conflict-set

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --disable-numa
  --enable-ignore-build-platform-mismatch=yes
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
_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=no-sphinx-pdfs

pushd "${PREFIX}"/share/doc/x86_64-osx-ghc-"${PKG_VERSION}"-inplace
  for file in */LICENSE; do
    cp "${file///-}" "${SRC_DIR}"/license_files
  done
popd
