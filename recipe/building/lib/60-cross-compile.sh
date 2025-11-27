#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Cross-Compilation Helpers Module
# ==============================================================================
# Purpose: Cross-compilation environment setup
#
# Functions:
#   setup_cross_build_env(platform, env_name, extra_packages...)
#   build_hadrian_cross(ghc_path, ar_stage0, cc_stage0, ld_stage0, extra_cflags, extra_ldflags)
#
# Dependencies: run_and_log() from 00-logging.sh
#
# Usage:
#   source lib/60-cross-compile.sh
#   setup_cross_build_env "linux-64" "libc2.17_env" "sysroot_linux-64==2.17"
# ==============================================================================

set -eu

# Create and configure a conda environment for cross-compilation bootstrap
#
# Cross-compilation requires a bootstrap GHC and cabal that run on the
# build machine. This function creates a temporary conda environment with
# the necessary tools.
#
# Sets these global variables:
#   CROSS_ENV_PATH    - Path to created environment
#   GHC               - Path to bootstrap GHC
#   CABAL             - Path to cabal
#   CABAL_DIR         - Path to cabal configuration directory
#
# Usage:
#   setup_cross_build_env "linux-64" "libc2.17_env" "sysroot_linux-64==2.17"
#   "${GHC}" --version
#
# Parameters:
#   $1 - platform: Conda platform (e.g., "linux-64", "osx-64")
#   $2 - env_name: Name for the conda environment
#   $@ - extra_packages: Additional packages to install (rest of arguments)
#
setup_cross_build_env() {
  local platform="$1"
  local env_name="$2"
  shift 2
  local extra_packages=("$@")

  echo "=== Creating cross-compilation environment ==="
  echo "  Platform: ${platform}"
  echo "  Name: ${env_name}"
  [[ ${#extra_packages[@]} -gt 0 ]] && echo "  Extra packages: ${extra_packages[*]}"

  conda create -y \
    -n "${env_name}" \
    --platform "${platform}" \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap==9.6.7 \
    "${extra_packages[@]}"

  # Get environment path
  local env_path
  env_path=$(conda info --envs | grep "${env_name}" | awk '{print $2}')

  if [[ -z "$env_path" || ! -d "$env_path" ]]; then
    echo "ERROR: Could not find conda environment ${env_name}"
    return 1
  fi

  # Export standard variables
  export CROSS_ENV_PATH="${env_path}"
  export GHC="${env_path}/ghc-bootstrap/bin/ghc"
  export CABAL="${env_path}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}/.cabal"

  echo "  Environment created at: ${env_path}"

  # Verify GHC works
  "${GHC}" --version

  # Recache package database
  "${env_path}/ghc-bootstrap/bin/ghc-pkg" recache

  # Initialize cabal
  mkdir -p "${CABAL_DIR}"

  # Only init if config doesn't exist (avoid "already exists" error)
  if [[ ! -f "${CABAL_DIR}/config" ]]; then
    "${CABAL}" user-config init
  else
    echo "  Cabal config already exists, skipping init"
  fi

  # Update cabal package list
  run_and_log "cabal-update" "${CABAL}" v2-update

  echo "=== Cross-compilation environment ready ==="
  return 0
}

# Build Hadrian and its dependencies with correct toolchain for build machine
#
# CRITICAL: Hadrian is a BUILD TOOL that runs on the build machine (x86_64),
# NOT on the target machine (aarch64/ppc64le). Therefore:
# - MUST use BUILD machine compilers (CC_STAGE0, not CC)
# - MUST use BUILD machine CFLAGS (x86_64, not target flags)
# - MUST NOT be affected by target architecture environment variables
#
# Reference: CLAUDE.md "CRITICAL #1: Directory Package Configure Failure"
#
# Exports:
#   HADRIAN_BIN - Path to the built hadrian executable
#
# Returns:
#   stdout - Path to hadrian executable (for command substitution)
#
# Usage:
#   # Option 1: Use exported variable
#   build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}"
#   "${HADRIAN_BIN}" --version
#
#   # Option 2: Capture return value
#   HADRIAN_BUILD=$(build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}")
#   "${HADRIAN_BUILD}" --version
#
#   # With custom CFLAGS for build machine (space-separated values):
#   build_cflags="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC"
#   HADRIAN_BUILD=$(build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}" "${build_cflags}")
#
#   # IMPORTANT: Always quote variables to preserve spaces in CFLAGS/LDFLAGS
#
# Parameters:
#   $1 - ghc_path: Path to bootstrap GHC (must run on build machine)
#   $2 - ar_stage0: Path to ar for build machine
#   $3 - cc_stage0: Path to C compiler for build machine
#   $4 - ld_stage0: Path to linker for build machine
#   $5 - extra_cflags: Override CFLAGS for build machine (optional)
#   $6 - extra_ldflags: Override LDFLAGS for build machine (optional)
#
build_hadrian_cross() {
  local ghc_path="$1"
  local ar_stage0="$2"
  local cc_stage0="$3"
  local ld_stage0="$4"
  local extra_cflags="${5:-}"
  local extra_ldflags="${6:-}"

  echo "=== Building Hadrian with dependencies ===" >&2
  echo "  GHC: ${ghc_path}" >&2
  echo "  AR: ${ar_stage0}" >&2
  echo "  CC: ${cc_stage0}" >&2
  echo "  LD: ${ld_stage0}" >&2

  pushd "${SRC_DIR}/hadrian" || return 1

  # CRITICAL: Override CFLAGS/LDFLAGS if provided
  # This prevents target architecture flags from contaminating Hadrian build
  if [[ -n "$extra_cflags" ]]; then
    echo "  Overriding CFLAGS for build machine:" >&2
    echo "    ${extra_cflags}" >&2
    export CFLAGS="$extra_cflags"
  fi

  if [[ -n "$extra_ldflags" ]]; then
    echo "  Overriding LDFLAGS for build machine:" >&2
    echo "    ${extra_ldflags}" >&2
    export LDFLAGS="$extra_ldflags"
  fi

  export CABFLAGS=(--enable-shared --enable-executable-dynamic -j)

  # Build Hadrian and let cabal resolve dependencies automatically
  # Note: The dependency list was removed because it contained obsolete packages
  # (e.g., file-io, js-*, etc.) that are not needed for GHC 9.10.3's Hadrian.
  # Cabal will automatically resolve the actual dependencies from hadrian.cabal.
  #
  # CRITICAL: Use VERY short builddir path to avoid macOS exec length limits
  # The default dist-newstyle path under $SRC_DIR/hadrian/ is too long
  # Even /tmp/hb results in paths like: /tmp/hb/build/x86_64-osx/.../hadrian (83 chars)
  # macOS has strict exec path limits, so use absolute minimum
  local hadrian_builddir="/tmp/b"
  rm -rf "${hadrian_builddir}"  # Clean previous builds
  mkdir -p "${hadrian_builddir}"

  "${CABAL}" v2-build \
    --builddir="${hadrian_builddir}" \
    --with-ar="${ar_stage0}" \
    --with-gcc="${cc_stage0}" \
    --with-ghc="${ghc_path}" \
    --with-ld="${ld_stage0}" \
    -j \
    hadrian \
    2>&1 | tee "${SRC_DIR}/cabal-verbose.log"

  local exit_code=${PIPESTATUS[0]}

  popd || return 1

  if [[ $exit_code -ne 0 ]]; then
    echo "=== Cabal build FAILED with exit code ${exit_code} ===" >&2
    echo "See ${SRC_DIR}/cabal-verbose.log for details" >&2
    return 1
  fi

  # Find hadrian binary location in short builddir
  local hadrian_path
  hadrian_path=$(find "${hadrian_builddir}" -type f -name hadrian -perm /111 | head -1)

  if [[ -z "$hadrian_path" ]]; then
    echo "=== ERROR: Could not find hadrian binary ===" >&2
    return 1
  fi

  # Export for convenience
  export HADRIAN_BIN="${hadrian_path}"

  echo "=== Hadrian build completed successfully ===" >&2
  echo "  Hadrian binary: ${hadrian_path}" >&2

  # Return path for command substitution: HADRIAN_BUILD=$(build_hadrian_cross ...)
  echo "${hadrian_path}"
  return 0
}
