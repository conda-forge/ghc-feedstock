#!/usr/bin/env bash
# ==============================================================================
# GHC Build Helpers - Utility Functions
# ==============================================================================
# Provides utility functions for the GHC build process:
#   - Logging (run_and_log)
#   - Array builders (nameref pattern)
#   - Settings file manipulation
#   - Cross-compilation helpers
#   - Hook execution
#
# These are foundational functions used by phases.sh and platform scripts.
# ==============================================================================

set -eu

# ==============================================================================
# Common Hadrian Options
# ==============================================================================
# These options are used consistently across all stage builds.
# Platform scripts can use: "${HADRIAN_CMD[@]}" ${HADRIAN_STAGE_OPTS} ...

HADRIAN_STAGE_OPTS="--docs=none --progress-info=none"

# ==============================================================================
# Binary Distribution Installation Helper
# ==============================================================================
# Creates binary distribution and installs it using configure/make.
# Used by most platforms for consistent installation.
#
# Parameters:
#   $1 - target_triple: Target for cross-compile (empty for native)
#   $2 - extra_configure_args: Additional configure arguments (optional)
#
# Usage:
#   bindist_install                           # Native build
#   bindist_install "${ghc_target}"           # Cross-compile
#   bindist_install "" "--with-cc=clang"      # Native with extra args
#
bindist_install() {
  local target_triple="${1:-}"
  local extra_args="${2:-}"

  echo "  Creating binary distribution..."

  # Create binary distribution directory (faster than binary-dist tarball)
  run_and_log "bindist" "${HADRIAN_CMD[@]}" binary-dist-dir \
    --prefix="${PREFIX}" \
    --flavour="${FLAVOUR}" \
    --freeze1 --freeze2 \
    ${HADRIAN_STAGE_OPTS}

  # Find bindist directory
  local bindist_pattern="ghc-${PKG_VERSION}-*"
  local bindist_dir
  bindist_dir=$(find "${SRC_DIR}/_build/bindist" -maxdepth 1 -name "${bindist_pattern}" -type d | head -1)

  if [[ -z "${bindist_dir}" ]]; then
    echo "ERROR: Binary distribution directory not found"
    echo "Looking for: ${bindist_pattern} in ${SRC_DIR}/_build/bindist"
    ls -la "${SRC_DIR}/_build/bindist/" 2>/dev/null || true
    return 1
  fi

  echo "  Installing from: ${bindist_dir}"

  pushd "${bindist_dir}" >/dev/null

  # Build configure command
  local -a configure_cmd=(./configure --prefix="${PREFIX}")
  if [[ -n "${target_triple}" ]]; then
    configure_cmd+=(--target="${target_triple}")
  fi

  # Run configure
  run_and_log "configure-install" "${configure_cmd[@]}" ${extra_args} || {
    cat config.log 2>/dev/null | tail -100
    popd >/dev/null
    return 1
  }

  # Install (skip update_package_db which can fail for cross-compile)
  run_and_log "make-install" make install_bin install_lib install_man

  popd >/dev/null

  echo "  ✓ Binary distribution installed"
}

# ==============================================================================
# Logging
# ==============================================================================

_log_index=0

run_and_log() {
  local phase="$1"
  shift

  ((_log_index++)) || true
  mkdir -p "${SRC_DIR}/_logs"
  local log_file="${SRC_DIR}/_logs/$(printf "%02d" ${_log_index})-${phase}.log"

  echo "  Running: $*"
  echo "  Log: ${log_file}"

  "$@" > "${log_file}" 2>&1 || {
    local exit_code=$?
    echo ""
    echo "========================================"
    echo "*** COMMAND FAILED (exit code: ${exit_code}) ***"
    echo "*** Phase: ${phase}"
    echo "*** Log file: ${log_file}"
    echo "========================================"
    echo ""
    echo "=== FULL LOG OUTPUT ==="
    cat "${log_file}"
    echo ""
    echo "=== END LOG OUTPUT ==="
    return ${exit_code}
  }
  return 0
}

