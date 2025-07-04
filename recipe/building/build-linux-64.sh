#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd "${SRC_DIR}"/bootstrap-ghc
  run_and_log "bs-configure" bash configure --prefix="${SRC_DIR}"/binary
  perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' default.target
  run_and_log "bs-make-install" make install

  # CLANG: workaround to GHC not adding gmp to its needed library paths
  perl -pi -e 's#(link flags", "(--target=x86_64-unknown-linux|-Wl,--no-as-needed))#$1 -Wl,-L$ENV{BUILD_PREFIX}/lib#' "${SRC_DIR}"/binary/lib/ghc-"${BOOT_VERSION}"/lib/settings
  perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/binary/lib/ghc-"${BOOT_VERSION}"/lib/settings

  # Update rpath of bootstrap HShaskeline and HSterminfo
  find "${SRC_DIR}/binary/lib" -type f \( -name "*HShaskeline*.so" -o -name "*HSterminfo*.so" -o -name "ghc-${BOOT_VERSION}" \) | while read -r lib; do
    current_rpath=$(patchelf --print-rpath "$lib")
    patchelf --set-rpath "${BUILD_PREFIX}/lib" "${lib}"
    if [[ -n "${current_rpath}" ]]; then
      patchelf --add-rpath "${current_rpath}" "${lib}"
    fi
    patchelf --replace-needed libtinfo.so.6 "${BUILD_PREFIX}"/lib/libtinfo.so.6 "${lib}"
  done
popd

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
  # --enable-ghc-toolchain=yes
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

# run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
# run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release --freeze1 --docs=none --progress-info=none
# run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none

# GHC build ghc-pkg with '-fno-use-rpaths' but it requires libiconv.so.2
# _build/stage1/bin/ghc-pkg: error while loading shared libraries: libiconv.so.2
export LD_PRELOAD="${PREFIX}/lib/libiconv.so.2 ${PREFIX}/lib/libgmp.so.10 ${PREFIX}/lib/libffi.so.8 ${PREFIX}/lib/libtinfow.so.6 ${PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"
# run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none

run_and_log "build" "${_hadrian_build[@]}" --prefix="${PREFIX}" --flavour=release --docs=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none

# _lib_path='x86_64-linux-ghc-'"${PKG_VERSION}"'-inplace'
# perl -pi -e "s#(link flags\", \"--target=x86_64-conda-linux)#\$1 -L\\\$topdir/${_lib_path} -Wl,-rpath=\\\$topdir/${_lib_path} -Wl,-rpath-link=\\\$topdir/${_lib_path}#g" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings
# perl -pi -e "s#(compiler flags\", \"--target=x86_64-conda-linux)#\$1 -L\\\$topdir/${_lib_path} -Wl,-rpath=\\\$topdir/${_lib_path} -Wl,-rpath-link=\\\$topdir/${_lib_path}#g" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings
