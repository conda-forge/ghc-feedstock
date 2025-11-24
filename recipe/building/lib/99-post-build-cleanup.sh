#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Post-Build Cleanup (Shared)
# ==============================================================================
# Purpose: Common post-build tasks for ALL platforms
#
# This cleanup must run for every build, regardless of which build script
# or architecture is used. It handles:
#   - Bash completion installation
#   - Package cache cleanup
#   - Activation script
#   - Settings file cleanup (removes hardcoded paths)
#   - Library symlink creation
#   - License file collection
#
# Usage:
#   source "${RECIPE_DIR}/building/lib/99-post-build-cleanup.sh"
#   run_post_build_cleanup
#
# Dependencies: Expects PREFIX, PKG_VERSION, PKG_NAME, SRC_DIR, RECIPE_DIR
# ==============================================================================

set -eu

# Run all post-build cleanup tasks
#
# This function MUST be called at the end of every build, regardless of
# platform or build method. It ensures packages are properly configured
# and complete.
#
run_post_build_cleanup() {
  echo ""
  echo "=== Post-Build Cleanup ==="

  # Install bash completion
  echo "  Installing bash completion..."
  mkdir -p "${PREFIX}"/etc/bash_completion.d
  if [[ -f utils/completion/ghc.bash ]]; then
    cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc
  else
    echo "  WARNING: ghc.bash completion file not found"
  fi

  # Clean up package cache (we use ghc-pkg in activation)
  echo "  Cleaning package cache..."
  rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
  rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

  # Install activation script
  echo "  Installing activation script..."
  mkdir -p "${PREFIX}/etc/conda/activate.d"
  if [[ -f "${RECIPE_DIR}/activate.sh" ]]; then
    cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"
  else
    echo "  WARNING: activate.sh not found"
  fi

  # Cleanup hard-coded build paths in settings file
  echo "  Cleaning build paths from settings file..."
  settings_file=$(find "${PREFIX}"/lib/ -name settings 2>/dev/null | head -1)
  if [[ -n "${settings_file}" ]]; then
    # Remove absolute paths to BUILD_PREFIX and PREFIX from tool paths
    perl -pi -e "s#(${BUILD_PREFIX}|${PREFIX})/(bin|lib)/##g" "${settings_file}" 2>/dev/null || true
  else
    echo "  WARNING: settings file not found in ${PREFIX}/lib/"
  fi

  # Create symlinks for dynamic libraries (remove -ghc<version> suffix)
  echo "  Creating library symlinks..."
  local symlink_count=0
  find "${PREFIX}/lib" -name "*-ghc${PKG_VERSION}.dylib" -o -name "*-ghc${PKG_VERSION}.so" 2>/dev/null | while read -r lib; do
    base_lib="${lib//-ghc${PKG_VERSION}./.}"
    if [[ ! -e "$base_lib" ]]; then
      ln -s "$(basename "$lib")" "$base_lib"
      ((symlink_count++)) || true
    fi
  done
  if [[ $symlink_count -gt 0 ]]; then
    echo "  Created $symlink_count library symlinks"
  fi

  # Collect license files from libraries
  echo "  Collecting license files..."
  local license_count=0
  for lic_file in "${SRC_DIR}"/libraries/*/LICENSE; do
    if [[ -f "${lic_file}" ]]; then
      folder=$(dirname "${lic_file}")
      mkdir -p "${SRC_DIR}"/license_files/"${folder}"
      cp "${lic_file}" "${SRC_DIR}"/license_files/"${folder}"
      ((license_count++)) || true
    fi
  done
  if [[ $license_count -gt 0 ]]; then
    echo "  Collected $license_count license files"
  else
    echo "  WARNING: No library license files found"
  fi

  echo "  Cleanup complete"
  echo ""
}
