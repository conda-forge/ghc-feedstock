#!/usr/bin/env bash
# domains/install.sh - ALL install logic for ALL platforms
# Part of domain-centric architecture

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"
source "${RECIPE_DIR}/support/toolchain.sh"

# Source platform-specific helper libraries
source "${RECIPE_DIR}/lib/helpers.sh"
if [[ "${target_platform}" == "win-64" ]]; then
    source "${RECIPE_DIR}/lib/windows-helpers.sh"
fi

install_ghc() {
    log_info "Phase: Install GHC"

    # Create binary distribution
    _create_bindist

    # Install it
    _install_bindist

    log_info "✓ GHC installed"
}

post_install_ghc() {
    log_info "Phase: Post-Install"

    # Fix settings file (strip BUILD_PREFIX)
    post_install_fixes

    # Verify installation
    _verify_install

    log_info "✓ Post-install complete"
}

_create_bindist() {
    log_info "  Creating binary distribution..."

    local -a hadrian_cmd=(
        "${HADRIAN_EXE}"
        binary-dist-dir
        --prefix="${PREFIX}"
        -j"${CPU_COUNT}"
        --docs=no-sphinx
    )

    # Add flavour
    local flavour="release"
    if is_windows; then
        flavour="quickest"
    elif [[ "${target_platform}" == "osx-64" ]]; then
        flavour="release+omit_pragmas"
    fi
    hadrian_cmd+=(--flavour="${flavour}")

    # Cross-compile: freeze stages
    if is_cross_compile; then
        hadrian_cmd+=(--freeze1 --freeze2)
    fi

    # Windows: add --directory flag
    if is_windows; then
        hadrian_cmd+=(--directory "${_SRC_DIR}")
    fi

    run_and_log "create-bindist" "${hadrian_cmd[@]}"
}

_install_bindist() {
    log_info "  Installing binary distribution..."

    # Find bindist directory
    # Windows uses x86_64-unknown-mingw32 (not x86_64-w64-mingw32) for target triple
    local bindist_dir
    if is_windows; then
        local ghc_target="x86_64-unknown-mingw32"
        bindist_dir=$(find "${_SRC_DIR}/_build/bindist" -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)
    else
        bindist_dir=$(find "${SRC_DIR}/_build/bindist" -maxdepth 1 -name "ghc-${PKG_VERSION}-*" -type d | head -1)
    fi

    if [[ -z "${bindist_dir}" ]]; then
        die "Binary distribution directory not found"
    fi

    log_info "  Binary distribution: ${bindist_dir}"

    # Windows: Just copy directly (bindists are relocatable)
    if is_windows; then
        log_info "  Installing to: ${_PREFIX}"
        cp -r "${bindist_dir}"/* "${_PREFIX}"/

        # Copy windres wrapper for installed package
        cp "${_BUILD_PREFIX}/Library/bin/windres.bat" "${_PREFIX}/bin/ghc_windres.bat"

        # Post-install cleanup (replace bundled mingw, update settings)
        post_install_cleanup
    else
        # Unix: Run configure and make install
        pushd "${bindist_dir}" >/dev/null

        # CRITICAL: Bindist configure runs on BUILD platform, not TARGET
        # Clear cross-compile environment to use BUILD compiler
        if is_cross_compile; then
            log_info "  Clearing cross-compile environment for bindist configure..."
            unset CC CXX LD AR NM RANLIB OBJDUMP STRIP
            # Use BUILD platform compiler explicitly
            export CC="${CC_FOR_BUILD:-gcc}"
            export CXX="${CXX_FOR_BUILD:-g++}"
        fi

        # Remove autoconf cache (critical for cross-compile)
        # Autoconf caches compiler paths - must clear for BUILD compiler
        rm -f config.cache

        # Configure bindist
        local -a configure_args=(--prefix="${PREFIX}")
        if is_cross_compile; then
            configure_args+=(--target="${TARGET}")
        fi

        run_and_log "configure-bindist" ./configure "${configure_args[@]}"

        # Install (skip update_package_db for cross-compile - can fail)
        run_and_log "install-bindist" make install_bin install_lib install_man

        popd >/dev/null
    fi

    # Install conda activation scripts
    _install_activation_scripts
}

_install_activation_scripts() {
    log_info "  Installing conda activation scripts..."

    mkdir -p "${PREFIX}/etc/conda/activate.d"

    # Determine script extension
    local sh_ext="sh"
    if is_windows; then
        sh_ext="bat"
    fi

    # Copy activation script
    cp "${RECIPE_DIR}/scripts/activate.${sh_ext}" \
       "${PREFIX}/etc/conda/activate.d/ghc_activate.${sh_ext}"

    log_info "  ✓ Activation scripts installed"
}

_verify_install() {
    log_info "  Verifying installation..."

    # Windows: Use verify_installed_binaries from windows-helpers.sh
    if is_windows; then
        verify_installed_binaries || die "Windows binary verification failed"
    else
        # Check GHC installed
        if [[ ! -x "${PREFIX}/bin/ghc" ]]; then
            die "GHC not found at ${PREFIX}/bin/ghc"
        fi

        # Check settings file
        local settings="${PREFIX}/lib/ghc-${PKG_VERSION}/lib/settings"
        if [[ ! -f "${settings}" ]]; then
            die "Settings file not found"
        fi

        log_info "  GHC version: $(${PREFIX}/bin/ghc --version)"
    fi
}
