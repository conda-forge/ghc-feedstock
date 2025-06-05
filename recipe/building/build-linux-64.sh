#!/usr/bin/env bash
set -eu

_log_index=0
_debug=1

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  CC="${CC_FOR_BUILD}" \
  CXX="${CXX_FOR_BUILD}" \
  LDFLAGS="${LDFLAGS//$PREFIX/$BUILD_PREFIX}" \
  run_and_log "bs-configure" bash configure --prefix="${SRC_DIR}"/binary
  run_and_log "bs-make-install" make install

  # Update rpath of bootstrap HShaskeline and HSterminfo
  find "${SRC_DIR}/binary" -type f -name "*HShaskeline*.so" -o -name "*HSterminfo*.so" | while read lib; do
    current_rpath=$(patchelf --print-rpath "$lib" 2>/dev/null)
    patchelf --set-rpath "$BUILD_PREFIX/lib" "$lib"
    if [[ -n "$current_rpath" ]]; then
      patchelf --add-rpath "$current_rpath" "$lib"
    fi
    patchelf --replace-needed libtinfo.so.6 "$BUILD_PREFIX"/lib/libtinfo.so.6 "$lib"
  done
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

# --- Start conda build with bootstrapping tools ---

case "${target_platform}" in
  linux-*)
    GHC_BUILD_STAGE0=x86_64-unknown-linux
    GHC_BUILD_STAGE1=x86_64-conda-linux-gnu
    _hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
    ;;
  osx-*)
    GHC_BUILD_STAGE0=x86_64-apple-darwin
    GHC_BUILD_STAGE1=x86_64-apple-darwin
    _hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
    ;;
  default)
    GHC_BUILD_STAGE0=x86_64-w64-mingw32
    GHC_BUILD_STAGE1=x86_64-w64-mingw32
    _hadrian_build=("${SRC_DIR}"/hadrian/build.bat "-j")
    ;;
esac

# Set target-specific values
case "$target_platform" in
  linux-64)      GHC_TARGET=x86_64-conda-linux-gnu ;;
  linux-aarch64) GHC_TARGET=aarch64-conda-linux-gnu ;;
  osx-64)        GHC_TARGET=x86_64-apple-darwin13.4.0 ;;
  osx-arm64)     GHC_TARGET=arm64-apple-darwin20.0.0 ;;
  default)       GHC_TARGET=x86_64-w64-mingw32 ;;
esac

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="${GHC_BUILD_STAGE0}"
  --host="${GHC_BUILD_STAGE0}"
  --target="${GHC_TARGET:-${GHC_BUILD_STAGE0}}"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --ignore-build-platform-mismatch
  --enable-ghc-toolchain
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
LDFLAGS="${LDFLAGS//$PREFIX/$BUILD_PREFIX}" run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# Prefer the ghc-toolchain configuration
if [[ -e "hadrian/cfg/default.target.ghc-toolchain" ]]; then
  cp "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain "${SRC_DIR}"/hadrian/cfg/default.target
fi

# Build and install using hadrian
if [[ "${target_platform}" == "osx-arm64" ]] && [[ "${_debug}" == "1" ]]; then
  "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
else
  run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
fi

# Re-built stage1 with conda host convention
# SYSTEM_CONFIG=(
#   # GHC="${SRC_DIR}"/_build/stage0/bin/"${GHC_BUILD_STAGE1}"-ghc
#   --build="${GHC_BUILD_STAGE0}"
#   --host="${GHC_BUILD_STAGE0}"
#   --target="${GHC_TARGET:-${GHC_BUILD_STAGE1}}"
# )
# run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
if [[ -e "hadrian/cfg/default.target.ghc-toolchain" ]]; then
  cp "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain "${SRC_DIR}"/hadrian/cfg/default.target
fi
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all"  "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none

if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  CC="${CC_FOR_BUILD}" run_and_log "install_xcompiled" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs
else
  run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs
fi

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

# Run post-install
if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  "${PREFIX}"/bin/ghc-pkg recache
  # run_and_log "recache" "${PREFIX}"/bin/ghc-pkg recache
else
  "${CROSSCOMPILING_EMULATOR}" "${PREFIX}"/bin/ghc-pkg recache
  # run_and_log "recache_xcompiled" "${CROSSCOMPILING_EMULATOR}" "${PREFIX}"/bin/ghc-pkg recache
fi
