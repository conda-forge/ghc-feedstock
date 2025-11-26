#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Windows x86_64 Native Build (MinGW-w64 UCRT)
# ==============================================================================
# Purpose: Configuration for native Windows x86_64 GHC builds using GCC
#
# Windows build uses GCC 15.2.0 (MinGW-w64 UCRT) instead of Clang to match
# the bootstrap GHC compiler. This prevents ABI mismatches between GCC-compiled
# RTS libraries and Clang-compiled Haskell code.
#
# Critical Windows-specific requirements:
# - Path conversion (Unix ↔ Windows format)
# - chkstk_ms stub library for stack checking
# - Bootstrap settings patching (merge-objects → GNU ld)
# - system.config patching (force system toolchain/FFI)
# - Single-threaded Hadrian build (avoids package.cache races)
#
# Dependencies: common-hooks.sh, lib/90-windows.sh
# ==============================================================================

set -eu

# Load common hook defaults
source "${RECIPE_DIR}/building/config/common-hooks.sh"

# ==============================================================================
# WINDOWS PATH INITIALIZATION
# ==============================================================================
# Convert conda environment variables from Windows paths to Unix paths
# MSYS2/Git Bash provides these as Unix paths (/c/...), but some code needs
# Windows paths (C:\...), so we keep both versions.

# Unix-style paths (for MSYS2/Git Bash tools)
export _BUILD_PREFIX="${BUILD_PREFIX}"
export _PREFIX="${PREFIX}"
export _SRC_DIR="${SRC_DIR}"

# ==============================================================================
# PLATFORM METADATA
# ==============================================================================

PLATFORM_NAME="windows-64"
PLATFORM_TYPE="native"
INSTALL_METHOD="native"

# ==============================================================================
# ARCHITECTURE DETECTION
# ==============================================================================

platform_detect_architecture() {
  # Windows uses x86_64-w64-mingw32 triple
  ghc_host="x86_64-unknown-mingw32"
  ghc_target="x86_64-unknown-mingw32"
  conda_target="x86_64-w64-mingw32"

  echo "  GHC host: ${ghc_host}"
  echo "  GHC target: ${ghc_target}"
  echo "  Conda target: ${conda_target}"
}

# ==============================================================================
# BOOTSTRAP SETUP
# ==============================================================================

platform_setup_bootstrap() {
  # Windows-specific bootstrap environment
  # Bootstrap GHC is at BUILD_PREFIX/ghc-bootstrap/bin/ghc.exe

  export PATH="${_BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}:/c/Windows/System32"
  export CABAL="${_BUILD_PREFIX}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}\.cabal"
  export _PYTHON="${_BUILD_PREFIX}/python.exe"
  export GHC="${BUILD_PREFIX}\\ghc-bootstrap\\bin\\ghc.exe"

  # Test bootstrap GHC is functional
  echo "  Testing bootstrap GHC..."
  "${GHC}" --version >/dev/null || {
    echo "ERROR: Bootstrap GHC failed to run"
    exit 1
  }
  echo "  Bootstrap GHC is functional"

  # Copy m4 to bin for autoconf
  mkdir -p "${_BUILD_PREFIX}/bin"
  cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin/" 2>/dev/null || true
}

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

platform_setup_environment() {
  # Windows-specific environment configuration
  # Critical: Must happen BEFORE configure

  # Step 1: Path conversion and flag cleanup
  setup_windows_paths

  # Step 2: GCC toolchain setup
  setup_windows_gcc_toolchain

  # Step 3: MinGW/UCRT integration
  setup_windows_mingw

  # Step 4: Create chkstk_ms stub library
  # CRITICAL: Must be created BEFORE patching bootstrap settings
  create_chkstk_stub

  # Step 5: Patch bootstrap GHC settings
  # CRITICAL: Must happen AFTER chkstk creation, BEFORE configure
  patch_bootstrap_settings_windows
}

# ==============================================================================
# CABAL SETUP
# ==============================================================================

