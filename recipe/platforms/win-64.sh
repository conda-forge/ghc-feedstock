#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Windows x86_64 (MinGW-w64 UCRT + GCC)
# ==============================================================================
# Windows-specific build behavior using GCC toolchain to match bootstrap GHC.
#
# Key implementation details:
# - GCC/G++ toolchain (x86_64-w64-mingw32-gcc) matches bootstrap GHC compiler
# - UCRT runtime (Universal C Runtime)
# - GNU ld with --enable-auto-import for proper PE import tables
# - High image base (0x140000000) to avoid relocation errors
# - Direct touchy.exe rebuild (bypasses Hadrian caching issues)
# - Binary distribution install method (relocatable Windows GHC)
#
# See CLAUDE.md for full build documentation and troubleshooting.
# ==============================================================================

set -eu

# Source Windows-specific helper functions
source "${RECIPE_DIR}/lib/windows-helpers.sh"

# Platform metadata
PLATFORM_NAME="Windows x86_64 (MinGW-w64 UCRT + GCC)"
PLATFORM_TYPE="native"
INSTALL_METHOD="bindist"
FLAVOUR="quickest"

# Configure triples for native Windows build
# Sets: ghc_build, ghc_host, ghc_target, ghc_triple, conda_*
configure_triples

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

platform_setup_environment() {
  echo "  Configuring Windows-specific environment..."

  # Build clean PATH - don't append conda's bad PATH with unexpanded %BUILD_PREFIX% placeholders
  # Include MSYS2 tools (m2-coreutils, m2-bash, etc.) from Library/usr/bin
  export PATH="${_BUILD_PREFIX}/Library/bin:${_BUILD_PREFIX}/Library/usr/bin:${_BUILD_PREFIX}/ghc-bootstrap/bin:${_BUILD_PREFIX}/bin:/c/Windows/System32:/c/Windows"

  # Set up MinGW-w64 toolchain paths (these are in Library/bin/ with full triple prefix)
  # CRITICAL: Use _BUILD_PREFIX_ (C:/bld/...) not _BUILD_PREFIX (/c/bld/...)
  # GHC on Windows needs Windows-format paths to execute tools
  export CC="x86_64-w64-mingw32-gcc"
  export CXX="x86_64-w64-mingw32-g++"
  export CPP="x86_64-w64-mingw32-cpp"
  export LD="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-ld.exe"
  export AR="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-ar.exe"
  export NM="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-nm.exe"
  export RANLIB="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-ranlib.exe"
  export OBJDUMP="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-objdump.exe"
  export STRIP="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-strip.exe"
  export DLLWRAP="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-dllwrap.exe"
  export WINDRES="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-windres.exe"

  # Set up Cabal environment
  export CABAL="${_BUILD_PREFIX}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}\\.cabal"
  export GHC="${_BUILD_PREFIX}/ghc-bootstrap/bin/ghc.exe"
  # Python path for Hadrian - must use Windows format (C:/...) for GHC
  export PYTHON="${_BUILD_PREFIX_}/python.exe"
  export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

  # Expand conda variables in flags
  windows_expand_conda_variables

  # Remove problematic flags
  windows_remove_problematic_flags

  export CFLAGS="-I${_BUILD_PREFIX}/Library/include ${CFLAGS:-}"
  export CXXFLAGS="-I${_BUILD_PREFIX}/Library/include ${CXXFLAGS:-}"
  export LDFLAGS="-L${_BUILD_PREFIX}/Library/lib -L${_BUILD_PREFIX}/Library/lib/gcc/x86_64-w64-mingw32/15.2.0 ${LDFLAGS:-}"

  # Fix windres.bat (ghc-bootstrap bug)
  if [[ -f "${_BUILD_PREFIX}/ghc-bootstrap/bin/windres.bat" ]]; then
    perl -pi -e 's/findstr/C:\\Windows\\System32\\findstr/g' "${_BUILD_PREFIX}/ghc-bootstrap/bin/windres.bat"
  fi

  # Create chkstk_ms stub library
  create_chkstk_stub

  # Install windres wrapper
  if [[ -f "${_RECIPE_DIR}/support/windres.bat" ]]; then
    cp "${_RECIPE_DIR}/support/windres.bat" "${_BUILD_PREFIX}/Library/bin/"
    echo "  Installed windres.bat wrapper"
  fi

  # Patch bootstrap settings (tool paths, CFLAGS, dllwrap=false, etc.)
  patch_windows_settings "${_BUILD_PREFIX}/ghc-bootstrap/lib/settings" --bootstrap --debug

  # Set up temp variables
  export TMP="$(cygpath -w "${TEMP}")"
  export TMPDIR="$(cygpath -w "${TEMP}")"

  # Copy m4 to bin for autoconf
  mkdir -p "${_BUILD_PREFIX}/bin"
  cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin/" 2>/dev/null || true

  echo "  ✓ Windows environment configured"
}

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

