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
    # CRITICAL: For macOS, toolchain binaries include SDK version (x86_64-apple-darwin13.4.0-*)
    # We must use conda-forge's build_alias/host_alias variables directly, not recompute them
    if [[ "${BUILD}" != "${TARGET}" ]]; then
        # Cross-compile: Use conda-forge's actual toolchain prefixes
        # These are provided by conda-forge and include version suffixes where needed
        export conda_build="${build_alias}"
        export conda_host="${build_alias}"  # GHC HOST = BUILD in cross-compile
        export conda_target="${host_alias}"  # host_alias is the target platform in conda terms
    else
        # Native build: Use build_alias for all three (if available)
        if [[ -n "${build_alias:-}" ]]; then
            export conda_build="${build_alias}"
            export conda_host="${build_alias}"
            export conda_target="${build_alias}"
        else
            # Fallback if build_alias not set (shouldn't happen in conda-forge)
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
            export conda_build conda_host conda_target
        fi
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
