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
# IMPORTANT: Platform-specific pre-build setup differences:
#   - Linux cross-compile: Requires explicit CFLAGS/LDFLAGS with --sysroot.
#     Linux GCC toolchain doesn't automatically find sysroot libraries.
#
#   - macOS cross-compile: No explicit flags needed. macOS Clang handles
#     sysroot/SDK paths automatically via CONDA_BUILD_SYSROOT.
#
# These differences are intentional and are now encapsulated in the unified
# cross_setup_hadrian_environment() function below. Platform scripts should
# call that function instead of duplicating the platform-specific logic.
#
# Usage:
#   cross_setup_hadrian_flags       # Low-level: just sets HADRIAN_CABAL_FLAGS
#   cross_setup_hadrian_environment # High-level: handles CFLAGS/LDFLAGS + flags
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
# Cross-Compile Hadrian Environment Setup (Unified Interface)
# ==============================================================================
# Sets up complete Hadrian build environment for cross-compilation.
# Unifies the interface while preserving platform-specific behavior:
#   - Linux: exports CFLAGS/LDFLAGS with sysroot (GCC needs explicit paths)
#   - macOS: relies on Clang's automatic SDK handling (no flags needed)
# Then calls cross_setup_hadrian_flags for both platforms.
#
# This function consolidates the logic that was previously duplicated in:
#   - linux-cross.sh:platform_pre_build_hadrian()
#   - osx-arm64.sh:platform_pre_build_hadrian()
#
# Usage:
#   platform_pre_build_hadrian() {
#     cross_setup_hadrian_environment
#   }
#
cross_setup_hadrian_environment() {
  echo "  Setting up Hadrian cross-compile environment..."

  if is_linux; then
    # Linux GCC needs explicit sysroot and library paths.
    # Without these, GCC cannot find headers and libraries in the cross-sysroot.
    # (macOS Clang handles this automatically via CONDA_BUILD_SYSROOT)
    export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include -fdebug-prefix-map=${SRC_DIR}=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
    export LDFLAGS="-L${BUILD_PREFIX}/${conda_host}/lib -L${BUILD_PREFIX}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"
    echo "  ✓ Linux sysroot flags set for GCC toolchain"
  else
    echo "  ℹ macOS Clang uses automatic SDK handling (no explicit flags needed)"
  fi

  # Both platforms: set Hadrian cabal flags (--with-ghc, --with-ar, etc.)
  cross_setup_hadrian_flags
}

# ==============================================================================
# Cross-Compile Toolchain Environment Setup
# ==============================================================================
# Sets up toolchain environment variables for cross-compilation stages.
# Consolidates toolchain exports from platform scripts.
#
# Parameters:
#   $1 - stage: "stage0" (build-host tools) or "stage1" (target tools) [default: stage0]
#
# Required variables:
#   - conda_host: Conda toolchain triple for build host
#   - conda_target: Conda toolchain triple for target
#   - BUILD_PREFIX: Build prefix path
#   - AR_STAGE0: Archive tool for Stage0 (usually set by macos_setup_llvm_ar)
#
# Usage:
#   setup_cross_toolchain_environment            # Uses stage0 (build-host) tools
#   setup_cross_toolchain_environment "stage0"   # Explicit stage0
#
setup_cross_toolchain_environment() {
  local stage="${1:-stage0}"

  echo "  Setting up cross-compile toolchain for ${stage}..."

  if [[ "${stage}" == "stage0" ]]; then
    # Stage0 uses build-host tools (conda_host)
    export AR="${AR_STAGE0:-${BUILD_PREFIX}/bin/${conda_host}-ar}"
    export AS="${BUILD_PREFIX}/bin/${conda_host}-as"
    export CC="${CC_FOR_BUILD:-${BUILD_PREFIX}/bin/${conda_host}-clang}"
    export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
    export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  else
    # Later stages use target tools (conda_target)
    export AR="${BUILD_PREFIX}/bin/${conda_target}-ar"
    export AS="${BUILD_PREFIX}/bin/${conda_target}-as"
    export CC="${BUILD_PREFIX}/bin/${conda_target}-clang"
    export CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"
    export LD="${BUILD_PREFIX}/bin/${conda_target}-ld"
  fi

  echo "    AR=${AR}"
  echo "    CC=${CC}"
}

