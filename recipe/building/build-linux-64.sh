#!/usr/bin/env bash
set -eu

_log_index=0
_debug=1

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd "${SRC_DIR}"/bootstrap-ghc
  # CC="${CC_FOR_BUILD}" \
  # CXX="${CXX_FOR_BUILD}" \
  # LDFLAGS="${LDFLAGS//$PREFIX/$BUILD_PREFIX}" \
  run_and_log "bs-configure" bash configure \
    --prefix="${SRC_DIR}"/binary \
    --host="x86_64-conda-linux-gnu" \
    --enable-ghc-toolchain=yes
  cp default.host.target.ghc-toolchain default.host.target
  cp default.target.ghc-toolchain default.target
  run_and_log "bs-make-install" make install

  # Update rpath of bootstrap HShaskeline and HSterminfo
  find "${SRC_DIR}/binary/lib" -type f \( -name "*HShaskeline*.so" -o -name "*HSterminfo*.so" -o -name "ghc-${PKG_VERSION}" \) | while read lib; do
    echo "Updating rpath of $lib"
    current_rpath=$(patchelf --print-rpath "$lib")
    patchelf --set-rpath "$BUILD_PREFIX/lib" "$lib"
    if [[ -n "$current_rpath" ]]; then
      patchelf --add-rpath "$current_rpath" "$lib"
    fi
    patchelf --replace-needed libtinfo.so.6 "$BUILD_PREFIX"/lib/libtinfo.so.6 "$lib"
  done

  run_and_log "bs-ghc-toolchain" ./bin/ghc-toolchain-bin \
    -t x86_64-conda-linux-gnu \
    -T x86_64-conda-linux-gnu- \
    --ld-opt="-L$BUILD_PREFIX/lib" \
    -o "${SRC_DIR}"/hadrian/cfg/x86_64-conda-linux-gnu.target
  cp "${SRC_DIR}"/hadrian/cfg/x86_64-conda-linux-gnu.target "${SRC_DIR}"/hadrian/cfg/x86_64-unknow-linux.host.target
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-unknown-linux"
  --host="x86_64-unknown-linux"
  --target="x86_64-conda-linux-gnu"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --enable-ghc-toolchain=yes  # Necessary to avoid linker unable to load -lgmp
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
mkdir -p bin && cp bootstrap-ghc/bin/ghc-toolchain-bin bin/ghc-toolchain-bin
autoreconf -fiv
GHC="binary/bin/ghc -v2" run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

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
