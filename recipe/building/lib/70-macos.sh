#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: macOS-Specific Functions Module
# ==============================================================================
# Purpose: macOS bootstrap and platform-specific helpers
#
# Functions:
#   build_iconv_compat_dylib() - Build libiconv_compat.dylib
#   setup_macos_native_environment() - Complete macOS native setup
#   setup_macos_cross_environment(conda_host, conda_target) - macOS cross setup
#   fix_cross_architecture_defines(from_arch, to_arch) - Fix buildinfo files
#   fix_macos_bootstrap_settings(bootstrap_env_path, conda_host, ar_stage0)
#
# Dependencies: None
#
# Usage:
#   source lib/70-macos.sh
#   setup_macos_native_environment
# ==============================================================================

set -eu

# Build libiconv compatibility dynamic library for macOS
#
# macOS GHC needs explicit SDK version for compatibility with conda-forge libiconv.
# This resolves issues with missing _iconv_open when linking to conda-forge libiconv.
#
# Usage:
#   build_iconv_compat_dylib
#
# Parameters: None (uses environment variables)
#
build_iconv_compat_dylib() {
  echo "=== Building libiconv compatibility library ==="

  mkdir -p "${PREFIX}/lib/ghc-${PKG_VERSION}/lib"

  ${CC} -dynamiclib \
    -o "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib" \
    "${RECIPE_DIR}/building/osx_iconv_compat.c" \
    -L"${PREFIX}/lib" \
    -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -mmacosx-version-min=10.13 \
    -install_name "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"

  echo "  Created: ${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"
}

# Set up complete macOS native build environment
#
# Configures all macOS-specific environment variables and settings:
# - Builds libiconv_compat.dylib
# - Sets DYLD variables to override system libraries
# - Configures llvm-ar (required for macOS)
# - Patches bootstrap GHC settings if present
#
# Usage:
#   setup_macos_native_environment
#
# Parameters: None (uses environment variables)
#
setup_macos_native_environment() {
  echo "=== Setting up macOS native environment ==="

  # Build libiconv compatibility library
  build_iconv_compat_dylib

  # Preload conda libraries to override system libraries
  export DYLD_INSERT_LIBRARIES="${PREFIX}/lib/libiconv.dylib:${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"
  export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"

  echo "  DYLD_INSERT_LIBRARIES: ${DYLD_INSERT_LIBRARIES}"
  echo "  DYLD_LIBRARY_PATH: ${DYLD_LIBRARY_PATH}"

  # Use llvm-ar (only archiver that resolves odd mismatched arch when linking)
  export AR=llvm-ar
  echo "  AR: ${AR}"

  # Patch bootstrap GHC settings if present
  local bootstrap_settings=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings 2>/dev/null | head -n 1)
  if [[ -n "$bootstrap_settings" ]]; then
    echo "  Patching bootstrap settings: ${bootstrap_settings}"
    update_settings_link_flags "${bootstrap_settings}"
    set_macos_conda_ar_ranlib "${bootstrap_settings}" "${CONDA_TOOLCHAIN_BUILD}"
  fi

  echo "=== macOS native environment ready ==="
}

# Set up macOS cross-compilation environment
#
# Configures environment for cross-compiling from x86_64 to arm64:
# - Sets ac_cv_build/ac_cv_host to force darwin (not osx)
# - Configures stage0 tools for BUILD machine
# - Fixes bootstrap settings with --target flags
#
# Usage:
#   setup_macos_cross_environment "x86_64-apple-darwin13.4.0" "arm64-apple-darwin20.0.0"
#
# Parameters:
#   $1 - conda_host: BUILD machine triple (e.g., x86_64-apple-darwin13.4.0)
#   $2 - conda_target: TARGET machine triple (e.g., arm64-apple-darwin20.0.0)
#
setup_macos_cross_environment() {
  local conda_host="$1"
  local conda_target="$2"

  echo "=== Setting up macOS cross-compilation environment ==="
  echo "  BUILD (host): ${conda_host}"
  echo "  TARGET: ${conda_target}"

  # CRITICAL FIX: Force RTS configure to use darwin not osx
  # autoconf's config.sub normalizes arm64-apple-darwin to aarch64-unknown-osx
  # but GHC's configure only recognizes "darwin" not "osx"
  export ac_cv_build="x86_64-apple-darwin13.4.0"
  export ac_cv_host="aarch64-apple-darwin20.0.0"

  echo "  ac_cv_build: ${ac_cv_build}"
  echo "  ac_cv_host: ${ac_cv_host}"

  # Configure stage0 tools (BUILD machine)
  export AR_STAGE0=$(find "${BUILD_PREFIX}" -name llvm-ar | head -1)
  export CC_STAGE0="${CC_FOR_BUILD}"
  export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export AS_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-as"

  echo "  AR_STAGE0: ${AR_STAGE0}"
  echo "  CC_STAGE0: ${CC_STAGE0}"
  echo "  LD_STAGE0: ${LD_STAGE0}"

  echo "=== macOS cross-compilation environment ready ==="
}

