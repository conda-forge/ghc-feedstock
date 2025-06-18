#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PYTHON=python
export MSYSTEM=MINGW64
export MSYS2_ARG_CONV_EXCL="*"
export PATH="${SRC_DIR}"/bootstrap-ghc/bin:"${SRC_DIR}"/bootstrap-cabal/bin${PATH:+:}${PATH:-}

export TMP="$(cygpath -w "$TEMP")"
export TMPDIR="$(cygpath -w "$TEMP")"
export GHC="${SRC_DIR}"/bootstrap-ghc/bin/ghc.exe
export CABAL="${SRC_DIR}"/bootstrap-cabal/bin/cabal.exe
ln -s "${SRC_DIR}"/bootstrap-cabal/bin/cabal.exe "${SRC_DIR}"/bootstrap-cabal/bin/cabal

mkdir -p "${SRC_DIR}/hadrian/cfg"
touch "${SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"

# Update cabal package database
# run_and_log "cabal-update" cabal v2-update
cabal v2-update

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
# run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --docs=none
