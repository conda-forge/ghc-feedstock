#!/usr/bin/env bash
# ==============================================================================
# Cross-Compilation Helper Functions
# ==============================================================================
# Shared functions for cross-compiled GHC builds (linux-cross, osx-arm64).
# These handle common tasks like symlink creation, wrapper script fixes, etc.
#
# Usage: source "${RECIPE_DIR}/lib/cross-helpers.sh"
#
# Required variables (set by platform script before calling):
#   - PREFIX: Installation prefix
#   - PKG_VERSION: GHC version (e.g., "9.6.7")
#   - One of: ghc_target, conda_target (target triple)
# ==============================================================================

# Get the target triple (supports both naming conventions)
_get_target_triple() {
  echo "${ghc_target:-${conda_target:-}}"
}

# ==============================================================================
# Cross-Compile Hadrian Build Setup
# ==============================================================================
# Sets HADRIAN_CABAL_FLAGS for cross-compilation builds.
# Call this before phase_build_hadrian() to use default_build_hadrian().
#
# Usage:
#   cross_setup_hadrian_flags
#
cross_setup_hadrian_flags() {
  echo "  Setting up Hadrian cabal flags for cross-compilation..."

  # These flags ensure Hadrian is built with the correct build-machine tools
  declare -ga HADRIAN_CABAL_FLAGS=(
    "--with-ghc=${GHC}"
    "--with-ar=${AR_STAGE0:-${AR:-}}"
    "--with-gcc=${CC_STAGE0:-${CC_FOR_BUILD:-}}"
  )

  # Add LD if set
  if [[ -n "${LD_STAGE0:-}" ]]; then
    HADRIAN_CABAL_FLAGS+=("--with-ld=${LD_STAGE0}")
  fi

  echo "  HADRIAN_CABAL_FLAGS: ${HADRIAN_CABAL_FLAGS[*]}"
}

# ==============================================================================
# Unified Cross-Compile Configure
# ==============================================================================
# Runs ./configure with cross-compilation settings for both Linux and macOS.
# Unifies the configure patterns from linux-cross.sh and osx-arm64.sh.
#
# Parameters:
#   $1 - extra_ldflags: Additional LDFLAGS (e.g., "-L${PREFIX}/lib ${LDFLAGS:-}")
#
# Required variables:
#   - ghc_host, ghc_target: GHC triples (set by configure_triples)
#   - conda_host, conda_target: Conda toolchain triples (set by configure_triples)
#   - target_alias: Autoconf target alias (set by configure_triples)
#
# Usage:
#   # In linux-cross.sh or osx-arm64.sh:
#   platform_configure_ghc() {
#     shared_cross_configure_ghc "-L${PREFIX}/lib ${LDFLAGS:-}"
#   }
#
shared_cross_configure_ghc() {
  local extra_ldflags="${1:-}"

  echo "  Configuring GHC for ${target_arch:-cross} cross-compilation..."

  # Build system config - platform-specific triple handling
  local -a system_config
  if is_linux; then
    # Linux cross: use full triple set (build=host for cross-compile to target)
    build_system_config system_config "${ghc_host}" "${ghc_host}" "${ghc_target}"
  else
    # macOS cross: use only target (build/host inferred from environment)
    build_system_config system_config "" "" "${target_alias}"
  fi

  # Build standard configure args (--with-gmp, --with-ffi, etc.)
  local -a configure_args
  build_configure_args configure_args "${extra_ldflags}"

  # Set platform-specific autoconf cache variables
  if is_linux; then
    set_autoconf_toolchain_vars --linux --cross
  else
    set_autoconf_toolchain_vars --macos --cross
  fi

  # Add cross-compile toolchain args (CC=, AR=, STAGE0 tools, sysroot)
  cross_build_toolchain_args configure_args "${conda_target}" "${conda_host}" "--sysroot"

  # Run configure with verbose flag for debugging
  run_and_log "configure" ./configure -v "${system_config[@]}" "${configure_args[@]}" || {
    cat config.log
    return 1
  }

  echo "  ✓ GHC configured for cross-compilation"
}

