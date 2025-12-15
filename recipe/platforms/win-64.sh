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
  export CC="x86_64-w64-mingw32-gcc"
  export CXX="x86_64-w64-mingw32-g++"
  export CPP="x86_64-w64-mingw32-cpp"
  export LD="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
  export AR="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ar.exe"
  export NM="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-nm.exe"
  export RANLIB="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ranlib.exe"
  export OBJDUMP="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-objdump.exe"
  export STRIP="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-strip.exe"
  export DLLWRAP="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-dllwrap.exe"
  export WINDRES="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-windres.exe"

  # Set up Cabal environment
  export CABAL="${_BUILD_PREFIX}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}\\.cabal"
  export GHC="${_BUILD_PREFIX}/ghc-bootstrap/bin/ghc.exe"
  export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

  # Expand conda variables in flags
  expand_conda_variables

  # Remove problematic flags
  remove_problematic_flags

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
# Phase 2: Bootstrap Setup
# ==============================================================================

# NOTE: platform_setup_bootstrap() removed - phases.sh already verifies bootstrap
# GHC after calling common_setup_environment() and any platform overrides.

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

platform_setup_cabal() {
  echo "  Configuring Windows Cabal..."

  # Clean any stale .cabal directory that might have permission issues
  echo "  Cleaning stale .cabal directory to prevent permission issues..."
  rm -rf "${_SRC_DIR}/.cabal"
  rm -rf "${HOME}/.cabal"

  mkdir -p "${_SRC_DIR}/.cabal"
  "${CABAL}" user-config init

  # CRITICAL: Pass chkstk_ms library through LDFLAGS for linking
  echo "  Adding chkstk_ms library to LDFLAGS..."
  export LDFLAGS="${LDFLAGS} -lchkstk_ms"

  run_and_log "cabal-update" "${CABAL}" v2-update || { cat "${_SRC_DIR}"/_logs/cabal-update.log; return 1; }

  echo "  ✓ Cabal configured"
}

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

# NOTE: platform_add_configure_args removed - build_configure_args in helpers.sh
# now handles Windows paths automatically (${_PREFIX}/Library/{include,lib})

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
  patch_system_config

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
  run_and_log "stage2-exe" "${HADRIAN_CMD[@]}" stage2:exe:ghc-bin --flavour="${FLAVOUR}" --freeze1 --docs=none --progress-info=none

  # Patch Stage1 settings (used by Stage2 build) with tool paths AND link flags.
  # Link flags are added here because Stage2 produces the final GHC binary.
  patch_windows_settings "${_SRC_DIR}/_build/stage1/lib/settings" --link-flags

  # Build Stage 1 supporting tools
  run_and_log "stage2-pkg" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage2:exe:ghc-pkg --freeze1 --docs=none --progress-info=none
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" stage2:exe:hsc2hs --freeze1 --docs=none --progress-info=none

  # CRITICAL: Rebuild touchy.exe with correct linker flags BEFORE stage2:lib:ghc
  # touchy.exe was built during stage1:exe:ghc-bin with Stage0 settings (no --enable-auto-import)
  # Stage1 ghc.exe (in _build/stage1/bin/) needs touchy.exe (in _build/stage1/lib/bin/)
  # to work correctly when compiling Stage2 libraries.
  rebuild_touchy_with_correct_linker_flags

  # Build Stage 2 GHC libraries
  # NOTE: Do NOT add Stage1 bin to PATH - Hadrian handles this internally.
  # Adding it would cause Cabal to find our Stage1 ghc.exe (which may have
  # relocation issues) and fail when trying to detect its version.
  echo "  Command: ${HADRIAN_CMD[*]} stage2:lib:ghc --flavour=${FLAVOUR} --freeze1 --docs=none --progress-info=none"

  run_and_log "stage2-lib" "${HADRIAN_CMD[@]}" stage2:lib:ghc --flavour="${FLAVOUR}" --freeze1 --docs=none --progress-info=none || {
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
  run_and_log "bindist" "${HADRIAN_CMD[@]}" binary-dist-dir --prefix="${_PREFIX}" --flavour="${FLAVOUR}" --freeze1 --freeze2 --docs=none

  # Find bindist directory
  local ghc_target="x86_64-w64-mingw32"
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

  # Verify GHC binaries
  echo "  GHC binaries in ${_PREFIX}/bin:"
  ls -la "${_PREFIX}/bin" | head -20

  echo "  ✓ Windows post-install complete"
}

