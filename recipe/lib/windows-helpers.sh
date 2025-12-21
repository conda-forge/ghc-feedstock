#!/usr/bin/env bash
# ==============================================================================
# Windows-Specific Helper Functions
# ==============================================================================
# Shared functions for Windows GHC builds (win-64).
# These handle Windows-specific tasks like settings patching, toolchain setup,
# and workarounds for MinGW-w64 quirks.
#
# Usage: source "${RECIPE_DIR}/lib/windows-helpers.sh"
#
# Required variables (set by platform script before calling):
#   - _PREFIX, _PREFIX_: Unix and Windows format PREFIX paths
#   - _BUILD_PREFIX, _BUILD_PREFIX_: Unix and Windows format BUILD_PREFIX paths
#   - _SRC_DIR: Unix format SRC_DIR path
#   - CC, CXX, LD, AR, NM, RANLIB, etc.: Toolchain paths
#   - CFLAGS, CXXFLAGS, LDFLAGS: Compiler/linker flags
# ==============================================================================

# ==============================================================================
# Environment Setup Helpers
# ==============================================================================

# Expand conda placeholder variables in flags
# Replaces %VAR% and $ENV{VAR} patterns with actual paths
windows_expand_conda_variables() {
  # Replace conda variables with Unix paths (backslash escape prevention)
  # Use :- default to handle unset variables (set -eu safe)
  CFLAGS=$(echo "${CFLAGS:-}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")
  CXXFLAGS=$(echo "${CXXFLAGS:-}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")
  LDFLAGS=$(echo "${LDFLAGS:-}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")

  CFLAGS=$(echo "${CFLAGS:-}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
  CXXFLAGS=$(echo "${CXXFLAGS:-}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
  LDFLAGS=$(echo "${LDFLAGS:-}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
}

# Remove flags that are incompatible with MinGW-w64 GCC toolchain
windows_remove_problematic_flags() {
  # Initialize if unset (set -eu safe)
  CFLAGS="${CFLAGS:-}"
  CXXFLAGS="${CXXFLAGS:-}"
  LDFLAGS="${LDFLAGS:-}"

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

# Set up Windows SDK paths (if available)
setup_windows_sdk() {
  local SDK_PATH=$(ls -1d /c/Program*Files*x86*/Windows*/10 2>/dev/null | head -1)

  if [[ -n "${SDK_PATH}" ]]; then
    SDK_PATH=$(cygpath -u "$(cygpath -d "${SDK_PATH}")")
    local SDK_VER=$(ls -1 "${SDK_PATH}"/Include/ 2>/dev/null | grep "^10\." | sort -V | tail -1)

    export UCRT_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/ucrt"
    export UM_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/um"

    echo "  Windows SDK configured: ${SDK_VER}"
  fi
}

# ==============================================================================
# Build Helpers
# ==============================================================================

# Create ___chkstk_ms stub library
# This is needed because MinGW's stack check symbol may not be available
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

# Rebuild touchy.exe with correct linker flags
# touchy.exe is built during stage1:exe:ghc-bin with Stage0 settings (no --enable-auto-import)
# but Stage1 ghc.exe needs it to work correctly when compiling Stage2 libraries.
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

# Create fake mingw directory for binary distribution
# Hadrian expects a mingw directory structure even when using system toolchain
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

# ==============================================================================
# Settings Patching
# ==============================================================================

# Unified GHC settings patching for Windows
#
# Usage:
#   patch_windows_settings <settings_file> [options...]
#
# Options:
#   --include-paths    Add include paths for ffi.h, gmp.h, etc.
#   --link-flags       Add Windows-specific linker flags (for final binary)
#   --bootstrap        Apply bootstrap-specific patches (dllwrap=false, CFLAGS, etc.)
#   --debug            Show settings file after patching
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

# Patch Hadrian's system.config for Windows
patch_windows_system_config() {
  echo "  Patching Hadrian system.config..."

  local config_file="${_SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${config_file}" ]]; then
    echo "WARNING: system.config not found at ${config_file}"
    return 1
  fi

  # Fix Python path - use PYTHON from environment (Windows format C:/...)
  # CONDA_PYTHON_EXE may contain backslashes that get interpreted as escapes
  perl -pi -e "s#(^python\\s*=).*#\$1 ${PYTHON}#" "${config_file}"

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

  # Set windres - default is 'false' which causes Stage0 build to fail
  perl -pi -e "s#^settings-windres-command\\s*=.*#settings-windres-command = ${_BUILD_PREFIX_}/Library/bin/windres.bat#" "${config_file}"

  # NOTE: Do NOT add --allow-multiple-definition here!
  # The proper solution is library ordering in Stage1 settings where -lmingw32
  # comes AFTER user objects so user's main() is found first.

  echo "  ✓ system.config patched"
}

# ==============================================================================
# Stage Build Helpers
# ==============================================================================

# Build stage executables (ghc-bin, ghc-pkg, hsc2hs) for Windows
# This is a helper - the caller controls patching order between calls.
#
# Parameters:
#   $1 - stage: Stage number (1 or 2)
#   $@ - extra_opts: Additional Hadrian options (e.g., --freeze1)
#
# Usage:
#   windows_build_stage_executables 1                # Stage 1
#   windows_build_stage_executables 2 --freeze1      # Stage 2 with freeze
#
windows_build_stage_executables() {
  local stage="$1"
  shift
  local extra_opts="$*"

  echo "  Building Stage ${stage} executables (Windows)..."

  run_and_log "stage${stage}-ghc" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" "stage${stage}:exe:ghc-bin" ${extra_opts}
  run_and_log "stage${stage}-pkg" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" "stage${stage}:exe:ghc-pkg" ${extra_opts}
  run_and_log "stage${stage}-hsc2hs" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" "stage${stage}:exe:hsc2hs" ${extra_opts}

  echo "  ✓ Stage ${stage} executables built"
}

# Build stage libraries for Windows
#
# Parameters:
#   $1 - stage: Stage number (1 or 2)
#   $@ - extra_opts: Additional Hadrian options (e.g., --freeze1)
#
windows_build_stage_libraries() {
  local stage="$1"
  shift
  local extra_opts="$*"

  echo "  Building Stage ${stage} libraries (Windows)..."

  run_and_log "stage${stage}-lib" "${HADRIAN_CMD[@]}" --flavour="${FLAVOUR}" "stage${stage}:lib:ghc" ${extra_opts} || {
    local exit_code=$?
    echo "ERROR: stage${stage}:lib:ghc failed with exit code ${exit_code}"
    exit ${exit_code}
  }

  echo "  ✓ Stage ${stage} libraries built"
}

# Install GHC from binary distribution (Windows copy method)
# Creates binary-dist-dir and copies to PREFIX.
#
# Returns:
#   0 on success, exits on failure
#
windows_bindist_install() {
  echo "  Installing GHC from binary distribution (Windows)..."

  # Create binary distribution directory
  run_and_log "bindist" "${HADRIAN_CMD[@]}" binary-dist-dir \
    --prefix="${_PREFIX}" --flavour="${FLAVOUR}" --freeze1 --freeze2 ${HADRIAN_STAGE_OPTS}

  # Find and copy bindist
  local ghc_target="x86_64-unknown-mingw32"
  local bindist_dir
  bindist_dir=$(find "${_SRC_DIR}/_build/bindist" -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)

  if [[ -z "${bindist_dir}" ]]; then
    echo "ERROR: Could not find binary distribution directory"
    echo "Looking for: ghc-${PKG_VERSION}-${ghc_target}"
    ls -la "${_SRC_DIR}/_build/bindist/" || true
    exit 1
  fi

  echo "  Copying from: ${bindist_dir}"
  cp -r "${bindist_dir}"/* "${_PREFIX}"/

  # Install windres wrapper
  cp "${_BUILD_PREFIX}/Library/bin/windres.bat" "${_PREFIX}/bin/ghc_windres.bat"

  echo "  ✓ Binary distribution installed"
}

# ==============================================================================
# Post-Install Helpers
# ==============================================================================

# Post-install cleanup: remove bundled mingw and update settings
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
  local settings_file=$(get_installed_settings_file "${_PREFIX}")
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
