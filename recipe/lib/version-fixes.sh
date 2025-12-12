#!/usr/bin/env bash
# ==============================================================================
# GHC Version-Specific Fixes Library
# ==============================================================================
# This file contains functions that apply version-specific workarounds for
# known bugs and differences between GHC versions.
#
# Usage:
#   source "${RECIPE_DIR}/lib/version-fixes.sh"
#   apply_version_specific_fixes
#
# The fixes are selected based on GHC_MAJOR_VERSION (e.g., "9.2", "9.6")
# which is derived from PKG_VERSION in the build environment.
# ==============================================================================

# Derive major version from PKG_VERSION (e.g., "9.2.8" -> "9.2")
get_ghc_major_version() {
  echo "${PKG_VERSION}" | cut -d. -f1,2
}

# ==============================================================================
# GHC 9.2.x Specific Fixes
# ==============================================================================

# Fix: GHC 9.2.8 has a bug in m4/fp_gmp.m4 where --with-intree-gmp=no
# triggers GMP_FORCE_INTREE=YES due to broken AC_ARG_WITH parsing.
# Workaround: Don't pass --with-intree-gmp flag, then patch system.config
apply_intree_gmp_bug_fix() {
  local config_file="$1"

  if [[ ! -f "${config_file}" ]]; then
    echo "WARNING: Cannot apply intree-gmp fix - config file not found: ${config_file}"
    return 1
  fi

  echo "  Applying GHC 9.2.x intree-gmp bug fix..."
  perl -pi -e 's#^intree-gmp\s*=\s*.*#intree-gmp = NO#' "${config_file}"
  echo "  ✓ intree-gmp = NO forced in system.config"
}

# Fix: GHC 9.2.8 has a bug in m4/fp_settings.m4 where --enable-distro-toolchain
# sets SettingsTouchCommand to 'touchy.exe' on ALL platforms, not just Windows.
# Workaround: Patch system.config to use 'touch' on Unix platforms
apply_touchy_exe_bug_fix() {
  local config_file="$1"

  if [[ ! -f "${config_file}" ]]; then
    echo "WARNING: Cannot apply touchy.exe fix - config file not found: ${config_file}"
    return 1
  fi

  echo "  Applying GHC 9.2.x touchy.exe cross-platform bug fix..."
  perl -pi -e 's#\$\$topdir/bin/touchy\.exe#touch#' "${config_file}"
  echo "  ✓ touchy.exe replaced with touch"
}

# Fix: GHC 9.2.8 RTS static libraries are not compiled with -fPIC,
# causing PIE relocation errors on Linux when linking executables.
# Workaround: Add -fPIC to C compiler flags and -no-pie to linker flags
apply_pie_relocation_fix() {
  local config_file="$1"

  if [[ ! -f "${config_file}" ]]; then
    echo "WARNING: Cannot apply PIE fix - config file not found: ${config_file}"
    return 1
  fi

  echo "  Applying GHC 9.2.x PIE relocation fix..."

  # Add -fPIC to C compiler flags for all stages
  perl -pi -e 's#^(conf-cc-args-stage[0-3][ \t]*=[ \t]*)(.*)$#$1-fPIC $2#' "${config_file}"
  perl -pi -e 's#^(settings-c-compiler-flags[ \t]*=[ \t]*)(.*)$#$1-fPIC $2#' "${config_file}"

  # Add -no-pie to linker flags (RTS is not PIC-compatible)
  perl -pi -e 's#^(conf-gcc-linker-args-stage[0-3][ \t]*=[ \t]*)(.*)$#$1-no-pie $2#' "${config_file}"
  perl -pi -e 's#^(settings-c-compiler-link-flags[ \t]*=[ \t]*)(.*)$#$1-no-pie $2#' "${config_file}"
  perl -pi -e 's#^(settings-ld-flags[ \t]*=[ \t]*)(.*)$#$1-no-pie $2#' "${config_file}"

  echo "  ✓ Added -fPIC to compiler flags, -no-pie to linker flags"
}

