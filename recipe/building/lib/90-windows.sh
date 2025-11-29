#!/usr/bin/env bash
# Windows-specific helper functions for GHC build
#
# This module provides Windows/MinGW-specific build support including:
# - Path conversion (Unix ↔ Windows format)
# - GCC toolchain setup for MinGW-w64 UCRT
# - chkstk_ms stub library creation
# - Bootstrap settings patching
# - system.config Windows-specific modifications

# ============================================================================
# Path Conversion Utilities
# ============================================================================

setup_windows_paths() {
  # Configure Windows-specific path handling
  # Critical: Replace %VARS% with Unix paths to prevent backslash escape issues
  # When %PREFIX% expands to C:\bld\..., the \b becomes backspace character!

  # Expand conda variables in CFLAGS/CXXFLAGS/LDFLAGS
  # Replace %PREFIX%, %BUILD_PREFIX%, %SRC_DIR% with Unix path equivalents
  CFLAGS=$(echo "${CFLAGS}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g; s|%PREFIX%|${_PREFIX}|g; s|%SRC_DIR%|${_SRC_DIR}|g")

  # Also handle $ENV{VAR} style references
  CFLAGS=$(echo "${CFLAGS}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe "s|\$ENV{BUILD_PREFIX}|${_BUILD_PREFIX}|g; s|\$ENV{PREFIX}|${_PREFIX}|g; s|\$ENV{SRC_DIR}|${_SRC_DIR}|g")

  # Remove problematic flags from conda environment
  CFLAGS="${CFLAGS//-nostdlib/}"
  CXXFLAGS="${CXXFLAGS//-nostdlib/}"
  LDFLAGS="${LDFLAGS//-nostdlib/}"

  # Remove problematic -Wl,-defaultlib: flags (MSVC-specific)
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe 's/-Wl,-defaultlib:[^ ]*//g')

  # Remove -fstack-protector-strong (generates __security_cookie calls incompatible with MinGW)
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fstack-protector-strong//g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fstack-protector-strong//g')

  # Remove -fms-runtime-lib=dll (forces Microsoft MSVCRT, we want MinGW's msvcrt)
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fms-runtime-lib=dll//g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fms-runtime-lib=dll//g')

  # Remove flags with Windows paths containing backslashes
  # -fdebug-prefix-map and -isystem can have corrupted paths (C:\bld → C:␈ld)
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fdebug-prefix-map=[^ ]*//g; s/-isystem [^ ]*//g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fdebug-prefix-map=[^ ]*//g; s/-isystem [^ ]*//g')

  # Export cleaned flags
  export CFLAGS
  export CXXFLAGS
  export LDFLAGS

  # Set up temp variables with Windows paths
  export TMP="$(cygpath -w "${TEMP}")"
  export TMPDIR="$(cygpath -w "${TEMP}")"

  # Override conda's PYTHON (has Windows backslashes) with Unix-format path
  export PYTHON="${_BUILD_PREFIX}/python.exe"
}

# ============================================================================
# GCC Toolchain Setup
# ============================================================================

