#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux ppc64le (cross-compiled from x86_64)
# ==============================================================================
# Thin wrapper that sources the common Linux cross-compilation script.
# All logic is in linux-cross.sh which handles both aarch64 and ppc64le.
#
# NOTE: ppc64le may require additional patches for ELF relocations.
# See patches/ directory for any ppc64le-specific patches.
# ==============================================================================

set -eu

# Platform metadata
PLATFORM_NAME="Linux ppc64le (cross-compiled from x86_64)"

# Source common Linux cross-compilation logic
source "${RECIPE_DIR}/building/platforms/linux-cross.sh"