platform_setup_cabal() {
  echo "  Configuring Windows Cabal..."

  # Clean stale .cabal directories
  rm -rf "${_SRC_DIR}/.cabal" "${HOME}/.cabal"
  mkdir -p "${_SRC_DIR}/.cabal"
  "${CABAL}" user-config init

  # Pass chkstk_ms library through LDFLAGS for linking
  export LDFLAGS="${LDFLAGS} -lchkstk_ms"

  run_and_log "cabal-update" "${CABAL}" v2-update || { cat "${_SRC_DIR}"/_logs/cabal-update.log; return 1; }

  echo "  ✓ Cabal configured"
}

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

platform_pre_configure_ghc() {
  # Force use of conda-provided toolchain and libraries (not inplace MinGW)
  export UseSystemMingw=YES
  export WindowsToolchainAutoconf=NO
  export WINDOWS_TOOLCHAIN_AUTOCONF=no
  export UseSystemFfi=YES
  export CXX_STD_LIB_LIBS="stdc++"

  # Set autoconf variables (Windows-specific: ffi, DLLWRAP, WINDRES)
  set_autoconf_toolchain_vars --windows

  # Set up Windows SDK paths
  setup_windows_sdk

  echo "  Pre-configure environment set"
}

platform_post_configure_ghc() {
  # Use unified post-configure orchestrator (auto-detects Windows)
  shared_post_configure_ghc
}

# ==============================================================================
# Phase 5: Build Hadrian
# ==============================================================================

# Note: Windows needs custom Hadrian build due to _SRC_DIR path format
platform_build_hadrian() {
  echo "  Building Hadrian (Windows)..."

  pushd "${_SRC_DIR}/hadrian" >/dev/null
  run_and_log "build-hadrian" "${CABAL}" v2-build -j${CPU_COUNT} hadrian
  popd >/dev/null

  # Find and set up Hadrian binary (searches in dist-newstyle, not /build subdir)
  update_hadrian_cmd_after_build "${_SRC_DIR}/hadrian/dist-newstyle"
}

# ==============================================================================
# Phase 6: Build Stage 1 (uses default_build_stage1 with hooks)
# ==============================================================================
# Windows uses the standard stage build pattern with granular hooks:
#   1. ghc-bin → platform_post_stage1_ghc_bin (patch include paths)
#   2. ghc-pkg, hsc2hs
#   3. platform_build_stage1_libraries (Windows-specific library build)

# Hook: Called after stage1:exe:ghc-bin, before ghc-pkg/hsc2hs
# Patches settings with include paths for ffi.h, gmp.h, etc.
platform_post_stage1_ghc_bin() {
  # CRITICAL: After stage1:exe:ghc-bin creates _build/stage0/lib/settings,
  # patch it with include paths BEFORE building libraries that need ffi.h
  # NOTE: Do NOT add link flags here - Stage0 must use normal MinGW linking.
  patch_windows_settings "${_SRC_DIR}/_build/stage0/lib/settings" --include-paths
}

# Hook: Override library build for Windows-specific behavior
# NOTE: Windows uses windows_build_stage_libraries() instead of build_stage_libraries()
# because Windows builds have different failure modes (no retry logic needed) and
# don't use HADRIAN_STAGE_OPTS. This separation is intentional for maintainability.
platform_build_stage1_libraries() {
  windows_build_stage_libraries 1
}

# ==============================================================================
# Phase 7: Build Stage 2 (uses default_build_stage2 with hooks)
# ==============================================================================
# Windows uses the standard stage build pattern with granular hooks:
#   1. ghc-bin → platform_post_stage2_ghc_bin (patch link flags)
#   2. ghc-pkg, hsc2hs
#   3. platform_pre_stage2_libraries (rebuild touchy)
#   4. platform_build_stage2_libraries (Windows-specific library build)

