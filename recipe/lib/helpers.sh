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
# Platform Detection Helpers
# ==============================================================================
# Standardized platform checks to replace scattered conditionals.
# Use these instead of inline [[ "${target_platform}" == ... ]] checks.

is_windows() { [[ "${target_platform:-}" == "win-64" ]]; }
is_linux() { [[ "${target_platform:-}" == linux-* ]]; }
is_macos() { [[ "${target_platform:-}" == osx-* ]]; }
is_unix() { ! is_windows; }
is_cross_compile() { [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]; }

# File existence guard - replaces repeated file check patterns
# Usage: file_exists_or_warn "${file}" || return 0
file_exists_or_warn() {
  [[ -f "$1" ]] && return 0
  echo "  WARNING: $1 not found, skipping"
  return 1
}

# ==============================================================================
# Shared Configure Orchestrators
# ==============================================================================
# These unified functions reduce code duplication across platforms by providing
# a single configure/post-configure implementation that auto-detects platform
# and cross-compile status. Platform scripts can use these directly or override
# for full custom behavior.

# Unified configure phase with auto-detection for platform and cross-compile
#
# This orchestrator:
#   1. Builds system config args (--prefix, --build, --host, --target)
#   2. Builds library configure args (--with-gmp-includes, etc.)
#   3. Sets platform-specific autoconf cache variables
#   4. Adds cross-compile toolchain args if needed
#   5. Runs ./configure with all assembled arguments
#
# Parameters:
#   $1 - build_triple: Build machine triple (e.g., "x86_64-unknown-linux-gnu")
#   $2 - host_triple: Host machine triple (empty for native = same as build)
#   $3 - target_triple: Target machine triple (optional, for 3-way cross)
#
# Usage:
#   # Native builds (linux-64, osx-64):
#   shared_configure_ghc "${ghc_triple}" "${ghc_triple}"
#
#   # Cross-compile (linux-cross, osx-arm64):
#   shared_configure_ghc "${ghc_build}" "${ghc_host}" "${ghc_target}"
#
# Notes:
#   - Auto-detects platform via is_linux/is_macos helpers
#   - Auto-detects cross-compile via build_platform != target_platform
#   - Requires conda_host/conda_target vars for cross-compile toolchain args
#
shared_configure_ghc() {
  local build_triple="$1"
  local host_triple="$2"
  local target_triple="${3:-}"

  echo "  Unified configure orchestrator:"
  echo "    build:  ${build_triple}"
  echo "    host:   ${host_triple}"
  [[ -n "${target_triple}" ]] && echo "    target: ${target_triple}"

  # Step 1: Build configure argument arrays
  local -a system_config configure_args

  build_system_config system_config "${build_triple}" "${host_triple}" "${target_triple}"
  build_configure_args configure_args

  # Step 2: Platform-specific autoconf cache variables
  if is_linux; then
    if is_cross_compile; then
      set_autoconf_toolchain_vars --linux --cross
    else
      set_autoconf_toolchain_vars --linux
    fi
  elif is_macos; then
    if is_cross_compile; then
      set_autoconf_toolchain_vars --macos --cross
    else
      set_autoconf_toolchain_vars --macos
    fi
  fi

  # Step 3: Cross-compile toolchain args (CC=, AR=, STAGE0 tools, sysroot)
  if is_cross_compile && [[ -n "${conda_target:-}" ]]; then
    local sysroot_opt=""
    is_linux && sysroot_opt="--sysroot"
    cross_build_toolchain_args configure_args "${conda_target}" "${conda_host:-}" "${sysroot_opt}"
  fi

  # Step 4: Run configure
  run_and_log "configure" ./configure "${system_config[@]}" "${configure_args[@]}"
}

