#!/usr/bin/env bash
# domains/install.sh - ALL install logic for ALL platforms
# Part of domain-centric architecture

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"
source "${RECIPE_DIR}/support/toolchain.sh"

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

    run_and_log "create-bindist" "${hadrian_cmd[@]}"
}

_install_bindist() {
    log_info "  Installing binary distribution..."

    # Find bindist directory
    local bindist_dir
    bindist_dir=$(find "${SRC_DIR}/_build/bindist" -maxdepth 1 -name "ghc-${PKG_VERSION}-*" -type d | head -1)

    if [[ -z "${bindist_dir}" ]]; then
        die "Binary distribution directory not found"
    fi

    pushd "${bindist_dir}" >/dev/null

    # Configure bindist
    local -a configure_args=(--prefix="${PREFIX}")
    if is_cross_compile; then
        configure_args+=(--target="${TARGET}")
    fi

    run_and_log "configure-bindist" ./configure "${configure_args[@]}"

    # Install (skip update_package_db for cross-compile - can fail)
    run_and_log "install-bindist" make install_bin install_lib install_man

    popd >/dev/null
}

_verify_install() {
    log_info "  Verifying installation..."

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
}
