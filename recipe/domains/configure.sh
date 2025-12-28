#!/usr/bin/env bash
# domains/configure.sh - ALL CONFIGURE LOGIC FOR ALL PLATFORMS
# Domain-centric: everything about "configure" is here
#
# STREAMLINED: Uses support/toolchain.sh for minimal, correct toolchain setup.
# See TOOLCHAIN-MINIMAL.md for the analysis showing this is sufficient.

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/toolchain.sh"

#=============================================================================
# PUBLIC API (called from build.sh)
#=============================================================================

configure_ghc() {
    log_info "Phase: Configure GHC"

    # Build toolchain arguments (handles all platforms uniformly)
    local -a tc_args
    build_toolchain_args tc_args

    # Common configure arguments
    # Use PREFIX for library paths (conda-forge makes build deps available here)
    local -a common_args=(
        "--prefix=${PREFIX}"
        "--with-system-libffi"
        "--with-ffi-includes=${PREFIX}/include"
        "--with-ffi-libraries=${PREFIX}/lib"
        "--with-gmp-includes=${PREFIX}/include"
        "--with-gmp-libraries=${PREFIX}/lib"
        "--with-iconv-includes=${PREFIX}/include"
        "--with-iconv-libraries=${PREFIX}/lib"
    )

    # Platform-specific library paths
    case "${target_platform}" in
        linux-*)
            common_args+=(
                "--with-curses-includes=${PREFIX}/include"
                "--with-curses-libraries=${PREFIX}/lib"
                "--disable-numa"
            )
            ;;
    esac

    # Run configure with all arguments
    run_and_log "configure" ./configure \
        "${common_args[@]}" \
        "${tc_args[@]}"
}

post_configure_ghc() {
    log_info "Phase: Post-Configure"

    # Minimal fixes - configure handles most things correctly
    # See TOOLCHAIN-MINIMAL.md for why this is sufficient
    post_configure_fixes

    log_info "✓ Post-configure complete"
}

#=============================================================================
# LINUX CONFIGURE (native and cross)
#=============================================================================

_configure_linux_native() {
    log_info "  Linux x86_64 native"

    run_and_log "configure" ./configure \
        --prefix="${PREFIX}" \
        --build="x86_64-unknown-linux-gnu" \
        --host="x86_64-unknown-linux-gnu" \
        --target="x86_64-unknown-linux-gnu" \
        $(_common_configure_args) \
        ac_cv_func_statx=no \
        CC="${CC}" CXX="${CXX}" LD="${LD}" AR="${AR}"
}

_configure_linux_cross() {
    local arch="$1"
    local target_triple sysroot

    case "${arch}" in
        aarch64)
            target_triple="aarch64-unknown-linux-gnu"
            sysroot="${BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot"
            ;;
        ppc64le)
            target_triple="powerpc64le-unknown-linux-gnu"
            sysroot="${BUILD_PREFIX}/powerpc64le-conda-linux-gnu/sysroot"
            ;;
    esac

    log_info "  Linux cross-compile: ${arch} → ${target_triple}"

    run_and_log "configure" ./configure \
        --prefix="${PREFIX}" \
        --build="x86_64-unknown-linux-gnu" \
        --host="${target_triple}" \
        --target="${target_triple}" \
        $(_common_configure_args) \
        cross_compiling=yes \
        ac_cv_func_statx=no \
        CC="${target_triple}-gcc --sysroot=${sysroot}" \
        LD="${target_triple}-ld --sysroot=${sysroot}"
}

_post_configure_linux_cross() {
    local settings="$1"

    # Strip BUILD_PREFIX from tools
    perl -i -pe "s|${BUILD_PREFIX}/||g" "${settings}"

    # Fix Python path
    perl -i -pe "s|^(python:).*|\$1 ${BUILD_PREFIX}/bin/python3|" "${settings}"
}

#=============================================================================
# MACOS CONFIGURE (native and cross)
#=============================================================================

