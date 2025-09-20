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
  # --build="x86_64-apple-darwin13.4.0"
  # --host="x86_64-apple-darwin13.4.0"
  --build="x86_64-apple-darwin"
  --host="x86_64-apple-darwin"
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

# configure detect the wrong CC/CXX (unknown why)
# export ac_cv_prog_CC="x86_64-apple-darwin13.4.0-clang"
# export ac_cv_path_CC="x86_64-apple-darwin13.4.0-clang"
# export ac_cv_prog_CXX="x86_64-apple-darwin13.4.0-clang++"
# export ac_cv_path_CXX="x86_64-apple-darwin13.4.0-clang++"

# Prevent autoconf from finding system compilers
# export ac_cv_path_ac_pt_CC=""
# export ac_cv_path_ac_pt_CXX=""

run_and_log "configure" bash ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || true

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none --progress-info=none
