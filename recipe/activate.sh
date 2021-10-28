#!/bin/bash

if [[ "${CONDA_BUILD:-0}" == 1 && "${PKG_NAME}" == ghc* ]]; then
  echo "Skipping ghc-pkg recache during ghc* package build"
  export
else
  conda_target_arch-ghc-pkg-PKG_VERSION recache
fi
export GHC=${CONDA_PREFIX}/bin/conda_target_arch-ghc-PKG_VERSION
export GHC_PKG=${CONDA_PREFIX}/bin/conda_target_arch-ghc-pkg-PKG_VERSION
export HSC2HS=${CONDA_PREFIX}/bin/conda_target_arch-hsc2hs
