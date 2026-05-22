#!/bin/bash

set -exuo pipefail

GHC_BINARIES="ghc-${PKG_VERSION} ghc-pkg-${PKG_VERSION} ghci-${PKG_VERSION} hp2ps hpc hsc2hs runghc-${PKG_VERSION}"
for exe in ${GHC_BINARIES}; do
  ln -s ${PREFIX}/bin/${conda_target_arch}-${exe} ${PREFIX}/bin/${exe}
done

ln -s ${PREFIX}/bin/${conda_target_arch}-ghc-${PKG_VERSION} ${PREFIX}/bin/ghc
ln -s ${PREFIX}/bin/${conda_target_arch}-ghci-${PKG_VERSION} ${PREFIX}/bin/ghci
ln -s ${PREFIX}/bin/${conda_target_arch}-ghc-pkg-${PKG_VERSION} ${PREFIX}/bin/ghc-pkg
ln -s ${PREFIX}/bin/${conda_target_arch}-runghc-${PKG_VERSION} ${PREFIX}/bin/runghc
ln -s ${PREFIX}/bin/${conda_target_arch}-runghc ${PREFIX}/bin/runhaskell
