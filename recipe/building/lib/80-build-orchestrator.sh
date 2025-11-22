#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Build Orchestrator Module
# ==============================================================================
# Purpose: Centralized GHC build flow orchestration
#
# Functions:
#   build_hadrian_binary() - Build and locate Hadrian
#   configure_ghc(system_config_array, configure_args_array) - Run GHC configure
#   build_stage1_libs(hadrian_cmd_array, flavour) - Build stage1 libraries in order
#   build_stage1_tools(hadrian_cmd_array, flavour) - Build stage1 tools
#   build_stage2_libs(hadrian_cmd_array, flavour) - Build stage2 libraries
#   build_stage2_exe(hadrian_cmd_array, flavour) - Build stage2 compiler
#   install_ghc(hadrian_cmd_array, flavour) - Install to PREFIX
#   create_bindist(hadrian_cmd_array, flavour) - Create binary distribution
#
# Dependencies: Bash 5.2+, run_and_log from 00-logging.sh
#
# Usage:
#   source lib/80-build-orchestrator.sh
#   build_hadrian_binary
#   configure_ghc SYSTEM_CONFIG CONFIGURE_ARGS
#   build_stage1_libs HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
#   install_ghc HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
# ==============================================================================

set -eu

# Build Hadrian binary and return array command for subsequent builds
#
# This function handles the common pattern of:
# 1. Build Hadrian with cabal
# 2. Find the binary location
# 3. Set up Hadrian command array
#
# Returns via nameref: Array with Hadrian command + standard flags
#
# Parameters:
#   $1 - result_array_name: Name of array variable for Hadrian command (nameref)
#   $2 - cabal_path: Path to cabal executable (optional, defaults to BUILD_PREFIX/bin/cabal)
#
build_hadrian_binary() {
  local -n hadrian_cmd="$1"
  local cabal_path="${2:-${BUILD_PREFIX}/bin/cabal}"

  echo "=== Building Hadrian ==="
  run_and_log "build-hadrian" sh -c "cd '${SRC_DIR}/hadrian' && ${cabal_path} v2-build -j hadrian"

  # Find Hadrian binary
  local hadrian_bin
  hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f -perm /111 | head -1)

  if [[ -z "${hadrian_bin}" ]]; then
    echo "ERROR: Could not find hadrian binary after build"
    echo "Expected location: ${SRC_DIR}/hadrian/dist-newstyle/build/*/ghc-*/hadrian-*/*/build/hadrian/hadrian"
    return 1
  fi

  echo "  Hadrian binary: ${hadrian_bin}"
  "${hadrian_bin}" --version

  # Build command array for caller
  hadrian_cmd=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

  echo "=== Hadrian ready ==="
}

# Run GHC configure with provided arguments
#
# Parameters:
#   $1 - system_config_array: Name of array with --build/--host/--target flags (nameref)
#   $2 - configure_args_array: Name of array with --with-* flags (nameref)
#
configure_ghc() {
  local -n sys_cfg="$1"
  local -n cfg_args="$2"

  echo "=== Running GHC Configure ==="
  run_and_log "ghc-configure" "${SRC_DIR}"/configure "${sys_cfg[@]}" "${cfg_args[@]}"
  echo "=== Configure Complete ==="
}

# Build Stage 1 core libraries in dependency order
#
# This prevents Hadrian parallel build race conditions by building
# libraries in explicit dependency order:
#   ghc-prim → ghc-bignum → ghc
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour (e.g., "release", "quick")
#   $3 - settings_file: Path to settings file for patching (optional)
#
build_stage1_libs() {
  local -n hadrian="$1"
  local flavour="$2"
  local settings_file="${3:-}"

  echo "=== Building Stage 1 Libraries ==="

  # Patch settings before building (if provided)
  if [[ -n "$settings_file" ]]; then
    update_settings_link_flags "$settings_file"
  fi

  # Build libraries in dependency order (race condition prevention)
  echo "  Building libraries explicitly (race condition prevention)"
  run_and_log "stage1_ghc-prim" "${hadrian[@]}" stage1:lib:ghc-prim --flavour="${flavour}"
  run_and_log "stage1_ghc-bignum" "${hadrian[@]}" stage1:lib:ghc-bignum --flavour="${flavour}"
  run_and_log "stage1_lib" "${hadrian[@]}" stage1:lib:ghc --flavour="${flavour}"

  # Patch settings again after library build (if provided)
  if [[ -n "$settings_file" ]]; then
    update_settings_link_flags "$settings_file"
  fi

  echo "=== Stage 1 Libraries Complete ==="
}

