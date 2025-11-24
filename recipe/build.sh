#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build - Unified Entry Point
# ==============================================================================
# This script works for ALL platforms (linux-64, linux-aarch64, osx-64, osx-arm64)
# Platform-specific configuration is loaded from building/config/
#
# Build flow:
#   1. Common setup (directories, environment)
#   2. Detect platform and load configuration
#   3. Execute common build flow (customized via platform hooks)
#   4. Common post-build cleanup
# ==============================================================================

set -eu

# ==============================================================================
# COMMON SETUP (all platforms)
# ==============================================================================

# Set up directories
mkdir -p binary/bin _logs
mkdir -p "${PREFIX}"/etc/bash_completion.d

# Set up build environment
export MergeObjsCmd=${LD_GOLD:-${LD}}
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python
# Ensure BUILD_PREFIX/bin is FIRST in PATH (for bash 5.2+ support)
export PATH=${BUILD_PREFIX}/bin:${BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}

# ==============================================================================
# PLATFORM DETECTION AND CONFIGURATION
# ==============================================================================

# Detect platform and load configuration
source "${RECIPE_DIR}/building/config/detect-platform.sh"
detect_and_load_platform_config

# Load common modules and build flow
source "${RECIPE_DIR}/building/common.sh"
source "${RECIPE_DIR}/building/lib/90-common-flow.sh"

# ==============================================================================
# EXECUTE BUILD FLOW
# ==============================================================================
# The common flow orchestrates all build phases, calling platform-specific
# hooks at each stage. See lib/90-common-flow.sh for the complete sequence.
# ==============================================================================

common_flow_execute_all

# ==============================================================================
# COMMON POST-BUILD CLEANUP (all platforms)
# ==============================================================================

echo ""
echo "=== Post-Build Cleanup ==="

# Install bash completion
echo "  Installing bash completion..."
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache (we use ghc-pkg in activation)
echo "  Cleaning package cache..."
rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

# Install activation script
echo "  Installing activation script..."
mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"

# Cleanup hard-coded build paths in settings file
echo "  Cleaning build paths from settings file..."
settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
if [[ -n "${settings_file}" ]]; then
  perl -pi -e "s#(${BUILD_PREFIX}|${PREFIX})/(bin|lib)/##g" "${settings_file}"
fi

# Create symlinks for dynamic libraries (remove -ghc<version> suffix)
echo "  Creating library symlinks..."
find "${PREFIX}/lib" -name "*-ghc${PKG_VERSION}.dylib" -o -name "*-ghc${PKG_VERSION}.so" | while read -r lib; do
  base_lib="${lib//-ghc${PKG_VERSION}./.}"
  if [[ ! -e "$base_lib" ]]; then
    ln -s "$(basename "$lib")" "$base_lib"
  fi
done

# Collect license files from libraries
echo "  Collecting license files..."
for lic_file in $(find "${SRC_DIR}"/libraries/*/LICENSE); do
  folder=$(dirname "${lic_file}")
  mkdir -p "${SRC_DIR}"/license_files/"${folder}"
  cp "${lic_file}" "${SRC_DIR}"/license_files/"${folder}"
done

echo "  Cleanup complete"
echo ""

# ==============================================================================
# BUILD COMPLETE
# ==============================================================================

echo "===================================================================="
echo "  GHC ${PKG_VERSION} BUILD COMPLETE"
echo "  Platform: ${PLATFORM_NAME}"
echo "  Installed to: ${PREFIX}"
echo "===================================================================="
