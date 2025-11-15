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
# This function prints array elements that caller can capture via readarray/mapfile.
#
# Bash 3.2 Compatible Usage:
#   # Method 1: Using command substitution and word splitting
#   CONFIGURE_ARGS=($(build_configure_args))
#
#   # Method 2: Using while read loop (safer for args with spaces)
#   declare -a CONFIGURE_ARGS
#   while IFS= read -r arg; do
#     CONFIGURE_ARGS+=("$arg")
#   done < <(build_configure_args)
#
# Parameters:
#   $1 - extra_ldflags: Additional LDFLAGS to append (optional)
#
# Returns: Prints one argument per line to stdout
#
build_configure_args() {
  local extra_ldflags="${1:-}"

  echo "DEBUG: build_configure_args called" >&2

  # Check required environment variables
  if [[ -z "${PREFIX:-}" ]]; then
    echo "ERROR: PREFIX not set" >&2
    return 1
  fi

  echo "DEBUG: PREFIX is set to: ${PREFIX}" >&2
  echo "DEBUG: target_platform is: ${target_platform:-UNSET}" >&2

  # Print each argument on a separate line
  # Caller will capture these via command substitution or read loop
  printf '%s\n' --with-system-libffi=yes
  printf '%s\n' "--with-curses-includes=${PREFIX}/include"
  printf '%s\n' "--with-curses-libraries=${PREFIX}/lib"
  printf '%s\n' "--with-ffi-includes=${PREFIX}/include"
  printf '%s\n' "--with-ffi-libraries=${PREFIX}/lib"
  printf '%s\n' "--with-gmp-includes=${PREFIX}/include"
  printf '%s\n' "--with-gmp-libraries=${PREFIX}/lib"
  printf '%s\n' "--with-iconv-includes=${PREFIX}/include"
  printf '%s\n' "--with-iconv-libraries=${PREFIX}/lib"

  # Platform-specific additions
  if [[ "${target_platform:-}" == linux-* ]]; then
    echo "DEBUG: Adding --disable-numa for linux platform" >&2
    printf '%s\n' --disable-numa
  fi

  # Optional LDFLAGS
  if [[ -n "$extra_ldflags" ]]; then
    echo "DEBUG: Adding LDFLAGS: $extra_ldflags" >&2
    printf '%s\n' "LDFLAGS=$extra_ldflags"
  fi

  echo "DEBUG: build_configure_args completed successfully" >&2
  return 0
}

# Build system configuration arguments (--build, --host, --target)
#
# Configure requires --build, --host, --target for cross-compilation.
# This function generates the appropriate flags based on provided triples.
#
# Bash 3.2 Compatible Usage:
#   SYSTEM_CONFIG=($(build_system_config "x86_64-unknown-linux-gnu" "" "aarch64-unknown-linux-gnu"))
#   ./configure "${SYSTEM_CONFIG[@]}"
#
# Parameters:
#   $1 - build_triple: Build machine triple (empty = omit)
#   $2 - host_triple: Host machine triple (empty = omit)
#   $3 - target_triple: Target machine triple (empty = omit)
#
# Returns: Prints one argument per line to stdout
#
build_system_config() {
  local build_triple="$1"
  local host_triple="$2"
  local target_triple="$3"

  # Always include --prefix
  printf '%s\n' "--prefix=${PREFIX}"

  [[ -n "$build_triple" ]] && printf '%s\n' "--build=$build_triple"
  [[ -n "$host_triple" ]] && printf '%s\n' "--host=$host_triple"
  [[ -n "$target_triple" ]] && printf '%s\n' "--target=$target_triple"
}
