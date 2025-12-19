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

# Source common hook defaults (provides no-op implementations)
source "${RECIPE_DIR}/lib/common-hooks.sh"

# Source Windows-specific helper functions
source "${RECIPE_DIR}/lib/windows-helpers.sh"

# Platform metadata
PLATFORM_NAME="Windows x86_64 (MinGW-w64 UCRT + GCC)"
PLATFORM_TYPE="native"
INSTALL_METHOD="bindist"
FLAVOUR="quickest"

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
  # Patch Hadrian's system.config file
  patch_windows_system_config

  echo "  Post-configure patches applied"
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

  # Find Hadrian binary (Windows uses .exe extension)
  local hadrian_bin=$(find "${_SRC_DIR}"/hadrian/dist-newstyle -name hadrian.exe -type f | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  # Set up Hadrian command array (uses Windows path format _SRC_DIR)
  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${_SRC_DIR}")

  echo "  Hadrian binary: ${hadrian_bin}"
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

platform_build_stage1() {
  echo "  Building Stage 1 GHC (Windows)..."

  # Build Stage 1 GHC compiler
  run_and_log "stage1-ghc" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage1:exe:ghc-bin

  # CRITICAL: After stage1:exe:ghc-bin creates _build/stage0/lib/settings,
  # patch it with include paths BEFORE building libraries that need ffi.h
  # NOTE: Do NOT add link flags here - Stage0 must use normal MinGW linking.
  patch_windows_settings "${_SRC_DIR}/_build/stage0/lib/settings" --include-paths

  # Build Stage 1 supporting tools
  run_and_log "stage1-pkg" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage1:exe:ghc-pkg
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage1:exe:hsc2hs

  # CRITICAL: Build Stage 1 libraries BEFORE Stage 2
  run_and_log "stage1-lib" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage1:lib:ghc

  echo "  ✓ Stage 1 GHC built"
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

platform_pre_build_stage2() {
  echo "  Running Windows-specific Stage2 pre-build..."

  # Create fake mingw structure for binary distribution
  create_fake_mingw_for_binary_dist

  echo "  ✓ Windows Stage2 pre-build complete"
}

platform_build_stage2() {
  echo "  Building Stage 2 GHC (Windows)..."

  # NOTE: Do NOT patch stage0 settings here - the bootstrap GHC must use
  # normal MinGW linking. Custom link flags are only for Stage1 settings.

  # CRITICAL: Build stage2:exe:ghc-bin FIRST to generate _build/stage1/lib/settings
  # This creates _build/stage1/bin/ghc.exe (NOT stage1:exe:ghc-bin which creates stage0!)
  run_and_log "stage2-exe" "${HADRIAN_CMD[@]}" stage2:exe:ghc-bin --flavour="${FLAVOUR}" --freeze1 ${HADRIAN_STAGE_OPTS}

  # Patch Stage1 settings (used by Stage2 build) with tool paths AND link flags.
  # Link flags are added here because Stage2 produces the final GHC binary.
  patch_windows_settings "${_SRC_DIR}/_build/stage1/lib/settings" --link-flags

  # Build Stage 2 supporting tools
  run_and_log "stage2-pkg" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage2:exe:ghc-pkg --freeze1 ${HADRIAN_STAGE_OPTS}
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage2:exe:hsc2hs --freeze1 ${HADRIAN_STAGE_OPTS}

  # CRITICAL: Rebuild touchy.exe with correct linker flags BEFORE stage2:lib:ghc
  # touchy.exe was built during stage1:exe:ghc-bin with Stage0 settings (no --enable-auto-import)
  # Stage1 ghc.exe (in _build/stage1/bin/) needs touchy.exe (in _build/stage1/lib/bin/)
  # to work correctly when compiling Stage2 libraries.
  rebuild_touchy_with_correct_linker_flags

  # Build Stage 2 GHC libraries
  # NOTE: Do NOT add Stage1 bin to PATH - Hadrian handles this internally.
  # Adding it would cause Cabal to find our Stage1 ghc.exe (which may have
  # relocation issues) and fail when trying to detect its version.
  echo "  Command: ${HADRIAN_CMD[*]} stage2:lib:ghc --flavour=${FLAVOUR} --freeze1 ${HADRIAN_STAGE_OPTS}"

  run_and_log "stage2-lib" "${HADRIAN_CMD[@]}" stage2:lib:ghc --flavour="${FLAVOUR}" --freeze1 ${HADRIAN_STAGE_OPTS} || {
    stage2_exit=$?
    echo "ERROR: stage2:lib:ghc failed with exit code ${stage2_exit}"
    exit ${stage2_exit}
  }

  echo "  ✓ Stage 2 GHC built"
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

  # Verify expected GHC binaries exist
  echo "  Checking GHC binaries in ${_PREFIX}/bin:"
  local -a expected_bins=(ghc.exe ghc-pkg.exe hsc2hs.exe runghc.exe hp2ps.exe hpc.exe)
  local missing=0
  for bin in "${expected_bins[@]}"; do
    if [[ -f "${_PREFIX}/bin/${bin}" ]]; then
      echo "    ✓ ${bin}"
    else
      echo "    ✗ ${bin} MISSING"
      ((missing++)) || true
    fi
  done

  # Show total file count
  local file_count=$(ls -1 "${_PREFIX}/bin" 2>/dev/null | wc -l)
  echo "  Total files in bin/: ${file_count}"

  if [[ ${missing} -gt 0 ]]; then
    echo "WARNING: ${missing} expected binaries missing"
  fi

  echo "  ✓ Windows post-install complete"
}
