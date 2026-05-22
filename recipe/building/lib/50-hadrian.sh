#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Hadrian Configuration Module
# ==============================================================================
# Purpose: Hadrian system.config manipulation
#
# Functions:
#   update_hadrian_system_config(target_prefix, stage0_overrides, ar_stage0)
#
# Dependencies: None
#
# Usage:
#   source lib/50-hadrian.sh
#   update_hadrian_system_config "aarch64-conda-linux-gnu" "false"
# ==============================================================================

set -eu

# Update hadrian/cfg/system.config with correct tool paths and library flags
#
# After configure runs, hadrian's system.config needs adjustments for:
# - Tool prefixes (aarch64-conda-linux-gnu-clang, etc.)
# - Library search paths
# - Stage-specific compiler flags
#
# Usage:
#   update_hadrian_system_config "aarch64-conda-linux-gnu" "false"
#
# Parameters:
#   $1 - target_prefix: Tool prefix for target architecture
#   $2 - stage0_overrides: Set to "true" for cross-compilation (adds --target flags)
#   $3 - ar_stage0: Override for system-ar (optional, for macOS llvm-ar)
#   $4 - host_triple: Host triple for stage0 overrides (optional, required if stage0_overrides=true)
#
update_hadrian_system_config() {
  local target_prefix="$1"
  local stage0_overrides="${2:-false}"
  local ar_stage0="${3:-}"
  local host_triple="${4:-}"

  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "$settings_file" ]]; then
    echo "ERROR: Hadrian system.config not found at ${settings_file}"
    return 1
  fi

  echo "Updating Hadrian system.config for target: ${target_prefix}"

  # Remove build prefix from all tool paths
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"

  # Platform-specific tool prefixing
  if [[ "${target_platform}" == osx-* ]]; then
    # macOS includes objdump in tool list
    local tools="ar|clang|clang\+\+|llc|nm|objdump|opt|ranlib"

    # Override system-ar with LLVM ar if provided
    if [[ -n "$ar_stage0" ]]; then
      perl -pi -e "s#(system-ar\s*?=\s).*#\$1${ar_stage0}#" "${settings_file}"
    fi
  else
    # Linux: no objdump override needed
    local tools="ar|clang|clang\+\+|llc|nm|opt|ranlib"
  fi

  perl -pi -e "s#(=\s+)(${tools})\$#\$1${target_prefix}-\$2#" "${settings_file}"

  # Add library paths for stage1 and stage2
  perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"

  # Cross-compilation: stage0 overrides
  # Stage0 tools run on build machine, need --target flag for cross
  if [[ "$stage0_overrides" == "true" ]]; then
    if [[ -z "$host_triple" ]]; then
      echo "ERROR: host_triple required when stage0_overrides=true"
      return 1
    fi
    perl -pi -e "s#(conf-cc-args-stage0\s*?=\s).*#\$1--target=${host_triple}#" "${settings_file}"
    perl -pi -e "s#(conf-gcc-linker-args-stage0\s*?=\s).*#\$1--target=${host_triple}#" "${settings_file}"
  fi

  # macOS: Additional objdump cleanup (llvm-objdump doesn't need prefix)
  if [[ "${target_platform}" == osx-* ]]; then
    perl -pi -e "s#${target_prefix}-(objdump)#\$1#" "${settings_file}"
  fi

  echo "Hadrian system.config updated. Preview:"
  head -20 "${settings_file}"
}
