#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export CABAL="${BUILD_PREFIX}/bin/cabal"
run_and_log "cabal-update" "${CABAL}" v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-conda-linux-gnu"
  --host="x86_64-conda-linux-gnu"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  --enable-ignore-build-platform-mismatch=yes
  --enable-shared
  --disable-static
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

CFLAGS="${CFLAGS} -Wl,--allow-multiple-definition" \
LDFLAGS="${LDFLAGS} -Wl,--no-as-needed -Wl,--allow-multiple-definition" \
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -Wl,--allow-multiple-definition"#g' "${BUILD_PREFIX}"/ghc-bootstrap/lib/ghc-*/settings
perl -i -pe 's#("ld flags", ")([^"]*)"#\1\2 -Wl,--allow-multiple-definition"#g' "${BUILD_PREFIX}"/ghc-bootstrap/lib/ghc-*/settings
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest

export LD_PRELOAD="${PREFIX}/lib/libiconv.so.2 ${PREFIX}/lib/libgmp.so.10 ${PREFIX}/lib/libffi.so.8 ${PREFIX}/lib/libtinfow.so.6 ${PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none

# Build cross-compiler for aarch64 - desabled
# Disable x-compiler: "${RECIPE_DIR}"/building/cross-build-linux-aarch64.sh
