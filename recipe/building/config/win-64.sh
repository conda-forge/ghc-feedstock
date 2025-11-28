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
# NOTE: build.bat has already prepared _BUILD_PREFIX, _PREFIX, _SRC_DIR with
# proper Unix format conversion. DO NOT redefine these variables here!
# build.bat converts Windows paths (C:\bld\...) to Unix format (/c/bld/...)

# ==============================================================================
# PLATFORM METADATA
# ==============================================================================

PLATFORM_NAME="win-64"
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

  # Build clean PATH - don't append conda's bad PATH with unexpanded %BUILD_PREFIX% placeholders
  # Include MSYS2 tools (m2-coreutils, m2-bash, etc.) from Library/usr/bin
  export PATH="${_BUILD_PREFIX}/Library/bin:${_BUILD_PREFIX}/Library/usr/bin:${_BUILD_PREFIX}/ghc-bootstrap/bin:${_BUILD_PREFIX}/bin:/c/Windows/System32:/c/Windows"
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

  # CRITICAL: Use gcc -E as preprocessor, not standalone cpp
  # GHC's configure tests preprocessor flags that only work with gcc -E
  # The standalone cpp doesn't handle -CC -Wno-unicode -nostdinc correctly
  export CPP="x86_64-w64-mingw32-gcc -E"

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

  echo "  Toolchain setup:"
  echo "    CPP=${CPP}"
}

# ==============================================================================
# CABAL SETUP
# ==============================================================================

platform_setup_cabal() {
  # Windows-specific Cabal configuration

  mkdir -p "${_SRC_DIR}/.cabal"

  # Only init if config doesn't exist (avoid "already exists" error)
  # The --force flag doesn't work reliably in all cabal versions
  if [[ ! -f "${_SRC_DIR}/.cabal/config" ]]; then
    "${CABAL}" user-config init
  else
    echo "  Cabal config already exists, skipping init"
  fi

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
  # Build standard configure args first
  build_configure_args CONFIGURE_ARGS

  # Add Windows-specific configure arguments
  CONFIGURE_ARGS+=(
    --enable-distro-toolchain
    --with-intree-gmp=no
  )
}

# ==============================================================================
# PRE-CONFIGURE SETUP
# ==============================================================================