# Fix: GHC 9.2.8 bootstrap GHC's time library references __imp__timezone and
# __imp__tzname which are MSVCRT symbols not available in modern UCRT.
# Workaround: Create and link mingw32_stubs library with these symbols
apply_mingw32_stubs_to_bootstrap() {
  local settings_file="$1"
  local stubs_lib_dir="$2"

  if [[ ! -f "${settings_file}" ]]; then
    echo "WARNING: Cannot apply mingw32_stubs fix - settings file not found: ${settings_file}"
    return 1
  fi

  echo "  Applying GHC 9.2.x mingw32_stubs fix to bootstrap settings..."

  # Add stubs library to link flags
  perl -pi -e "s#(C compiler link flags\", \")([^\"]*)#\$1\$2 -L${stubs_lib_dir} -lmingw32_stubs#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \")([^\"]*)#\$1\$2 -L${stubs_lib_dir} -lmingw32_stubs#" "${settings_file}"

  echo "  ✓ Added -lmingw32_stubs to bootstrap GHC link flags"
}

# ==============================================================================
# GHC 9.4.x Specific Fixes
# ==============================================================================

# Fix: GHC 9.4.8 has a bug in libraries/ghc-bignum/configure where
# --with-intree-gmp=no triggers GMP_FORCE_INTREE=YES due to broken parsing.
# This is similar to 9.2.x but in a different file location.
# Workaround: Apply fix-ghc-bignum-intree-gmp-check.patch at build time
apply_ghc_bignum_intree_gmp_fix() {
  local config_file="$1"

  if [[ ! -f "${config_file}" ]]; then
    echo "WARNING: Cannot apply ghc-bignum intree-gmp fix - config file not found: ${config_file}"
    return 1
  fi

  echo "  Applying GHC 9.4.x ghc-bignum intree-gmp fix..."
  perl -pi -e 's#^intree-gmp\s*=\s*.*#intree-gmp = NO#' "${config_file}"
  echo "  ✓ intree-gmp = NO forced in system.config"
}

# ==============================================================================
# GHC 9.6.x Specific Fixes
# ==============================================================================

# Currently no 9.6.x specific runtime fixes needed
# (patches handle source-level differences)

# ==============================================================================
# Version Detection and Dispatch
# ==============================================================================

# Apply all version-specific fixes for the current GHC version
# Arguments:
#   $1 - config_file path (system.config or settings file)
#   $2 - platform (linux-64, linux-aarch64, osx-64, osx-arm64, win-64)
#   $3 - (optional) additional context (e.g., stubs_lib_dir for Windows)
apply_version_specific_fixes() {
  local config_file="${1:-}"
  local platform="${2:-${target_platform:-unknown}}"
  local extra_arg="${3:-}"

  local major_version=$(get_ghc_major_version)

  echo "Applying version-specific fixes for GHC ${major_version} on ${platform}..."

  case "${major_version}" in
    9.2)
      # GHC 9.2.x has several known bugs that need runtime workarounds

      # All platforms: intree-gmp and touchy.exe bugs
      if [[ -n "${config_file}" && -f "${config_file}" ]]; then
        apply_intree_gmp_bug_fix "${config_file}"
        apply_touchy_exe_bug_fix "${config_file}"
      fi

      # Linux: PIE relocation errors
      case "${platform}" in
        linux-64|linux-aarch64|linux-ppc64le)
          if [[ -n "${config_file}" && -f "${config_file}" ]]; then
            apply_pie_relocation_fix "${config_file}"
          fi
          ;;
      esac

      # Windows: mingw32_stubs for timezone symbols
      # (This is called separately from patch_bootstrap_settings with the stubs path)
      ;;

    9.4)
      # GHC 9.4.x has the intree-gmp bug (fixed via patch, but may need runtime fix too)
      # and potentially PIE issues on Linux

      # All platforms: intree-gmp bug (different location than 9.2.x)
      if [[ -n "${config_file}" && -f "${config_file}" ]]; then
        apply_ghc_bignum_intree_gmp_fix "${config_file}"
      fi

      # Linux: PIE relocation errors (same as 9.2.x)
      case "${platform}" in
        linux-64|linux-aarch64|linux-ppc64le)
          if [[ -n "${config_file}" && -f "${config_file}" ]]; then
            apply_pie_relocation_fix "${config_file}"
          fi
          ;;
      esac
      ;;

    9.6|9.8|9.10)
      # GHC 9.6.x and later have these bugs fixed
      echo "  No runtime fixes needed for GHC ${major_version}"
      ;;

    *)
      echo "  Unknown GHC version: ${major_version} - no fixes applied"
      ;;
  esac

  echo "✓ Version-specific fixes complete"
}