# Unified post-configure patching with auto-detection
#
# This orchestrator handles platform-specific system.config patching after
# ./configure completes. It auto-detects the platform and cross-compile
# status to apply the correct patch sequence.
#
# Parameters:
#   $1 - toolchain_prefix: Toolchain prefix for settings patching
#        - Native Linux: GHC triple (e.g., "x86_64-unknown-linux-gnu")
#        - Native macOS: GHC triple (e.g., "x86_64-apple-darwin13.4.0")
#        - Cross-compile: Target triple (e.g., "aarch64-conda-linux-gnu")
#
# Usage:
#   # Native builds:
#   shared_post_configure_ghc "${ghc_triple}"
#
#   # Cross-compile:
#   shared_post_configure_ghc "${conda_target}"
#
# Notes:
#   - For macOS cross-compile, requires conda_host and conda_target vars
#   - Auto-detects platform via is_linux/is_macos helpers
#   - Auto-detects cross-compile via build_platform != target_platform
#
shared_post_configure_ghc() {
  local toolchain_prefix="${1:-}"
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  echo "  Unified post-configure orchestrator:"
  echo "    toolchain: ${toolchain_prefix}"

  # Platform-specific patching logic
  if is_windows; then
    # Windows: Custom patching (uses _SRC_DIR paths)
    patch_windows_system_config
  elif is_linux; then
    if is_cross_compile; then
      # Linux cross-compile: strip BUILD_PREFIX, fix python, add prefix, linker flags
      cross_patch_system_config "${toolchain_prefix}"
    else
      # Native Linux: just linker flags and doc placeholders
      patch_settings "${settings_file}" --linker-flags --doc-placeholders
    fi
  elif is_macos; then
    if is_cross_compile; then
      # macOS cross-compile: all-in-one orchestrator
      # Requires conda_host and conda_target to be set by platform script
      if [[ -z "${conda_host:-}" ]] || [[ -z "${conda_target:-}" ]]; then
        echo "  ERROR: conda_host and conda_target required for macOS cross-compile"
        return 1
      fi
      macos_cross_post_configure "${conda_host}" "${conda_target}"
    else
      # Native macOS: strip, llvm-ar, prefix, linker flags, doc placeholders
      macos_patch_system_config "${toolchain_prefix}"
    fi
  fi

  echo "  ✓ Post-configure patches applied"
}

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
  elif [[ "${target_platform:-}" == "win-64" ]]; then
    # Use conda-provided toolchain, don't download MSYS2 tarballs
    _result+=(--enable-distro-toolchain)
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
# Hadrian Binary Update
# ==============================================================================
# Updates HADRIAN_CMD after Stage1 build when a new Hadrian binary may exist.
# Cross-compile builds create a native Hadrian during Stage1 that should be
# used for Stage2 instead of the bootstrap-built version.
#
# Parameters:
#   $1 - search_dir: Directory to search (default: SRC_DIR/hadrian/dist-newstyle/build)
#
# Globals Modified:
#   HADRIAN_CMD - Updated to point to the found Hadrian binary
#
# Returns:
#   0 on success, exits with 1 if Hadrian not found
#
# Usage:
#   update_hadrian_cmd_after_build                    # Use defaults
#   update_hadrian_cmd_after_build "${custom_dir}"    # Custom search dir
#
update_hadrian_cmd_after_build() {
  local search_dir="${1:-${SRC_DIR}/hadrian/dist-newstyle/build}"
  local hadrian_name="hadrian"
  is_windows && hadrian_name="hadrian.exe"

  echo "  Updating Hadrian binary reference..."

  local hadrian_bin
  hadrian_bin=$(find "${search_dir}" -name "${hadrian_name}" -type f 2>/dev/null | head -1)

  # On Unix, also check for executable permission
  if is_unix && [[ -n "${hadrian_bin}" ]] && [[ ! -x "${hadrian_bin}" ]]; then
    hadrian_bin=""
  fi

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found in ${search_dir}"
    exit 1
  fi

  # Use appropriate source directory (Windows uses _SRC_DIR)
  local src_dir="${SRC_DIR}"
  is_windows && src_dir="${_SRC_DIR}"

  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${src_dir}")
  echo "  Updated HADRIAN_CMD: ${hadrian_bin}"
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

  # Granular hook after ghc-bin build - allows Windows to patch settings
  # before building other executables that depend on them
  call_hook "post_stage${stage}_ghc_bin"

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

  # Allow platforms to override the entire library build (e.g., Windows)
  if type -t "platform_build_stage${stage}_libraries" >/dev/null 2>&1; then
    "platform_build_stage${stage}_libraries" "${extra_opts[@]}"
    call_hook "post_stage${stage}_libraries"
    return $?
  fi

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
# Consolidated settings patching via patch_settings() with option flags:
#   --linker-flags[=PREFIX]     Add library paths and rpaths
#   --doc-placeholders          Add xelatex/sphinx-build/makeindex placeholders
#   --strip-build-prefix[=EXC]  Strip BUILD_PREFIX from tools
#   --toolchain-prefix=PREFIX   Add toolchain prefix to tools
#   --fix-python                Fix Python path for cross-compilation
#   --platform-link-flags       Add platform-specific link flags
#   --macos-ar-ranlib[=TC]      Set macOS LLVM ar/ranlib config
#   --installed                 Apply installed GHC settings transformations
#
# NOTE: Call patch_settings() directly with options (wrapper functions removed).

source "${RECIPE_DIR}/lib/settings-patch.sh"

# ==============================================================================
# Triple Configuration
# ==============================================================================
# Centralized GHC triple mappings - provides:
#   - configure_triples() - main function to set all triple variables
#   - _ghc_triple_for_platform() - internal mapping from platform to GHC triple
#
# Sets global variables:
#   - ghc_build, ghc_host, ghc_target - GHC-style triples
#   - conda_host, conda_target - Conda toolchain triples
#   - build_alias, host_alias, target_alias - Autoconf aliases
#   - host_platform - For cross-compile detection
#
# NOTE: This is sourced by helpers.sh. Platform scripts call configure_triples()
# early in their initialization to set up triple configuration.

source "${RECIPE_DIR}/lib/triple-helpers.sh"

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
  shift  # Remove hook name, remaining args passed to hook
  if type -t "${hook_name}" >/dev/null 2>&1; then
    "${hook_name}" "$@"
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

# Verify installed GHC works
# Common verification helper that handles cross-compiled binaries gracefully.
#
# Parameters:
#   $1 - expect_failure: "true" if cross-compiled binary may fail (optional)
#
# Usage:
#   verify_installed_ghc                  # Native - fail on error
#   verify_installed_ghc "true"           # Cross-compile - warning only
#
verify_installed_ghc() {
  local expect_failure="${1:-false}"

  echo "  Verifying GHC installation..."
  if "${PREFIX}/bin/ghc" --version; then
    echo "  ✓ GHC runs successfully"
    return 0
  else
    if [[ "${expect_failure}" == "true" ]]; then
      echo "  WARNING: Installed GHC failed (expected for cross-compiled binary)"
      return 0
    else
      echo "  ERROR: Installed GHC failed to run"
      return 1
    fi
  fi
}

# Verify all expected GHC binaries exist
# Complements verify_installed_ghc() which tests that ghc runs.
#
# Parameters:
#   $1 - expect_failure: "true" to allow missing binaries (warning only)
#
# Returns:
#   0 if all binaries found, 1 if any missing (unless expect_failure=true)
#
# Usage:
#   verify_installed_binaries                  # Error on missing
#   verify_installed_binaries "true"           # Warning only
#
verify_installed_binaries() {
  local expect_failure="${1:-false}"

  local bin_dir="${PREFIX}/bin"
  is_windows && bin_dir="${_PREFIX}/bin"

  local -a expected_bins
  if is_windows; then
    expected_bins=(ghc.exe ghc-pkg.exe hsc2hs.exe runghc.exe hp2ps.exe hpc.exe)
  else
    expected_bins=(ghc ghc-pkg hsc2hs runghc hp2ps hpc)
  fi

  echo "  Verifying installed binaries in ${bin_dir}:"
  local missing=0
  for bin in "${expected_bins[@]}"; do
    if [[ -f "${bin_dir}/${bin}" ]]; then
      echo "    ✓ ${bin}"
    else
      echo "    ✗ ${bin} MISSING"
      ((missing++)) || true
    fi
  done

  # Show total file count
  local file_count
  file_count=$(ls -1 "${bin_dir}" 2>/dev/null | wc -l)
  echo "  Total files in bin/: ${file_count}"

  if [[ ${missing} -gt 0 ]]; then
    if [[ "${expect_failure}" == "true" ]]; then
      echo "  WARNING: ${missing} expected binaries missing"
      return 0
    else
      echo "  ERROR: ${missing} expected binaries missing"
      return 1
    fi
  fi

  echo "  ✓ All expected binaries present"
  return 0
}

# Unified install orchestrator - auto-detects native vs cross-compile
# Delegates to bindist_install or cross_bindist_install based on build type.
#
# Parameters:
#   $1 - target: Target triple (optional, defaults to ghc_target)
#   $2 - extra_args: Additional configure arguments (optional)
#
# Usage:
#   shared_install_ghc                           # Auto-detect, use defaults
#   shared_install_ghc "${ghc_target}"           # Explicit target
#   shared_install_ghc "${target}" "CFLAGS=-O2"  # With extra args
#
shared_install_ghc() {
  local target="${1:-${ghc_target:-}}"
  local extra_args="${2:-}"

  if is_cross_compile; then
    cross_bindist_install "${target}" "${extra_args}"
  else
    bindist_install "${target}" "${extra_args}"
  fi
}

# Unified post-install verification and setup
# Handles cross-compile patches, macOS settings, verification, and completion.
#
# Parameters:
#   $1 - target: Target triple (optional, defaults to ghc_target)
#   $2 - expect_failure: "true" to allow GHC verification failure (optional)
#
# Usage:
#   shared_post_install_ghc                      # Native build
#   shared_post_install_ghc "${ghc_target}"      # Cross-compile (auto-detects)
#   shared_post_install_ghc "${target}" "true"   # Explicit expect_failure
#
shared_post_install_ghc() {
  local target="${1:-${ghc_target:-}}"
  local expect_failure="${2:-false}"

  # Cross-compile specific patches
  if is_cross_compile && type -t patch_final_settings >/dev/null 2>&1; then
    patch_final_settings
  fi

  # macOS-specific installed settings
  if is_macos; then
    patch_settings "" --installed="${target}"
    local settings_file
    settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
    if [[ -f "${settings_file}" ]]; then
      patch_settings "${settings_file}" --macos-ar-ranlib="${CONDA_TOOLCHAIN_BUILD:-}"
    fi
  fi

  # Verify and install completion
  if is_cross_compile; then
    expect_failure="true"
  fi
  verify_installed_ghc "${expect_failure}"
  install_bash_completion
}

# ==============================================================================
# Unified Stage Settings Patching
# ==============================================================================
# Single dispatch function for patching stage settings after building ghc-bin.
# Consolidates the three different mechanisms:
#   - Linux: patch_settings with --linker-flags
#   - macOS: macos_update_stage_settings (llvm-ar, link flags)
#   - Windows: granular hooks (handled separately, this is a no-op)
#
# Parameters:
#   $1 - stage_dir: Stage directory name ("stage0" or "stage1")
#
# Usage:
#   shared_patch_stage_settings "stage0"  # After Stage 1 ghc-bin
#   shared_patch_stage_settings "stage1"  # After Stage 2 ghc-bin
#
shared_patch_stage_settings() {
  local stage_dir="$1"
  local settings_file="${SRC_DIR}/_build/${stage_dir}/lib/settings"

  [[ -f "${settings_file}" ]] || return 0

  if is_macos; then
    # macOS: uses llvm-ar and platform-specific link flags
    macos_update_stage_settings "${stage_dir}"
  elif is_windows; then
    # Windows uses granular hooks (platform_post_stage{N}_ghc_bin)
    # which are called by build_stage_executables() - no-op here
    return 0
  else
    # Linux: Add library paths and rpath (idempotent - skips if already present)
    grep -q "Wl,-L${PREFIX}/lib" "${settings_file}" 2>/dev/null && return 0
    patch_settings "${settings_file}" --linker-flags
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
