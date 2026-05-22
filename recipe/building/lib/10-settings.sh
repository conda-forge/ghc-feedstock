#!/usr/bin/env bash
# ==============================================================================
# GHC Conda-Forge Build: Settings Patching Module
# ==============================================================================
# Purpose: Patch GHC settings files to use conda toolchain and libraries
#
# Functions:
#   set_macos_conda_ar_ranlib(settings_file, toolchain)
#   update_settings_link_flags(settings_file, toolchain, prefix)
#   update_installed_settings(toolchain)
#   update_linux_link_flags(settings_file)
#   update_osx_link_flags(settings_file)
#
# Dependencies: None
#
# Usage:
#   source lib/10-settings.sh
#   update_settings_link_flags "${SRC_DIR}/_build/stage0/lib/settings"
# ==============================================================================

set -eu

# Function to set the conda ar/ranlib for OSX
set_macos_conda_ar_ranlib() {
  local settings_file="$1"
  local toolchain="${2:-x86_64-apple-darwin13.4.0}"

  if [[ -f "$settings_file" ]]; then
    if [[ "$(basename "${settings_file}")" == "default."* ]]; then
      # Use LLVM ar instead of GNU ar for compatibility with Apple ld64
      perl -i -pe 's#(arMkArchive\s*=\s*).*#$1Program {prgPath = "llvm-ar", prgFlags = ["qcs"]}#g' "${settings_file}"
      perl -i -pe 's#((arIsGnu|arSupportsAtFile)\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe 's#(arNeedsRanlib\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe 's#(tgtRanlib\s*=\s*).*#$1Nothing#g' "${settings_file}"
    else
      # Use LLVM ar instead of GNU ar for compatibility with Apple ld64
      perl -i -pe 's#("ar command", ")[^"]*#$1llvm-ar#g' "${settings_file}"
      perl -i -pe 's#("ar flags", ")[^"]*#$1qcs#g' "${settings_file}"
      perl -i -pe "s#(\"(clang|llc|opt|ranlib) command\", \")[^\"]*#\$1${toolchain}-\$2#g" "${settings_file}"
    fi
  else
    echo "Error: $settings_file not found!"
    exit 1
  fi
}

# Patch macOS settings file (link flags + ar/ranlib)
# Combines update_settings_link_flags + set_macos_conda_ar_ranlib
patch_macos_settings() {
  local settings_file="$1"
  local toolchain="${2:-${CONDA_TOOLCHAIN_BUILD}}"

  update_settings_link_flags "${settings_file}"
  set_macos_conda_ar_ranlib "${settings_file}" "${toolchain}"
}

update_settings_link_flags() {
  local settings_file="$1"
  local toolchain="${2:-$CONDA_TOOLCHAIN_HOST}"
  local prefix="${3:-$PREFIX}"

  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"

    # PowerPC 64-bit little-endian: Must use ABI v2 (not v1 which has .opd sections)
    if [[ "${TARGET_ARCH:-${target_arch:-}}" == *"ppc64le"* || "${TARGET_ARCH:-${target_arch:-}}" == *"powerpc64le"* || "${host_alias}" == *"ppc64le"* || "${target_platform}" == *"ppc64le"* ]]; then
      perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -v -mabi=elfv2#' "${settings_file}"
      perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -v -mabi=elfv2#' "${settings_file}"
    fi

    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${prefix}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${prefix}/lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${prefix}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${prefix}/lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    # Don't add -fuse-ld=lld during build (bootstrap compiler doesn't support it)
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-arm64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    # Don't add -fuse-ld=lld during build (bootstrap compiler doesn't support it)
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fuse-ld=lld -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
  fi

  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${settings_file}"
}

update_installed_settings() {
  local toolchain="${1:-$CONDA_TOOLCHAIN_HOST}"

  # Extract architecture from toolchain (e.g., "aarch64" from "aarch64-conda-linux-gnu")
  local arch="${toolchain%%-*}"

  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/${arch}-linux-ghc-${PKG_VERSION} -Wl,-rpath,\\\$topdir/${arch}-linux-ghc-${PKG_VERSION} -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \")#\$1-L\\\$topdir/${arch}-linux-ghc-${PKG_VERSION} -rpath \\\$topdir/${arch}-linux-ghc-${PKG_VERSION} -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-"* ]]; then
    perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"
    perl -i -pe "s#(C\\+\\+ compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"

    # CRITICAL FIX: First append our flags, THEN remove dangerous ones (order matters!)
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -fuse-ld=lld -fno-lto -fno-use-linker-plugin -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib -liconv -Wl,-L\\\$topdir/../lib -Wl,-rpath,\\\$topdir/../lib -liconv_compat#" "${settings_file}"

    # Remove dangerous macOS-specific linker flags that cause runtime crashes
    # -undefined dynamic_lookup: Causes "strange closure type 0" errors because closure info tables
    #                            may not be properly linked, leading to uninitialized type tags (GC reads type=0)
    # -dead_strip: May incorrectly remove closure info tables that linker thinks are "unused"
    # These flags are added by GHC's default macOS configuration but are incompatible with GHC's closure model
    # Use more aggressive matching: handle variations in whitespace and word boundaries
    perl -i -pe "s#\\s*-undefined\\s+dynamic_lookup\\s*# #g" "${settings_file}"
    perl -i -pe "s#\\s*-dead_strip(_dylibs)?\\s*# #g" "${settings_file}"
  fi

  perl -pi -e "s#(-Wl,-L${BUILD_PREFIX}/lib|-Wl,-L${PREFIX}/lib|-Wl,-rpath,${BUILD_PREFIX}/lib|-Wl,-rpath,${PREFIX}/lib)##g" "${settings_file}"
  perl -pi -e "s#(-L${BUILD_PREFIX}/lib|-L${PREFIX}/lib|-rpath ${PREFIX}/lib|-rpath ${BUILD_PREFIX}/lib)##g" "${settings_file}"

  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${settings_file}"
}

update_linux_link_flags() {
  local settings_file="$1"

  # Base compiler flags for all Linux platforms
  perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"

  # PowerPC 64-bit little-endian: Must use ABI v2 (not v1 which has .opd sections)
  # The -mabi=elfv2 flag explicitly tells the compiler AND assembler to use ELF v2 ABI
  # This prevents "error: .opd not allowed in ABI version 2" linker errors
  # CRITICAL: Assembly files (.S) need this flag passed to BOTH preprocessor and assembler
  # For .S files, GHC uses -optc for preprocessor, but we need -Wa, to pass to assembler
  if [[ "${TARGET_ARCH:-${target_arch:-}}" == *"ppc64le"* || "${TARGET_ARCH:-${target_arch:-}}" == *"powerpc64le"* || "${host_alias}" == *"ppc64le"* || "${target_platform}" == *"ppc64le"* ]]; then
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -mabi=elfv2 -Wa,-mabi=elfv2#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -mabi=elfv2 -Wa,-mabi=elfv2#' "${settings_file}"
    # Also update Haskell CPP flags for .S file preprocessing
    perl -pi -e 's#(Haskell CPP flags", "[^"]*)#$1 -mabi=elfv2#' "${settings_file}"
  fi

  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${PREFIX}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${CONDA_TOOLCHAIN_HOST}-\$1\"#" "${settings_file}"
}

update_osx_link_flags() {
  local settings_file="$1"

  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${PREFIX}/lib -Wl,-liconv -Wl,-L${PREFIX}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${PREFIX}/lib -liconv -L${PREFIX}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
}
