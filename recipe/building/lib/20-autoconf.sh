#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Autoconf Variable Management Module
# ==============================================================================
# Purpose: Set autoconf cache variables for configure scripts
#
# Functions:
#   set_autoconf_toolchain_vars(target_prefix, debug)
#   set_autoconf_macos_vars(debug)
#
# Dependencies: None
#
# Usage:
#   source lib/20-autoconf.sh
#   set_autoconf_toolchain_vars "aarch64-conda-linux-gnu"
# ==============================================================================

set -eu

# Set autoconf cache variables for GHC configure and sub-library configures
#
# CRITICAL: These variables MUST be exported globally (not in CONFIGURE_ARGS)
# because sub-library configure scripts (unix, time, directory, process, base)
# check the environment for ac_cv_* variables DURING the build.
#
# Reference: CLAUDE.md "CRITICAL #2: statx() System Call - GLIBC 2.17 Incompatibility"
#
# Autoconf variable patterns explained:
#   ac_cv_prog_XXX        - Set by AC_PROG_XXX (searches PATH)
#   ac_cv_path_XXX        - Set by AC_PATH_PROG (needs absolute path)
#   ac_cv_path_ac_pt_XXX  - Set by AC_PATH_TOOL (cross-compilation fallback)
#
# GHC's configure uses multiple detection methods, so we set all patterns
# to ensure tools are found regardless of which autoconf macro is used.
#
# Usage:
#   set_autoconf_toolchain_vars "aarch64-conda-linux-gnu"
#
# Parameters:
#   $1 - target_prefix: Tool prefix for target architecture (e.g., "aarch64-conda-linux-gnu")
#   $2 - debug: Set to "true" to print all exported variables (default: "false")
#
set_autoconf_toolchain_vars() {
  local target_prefix="$1"
  local debug="${2:-false}"

  echo "DEBUG: set_autoconf_toolchain_vars START with target_prefix='${target_prefix}'" >&2

  if [[ -z "$target_prefix" ]]; then
    echo "ERROR: set_autoconf_toolchain_vars requires target_prefix argument" >&2
    return 1
  fi

  echo "DEBUG: target_prefix check passed" >&2
  [[ "$debug" == "true" ]] && echo "=== Setting autoconf toolchain variables for: ${target_prefix}"

  # Core build tools - set ALL patterns for maximum compatibility
  # Using indirect variable expansion to get values of AR, CC, etc.
  echo "DEBUG: About to loop through tools" >&2
  for tool in AR AS CC CXX LD NM OBJDUMP RANLIB; do
    echo "DEBUG: Processing tool: ${tool}" >&2
    local tool_value="${!tool}"  # Indirect expansion: get value of $AR, $CC, etc.
    echo "DEBUG: tool_value for ${tool} = '${tool_value}'" >&2

    if [[ -n "$tool_value" ]]; then
      echo "DEBUG: Exporting ac_cv vars for ${tool}" >&2
      export ac_cv_prog_${tool}="${tool_value}"
      export ac_cv_path_${tool}="${tool_value}"
      export ac_cv_path_ac_pt_${tool}="${tool_value}"

      [[ "$debug" == "true" ]] && echo "  ac_cv_prog_${tool}=${tool_value}"
    fi
  done
  echo "DEBUG: Tool loop completed" >&2

  # LLVM tools (different naming convention)
  echo "DEBUG: Setting LLVM tools" >&2
  export ac_cv_prog_LLC="${target_prefix}-llc"
  export ac_cv_prog_OPT="${target_prefix}-opt"
  export ac_cv_prog_ac_ct_LLC="${target_prefix}-llc"
  export ac_cv_prog_ac_ct_OPT="${target_prefix}-opt"
  echo "DEBUG: LLVM tools set" >&2

  [[ "$debug" == "true" ]] && echo "  ac_cv_prog_LLC=${target_prefix}-llc"
  [[ "$debug" == "true" ]] && echo "  ac_cv_prog_OPT=${target_prefix}-opt"

  # CRITICAL: glibc 2.17 compatibility
  # statx() was added in glibc 2.28, but conda uses 2.17
  # Reference: CLAUDE.md "CRITICAL #2"
  echo "DEBUG: Setting glibc 2.17 compatibility vars" >&2
  export ac_cv_func_statx=no
  export ac_cv_have_decl_statx=no
  echo "DEBUG: glibc vars set" >&2

  [[ "$debug" == "true" ]] && echo "  ac_cv_func_statx=no (glibc 2.17 compatibility)"

  # libffi detection (often fails even when present)
  echo "DEBUG: Setting libffi detection" >&2
  export ac_cv_lib_ffi_ffi_call=yes
  echo "DEBUG: libffi set" >&2

  [[ "$debug" == "true" ]] && echo "  ac_cv_lib_ffi_ffi_call=yes"
  [[ "$debug" == "true" ]] && echo "=== Autoconf variables set successfully"
  echo "DEBUG: set_autoconf_toolchain_vars ENDING" >&2
}

# Set macOS-specific autoconf variables
#
# macOS has different tool availability and naming conventions.
# This function handles the platform-specific quirks.
#
# Usage:
#   set_autoconf_macos_vars
#
# Parameters:
#   $1 - debug: Set to "true" to print all exported variables (default: "false")
#
set_autoconf_macos_vars() {
  local debug="${1:-false}"

  [[ "$debug" == "true" ]] && echo "=== Setting macOS-specific autoconf variables"

  # Prevent autoconf from finding tools without explicit paths
  # This forces use of our conda-provided toolchain
  export ac_cv_path_ac_pt_CC=""
  export ac_cv_path_ac_pt_CXX=""

  # Explicitly set tool paths from environment (use :- for unset variables)
  export ac_cv_prog_AR="${AR:-}"
  export ac_cv_prog_CC="${CC:-}"
  export ac_cv_prog_CXX="${CXX:-}"
  export ac_cv_prog_LD="${LD:-}"
  export ac_cv_prog_RANLIB="${RANLIB:-}"

  # Also set path variants (macOS configure checks both)
  export ac_cv_path_AR="${AR:-}"
  export ac_cv_path_CC="${CC:-}"
  export ac_cv_path_CXX="${CXX:-}"
  export ac_cv_path_LD="${LD:-}"
  export ac_cv_path_RANLIB="${RANLIB:-}"

  # libffi detection
  export ac_cv_lib_ffi_ffi_call=yes

  if [[ "$debug" == "true" ]]; then
    echo "  ac_cv_prog_CC=${CC:-<unset>}"
    echo "  ac_cv_path_ac_pt_CC=<empty> (force conda toolchain)"
    echo "=== macOS autoconf variables set"
  fi

  return 0
}
