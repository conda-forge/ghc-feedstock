#!/usr/bin/env bash
set -eu

_log_index=0
_debug=1

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  CC="${CC_FOR_BUILD}" \
  CXX="${CXX_FOR_BUILD}" \
  CPP="${CPP_FOR_BUILD:-${CPP}}" \
  LDFLAGS="${LDFLAGS//$PREFIX/$BUILD_PREFIX}" \
  run_and_log "bs-configure" bash configure --prefix="${SRC_DIR}"/binary
  run_and_log "bs-make-install" make install
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin"
  --host="x86_64-apple-darwin"
  --target="x86_64-apple-darwin13.4.0"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
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
_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all"  "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs

# Create bash completion
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Run post-install
run_and_log "recache" "${PREFIX}"/bin/ghc-pkg recache
