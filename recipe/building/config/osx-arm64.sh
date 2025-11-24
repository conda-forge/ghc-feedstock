#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: macOS x86_64 → arm64 Cross-Compile
# ==============================================================================
# Purpose: Cross-compile GHC from macOS x86_64 to arm64
#
# NOTE: This is a complex platform with custom build flow that doesn't map
#       cleanly to the standard orchestrator pattern. Implementation pending.
#
# For now, this config will trigger an error and the build will fall back
# to using the original build-osx-arm64.sh script.
#
# Dependencies: common-hooks.sh (for defaults)
# ==============================================================================

set -eu

# Load common hook defaults
source "${RECIPE_DIR}/building/config/common-hooks.sh"

# ==============================================================================
# PLATFORM METADATA
# ==============================================================================

PLATFORM_NAME="osx-arm64"
PLATFORM_TYPE="cross"
INSTALL_METHOD="native"  # Uses hadrian install, not bindist

# ==============================================================================
# TODO: IMPLEMENTATION PENDING
# ==============================================================================

echo "ERROR: osx-arm64 unified config not yet implemented"
echo "  This platform requires custom build flow that doesn't map cleanly"
echo "  to the standard orchestrator pattern."
echo ""
echo "  Please use the original build-osx-arm64.sh for now."
echo "  The unified architecture is available for:"
echo "    - linux-64 (native)"
echo "    - linux-cross (aarch64, ppc64le)"
echo "    - osx-64 (native)"
echo ""
exit 1

# ==============================================================================
# PLACEHOLDER HOOKS (not implemented)
# ==============================================================================

# All hooks will use defaults from common-hooks.sh
# This will cause errors, which is intentional until we implement this platform
