#!/usr/bin/env bash
# ==============================================================================
# Unified Settings Patch Function
# ==============================================================================
# Consolidated settings patching with mode-based dispatch.
# Replaces 7 separate functions with a single unified interface.
#
# Usage:
#   patch_settings <file> [options...]
#
# Atomic Options:
#   --linker-flags[=PREFIX]     Add library paths and rpaths (default: $PREFIX)
#   --doc-placeholders          Add xelatex/sphinx-build/makeindex placeholders
#   --strip-build-prefix[=EXC]  Strip BUILD_PREFIX from tools (optional exclude pattern)
#   --toolchain-prefix=PREFIX   Add toolchain prefix to tools
#   --tools=LIST                Custom tool list for --toolchain-prefix (space-separated)
#   --fix-python                Fix Python path for cross-compilation
#   --platform-link-flags       Add platform-specific link flags (for GHC settings)
#   --macos-ar-ranlib[=TC]      Set macOS LLVM ar/ranlib config
#   --installed                 Apply installed GHC settings transformations
#
# Compound Options (combine multiple atomic options):
#   --linux-cross=TARGET        Cross-compile configure: strip-build-prefix=python + fix-python
#                               + toolchain-prefix=TARGET + linker-flags + doc-placeholders
#   --macos-native=TC           Native macOS configure: strip-build-prefix + toolchain-prefix=TC
#                               + linker-flags + doc-placeholders
#   --macos-stage=TC            macOS stage settings: platform-link-flags + macos-ar-ranlib
#   --macos-bootstrap-cross=HOST  macOS bootstrap cross-compile: verbose + BUILD_PREFIX paths
#                               + llvm-ar/ranlib + host tool prefixes
#
# Examples:
#   patch_settings "${SRC_DIR}/hadrian/cfg/system.config" --linker-flags --doc-placeholders
#   patch_settings "${settings_file}" --linux-cross=aarch64-conda-linux-gnu
#   patch_settings "${settings_file}" --macos-stage="${CONDA_TOOLCHAIN_HOST}"
#
# ==============================================================================

patch_settings() {
  local file="$1"
  shift

  [[ ! -f "${file}" ]] && { echo "  WARNING: ${file} not found, skipping"; return 0; }

  local prefix="${PREFIX}"
  local toolchain="${CONDA_TOOLCHAIN_HOST:-}"
  local tools="ar clang clang++ llc nm opt ranlib"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --linker-flags=*) prefix="${1#*=}"; _patch_linker_flags "${file}" "${prefix}" ;;
      --linker-flags)   _patch_linker_flags "${file}" "${prefix}" ;;

      --doc-placeholders) _patch_doc_placeholders "${file}" ;;

      --strip-build-prefix=*) _patch_strip_build_prefix "${file}" "${1#*=}" ;;
      --strip-build-prefix)   _patch_strip_build_prefix "${file}" "" ;;

      --toolchain-prefix=*) _patch_toolchain_prefix "${file}" "${1#*=}" "${tools}" ;;
      --tools=*) tools="${1#*=}" ;;

      --fix-python) _patch_fix_python "${file}" ;;

      --platform-link-flags=*) toolchain="${1#*=}"; _patch_platform_link_flags "${file}" "${toolchain}" "${prefix}" ;;
      --platform-link-flags)   _patch_platform_link_flags "${file}" "${toolchain}" "${prefix}" ;;

      --macos-ar-ranlib=*) _patch_macos_ar_ranlib "${file}" "${1#*=}" ;;
      --macos-ar-ranlib)   _patch_macos_ar_ranlib "${file}" "${toolchain}" ;;

      --installed=*) toolchain="${1#*=}"; _patch_installed_settings "${toolchain}" ;;
      --installed)   _patch_installed_settings "${toolchain}" ;;

      # Compound modes (combine multiple atomic operations)
      --linux-cross=*)
        local target="${1#*=}"
        _patch_strip_build_prefix "${file}" "python"
        _patch_fix_python "${file}"
        _patch_toolchain_prefix "${file}" "${target}" "${tools}"
        _patch_linker_flags "${file}" "${prefix}"
        _patch_doc_placeholders "${file}"
        ;;

      --macos-native=*)
        local tc="${1#*=}"
        _patch_strip_build_prefix "${file}" ""
        _patch_toolchain_prefix "${file}" "${tc}" "${tools}"
        _patch_linker_flags "${file}" "${prefix}"
        _patch_doc_placeholders "${file}"
        ;;

      --macos-stage=*)
        local tc="${1#*=}"
        _patch_platform_link_flags "${file}" "${tc}" "${prefix}"
        _patch_macos_ar_ranlib "${file}" "${tc}"
        ;;

      --macos-bootstrap-cross=*)
        local host="${1#*=}"
        _patch_macos_bootstrap_cross "${file}" "${host}"
        ;;
    esac
    shift
  done
}