setup_windows_gcc_toolchain() {
  # Configure GCC toolchain for MinGW-w64 UCRT
  # Uses GCC instead of Clang to match bootstrap GHC's compiler
  # Bootstrap GHC was built with GCC 15.2.0, not Clang

  local conda_target=x86_64-w64-mingw32

  # Override conda's CC/CXX to use GCC instead of Clang
  export CC="x86_64-w64-mingw32-gcc.exe"
  export CXX="x86_64-w64-mingw32-g++.exe"
  # NOTE: CPP is set by platform config (win-64.sh) to "gcc -E"
  # Do NOT override here - standalone cpp doesn't handle GHC's configure flags

  # Override conda's toolchain vars with UNIX-style paths
  # Conda sets these with %BUILD_PREFIX% which may expand to Windows paths with backslashes
  # BASH/MSYS2 handles UNIX-style paths fine, only specific tools need Windows format
  export AR="x86_64-w64-mingw32-ar.exe"
  export AS="x86_64-w64-mingw32-as.exe"
  export LD="x86_64-w64-mingw32-ld.exe"
  export NM="x86_64-w64-mingw32-nm.exe"
  export OBJCOPY="x86_64-w64-mingw32-objcopy.exe"
  export OBJDUMP="x86_64-w64-mingw32-objdump.exe"
  export RANLIB="x86_64-w64-mingw32-ranlib.exe"
  export READELF="x86_64-w64-mingw32-readelf.exe"
  export STRIP="x86_64-w64-mingw32-strip.exe"

  # Use GNU ld (bfd) for MinGW compatibility (lld defaults to MSVC mode on Windows)
  CFLAGS=$(echo "${CFLAGS}" | perl -pe 's/-fuse-ld=lld/-fuse-ld=bfd/g')
  CXXFLAGS=$(echo "${CXXFLAGS}" | perl -pe 's/-fuse-ld=lld/-fuse-ld=bfd/g')
  LDFLAGS=$(echo "${LDFLAGS}" | perl -pe 's/-fuse-ld=lld/-fuse-ld=bfd/g')

  # Add include and library paths
  export CFLAGS="-I${_BUILD_PREFIX}/Library/include ${CFLAGS:-}"
  export CXXFLAGS="-I${_BUILD_PREFIX}/Library/include ${CXXFLAGS:-}"
  export LDFLAGS="-L${_BUILD_PREFIX}/Library/lib -L${_BUILD_PREFIX}/Library/lib/gcc/x86_64-w64-mingw32/15.2.0 ${LDFLAGS:-}"

  # GCC uses libgcc, not compiler-rt
  export COMPILER_RT_LIB=""

  # Set library path for runtime linking
  export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

  if [[ -f "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat ]]; then
    # Specific to ghc-bootstrap 9.6.7
    perl -pi -e 's/findstr/C:\\Windows\\System32\\findstr/g' "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat
    perl -pi -e 's/Library\\x86_64-w64-mingw32\\bin\\windres.exe/Library\\bin\\x86_64-w64-mingw32-windres/' "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat
    perl -pi -e 's/REM Set environment variables for windres/set PATH=%BUILD_PREFIX%\\Library\\bin;%PATH%/' "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat
  fi
  cat "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat
}

# ============================================================================
# chkstk_ms Stub Library
# ============================================================================

create_chkstk_stub() {
  # Create ___chkstk_ms stub library
  # MinGW libraries reference this symbol but don't provide it
  # GCC generates calls to this symbol for stack checking
  #
  # CRITICAL: Must be created BEFORE updating bootstrap settings file

  pushd "${_SRC_DIR}" >/dev/null

  # Create assembly stub
  cat > chkstk_ms.s <<'EOF'
  .text
  .globl ___chkstk_ms
  .def ___chkstk_ms; .scl 2; .type 32; .endef
___chkstk_ms:
  ret
EOF

  # Compile the stub
  x86_64-w64-mingw32-gcc -c chkstk_ms.s -o chkstk_ms.o

  # Create static library
  x86_64-w64-mingw32-ar rcs libchkstk_ms.a chkstk_ms.o

  # Install to library directory
  cp libchkstk_ms.a "${_BUILD_PREFIX}/Library/lib/"

  # Verify library was created
  if [[ ! -f "${_BUILD_PREFIX}/Library/lib/libchkstk_ms.a" ]]; then
    echo "ERROR: Failed to create chkstk_ms library"
    exit 1
  fi

  # Add to LDFLAGS so all packages link against it
  export LDFLAGS="${LDFLAGS} -lchkstk_ms"

  popd >/dev/null
}

# ============================================================================
# MinGW/UCRT Setup
# ============================================================================

setup_windows_mingw() {
  # Configure MinGW and UCRT (Universal C Runtime) integration
  # Detects Windows SDK paths and sets up include/library paths

  # Detect Windows SDK paths
  local SDK_PATH=$(ls -1d /c/Program*Files*x86*/Windows*/10 2>/dev/null | head -1)
  SDK_PATH=$(cygpath -u "$(cygpath -d "${SDK_PATH}")")
  local SDK_VER=$(ls -1 "${SDK_PATH}"/Include/ 2>/dev/null | grep "^10\." | sort -V | tail -1)

  # UCRT and Windows SDK include paths
  export UCRT_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/ucrt"
  export UM_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/um"
  export SHARED_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/shared"
  export CPPWINRT_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/cppwinrt"
  export WINRT_INCLUDE="${SDK_PATH}/Include/${SDK_VER}/winrt"

  # UCRT and Windows SDK library paths
  export UCRT_LIB="${SDK_PATH}/Lib/${SDK_VER}/ucrt/x64"
  export UM_LIB="${SDK_PATH}/Lib/${SDK_VER}/um/x64"

  # Detect MSVC paths (for compatibility, though we use GCC)
  local MSVC_BASE=$(ls -1d /c/Program*/Microsoft*/*/*/VC/Tools/MSVC 2>/dev/null | sort -V | tail -1)
  if [[ -n "${MSVC_BASE}" ]]; then
    MSVC_BASE=$(cygpath -u "$(cygpath -d "${MSVC_BASE}")")
    local MSVC_VER=$(ls -1 "${MSVC_BASE}" 2>/dev/null | sort -V | tail -1)
    export MSVC_INCLUDE="${MSVC_BASE}/${MSVC_VER}/include"
  fi

  # Force use of conda-provided toolchain and libraries
  export UseSystemMingw=YES
  export WindowsToolchainAutoconf=NO
  export WINDOWS_TOOLCHAIN_AUTOCONF=no
  export UseSystemFfi=YES
  export ac_cv_use_system_libffi=yes
  export ac_cv_lib_ffi_ffi_call=yes

  export CXX_STD_LIB_LIBS="stdc++"
}

# ============================================================================
# Bootstrap Settings Patching
# ============================================================================

patch_bootstrap_settings_windows() {
  # Patch Stage0 (bootstrap) GHC settings file
  # Critical: Fix merge-objects to use GNU ld instead of lld
  #
  # TIMING: Must run AFTER create_chkstk_stub() and BEFORE configure

  # Windows ghc-bootstrap package installs to lib/settings (no version subdir)
  # Unlike Linux/macOS which use lib/ghc-VERSION/lib/settings
  local settings_file="${_BUILD_PREFIX}/ghc-bootstrap/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "WARNING: Bootstrap settings file not found at ${settings_file}"
    return 1
  fi

  perl -pi -e "s#(Merge objects command\", \")[^\"]*#\$1${LD}#" "${settings_file}"
}

# ============================================================================
# system.config Patching
# ============================================================================

patch_system_config_windows() {
  # Patch Hadrian's system.config file for Windows build
  # Critical: Force use of system toolchain and libraries
  #
  # TIMING: Must run AFTER configure

  local config_file="${_SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${config_file}" ]]; then
    echo "ERROR: system.config not found at ${config_file}"
    return 1
  fi

  # Fix Python path (configure sets Linux path, we need Windows)
  # Use forward slashes to avoid escape sequence issues (\n, \t, \b, etc.)
  perl -pi -e "s#(^python\\s*=).*#\$1 ${_PYTHON}#" "${config_file}"

  echo "=== Expanding conda variables in system.config ==="
  # Replace %PREFIX%, %BUILD_PREFIX%, %SRC_DIR% with their Unix path equivalents
  # This prevents backslash escape sequences when Windows expands these variables
  perl -pi -e "s#%PREFIX%#${_PREFIX}#g" "${config_file}"
  perl -pi -e "s#%BUILD_PREFIX%#${_BUILD_PREFIX}#g" "${config_file}"
  perl -pi -e "s#%SRC_DIR%#${_SRC_DIR}#g" "${config_file}"

  perl -pi -e "s#\$ENV{PREFIX}#${_PREFIX}#g" "${config_file}"
  perl -pi -e "s#\$ENV{BUILD_PREFIX}#${_BUILD_PREFIX}#g" "${config_file}"
  perl -pi -e "s#\$ENV{SRC_DIR}#${_SRC_DIR}#g" "${config_file}"

  echo "=== Converting FFI paths to Windows format in system.config ==="
  perl -pi -e 's#^ffi-include-dir\s*=\s*/c/#ffi-include-dir   = C:/#' "${config_file}"
  perl -pi -e 's#^ffi-lib-dir\s*=\s*/c/#ffi-lib-dir       = C:/#' "${config_file}"
  perl -pi -e 's#^([a-z-]+dir)\s*=\s*/c/#$1 = C:/#g' "${config_file}"
  perl -pi -e "s#^(intree-gmp\s*=\s*).*#\$1NO#" "${config_file}"

  echo "=== Forcing system toolchain and libffi settings ==="
  # Force use of conda toolchain (not inplace MinGW)
  perl -pi -e 's#^use-system-mingw\s*=\s*.*$#use-system-mingw = YES#' "${config_file}"
  perl -pi -e 's#^windows-toolchain-autoconf\s*=\s*.*$#windows-toolchain-autoconf = NO#' "${config_file}"

  # Force use of conda libffi
  perl -pi -e 's#^use-system-ffi\s*=\s*.*$#use-system-ffi = YES#' "${config_file}"

  # CRITICAL: Fix system-merge-objects to use GNU ld
  # The bootstrap's system-merge-objects may point to wrong ld (ld.lld, or nonexistent mingw/bin/ld.exe)
  # We need GNU ld which works with MinGW .a files
  # Match ANY line with system-merge-objects, not just those containing ld.lld
  perl -pi -e 's#^system-merge-objects\s*=\s*.*$#system-merge-objects = '"${LD}"'#' "${config_file}"

  cat "${config_file}" | grep "include-dir\|lib-dir\|windres\|dllwrap\|system-mingw\|system-ffi\|merge-objects"

  # GHC 9.10+ uses ghc-toolchain which creates its own config files
  # These must also be patched to fix invalid Windows paths
  echo "=== Patching ghc-toolchain output files (GHC 9.10+) ==="
  patch_ghc_toolchain_output
}