# ==============================================================================
# Cross-Compile Configure Arguments Builder
# ==============================================================================
# Builds an array of toolchain arguments for cross-compilation configure.
# Uses direct variable assignment (CC=..., AR=...) which is the official
# autoconf API as documented in GHC's configure.ac.
#
# Parameters:
#   $1 - result_array_name: Name of array to populate (nameref)
#   $2 - target_prefix: Target toolchain prefix (e.g., "aarch64-conda-linux-gnu")
#   $3 - host_prefix (optional): Host toolchain prefix for STAGE0 tools
#   $4 - options (optional): Space-separated options:
#        --sysroot    Add CFLAGS/CPPFLAGS/CXXFLAGS with sysroot
#        --gcc        Use gcc/g++ instead of clang/clang++
#
# Usage:
#   local -a extra_args
#   cross_build_toolchain_args extra_args "${conda_target}"
#   cross_build_toolchain_args extra_args "${conda_target}" "${conda_host}"
#   cross_build_toolchain_args extra_args "${conda_target}" "${conda_host}" "--sysroot"
#   ./configure "${extra_args[@]}"
#
cross_build_toolchain_args() {
  local -n _result="$1"
  local target_prefix="$2"
  local host_prefix="${3:-}"
  local options="${4:-}"

  echo "  Building toolchain args for target: ${target_prefix}"
  [[ -n "${host_prefix}" ]] && echo "  STAGE0 host: ${host_prefix}"

  # Determine compiler names based on options
  local cc_name="clang"
  local cxx_name="clang++"
  if [[ "${options}" == *"--gcc"* ]]; then
    cc_name="gcc"
    cxx_name="g++"
  fi

  # Target tools - direct variable assignment (official autoconf API)
  local -a tools=(AR AS LD NM OBJDUMP RANLIB STRIP)
  for tool in "${tools[@]}"; do
    local tool_lower="${tool,,}"
    local tool_path="${BUILD_PREFIX}/bin/${target_prefix}-${tool_lower}"
    if [[ -f "${tool_path}" ]] || [[ -L "${tool_path}" ]]; then
      _result+=("${tool}=${tool_path}")
    fi
  done

  # Compilers (CC, CXX) - handle clang vs gcc naming
  local cc_path="${BUILD_PREFIX}/bin/${target_prefix}-${cc_name}"
  local cxx_path="${BUILD_PREFIX}/bin/${target_prefix}-${cxx_name}"
  [[ -f "${cc_path}" || -L "${cc_path}" ]] && _result+=("CC=${cc_path}")
  [[ -f "${cxx_path}" || -L "${cxx_path}" ]] && _result+=("CXX=${cxx_path}")

  # LLVM tools (always use target prefix)
  local llc_path="${BUILD_PREFIX}/bin/${target_prefix}-llc"
  local opt_path="${BUILD_PREFIX}/bin/${target_prefix}-opt"
  [[ -f "${llc_path}" || -L "${llc_path}" ]] && _result+=("LLC=${llc_path}")
  [[ -f "${opt_path}" || -L "${opt_path}" ]] && _result+=("OPT=${opt_path}")

  # STAGE0 tools (bootstrap stage - run on build host)
  if [[ -n "${host_prefix}" ]]; then
    _result+=("CC_STAGE0=${CC_FOR_BUILD:-${BUILD_PREFIX}/bin/${host_prefix}-${cc_name}}")
    _result+=("LD_STAGE0=${BUILD_PREFIX}/bin/${host_prefix}-ld")
    _result+=("AR_STAGE0=${BUILD_PREFIX}/bin/${host_prefix}-ar")
  fi

  # Sysroot flags (for cross-compilation)
  # Linux: Use target-specific sysroot at $BUILD_PREFIX/${target}/sysroot
  # macOS: Use SDK sysroot from CONDA_BUILD_SYSROOT
  if [[ "${options}" == *"--sysroot"* ]]; then
    local sysroot=""
    local target_sysroot="${BUILD_PREFIX}/${target_prefix}/sysroot"

    if [[ -d "${target_sysroot}" ]]; then
      # Linux cross-compile: target-specific sysroot
      sysroot="${target_sysroot}"
    elif [[ -n "${CONDA_BUILD_SYSROOT:-}" ]] && [[ -d "${CONDA_BUILD_SYSROOT}" ]]; then
      # macOS cross-compile: SDK sysroot
      sysroot="${CONDA_BUILD_SYSROOT}"
    fi

    if [[ -n "${sysroot}" ]]; then
      _result+=("CFLAGS=--sysroot=${sysroot} ${CFLAGS:-}")
      _result+=("CPPFLAGS=--sysroot=${sysroot} ${CPPFLAGS:-}")
      _result+=("CXXFLAGS=--sysroot=${sysroot} ${CXXFLAGS:-}")
      echo "  Using sysroot: ${sysroot}"
    else
      echo "  WARNING: No sysroot found (checked ${target_sysroot} and CONDA_BUILD_SYSROOT)"
    fi
  fi
}