# ==============================================================================
# Internal Implementation Functions
# ==============================================================================

# Helper for replacing values in GHC settings files
# Abstracts the repeated perl -pi -e pattern for tool/value replacements.
#
# Parameters:
#   $1 - file: Path to settings file
#   $2 - key: The settings key to match (e.g., "C compiler command")
#   $3 - value: The replacement value
#
# Usage:
#   _replace_settings_value "${file}" "C compiler command" "${CC}"
#   _replace_settings_value "${file}" "ar command" "llvm-ar"
#
_replace_settings_value() {
  local file="$1" key="$2" value="$3"
  perl -pi -e "s#(${key}\", \")[^\"]*#\$1${value}#" "${file}"
}

# Add linker flags to system.config
_patch_linker_flags() {
  local file="$1" prefix="$2"
  perl -pi -e "s#(conf-cc-args-stage[012].*?= )#\$1-Wno-deprecated-non-prototype #" "${file}"
  perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${prefix}/lib -Wl,-rpath,${prefix}/lib #" "${file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${prefix}/lib -rpath ${prefix}/lib #" "${file}"
  perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${prefix}/lib -Wl,-rpath,${prefix}/lib #" "${file}"
  perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${prefix}/lib -rpath ${prefix}/lib #" "${file}"
}

# Add doc tool placeholders
_patch_doc_placeholders() {
  local file="$1"
  for tool in xelatex sphinx-build makeindex; do
    if ! grep -qE "^${tool}\s*=\s*\S" "${file}"; then
      perl -pi -e "s/^${tool}\\s*=.*/${tool} = \\/bin\\/true/" "${file}"
      grep -qE "^${tool}\s*=\s*\S" "${file}" || echo "${tool} = /bin/true" >> "${file}"
    fi
  done
}

# Strip BUILD_PREFIX from tool paths
_patch_strip_build_prefix() {
  local file="$1" exclude="$2"
  if [[ -n "${exclude}" ]]; then
    perl -pi -e "s#${BUILD_PREFIX}/bin/(?!${exclude})##" "${file}"
  else
    perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${file}"
  fi
}

# Add toolchain prefix to tools
_patch_toolchain_prefix() {
  local file="$1" prefix="$2" tools="$3"
  local pattern=$(echo "${tools}" | tr ' ' '|')
  perl -pi -e "s#(=\\s+)(${pattern})\$#\$1${prefix}-\$2#" "${file}"
}

# Fix Python path for cross-compilation
_patch_fix_python() {
  local file="$1"
  perl -pi -e "s#(^python\\s*=).*#\$1 ${BUILD_PREFIX}/bin/python#" "${file}"
}

# Platform-specific link flags for GHC settings
_patch_platform_link_flags() {
  local file="$1" toolchain="$2" prefix="$3"

  case "${target_platform}" in
    linux-*)
      perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${file}"
      perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${file}"
      perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${prefix}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${prefix}/lib#" "${file}"
      perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${prefix}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${prefix}/lib#" "${file}"
      ;;
    osx-64)
      perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${file}"
      perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${file}"
      perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${file}"
      perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${file}"
      ;;
    osx-arm64)
      perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${file}"
      perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${file}"
      perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fuse-ld=lld -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${file}"
      perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${file}"
      ;;
  esac
  # Update toolchain paths
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${file}"
}

