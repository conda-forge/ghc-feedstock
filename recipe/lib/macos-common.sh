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
# Create Host Tool Symlinks for Cross-Compilation
# ==============================================================================
# Creates symlinks for ar, as, ld pointing to the host toolchain versions.
# Needed for Stage 1 build on macOS cross-compilation (osx-arm64).
#
# Parameters:
#   $1 - host_prefix (optional): Toolchain prefix, defaults to conda_host
#
# Usage:
#   macos_create_host_tool_symlinks
#   macos_create_host_tool_symlinks "x86_64-apple-darwin13.4.0"
#
macos_create_host_tool_symlinks() {
  local host_prefix="${1:-${conda_host}}"

  echo "  Creating host tool symlinks..."
  for tool in ar as ld; do
    ln -sf "${BUILD_PREFIX}/bin/${host_prefix}-${tool}" "${BUILD_PREFIX}/bin/${tool}" 2>/dev/null || true
  done
  echo "  ✓ Host tool symlinks created: ar, as, ld"
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

  # Strip BUILD_PREFIX from tool paths
  patch_settings "${settings_file}" --strip-build-prefix

  # macOS-specific: Use llvm-ar/llvm-ranlib instead of GNU ar (Apple ld64 compatibility)
  # CRITICAL: Use full path from AR env var to ensure Hadrian finds llvm-ar
  # Even though PATH includes BUILD_PREFIX/bin, explicitly using the path is safer
  local llvm_ar="${AR:-llvm-ar}"
  local llvm_ranlib="${llvm_ar/llvm-ar/llvm-ranlib}"  # Derive ranlib path from ar path

  echo "  Setting ar tools: ar=${llvm_ar}, ranlib=${llvm_ranlib}"

  # - 'ar' line: used for stage builds
  # - 'ranlib' line: used for stage builds
  # - 'system-ar' line: used by Hadrian for builds
  # - 'settings-ar-command' line: used for installed GHC (what ends up in package)
  perl -pi -e "s#(^ar\\s*=\\s*).*#\$1${llvm_ar}#" "${settings_file}"
  perl -pi -e "s#(^ranlib\\s*=\\s*).*#\$1${llvm_ranlib}#" "${settings_file}"
  perl -pi -e "s#(system-ar\\s*=\\s*).*#\$1${llvm_ar}#" "${settings_file}"
  perl -pi -e "s#(settings-ar-command\\s*=\\s*).*#\$1llvm-ar#" "${settings_file}"

  # Add toolchain prefix to tools (exclude ar/ranlib - already set to llvm-*)
  patch_settings "${settings_file}" --tools="clang clang++ llc nm opt" --toolchain-prefix="${toolchain}"

  # Add library paths and rpath
  patch_settings "${settings_file}" --linker-flags --doc-placeholders

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

  # Common operations for both modes:
  # Remove problematic libiconv2 reference (if present)
  perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${settings_file}"

  # Add -fno-lto to prevent ABI mismatches and runtime crashes
  perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"

  # Mode-specific patching via unified patch_settings()
  if [[ "${cross_mode}" == "cross" ]]; then
    # Cross-compile: verbose flag, BUILD_PREFIX paths, llvm-ar/ranlib, host tool prefixes
    patch_settings "${settings_file}" --macos-bootstrap-cross="${toolchain}"
  else
    # Native mode: platform-specific link flags and llvm ar/ranlib
    patch_settings "${settings_file}" --platform-link-flags="${toolchain}"
    patch_settings "${settings_file}" --macos-ar-ranlib="${toolchain}"
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
# ==============================================================================
# Stage Settings Update Helper
# ==============================================================================
# Updates stage settings with platform-specific link flags and ar/ranlib.
# Consolidates duplicate patterns in platform_post_stage{1,2}_executables().
#
# Parameters:
#   $1 - stage_dir: Stage directory name ("stage0" or "stage1")
#   $2 - toolchain: Toolchain prefix (optional, defaults to CONDA_TOOLCHAIN_BUILD)
#
# Usage:
#   macos_update_stage_settings "stage0"
#   macos_update_stage_settings "stage1" "${CONDA_TOOLCHAIN_BUILD}"
#
macos_update_stage_settings() {
  local stage_dir="$1"
  local toolchain="${2:-${CONDA_TOOLCHAIN_BUILD:-}}"
  local settings_file="${SRC_DIR}/_build/${stage_dir}/lib/settings"

  [[ -f "${settings_file}" ]] || return 0

  # Compound mode: platform-link-flags + macos-ar-ranlib in one call
  patch_settings "${settings_file}" --macos-stage="${toolchain}"

  # CRITICAL: Redirect FFI paths to conda-forge to avoid Apple SDK availability macros
  # The macOS SDK ffi.h (updated after Dec 2025) contains API_AVAILABLE/API_UNAVAILABLE
  # macros that break hsc2hs preprocessing. Hadrian reads ffi-include-dir from settings
  # and passes it to Cabal as --extra-include-dirs, which then passes to hsc2hs.
  # By redirecting to conda-forge libffi, we get clean headers without Apple macros.
  local ffi_prefix
  if is_cross_compile; then
    ffi_prefix="${BUILD_PREFIX}"
  else
    ffi_prefix="${PREFIX}"
  fi
  echo "  Redirecting FFI paths to ${ffi_prefix} in ${stage_dir} settings..."
  perl -pi -e "s#^(.*ffi-include-dir.*\",\\s*\")[^\"]*#\$1${ffi_prefix}/include#" "${settings_file}"
  perl -pi -e "s#^(.*ffi-lib-dir.*\",\\s*\")[^\"]*#\$1${ffi_prefix}/lib#" "${settings_file}"
}

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

  # Patch bootstrap settings (detect cross-compile mode)
  if is_cross_compile; then
    macos_patch_bootstrap_settings "${conda_host:-x86_64-apple-darwin13.4.0}" "cross"
  else
    macos_patch_bootstrap_settings
  fi

  echo "  ✓ macOS common setup complete"
}
