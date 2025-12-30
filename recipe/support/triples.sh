#!/usr/bin/env bash
# support/triples.sh - Platform triple detection and configuration
# Part of domain-centric architecture

set -eu

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

    # Conda toolchain triples (compatibility with working feedstock lib/triple-helpers.sh)
    # These use conda toolchain format: {arch}-conda-{os}
    # In cross-compile: conda_host = conda_build (both are build platform)
    if [[ "${BUILD}" != "${TARGET}" ]]; then
        # Cross-compile: build/host are build platform, target is cross target
        export conda_build="${build_plat//-64/}"  # linux-64 → linux
        export conda_host="${conda_build}"
        case "${target_plat}" in
            linux-64)       conda_target="x86_64-conda-linux-gnu" ;;
            linux-aarch64)  conda_target="aarch64-conda-linux-gnu" ;;
            linux-ppc64le)  conda_target="powerpc64le-conda-linux-gnu" ;;
            osx-64)         conda_target="x86_64-apple-darwin" ;;
            osx-arm64)      conda_target="aarch64-apple-darwin" ;;
            win-64)         conda_target="x86_64-w64-mingw32" ;;
        esac

        # Convert conda_build/conda_host to full conda toolchain format
        case "${build_plat}" in
            linux-64)       conda_build="x86_64-conda-linux-gnu"; conda_host="${conda_build}" ;;
            linux-aarch64)  conda_build="aarch64-conda-linux-gnu"; conda_host="${conda_build}" ;;
            linux-ppc64le)  conda_build="powerpc64le-conda-linux-gnu"; conda_host="${conda_build}" ;;
            osx-64)         conda_build="x86_64-apple-darwin"; conda_host="${conda_build}" ;;
            osx-arm64)      conda_build="aarch64-apple-darwin"; conda_host="${conda_build}" ;;
            win-64)         conda_build="x86_64-w64-mingw32"; conda_host="${conda_build}" ;;
        esac
    else
        # Native build: all three are the same
        case "${target_plat}" in
            linux-64)       conda_build="x86_64-conda-linux-gnu" ;;
            linux-aarch64)  conda_build="aarch64-conda-linux-gnu" ;;
            linux-ppc64le)  conda_build="powerpc64le-conda-linux-gnu" ;;
            osx-64)         conda_build="x86_64-apple-darwin" ;;
            osx-arm64)      conda_build="aarch64-apple-darwin" ;;
            win-64)         conda_build="x86_64-w64-mingw32" ;;
        esac
        conda_host="${conda_build}"
        conda_target="${conda_build}"
    fi

    export conda_build conda_host conda_target
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
