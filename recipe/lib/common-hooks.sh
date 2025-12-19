#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Common Hook Defaults
# ==============================================================================
# Purpose: Provide no-op default implementations for all platform hooks
#
# Platform configs can source this file and override only the hooks they need.
# All hooks have no-op defaults so platforms only implement what's necessary.
#
# Hook Categories:
#   1. Pre/Post hooks  - Called before/after each phase (via call_hook)
#   2. Main hooks      - Override default_xxx() behavior
#   3. Callback hooks  - Called by default implementations for customization
#
# Usage:
#   source "${RECIPE_DIR}/lib/common-hooks.sh"
#
#   # Override only what you need:
#   platform_setup_environment() {
#     export MY_VAR="value"
#   }
# ==============================================================================

set -eu

# ==============================================================================
# PHASE 1: ENVIRONMENT SETUP HOOKS
# ==============================================================================

# Called before default environment setup
platform_pre_setup_environment() {
  : # No-op
}

# Override to customize environment setup
# If defined, replaces default_setup_environment()
# platform_setup_environment() {
#   export PATH="${BUILD_PREFIX}/bin:${PATH}"
# }

# Called after environment setup
platform_post_setup_environment() {
  : # No-op
}

# ==============================================================================
# PHASE 2: BOOTSTRAP SETUP HOOKS
# ==============================================================================

# Called before bootstrap setup
platform_pre_setup_bootstrap() {
  : # No-op
}

# Override to customize bootstrap GHC/Cabal setup
# If defined, replaces default_setup_bootstrap()
# platform_setup_bootstrap() {
#   export GHC="${BUILD_PREFIX}/ghc-bootstrap/bin/ghc"
# }

# Called after bootstrap setup
platform_post_setup_bootstrap() {
  : # No-op
}

# ==============================================================================
# PHASE 3: CABAL SETUP HOOKS
# ==============================================================================

# Called before cabal setup
platform_pre_setup_cabal() {
  : # No-op
}

# Override to customize Cabal configuration
# If defined, replaces default_setup_cabal()
# platform_setup_cabal() {
#   export CABAL="${BUILD_PREFIX}/bin/cabal"
#   export CABAL_DIR="${SRC_DIR}/.cabal"
# }

# Called after cabal setup
platform_post_setup_cabal() {
  : # No-op
}

# ==============================================================================
# PHASE 4: CONFIGURE GHC HOOKS
# ==============================================================================

# Called before GHC configure
platform_pre_configure_ghc() {
  : # No-op
}

# Override to completely customize GHC configure
# If defined, replaces default_configure_ghc()
# platform_configure_ghc() {
#   ./configure --prefix="${PREFIX}" "${MY_ARGS[@]}"
# }

# Callback: Add extra arguments to default configure
# Called by default_configure_ghc() to extend configure_args array
# Uses nameref pattern - receives array name as $1
#
# Example:
#   platform_add_configure_args() {
#     local -n args="$1"
#     args+=(--with-intree-gmp=yes)
#   }
#
# platform_add_configure_args() {
#   : # No-op - use default args only
# }

# Called after GHC configure
platform_post_configure_ghc() {
  : # No-op
}

# ==============================================================================
# PHASE 5: BUILD HADRIAN HOOKS
# ==============================================================================

# Called before Hadrian build
platform_pre_build_hadrian() {
  : # No-op
}

# Override to customize Hadrian build
# If defined, replaces default_build_hadrian()
# Must set HADRIAN_CMD array and FLAVOUR
# platform_build_hadrian() {
#   "${CABAL}" v2-build hadrian
#   build_hadrian_cmd HADRIAN_CMD "${hadrian_bin}"
# }

# Called after Hadrian build
platform_post_build_hadrian() {
  : # No-op
}

# ==============================================================================
# PHASE 6: BUILD STAGE 1 HOOKS
# ==============================================================================

# Called before Stage 1 build
platform_pre_build_stage1() {
  : # No-op
}

# Override to customize Stage 1 build
# If defined, replaces default_build_stage1()
# platform_build_stage1() {
#   "${HADRIAN_CMD[@]}" stage1:exe:ghc-bin --flavour="${FLAVOUR}"
# }

# Called after Stage 1 build
platform_post_build_stage1() {
  : # No-op
}

# ==============================================================================
# PHASE 7: BUILD STAGE 2 HOOKS
# ==============================================================================

# Called before Stage 2 build
platform_pre_build_stage2() {
  : # No-op
}

# Override to customize Stage 2 build
# If defined, replaces default_build_stage2()
# platform_build_stage2() {
#   "${HADRIAN_CMD[@]}" stage2:exe:ghc-bin --flavour="${FLAVOUR}"
# }

# Called after Stage 2 build
platform_post_build_stage2() {
  : # No-op
}

# ==============================================================================
# PHASE 8: INSTALL GHC HOOKS
# ==============================================================================

# Called before GHC install
platform_pre_install_ghc() {
  : # No-op
}

# Override to customize GHC installation
# If defined, replaces default_install_ghc()
# platform_install_ghc() {
#   "${HADRIAN_CMD[@]}" binary-dist --prefix="${PREFIX}"
#   # ... install from bindist
# }

# Called after GHC install
platform_post_install_ghc() {
  : # No-op
}

# ==============================================================================
# PHASE 9: POST-INSTALL HOOKS
# ==============================================================================

# Called before post-install
platform_pre_post_install() {
  : # No-op
}

# Override to customize post-installation
# If defined, replaces default_post_install()
# platform_post_install() {
#   "${PREFIX}/bin/ghc" --version
# }

# Called after post-install
platform_post_post_install() {
  : # No-op
}

# ==============================================================================
# PHASE 10: ACTIVATION HOOKS
# ==============================================================================

# Called before activation
platform_pre_activation() {
  : # No-op
}

# Override to customize activation script installation
# If defined, replaces default_activation()
# platform_activation() {
#   cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/"
# }

# Called after activation
platform_post_activation() {
  : # No-op
}

# ==============================================================================
# METADATA VARIABLES (optional, for documentation)
# ==============================================================================
# Platform configs can set these for self-documentation:
#
# PLATFORM_NAME="linux-64"       # Human-readable platform name
# PLATFORM_TYPE="native"         # "native" or "cross"
# INSTALL_METHOD="bindist"       # "native" (hadrian install) or "bindist"
