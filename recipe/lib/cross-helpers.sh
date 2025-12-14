#!/usr/bin/env bash
# ==============================================================================
# Cross-Compilation Helper Functions
# ==============================================================================
# Shared functions for cross-compiled GHC builds (linux-cross, osx-arm64).
# These handle common tasks like symlink creation, wrapper script fixes, etc.
#
# Usage: source "${RECIPE_DIR}/lib/cross-helpers.sh"
#
# Required variables (set by platform script before calling):
#   - PREFIX: Installation prefix
#   - PKG_VERSION: GHC version (e.g., "9.6.7")
#   - One of: ghc_target, conda_target (target triple)
# ==============================================================================

# Get the target triple (supports both naming conventions)
_get_target_triple() {
  echo "${ghc_target:-${conda_target:-}}"
}

# ==============================================================================
# Symlink Creation for Cross-Compiled Tools
# ==============================================================================
# Creates symlinks so cross-compiled tools can be invoked without target prefix.
#
# GHC bindist installs versioned wrappers like:
#   powerpc64le-unknown-linux-gnu-ghci-9.6.7
# But users expect to call just 'ghci'. We create:
#   versioned -> unversioned -> short name
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#
cross_create_symlinks() {
  local target="${1:-$(_get_target_triple)}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_create_symlinks requires target triple"
    return 1
  fi

  echo "  Creating symlinks for cross-compiled tools..."

  pushd "${PREFIX}/bin" >/dev/null

  # Standard GHC tools that need symlinks
  local tools="ghc ghci ghc-pkg hp2ps hsc2hs haddock hpc runghc"

  for bin in ${tools}; do
    local versioned="${target}-${bin}-${PKG_VERSION}"
    local unversioned="${target}-${bin}"

    # Create unversioned -> versioned symlink if versioned exists
    if [[ -f "${versioned}" ]] && [[ ! -e "${unversioned}" ]]; then
      ln -sf "${versioned}" "${unversioned}"
      echo "    ${versioned} -> ${unversioned}"
    fi

    # Create short name -> unversioned/versioned symlink
    if [[ -e "${unversioned}" ]] && [[ ! -e "${bin}" ]]; then
      ln -sf "${unversioned}" "${bin}"
      echo "    ${unversioned} -> ${bin}"
    elif [[ -f "${versioned}" ]] && [[ ! -e "${bin}" ]]; then
      # Direct link if unversioned doesn't exist
      ln -sf "${versioned}" "${bin}"
      echo "    ${versioned} -> ${bin}"
    fi
  done

  popd >/dev/null

  # Create directory symlink for libraries
  # Move target-prefixed dir to standard name and create reverse symlink
  local target_lib_dir="${PREFIX}/lib/${target}-ghc-${PKG_VERSION}"
  local standard_lib_dir="${PREFIX}/lib/ghc-${PKG_VERSION}"

  if [[ -d "${target_lib_dir}" ]] && [[ ! -d "${standard_lib_dir}" ]]; then
    mv "${target_lib_dir}" "${standard_lib_dir}"
    ln -sf "${standard_lib_dir}" "${target_lib_dir}"
    echo "    ${target}-ghc-${PKG_VERSION} -> ghc-${PKG_VERSION}"
  fi

  echo "  ✓ Symlinks created"
}

