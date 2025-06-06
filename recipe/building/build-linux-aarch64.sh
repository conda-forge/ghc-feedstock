#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd "${SRC_DIR}"/bootstrap-ghc
  CC=${CC_FOR_BUILD} \
  CXX=${CXX_FOR_BUILD} \
  run_and_log "bs-configure" bash configure --prefix="${SRC_DIR}"/binary
  cp default.target.ghc-toolchain default.target
  run_and_log "bs-make-install" make install

  # Correct GHC settings (odd)
  perl -pi -e 's/(LLVM llvm-as command", ").+?"/$1llvm-as"/' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"
  # Not needed: perl -pi -e 's/(CPP command", ".+?-clang)/$1-cpp/' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"

  # CLANG: workaround to GHC not adding gmp to its needed library paths
  perl -pi -e 's/(link flags", "(--target=x86_64-unknown-linux|-Wl,--no-as-needed))/$1 -Wl,-L$ENV{BUILD_PREFIX}\/lib/' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"

  # Update rpath of bootstrap HShaskeline and HSterminfo
  find "${SRC_DIR}/binary/lib" -type f \( -name "*HShaskeline*.so" -o -name "*HSterminfo*.so" -o -name "ghc-${BOOT_VERSION}" \) | while read -r lib; do
    current_rpath=$(patchelf --print-rpath "$lib")
    patchelf --set-rpath "$BUILD_PREFIX/lib" "$lib"
    if [[ -n "$current_rpath" ]]; then
      patchelf --add-rpath "$current_rpath" "$lib"
    fi
    patchelf --replace-needed libtinfo.so.6 "$BUILD_PREFIX"/lib/libtinfo.so.6 "$lib"
  done
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update --allow-newer --minimize-conflict-set

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-conda-linux-gnu"
  --host="x86_64-conda-linux-gnu"
  --target="x86_64-conda-linux-gnu"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --enable-ignore-build-platform-mismatch=yes
  --enable-ghc-toolchain=yes
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
CC="${BUILD_PREFIX}"/bin/x86_64-conda-linux-gnu-clang \
CXX="${BUILD_PREFIX}"/bin/x86_64-conda-linux-gnu-clang++ \
LD="${BUILD_PREFIX}"/bin/x86_64-conda-linux-gnu-ld \
run_and_log "ghc-configure" bash configure "${CONFIGURE_ARGS[@]}"

# Prefer the ghc-toolchain configuration
if [[ -e "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain ]]; then
  mv "${SRC_DIR}"/hadrian/cfg/default.target "${SRC_DIR}"/hadrian/cfg/default.target.bak
  # cp "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain "${SRC_DIR}"/hadrian/cfg/default.target
  perl -pi -e 's/(cppProgram = Program { prgPath =  ".+?clang)/$1-cpp/' "${SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"
fi
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
# Correct GHC settings (odd)
perl -pi -e 's/(LLVM llvm-as command", ").+?"/$1llvm-as"/' "${SRC_DIR}/_build/stage0/lib/settings"
# Not needed: perl -pi -e 's/(CPP command", ".+?-clang)/$1-cpp/' "${SRC_DIR}/_build/stage0/lib/settings"

SYSTEM_CONFIG=(
  --build="x86_64-conda-linux-gnu"
  --host="x86_64-conda-linux-gnu"
  --target="aarch64-conda-linux-gnu"
)

GHC="${SRC_DIR}"/_build/stage0/bin/ghc run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# Prefer the ghc-toolchain configuration
if [[ -e "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain ]]; then
  mv "${SRC_DIR}"/hadrian/cfg/default.target "${SRC_DIR}"/hadrian/cfg/default.target.bak
  # cp "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain "${SRC_DIR}"/hadrian/cfg/default.target
  perl -pi -e 's/(cppProgram = Program { prgPath =  ".+?clang)/$1-cpp/' "${SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"
fi
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc -VV --flavour=release --freeze1 --docs=none --progress-info=unicorn
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
# run_and_log "build_all"  "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none
# run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs

# One go when ready
# run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=no-sphinx-pdfs
