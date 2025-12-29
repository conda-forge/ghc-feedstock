#!/usr/bin/env bash
# domains/build.sh - ALL build logic for ALL platforms
# Part of domain-centric architecture

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"

# Global for Hadrian path
HADRIAN_EXE=""

build_hadrian() {
    log_info "Phase: Build Hadrian"

    pushd hadrian >/dev/null

    # Update cabal package index if needed
    if [[ ! -f "${HOME}/.cabal/packages/hackage.haskell.org/01-index.tar" ]]; then
        log_info "  Updating cabal package index..."
        "${CABAL}" v2-update || true  # Don't fail if offline
    fi

    # Build cabal flags array
    local -a cabal_flags=(
        --with-compiler="${GHC}"
        -j"${CPU_COUNT}"
    )

    # CRITICAL for cross-compile: Hadrian runs on BUILD machine, needs BUILD toolchain
    # Use cabal --with-* flags instead of env vars (more surgical, no downstream effects)
    if is_cross_compile; then
        log_info "  Building Hadrian with BUILD toolchain (cabal flags)"
        cabal_flags+=(
            "--with-gcc=${CC_FOR_BUILD:-${CC}}"
            "--with-ar=${AR_FOR_BUILD:-${AR}}"
        )
        # Add LD if available
        if [[ -n "${LD_FOR_BUILD:-}" ]]; then
            cabal_flags+=("--with-ld=${LD_FOR_BUILD}")
        fi
    fi

    # Use v2-build (modern cabal command)
    run_and_log "build-hadrian" "${CABAL}" v2-build "${cabal_flags[@]}" hadrian

    popd >/dev/null

    # Find the built executable (v2-build puts it in dist-newstyle)
    HADRIAN_EXE=$(find hadrian/dist-newstyle -name hadrian -type f -executable 2>/dev/null | head -1)
    if [[ -z "${HADRIAN_EXE}" ]]; then
        die "Hadrian executable not found"
    fi

    log_info "✓ Hadrian built: ${HADRIAN_EXE}"
}

build_stage1() {
    log_info "Phase: Build Stage 1"

    # Determine flavour
    local flavour="release"
    if is_windows; then
        flavour="quickest"  # Windows needs quickest to avoid 32-bit relocation overflow
    elif [[ "${target_platform}" == "osx-64" ]]; then
        flavour="release+omit_pragmas"  # macOS x86_64 needs omit_pragmas for timeout
    fi

    # Build stage 1 targets
    local -a hadrian_cmd=(
        "${HADRIAN_EXE}"
        --flavour="${flavour}"
        -j"${CPU_COUNT}"
        --docs=no-sphinx
    )

    # Build stage 1 executables
    if is_cross_compile; then
        hadrian_cmd+=(--freeze1)
    fi

    hadrian_cmd+=(
        stage1:exe:ghc-bin
        stage1:exe:ghc-pkg
        stage1:exe:hsc2hs
    )

    run_and_log "build-stage1" "${hadrian_cmd[@]}"

    log_info "✓ Stage 1 built"
}

build_stage2() {
    log_info "Phase: Build Stage 2"

    # Skip stage2 for Windows (quickest flavour)
    if is_windows; then
        log_info "  Skipping stage 2 (Windows uses quickest flavour)"
        return 0
    fi

    # Determine flavour
    local flavour="release"
    if [[ "${target_platform}" == "osx-64" ]]; then
        flavour="release+omit_pragmas"
    fi

    # Cross-compile: only build stage 1 libraries
    if is_cross_compile; then
        log_info "  Building stage 1 libraries (cross-compile)"

        # CRITICAL: These libraries are FOR the target, need target sysroot
        # Detect target triple to find correct sysroot
        local target_triple
        case "${target_platform}" in
            linux-aarch64)
                target_triple="aarch64-conda-linux-gnu"
                ;;
            linux-ppc64le)
                target_triple="powerpc64le-conda-linux-gnu"
                ;;
            osx-arm64)
                # macOS uses CONDA_BUILD_SYSROOT already set in environment
                target_triple=""
                ;;
            *)
                die "Unknown cross-compile target: ${target_platform}"
                ;;
        esac

        # Set target sysroot for Linux cross-compile
        if [[ -n "${target_triple}" ]]; then
            export CONDA_BUILD_SYSROOT="${BUILD_PREFIX}/${target_triple}/sysroot"
            log_info "  Using target sysroot: ${CONDA_BUILD_SYSROOT}"
        fi

        local -a hadrian_cmd=(
            "${HADRIAN_EXE}"
            --flavour="${flavour}"
            -j"${CPU_COUNT}"
            --docs=no-sphinx
            --freeze1
            --freeze2
            stage1:lib:ghc
        )

        run_and_log "build-stage2" "${hadrian_cmd[@]}"
    else
        # Native: build stage 2 executables and libraries
        log_info "  Building stage 2 executables"

        local -a hadrian_cmd=(
            "${HADRIAN_EXE}"
            --flavour="${flavour}"
            -j"${CPU_COUNT}"
            --docs=no-sphinx
            --freeze1
            stage2:exe:ghc-bin
            stage2:exe:ghc-pkg
            stage2:exe:hsc2hs
        )

        run_and_log "build-stage2-exe" "${hadrian_cmd[@]}"

        log_info "  Building stage 2 libraries"

        hadrian_cmd=(
            "${HADRIAN_EXE}"
            --flavour="${flavour}"
            -j"${CPU_COUNT}"
            --docs=no-sphinx
            --freeze1
            stage2:lib:ghc
        )

        run_and_log "build-stage2-lib" "${hadrian_cmd[@]}"
    fi

    log_info "✓ Stage 2 built"
}
