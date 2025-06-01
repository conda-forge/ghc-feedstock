#!/usr/bin/env bash
set -ex

unset host_alias

# Set environment variables
export MergeObjsCmd=${LD_GOLD:-${LD}}
export CC=${CC}
export CXX=${CXX}
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python

# Set up binary directory
mkdir -p binary _logs
_log_index=0

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  CC="${CC_FOR_BUILD}" \
  CXX="${CXX_FOR_BUILD}" \
  LDFLAGS="${LDFLAGS//$PREFIX/$BUILD_PREFIX}" \
  _logname="bs-configure"
  ./configure \
    --prefix="${SRC_DIR}"/binary > ../_logs/${_log_index}_${_logname}.log 2>&1; tail -20 ../_logs/${_log_index}_${_logname}.log; let "_log_index += 1"
  _logname="bs-make-install" make install > ../_logs/${_log_index}_${_logname}.log 2>&1; tail -20 ../_logs/${_log_index}_${_logname}.log; let "_log_index += 1"

  # Find bootstrap HShaskeline and HSterminfo
  find "${SRC_DIR}/binary" -type f -name "*HShaskeline*.so" -o -name "*HSterminfo*.so" | while read lib; do
    # Check if this library has the RPATH we want to change
    current_rpath=$(patchelf --print-rpath "$lib" 2>/dev/null)
    if [[ "$current_rpath" == *"$PREFIX/lib"* ]]; then
      # Replace with BUILD_PREFIX but preserve any other paths
      new_rpath="${current_rpath//$PREFIX\/lib/$BUILD_PREFIX/lib}"
      patchelf --set-rpath "$new_rpath" "$lib"
      patchelf --replace-needed libtinfo.so.6 "$BUILD_PREFIX"/lib/libtinfo.so.6 "$lib"
    fi
  done
popd

# Add binary GHC to PATH
export PATH=$PWD/binary/bin:$PATH

# Install cabal-install
mkdir -p binary/bin
cp bootstrap-cabal/cabal binary/bin/

# Update cabal package database
_logname="cabal-update" cabal v2-update > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"

case "${target_platform}" in
  linux-*)
    GHC_BUILD=x86_64-unknown-linux
    GHC_HOST=x86_64-unknown-linux
    ;;
  osx-*)
    GHC_BUILD=x86_64-apple-darwin
    GHC_HOST=x86_64-apple-darwin
    ;;
esac

# Set target-specific values
case "$target_platform" in
  linux-64)      GHC_TARGET=x86_64-conda-linux-gnu ;;
  linux-aarch64) GHC_TARGET=aarch64-conda-linux-gnu ;;
  osx-64)        GHC_TARGET=x86_64-apple-darwin13.4.0 ;;
  osx-arm64)     GHC_TARGET=aarch64-apple-darwin20.0.0 ;;
esac

# Configure and build GHC
CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --build="${GHC_BUILD}"
  --host="${GHC_HOST}"
  --target="${GHC_TARGET}"
  --disable-numa
  --with-system-libffi=yes
  --with-ffi-includes="${PREFIX}"/include
  --with-ffi-libraries="${PREFIX}"/lib
  --with-gmp-includes="${PREFIX}"/include
  --with-gmp-libraries="${PREFIX}"/lib
  --with-curses-includes="${PREFIX}"/include
  --with-curses-libraries="${PREFIX}"/lib
)

export LD_LIBRARY_PATH=$PREFIX/lib:$LD_LIBRARY_PATH
_logname="ghc-configure" ./configure "${CONFIGURE_ARGS[@]}" > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"

# Build and install using hadrian
_logname="stage1_exe" hadrian/build stage1:exe:ghc-bin -j"${CPU_COUNT}" --flavour=release --docs=none --progress-info=none > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
_logname="stage1_lib" hadrian/build stage1:lib:ghc -j"${CPU_COUNT}" --flavour=release --docs=none --progress-info=none > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
_logname="stage2_exe" hadrian/build stage2:exe:ghc-bin -j"${CPU_COUNT}" --flavour=release --freeze1 --docs=none --progress-info=none > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
_logname="stage2_lib" hadrian/build stage2:lib:ghc -j"${CPU_COUNT}" --flavour=release --freeze1 --docs=none --progress-info=none > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
_logname="build_all" hadrian/build -j"${CPU_COUNT}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"

if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  _logname="install" hadrian/build install -j"${CPU_COUNT}" --prefix="${PREFIX}" --flavour=release --docs=no-sphinx-pdfs > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
else
  _logname="install_xcompiled" CC="${CC_FOR_BUILD}" hadrian/build install -j"${CPU_COUNT}" --prefix="${PREFIX}" --flavour=release --docs=no-sphinx-pdfs > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
fi

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

# Run post-install
if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  _logname="recache_xcompiled" "${CROSSCOMPILING_EMULATOR}" "${PREFIX}"/bin/ghc-pkg recache > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
else
  _logname="recache" "${PREFIX}"/bin/ghc-pkg recache > _logs/${_log_index}_${_logname}.log 2>&1; tail -20 _logs/${_log_index}_${_logname}.log; let "_log_index += 1"
fi