# Build Stage 1 tools
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#
build_stage1_tools() {
  local -n hadrian="$1"
  local flavour="$2"

  echo "=== Building Stage 1 Tools ==="
  run_and_log "stage1_ghc-pkg" "${hadrian[@]}" stage1:exe:ghc-pkg --flavour="${flavour}"
  run_and_log "stage1_hsc2hs" "${hadrian[@]}" stage1:exe:hsc2hs --flavour="${flavour}"
  echo "=== Stage 1 Tools Complete ==="
}

# Build Stage 1 complete (libs + exe + tools)
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#   $3 - settings_file: Path to stage0 settings file for patching (optional)
#
build_stage1() {
  local -n hadrian="$1"
  local flavour="$2"
  local settings_file="${3:-}"

  echo "=== Building Stage 1 Compiler ==="

  # Build stage 1 compiler executable first
  export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
  run_and_log "stage1_exe" "${hadrian[@]}" stage1:exe:ghc-bin --flavour="${flavour}"

  # Build libraries
  build_stage1_libs "$1" "$flavour" "$settings_file"

  # Build tools
  build_stage1_tools "$1" "$flavour"

  echo "=== Stage 1 Complete ==="
}

# Build Stage 2 core libraries in dependency order
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#
build_stage2_libs() {
  local -n hadrian="$1"
  local flavour="$2"

  echo "=== Building Stage 2 Libraries ==="
  echo "  Building libraries explicitly (race condition prevention)"
  run_and_log "stage2_ghc-prim" "${hadrian[@]}" stage2:lib:ghc-prim --flavour="${flavour}" --freeze1
  run_and_log "stage2_ghc-bignum" "${hadrian[@]}" stage2:lib:ghc-bignum --flavour="${flavour}" --freeze1
  echo "=== Stage 2 Libraries Complete ==="
}

# Build Stage 2 compiler executable
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#   $3 - settings_file: Path to stage1 settings file for patching (optional)
#
build_stage2_exe() {
  local -n hadrian="$1"
  local flavour="$2"
  local settings_file="${3:-}"

  echo "=== Building Stage 2 Compiler ==="
  run_and_log "stage2_exe" "${hadrian[@]}" stage2:exe:ghc-bin --flavour="${flavour}" --freeze1

  # Patch stage 1 settings (used by stage 2 compiler)
  if [[ -n "$settings_file" ]]; then
    update_settings_link_flags "$settings_file"
  fi

  # Build stage 2 ghc library (used by ghci and plugins)
  run_and_log "stage2_lib" "${hadrian[@]}" stage2:lib:ghc --flavour="${flavour}" --freeze1

  echo "=== Stage 2 Compiler Complete ==="
}

# Build complete Stage 2 (libs + exe)
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#   $3 - settings_file: Path to stage1 settings file for patching (optional)
#
build_stage2() {
  local -n hadrian="$1"
  local flavour="$2"
  local settings_file="${3:-}"

  build_stage2_libs "$1" "$flavour"
  build_stage2_exe "$1" "$flavour" "$settings_file"
}

# Install GHC to PREFIX (native builds)
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#   $3 - docs: Build docs? "none" or "html" (optional, default: "none")
#
install_ghc() {
  local -n hadrian="$1"
  local flavour="$2"
  local docs="${3:-none}"

  echo "=== Installing GHC to ${PREFIX} ==="
  run_and_log "install" \
    "${hadrian[@]}" install \
    --prefix="${PREFIX}" \
    --flavour="${flavour}" \
    --freeze1 \
    --freeze2 \
    --docs="${docs}"

  # Update installed settings file
  update_installed_settings "${PREFIX}"

  echo "=== Installation Complete ==="
}