# ==============================================================================
# Symlink Creation for Cross-Compiled Tools
# ==============================================================================
# Creates symlinks so cross-compiled tools can be invoked without target prefix.
#
# GHC bindist installs versioned wrappers like:
#   powerpc64le-unknown-linux-gnu-ghci-9.6.7
# But users expect to call just 'ghci'. We create:
#   versioned -> unversioned -> short name
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#
cross_create_symlinks() {
  local target="${1:-$(_get_target_triple)}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_create_symlinks requires target triple"
    return 1
  fi

  echo "  Creating symlinks for cross-compiled tools..."

  pushd "${PREFIX}/bin" >/dev/null

  # Standard GHC tools that need symlinks
  local tools="ghc ghci ghc-pkg hp2ps hsc2hs haddock hpc runghc"

  for bin in ${tools}; do
    local versioned="${target}-${bin}-${PKG_VERSION}"
    local unversioned="${target}-${bin}"

    # Create unversioned -> versioned symlink if versioned exists
    if [[ -f "${versioned}" ]] && [[ ! -e "${unversioned}" ]]; then
      ln -sf "${versioned}" "${unversioned}"
    fi

    # Create short name -> unversioned/versioned symlink
    if [[ -e "${unversioned}" ]] && [[ ! -e "${bin}" ]]; then
      ln -sf "${unversioned}" "${bin}"
    elif [[ -f "${versioned}" ]] && [[ ! -e "${bin}" ]]; then
      ln -sf "${versioned}" "${bin}"
    fi
  done

  popd >/dev/null

  # Create directory symlink for libraries
  local target_lib_dir="${PREFIX}/lib/${target}-ghc-${PKG_VERSION}"
  local standard_lib_dir="${PREFIX}/lib/ghc-${PKG_VERSION}"

  if [[ -d "${target_lib_dir}" ]] && [[ ! -d "${standard_lib_dir}" ]]; then
    mv "${target_lib_dir}" "${standard_lib_dir}"
    ln -sf "${standard_lib_dir}" "${target_lib_dir}"
  fi

  echo "  ✓ Symlinks created"
}

# ==============================================================================
# Fix Wrapper Scripts "./" Prefix Bug
# ==============================================================================
# GHC bindist Makefile uses 'find . ! -type d' to list wrapper files,
# which outputs './ghci' instead of 'ghci'. This "./" gets embedded in:
#   exeprog="./ghci"
#   executablename="/path/to/lib/bin/./ghci"
# causing broken paths like: $libdir/bin/./target-ghci-9.6.7
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#
cross_fix_wrapper_scripts() {
  local target="${1:-$(_get_target_triple)}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_fix_wrapper_scripts requires target triple"
    return 1
  fi

  echo "  Fixing wrapper scripts..."

  pushd "${PREFIX}/bin" >/dev/null

  local wrappers="ghc ghci ghc-pkg runghc runhaskell haddock hp2ps hsc2hs hpc"

  for wrapper in ${wrappers}; do
    # Fix target-prefixed wrapper
    local target_wrapper="${target}-${wrapper}"
    if [[ -f "${target_wrapper}" ]]; then
      # Fix both exeprog and executablename - both can have "./" prefix
      perl -pi -e 's#^(exeprog=")\./#$1#' "${target_wrapper}"
      perl -pi -e 's#(/bin/)\./#$1#' "${target_wrapper}"
    fi

    # Fix short-name wrapper (may be script or symlink - only fix if script)
    if [[ -f "${wrapper}" ]] && [[ ! -L "${wrapper}" ]]; then
      perl -pi -e 's#^(exeprog=")\./#$1#' "${wrapper}"
      perl -pi -e 's#(/bin/)\./#$1#' "${wrapper}"
    fi
  done

  popd >/dev/null
  echo "  ✓ Wrapper scripts fixed"
}

