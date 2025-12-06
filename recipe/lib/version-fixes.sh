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
      # GHC 9.4.x - may have some of the same bugs as 9.2.x
      # Add fixes as needed
      echo "  No runtime fixes needed for GHC 9.4.x"
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
      [[ "${major_version}" == "9.2" ]]
      ;;
    touchy_exe_bug)
      [[ "${major_version}" == "9.2" ]]
      ;;
    pie_relocation)
      [[ "${major_version}" == "9.2" ]]
      ;;
    mingw32_stubs)
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
  local major_version=$(get_ghc_major_version)
  local platform="${1:-${target_platform:-linux-64}}"

  case "${major_version}" in
    9.2)
      # GHC 9.2.x builds are slower, use faster flavours
      case "${platform}" in
        win-64)
          echo "quickest"
          ;;
        *)
          echo "quick"
          ;;
      esac
      ;;
    *)
      # GHC 9.4+ can use release flavour
      echo "release"
      ;;
  esac
}

# Get the install targets for bindist installation
get_install_targets() {
  local major_version=$(get_ghc_major_version)

  case "${major_version}" in
    9.2)
      # GHC 9.2.x doesn't have install_man target
      echo "install_bin install_lib install_includes"
      ;;
    *)
      # GHC 9.4+ has install_man
      echo "install_bin install_lib install_man"
      ;;
  esac
}

# Get the patches directory for the current version
get_patches_dir() {
  local major_version=$(get_ghc_major_version)
  echo "${RECIPE_DIR}/patches/${major_version%%.*}.${major_version#*.}"
}

echo "  ✓ Version fixes library loaded (GHC $(get_ghc_major_version))"
