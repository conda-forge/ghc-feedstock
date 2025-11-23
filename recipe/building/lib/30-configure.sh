#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Configure Argument Builders Module
# ==============================================================================
# Purpose: Build standard configure arguments
#
# Functions:
#   build_configure_args(result_array_name, extra_ldflags)
#   build_system_config(result_array_name, build_triple, host_triple, target_triple)
#
# Dependencies: Bash 5.2+ (for nameref support)
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
# Uses Bash 5.2+ nameref to directly modify caller's array.
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - extra_ldflags: Additional LDFLAGS to append (optional)
#
# Returns: Populates array in caller's scope via nameref
#
build_configure_args() {
  local -n result_array="$1"  # Bash 5.2+ nameref
  local extra_ldflags="${2:-}"

  # Check required environment variables
  if [[ -z "${PREFIX:-}" ]]; then
    echo "ERROR: PREFIX not set" >&2
    return 1
  fi

  # Build array directly in caller's scope
  result_array+=(--with-system-libffi=yes)
  result_array+=("--with-curses-includes=${PREFIX}/include")
  result_array+=("--with-curses-libraries=${PREFIX}/lib")
  result_array+=("--with-ffi-includes=${PREFIX}/include")
  result_array+=("--with-ffi-libraries=${PREFIX}/lib")
  result_array+=("--with-gmp-includes=${PREFIX}/include")
  result_array+=("--with-gmp-libraries=${PREFIX}/lib")
  result_array+=("--with-iconv-includes=${PREFIX}/include")
  result_array+=("--with-iconv-libraries=${PREFIX}/lib")

  # Platform-specific additions
  if [[ "${target_platform:-}" == linux-* ]]; then
    result_array+=(--disable-numa)
  fi

  # Optional LDFLAGS
  if [[ -n "$extra_ldflags" ]]; then
    result_array+=("LDFLAGS=$extra_ldflags")
  fi
}

# Build system configuration arguments (--build, --host, --target)
#
# Configure requires --build, --host, --target for cross-compilation.
# Uses Bash 5.2+ nameref to directly modify caller's array.
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - build_triple: Build machine triple (empty = omit)
#   $3 - host_triple: Host machine triple (empty = omit)
#   $4 - target_triple: Target machine triple (empty = omit)
#
# Returns: Populates array in caller's scope via nameref
#
build_system_config() {
  local -n result_array="$1"
  local build_triple="$2"
  local host_triple="$3"
  local target_triple="$4"

  # Always include --prefix
  result_array+=("--prefix=${PREFIX}")

  [[ -n "$build_triple" ]] && result_array+=("--build=$build_triple")
  [[ -n "$host_triple" ]] && result_array+=("--host=$host_triple")
  [[ -n "$target_triple" ]] && result_array+=("--target=$target_triple")
}