# ==============================================================================
# Helper Functions
# ==============================================================================

# ------------------------------------------------------------------------------
# Unified GHC Settings Patching
# ------------------------------------------------------------------------------
# Patches GHC settings files with conda toolchain paths and flags.
#
# Usage:
#   patch_windows_settings <settings_file> [options...]
#
# Options:
#   --include-paths    Add include paths for ffi.h, gmp.h, etc.
#   --link-flags       Add Windows-specific linker flags (for final binary)
#   --bootstrap        Apply bootstrap-specific patches (dllwrap=false, CFLAGS, etc.)
#   --debug            Show settings file after patching
# ------------------------------------------------------------------------------

patch_windows_settings() {
  local settings_file="$1"
  shift

  # Parse options
  local add_include_paths=false
  local add_link_flags=false
  local is_bootstrap=false
  local debug_output=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-paths) add_include_paths=true ;;
      --link-flags) add_link_flags=true ;;
      --bootstrap) is_bootstrap=true ;;
      --debug) debug_output=true ;;
      *) echo "WARNING: Unknown option: $1" ;;
    esac
    shift
  done

  if [[ ! -f "${settings_file}" ]]; then
    echo "WARNING: Settings file not found at ${settings_file}"
    return 1
  fi

  echo "  Patching: ${settings_file}"

  # --- Tool path patching (common to all) ---
  perl -pi -e "s#(C compiler command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  perl -pi -e "s#(Haskell CPP command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler command\", \")[^\"]*#\$1${CXX}#" "${settings_file}"
  perl -pi -e "s#(ld command\", \")[^\"]*#\$1${LD}#" "${settings_file}"
  perl -pi -e "s#(Merge objects command\", \")[^\"]*#\$1${LD}#" "${settings_file}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR}#" "${settings_file}"
  perl -pi -e "s#(nm command\", \")[^\"]*#\$1${NM}#" "${settings_file}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1${RANLIB}#" "${settings_file}"
  perl -pi -e "s#(objdump command\", \")[^\"]*#\$1${OBJDUMP}#" "${settings_file}"
  perl -pi -e "s#(strip command\", \")[^\"]*#\$1${STRIP}#" "${settings_file}"
  perl -pi -e "s#(dllwrap command\", \")[^\"]*#\$1${DLLWRAP}#" "${settings_file}"

  # --- windres wrapper (common to all) ---
  if [[ -f "${_BUILD_PREFIX}/Library/bin/windres.bat" ]]; then
    perl -pi -e "s#(windres command\", \")[^\"]*#\$1${_BUILD_PREFIX_}/Library/bin/windres.bat#" "${settings_file}"
  else
    echo "  WARNING: windres.bat not found at ${_BUILD_PREFIX}/Library/bin/windres.bat"
    echo "  windres setting will NOT be patched - this may cause build failures!"
  fi

  # --- Bootstrap-specific patches ---
  if [[ "${is_bootstrap}" == "true" ]]; then
    # Disable dllwrap (not used, causes issues)
    perl -pi -e "s#(dllwrap command\", \")[^\"]*#\$1false#" "${settings_file}"

    # Replace bootstrap's mingw/include with conda include paths
    perl -pi -e "s#-I\\\$tooldir/mingw/include#-I${_BUILD_PREFIX}/Library/include#g" "${settings_file}"

    # Add CFLAGS to compiler flags
    perl -pi -e "s#(C compiler flags\", \")([^\"]*)#\$1\$2 ${CFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"
    perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)#\$1\$2 ${CXXFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"

    # Haskell CPP needs traditional-cpp for Haskell compatibility
    perl -pi -e "s#(Haskell CPP flags\", \")[^\"]*#\$1-E -undef -traditional-cpp -I${_BUILD_PREFIX}/Library/include -I${_PREFIX}/Library/include#" "${settings_file}"
  fi

  # --- Include paths for ffi.h, gmp.h, etc. (stage0, not stage2) ---
  if [[ "${add_include_paths}" == "true" ]]; then
    perl -pi -e "s#(C compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
    perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  fi

  # --- Link flags for final binary (stage2 only) ---
  # IMPORTANT: Do NOT add link flags to bootstrap or stage0 - they must use
  # normal MinGW linking so intermediate Haskell programs work correctly.
  if [[ "${add_link_flags}" == "true" ]]; then
    local CHKSTK_DIR="${_BUILD_PREFIX}/Library/lib"
    local MINGW_SYSROOT="${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib"

    # Build complete link flags string
    # CRITICAL: Use -Xlinker prefix because flags go through GHC to linker
    local LINK_FLAGS="-Wl,--subsystem,console -Wl,--enable-auto-import -Wl,--image-base=0x140000000 -Wl,--dynamicbase -Wl,--high-entropy-va -Xlinker -L${CHKSTK_DIR} -Xlinker -L${MINGW_SYSROOT}"
    LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmoldname -Xlinker -lmingwex -Xlinker -lmingw32 -Xlinker -lchkstk_ms -Xlinker -lgcc -Xlinker -lucrt -Xlinker -lkernel32 -Xlinker -ladvapi32"

    perl -pi -e "s#(C compiler link flags\", \")#\$1${LINK_FLAGS} #" "${settings_file}"
    perl -pi -e "s#(ld flags\", \")#\$1--subsystem,console --enable-auto-import --image-base=0x140000000 --dynamicbase --high-entropy-va -L${CHKSTK_DIR} -L${MINGW_SYSROOT} -lmoldname -lmingwex -lmingw32 -lchkstk_ms -lgcc -lucrt -lkernel32 -ladvapi32 #" "${settings_file}"
  fi

  # --- Debug output ---
  if [[ "${debug_output}" == "true" ]]; then
    echo "  ===== SETTINGS FILE (after patching) ====="
    cat "${settings_file}"
    echo "  ===== END SETTINGS ====="
  fi

  echo "  ✓ Settings patched"
}