# ==============================================================================
# Unified Pre-Stage1 Setup for Cross-Compilation
# ==============================================================================
# Standard pre-Stage1 setup shared by all cross-compile platforms.
# Disables copy optimization and handles platform-specific toolchain setup.
#
# Usage:
#   # In platform script:
#   platform_pre_build_stage1() {
#     cross_pre_stage1_standard
#   }
#
cross_pre_stage1_standard() {
  echo "  Running cross-compile pre-Stage1 setup..."

  # CRITICAL: Disable Hadrian's copy optimization for cross-compilation.
  # Without this, Hadrian would copy the bootstrap GHC binary instead of
  # building a new cross-compiled binary.
  disable_copy_optimization

  # macOS requires explicit toolchain setup for Stage0 (clang paths).
  # Linux cross-compile sets this via configure args instead.
  if is_macos; then
    setup_cross_toolchain_environment "stage0"
  fi

  echo "  ✓ Pre-Stage1 setup complete"
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

# Smart default: Standard cross-compile configure with common ldflags
# Platforms can override platform_configure_ghc() if they need different ldflags
# Eliminates platform_configure_ghc() from linux-cross, osx-arm64
default_cross_configure_ghc() {
  shared_cross_configure_ghc "-L${PREFIX}/lib ${LDFLAGS:-}"
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
# Combined Wrapper Fixes for Cross-Compiled GHC
# ==============================================================================
# Applies all wrapper fixes in one call: fixes "./" prefix in wrapper scripts
# and replaces broken ghci wrapper with correct ghc --interactive script.
#
# Parameters:
#   $1 - target_triple (optional, uses ghc_target/conda_target if not provided)
#
cross_fix_all_wrappers() {
  local target="${1:-$(_get_target_triple)}"

  if [[ -z "${target}" ]]; then
    echo "ERROR: cross_fix_all_wrappers requires target triple"
    return 1
  fi

  echo "  Applying all wrapper fixes..."
  cross_fix_wrapper_scripts "${target}"
  cross_fix_ghci_wrapper "${target}"
  echo "  ✓ All wrapper fixes applied"
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

  # Use compound mode for standard case, atomic options for custom tools
  if [[ -z "${tools}" ]]; then
    # Compound mode: strip-build-prefix=python + fix-python + toolchain-prefix + linker-flags + doc-placeholders
    patch_settings "${settings_file}" --linux-cross="${target}"
  else
    # Custom tools: use atomic options
    patch_settings "${settings_file}" --strip-build-prefix=python
    patch_settings "${settings_file}" --fix-python
    patch_settings "${settings_file}" --tools="${tools}" --toolchain-prefix="${target}"
    patch_settings "${settings_file}" --linker-flags --doc-placeholders
  fi

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

  # Apply wrapper fixes (combined function handles both script fixes and ghci)
  # Use "no-wrapper-fix" to skip only the "./" prefix fixes but still fix ghci
  if [[ "${options}" != *"no-wrapper-fix"* ]]; then
    cross_fix_all_wrappers "${target}"
  else
    # Skip script fixes but still fix ghci wrapper
    cross_fix_ghci_wrapper "${target}"
  fi

  # Create symlinks
  cross_create_symlinks "${target}"

  # Verify binaries exist (cross-compiled may fail to run, but should exist)
  verify_installed_binaries "true"

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

# ==============================================================================
# Patch Installed Settings for Cross-Compiled GHC
# ==============================================================================
# Patches the installed settings file for cross-compiled GHC to:
#   1. Fix architecture references (host_arch → target_arch)
#   2. Add relocatable library paths (-L$topdir/../../../lib -rpath...)
#   3. Strip absolute BUILD_PREFIX paths from tool names
#
# This function handles the final settings patching that must happen after
# installation when host and target architectures differ.
#
# Parameters:
#   $1 - target (optional): Target triple, defaults to ghc_target/conda_target
#
# Required Variables:
#   - host_arch: Build host architecture (e.g., "x86_64")
#   - target_arch: Target architecture (e.g., "aarch64", "ppc64le")
#
# Usage:
#   cross_patch_installed_settings
#   cross_patch_installed_settings "${ghc_target}"
#
cross_patch_installed_settings() {
  local target="${1:-$(_get_target_triple)}"

  echo "  Patching installed settings for cross-compile..."

  local settings_file
  settings_file=$(get_installed_settings_file)

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: Could not find settings file in ${PREFIX}/lib/"
    return 0
  fi

  # Fix architecture references (e.g., x86_64 → aarch64)
  # This handles tool paths and other arch-specific strings
  perl -pi -e "s#${host_arch}(-[^ \"]*)#${target_arch}\$1#g" "${settings_file}"

  # Add relocatable library paths for conda prefix
  # These ensure the installed GHC can find conda-forge libraries at runtime
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"

  # Strip absolute tool paths - keep just the target prefix and tool name
  # Pattern: "/full/path/to/aarch64-conda-linux-gnu-ar" → "aarch64-conda-linux-gnu-ar"
  perl -pi -e "s#\"[^\"]*/([^/]*-)(ar|as|clang|clang\+\+|ld|nm|objdump|ranlib|llc|opt)\"#\"\$1\$2\"#g" "${settings_file}"

  echo "  ✓ Installed settings patched for ${target_arch}"
}
