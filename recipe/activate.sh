#!/bin/bash

ghc-pkg recache

# Disabled: if [[ "$(uname)" == "Linux" ]] && [[ "$(uname -m)" == "x86_64" ]]; then
# Disabled:   aarch64-conda-linux-gnu-ghc-pkg recache
# Disabled: fi