expand_conda_variables() {
  # CRITICAL: Replace ALL conda variables with Unix paths to prevent backslash escape issues
  # When %PREFIX% expands to C:\bld\..., the \b becomes backspace character!

  echo "  Expanding conda variables in CFLAGS/CXXFLAGS/LDFLAGS..."

  CFLAGS=$(echo "${CFLAGS}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")

  CFLAGS=$(echo "${CFLAGS}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
}

remove_problematic_flags() {
  echo "  Removing problematic flags..."

  # Remove problematic flags from conda environment
  CFLAGS="${CFLAGS//-nostdlib/}"
  CXXFLAGS="${CXXFLAGS//-nostdlib/}"
  LDFLAGS="${LDFLAGS//-nostdlib/}"

  # Use GNU ld (bfd) for MinGW compatibility (lld defaults to MSVC mode on Windows)
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fuse-ld=lld/-fuse-ld=bfd/g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fuse-ld=lld/-fuse-ld=bfd/g')
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe 's/-fuse-ld=lld/-fuse-ld=bfd/g')

  # Remove problematic -Wl,-defaultlib: flags (MSVC-specific)
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe 's/-Wl,-defaultlib:[^ ]*//g')

  # Remove -fstack-protector-strong (generates __security_cookie calls incompatible with MinGW)
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fstack-protector-strong//g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fstack-protector-strong//g')

  # Remove -fms-runtime-lib=dll (forces Microsoft MSVCRT)
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fms-runtime-lib=dll//g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fms-runtime-lib=dll//g')

  # Remove flags with corrupted Windows paths
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fdebug-prefix-map=[^ ]*//g; s/-isystem [^ ]*//g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fdebug-prefix-map=[^ ]*//g; s/-isystem [^ ]*//g')

  export CFLAGS CXXFLAGS LDFLAGS
}