# Check if a specific fix is needed for the current version
needs_fix() {
  local fix_name="$1"
  local major_version=$(get_ghc_major_version)

  case "${fix_name}" in
    intree_gmp_bug)
      # 9.2.x has m4/fp_gmp.m4 bug, 9.4.x has ghc-bignum/configure bug
      [[ "${major_version}" == "9.2" || "${major_version}" == "9.4" ]]
      ;;
    touchy_exe_bug)
      # Only 9.2.x has the touchy.exe cross-platform bug
      [[ "${major_version}" == "9.2" ]]
      ;;
    pie_relocation)
      # 9.2.x and 9.4.x have PIE relocation issues on Linux
      [[ "${major_version}" == "9.2" || "${major_version}" == "9.4" ]]
      ;;
    mingw32_stubs)
      # Only 9.2.x needs mingw32_stubs (9.4.x doesn't support Windows)
      [[ "${major_version}" == "9.2" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

# ==============================================================================
# Version-Specific Configuration
# ==============================================================================

# Get the recommended Hadrian flavour for the current version
get_hadrian_flavour() {
  local platform="${1:-${target_platform:-linux-64}}"
  local major_version=$(get_ghc_major_version)

  case "${major_version}" in
    9.2)
      # GHC 9.2.x builds are slower, use faster flavours
      # Windows: Use 'quickest' to avoid 92MB binary size triggering PE/COFF
      # 32-bit relocation limits (R_X86_64_PC32 overflow)
      case "${platform}" in
        win-64)
          echo "quickest"
          ;;
        *)
          echo "quick"
          ;;
      esac
      ;;
    9.4)
      # GHC 9.4.x: Linux uses quick, macOS uses release+no_profiled_libs
      # The 'quick' flavour has issues with dynamic library builds on macOS
      case "${platform}" in
        osx-64|osx-arm64)
          echo "release+no_profiled_libs"
          ;;
        *)
          echo "release"
          ;;
      esac
      ;;
    *)
      # GHC 9.6+ can use release flavour
      echo "release"
      ;;
  esac
}

# Get the install targets for bindist installation
get_install_targets() {
  local major_version=$(get_ghc_major_version)

  case "${major_version}" in
    9.2)
      # GHC 9.2.x has install_includes target
      echo "install_bin install_lib install_includes"
      ;;
    9.4)
      # GHC 9.4.x doesn't have install_man or install_includes
      echo "install_bin install_lib"
      ;;
    *)
      # GHC 9.6+ has install_man
      echo "install_bin install_lib install_man"
      ;;
  esac
}

# Get the patches directory for the current version
get_patches_dir() {
  local major_version=$(get_ghc_major_version)
  echo "${RECIPE_DIR}/patches/${major_version%%.*}.${major_version#*.}"
}

# Check if Windows is supported for the current version
is_windows_supported() {
  local major_version=$(get_ghc_major_version)

  case "${major_version}" in
    9.4|9.8)
      # GHC 9.4.x and 9.8.x do not support Windows in conda-forge
      return 1
      ;;
    *)
      # GHC 9.2.x, 9.6.x, 9.10.x support Windows
      return 0
      ;;
  esac
}

# Get the required bootstrap GHC version for the current version
# Unix: Use 9.2.8 as it's the most reliable bootstrap version
# Windows: Use 9.6.7 because it has process-1.6.19.0 which fixes the
#          builderMainLoop job object bug (fixed in process-1.6.18.0)
#          GHC 9.2.8 bundles process-1.6.16.0 which has the bug
get_bootstrap_version() {
  local platform="${target_platform:-${build_platform:-}}"

  case "${platform}" in
    win-64|win-*)
      # Windows needs 9.6.7 bootstrap for fixed process library
      echo "9.6.7"
      ;;
    *)
      # Unix platforms use 9.2.8
      echo "9.2.8"
      ;;
  esac
}

