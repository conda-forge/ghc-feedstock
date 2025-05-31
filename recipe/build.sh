#!/usr/bin/env bash
set -ex

unset host_alias

# Set environment variables
export MergeObjsCmd=${LD_GOLD}
export CC=${CC}
export CXX=${CXX}
export LDFLAGS="${LDFLAGS} -Wl,--allow-multiple-definition"
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python

# Set up binary directory
mkdir -p binary _logs

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
    CC="${CC_FOR_BUILD}" \
    CXX="${CXX_FOR_BUILD}" \
    ./configure \
    --prefix="${PWD}"/../binary #> ../_logs/bs-configure.log 2>&1
  make install #> ../_logs/bs-make-install.log 2>&1
popd

if [[ -d target-ghc-libs ]]; then
  pushd target-ghc-libs
    ./configure --prefix="${PWD}"/../binary --target="${GHC_TARGET}" #> ../_logs/bs-libs-configure.log 2>&1
  popd
fi

# Add binary GHC to PATH
export PATH=$PWD/binary/bin:$PATH

# Install cabal-install
mkdir -p binary/bin
cp bootstrap-cabal/cabal binary/bin/

# Update cabal package database
cabal v2-update > _logs/cabal-configure.log 2>&1

case "$target_platform" in
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
./configure "${CONFIGURE_ARGS[@]}" #> _logs/configure.log 2>&1

# Build and install using hadrian
hadrian/build install -j"${CPU_COUNT}" --prefix="${PREFIX}" --flavour=release --freeze1 --docs=no-sphinx-pdfs

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

# Run post-install
if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  "${PREFIX}"/bin/ghc-pkg recache
else
  "${CROSSCOMPILING_EMULATOR}" "${PREFIX}"/bin/ghc-pkg recache
fi

# # For macOS, fix library paths if needed
# if [[ "$target_platform" == "osx-"* ]]; then
#   find "${PREFIX}/lib" -name "*.dylib" -o -name "*.so" | while read lib; do
#     install_name_tool -change "@rpath/libgmp.10.dylib" "${PREFIX}/lib/libgmp.10.dylib" "$lib" || true
#   done
#
#   # Also fix executables
#   find "${PREFIX}/bin" -type f -executable | while read exe; do
#     install_name_tool -change "@rpath/libgmp.10.dylib" "${PREFIX}/lib/libgmp.10.dylib" "$exe" || true
#   done
# fi