create_chkstk_stub() {
  echo "  Creating ___chkstk_ms stub library..."

  local CHKSTK_OBJ="${_SRC_DIR}/chkstk_ms.o"
  local CHKSTK_LIB="${_BUILD_PREFIX}/Library/lib/libchkstk_ms.a"

  # Check if source file exists
  if [[ ! -f "${_RECIPE_DIR}/support/chkstk_ms.c" ]]; then
    # Create inline if not exists
    cat > "${_SRC_DIR}/chkstk_ms.c" <<'EOF'
void ___chkstk_ms(void) {
  /* Stub implementation */
}
EOF
    ${CC} -c "${_SRC_DIR}/chkstk_ms.c" -o "${CHKSTK_OBJ}"
  else
    ${CC} -c "${_RECIPE_DIR}/support/chkstk_ms.c" -o "${CHKSTK_OBJ}"
  fi

  ${AR} rcs "${CHKSTK_LIB}" "${CHKSTK_OBJ}"

  if [[ ! -f "${CHKSTK_LIB}" ]]; then
    echo "ERROR: Failed to create chkstk_ms library"
    exit 1
  fi

  echo "  ✓ Created ${CHKSTK_LIB}"
}

# NOTE: Legacy wrapper functions removed - now calling patch_windows_settings() directly:
# - patch_bootstrap_settings() → patch_windows_settings ... --bootstrap --debug
# - patch_stage0_settings_include_paths() → patch_windows_settings ... --include-paths
# - patch_stage2_settings() → patch_windows_settings ... --link-flags
# - test_stage1_ghc() → removed (was dead code, never called)

rebuild_touchy_with_correct_linker_flags() {
  echo "  Rebuilding touchy.exe with correct linker flags..."

  local touchy_source="${_SRC_DIR}/utils/touchy/touchy.c"
  local touchy_output="${_SRC_DIR}/_build/stage1/lib/bin/touchy.exe"

  if [[ -f "${touchy_output}" ]]; then
    echo "  Deleting old touchy.exe..."
    rm -f "${touchy_output}"
  fi

  if [[ ! -f "${touchy_source}" ]]; then
    echo "ERROR: touchy.c source not found at ${touchy_source}"
    exit 1
  fi

  mkdir -p "$(dirname "${touchy_output}")"

  echo "  Compiling touchy.exe with correct flags..."
  "${CC}" "${touchy_source}" -o "${touchy_output}" \
    -Wl,--enable-auto-import \
    -Wl,--image-base=0x140000000 \
    -Wl,--dynamicbase \
    -Wl,--high-entropy-va \
    -lucrt -lkernel32 || {
    echo "ERROR: Failed to compile touchy.exe"
    exit 1
  }

  if [[ ! -f "${touchy_output}" ]]; then
    echo "ERROR: touchy.exe not created"
    exit 1
  fi

  echo "  ✓ touchy.exe rebuilt successfully"
}

create_fake_mingw_for_binary_dist() {
  echo "  Creating fake mingw directory for binary distribution..."

  local fake_mingw="${_SRC_DIR}/_build/mingw"
  mkdir -p "${fake_mingw}"/{include,lib,bin,share}

  echo "This is a placeholder mingw directory." > "${fake_mingw}/README.txt"
  echo "Conda-forge provides the actual MinGW toolchain." >> "${fake_mingw}/README.txt"

  for subdir in include lib bin share; do
    echo "Fake mingw directory - conda-forge provides toolchain" > "${fake_mingw}/${subdir}/__placeholder__"
  done

  echo "  ✓ Created fake mingw at: ${fake_mingw}"
}

