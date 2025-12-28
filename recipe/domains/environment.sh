#!/usr/bin/env bash
# domains/environment.sh - ALL environment setup for ALL platforms
# Part of domain-centric architecture

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"

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
        # conda-build sets CONDA_BUILD_SYSROOT to TARGET sysroot by default.
        # This breaks Stage0/Stage1 builds (they need BUILD sysroot).
        #
        # Solution: UNSET it here, let conda compiler wrappers auto-detect:
        #   - x86_64-conda-linux-gnu-clang → auto-uses x86_64 sysroot
        #   - aarch64-conda-linux-gnu-clang → auto-uses aarch64 sysroot
        #
        # For Stage2 target libraries, we'll explicitly set it in build_stage2()
        unset CONDA_BUILD_SYSROOT
    fi
}

_setup_macos_environment() {
    # macOS SDK path
    if [[ -n "${CONDA_BUILD_SYSROOT:-}" ]]; then
        export SDKROOT="${CONDA_BUILD_SYSROOT}"
    fi

    # Cross-compile: C++ stdlib
    if is_cross_compile; then
        export CXX_STD_LIB_LIBS='c++ c++abi'
    fi
}

_setup_windows_environment() {
    # Windows path variables (mixed format for Cabal)
    export _PREFIX_="${PREFIX}"
    export _PREFIX="$(cygpath -u "${PREFIX}")"

    # Ensure windres.bat is in PATH
    export PATH="${RECIPE_DIR}/support:${PATH}"
}
