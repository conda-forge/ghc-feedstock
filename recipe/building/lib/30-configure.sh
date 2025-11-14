#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Configure Argument Builders Module
# ==============================================================================
# Purpose: Build standard configure arguments
#
# Functions:
#   build_configure_args(result_array, extra_ldflags)
#   build_system_config(result_array, build_triple, host_triple, target_triple)
#
# Dependencies: None
#
# Usage:
#   source lib/30-configure.sh
#   declare -a CONFIGURE_ARGS
#   build_configure_args CONFIGURE_ARGS
#   ./configure "${CONFIGURE_ARGS[@]}"
# ==============================================================================

set -eu

# Build standard GHC configure arguments (--with-* flags)
#
# All platforms use the same set of --with-* flags to specify library locations.
# This function populates an array with these standard arguments.
#
# Usage:
#   declare -a CONFIGURE_ARGS
#   build_configure_args CONFIGURE_ARGS
#   ./configure "${CONFIGURE_ARGS[@]}"
#
# Parameters:
#   $1 - Name of array variable to populate (passed by reference)
#   $2 - extra_ldflags: Additional LDFLAGS to append (optional)
#
build_configure_args() {
  local array_name="$1"
  local extra_ldflags="${2:-}"

  # Use eval to set caller's array (compatible with Bash 3.2+)
  eval "$array_name=(
    --with-system-libffi=yes
    --with-curses-includes=\"\${PREFIX}/include\"
    --with-curses-libraries=\"\${PREFIX}/lib\"
    --with-ffi-includes=\"\${PREFIX}/include\"
    --with-ffi-libraries=\"\${PREFIX}/lib\"
    --with-gmp-includes=\"\${PREFIX}/include\"
    --with-gmp-libraries=\"\${PREFIX}/lib\"
    --with-iconv-includes=\"\${PREFIX}/include\"
    --with-iconv-libraries=\"\${PREFIX}/lib\"
  )"

  # Platform-specific additions
  if [[ "${target_platform}" == linux-* ]]; then
    eval "$array_name+=(--disable-numa)"
  fi

  # Optional LDFLAGS
  if [[ -n "$extra_ldflags" ]]; then
    eval "$array_name+=(LDFLAGS=\"$extra_ldflags\")"
  fi
}

# Build system configuration arguments (--build, --host, --target)
#
# Configure requires --build, --host, --target for cross-compilation.
# This function generates the appropriate flags based on provided triples.
#
# Usage:
#   declare -a SYSTEM_CONFIG
#   build_system_config SYSTEM_CONFIG "x86_64-unknown-linux-gnu" "" "aarch64-unknown-linux-gnu"
#   ./configure "${SYSTEM_CONFIG[@]}"
#
# Parameters:
#   $1 - Name of array variable to populate (passed by reference)
#   $2 - build_triple: Build machine triple (empty = omit)
#   $3 - host_triple: Host machine triple (empty = omit)
#   $4 - target_triple: Target machine triple (empty = omit)
#
build_system_config() {
  local array_name="$1"
  local build_triple="$2"
  local host_triple="$3"
  local target_triple="$4"

  # Use eval to set caller's array (compatible with Bash 3.2+)
  eval "$array_name=(--prefix=\"\${PREFIX}\")"

  [[ -n "$build_triple" ]] && eval "$array_name+=(--build=\"$build_triple\")"
  [[ -n "$host_triple" ]] && eval "$array_name+=(--host=\"$host_triple\")"
  [[ -n "$target_triple" ]] && eval "$array_name+=(--target=\"$target_triple\")"
}
