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
#   $3 - with_gcc: Explicit GCC path for --with-gcc (optional for cross-compile)
#   $4 - with_ar: Explicit AR path for --with-ar (optional for cross-compile)
#   $5 - with_ghc: Explicit GHC path for --with-ghc (optional, for bootstrap GHC)
#
build_hadrian_binary() {
  local -n hadrian_cmd="$1"
  local cabal_path="${2:-${BUILD_PREFIX}/bin/cabal}"
  local with_gcc="${3:-}"
  local with_ar="${4:-}"
  local with_ghc="${5:-}"

  echo "=== Building Hadrian ==="

  # Build cabal options
  local cabal_opts="-j hadrian"
  [[ -n "$with_ghc" ]] && cabal_opts="--with-ghc=${with_ghc} ${cabal_opts}"
  [[ -n "$with_gcc" ]] && cabal_opts="--with-gcc=${with_gcc} ${cabal_opts}"
  [[ -n "$with_ar" ]] && cabal_opts="--with-ar=${with_ar} ${cabal_opts}"

  run_and_log "build-hadrian" sh -c "cd '${SRC_DIR}/hadrian' && ${cabal_path} v2-build ${cabal_opts}"

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

  # Allow platform to request verbose configure (skip run_and_log wrapper)
  if [[ "${CONFIGURE_VERBOSE:-false}" == "true" ]]; then
    echo "  (Verbose mode: real-time output, will dump config.log on failure)"
    "${SRC_DIR}"/configure "${sys_cfg[@]}" "${cfg_args[@]}" || {
      echo ""
      echo "=== Configure failed! Dumping config.log ==="
      if [[ -f "${SRC_DIR}/config.log" ]]; then
        cat "${SRC_DIR}/config.log"
      else
        echo "ERROR: config.log not found at ${SRC_DIR}/config.log"
      fi
      exit 1
    }
  else
    run_and_log "ghc-configure" "${SRC_DIR}"/configure "${sys_cfg[@]}" "${cfg_args[@]}"
  fi

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
# Build Stage 1 (exe + tools + libs)
#
# Simple, complete stage1 build with race condition prevention.
# Settings patching optional - can be done before/after by caller.
#
# Parameters:
#   $1 - hadrian_cmd_array: Name of array with Hadrian command (nameref)
#   $2 - flavour: Hadrian flavour
#   $3 - settings_file: Path to settings file for patching (optional)
#
build_stage1() {
  local -n hadrian="$1"
  local flavour="$2"
  local settings_file="${3:-}"

  echo "=== Building Stage 1 Compiler ==="

  # Build compiler executable
  export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
  run_and_log "stage1_exe" "${hadrian[@]}" stage1:exe:ghc-bin --flavour="${flavour}"

  # Build tools
  run_and_log "stage1_ghc-pkg" "${hadrian[@]}" stage1:exe:ghc-pkg --flavour="${flavour}"
  run_and_log "stage1_hsc2hs" "${hadrian[@]}" stage1:exe:hsc2hs --flavour="${flavour}"

  # Patch settings if provided (before libraries)
  if [[ -n "$settings_file" ]]; then
    update_settings_link_flags "$settings_file"
  fi

  # Build libraries in dependency order (race condition prevention)
  run_and_log "stage1_ghc-prim" "${hadrian[@]}" stage1:lib:ghc-prim --flavour="${flavour}"
  run_and_log "stage1_ghc-bignum" "${hadrian[@]}" stage1:lib:ghc-bignum --flavour="${flavour}"
  run_and_log "stage1_ghc-experimental" "${hadrian[@]}" stage1:lib:ghc-experimental --flavour="${flavour}"
  run_and_log "stage1_xhtml" "${hadrian[@]}" stage1:lib:xhtml --flavour="${flavour}"
  run_and_log "stage1_lib" "${hadrian[@]}" stage1:lib:ghc --flavour="${flavour}"

  echo "=== Stage 1 Complete ==="
}


# Build Stage 2 (libs + exe)
#
# Simple, complete stage2 build with race condition prevention.
# Settings patching optional - can be done before/after by caller.
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

  echo "=== Building Stage 2 Compiler ==="

  # Build core libraries in dependency order (race condition prevention)
  # Using -VV for verbose output to diagnose issues
  echo "Building stage2:lib:ghc-prim..."
  "${hadrian[@]}" stage2:lib:ghc-prim --flavour="${flavour}" --freeze1 -VV

  echo "Building stage2:lib:ghc-bignum..."
  "${hadrian[@]}" stage2:lib:ghc-bignum --flavour="${flavour}" --freeze1 -VV

  # Build compiler executable
  echo "Building stage2:exe:ghc-bin..."
  "${hadrian[@]}" stage2:exe:ghc-bin --flavour="${flavour}" --freeze1 -VV

  # Patch stage1 settings if provided (used by stage2 compiler)
  if [[ -n "$settings_file" ]]; then
    update_settings_link_flags "$settings_file"
  fi

  # Build ghc library (used by ghci and plugins)
  echo "Building stage2:lib:ghc..."
  "${hadrian[@]}" stage2:lib:ghc --flavour="${flavour}" --freeze1 -VV

  echo "=== Stage 2 Complete ==="
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
# CRITICAL: Bindist configure must run with BUILD machine tools, not TARGET tools!
# The cross-compile build creates autoconf cache for TARGET architecture.
# This function clears all caches and resets to BUILD machine environment.
#
# Parameters:
#   $1 - tarball_path: Path to bindist tarball
#   $2 - system_config_array: Configure flags for bindist (nameref)
#   $3 - conda_host: BUILD machine triple (e.g., x86_64-conda-linux-gnu)
#   $4 - target_arch: TARGET architecture (e.g., aarch64)
#
install_bindist() {
  local tarball="$1"
  local -n sys_cfg="$2"
  local conda_host="$3"       # BUILD machine triple (e.g., x86_64-conda-linux-gnu)
  local target_arch="$4"      # TARGET architecture (e.g., aarch64)

  echo "=== Installing Binary Distribution ==="

  # Extract tarball
  local bindist_dir="${SRC_DIR}/ghc-bindist"
  mkdir -p "${bindist_dir}"
  tar -xf "${tarball}" -C "${bindist_dir}" --strip-components=1

  # CRITICAL: Reset environment for BUILD machine configuration
  # Cross-compile sets TARGET variables, bindist needs BUILD variables
  echo "  Resetting environment for BUILD machine"
  echo "  BUILD machine: ${conda_host}"
  echo "  TARGET arch: ${target_arch}"

  # Unset all TARGET architecture autoconf cache variables
  # Both ac_cv_path_* (tool paths) and ac_cv_prog_* (tool program names)
  unset ac_cv_path_AR ac_cv_path_AS ac_cv_path_CC ac_cv_path_CXX
  unset ac_cv_path_LD ac_cv_path_NM ac_cv_path_OBJDUMP ac_cv_path_RANLIB
  unset ac_cv_path_LLC ac_cv_path_OPT
  unset ac_cv_prog_AR ac_cv_prog_AS ac_cv_prog_CC ac_cv_prog_CXX
  unset ac_cv_prog_LD ac_cv_prog_NM ac_cv_prog_OBJDUMP ac_cv_prog_RANLIB
  unset ac_cv_prog_LLC ac_cv_prog_OPT

  # CRITICAL: Set target-prefixed tool cache variables to BUILD tools
  # GHC's bindist configure reads target info from the tarball and looks for target tools
  # We OVERRIDE these to force it to use BUILD machine tools instead
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_AR="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_AS="${BUILD_PREFIX}/bin/${conda_host}-as"
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_NM="${BUILD_PREFIX}/bin/${conda_host}-nm"
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_OBJDUMP="${BUILD_PREFIX}/bin/${conda_host}-objdump"
  export ac_cv_prog_${target_arch}_unknown_linux_gnu_RANLIB="${BUILD_PREFIX}/bin/${conda_host}-ranlib"

  unset ac_cv_func_statx ac_cv_have_decl_statx ac_cv_lib_ffi_ffi_call
  unset ac_cv_func_posix_spawn_file_actions_addchdir_np

  # CRITICAL: Also unset environment-based autoconf cache (ac_cv_env_*)
  # These are cached from the environment variables at configure time
  unset CFLAGS CXXFLAGS  # Will trigger unset of ac_cv_env_CFLAGS_value, ac_cv_env_CXXFLAGS_value

  # Set BUILD machine compiler, linker, and all tools
  # These MUST be set to prevent configure from looking for target-prefixed tools
  export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export AR="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export NM="${BUILD_PREFIX}/bin/${conda_host}-nm"
  export RANLIB="${BUILD_PREFIX}/bin/${conda_host}-ranlib"
  export STRIP="${BUILD_PREFIX}/bin/${conda_host}-strip"
  export OBJDUMP="${BUILD_PREFIX}/bin/${conda_host}-objdump"
  export AS="${BUILD_PREFIX}/bin/${conda_host}-as"

  # CRITICAL: Also export ac_cv_path_* to force autoconf to use BUILD tools
  # The object merging test uses these cached paths
  export ac_cv_path_CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export ac_cv_path_CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export ac_cv_path_LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export ac_cv_path_AR="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export ac_cv_path_NM="${BUILD_PREFIX}/bin/${conda_host}-nm"
  export ac_cv_path_RANLIB="${BUILD_PREFIX}/bin/${conda_host}-ranlib"
  export ac_cv_path_STRIP="${BUILD_PREFIX}/bin/${conda_host}-strip"
  export ac_cv_path_OBJDUMP="${BUILD_PREFIX}/bin/${conda_host}-objdump"
  export ac_cv_path_AS="${BUILD_PREFIX}/bin/${conda_host}-as"

  # CRITICAL: Also override ac_cv_path_ac_pt_* variables (autoconf program test)
  # These are set when configure searches PATH and finds tools
  # Without these, configure finds target-prefixed tools in PATH and uses them for MergeObjsCmd
  export ac_cv_path_ac_pt_CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export ac_cv_path_ac_pt_CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export ac_cv_path_ac_pt_LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export ac_cv_path_ac_pt_AR="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export ac_cv_path_ac_pt_NM="${BUILD_PREFIX}/bin/${conda_host}-nm"
  export ac_cv_path_ac_pt_RANLIB="${BUILD_PREFIX}/bin/${conda_host}-ranlib"
  export ac_cv_path_ac_pt_STRIP="${BUILD_PREFIX}/bin/${conda_host}-strip"
  export ac_cv_path_ac_pt_OBJDUMP="${BUILD_PREFIX}/bin/${conda_host}-objdump"
  export ac_cv_path_ac_pt_AS="${BUILD_PREFIX}/bin/${conda_host}-as"

  # Provide minimal BUILD machine library paths (not target-specific flags like -march)
  export CFLAGS=""  # Explicitly empty - no target-specific optimization flags
  export CXXFLAGS=""  # Explicitly empty
  export LDFLAGS="-L${BUILD_PREFIX}/lib"
  export CPPFLAGS="-I${BUILD_PREFIX}/include"

  # CRITICAL: Override MergeObjsCmd from bindist settings file
  # The bindist settings file contains TARGET architecture tools (aarch64-conda-linux-gnu-ld)
  # But we need BUILD architecture tools (x86_64-conda-linux-gnu-ld) for installation
  export MergeObjsCmd="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export SettingsMergeObjectsCommand="${BUILD_PREFIX}/bin/${conda_host}-ld"

  echo "  Cleared autoconf cache variables and compiler flags for bindist configure"
  echo "  CC: ${CC}"
  echo "  CXX: ${CXX}"
  echo "  LD: ${LD}"

  # Configure and install
  pushd "${bindist_dir}"
  echo "  Running bindist configure"
  ./configure "${sys_cfg[@]}" || { cat config.log; return 1; }

  echo "  Installing to ${PREFIX}"
  make install
  popd

  echo "=== Bindist Installation Complete ==="
}