# ==============================================================================
# Fix Wrapper Scripts "./" Prefix Bug
# ==============================================================================
# GHC bindist Makefile uses 'find . ! -type d' to list wrapper files,
# which outputs './ghci' instead of 'ghci'. This "./" gets embedded in:
#   exeprog="./ghci"
#   executablename="/path/to/lib/bin/./ghci"
# causing broken paths like: $libdir/bin/./target-ghci-9.6.7
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#
cross_fix_wrapper_scripts() {
  local target="${1:-$(_get_target_triple)}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_fix_wrapper_scripts requires target triple"
    return 1
  fi

  echo "  Fixing wrapper scripts..."

  pushd "${PREFIX}/bin" >/dev/null

  local wrappers="ghc ghci ghc-pkg runghc runhaskell haddock hp2ps hsc2hs hpc"

  for wrapper in ${wrappers}; do
    # Fix target-prefixed wrapper
    local target_wrapper="${target}-${wrapper}"
    if [[ -f "${target_wrapper}" ]]; then
      # Fix both exeprog and executablename - both can have "./" prefix
      perl -pi -e 's#^(exeprog=")\./#$1#' "${target_wrapper}"
      perl -pi -e 's#(/bin/)\./#$1#' "${target_wrapper}"
    fi

    # Fix short-name wrapper (may be script or symlink - only fix if script)
    if [[ -f "${wrapper}" ]] && [[ ! -L "${wrapper}" ]]; then
      perl -pi -e 's#^(exeprog=")\./#$1#' "${wrapper}"
      perl -pi -e 's#(/bin/)\./#$1#' "${wrapper}"
    fi
  done

  popd >/dev/null
  echo "  ✓ Wrapper scripts fixed"
}

# ==============================================================================
# Fix ghci Wrapper for Cross-Compiled GHC
# ==============================================================================
# For cross-compiled GHC, ghci is NOT a separate binary - it's just 'ghc --interactive'.
# The bindist install creates a broken wrapper pointing to a non-existent ghci binary.
# Replace it with a simple script that calls ghc --interactive.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#
cross_fix_ghci_wrapper() {
  local target="${1:-$(_get_target_triple)}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_fix_ghci_wrapper requires target triple"
    return 1
  fi

  echo "  Fixing ghci wrapper to call ghc --interactive..."

  # Fix target-prefixed ghci wrapper
  local ghci_wrapper="${PREFIX}/bin/${target}-ghci"
  if [[ -f "${ghci_wrapper}" ]]; then
    cat > "${ghci_wrapper}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
    chmod +x "${ghci_wrapper}"
    echo "    Fixed ${target}-ghci"
  fi

  # Also fix short-name ghci if it's a script (not symlink)
  local short_ghci="${PREFIX}/bin/ghci"
  if [[ -f "${short_ghci}" ]] && [[ ! -L "${short_ghci}" ]]; then
    cat > "${short_ghci}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
    chmod +x "${short_ghci}"
    echo "    Fixed ghci"
  fi

  echo "  ✓ ghci wrapper fixed"
}

# ==============================================================================
# Common Post-Configure for Cross-Compilation
# ==============================================================================
# Standard system.config patching for cross-compile builds.
# Calls helper functions from helpers.sh in the correct order.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#   $2 - tools_to_prefix (optional, space-separated list of tools)
#
cross_patch_system_config() {
  local target="${1:-$(_get_target_triple)}"
  local tools="${2:-}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_patch_system_config requires target triple"
    return 1
  fi

  echo "  Patching system.config for cross-compilation..."

  # Strip BUILD_PREFIX from tool paths (exclude python - it runs on build host)
  strip_build_prefix_from_tools "python"

  # Fix Python path for cross-compile
  fix_python_path_for_cross

  # Add toolchain prefix to tools
  if [[ -n "${tools}" ]]; then
    add_toolchain_prefix_to_tools "${target}" "${tools}"
  else
    add_toolchain_prefix_to_tools "${target}"
  fi

  # Add library paths and rpath
  patch_system_config_linker_flags

  echo "  ✓ System config patched for cross-compilation"
}

# ==============================================================================
# Common Post-Install for Cross-Compilation
# ==============================================================================
# Standard post-install steps for cross-compile builds.
# Can be called directly or individual functions can be called separately.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#   $2 - options (optional): "no-wrapper-fix" to skip wrapper script fixing
#
cross_post_install() {
  local target="${1:-$(_get_target_triple)}"
  local options="${2:-}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_post_install requires target triple"
    return 1
  fi

  # Fix wrapper scripts (Linux needs this, macOS may not)
  if [[ "${options}" != *"no-wrapper-fix"* ]]; then
    cross_fix_wrapper_scripts "${target}"
  fi

  # Fix ghci wrapper
  cross_fix_ghci_wrapper "${target}"

  # Create symlinks
  cross_create_symlinks "${target}"

  # Install bash completion
  install_bash_completion
}
