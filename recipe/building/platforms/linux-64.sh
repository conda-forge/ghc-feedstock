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
# Linux uses mostly default implementations
# ==============================================================================

# Linux typically doesn't need many overrides
# The defaults in common-functions.sh work well

# Example override if needed:
# platform_setup_environment() {
#   echo "  Configuring Linux-specific environment..."
#   # Custom Linux environment setup
#   echo "  ✓ Linux environment configured"
# }