# ==============================================================================
# Fix ghci Wrapper for Cross-Compiled GHC
# ==============================================================================
# For cross-compiled GHC, ghci is NOT a separate binary - it's just 'ghc --interactive'.
# The bindist install creates a broken wrapper pointing to a non-existent ghci binary.
# Replace it with a simple script that calls ghc --interactive.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#
cross_fix_ghci_wrapper() {
  local target="${1:-$(_get_target_triple)}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_fix_ghci_wrapper requires target triple"
    return 1
  fi

  echo "  Fixing ghci wrapper..."

  # Fix target-prefixed ghci wrapper
  local ghci_wrapper="${PREFIX}/bin/${target}-ghci"
  if [[ -f "${ghci_wrapper}" ]]; then
    cat > "${ghci_wrapper}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
    chmod +x "${ghci_wrapper}"
  fi

  # Also fix short-name ghci if it's a script (not symlink)
  local short_ghci="${PREFIX}/bin/ghci"
  if [[ -f "${short_ghci}" ]] && [[ ! -L "${short_ghci}" ]]; then
    cat > "${short_ghci}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
    chmod +x "${short_ghci}"
  fi

  echo "  ✓ ghci wrapper fixed"
}

# ==============================================================================
# Common Post-Configure for Cross-Compilation
# ==============================================================================
# Standard system.config patching for cross-compile builds.
# Calls helper functions from helpers.sh in the correct order.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#   $2 - tools_to_prefix (optional, space-separated list of tools)
#
cross_patch_system_config() {
  local target="${1:-$(_get_target_triple)}"
  local tools="${2:-}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_patch_system_config requires target triple"
    return 1
  fi

  echo "  Patching system.config for cross-compilation..."

  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  # Strip BUILD_PREFIX from tool paths (exclude python - it runs on build host)
  patch_settings "${settings_file}" --strip-build-prefix=python

  # Fix Python path for cross-compile
  patch_settings "${settings_file}" --fix-python

  # Add toolchain prefix to tools
  if [[ -n "${tools}" ]]; then
    patch_settings "${settings_file}" --tools="${tools}" --toolchain-prefix="${target}"
  else
    patch_settings "${settings_file}" --toolchain-prefix="${target}"
  fi

  # Add library paths and rpath
  patch_settings "${settings_file}" --linker-flags --doc-placeholders

  echo "  ✓ System config patched for cross-compilation"
}

# ==============================================================================
# Common Post-Install for Cross-Compilation
# ==============================================================================
# Standard post-install steps for cross-compile builds.
# Can be called directly or individual functions can be called separately.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#   $2 - options (optional): "no-wrapper-fix" to skip wrapper script fixing
#
cross_post_install() {
  local target="${1:-$(_get_target_triple)}"
  local options="${2:-}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_post_install requires target triple"
    return 1
  fi

  # Fix wrapper scripts (Linux needs this, macOS may not)
  if [[ "${options}" != *"no-wrapper-fix"* ]]; then
    cross_fix_wrapper_scripts "${target}"
  fi

  # Fix ghci wrapper
  cross_fix_ghci_wrapper "${target}"

  # Create symlinks
  cross_create_symlinks "${target}"

  # Install bash completion
  install_bash_completion
}

# ==============================================================================
# Common Bindist Install for Cross-Compilation
# ==============================================================================
# Installs GHC from binary distribution with cross-compile specific settings.
# Uses build-host compiler for wrapper generation and clears target flags.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#   $2 - extra_args (optional): Additional configure arguments
#
# Usage:
#   cross_bindist_install                                    # Basic cross install
#   cross_bindist_install "${ghc_target}"                    # Explicit target
#   cross_bindist_install "${conda_target}" "CXX_STD_LIB_LIBS='c++ c++abi'"  # macOS
#
cross_bindist_install() {
  local target="${1:-$(_get_target_triple)}"
  local platform_extra="${2:-}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_bindist_install requires target triple"
    return 1
  fi

  # Build-host compiler for wrapper script generation
  local host="${conda_host:-${build_alias}}"
  local extra_args="ac_cv_path_CC=${BUILD_PREFIX}/bin/${host}-clang"
  extra_args+=" ac_cv_path_CXX=${BUILD_PREFIX}/bin/${host}-clang++"
  extra_args+=" CFLAGS= CXXFLAGS= LDFLAGS="

  # Add platform-specific arguments
  [[ -n "${platform_extra}" ]] && extra_args+=" ${platform_extra}"

  bindist_install "${target}" "${extra_args}"
}