# Fix architecture defines in buildinfo and setup-config files
#
# During cross-compilation, configure sets the wrong HOST_ARCH defines.
# This function fixes them to use the correct target architecture.
#
# Usage:
#   fix_cross_architecture_defines "x86_64" "aarch64"
#
# Parameters:
#   $1 - from_arch: Source architecture (e.g., x86_64)
#   $2 - to_arch: Target architecture (e.g., aarch64)
#
fix_cross_architecture_defines() {
  local from_arch="$1"
  local to_arch="$2"

  echo "=== Fixing architecture defines ==="
  echo "  ${from_arch}_HOST_ARCH → ${to_arch}_HOST_ARCH"

  local count=0
  find "${SRC_DIR}" -name "*.buildinfo" -o -name "setup-config" | while read -r file; do
    if [ -f "$file" ] && grep -q "${from_arch}_HOST_ARCH" "$file" 2>/dev/null; then
      perl -pi -e "s/-D${from_arch}_HOST_ARCH=1/-D${to_arch}_HOST_ARCH=1/g" "$file"
      echo "  Fixed: $file"
      count=$((count + 1))
    fi
  done

  echo "=== Fixed ${count} files ==="
}

# Fix macOS bootstrap GHC settings for conda environment
#
# The ghc-bootstrap package from conda has settings that reference system
# libraries (libiconv2.tbd) which don't exist in conda environment.
# This function patches the bootstrap settings to use conda toolchain.
#
# Usage:
#   fix_macos_bootstrap_settings "${osx_64_env}" "x86_64-apple-darwin13.4.0" "llvm-ar"
#
# Parameters:
#   $1 - bootstrap_env_path: Path to bootstrap conda environment
#   $2 - conda_host: Conda host triple (for tool prefixing)
#   $3 - ar_stage0: Path to ar command (default: llvm-ar)
#
fix_macos_bootstrap_settings() {
  local bootstrap_env_path="$1"
  local conda_host="$2"
  local ar_stage0="${3:-llvm-ar}"

  local bootstrap_settings="${bootstrap_env_path}/ghc-bootstrap/lib/ghc-9.6.7/lib/settings"

  if [[ ! -f "$bootstrap_settings" ]]; then
    echo "WARNING: Bootstrap settings not found at ${bootstrap_settings}"
    return 1
  fi

  echo "=== Fixing macOS bootstrap settings ==="
  echo "  Settings file: ${bootstrap_settings}"

  # Remove system libiconv reference (doesn't exist in conda env)
  perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${bootstrap_settings}"

  # Add -fno-lto to prevent ABI mismatches between bootstrap and final GHC
  perl -pi -e "s#(C compiler flags\", \")#\$1-v -fno-lto #" "${bootstrap_settings}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${bootstrap_settings}"
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto#" "${bootstrap_settings}"

  # Use conda toolchain instead of system tools
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${ar_stage0}#" "${bootstrap_settings}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1llvm-ranlib#" "${bootstrap_settings}"
  perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${conda_host}-\$2#" "${bootstrap_settings}"

  echo "=== Bootstrap settings updated ==="
  echo "Preview:"
  grep -E "(iconv|lto|ar command|ranlib command|clang command)" "${bootstrap_settings}" || true

  return 0
}
