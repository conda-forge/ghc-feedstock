#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PYTHON=python
export MSYSTEM=MINGW64
export MSYS2_ARG_CONV_EXCL="*"
export PATH="${SRC_DIR}"/bootstrap-ghc/bin:"${SRC_DIR}"/bootstrap-cabal${PATH:+:}${PATH:-}

# Update cabal package database
run_and_log "cabal-update" cabal v2-update
# run_and_log "cabal-install" cabal install -j \
#   --installdir=/usr/local/bin \
#   --install-method=copy \
#   ghc-platform-0.1.0.0\
#   hadrian-0.1.0.0 \
#   alex-3.2.6 happy hscolour

_hadrian_build=("${SRC_DIR}"/hadrian/build.bat "-j")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-w64-mingw32"
  --host="x86_64-w64-mingw32"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --disable-numa
  --enable-distro-toolchain
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
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --docs=none
