#!/usr/bin/env bash
# ============================================================
# GHC Build Script - Linux x86_64 Native
# ============================================================
# Simplified using build orchestrator
# ============================================================

set -eu

# Initialize logging index
_log_index=0

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

# ============================================================
# CABAL SETUP
# ============================================================

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# ============================================================
# HADRIAN BUILD
# ============================================================

declare -a HADRIAN_BUILD
build_hadrian_binary HADRIAN_BUILD

# ============================================================
# CONFIGURE
# ============================================================

SYSTEM_CONFIG+=(
  --build="x86_64-unknown-linux"
  --host="x86_64-unknown-linux"
)

configure_ghc SYSTEM_CONFIG CONFIGURE_ARGS

# ============================================================
# BUILD FLAVOUR
# ============================================================
# 9.2.8: GHC does not have 'release' flavour, must use 'quick'
# 9.4.8+: Use 'release' for consistency and full optimization

if [[ "${PKG_VERSION}" == "9.2.8"* ]]; then
  HADRIAN_FLAVOUR="quick"
else
  HADRIAN_FLAVOUR="release"
fi

# ============================================================
# BUILD STAGES
# ============================================================

build_stage1 HADRIAN_BUILD "${HADRIAN_FLAVOUR}" "${SRC_DIR}/_build/stage0/lib/settings"
build_stage2 HADRIAN_BUILD "${HADRIAN_FLAVOUR}" "${SRC_DIR}/_build/stage1/lib/settings"

# ============================================================
# INSTALL
# ============================================================

install_ghc HADRIAN_BUILD "${HADRIAN_FLAVOUR}"

echo "=== Build completed successfully ==="