# ==============================================================================
# Array Builder Helpers (Bash 5.2+ nameref pattern)
# ==============================================================================
# These functions use `local -n` (nameref) to directly populate arrays in
# the caller's scope. This is cleaner than global variables or subshell+eval.
#
# Usage pattern:
#   declare -a MY_ARGS
#   build_configure_args MY_ARGS
#   ./configure "${MY_ARGS[@]}"
# ==============================================================================

# Build standard GHC configure arguments (--with-* flags for libraries)
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - extra_ldflags: Additional LDFLAGS to append (optional)
#
build_configure_args() {
  local -n _result="$1"
  local extra_ldflags="${2:-}"

  # Determine include/lib paths based on platform
  # Windows: ${_PREFIX}/Library/{include,lib} (conda Windows layout)
  # Unix:    ${PREFIX}/{include,lib}
  local inc_dir lib_dir
  if [[ "${target_platform:-}" == "win-64" ]]; then
    inc_dir="${_PREFIX}/Library/include"
    lib_dir="${_PREFIX}/Library/lib"
  else
    inc_dir="${PREFIX}/include"
    lib_dir="${PREFIX}/lib"
  fi

  _result+=(--with-system-libffi=yes)
  _result+=("--with-curses-includes=${inc_dir}")
  _result+=("--with-curses-libraries=${lib_dir}")
  _result+=("--with-ffi-includes=${inc_dir}")
  _result+=("--with-ffi-libraries=${lib_dir}")
  _result+=("--with-gmp-includes=${inc_dir}")
  _result+=("--with-gmp-libraries=${lib_dir}")
  _result+=("--with-iconv-includes=${inc_dir}")
  _result+=("--with-iconv-libraries=${lib_dir}")

  # Platform-specific additions
  if [[ "${target_platform:-}" == linux-* ]]; then
    _result+=(--disable-numa)
  fi

  # Optional LDFLAGS
  if [[ -n "$extra_ldflags" ]]; then
    _result+=("LDFLAGS=$extra_ldflags")
  fi
}

# Build system configuration arguments (--build, --host, --target, --prefix)
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - build_triple: Build machine triple (empty = omit)
#   $3 - host_triple: Host machine triple (empty = omit)
#   $4 - target_triple: Target machine triple (empty = omit)
#
build_system_config() {
  local -n _result="$1"
  local build_triple="${2:-}"
  local host_triple="${3:-}"
  local target_triple="${4:-}"

  # Windows: Use _PREFIX_ (C:/... mixed format) for Cabal compatibility
  # Unix: Use PREFIX directly
  local prefix_path
  if [[ "${target_platform:-}" == "win-64" ]]; then
    prefix_path="${_PREFIX_:-${_PREFIX:-${PREFIX}}}"
  else
    prefix_path="${PREFIX}"
  fi

  _result+=("--prefix=${prefix_path}")
  [[ -n "$build_triple" ]] && _result+=("--build=$build_triple")
  [[ -n "$host_triple" ]] && _result+=("--host=$host_triple")
  [[ -n "$target_triple" ]] && _result+=("--target=$target_triple")
  true  # Ensure function returns 0 (set -e safe)
}

# Build Hadrian command array with standard flags
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - hadrian_bin: Path to hadrian executable
#   $3 - jobs: Number of parallel jobs (optional, defaults to CPU_COUNT)
#
build_hadrian_cmd() {
  local -n _result="$1"
  local hadrian_bin="$2"
  local jobs="${3:-${CPU_COUNT:-1}}"

  _result=("${hadrian_bin}" "-j${jobs}" "--directory" "${SRC_DIR}")
}