platform_setup_cabal() {
  # Windows-specific Cabal configuration

  # Clean any stale .cabal directory (permission issues on package.cache)
  rm -rf "${_SRC_DIR}/.cabal" "${HOME}/.cabal" 2>/dev/null || true

  mkdir -p "${_SRC_DIR}/.cabal"

  # Use --force to overwrite existing config (may exist from previous run)
  "${CABAL}" user-config init --force

  # Update Cabal package database
  run_and_log "cabal-update" "${CABAL}" v2-update
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

platform_build_system_config() {
  # System configuration for Windows build
  SYSTEM_CONFIG=(
    --prefix="${_PREFIX}"
  )
}

platform_build_configure_args() {
  # Configure arguments for Windows build
  CONFIGURE_ARGS=(
    --enable-distro-toolchain
    --with-system-libffi=yes
    --with-intree-gmp=no
    --with-curses-includes="${_PREFIX}"/Library/include
    --with-curses-libraries="${_PREFIX}"/Library/lib
    --with-ffi-includes="${_PREFIX}"/Library/include
    --with-ffi-libraries="${_PREFIX}"/Library/lib
    --with-gmp-includes="${_PREFIX}"/Library/include
    --with-gmp-libraries="${_PREFIX}"/Library/lib
    --with-iconv-includes="${_PREFIX}"/Library/include
    --with-iconv-libraries="${_PREFIX}"/Library/lib
  )
}

platform_run_configure() {
  # Run configure with Windows-specific settings

  # Use GNU ld for linking (Windows format path for tool execution)
  local LD_UNIX="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
  local LD_WIN=$(echo "${LD_UNIX}" | sed 's#^/c/#C:/#')
  export LD="${LD_WIN}"

  # Run configure
  MergeObjsCmd="${LD}" \
  MergeObjsArgs="" \
  ./configure "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }
}

# ==============================================================================
# POST-CONFIGURE
# ==============================================================================

platform_post_configure() {
  # Post-configure setup for Windows
  # Patch Hadrian's system.config file
  patch_system_config_windows
}

# ==============================================================================
# BUILD FLAVOUR
# ==============================================================================

platform_select_flavour() {
  # Use release flavour for Windows builds
  HADRIAN_FLAVOUR="release"
}

# ==============================================================================
# HADRIAN BUILD
# ==============================================================================

platform_build_hadrian() {
  # Build Hadrian with Windows-specific settings
  #
  # CRITICAL: Use single-threaded build (-j1) to avoid race conditions
  # Parallel ghc-pkg updates can conflict on package.cache

  pushd "${_SRC_DIR}/hadrian" >/dev/null

  # Use LD in Windows format
  local LD_UNIX="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
  local LD_WIN=$(echo "${LD_UNIX}" | sed 's#^/c/#C:/#')

  run_and_log "build-hadrian" "${CABAL}" v2-build -j1 --with-ld="${LD_WIN}" hadrian

  popd >/dev/null

  # Find and verify Hadrian binary
  _hadrian_bin=$(find "${_SRC_DIR}"/hadrian/dist-newstyle -name hadrian.exe -type f | head -1)

  if [[ ! -f "${_hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  echo "  Hadrian binary: ${_hadrian_bin}"
}

# ==============================================================================
# STAGE BUILDS
# ==============================================================================

platform_build_stage1() {
  # Build Stage1 GHC using orchestrator
  #
  # Windows uses the standard build_stage1() from orchestrator
  # with explicit Hadrian binary and race condition prevention

  build_stage1
}

platform_build_stage2() {
  # Build Stage2 GHC using orchestrator
  #
  # Windows uses the standard build_stage2() from orchestrator
  # with explicit Hadrian binary and race condition prevention

  build_stage2
}

# ==============================================================================
# INSTALLATION
# ==============================================================================

platform_install() {
  # Install GHC using standard native installation
  #
  # Windows uses the standard install_ghc() from orchestrator

  install_ghc
}

# ==============================================================================
# POST-INSTALLATION
# ==============================================================================

platform_post_install() {
  # Windows-specific post-install steps
  # Currently no additional steps needed
  :
}