# Check if version requires separate ghc-prim/ghc-bignum build steps
needs_separate_prim_builds() {
  local major_version=$(get_ghc_major_version)

  case "${major_version}" in
    9.8|9.10)
      # GHC 9.8+ requires building ghc-prim and ghc-bignum separately
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Check if version uses ghc-toolchain for toolchain detection
# GHC 9.10+ introduced ghc-toolchain which runs during configure
# and creates config files that may need path patching on Windows
uses_ghc_toolchain() {
  local major_version=$(get_ghc_major_version)

  case "${major_version}" in
    9.10)
      # GHC 9.10+ uses ghc-toolchain
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Relax library version bounds for GHC 9.6.7 bootstrap compatibility
# GHC 9.6.7 bundles: base 4.18.x, time 1.12.2, ghc-prim 0.10.0
# GHC 9.2.8 libraries require: base < 4.17, time < 1.12, ghc-prim < 0.9
# This function relaxes upper bounds so 9.6.7 can build 9.2.8
relax_bootstrap_version_bounds() {
  local src_dir="${1:-${SRC_DIR:-$(pwd)}}"
  local libraries_dir="${src_dir}/libraries"

  if [[ ! -d "${libraries_dir}" ]]; then
    echo "WARNING: Cannot relax version bounds - libraries dir not found: ${libraries_dir}"
    return 1
  fi

  echo "  Relaxing library version bounds for GHC 9.6.7 bootstrap..."

  # Find ALL .cabal and .cabal.in files in libraries/ and patch them
  # This is more robust than maintaining a manual list
  local count=0
  while IFS= read -r -d '' cabal_file; do
    local modified=false

    # Relax base < 4.17 to < 4.19
    if grep -q "base.*<.*4\.17" "${cabal_file}" 2>/dev/null; then
      sed -i 's/base[[:space:]]*>=[[:space:]]*[0-9.]*[[:space:]]*&&[[:space:]]*<[[:space:]]*4\.17/base >= 4.5 \&\& < 4.19/g' "${cabal_file}"
      modified=true
    fi

    # Relax base < 4.18 to < 4.19
    if grep -q "base.*<.*4\.18" "${cabal_file}" 2>/dev/null; then
      sed -i 's/base[[:space:]]*>=[[:space:]]*[0-9.]*[[:space:]]*&&[[:space:]]*<[[:space:]]*4\.18/base >= 4.5 \&\& < 4.19/g' "${cabal_file}"
      modified=true
    fi

    # Relax time < 1.12 to < 1.14
    if grep -q "time.*<.*1\.12" "${cabal_file}" 2>/dev/null; then
      sed -i 's/time[[:space:]]*>=[[:space:]]*[0-9.]*[[:space:]]*&&[[:space:]]*<[[:space:]]*1\.12/time >= 1.2 \&\& < 1.14/g' "${cabal_file}"
      modified=true
    fi

    # Relax ghc-prim < 0.9 to < 0.11
    if grep -q "ghc-prim.*<.*0\.9" "${cabal_file}" 2>/dev/null; then
      sed -i 's/ghc-prim[[:space:]]*>[=]*[[:space:]]*[0-9.]*[[:space:]]*&&[[:space:]]*<[[:space:]]*0\.9/ghc-prim >= 0.2 \&\& < 0.11/g' "${cabal_file}"
      modified=true
    fi

    if [[ "${modified}" == "true" ]]; then
      echo "    ✓ Patched: $(basename ${cabal_file})"
      ((count++))
    fi
  done < <(find "${libraries_dir}" -name "*.cabal" -o -name "*.cabal.in" -print0 2>/dev/null)

  echo "  ✓ Version bounds relaxed in ${count} files for 9.6.7 bootstrap compatibility"
}

echo "  ✓ Version fixes library loaded (GHC $(get_ghc_major_version))"
