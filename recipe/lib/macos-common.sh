#!/usr/bin/env bash
# ==============================================================================
# macOS Common Helper Functions
# ==============================================================================
# Shared functions for macOS GHC builds (osx-64 native, osx-arm64 cross).
# These handle common macOS-specific tasks like:
#   - iconv compatibility library creation
#   - LLVM ar/ranlib setup (required for Apple ld64)
#   - Bootstrap settings patching
#   - system.config patching for Hadrian builds
#
# Usage: source "${RECIPE_DIR}/lib/macos-common.sh"
#
# Required variables:
#   - PREFIX: Installation prefix
#   - BUILD_PREFIX: Build environment prefix
#   - PKG_VERSION: GHC version (e.g., "9.6.7")
#   - CC: C compiler path
#   - SRC_DIR: Source directory (for system.config patching)
# ==============================================================================

# ==============================================================================
# iconv Compatibility Library
# ==============================================================================
# Creates libiconv_compat.dylib to resolve missing _iconv_open when linking.
# Conda-forge's libiconv has different symbol names than macOS system libiconv.
#
# Usage:
#   macos_create_iconv_compat
#
macos_create_iconv_compat() {
  echo "  Building libiconv_compat.dylib..."

  local lib_dir="${PREFIX}/lib/ghc-${PKG_VERSION}/lib"
  mkdir -p "${lib_dir}"

  ${CC} -dynamiclib -o "${lib_dir}/libiconv_compat.dylib" \
    "${RECIPE_DIR}/support/osx_iconv_compat.c" \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -mmacosx-version-min=10.13 \
    -install_name "${lib_dir}/libiconv_compat.dylib"

  echo "  ✓ Created: ${lib_dir}/libiconv_compat.dylib"
}

# ==============================================================================
# LLVM ar Setup
# ==============================================================================
# Sets AR to llvm-ar which is required for Apple ld64 compatibility.
# GNU ar produces archives that Apple's linker cannot process correctly.
#
# Usage:
#   macos_setup_llvm_ar
#
macos_setup_llvm_ar() {
  # Find llvm-ar in BUILD_PREFIX
  local llvm_ar=$(find "${BUILD_PREFIX}" -name llvm-ar -type f 2>/dev/null | head -1)

  if [[ -n "${llvm_ar}" ]]; then
    export AR="${llvm_ar}"
    export AR_STAGE0="${llvm_ar}"
    echo "  AR set to: ${AR}"
  else
    # Fallback to just 'llvm-ar' on PATH
    export AR=llvm-ar
    export AR_STAGE0=llvm-ar
    echo "  AR set to: llvm-ar (from PATH)"
  fi
}

# ==============================================================================
# system.config Patching for Native macOS (osx-64)
# ==============================================================================
# Patches hadrian/cfg/system.config for native macOS builds.
# This is called from platform_post_configure_ghc() in osx-64.sh.
#
# Parameters:
#   $1 - toolchain: Toolchain prefix (e.g., "x86_64-apple-darwin13.4.0")
#
# Usage:
#   macos_patch_system_config "x86_64-apple-darwin13.4.0"
#
macos_patch_system_config() {
  local toolchain="${1:-${CONDA_TOOLCHAIN_HOST:-x86_64-apple-darwin13.4.0}}"
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: system.config not found at ${settings_file}, skipping patch"
    return 0
  fi

  echo "  Patching system.config for native macOS..."

  # Strip BUILD_PREFIX from tool paths (uses helper from helpers.sh)
  strip_build_prefix_from_tools

  # macOS-specific: Use llvm-ar instead of GNU ar (Apple ld64 compatibility)
  perl -pi -e 's#(=\s+)(ar)$#$1llvm-$2#' "${settings_file}"

  # Add toolchain prefix to tools (uses helper from helpers.sh)
  add_toolchain_prefix_to_tools "${toolchain}"

  # Add library paths and rpath (uses helper from helpers.sh)
  patch_system_config_linker_flags

  echo "  ✓ system.config patched for native macOS"
}

