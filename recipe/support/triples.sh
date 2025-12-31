#!/usr/bin/env bash
# support/triples.sh - Platform triple detection and configuration
# Part of domain-centric architecture

set -eu

# GHC triple format for each platform (with SDK versions for macOS)
_ghc_triple_for_platform() {
    case "$1" in
        linux-64)       echo "x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  echo "aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  echo "powerpc64le-unknown-linux-gnu" ;;
        osx-64)         echo "x86_64-apple-darwin13.4.0" ;;
        osx-arm64)      echo "aarch64-apple-darwin20.0.0" ;;
        win-64)         echo "x86_64-unknown-mingw32" ;;
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
    case "${build_plat}" in
        linux-64)       BUILD="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  BUILD="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  BUILD="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         BUILD="x86_64-apple-darwin" ;;
        osx-arm64)      BUILD="aarch64-apple-darwin" ;;
        win-64)         BUILD="x86_64-w64-mingw32" ;;
    esac

    case "${host_plat}" in
        linux-64)       HOST="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  HOST="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  HOST="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         HOST="x86_64-apple-darwin" ;;
        osx-arm64)      HOST="aarch64-apple-darwin" ;;
        win-64)         HOST="x86_64-w64-mingw32" ;;
    esac

    case "${target_plat}" in
        linux-64)       TARGET="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  TARGET="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  TARGET="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         TARGET="x86_64-apple-darwin" ;;
        osx-arm64)      TARGET="aarch64-apple-darwin" ;;
        win-64)         TARGET="x86_64-w64-mingw32" ;;
    esac

    # Export GHC triples
    export BUILD HOST TARGET

    # Conda toolchain triples (match modularization branch logic exactly)
    if [[ "${BUILD}" != "${TARGET}" ]]; then
        # Cross-compile: compute triples from platform names
        local build_triple=$(_ghc_triple_for_platform "${build_plat}")
        local target_triple=$(_ghc_triple_for_platform "${target_plat}")

        export conda_build="${build_triple}"
        export conda_host="${build_triple}"  # GHC HOST = BUILD in cross-compile
        export conda_target="${target_triple}"
    else
        # Native build: all three are the same
        local triple=$(_ghc_triple_for_platform "${target_plat}")
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