patch_ghc_toolchain_output() {
  # GHC 9.10+ introduces ghc-toolchain which runs during configure
  # It creates hadrian/cfg/default.target.ghc-toolchain with toolchain paths
  # Problem: It converts UNIX paths like /c/bld/... to invalid \c\bld\...
  # Solution: Convert these to Windows format C:/bld/...

  local toolchain_file="${_SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"

  if [[ ! -f "${toolchain_file}" ]]; then
    echo "  ghc-toolchain output not found (expected for GHC <9.10)"
    return 0
  fi

  echo "  Found ghc-toolchain output, patching paths..."

  # Convert invalid \c\bld\... paths to valid C:/bld/... paths
  # Pattern: "\\c\\ -> "C:/
  # Must escape backslashes in both pattern and replacement
  perl -pi -e 's#"\\\\([a-z])\\\\#"\U$1:/#g' "${toolchain_file}"

  echo "  ghc-toolchain paths patched"
}

# ============================================================================
# Exported Functions
# ============================================================================

# Make functions available to build scripts
export -f setup_windows_paths
export -f setup_windows_gcc_toolchain
export -f create_chkstk_stub
export -f setup_windows_mingw
export -f patch_bootstrap_settings_windows
export -f patch_system_config_windows
export -f patch_ghc_toolchain_output
