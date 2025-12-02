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
#
# CRITICAL: Ensure we're using conda bash 5.2+, not system bash
# The shebang uses /bin/bash, but conda-build will invoke this with the
# build environment's bash through its own execution wrapper.
if [[ ${BASH_VERSINFO[0]} -lt 5 || (${BASH_VERSINFO[0]} -eq 5 && ${BASH_VERSINFO[1]} -lt 2) ]]; then
  echo "re-exec with conda bash..."
  if [[ -x "${BUILD_PREFIX}/bin/bash" ]]; then
    exec "${BUILD_PREFIX}/bin/bash" "$0" "$@"
  else
    echo "ERROR: Could not find conda bash at ${BUILD_PREFIX}/bin/bash"
    exit 1
  fi
fi

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
# Set GHC to bootstrap compiler (if not already set by platform config)
# For native builds, use 'which ghc' to find it dynamically (handles both ghc-bootstrap and ghc packages)
# For cross-compile, setup_cross_build_env will override this.
if [[ -z "${GHC:-}" ]]; then
  export GHC=$(which ghc 2>/dev/null || echo "")
fi

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
# VERIFY CRITICAL PATCHES (PPC64LE only)
# ==============================================================================
# After Issues #23, #27, #30: Patches can fail silently!
# Verify critical StgRun patches were applied on ppc64le
if [[ "${target_platform}" == *"ppc64le"* ]]; then
  echo "=== Verifying PPC64LE StgRun patches applied ==="

  # Check StgCRunAsm.S - should have .hidden commented out with /* */ (file is preprocessed)
  if grep -q "/\*.*\.hidden StgRun" "${SRC_DIR}/rts/StgCRunAsm.S"; then
    echo "  ✓ StgCRunAsm.S: .hidden StgRun commented out"
  else
    echo "  ✗ ERROR: StgCRunAsm.S patch not applied!"
    grep -n "\.hidden StgRun" "${SRC_DIR}/rts/StgCRunAsm.S" || true
    exit 1
  fi

  # Check StgCRun.c - should have .hidden commented out with /* */
  if grep -q "/\*.*\.hidden StgRun" "${SRC_DIR}/rts/StgCRun.c"; then
    echo "  ✓ StgCRun.c: .hidden StgRun directives commented out"
  else
    echo "  ✗ ERROR: StgCRun.c patch not applied!"
    grep -n "\.hidden StgRun" "${SRC_DIR}/rts/StgCRun.c" || true
    exit 1
  fi

  # Check StgRun.h - should have PowerPC conditional without RTS_PRIVATE
  if grep -q "powerpc64_HOST_ARCH" "${SRC_DIR}/rts/StgRun.h"; then
    echo "  ✓ StgRun.h: powerpc64_HOST_ARCH conditional present"
  else
    echo "  ✗ ERROR: StgRun.h patch not applied!"
    cat "${SRC_DIR}/rts/StgRun.h"
    exit 1
  fi

  echo "=== All PPC64LE patches verified ==="
fi

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

source "${RECIPE_DIR}/building/lib/99-post-build-cleanup.sh"
run_post_build_cleanup

# ==============================================================================
# BUILD COMPLETE
# ==============================================================================

echo "===================================================================="
echo "  GHC ${PKG_VERSION} BUILD COMPLETE"
echo "  Platform: ${PLATFORM_NAME}"
echo "  Installed to: ${PREFIX}"
echo "===================================================================="