_configure_macos_native() {
    log_info "  macOS x86_64 native"

    _setup_macos_llvm_ar  # macOS-specific: use llvm-ar

    run_and_log "configure" ./configure \
        --prefix="${PREFIX}" \
        --build="x86_64-apple-darwin" \
        --host="x86_64-apple-darwin" \
        --target="x86_64-apple-darwin" \
        $(_common_configure_args) \
        CC="${CC}" CXX="${CXX}" LD="${LD}" \
        AR="${BUILD_PREFIX}/bin/llvm-ar" \
        RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
}

_configure_macos_cross() {
    log_info "  macOS arm64 cross-compile"

    _setup_macos_llvm_ar

    run_and_log "configure" ./configure \
        --prefix="${PREFIX}" \
        --build="x86_64-apple-darwin" \
        --host="aarch64-apple-darwin" \
        --target="aarch64-apple-darwin" \
        $(_common_configure_args) \
        cross_compiling=yes \
        CC="${CC}" CXX="${CXX}" LD="${LD}" \
        AR="${BUILD_PREFIX}/bin/llvm-ar" \
        RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
}

_post_configure_macos_native() {
    local settings="$1"
    _patch_macos_ar_ranlib "${settings}"
}

_post_configure_macos_cross() {
    local settings="$1"
    _patch_macos_ar_ranlib "${settings}"
    perl -i -pe "s|^(python:).*|\$1 ${BUILD_PREFIX}/bin/python3|" "${settings}"
}

_setup_macos_llvm_ar() {
    # macOS Apple ld64 requires BSD archive format (llvm-ar), not GNU ar
    export AR="${BUILD_PREFIX}/bin/llvm-ar"
    export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
}

_patch_macos_ar_ranlib() {
    local settings="$1"
    perl -i -pe "s|^(ar-prog:).*|\$1 ${BUILD_PREFIX}/bin/llvm-ar|" "${settings}"
    perl -i -pe "s|^(ranlib-prog:).*|\$1 ${BUILD_PREFIX}/bin/llvm-ranlib|" "${settings}"
}

#=============================================================================
# WINDOWS CONFIGURE
#=============================================================================

_configure_windows() {
    log_info "  Windows MinGW-w64"

    _setup_windows_sdk  # Windows-specific SDK setup

    run_and_log "configure" ./configure \
        --prefix="${PREFIX}" \
        --build="x86_64-w64-mingw32" \
        --host="x86_64-w64-mingw32" \
        --target="x86_64-w64-mingw32" \
        --enable-distro-toolchain \
        $(_common_configure_args) \
        CC="${CC}" CXX="${CXX}" LD="${LD}"
}

_post_configure_windows() {
    local settings="$1"

    # Expand conda variables in settings
    perl -i -pe "s|%BUILD_PREFIX%|${BUILD_PREFIX}|g" "${settings}"
    perl -i -pe "s|%PREFIX%|${PREFIX}|g" "${settings}"

    # Remove problematic flags
    perl -i -pe 's|-Wl,--export-all-symbols||g' "${settings}"
}

_setup_windows_sdk() {
    # Windows SDK path setup
    export INCLUDE="${BUILD_PREFIX}/Library/include"
    export LIB="${BUILD_PREFIX}/Library/lib"
}

#=============================================================================
# SHARED HELPERS (inline, not in separate file)
#=============================================================================

_common_configure_args() {
    echo "--with-system-libffi \
          --with-ffi-includes=${PREFIX}/include \
          --with-ffi-libraries=${PREFIX}/lib \
          --with-gmp-includes=${PREFIX}/include \
          --with-gmp-libraries=${PREFIX}/lib"
}

_patch_linker_flags() {
    local settings="$1"
    perl -i -pe "s|^(ld-options:.*)|\$1 ${LDFLAGS:-}|" "${settings}"
}

_patch_doc_placeholders() {
    local settings="$1"
    local doc_dir="${PREFIX}/share/doc/ghc-${PKG_VERSION}"
    perl -i -pe "s|{docdir}|${doc_dir}|g" "${settings}"
    perl -i -pe "s|{htmldir}|${doc_dir}/html|g" "${settings}"
}