platform_pre_build_stage2() {
  echo "  Running Windows-specific Stage2 pre-build..."

  # Create fake mingw structure for binary distribution
  create_fake_mingw_for_binary_dist

  echo "  ✓ Windows Stage2 pre-build complete"
}

# Hook: Called after stage2:exe:ghc-bin, before ghc-pkg/hsc2hs
# Patches settings with link flags for final binary
platform_post_stage2_ghc_bin() {
  # Patch Stage1 settings (used by Stage2 build) with tool paths AND link flags.
  # Link flags are added here because Stage2 produces the final GHC binary.
  patch_windows_settings "${_SRC_DIR}/_build/stage1/lib/settings" --link-flags
}

# Hook: Called before library build, after all executables
# Rebuilds touchy.exe with correct linker flags
platform_pre_stage2_libraries() {
  # CRITICAL: Rebuild touchy.exe with correct linker flags BEFORE stage2:lib:ghc
  # touchy.exe was built during stage1:exe:ghc-bin with Stage0 settings (no --enable-auto-import)
  # Stage1 ghc.exe (in _build/stage1/bin/) needs touchy.exe (in _build/stage1/lib/bin/)
  # to work correctly when compiling Stage2 libraries.
  rebuild_touchy_with_correct_linker_flags
}

# Hook: Override library build for Windows-specific behavior
platform_build_stage2_libraries() {
  local -a extra_opts=("$@")

  # Build Stage 2 GHC libraries
  # NOTE: Do NOT add Stage1 bin to PATH - Hadrian handles this internally.
  # Adding it would cause Cabal to find our Stage1 ghc.exe (which may have
  # relocation issues) and fail when trying to detect its version.
  echo "  Command: ${HADRIAN_CMD[*]} stage2:lib:ghc --flavour=${FLAVOUR} --freeze1 ${HADRIAN_STAGE_OPTS}"

  run_and_log "stage2-lib" "${HADRIAN_CMD[@]}" stage2:lib:ghc --flavour="${FLAVOUR}" --freeze1 ${HADRIAN_STAGE_OPTS} || {
    local stage2_exit=$?
    echo "ERROR: stage2:lib:ghc failed with exit code ${stage2_exit}"
    exit ${stage2_exit}
  }

  echo "  ✓ Stage 2 libraries built"
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

platform_install_ghc() {
  echo "  Installing GHC from binary distribution (Windows method)..."

  # Create binary distribution directory (no compression - we copy directly)
  # binary-dist-dir is faster than binary-dist-gzip since we don't need the tarball
  run_and_log "bindist" "${HADRIAN_CMD[@]}" binary-dist-dir --prefix="${_PREFIX}" --flavour="${FLAVOUR}" --freeze1 --freeze2 ${HADRIAN_STAGE_OPTS}

  # Find bindist directory
  # GHC uses x86_64-unknown-mingw32 (not x86_64-w64-mingw32) for Windows target
  local ghc_target="x86_64-unknown-mingw32"
  local bindist_dir=$(find "${_SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)

  if [[ -z "${bindist_dir}" ]]; then
    echo "ERROR: Could not find binary distribution directory"
    echo "Looking for: ghc-${PKG_VERSION}-${ghc_target}"
    echo "Contents of _build/bindist:"
    ls -la "${_SRC_DIR}"/_build/bindist/ || true
    exit 1
  fi

  echo "  Binary distribution directory: ${bindist_dir}"
  echo "  Installing to: ${_PREFIX}"

  # Windows binary distributions are relocatable - just copy the contents
  cp -r "${bindist_dir}"/* "${_PREFIX}"/

  # Copy windres wrapper for installed package
  cp "${_BUILD_PREFIX}/Library/bin/windres.bat" "${_PREFIX}/bin/ghc_windres.bat"

  echo "  ✓ Installation completed"

  # Post-install: Replace bundled mingw and update settings
  post_install_cleanup

  echo "  ✓ GHC installation complete"
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

platform_post_install() {
  echo "  Running Windows-specific post-install verification..."

  # Verify expected GHC binaries exist (error on missing)
  verify_installed_binaries || exit 1

  echo "  ✓ Windows post-install complete"
}