platform_pre_configure() {
  # Windows-specific pre-configure setup
  export MergeObjsCmd="${LD}"
  export MergeObjsArgs=""

  # Enable verbose configure (skip run_and_log wrapper for debugging)
  export CONFIGURE_VERBOSE=true

  echo "  Pre-configure exports:"
  echo "    LD not set (gcc toolchain will provide)"
  echo "    MergeObjsCmd=${MergeObjsCmd}"
  echo "    CONFIGURE_VERBOSE=${CONFIGURE_VERBOSE}"
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

  # Build Hadrian without --with-ld (cabal will use system default)
  # Note: Passing --with-ld causes path mangling issues on Windows
  run_and_log "build-hadrian" "${CABAL}" v2-build -j1 hadrian

  popd >/dev/null

  # Find and verify Hadrian binary
  _hadrian_bin=$(find "${_SRC_DIR}"/hadrian/dist-newstyle -name hadrian.exe -type f | head -1)

  if [[ ! -f "${_hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  echo "  Hadrian binary: ${_hadrian_bin}"

  # Set up HADRIAN_BUILD array for orchestrator functions
  # HADRIAN_BUILD=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${_SRC_DIR}")
  HADRIAN_BUILD=("${_hadrian_bin}" "-j1" "--directory" "${_SRC_DIR}")
  echo "  Hadrian command: ${HADRIAN_BUILD[*]}"
}

# ==============================================================================
# STAGE BUILDS
# ==============================================================================

platform_build_stage1() {
  # Build Stage1 GHC using orchestrator
  #
  # Windows uses the standard build_stage1() from orchestrator
  # with explicit Hadrian binary and race condition prevention

  # Add toolchain to PATH for configure subprocesses
  # Hadrian spawns configure for individual packages which need to find gcc
  export PATH="${_BUILD_PREFIX}/Library/bin:${PATH}"

  echo "=== DEBUG: Stage1 Build Environment ==="
  echo "  _BUILD_PREFIX: ${_BUILD_PREFIX}"
  echo "  PATH (first 200 chars): ${PATH:0:200}"
  echo "  Looking for GCC at: ${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-gcc.exe"
  if [[ -f "${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-gcc.exe" ]]; then
    echo "  ✓ GCC found"
  else
    echo "  ✗ GCC NOT FOUND"
    echo "  Contents of ${_BUILD_PREFIX}/Library/bin:"
    ls -la "${_BUILD_PREFIX}/Library/bin" | head -20
  fi
  echo "  CC=${CC}"
  echo "  which gcc: $(which x86_64-w64-mingw32-gcc.exe 2>&1 || echo 'not in PATH')"
  echo "=== END DEBUG ==="

  # Enable verbose mode to see real-time output (skip run_and_log)
  export STAGE1_VERBOSE=true

  # build_stage1 HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
  build_stage1 HADRIAN_BUILD "${HADRIAN_FLAVOUR}" || {
    echo "=== Stage 1 build failed - searching for config.log ===" >&2
    config_log=$(find "${_SRC_DIR}" -name "config.log" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
    if [[ -n "${config_log}" ]]; then
      echo "=== Found config.log at: ${config_log} ===" >&2
      cat "${config_log}"
    else
      echo "=== No config.log found ===" >&2
    fi
    exit 1
  }
}

platform_build_stage2() {
  # Build Stage2 GHC using orchestrator
  #
  # Windows uses the standard build_stage2() from orchestrator
  # with explicit Hadrian binary and race condition prevention

  # Add toolchain to PATH for configure subprocesses
  # Hadrian spawns configure for individual packages which need to find gcc
  export PATH="${_BUILD_PREFIX}/Library/bin:${PATH}"

  build_stage2 HADRIAN_BUILD "${HADRIAN_FLAVOUR}"
}

# ==============================================================================
# INSTALLATION
# ==============================================================================

platform_install() {
  # Install GHC from binary distribution (like Linux)
  #
  # Windows must use bindist configure/install instead of Hadrian install
  # because the installed GHC needs proper Windows-specific configuration

  echo ""
  echo "========================================================================"
  echo "=== Installing GHC from Binary Distribution ==="
  echo "========================================================================"

  # Find the bindist directory
  local ghc_target="x86_64-w64-mingw32"
  local bindist_dir=$(find "${_SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)

  if [[ -z "${bindist_dir}" ]]; then
    echo "ERROR: Could not find binary distribution directory"
    echo "Looking for: ghc-${PKG_VERSION}-${ghc_target}"
    echo "Contents of _build/bindist:"
    ls -la "${_SRC_DIR}"/_build/bindist/ || true
    exit 1
  fi

  echo "Binary distribution directory: ${bindist_dir}"
  echo "Installing to: ${_PREFIX}"
  echo ""

  # Enter bindist directory and install
  pushd "${bindist_dir}" >/dev/null

  # Configure with PREFIX (bindist configure is simpler than main configure)
  ./configure --prefix="${_PREFIX}" || { cat config.log; exit 1; }

  # Install binaries, libraries, and man pages
  run_and_log "make_install" make install_bin install_lib install_man

  popd >/dev/null

  echo "✓ Installation completed"
  echo ""

  # Post-install: Replace bundled mingw
  echo "========================================================================"
  echo "=== Post-install: Replace bundled mingw and update settings ==="
  echo "========================================================================"

  # Remove bundled mingw and create minimal structure (like ghc-bootstrap)
  local installed_mingw="${_PREFIX}/lib/mingw"
  if [[ -d "${installed_mingw}" ]]; then
    echo "Removing bundled mingw at: ${installed_mingw}"
    rm -rf "${installed_mingw}"
  fi

  echo "Creating minimal mingw structure..."
  mkdir -p "${installed_mingw}"/{include,lib,bin,share}
  echo "Fake mingw directory - conda-forge provides toolchain" > "${installed_mingw}"/include/__unused__
  echo "Fake mingw directory - conda-forge provides toolchain" > "${installed_mingw}"/lib/__unused__
  echo "Fake mingw directory - conda-forge provides toolchain" > "${installed_mingw}"/bin/__unused__
  echo "Fake mingw directory - conda-forge provides toolchain" > "${installed_mingw}"/share/__unused__

  # Update settings file to use conda-forge toolchain
  local settings_file=$(find "${_PREFIX}"/lib/ -name settings | head -1)
  if [[ -f "${settings_file}" ]]; then
    echo ""
    echo "Updating settings file: ${settings_file}"

    # Remove hard-coded build env paths
    perl -pi -e "s#(${BUILD_PREFIX}|${PREFIX})/(bin|lib)/##g" "${settings_file}"

    echo "Settings file toolchain configuration:"
    grep -E "(C compiler command|C compiler link flags|ar command|ld command)" "${settings_file}" || true
  else
    echo "WARNING: Could not find settings file"
  fi

  # Verify installation
  echo ""
  echo "========================================================================"
  echo "=== Verifying GHC installation ==="
  echo "========================================================================"
  echo "GHC binaries in ${_PREFIX}/bin:"
  ls -la "${_PREFIX}/bin" | head -20

  echo ""
  echo "GHC library structure:"
  if [[ -d "${_PREFIX}/lib/ghc-${PKG_VERSION}" ]]; then
    echo "✓ Found lib/ghc-${PKG_VERSION}"
    ls -la "${_PREFIX}/lib/ghc-${PKG_VERSION}" | head -10
  elif [[ -d "${_PREFIX}/lib/x86_64-windows-ghc-${PKG_VERSION}" ]]; then
    echo "✓ Found lib/x86_64-windows-ghc-${PKG_VERSION}"
    ls -la "${_PREFIX}/lib/x86_64-windows-ghc-${PKG_VERSION}" | head -10
  else
    echo "WARNING: Could not find GHC library directory"
    echo "Contents of ${_PREFIX}/lib:"
    ls -la "${_PREFIX}/lib" | head -20
  fi

  echo ""
  echo "========================================================================"
  echo "=== GHC ${PKG_VERSION} Windows build completed successfully! ==="
  echo "========================================================================"
}

# ==============================================================================
# POST-INSTALLATION
# ==============================================================================

platform_post_install() {
  # Windows-specific post-install steps
  # Currently no additional steps needed
  :
}
