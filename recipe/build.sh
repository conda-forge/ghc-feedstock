#!/usr/bin/env bash
set -ex

# Set environment variables
export MergeObjsCmd=ld
export CC=${CC}
export CXX=${CXX}
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python

# Set up binary directory
mkdir -p binary

# Install bootstrap GHC
pushd bootstrap-ghc || exit 1
  ./configure --prefix=$PWD/../binary
  make install
#  if [[ "$target_platform" == linux-* ]]; then
#    # Set library path for bootstrap executables
#    export LD_LIBRARY_PATH=$PREFIX/lib:$LD_LIBRARY_PATH
#
#    # Optionally use patchelf to fix the RPATH of the bootstrap GHC binaries
#    find binary -type f -executable -exec patchelf --set-rpath "$BUILD_PREFIX/lib" {} \; 2>/dev/null || true
#  fi
popd

# Add binary GHC to PATH
export PATH=$PWD/binary/bin:$PATH

# Install cabal-install
mkdir -p binary/bin
cp bootstrap-cabal/cabal binary/bin/

# Update cabal package database
cabal v2-update

# Configure and build GHC
CONFIGURE_ARGS=(
  --prefix=$PREFIX
  --disable-numa
  --enable-libffi-adjustors
  --with-system-libffi=yes
  --with-ffi-includes=$PREFIX/include
  --disable-exec-static-tramp
  --with-ffi-libraries=$PREFIX/lib
  --with-gmp-includes=$PREFIX/include
  --with-gmp-libraries=$PREFIX/lib
  --with-gmp-libraries=$PREFIX/lib
  --with-curses-includes=$PREFIX/include
  --with-curses-libraries=$PREFIX/lib
)

if [[ "$target_platform" == "linux-"* ]]; then
  CONFIGURE_ARGS+=(--build=x86_64-unknown-linux --host=x86_64-unknown-linux)
elif [[ "$target_platform" == "osx-"* ]]; then
  CONFIGURE_ARGS+=(--build=x86_64-apple-darwin13.4.0 --host=x86_64-apple-darwin13.4.0)
fi

if [[ "$target_platform" == "linux-aarch64" ]]; then
  CONFIGURE_ARGS+=(--target=aarch64-unknown-linux)
elif [[ "$target_platform" == "osx-arm64" ]]; then
  CONFIGURE_ARGS+=(--target=aarch64-apple-darwin)
fi

./configure ${CONFIGURE_ARGS[@]}

# Build and install using hadrian
hadrian/build install -j${CPU_COUNT} --prefix=$PREFIX --flavour=release --freeze1 --docs=no-sphinx-pdfs

# Create bash completion
mkdir -p $PREFIX/etc/bash_completion.d
cp utils/completion/ghc.bash $PREFIX/etc/bash_completion.d/ghc

# Clean up package cache
rm -f $PREFIX/lib/ghc-$PKG_VERSION/lib/package.conf.d/package.cache
rm -f $PREFIX/lib/ghc-$PKG_VERSION/lib/package.conf.d/package.cache.lock

# Run post-install
$PREFIX/bin/ghc-pkg recache
