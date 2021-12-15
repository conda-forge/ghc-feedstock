#!/bin/bash

if [[ "${PKG_NAME:-}" != "ghc_osx-arm64" ]]; then
  conda_target_arch-ghc-pkg-PKG_VERSION recache
fi
export GHC=${CONDA_PREFIX}/bin/conda_target_arch-ghc-PKG_VERSION
export GHC_PKG=${CONDA_PREFIX}/bin/conda_target_arch-ghc-pkg-PKG_VERSION
export HSC2HS=${CONDA_PREFIX}/bin/conda_target_arch-hsc2hs
