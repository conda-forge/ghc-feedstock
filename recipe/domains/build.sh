#!/usr/bin/env bash
# domains/build.sh - ALL build logic for ALL platforms
# Part of domain-centric architecture

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"

# Source platform-specific helper libraries
source "${RECIPE_DIR}/lib/helpers.sh"
if [[ "${target_platform}" == "win-64" ]]; then
    source "${RECIPE_DIR}/lib/windows-helpers.sh"
fi

# Global for Hadrian path
HADRIAN_EXE=""

# Helper: Add Windows-specific Hadrian flags to array
_add_windows_hadrian_flags() {
    local -n _cmd_array="$1"
    if is_windows; then
        _cmd_array+=(--directory "${_SRC_DIR}")
    fi
}

build_hadrian() {
    log_info "Phase: Build Hadrian"

    # Windows uses _SRC_DIR path format
    local hadrian_dir="hadrian"
    if is_windows; then
        hadrian_dir="${_SRC_DIR}/hadrian"
    fi

    pushd "${hadrian_dir}" >/dev/null

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

        # Linux cross-compile: Set CFLAGS/LDFLAGS with sysroot
        # macOS: LDFLAGS already unset in environment.sh (incompatible with ld64)
        if is_linux; then
            # CONDA_BUILD_SYSROOT was set to BUILD sysroot in environment.sh
            # conda_host was set by detect_platform_triples() to build platform triple
            export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include -fdebug-prefix-map=${SRC_DIR}=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
            export LDFLAGS="-L${BUILD_PREFIX}/${conda_host}/lib -L${BUILD_PREFIX}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"
            log_info "  ✓ Linux BUILD sysroot flags set: ${CONDA_BUILD_SYSROOT}"
        fi

        # Cabal toolchain flags
        # Derive BUILD ar from CC_FOR_BUILD (no AR_FOR_BUILD in conda-forge)
        local build_gcc="${CC_FOR_BUILD:-${CC}}"
        local build_ar="${build_gcc/%-clang/-ar}"
        build_ar="${build_ar/%-gcc/-ar}"

        if is_macos; then
            # macOS: Override with llvm-ar (Apple ld64 requires BSD archive format)
            build_ar="${BUILD_PREFIX}/bin/llvm-ar"
        fi

        cabal_flags+=(
            "--with-gcc=${build_gcc}"
            "--with-ar=${build_ar}"
        )

        log_info "  BUILD toolchain: gcc=${build_gcc}, ar=${build_ar}"
    fi

    # Use v2-build (modern cabal command)
    run_and_log "build-hadrian" "${CABAL}" v2-build "${cabal_flags[@]}" hadrian

    popd >/dev/null

    # Find the built executable (v2-build puts it in dist-newstyle)
    if is_windows; then
        # Windows: find hadrian.exe directly
        HADRIAN_EXE=$(find "${_SRC_DIR}/hadrian/dist-newstyle" -name hadrian.exe -type f 2>/dev/null | head -1)
        if [[ -z "${HADRIAN_EXE}" ]]; then
            die "Hadrian executable not found"
        fi
    else
        HADRIAN_EXE=$(find hadrian/dist-newstyle -name hadrian -type f -executable 2>/dev/null | head -1)
        if [[ -z "${HADRIAN_EXE}" ]]; then
            die "Hadrian executable not found"
        fi
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
    _add_windows_hadrian_flags hadrian_cmd

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

    # Windows: Patch settings with include paths after ghc-bin built
    if is_windows; then
        log_info "  Patching Windows settings with include paths..."
        patch_windows_settings "${_SRC_DIR}/_build/stage0/lib/settings" --include-paths
    fi

    # Windows: Use special library build function
    if is_windows; then
        log_info "  Building Stage 1 libraries (Windows-specific)..."
        windows_build_stage_libraries 1
    fi

    log_info "✓ Stage 1 built"
}

build_stage2() {
    log_info "Phase: Build Stage 2"

    # Determine flavour
    local flavour="release"
    if is_windows; then
        flavour="quickest"  # Windows needs quickest to avoid 32-bit relocation overflow
    elif [[ "${target_platform}" == "osx-64" ]]; then
        flavour="release+omit_pragmas"
    fi

    # Windows: Pre-Stage2 setup
    if is_windows; then
        log_info "  Running Windows-specific Stage2 pre-build..."
        create_fake_mingw_for_binary_dist
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
        _add_windows_hadrian_flags hadrian_cmd

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
        _add_windows_hadrian_flags hadrian_cmd

        run_and_log "build-stage2-exe" "${hadrian_cmd[@]}"

        # Windows: Patch settings with link flags after ghc-bin built
        if is_windows; then
            log_info "  Patching Windows settings with link flags..."
            patch_windows_settings "${_SRC_DIR}/_build/stage1/lib/settings" --link-flags
        fi

        # Windows: Rebuild touchy.exe before libraries
        if is_windows; then
            log_info "  Rebuilding touchy.exe with correct linker flags..."
            rebuild_touchy_with_correct_linker_flags
        fi

        log_info "  Building stage 2 libraries"

        # Windows uses special library build function
        if is_windows; then
            windows_build_stage_libraries 2
        else
            hadrian_cmd=(
                "${HADRIAN_EXE}"
                --flavour="${flavour}"
                -j"${CPU_COUNT}"
                --docs=no-sphinx
                --freeze1
                stage2:lib:ghc
            )
            _add_windows_hadrian_flags hadrian_cmd
            run_and_log "build-stage2-lib" "${hadrian_cmd[@]}"
        fi
    fi

    log_info "✓ Stage 2 built"
}
