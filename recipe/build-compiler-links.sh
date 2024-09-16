#!/bin/bash

set -exuo pipefail

GHC_BINARIES="hp2ps hpc hsc2hs"
for exe in ${GHC_BINARIES}; do
  mv ${SRC_DIR}/moved_binaries/${conda_target_arch}-${exe} ${PREFIX}/bin/${conda_target_arch}-${exe}
done

# Regenerate symlinks
pushd ${PREFIX}/bin
  ln -s ${PREFIX}/bin/${conda_target_arch}-ghc-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-ghc
  ln -s ${PREFIX}/bin/${conda_target_arch}-ghci-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-ghci
  ln -s ${PREFIX}/bin/${conda_target_arch}-ghc-pkg-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-ghc-pkg
  ln -s ${PREFIX}/bin/${conda_target_arch}-runghc-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-runghc
  ln -s ${PREFIX}/bin/${conda_target_arch}-runghc ${PREFIX}/bin/${conda_target_arch}-runhaskell
popd