# ==============================================================================
# Cross-Compile system.config Patches for macOS arm64
# ==============================================================================
# Applies macOS-specific patches AFTER cross_patch_system_config() has been
# called. These are additional patches needed for cross-compilation to arm64.
#
# Parameters:
#   $1 - conda_host: Build host triple (e.g., "x86_64-apple-darwin13.4.0")
#   $2 - conda_target: Target triple (e.g., "arm64-apple-darwin20.0.0")
#
# Required variables:
#   - AR_STAGE0: Path to llvm-ar for stage0 builds
#   - BUILD_PREFIX: Build environment prefix
#
# Usage:
#   # After calling cross_patch_system_config()
#   macos_cross_system_config_patches "${conda_host}" "${conda_target}"
#
macos_cross_system_config_patches() {
  local conda_host="${1}"
  local conda_target="${2}"
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: system.config not found, skipping macOS cross patches"
    return 0
  fi

  echo "  Applying macOS cross-compile patches..."

  # macOS-specific: Set system-ar to llvm-ar for stage0
  perl -pi -e "s#(system-ar\\s*?=\\s).*#\$1${AR_STAGE0}#" "${settings_file}"

  # CRITICAL FIX: Clear ffi-lib-dir and iconv-lib-dir for cross-compilation
  # Problem: Hadrian's Settings/Packages.hs adds cabalExtraDirs for ghci and rts
  # packages using ffi-lib-dir. This adds -L$PREFIX/lib to ALL stages including
  # Stage0. For cross-compilation, $PREFIX/lib contains arm64 libraries, but
  # Stage0 needs x86_64 libraries. The linker finds arm64 libs first and fails:
  #   ld: warning: ignoring file $PREFIX/lib/libffi.dylib, building for macOS-x86_64
  #   but attempting to link with file built for macOS-arm64
  #   Undefined symbols: _ffi_call, _locale_charset
  #
  # Solution: Clear these settings so Hadrian doesn't add -L$PREFIX/lib.
  # Stage0 will use system/SDK libraries (/Library/Developer/.../usr/lib).
  # Stage1+ gets library paths from conf-gcc-linker-args-stage1/2.
  echo "  Clearing ffi/iconv lib dirs to prevent arm64 libs in Stage0..."
  perl -pi -e 's#^(ffi-lib-dir\s*=).*#$1#' "${settings_file}"
  perl -pi -e 's#^(iconv-lib-dir\s*=).*#$1#' "${settings_file}"

  # macOS-specific: Set stage0 compiler/linker flags for BUILD machine (x86_64)
  perl -pi -e "s#(conf-cc-args-stage0\\s*?=\\s).*#\$1--target=${conda_host}#" "${settings_file}"
  perl -pi -e "s#(conf-gcc-linker-args-stage0\\s*?=\\s).*#\$1--target=${conda_host} -Wl,-L${BUILD_PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage0\\s*?=\\s).*#\$1-L${BUILD_PREFIX}/lib -rpath ${BUILD_PREFIX}/lib#" "${settings_file}"

  # macOS-specific: Override ar command in settings
  perl -pi -e "s#(settings-ar-command\\s*?=\\s).*#\$1${conda_target}-ar#" "${settings_file}"

  # macOS-specific: objdump doesn't need prefix (undo the prefix we just added)
  perl -pi -e "s#${conda_target}-(objdump)#\$1#" "${settings_file}"

  echo "  ✓ macOS cross-compile patches applied"
}

# ==============================================================================
# Complete Cross-Compile Post-Configure Orchestrator
# ==============================================================================
# Single-call orchestrator for all macOS cross-compile post-configure patches.
# Replaces 3-step manual calls in osx-arm64.sh platform_post_configure_ghc().
#
# Parameters:
#   $1 - host: Build host triple (e.g., "x86_64-apple-darwin13.4.0")
#   $2 - target: Target triple (e.g., "arm64-apple-darwin20.0.0")
#   $3 - tools: Space-separated tool list (optional, defaults to common set)
#
# Usage:
#   macos_cross_post_configure "${conda_host}" "${conda_target}"
#
macos_cross_post_configure() {
  local host="${1}"
  local target="${2}"
  local tools="${3:-ar clang clang++ llc nm objdump opt ranlib}"

  echo "  Applying macOS cross-compile post-configure patches..."

  # Step 1: Standard cross-compile patches (from cross-helpers.sh)
  # Handles: strip BUILD_PREFIX, fix python path, add toolchain prefix, linker flags
  cross_patch_system_config "${target}" "${tools}"

  # Step 2: macOS-specific cross-compile patches
  # Handles: system-ar, ffi/iconv lib dirs, stage0 flags, ar command, objdump fix
  macos_cross_system_config_patches "${host}" "${target}"

  # Step 3: Bootstrap settings for cross mode
  # Handles: -fno-lto, BUILD_PREFIX paths, ar/ranlib commands
  macos_patch_bootstrap_settings "${host}" "cross"

  echo "  ✓ Post-configure patches complete"
}

