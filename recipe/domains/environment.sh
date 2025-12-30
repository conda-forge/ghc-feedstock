#!/usr/bin/env bash
# domains/environment.sh - ALL environment setup for ALL platforms
# Part of domain-centric architecture

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"

# Source platform-specific helper libraries (from recipe/lib/)
# These contain the platform-specific functions we call in _setup_*_environment()
source "${RECIPE_DIR}/lib/helpers.sh"
if [[ "${target_platform}" == osx-* ]]; then
    source "${RECIPE_DIR}/lib/macos-common.sh"
elif [[ "${target_platform}" == "win-64" ]]; then
    source "${RECIPE_DIR}/lib/windows-helpers.sh"
fi

setup_environment() {
    log_info "Phase: Environment Setup"

    # Detect platform triples
    detect_platform_triples

    # Common environment for all platforms
    export M4="${BUILD_PREFIX}/bin/m4"
    export PYTHON="${BUILD_PREFIX}/bin/python3"
    export GHC="${BUILD_PREFIX}/ghc-bootstrap/bin/ghc"
    export GHC_PKG="${BUILD_PREFIX}/ghc-bootstrap/bin/ghc-pkg"
    export CABAL="${BUILD_PREFIX}/bin/cabal"

    # Library search paths for build
    # LIBRARY_PATH: compile-time (where to find libs when linking)
    # LD_LIBRARY_PATH: runtime for Linux/Windows
    # DYLD_LIBRARY_PATH: runtime for macOS
    # BUILD_PREFIX first: build tools (ghc-pkg, hsc2hs) run on build machine
    # PREFIX second: target libraries for final package
    export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${LIBRARY_PATH:-}"
    export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
    export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
    export C_INCLUDE_PATH="${PREFIX}/include:${C_INCLUDE_PATH:-}"
    export CPLUS_INCLUDE_PATH="${PREFIX}/include:${CPLUS_INCLUDE_PATH:-}"

    # CRITICAL: Prevent autoconf from searching for system compilers
    # conda-forge always provides compilers in BUILD_PREFIX/PREFIX
    # This prevents configure from finding /usr/bin/gcc, /usr/bin/g++, Xcode, etc.
    export ac_cv_path_ac_pt_CC=""
    export ac_cv_path_ac_pt_CXX=""
    export DEVELOPER_DIR=""  # Prevent macOS Xcode detection

    # Cross-compilation: Additional autoconf configuration
    # Prevent configure from finding or testing wrong compilers
    if [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]; then
        # Prevent autoconf from searching for compilers (use only what we explicitly pass)
        export ac_cv_prog_CC="${CC}"
        export ac_cv_prog_CXX="${CXX}"
        # Tell autoconf this is a cross-compile environment
        export cross_compiling=yes
    fi

    # Platform-specific setup
    if is_linux; then
        _setup_linux_environment
    elif is_macos; then
        _setup_macos_environment
    elif is_windows; then
        _setup_windows_environment
    fi

    log_info "✓ Environment ready (${target_platform})"
}

_setup_linux_environment() {
    # Cross-compilation: C++ stdlib and sysroot setup
    if is_cross_compile; then
        # Explicitly specify C++ stdlib for cross-compilation (same as macOS)
        export CXX_STD_LIB_LIBS='stdc++'

        # CRITICAL: In cross-compile, we have TWO sysroots:
        # 1. BUILD sysroot (x86_64): for Hadrian, cabal, Stage0/Stage1 executables
        #    → ${BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot
        # 2. TARGET sysroot (e.g., aarch64): for GHC libraries (Stage2)
        #    → ${BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot
        #
        # Strategy (matching working feedstock):
        # 1. Set CONDA_BUILD_SYSROOT to BUILD sysroot for Hadrian/Stage0/Stage1
        # 2. Later, explicitly override to TARGET sysroot for Stage2 libraries
        #
        # conda_host is set by detect_platform_triples() to build platform
        export CONDA_BUILD_SYSROOT="${BUILD_PREFIX}/${conda_host}/sysroot"
        log_info "  Set CONDA_BUILD_SYSROOT to BUILD platform: ${CONDA_BUILD_SYSROOT}"
    fi
}

_setup_macos_environment() {
    log_info "  macOS-specific environment setup"

    # Unset build_alias/host_alias - they interfere with configure scripts
    unset build_alias host_alias

    # Complete macOS setup: llvm-ar, iconv_compat, DYLD env, bootstrap patches
    # For cross-compile, skip iconv creation (arm64 uses different approach)
    if is_cross_compile; then
        macos_complete_setup "false"  # Skip iconv creation for cross-compile
        export CXX_STD_LIB_LIBS='c++ c++abi'
    else
        macos_complete_setup "true"   # Create iconv_compat for native
    fi

    # macOS SDK path
    if [[ -n "${CONDA_BUILD_SYSROOT:-}" ]]; then
        export SDKROOT="${CONDA_BUILD_SYSROOT}"
    fi

    # Ensure BUILD_PREFIX/bin is in PATH
    export PATH="${BUILD_PREFIX}/bin:${PATH}"
}

_setup_windows_environment() {
    log_info "  Windows-specific environment setup"

    # Windows path variables (both Unix and Windows formats needed)
    export _PREFIX_="${PREFIX}"
    export _PREFIX="$(cygpath -u "${PREFIX}")"
    export _BUILD_PREFIX_="${BUILD_PREFIX}"
    export _BUILD_PREFIX="$(cygpath -u "${BUILD_PREFIX}")"
    export _SRC_DIR="${SRC_DIR}"
    export _RECIPE_DIR="${RECIPE_DIR}"

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

    # Expand conda variables in flags (from windows-helpers.sh)
    windows_expand_conda_variables

    # Remove problematic flags (from windows-helpers.sh)
    windows_remove_problematic_flags

    export CFLAGS="-I${_BUILD_PREFIX}/Library/include ${CFLAGS:-}"
    export CXXFLAGS="-I${_BUILD_PREFIX}/Library/include ${CXXFLAGS:-}"
    export LDFLAGS="-L${_BUILD_PREFIX}/Library/lib -L${_BUILD_PREFIX}/Library/lib/gcc/x86_64-w64-mingw32/15.2.0 ${LDFLAGS:-}"

    # Fix windres.bat (ghc-bootstrap bug)
    if [[ -f "${_BUILD_PREFIX}/ghc-bootstrap/bin/windres.bat" ]]; then
        perl -pi -e 's/findstr/C:\\Windows\\System32\\findstr/g' "${_BUILD_PREFIX}/ghc-bootstrap/bin/windres.bat"
    fi

    # Create chkstk_ms stub library (from windows-helpers.sh)
    create_chkstk_stub

    # Install windres wrapper
    if [[ -f "${_RECIPE_DIR}/support/windres.bat" ]]; then
        cp "${_RECIPE_DIR}/support/windres.bat" "${_BUILD_PREFIX}/Library/bin/"
        log_info "  Installed windres.bat wrapper"
    fi

    # Patch bootstrap settings (tool paths, CFLAGS, dllwrap=false, etc.)
    patch_windows_settings "${_BUILD_PREFIX}/ghc-bootstrap/lib/settings" --bootstrap --debug

    # Set up temp variables
    export TMP="$(cygpath -w "${TEMP}")"
    export TMPDIR="$(cygpath -w "${TEMP}")"

    # Copy m4 to bin for autoconf
    mkdir -p "${_BUILD_PREFIX}/bin"
    cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin/" 2>/dev/null || true

    log_info "  ✓ Windows environment configured"
}