post_install_cleanup() {
  echo "  Post-install cleanup..."

  # Remove bundled mingw and create minimal structure
  local installed_mingw="${_PREFIX}/lib/mingw"
  if [[ -d "${installed_mingw}" ]]; then
    echo "  Removing bundled mingw..."
    rm -rf "${installed_mingw}"
  fi

  echo "  Creating minimal mingw structure..."
  mkdir -p "${installed_mingw}"/{include,lib,bin,share}
  for subdir in include lib bin share; do
    echo "Fake mingw directory - conda-forge provides toolchain" > "${installed_mingw}/${subdir}/__unused__"
  done

  # Update settings file to use conda-forge toolchain
  local settings_file=$(find "${_PREFIX}"/lib/ -name settings | head -1)
  if [[ -f "${settings_file}" ]]; then
    echo "  Updating installed settings file..."

    # Fix: Change \$2 to $2 for proper backreference
    perl -pi -e 's#((?:C compiler|C\+\+ compiler|Haskell CPP|ld|Merge objects|ar|ranlib) command",\s*")[^"]*-(gcc|g\+\+|ld|ar|ranlib)(?:.exe)?#$1x86_64-w64-mingw32-$2.exe#' "${settings_file}"
    perl -pi -e 's#(windres command",\s*")[^"]*#$1\$topdir/../bin/ghc_windres.bat#' "${settings_file}"
    perl -pi -e 's#(compiler link flags",\s*"[^"]*)#$1 -Wl,-L\$topdir/../../lib#' "${settings_file}"
    perl -pi -e 's#(ld flags",\s*"[^"]*)#$1 -L\$topdir/../../lib#' "${settings_file}"

    echo "  ✓ Settings file updated"
  else
    echo "WARNING: Could not find settings file"
  fi
}

setup_windows_sdk() {
  # Set up Windows SDK paths (if needed)
  local SDK_PATH=$(ls -1d /c/Program*Files*x86*/Windows*/10 2>/dev/null | head -1)

  if [[ -n "${SDK_PATH}" ]]; then
    SDK_PATH=$(cygpath -u "$(cygpath -d "${SDK_PATH}")")
    local SDK_VER=$(ls -1 "${SDK_PATH}"/Include/ 2>/dev/null | grep "^10\." | sort -V | tail -1)

    export UCRT_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/ucrt"
    export UM_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/um"

    echo "  Windows SDK configured: ${SDK_VER}"
  fi
}

patch_system_config() {
  echo "  Patching Hadrian system.config..."

  local config_file="${_SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${config_file}" ]]; then
    echo "WARNING: system.config not found at ${config_file}"
    return 1
  fi

  # Fix Python path
  perl -pi -e "s#(^python\\s*=).*#\$1 ${CONDA_PYTHON_EXE}#" "${config_file}"

  # Expand conda variables - both %VAR% and $ENV{VAR} patterns
  perl -pi -e "s#%PREFIX%#${_PREFIX}#g" "${config_file}"
  perl -pi -e "s#%BUILD_PREFIX%#${_BUILD_PREFIX}#g" "${config_file}"
  perl -pi -e "s#%SRC_DIR%#${_SRC_DIR}#g" "${config_file}"

  perl -pi -e "s#\\\$ENV{PREFIX}#${_PREFIX}#g" "${config_file}"
  perl -pi -e "s#\\\$ENV{BUILD_PREFIX}#${_BUILD_PREFIX}#g" "${config_file}"
  perl -pi -e "s#\\\$ENV{SRC_DIR}#${_SRC_DIR}#g" "${config_file}"

  # CRITICAL: Convert all *-dir paths from Unix (/c/...) to Windows (C:/...) format
  # This prevents Cabal from treating absolute paths as relative and mangling them
  # e.g., gmp-include-dir = /c/bld/... -> gmp-include-dir = C:/bld/...
  perl -pi -e 's#^([a-z-]+dir)\s*=\s*/c/#$1 = C:/#g' "${config_file}"

  # Force use of system toolchain and libraries
  perl -pi -e 's#^use-system-mingw\s*=\s*.*$#use-system-mingw = YES#' "${config_file}"
  perl -pi -e 's#^windows-toolchain-autoconf\s*=\s*.*$#windows-toolchain-autoconf = NO#' "${config_file}"
  perl -pi -e 's#^use-system-ffi\s*=\s*.*$#use-system-ffi = YES#' "${config_file}"
  perl -pi -e "s#^intree-gmp\s*=\s*.*#intree-gmp = NO#" "${config_file}"

  # NOTE: Do NOT add --allow-multiple-definition here!
  # The proper solution is library ordering in Stage1 settings where -lmingw32
  # comes AFTER user objects so user's main() is found first.

  echo "  ✓ system.config patched"
}
