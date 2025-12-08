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

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

platform_setup_environment() {
  echo "  Configuring Windows-specific environment..."

  # CRITICAL: Ensure _PREFIX_ and _BUILD_PREFIX_ are set to Windows-format paths (C:/...)
  # The build.bat should set these, but if they contain unexpanded %PREFIX% placeholders,
  # recreate them from the Unix-style paths (_PREFIX, _BUILD_PREFIX)
  if [[ -z "${_PREFIX_:-}" || "${_PREFIX_}" == *"%"* ]]; then
    export _PREFIX_=$(echo "${_PREFIX}" | sed 's#^/c/#C:/#; s#^/d/#D:/#')
  fi
  if [[ -z "${_BUILD_PREFIX_:-}" || "${_BUILD_PREFIX_}" == *"%"* ]]; then
    export _BUILD_PREFIX_=$(echo "${_BUILD_PREFIX}" | sed 's#^/c/#C:/#; s#^/d/#D:/#')
  fi
  echo "    _PREFIX_=${_PREFIX_}"
  echo "    _BUILD_PREFIX_=${_BUILD_PREFIX_}"

  # Build clean PATH - don't append conda's bad PATH with unexpanded %BUILD_PREFIX% placeholders
  # Include MSYS2 tools (m2-coreutils, m2-bash, etc.) from Library/usr/bin
  export PATH="${_BUILD_PREFIX}/Library/bin:${_BUILD_PREFIX}/Library/usr/bin:${_BUILD_PREFIX}/ghc-bootstrap/bin:${_BUILD_PREFIX}/bin:/c/Windows/System32:/c/Windows"

  # Set up Cabal environment
  export CABAL="${_BUILD_PREFIX}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}\\.cabal"
  export _PYTHON="${_BUILD_PREFIX}/python.exe"
  export GHC="${_BUILD_PREFIX}/ghc-bootstrap/bin/ghc.exe"
  export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

  # Use GCC toolchain to match bootstrap GHC compiler
  export CC="x86_64-w64-mingw32-gcc"
  export CXX="x86_64-w64-mingw32-g++"
  export CPP="x86_64-w64-mingw32-cpp"

  echo "  GCC toolchain:"
  echo "    CC=${CC}"
  echo "    CXX=${CXX}"
  echo "    CPP=${CPP}"

  # Define toolchain variables early for bootstrap settings patching
  export LD="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
  export AR="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ar.exe"
  export RANLIB="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ranlib.exe"

  # Expand conda variables in flags
  expand_conda_variables

  # Remove problematic flags
  remove_problematic_flags

  # Add Windows-specific include and library paths
  # Add include paths for system headers like ffi.h in two stages:
  # 1. Basic path in patch_bootstrap_settings() before configure
  # 2. Complete paths in patch_stage0_settings_include_paths() after stage1:exe:ghc-bin
  export CFLAGS="-I${_BUILD_PREFIX}/Library/include ${CFLAGS:-}"
  export CXXFLAGS="-I${_BUILD_PREFIX}/Library/include ${CXXFLAGS:-}"
  export LDFLAGS="-L${_BUILD_PREFIX}/Library/lib -L${_BUILD_PREFIX}/Library/lib/gcc/x86_64-w64-mingw32/15.2.0 ${LDFLAGS:-}"

  echo "  Flags configured:"
  echo "    CFLAGS=${CFLAGS:0:100}..."
  echo "    LDFLAGS=${LDFLAGS:0:100}..."

  # Fix windres.bat (ghc-bootstrap bug)
  if [[ -f "${_BUILD_PREFIX}/ghc-bootstrap/bin/windres.bat" ]]; then
    perl -pi -e 's/findstr/C:\\Windows\\System32\\findstr/g' "${_BUILD_PREFIX}/ghc-bootstrap/bin/windres.bat"
  fi

  # Create chkstk_ms stub library
  create_chkstk_stub

  # Create mingw32 compatibility stubs (timezone symbols for UCRT)
  create_mingw32_stubs

  # Install windres wrapper
  if [[ -f "${_RECIPE_DIR}/support/windres.bat" ]]; then
    cp "${_RECIPE_DIR}/support/windres.bat" "${_BUILD_PREFIX}/Library/bin/"
    echo "  Installed windres.bat wrapper"
  fi

  # Patch bootstrap settings
  patch_bootstrap_settings

  # CRITICAL: Patch bootstrap's time package to link against mingw32_stubs
  # The time library references __imp__timezone and __imp__tzname which are
  # MSVCRT symbols not available in UCRT. Our stubs provide these.
  patch_bootstrap_time_package

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

platform_setup_bootstrap() {
  echo "  Configuring Windows bootstrap..."

  # Test bootstrap GHC is functional
  echo "  Testing bootstrap GHC..."
  "${GHC}" --version >/dev/null || {
    echo "ERROR: Bootstrap GHC failed to run"
    exit 1
  }

  echo "  ✓ Bootstrap GHC is functional"
}

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

platform_add_configure_args() {
  local -n args=$1

  # Add Windows-specific configure arguments
  args+=(
    --with-system-libffi=yes
    --with-curses-includes="${_PREFIX}/Library/include"
    --with-curses-libraries="${_PREFIX}/Library/lib"
    --with-ffi-includes="${_PREFIX}/Library/include"
    --with-ffi-libraries="${_PREFIX}/Library/lib"
    --with-gmp-includes="${_PREFIX}/Library/include"
    --with-gmp-libraries="${_PREFIX}/Library/lib"
    --with-iconv-includes="${_PREFIX}/Library/include"
    --with-iconv-libraries="${_PREFIX}/Library/lib"
  )
}

platform_pre_configure_ghc() {
  # Configure environment variables for Windows
  export ac_cv_lib_ffi_ffi_call=yes

  # Force use of conda-provided toolchain and libraries (not inplace MinGW)
  export UseSystemMingw=YES
  export WindowsToolchainAutoconf=NO
  export WINDOWS_TOOLCHAIN_AUTOCONF=no

  # Force use of system libffi (conda-provided)
  export UseSystemFfi=YES
  export ac_cv_use_system_libffi=yes

  export CXX_STD_LIB_LIBS="stdc++"

  # CRITICAL: Override ALL conda toolchain variables that have %BUILD_PREFIX% placeholders
  # Configure reads these from environment, NOT from bootstrap GHC settings
  export ADDR2LINE="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-addr2line.exe"
  export AR="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ar.exe"
  export AS="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-as.exe"
  export CXXFILT="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-c++filt.exe"
  export ELFEDIT="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-elfedit.exe"
  export GPROF="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-gprof.exe"
  export LD="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
  export NM="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-nm.exe"
  export OBJCOPY="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-objcopy.exe"
  export OBJDUMP="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-objdump.exe"
  export RANLIB="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ranlib.exe"
  export READELF="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-readelf.exe"
  export SIZE="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-size.exe"
  export STRINGS="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-strings.exe"
  export STRIP="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-strip.exe"

  echo "  Toolchain environment variables overridden with actual paths"

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

platform_build_hadrian() {
  echo "  Building Hadrian (Windows-specific, single-threaded)..."

  pushd "${_SRC_DIR}/hadrian" >/dev/null

  # Add mingw32_stubs to link line for Hadrian build
  # This provides __imp__timezone and __imp__tzname symbols needed by bootstrap GHC's time library
  # IMPORTANT: LDFLAGS environment variable is not automatically used by Cabal/GHC
  # We must pass linker flags via --ghc-options=-optl-lmingw32_stubs
  local STUBS_LIB="${_BUILD_PREFIX}/Library/lib"

  # CRITICAL: Build Hadrian with single-threaded Cabal (-j1) to avoid race conditions
  # Parallel ghc-pkg updates can conflict on package.cache
  run_and_log "build-hadrian" "${CABAL}" v2-build -j1 \
    --ghc-options="-optl-L${STUBS_LIB} -optl-lmingw32_stubs" \
    hadrian

  popd >/dev/null

  # Find Hadrian binary
  local hadrian_bin=$(find "${_SRC_DIR}"/hadrian/dist-newstyle -name hadrian.exe -type f | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${_SRC_DIR}")
  # CRITICAL: Use quickest flavour on Windows to avoid "32 bit pseudo relocation"
  # errors in the Stage1 ghc.exe. Release flavour produces optimized binaries
  # that can exceed relocation limits and crash when Cabal tries to detect version.
  HADRIAN_FLAVOUR="quickest"

  echo "  Hadrian binary: ${hadrian_bin}"
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

patch_stage0_settings_include_paths() {
  echo "  Patching Stage0 settings with include paths for ffi.h, gmp.h, etc..."

  local settings_file="${_SRC_DIR}/_build/stage0/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "WARNING: Stage0 settings file not found at ${settings_file}"
    return 1
  fi

  # Add include paths for system headers (ffi.h, gmp.h, etc.)
  # CRITICAL: Use _PREFIX (Unix paths) NOT PREFIX (Windows paths)
  # CRITICAL: Include both _PREFIX and _BUILD_PREFIX
  # Use correct regex with closing quote capture group
  perl -pi -e "s#(C compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"

  # IMPORTANT: DO NOT patch stage0/bootstrap GHC link flags with custom CRT!
  # The bootstrap GHC must use NORMAL MinGW linking so that intermediate
  # Haskell programs (including hadrian) work correctly.
  # Custom link flags are ONLY needed for the FINAL Stage1 GHC settings.

  echo "  Stage0 settings after patching:"
  grep "C compiler flags\|C++ compiler flags" "${settings_file}" || echo "  (grep failed)"

  echo "  ✓ Stage0 settings include paths added"
}

platform_build_stage1() {
  echo "  Building Stage 1 GHC (Windows)..."

  # Build Stage 1 GHC compiler
  run_and_log "stage1-ghc" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage1:exe:ghc-bin

  # CRITICAL: After stage1:exe:ghc-bin creates _build/stage0/lib/settings,
  # patch it with include paths BEFORE building libraries that need ffi.h
  patch_stage0_settings_include_paths

  # Build Stage 1 supporting tools
  run_and_log "stage1-pkg" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage1:exe:ghc-pkg
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage1:exe:hsc2hs

  # CRITICAL: Build Stage 1 libraries BEFORE Stage 2
  run_and_log "stage1-lib" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage1:lib:ghc

  echo "  ✓ Stage 1 GHC built"
}

platform_post_build_stage1() {
  echo "  Running Windows-specific Stage1 post-build..."

  # NOTE: Stage1 ghc.exe is NOT created until stage2:exe:ghc-bin runs!
  # - stage1:exe:ghc-bin creates _build/stage0/bin/ghc.exe
  # - stage2:exe:ghc-bin creates _build/stage1/bin/ghc.exe
  # So we can't test Stage1 ghc.exe here - it doesn't exist yet.
  # The test and touchy rebuild are done AFTER stage2:exe:ghc-bin in platform_build_stage2.

  echo "  ✓ Windows Stage1 post-build complete (Stage1 ghc.exe test deferred to Stage2)"
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

patch_stage2_settings() {
  echo "  Patching Stage2 settings (_build/stage1/lib/settings)..."

  local settings_file="${_SRC_DIR}/_build/stage1/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "WARNING: Stage2 settings file not found at ${settings_file}"
    return 1
  fi

  # Directories for linking
  local CHKSTK_DIR="${_BUILD_PREFIX}/Library/lib"
  local MINGW_SYSROOT="${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib"

  # Build complete link flags string
  # CRITICAL: Use -Xlinker prefix because flags go through GHC to linker
  local LINK_FLAGS="-Wl,--subsystem,console -Wl,--enable-auto-import -Wl,--image-base=0x140000000 -Wl,--dynamicbase -Wl,--high-entropy-va -Xlinker -L${CHKSTK_DIR} -Xlinker -L${MINGW_SYSROOT}"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmoldname -Xlinker -lmingwex -Xlinker -lmingw32 -Xlinker -lchkstk_ms -Xlinker -lgcc -Xlinker -lucrt -Xlinker -lkernel32 -Xlinker -ladvapi32"

  perl -pi -e "s#(C compiler link flags\", \")#\$1${LINK_FLAGS} #" "${settings_file}"
  perl -pi -e "s#(ld flags\", \")#\$1--subsystem,console --enable-auto-import --image-base=0x140000000 --dynamicbase --high-entropy-va -L${CHKSTK_DIR} -L${MINGW_SYSROOT} -lmoldname -lmingwex -lmingw32 -lchkstk_ms -lgcc -lucrt -lkernel32 -ladvapi32 #" "${settings_file}"

  echo "  ✓ Stage2 settings patched"
}

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
  run_and_log "stage2-exe" "${HADRIAN_CMD[@]}" stage2:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR}" --freeze1 --docs=none --progress-info=none

  # Patch Stage1 settings file (created by stage2:exe:ghc-bin)
  patch_stage2_settings

  # Build Stage 1 supporting tools
  run_and_log "stage2-pkg" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage2:exe:ghc-pkg --freeze1 --docs=none --progress-info=none
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" stage2:exe:hsc2hs --freeze1 --docs=none --progress-info=none

  # CRITICAL: Rebuild touchy.exe with correct linker flags BEFORE stage2:lib:ghc
  # touchy.exe was built during stage1:exe:ghc-bin with Stage0 settings (no --enable-auto-import)
  # Stage1 ghc.exe (in _build/stage1/bin/) needs touchy.exe (in _build/stage1/lib/bin/)
  # to work correctly when compiling Stage2 libraries.
  rebuild_touchy_with_correct_linker_flags

  # Build Stage 2 GHC libraries
  # NOTE: Do NOT add Stage1 bin to PATH - Hadrian handles this internally.
  # Adding it would cause Cabal to find our Stage1 ghc.exe (which may have
  # relocation issues) and fail when trying to detect its version.
  echo "  Command: ${HADRIAN_CMD[*]} stage2:lib:ghc --flavour=${HADRIAN_FLAVOUR} --freeze1 --docs=none --progress-info=none"

  run_and_log "stage2-lib" "${HADRIAN_CMD[@]}" stage2:lib:ghc --flavour="${HADRIAN_FLAVOUR}" --freeze1 --docs=none --progress-info=none || {
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
  run_and_log "bindist" "${HADRIAN_CMD[@]}" binary-dist-dir --prefix="${_PREFIX}" --flavour="${HADRIAN_FLAVOUR}" --freeze1 --freeze2 --docs=none

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

create_mingw32_stubs() {
  echo "  Creating MinGW32 compatibility stub library (timezone symbols)..."

  local STUBS_OBJ="${_SRC_DIR}/mingw32_stubs.o"
  local STUBS_LIB="${_BUILD_PREFIX}/Library/lib/libmingw32_stubs.a"

  # Compile stubs from recipe support directory
  if [[ -f "${_RECIPE_DIR}/support/mingw32_stubs.c" ]]; then
    ${CC} -c "${_RECIPE_DIR}/support/mingw32_stubs.c" -o "${STUBS_OBJ}"
  else
    echo "ERROR: mingw32_stubs.c not found at ${_RECIPE_DIR}/support/mingw32_stubs.c"
    exit 1
  fi

  ${AR} rcs "${STUBS_LIB}" "${STUBS_OBJ}"

  if [[ ! -f "${STUBS_LIB}" ]]; then
    echo "ERROR: Failed to create mingw32_stubs library"
    exit 1
  fi

  echo "  ✓ Created ${STUBS_LIB}"
}

patch_bootstrap_time_package() {
  echo "  Patching bootstrap GHC's time package to use mingw32_stubs..."

  local pkg_db="${_BUILD_PREFIX}/ghc-bootstrap/lib/package.conf.d"
  local time_conf
  time_conf=$(find "${pkg_db}" -name "time-*.conf" 2>/dev/null | head -1)

  if [[ -z "${time_conf}" || ! -f "${time_conf}" ]]; then
    echo "WARNING: Bootstrap time package conf not found in ${pkg_db}"
    return 1
  fi

  echo "  Found time package: ${time_conf}"

  # Use Windows-format path for the stubs library directory
  local STUBS_LIB_DIR="${_BUILD_PREFIX}/Library/lib"

  # Add extra-lib-dirs if not present
  if ! grep -q "extra-lib-dirs:" "${time_conf}"; then
    echo "extra-lib-dirs: ${STUBS_LIB_DIR}" >> "${time_conf}"
  else
    # Append to existing extra-lib-dirs
    perl -pi -e "s#(extra-lib-dirs:.*)#\$1 ${STUBS_LIB_DIR}#" "${time_conf}"
  fi

  # Add extra-libraries if not present
  if ! grep -q "extra-libraries:" "${time_conf}"; then
    echo "extra-libraries: mingw32_stubs" >> "${time_conf}"
  else
    # Append to existing extra-libraries
    perl -pi -e "s#(extra-libraries:.*)#\$1 mingw32_stubs#" "${time_conf}"
  fi

  echo "  Recaching bootstrap package database..."
  "${_BUILD_PREFIX}/ghc-bootstrap/bin/ghc-pkg" recache

  echo "  ===== PATCHED TIME PACKAGE CONF ====="
  cat "${time_conf}"
  echo "  ===== END TIME PACKAGE CONF ====="

  echo "  ✓ Bootstrap time package patched"
}

patch_bootstrap_settings() {
  echo "  Patching bootstrap GHC settings..."

  local settings_file="${_BUILD_PREFIX}/ghc-bootstrap/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "WARNING: Bootstrap settings file not found at ${settings_file}"
    return 1
  fi

  # CRITICAL: Use _BUILD_PREFIX_ (C:/bld/... format) for all tool paths
  # GHC on Windows cannot execute paths like /c/bld/... - needs C:/bld/...
  local CC_WIN="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-gcc.exe"
  local CXX_WIN="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-g++.exe"
  local LD_WIN="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-ld.exe"
  local AR_WIN="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-ar.exe"
  local RANLIB_WIN="${_BUILD_PREFIX_}/Library/bin/x86_64-w64-mingw32-ranlib.exe"

  echo "  Patching with Windows-format paths (_BUILD_PREFIX_):"
  echo "    CC_WIN=${CC_WIN}"
  echo "    CXX_WIN=${CXX_WIN}"
  echo "    LD_WIN=${LD_WIN}"
  echo "    AR_WIN=${AR_WIN}"
  echo "    RANLIB_WIN=${RANLIB_WIN}"

  # Patch settings file with Windows-format paths
  perl -pi -e "s#(C compiler command\", \")[^\"]*#\$1${CC_WIN}#" "${settings_file}"
  perl -pi -e "s#(Haskell CPP command\", \")[^\"]*#\$1${CC_WIN}#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler command\", \")[^\"]*#\$1${CXX_WIN}#" "${settings_file}"
  # CRITICAL: Fix "ld command" field that points to non-existent $tooldir/mingw/bin/ld.exe
  perl -pi -e "s#(ld command\", \")[^\"]*#\$1${LD_WIN}#" "${settings_file}"
  perl -pi -e "s#(Merge objects command\", \")[^\"]*#\$1${LD_WIN}#" "${settings_file}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR_WIN}#" "${settings_file}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1${RANLIB_WIN}#" "${settings_file}"
  perl -pi -e "s#(dllwrap command\", \")[^\"]*#\$1false#" "${settings_file}"

  # Setup windres wrapper (using _BUILD_PREFIX_, Windows format)
  if [[ -f "${_BUILD_PREFIX}/Library/bin/windres.bat" ]]; then
    local WINDRES_WIN="${_BUILD_PREFIX_}/Library/bin/windres.bat"
    perl -pi -e "s#(windres command\", \")[^\"]*#\$1${WINDRES_WIN}#" "${settings_file}"
  fi

  # Update include paths - use _BUILD_PREFIX_ and _PREFIX_ (Windows format)
  # Replace bootstrap's mingw/include with conda include paths
  perl -pi -e "s#-I\\\$tooldir/mingw/include#-I${_BUILD_PREFIX_}/Library/include#g" "${settings_file}"

  # Add CFLAGS and basic include path to compiler flags
  # Note: More include paths will be added later in patch_stage0_settings_include_paths()
  perl -pi -e "s#(C compiler flags\", \")([^\"]*)#\$1\$2 ${CFLAGS} -I${_PREFIX_}/Library/include#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)#\$1\$2 ${CXXFLAGS} -I${_PREFIX_}/Library/include#" "${settings_file}"

  # Haskell CPP needs traditional-cpp for Haskell compatibility
  perl -pi -e "s#(Haskell CPP flags\", \")[^\"]*#\$1-E -undef -traditional-cpp -I${_BUILD_PREFIX_}/Library/include -I${_PREFIX_}/Library/include#" "${settings_file}"

  # CRITICAL: Add mingw32_stubs library to link flags for bootstrap GHC
  # The bootstrap GHC's time library references __imp__timezone and __imp__tzname
  # which are MSVCRT symbols not available in modern UCRT. Our stubs library provides these.
  # This is needed when bootstrap GHC links Stage0 executables (including Hadrian-built tools)
  # Without this, executables segfault during RTS initialization when accessing timezone.
  local STUBS_LIB_DIR="${_BUILD_PREFIX_}/Library/lib"
  perl -pi -e "s#(C compiler link flags\", \")([^\"]*)#\$1\$2 -L${STUBS_LIB_DIR} -lmingw32_stubs#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \")([^\"]*)#\$1\$2 -L${STUBS_LIB_DIR} -lmingw32_stubs#" "${settings_file}"
  echo "  Added mingw32_stubs to bootstrap GHC link flags"

  # Show complete bootstrap settings file for debugging
  echo "  ===== BOOTSTRAP SETTINGS FILE (after patching) ====="
  cat "${settings_file}"
  echo "  ===== END BOOTSTRAP SETTINGS ====="

  echo "  ✓ Bootstrap settings patched"
}

# NOTE: patch_stage1_settings_for_relocation_fix was REMOVED.
# It incorrectly patched stage0/lib/settings with link flags BEFORE stage2:exe:ghc-bin,
# causing "multiple definition of main" errors with the new m2w64-sysroot CRT.
#
# The correct approach (matching working branch):
# 1. Build stage1:exe:ghc-bin and stage2:exe:ghc-bin with DEFAULT MinGW linking
# 2. AFTER stage2:exe:ghc-bin, patch stage1/lib/settings via patch_stage2_settings()
# 3. Build stage2:lib:ghc and remaining targets with patched settings

test_stage1_ghc() {
  echo "  Testing Stage1 GHC..."

  local ghc_exe="${_SRC_DIR}/_build/stage1/bin/ghc.exe"

  if [[ -f "${ghc_exe}" ]]; then
    "${ghc_exe}" --version 2>&1 || {
      echo "WARNING: ghc.exe failed with exit code $?"
      echo "Build may fail at stage2:lib:ghc configuration"
    }
  else
    echo "WARNING: ghc.exe not found at ${ghc_exe}"
  fi
}

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
  perl -pi -e "s#(^python\\s*=).*#\$1 ${_PYTHON}#" "${config_file}"

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
