#!/usr/bin/env bash
# support/triples.sh - Platform triple detection and configuration
# Part of domain-centric architecture

set -eu

# Conda toolchain triple format for each platform
# Linux: uses conda format (x86_64-conda-linux-gnu) for toolchain binaries
# macOS: uses GHC format with SDK version (x86_64-apple-darwin13.4.0)
# Windows: uses mingw format
_conda_toolchain_triple() {
    case "$1" in
        linux-64)       echo "x86_64-conda-linux-gnu" ;;
        linux-aarch64)  echo "aarch64-conda-linux-gnu" ;;
        linux-ppc64le)  echo "powerpc64le-conda-linux-gnu" ;;
        osx-64)         echo "x86_64-apple-darwin13.4.0" ;;
        osx-arm64)      echo "aarch64-apple-darwin20.0.0" ;;
        win-64)         echo "x86_64-w64-mingw32" ;;
        *)              echo "unknown" ;;
    esac
}

# Platform triple detection
# Sets BUILD, HOST, TARGET based on conda-forge environment vars
# Also sets conda_build, conda_host, conda_target for compatibility with working feedstock
detect_platform_triples() {
    # Conda-forge provides these
    local build_plat="${build_platform:-${target_platform}}"
    local host_plat="${build_platform:-${target_platform}}"  # GHC: HOST must equal BUILD (can't cross-compile GHC itself)
    local target_plat="${target_platform}"

    # Normalize to GHC format (conda uses linux, GHC wants unknown-linux-gnu)
    # CRITICAL: macOS requires SDK version suffix (e.g., 13.4.0, 20.0.0)
    # Without version, GHC's bindist configure script rejects the platform triple
    case "${build_plat}" in
        linux-64)       BUILD="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  BUILD="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  BUILD="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         BUILD="x86_64-apple-darwin13.4.0" ;;
        osx-arm64)      BUILD="aarch64-apple-darwin20.0.0" ;;
        win-64)         BUILD="x86_64-w64-mingw32" ;;
    esac

    case "${host_plat}" in
        linux-64)       HOST="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  HOST="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  HOST="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         HOST="x86_64-apple-darwin13.4.0" ;;
        osx-arm64)      HOST="aarch64-apple-darwin20.0.0" ;;
        win-64)         HOST="x86_64-w64-mingw32" ;;
    esac

    case "${target_plat}" in
        linux-64)       TARGET="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  TARGET="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  TARGET="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         TARGET="x86_64-apple-darwin13.4.0" ;;
        osx-arm64)      TARGET="aarch64-apple-darwin20.0.0" ;;
        win-64)         TARGET="x86_64-w64-mingw32" ;;
    esac

    # Export GHC triples
    export BUILD HOST TARGET

    # Conda toolchain triples (for creating symlinks, finding binaries)
    # CRITICAL: conda_target must be in conda format (e.g., aarch64-conda-linux-gnu)
    # because cross_build_toolchain_args uses it to find sysroot at:
    # ${BUILD_PREFIX}/${conda_target}/sysroot
    if [[ "${BUILD}" != "${TARGET}" ]]; then
        # Cross-compile: Set build_alias/host_alias for compatibility
        # These match the working feedstock's triple-helpers.sh pattern
        local build_conda=$(_conda_toolchain_triple "${build_plat}")
        local target_conda=$(_conda_toolchain_triple "${target_plat}")

        case "${target_plat}" in
            linux-*)
                # For Linux: build_alias/host_alias use GHC-style triples
                # but conda_* use conda-style for sysroot paths
                export build_alias="${BUILD}"
                export host_alias="${BUILD}"  # GHC HOST = BUILD in cross-compile
                export target_alias="${TARGET}"
                export conda_build="${build_conda}"
                export conda_host="${build_conda}"
                export conda_target="${target_conda}"  # MUST be conda-style for sysroot!
                ;;
            osx-*)
                # For macOS: use conda-style with SDK version for all
                export build_alias="${build_conda}"
                export host_alias="${build_conda}"
                export target_alias="${target_conda}"
                export conda_build="${build_conda}"
                export conda_host="${build_conda}"
                export conda_target="${target_conda}"
                ;;
        esac
    else
        # Native build: all three are the same
        local triple=$(_conda_toolchain_triple "${target_plat}")
        export build_alias="${triple}"
        export host_alias="${triple}"
        export conda_build="${triple}"
        export conda_host="${triple}"
        export conda_target="${triple}"
    fi
}

# Detect build type
is_cross_compile() {
    [[ "${BUILD}" != "${TARGET}" ]]
}

is_native() {
    [[ "${BUILD}" == "${TARGET}" ]]
}

is_linux() {
    [[ "${target_platform}" == linux-* ]]
}

is_macos() {
    [[ "${target_platform}" == osx-* ]]
}

is_windows() {
    [[ "${target_platform}" == "win-64" ]]
}