# macOS bootstrap cross-compile settings
# Patches the bootstrap GHC settings for cross-compilation from x86_64 to arm64.
# This ensures Stage0 (which runs on the build machine) has correct paths/tools.
#
# Parameters:
#   $1 - file: Path to bootstrap settings file
#   $2 - host: Host toolchain triple (e.g., x86_64-apple-darwin13.4.0)
#
_patch_macos_bootstrap_cross() {
  local file="$1" host="$2"

  # Add verbose flag to help debug cross-compile issues
  perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -v#' "${file}"

  # Add BUILD_PREFIX library paths for stage0 linking (x86_64 libs)
  # Stage0 runs on x86_64, so it needs x86_64 libffi/libiconv from BUILD_PREFIX
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${BUILD_PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib#" "${file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -rpath ${BUILD_PREFIX}/lib#" "${file}"

  # Fix ar and ranlib commands for cross (use llvm tools)
  perl -pi -e 's#(ar command", ")[^"]*#$1llvm-ar#' "${file}"
  perl -pi -e 's#(ranlib command", ")[^"]*#$1llvm-ranlib#' "${file}"

  # Fix tool commands with host prefix (clang, llc, opt need x86_64 versions)
  perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${host}-\$2#" "${file}"
}

# macOS LLVM ar/ranlib configuration
_patch_macos_ar_ranlib() {
  local file="$1" toolchain="${2:-x86_64-apple-darwin13.4.0}"

  if [[ "$(basename "${file}")" == "default."* ]]; then
    perl -i -pe 's#(arMkArchive\s*=\s*).*#$1Program {prgPath = "llvm-ar", prgFlags = ["qcs"]}#g' "${file}"
    perl -i -pe 's#((arIsGnu|arSupportsAtFile)\s*=\s*).*#$1False#g' "${file}"
    perl -i -pe 's#(arNeedsRanlib\s*=\s*).*#$1False#g' "${file}"
    perl -i -pe 's#(tgtRanlib\s*=\s*).*#$1Nothing#g' "${file}"
  else
    perl -i -pe 's#("ar command", ")[^"]*#$1llvm-ar#g' "${file}"
    perl -i -pe 's#("ar flags", ")[^"]*#$1qcs#g' "${file}"
    perl -i -pe "s#(\"(clang|llc|opt|ranlib) command\", \")[^\"]*#\$1${toolchain}-\$2#g" "${file}"
  fi
}

# Installed GHC settings transformations
_patch_installed_settings() {
  local toolchain="${1:-$CONDA_TOOLCHAIN_HOST}"
  local file=$(get_installed_settings_file)

  case "${target_platform}" in
    linux-*)
      perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-rpath,\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${file}"
      perl -pi -e "s#(ld flags\", \")#\$1-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -rpath \\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${file}"
      ;;
    osx-*)
      perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${file}"
      perl -i -pe "s#(C\\+\\+ compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${file}"
      perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -fuse-ld=lld -fno-lto -fno-use-linker-plugin -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib -liconv -Wl,-L\\\$topdir/../lib -Wl,-rpath,\\\$topdir/../lib -liconv_compat#" "${file}"
      ;;
  esac
  # Remove build-time paths
  perl -pi -e "s#(-Wl,-L${BUILD_PREFIX}/lib|-Wl,-L${PREFIX}/lib|-Wl,-rpath,${BUILD_PREFIX}/lib|-Wl,-rpath,${PREFIX}/lib)##g" "${file}"
  perl -pi -e "s#(-L${BUILD_PREFIX}/lib|-L${PREFIX}/lib|-rpath ${PREFIX}/lib|-rpath ${BUILD_PREFIX}/lib)##g" "${file}"
  # Update toolchain paths
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${file}"
}

# ==============================================================================
# NOTE: Wrapper functions removed - use patch_settings() directly:
#
#   patch_system_config_linker_flags()   → patch_settings "$file" --linker-flags --doc-placeholders
#   strip_build_prefix_from_tools()      → patch_settings "$file" --strip-build-prefix[=exclude]
#   add_toolchain_prefix_to_tools()      → patch_settings "$file" --toolchain-prefix="$prefix"
#   fix_python_path_for_cross()          → patch_settings "$file" --fix-python
#   update_stage_settings()              → patch_settings "$file" (use idempotent stage patching)
#   update_settings_link_flags()         → patch_settings "$file" --platform-link-flags
#   set_macos_conda_ar_ranlib()          → patch_settings "$file" --macos-ar-ranlib
#   update_installed_settings()          → patch_settings "$file" --installed
# ==============================================================================