# ==============================================================================
# Stage Build Helper
# ==============================================================================
# Builds standard stage components (ghc-bin, ghc-pkg, hsc2hs) in sequence.
# This consolidates the repeated pattern across platforms.
#
# Parameters:
#   $1 - stage: Stage number (1 or 2)
#   $@ - extra_opts: Additional Hadrian options (e.g., --freeze1)
#
# Usage:
#   build_stage_executables 1                    # Stage 1, no extra opts
#   build_stage_executables 2 --freeze1          # Stage 2 with freeze
#
# Note: This builds executables only. Libraries (stage<N>:lib:ghc) should be
# built separately as they often need settings patches between exe and lib.
#
build_stage_executables() {
  local stage="$1"
  shift
  local -a extra_opts=("$@")

  call_hook "pre_stage${stage}_executables"

  echo "  Building Stage ${stage} executables..."

  local -a base_opts=(--flavour="${FLAVOUR}" ${HADRIAN_STAGE_OPTS} "${extra_opts[@]}")

  run_and_log "stage${stage}-ghc"    "${HADRIAN_CMD[@]}" "${base_opts[@]}" "stage${stage}:exe:ghc-bin"
  run_and_log "stage${stage}-pkg"    "${HADRIAN_CMD[@]}" "${base_opts[@]}" "stage${stage}:exe:ghc-pkg"
  run_and_log "stage${stage}-hsc2hs" "${HADRIAN_CMD[@]}" "${base_opts[@]}" "stage${stage}:exe:hsc2hs"

  echo "  ✓ Stage ${stage} executables built"

  call_hook "post_stage${stage}_executables"
}

# Build stage libraries with retry logic
#
# The -dynamic-too flag can cause race conditions where one module tries
# to load .dyn_hi before it's fully written. Retry logic handles this.
#
# Parameters:
#   $1 - stage: Stage number (1 or 2)
#   $@ - extra_opts: Additional Hadrian options (e.g., --freeze1)
#
# Environment:
#   STAGE_LIB_RETRIES: Max retry attempts (default: 3)
#
build_stage_libraries() {
  local stage="$1"
  shift
  local -a extra_opts=("$@")
  local max_retries="${STAGE_LIB_RETRIES:-3}"
  local retry=0

  call_hook "pre_stage${stage}_libraries"

  echo "  Building Stage ${stage} libraries..."

  local -a base_opts=(--flavour="${FLAVOUR}" ${HADRIAN_STAGE_OPTS} "${extra_opts[@]}")

  # Retry loop for race condition with -dynamic-too
  while (( retry < max_retries )); do
    if run_and_log "stage${stage}-lib" "${HADRIAN_CMD[@]}" "${base_opts[@]}" "stage${stage}:lib:ghc"; then
      break
    fi
    ((retry++)) || true  # Prevent set -e exit when retry=0
    if (( retry < max_retries )); then
      echo "  Retry ${retry}/${max_retries} for stage${stage}:lib:ghc"
      sleep 2  # Brief pause before retry
    fi
  done

  if (( retry >= max_retries )); then
    echo "ERROR: stage${stage}:lib:ghc failed after ${max_retries} attempts"
    return 1
  fi

  echo "  ✓ Stage ${stage} libraries built"

  call_hook "post_stage${stage}_libraries"
}

