#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  run_and_log "bs-configure" bash configure \
    --prefix="${SRC_DIR}"/binary \
    --host="x86_64-apple-darwin"
  cp default.target.ghc-toolchain default.target
  run_and_log "bs-make-install" make install
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update --allow-newer --minimize-conflict-set

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --target="arm64-apple-darwin20.0.0"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --disable-numa
  --enable-ignore-build-platform-mismatch=yes
  --enable-ghc-toolchain=yes
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

# This will not generate ghc-toolchain-bin or the .ghc-toolchain (possibly due to x-platform)
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
# Attempt to brute-force it
"${SRC_DIR}"/binary/lib/ghc-"${BOOT_VERSION}"/bin/ghc-toolchain-bin \
  -t "arm64-apple-darwin20.0.0" \
  -T "arm64-apple-darwin20.0.0-" \
  --cpp="${BUILD_PREFIX}"/bin/arm64-conda-linux-gnu-clang-cpp \
  -o "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain

find . -name "ghc-toolchain-bin"
find . -name "*.ghc-toolchain"
diff "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain "${SRC_DIR}"/hadrian/cfg/default.target

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all"  "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none
CC="${CC_FOR_BUILD}" run_and_log "install_xcompiled" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs
