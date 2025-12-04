#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux x86_64 (Native)
# ==============================================================================
# Linux-specific build behavior.
# Most phases use defaults from common-functions.sh
# ==============================================================================

set -eu

# Platform metadata
PLATFORM_NAME="Linux x86_64 (native)"

# ==============================================================================
# Platform Triple Configuration
# ==============================================================================
# Bootstrap GHC 9.2.8 uses 'x86_64-unknown-linux-gnu' but conda toolchain
# uses 'x86_64-conda-linux-gnu'. Override to match bootstrap GHC.

ghc_triple="x86_64-unknown-linux-gnu"

# Override build/host aliases for GHC configure
export build_alias="${ghc_triple}"
export host_alias="${ghc_triple}"

echo "Platform triple configuration:"
echo "  GHC triple: ${ghc_triple}"
echo "  build_alias: ${build_alias}"
echo "  host_alias: ${host_alias}"