# ==============================================================================
# Autoconf Cache Variables for Toolchain
# ==============================================================================
# Sets ac_cv_* variables for configure scripts.
# Unified helper for all platforms - call before ./configure.
#
# Parameters:
#   $1 - options: Space-separated options:
#        --linux     Add Linux-specific vars (statx=no for glibc 2.17)
#        --macos     Add macOS-specific vars (clear ac_pt_* to prevent Xcode interference)
#        --windows   Add Windows-specific vars (DLLWRAP, WINDRES)
#        --cross     Add cross-compile vars (LLC, OPT with target prefix)
#        --prefix=X  Tool prefix for LLVM tools (default: uses conda_target or empty)
#
# Usage:
#   set_autoconf_toolchain_vars --linux                    # Native Linux
#   set_autoconf_toolchain_vars --linux --cross            # Linux cross-compile
#   set_autoconf_toolchain_vars --macos                    # Native macOS
#   set_autoconf_toolchain_vars --macos --cross            # macOS cross-compile
#   set_autoconf_toolchain_vars --windows                  # Windows
#
set_autoconf_toolchain_vars() {
  local opts="$*"
  local is_linux=false is_macos=false is_windows=false
  local tool_prefix="${conda_target:-${CONDA_TOOLCHAIN_HOST:-}}"

  # Parse options
  for opt in $opts; do
    case "$opt" in
      --linux)   is_linux=true ;;
      --macos)   is_macos=true ;;
      --windows) is_windows=true ;;
      --prefix=*) tool_prefix="${opt#--prefix=}" ;;
    esac
  done

  echo "  Setting autoconf toolchain variables..."

  # Common: libffi detection (all platforms)
  export ac_cv_lib_ffi_ffi_call=yes
  export ac_cv_use_system_libffi=yes

  # Core build tools - set from environment variables
  for tool in AR AS CC CXX LD NM OBJDUMP RANLIB; do
    local tool_value="${!tool:-}"
    if [[ -n "$tool_value" ]]; then
      export ac_cv_prog_${tool}="${tool_value}"
      export ac_cv_path_${tool}="${tool_value}"
    fi
  done

  # LLVM tools - always set if prefix available (doesn't hurt if not needed)
  if [[ -n "$tool_prefix" ]]; then
    export ac_cv_prog_LLC="${tool_prefix}-llc"
    export ac_cv_prog_OPT="${tool_prefix}-opt"
    export ac_cv_prog_ac_ct_LLC="${tool_prefix}-llc"
    export ac_cv_prog_ac_ct_OPT="${tool_prefix}-opt"
  fi

  # Linux-specific: glibc 2.17 compatibility (statx added in 2.28)
  if [[ "$is_linux" == "true" ]]; then
    export ac_cv_func_statx=no
    export ac_cv_have_decl_statx=no
  fi

  # macOS-specific: clear ac_pt_* to prevent Xcode/wrong tool detection
  if [[ "$is_macos" == "true" ]]; then
    export ac_cv_path_ac_pt_CC=""
    export ac_cv_path_ac_pt_CXX=""
    export DEVELOPER_DIR=""
  fi

  # Windows-specific: additional tools
  if [[ "$is_windows" == "true" ]]; then
    [[ -n "${DLLWRAP:-}" ]] && export ac_cv_path_DLLWRAP="${DLLWRAP}"
    [[ -n "${WINDRES:-}" ]] && export ac_cv_path_WINDRES="${WINDRES}"
  fi

  echo "  ✓ Autoconf variables set"
}

# ==============================================================================
# Settings Patch Functions
# ==============================================================================
# Consolidated settings patching - see lib/settings-patch.sh for implementation

source "${RECIPE_DIR}/lib/settings-patch.sh"

# ==============================================================================
# Cross-Compilation Helpers
# ==============================================================================

# Configure native build triple for GHC
# Sets the GHC triple for native (non-cross) builds where build == host == target
#
# This function sets:
#   ghc_triple    - GHC-style triple for the native platform
#
# Environment exports:
#   build_alias   - Set to ghc_triple
#   host_alias    - Set to ghc_triple
#
# Usage:
#   configure_native_triple
#   echo "Native triple: ${ghc_triple}"
#
configure_native_triple() {
  case "${target_platform}" in
    linux-64)
      # Bootstrap GHC 9.2.8 uses 'x86_64-unknown-linux-gnu' but conda toolchain
      # uses 'x86_64-conda-linux-gnu'. Override to match bootstrap GHC.
      ghc_triple="x86_64-unknown-linux-gnu"
      ;;
    osx-64)
      ghc_triple="x86_64-apple-darwin13.4.0"
      ;;
    *)
      # Fallback: use conda's build_alias
      ghc_triple="${build_alias:-}"
      ;;
  esac

  export build_alias="${ghc_triple}"
  export host_alias="${ghc_triple}"

  echo "Native triple configuration:"
  echo "  GHC triple: ${ghc_triple}"
  echo "  build_alias: ${build_alias}"
  echo "  host_alias: ${host_alias}"
}