# Create binary distribution (cross-compile builds)
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#   $3 - result_var_name: Name of variable to store bindist path (nameref)
#
create_bindist() {
  local -n hadrian="$1"
  local flavour="$2"
  local -n bindist_path="$3"

  echo "=== Creating Binary Distribution ==="
  run_and_log "binary-dist" \
    "${hadrian[@]}" binary-dist \
    --flavour="${flavour}" \
    --freeze1 \
    --freeze2

  # Find the created tarball
  local tarball
  tarball=$(find "${SRC_DIR}"/_build/bindist -name 'ghc-*.tar.xz' -type f | head -1)

  if [[ -z "$tarball" ]]; then
    echo "ERROR: Could not find binary distribution tarball"
    return 1
  fi

  echo "  Binary distribution: ${tarball}"
  bindist_path="$tarball"

  echo "=== Binary Distribution Complete ==="
}

# Extract and configure bindist (cross-compile workflow)
#
# Parameters:
#   $1 - tarball_path: Path to bindist tarball
#   $2 - system_config_array: Configure flags for bindist (nameref)
#
install_bindist() {
  local tarball="$1"
  local -n sys_cfg="$2"

  echo "=== Installing Binary Distribution ==="

  # Extract tarball
  local bindist_dir="${SRC_DIR}/ghc-bindist"
  mkdir -p "${bindist_dir}"
  tar -xf "${tarball}" -C "${bindist_dir}" --strip-components=1

  # CRITICAL: Reset environment for BUILD machine configuration
  # Cross-compile sets TARGET variables, bindist needs BUILD variables
  echo "  Resetting environment for BUILD machine"

  # Unset all TARGET architecture autoconf cache variables
  unset ac_cv_path_AR ac_cv_path_AS ac_cv_path_CC ac_cv_path_CXX
  unset ac_cv_path_LD ac_cv_path_NM ac_cv_path_OBJDUMP ac_cv_path_RANLIB
  unset ac_cv_path_LLC ac_cv_path_OPT
  unset ac_cv_prog_AR ac_cv_prog_AS ac_cv_prog_CC ac_cv_prog_CXX
  unset ac_cv_prog_LD ac_cv_prog_NM ac_cv_prog_OBJDUMP ac_cv_prog_RANLIB
  unset ac_cv_prog_LLC ac_cv_prog_OPT
  unset ac_cv_func_statx ac_cv_have_decl_statx ac_cv_lib_ffi_ffi_call
  unset ac_cv_func_posix_spawn_file_actions_addchdir_np

  # Unset CFLAGS/CXXFLAGS to prevent autoconf caching (ac_cv_env_*)
  unset CFLAGS CXXFLAGS

  # Set BUILD machine compiler and minimal flags
  local build_host="${host_arch:-x86_64}-conda-linux-gnu"
  export CC="${BUILD_PREFIX}/bin/${build_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${build_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${build_host}-ld"
  export AR="${BUILD_PREFIX}/bin/${build_host}-ar"
  export NM="${BUILD_PREFIX}/bin/${build_host}-nm"
  export RANLIB="${BUILD_PREFIX}/bin/${build_host}-ranlib"
  export STRIP="${BUILD_PREFIX}/bin/${build_host}-strip"
  export OBJDUMP="${BUILD_PREFIX}/bin/${build_host}-objdump"
  export AS="${BUILD_PREFIX}/bin/${build_host}-as"

  # Minimal flags without target-specific optimizations
  export CFLAGS=""
  export CXXFLAGS=""
  export LDFLAGS="-L${BUILD_PREFIX}/lib"
  export CPPFLAGS="-I${BUILD_PREFIX}/include"

  # Configure and install
  pushd "${bindist_dir}"
  echo "  Running bindist configure"
  ./configure "${sys_cfg[@]}" || { cat config.log; return 1; }

  echo "  Installing to ${PREFIX}"
  make install
  popd

  echo "=== Bindist Installation Complete ==="
}