# ==============================================================================
# Bootstrap Settings Patching
# ==============================================================================
# Patches bootstrap GHC settings for macOS builds.
# Common patches needed for both native and cross-compile builds.
#
# Parameters:
#   $1 - toolchain: Toolchain prefix (e.g., "x86_64-apple-darwin13.4.0")
#   $2 - cross_mode: Set to "cross" for cross-compilation specific patches
#
# Usage:
#   macos_patch_bootstrap_settings "x86_64-apple-darwin13.4.0"
#   macos_patch_bootstrap_settings "x86_64-apple-darwin" "cross"
#
macos_patch_bootstrap_settings() {
  local toolchain="${1:-${CONDA_TOOLCHAIN_BUILD:-x86_64-apple-darwin13.4.0}}"
  local cross_mode="${2:-}"

  echo "  Patching bootstrap settings for macOS..."

  local settings_file
  settings_file=$(find "${BUILD_PREFIX}/ghc-bootstrap" -name settings -type f 2>/dev/null | head -1)

  if [[ -z "${settings_file}" ]] || [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: Bootstrap settings not found, skipping patch"
    return 0
  fi

  echo "  Found: ${settings_file}"

  # Remove problematic libiconv2 reference (if present)
  perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${settings_file}"

  # Add -fno-lto to prevent ABI mismatches and runtime crashes
  perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"

  # Cross-compilation needs additional patching
  if [[ "${cross_mode}" == "cross" ]]; then
    # Add verbose flag to help debug cross-compile issues
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -v#' "${settings_file}"

    # Add BUILD_PREFIX library paths for stage0 linking (x86_64 libs)
    # Stage0 runs on x86_64, so it needs x86_64 libffi/libiconv from BUILD_PREFIX
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${BUILD_PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -rpath ${BUILD_PREFIX}/lib#" "${settings_file}"

    # Fix ar and ranlib commands for cross
    if [[ -n "${AR_STAGE0:-}" ]]; then
      perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR_STAGE0}#" "${settings_file}"
    fi
    perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1llvm-ranlib#" "${settings_file}"

    # Fix tool commands with host prefix
    perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${toolchain}-\$2#" "${settings_file}"
  else
    # Native mode: use helpers from helpers.sh
    if type -t update_settings_link_flags >/dev/null 2>&1; then
      update_settings_link_flags "${settings_file}"
    fi

    if type -t set_macos_conda_ar_ranlib >/dev/null 2>&1; then
      set_macos_conda_ar_ranlib "${settings_file}" "${toolchain}"
    fi
  fi

  echo "  ✓ Bootstrap settings patched"
}

# ==============================================================================
# DYLD Environment Setup
# ==============================================================================
# Sets DYLD_INSERT_LIBRARIES and DYLD_LIBRARY_PATH for macOS builds.
# This ensures conda libraries are found during the build process.
#
# Usage:
#   macos_setup_dyld_env
#
macos_setup_dyld_env() {
  local iconv_compat="${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"

  # Preload CONDA libraries to override system libraries
  if [[ -f "${iconv_compat}" ]]; then
    export DYLD_INSERT_LIBRARIES="${PREFIX}/lib/libiconv.dylib:${iconv_compat}"
  else
    export DYLD_INSERT_LIBRARIES="${PREFIX}/lib/libiconv.dylib"
  fi

  export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"

  echo "  DYLD_INSERT_LIBRARIES=${DYLD_INSERT_LIBRARIES}"
  echo "  DYLD_LIBRARY_PATH=${DYLD_LIBRARY_PATH}"
}

# ==============================================================================
# Complete macOS Environment Setup
# ==============================================================================
# Convenience function that runs all macOS setup steps.
# Call this from platform_setup_environment() for a complete setup.
#
# Parameters:
#   $1 - create_iconv: "true" to create iconv compat library (default: true)
#
# Usage:
#   macos_complete_setup
#   macos_complete_setup "false"  # Skip iconv creation (for cross-compile)
#
macos_complete_setup() {
  local create_iconv="${1:-true}"

  echo "  Running macOS common setup..."

  # Set up LLVM ar (required for Apple ld64)
  macos_setup_llvm_ar

  # Create iconv compatibility library (native builds only)
  if [[ "${create_iconv}" == "true" ]]; then
    macos_create_iconv_compat
  fi

  # Set up DYLD environment
  macos_setup_dyld_env

  # Patch bootstrap settings
  macos_patch_bootstrap_settings

  echo "  ✓ macOS common setup complete"
}