# Configure cross-compilation triples for GHC
# Maps conda arch names to GHC arch names and exports environment variables
#
# This function sets:
#   conda_host    - Conda's build triple (from build_alias)
#   conda_target  - Conda's host triple (from host_alias)
#   host_arch     - Architecture portion of conda_host (e.g., x86_64, aarch64)
#   target_arch   - Architecture portion of conda_target
#   ghc_host      - GHC-style host triple
#   ghc_target    - GHC-style target triple
#
# Environment exports:
#   build_alias   - Set to conda_host (or ghc_host for Linux)
#   host_alias    - Set to conda_host (or ghc_host for Linux)
#   target_alias  - Set to conda_target (or ghc_target for Linux)
#   host_platform - Set to build_platform
#
# Usage:
#   configure_cross_triples
#   echo "Building ${host_arch} -> ${target_arch}"
#
configure_cross_triples() {
  # Map conda arch names to GHC arch names
  conda_host="${build_alias}"
  conda_target="${host_alias}"

  host_arch="${conda_host%%-*}"
  target_arch="${conda_target%%-*}"

  # Generate GHC-style triples (platform-specific)
  case "${target_platform}" in
    linux-*)
      # Linux uses *-unknown-linux-gnu format
      ghc_host="${host_arch}-unknown-linux-gnu"
      ghc_target="${target_arch}-unknown-linux-gnu"
      # Linux GHC configure wants the ghc-style triples
      export build_alias="${ghc_host}"
      export host_alias="${ghc_host}"
      export target_alias="${ghc_target}"
      ;;
    osx-*)
      # macOS uses condensed darwin format
      ghc_host="${conda_host/darwin*/darwin}"
      ghc_target="${conda_target/darwin*/darwin}"
      # macOS keeps conda-style triples
      export build_alias="${conda_host}"
      export host_alias="${conda_host}"
      export target_alias="${conda_target}"
      ;;
    *)
      # Fallback for other platforms
      ghc_host="${conda_host}"
      ghc_target="${conda_target}"
      export build_alias="${conda_host}"
      export host_alias="${conda_host}"
      export target_alias="${conda_target}"
      ;;
  esac

  export host_platform="${build_platform}"

  echo "Cross-compilation configuration:"
  echo "  Build arch: ${host_arch} (${conda_host})"
  echo "  Target arch: ${target_arch} (${conda_target})"
  echo "  GHC host: ${ghc_host}"
  echo "  GHC target: ${ghc_target}"
}

# Disable Hadrian's copy optimization for cross-compilation
# By default, Hadrian tries to copy the bootstrap GHC binary instead of building
# a new one. For cross-compilation, we need to force building the cross binary.
#
# Usage:
#   disable_copy_optimization
#
disable_copy_optimization() {
  echo "  Disabling copy optimization for cross-compilation..."

  # Force building the cross binary instead of copying
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' \
    "${SRC_DIR}/hadrian/src/Rules/Program.hs"

  echo "  ✓ Copy optimization disabled"
}

# ==============================================================================
# Hook Execution Helper
# ==============================================================================

call_hook() {
  local hook_name="platform_$1"
  if type -t "${hook_name}" >/dev/null 2>&1; then
    "${hook_name}"
  fi
}

# ==============================================================================
# Post-Install Helpers
# ==============================================================================

# Install bash completion script
# Should be called from platform_post_install or default_post_install
#
# Usage:
#   install_bash_completion
#
install_bash_completion() {
  echo "  Installing bash completion..."
  mkdir -p "${PREFIX}/etc/bash_completion.d"
  if [[ -f "${SRC_DIR}/utils/completion/ghc.bash" ]]; then
    cp "${SRC_DIR}/utils/completion/ghc.bash" "${PREFIX}/etc/bash_completion.d/ghc"
    echo "  ✓ Bash completion installed"
  else
    echo "  WARNING: ghc.bash completion file not found at ${SRC_DIR}/utils/completion/ghc.bash"
  fi
}

# ==============================================================================
# Platform Utility Helpers
# ==============================================================================

# Get the script file extension for the current platform
# Returns "sh" for Unix platforms, "bat" for Windows
#
# Usage:
#   local ext=$(get_script_extension)
#   cp "activate.${ext}" "${PREFIX}/etc/conda/activate.d/"
#
get_script_extension() {
  case "${target_platform}" in
    linux-64|linux-aarch64|linux-ppc64le|osx-64|osx-arm64)
      echo "sh"
      ;;
    *)
      echo "bat"
      ;;
  esac
}
