#!/usr/bin/env bash
# support/triples.sh - Platform triple detection and configuration
# Part of domain-centric architecture

set -eu

# Platform triple detection
# Sets BUILD, HOST, TARGET based on conda-forge environment vars
detect_platform_triples() {
    # Conda-forge provides these
    export BUILD="${build_platform:-${target_platform}}"
    export HOST="${build_platform:-${target_platform}}"  # GHC: HOST must equal BUILD (can't cross-compile GHC itself)
    export TARGET="${target_platform}"

    # Normalize to GHC format (conda uses linux, GHC wants unknown-linux-gnu)
    case "${BUILD}" in
        linux-64)       BUILD="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  BUILD="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  BUILD="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         BUILD="x86_64-apple-darwin" ;;
        osx-arm64)      BUILD="aarch64-apple-darwin" ;;
        win-64)         BUILD="x86_64-w64-mingw32" ;;
    esac

    case "${HOST}" in
        linux-64)       HOST="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  HOST="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  HOST="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         HOST="x86_64-apple-darwin" ;;
        osx-arm64)      HOST="aarch64-apple-darwin" ;;
        win-64)         HOST="x86_64-w64-mingw32" ;;
    esac

    case "${TARGET}" in
        linux-64)       TARGET="x86_64-unknown-linux-gnu" ;;
        linux-aarch64)  TARGET="aarch64-unknown-linux-gnu" ;;
        linux-ppc64le)  TARGET="powerpc64le-unknown-linux-gnu" ;;
        osx-64)         TARGET="x86_64-apple-darwin" ;;
        osx-arm64)      TARGET="aarch64-apple-darwin" ;;
        win-64)         TARGET="x86_64-w64-mingw32" ;;
    esac
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
