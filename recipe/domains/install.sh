#!/usr/bin/env bash
# domains/install.sh - ALL install logic for ALL platforms
# Part of domain-centric architecture
#
# This file handles:
#   - Binary distribution creation (Hadrian)
#   - Bindist installation (configure + make install)
#   - Cross-compile post-install fixes (wrappers, symlinks, settings)
#   - Verification of installed binaries
#
# Cross-compile functions ported from working feedstock's cross-helpers.sh
# to maintain CI compatibility while conforming to domain-centric organization.

source "${RECIPE_DIR}/support/utils.sh"
source "${RECIPE_DIR}/support/triples.sh"
source "${RECIPE_DIR}/support/toolchain.sh"

# Source platform-specific helper libraries
source "${RECIPE_DIR}/lib/helpers.sh"
if [[ "${target_platform}" == "win-64" ]]; then
    source "${RECIPE_DIR}/lib/windows-helpers.sh"
fi

#=============================================================================
# PUBLIC API - Called from build.sh
#=============================================================================

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

    # Cross-compile: Apply critical post-install fixes
    # These MUST run before generic post_install_fixes
    if is_cross_compile; then
        _cross_post_install
    fi

    # Fix settings file (strip BUILD_PREFIX)
    post_install_fixes

    # Verify installation
    _verify_install

    log_info "✓ Post-install complete"
}

#=============================================================================
# BINDIST CREATION
#=============================================================================

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

#=============================================================================
# BINDIST INSTALLATION
#=============================================================================

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
        # Must use BUILD compiler, not cross-compiler
        if is_cross_compile; then
            _setup_bindist_cross_environment
        fi

        # Remove autoconf cache file
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

    # Install bash completion (Unix only)
    if is_unix; then
        _install_bash_completion
    fi
}

# Setup environment for bindist configure during cross-compile
# The bindist configure runs on BUILD platform to generate wrapper scripts,
# so it needs BUILD compiler, not TARGET cross-compiler
_setup_bindist_cross_environment() {
    log_info "  Setting up BUILD platform environment for bindist configure..."

    # Clear autoconf cached variables from main configure run
    # These cache the TARGET compiler but bindist needs BUILD compiler
    unset ac_cv_path_CC ac_cv_path_CXX ac_cv_path_LD
    unset ac_cv_prog_CC ac_cv_prog_CXX ac_cv_prog_LD
    unset ac_cv_prog_cc_c89 ac_cv_prog_cc_c99 ac_cv_prog_cc_c11

    # Clear cross-compile environment variables
    unset CC CXX LD AR NM RANLIB OBJDUMP STRIP

    # Use explicit conda toolchain paths for BUILD platform
    # CRITICAL: Use full paths to conda toolchain, not fallback to system gcc
    local host="${conda_host:-x86_64-conda-linux-gnu}"

    if [[ -x "${BUILD_PREFIX}/bin/${host}-clang" ]]; then
        # Prefer clang from conda toolchain
        export CC="${BUILD_PREFIX}/bin/${host}-clang"
        export CXX="${BUILD_PREFIX}/bin/${host}-clang++"
        log_info "    Using conda clang: ${CC}"
    elif [[ -n "${CC_FOR_BUILD:-}" ]]; then
        # Fallback to CC_FOR_BUILD if set
        export CC="${CC_FOR_BUILD}"
        export CXX="${CXX_FOR_BUILD:-${CC_FOR_BUILD/clang/clang++}}"
        log_info "    Using CC_FOR_BUILD: ${CC}"
    else
        # Last resort: system gcc (may fail on some systems)
        export CC="gcc"
        export CXX="g++"
        log_info "    WARNING: Falling back to system gcc"
    fi

    # Clear flags that might interfere with BUILD platform compile
    export CFLAGS=""
    export CXXFLAGS=""
    export LDFLAGS=""
}

#=============================================================================
# CROSS-COMPILE POST-INSTALL
#=============================================================================
# These functions are ported from working feedstock's cross-helpers.sh
# They fix issues specific to cross-compiled GHC installations.

_cross_post_install() {
    log_info "  Applying cross-compile post-install fixes..."

    # Determine target triple for this build
    local target="${conda_target:-${TARGET}}"
    if [[ -z "${target}" ]]; then
        log_info "  WARNING: No target triple available, skipping cross fixes"
        return 0
    fi

    # 1. Patch installed settings for cross-compile
    _cross_patch_installed_settings "${target}"

    # 2. Fix wrapper scripts (./ prefix bug)
    _cross_fix_wrapper_scripts "${target}"

    # 3. Fix ghci wrapper (points to non-existent binary)
    _cross_fix_ghci_wrapper "${target}"

    # 4. Create symlinks (versioned → unversioned → short)
    _cross_create_symlinks "${target}"

    log_info "  ✓ Cross-compile post-install fixes applied"
}

# Patch installed settings file for cross-compiled GHC
# Fixes:
#   1. Architecture references (host_arch → target_arch)
#   2. Adds relocatable library paths (-rpath with $topdir)
#   3. Strips absolute BUILD_PREFIX paths from tool names
#
# Parameters:
#   $1 - target triple (e.g., aarch64-conda-linux-gnu)
#
_cross_patch_installed_settings() {
    local target="$1"

    log_info "    Patching installed settings for cross-compile..."

    # Find the settings file
    local settings_file
    settings_file=$(_get_installed_settings_file)

    if [[ ! -f "${settings_file}" ]]; then
        log_info "    WARNING: Settings file not found, skipping"
        return 0
    fi

    # Determine architecture substitution
    # host_arch = build platform arch (e.g., x86_64)
    # target_arch = target platform arch (e.g., aarch64, ppc64le)
    local host_arch target_arch
    case "${build_platform:-linux-64}" in
        linux-64|osx-64)   host_arch="x86_64" ;;
        linux-aarch64)     host_arch="aarch64" ;;
        linux-ppc64le)     host_arch="powerpc64le" ;;
        osx-arm64)         host_arch="aarch64" ;;
        *)                 host_arch="x86_64" ;;
    esac

    case "${target_platform}" in
        linux-64)          target_arch="x86_64" ;;
        linux-aarch64)     target_arch="aarch64" ;;
        linux-ppc64le)     target_arch="powerpc64le" ;;
        osx-64)            target_arch="x86_64" ;;
        osx-arm64)         target_arch="aarch64" ;;
        *)                 target_arch="${host_arch}" ;;
    esac

    # 1. Fix architecture references (e.g., x86_64 → aarch64)
    # This handles tool paths and other arch-specific strings
    if [[ "${host_arch}" != "${target_arch}" ]]; then
        perl -pi -e "s#${host_arch}(-[^ \"]*)#${target_arch}\$1#g" "${settings_file}"
        log_info "      Fixed arch references: ${host_arch} → ${target_arch}"
    fi

    # 2. Add relocatable library paths for conda prefix
    # These ensure the installed GHC can find conda-forge libraries at runtime
    # Uses $topdir which GHC resolves to the lib directory at runtime
    perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -Wl,-L\$topdir/../../../lib -Wl,-rpath,\$topdir/../../../lib#' "${settings_file}"
    perl -pi -e 's#(ld flags", "[^"]*)#$1 -L\$topdir/../../../lib -rpath \$topdir/../../../lib#' "${settings_file}"
    log_info "      Added relocatable library paths"

    # 3. Strip absolute tool paths - keep just the target prefix and tool name
    # Pattern: "/full/path/to/aarch64-conda-linux-gnu-ar" → "aarch64-conda-linux-gnu-ar"
    perl -pi -e 's#"[^"]*/([^/]*-)(ar|as|clang|clang\+\+|ld|nm|objdump|ranlib|llc|opt)"#"$1$2"#g' "${settings_file}"
    log_info "      Stripped absolute tool paths"

    log_info "    ✓ Settings patched for ${target}"
}

# Fix wrapper scripts "./" prefix bug
# GHC bindist Makefile uses 'find . ! -type d' which outputs './ghci' instead of 'ghci'.
# This "./" gets embedded in wrapper scripts:
#   exeprog="./ghci"
#   executablename="/path/to/lib/bin/./ghci"
# causing broken paths like: $libdir/bin/./target-ghci-9.6.7
#
# Parameters:
#   $1 - target triple
#
_cross_fix_wrapper_scripts() {
    local target="$1"

    log_info "    Fixing wrapper scripts..."

    if [[ ! -d "${PREFIX}/bin" ]]; then
        log_info "    WARNING: ${PREFIX}/bin not found, skipping"
        return 0
    fi

    pushd "${PREFIX}/bin" >/dev/null

    local wrappers="ghc ghci ghc-pkg runghc runhaskell haddock hp2ps hsc2hs hpc"

    for wrapper in ${wrappers}; do
        # Fix target-prefixed wrapper
        local target_wrapper="${target}-${wrapper}"
        if [[ -f "${target_wrapper}" ]]; then
            # Fix both exeprog and executablename - both can have "./" prefix
            perl -pi -e 's#^(exeprog=")\./#$1#' "${target_wrapper}"
            perl -pi -e 's#(/bin/)\./#$1#' "${target_wrapper}"
        fi

        # Fix short-name wrapper (may be script or symlink - only fix if script)
        if [[ -f "${wrapper}" ]] && [[ ! -L "${wrapper}" ]]; then
            perl -pi -e 's#^(exeprog=")\./#$1#' "${wrapper}"
            perl -pi -e 's#(/bin/)\./#$1#' "${wrapper}"
        fi
    done

    popd >/dev/null
    log_info "    ✓ Wrapper scripts fixed"
}

# Fix ghci wrapper for cross-compiled GHC
# For cross-compiled GHC, ghci is NOT a separate binary - it's 'ghc --interactive'.
# The bindist install creates a broken wrapper pointing to a non-existent ghci binary.
# Replace it with a simple script that calls ghc --interactive.
#
# Parameters:
#   $1 - target triple
#
_cross_fix_ghci_wrapper() {
    local target="$1"

    log_info "    Fixing ghci wrapper..."

    # Fix target-prefixed ghci wrapper
    local ghci_wrapper="${PREFIX}/bin/${target}-ghci"
    if [[ -f "${ghci_wrapper}" ]]; then
        cat > "${ghci_wrapper}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
        chmod +x "${ghci_wrapper}"
    fi

    # Also fix short-name ghci if it's a script (not symlink)
    local short_ghci="${PREFIX}/bin/ghci"
    if [[ -f "${short_ghci}" ]] && [[ ! -L "${short_ghci}" ]]; then
        cat > "${short_ghci}" << 'GHCI_EOF'
#!/bin/sh
exec "${0%ghci}ghc" --interactive ${1+"$@"}
GHCI_EOF
        chmod +x "${short_ghci}"
    fi

    log_info "    ✓ ghci wrapper fixed"
}

# Create symlinks for cross-compiled GHC tools
# Creates the chain: versioned → unversioned → short name
# Example: aarch64-conda-linux-gnu-ghc-9.6.7 → aarch64-conda-linux-gnu-ghc → ghc
#
# Also handles library directory naming (target-prefixed → standard)
#
# Parameters:
#   $1 - target triple
#
_cross_create_symlinks() {
    local target="$1"

    log_info "    Creating symlinks for cross-compiled tools..."

    if [[ ! -d "${PREFIX}/bin" ]]; then
        log_info "    WARNING: ${PREFIX}/bin not found, skipping"
        return 0
    fi

    pushd "${PREFIX}/bin" >/dev/null

    # Standard GHC tools that need symlinks
    local tools="ghc ghci ghc-pkg hp2ps hsc2hs haddock hpc runghc"

    for bin in ${tools}; do
        local versioned="${target}-${bin}-${PKG_VERSION}"
        local unversioned="${target}-${bin}"

        # Create unversioned → versioned symlink if versioned exists
        if [[ -f "${versioned}" ]] && [[ ! -e "${unversioned}" ]]; then
            ln -sf "${versioned}" "${unversioned}"
        fi

        # Create short name → unversioned/versioned symlink
        if [[ -e "${unversioned}" ]] && [[ ! -e "${bin}" ]]; then
            ln -sf "${unversioned}" "${bin}"
        elif [[ -f "${versioned}" ]] && [[ ! -e "${bin}" ]]; then
            ln -sf "${versioned}" "${bin}"
        fi
    done

    popd >/dev/null

    # Create directory symlink for libraries
    # Cross-compile installs to target-prefixed directory, create standard symlink
    local target_lib_dir="${PREFIX}/lib/${target}-ghc-${PKG_VERSION}"
    local standard_lib_dir="${PREFIX}/lib/ghc-${PKG_VERSION}"

    if [[ -d "${target_lib_dir}" ]] && [[ ! -d "${standard_lib_dir}" ]]; then
        mv "${target_lib_dir}" "${standard_lib_dir}"
        ln -sf "${standard_lib_dir}" "${target_lib_dir}"
        log_info "      Renamed lib dir: ${target}-ghc-${PKG_VERSION} → ghc-${PKG_VERSION}"
    fi

    log_info "    ✓ Symlinks created"
}

# Helper: Find the installed settings file
# Cross-compile may install to different locations
_get_installed_settings_file() {
    local settings_file="${PREFIX}/lib/ghc-${PKG_VERSION}/lib/settings"

    # Check standard location first
    if [[ -f "${settings_file}" ]]; then
        echo "${settings_file}"
        return 0
    fi

    # Cross-compile: Check target-prefixed location
    if is_cross_compile; then
        local target="${conda_target:-${TARGET}}"
        local cross_settings="${PREFIX}/lib/${target}-ghc-${PKG_VERSION}/lib/settings"
        if [[ -f "${cross_settings}" ]]; then
            echo "${cross_settings}"
            return 0
        fi
    fi

    # Search for it
    local found
    found=$(find "${PREFIX}/lib" -name "settings" -path "*/ghc-${PKG_VERSION}/*" 2>/dev/null | head -1)
    if [[ -n "${found}" ]]; then
        echo "${found}"
        return 0
    fi

    # Return default path (caller will check if exists)
    echo "${settings_file}"
}

#=============================================================================
# COMMON INSTALLATION HELPERS
#=============================================================================

_install_bash_completion() {
    log_info "  Installing bash completion..."

    mkdir -p "${PREFIX}/etc/bash_completion.d"

    if [[ -f "${SRC_DIR}/utils/completion/ghc.bash" ]]; then
        cp "${SRC_DIR}/utils/completion/ghc.bash" \
           "${PREFIX}/etc/bash_completion.d/ghc"
        log_info "  ✓ Bash completion installed"
    else
        log_info "  ! Bash completion source not found (skipped)"
    fi
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
        return 0
    fi

    # Unix: Check GHC binary and settings
    local ghc_bin="${PREFIX}/bin/ghc"
    local settings_file
    settings_file=$(_get_installed_settings_file)

    # Check GHC exists
    if [[ ! -x "${ghc_bin}" ]]; then
        # Cross-compile: Check if short symlink was created
        if is_cross_compile; then
            local target="${conda_target:-${TARGET}}"
            local target_ghc="${PREFIX}/bin/${target}-ghc"
            if [[ -x "${target_ghc}" ]]; then
                ghc_bin="${target_ghc}"
                log_info "  Using target-prefixed GHC: ${ghc_bin}"
            fi
        fi
    fi

    if [[ ! -x "${ghc_bin}" ]]; then
        log_info "  ERROR: GHC not found at ${ghc_bin}"
        log_info "  Searching for GHC binary..."
        find "${PREFIX}/bin" -name "*ghc*" -type f 2>/dev/null | head -10 || true
        die "GHC not found at expected location"
    fi

    # Check settings file
    if [[ ! -f "${settings_file}" ]]; then
        log_info "  WARNING: Settings file not found at ${settings_file}"
        log_info "  Searching for settings file..."
        find "${PREFIX}" -name "settings" -type f 2>/dev/null | head -10 || true
        die "Settings file not found"
    fi

    # For cross-compile, the binary may not run on build host
    if is_cross_compile; then
        log_info "  Cross-compiled GHC binary exists: ${ghc_bin}"
        log_info "  Settings file exists: ${settings_file}"
        log_info "  (Cannot run version check - binary is for target platform)"
    else
        log_info "  GHC version: $(${ghc_bin} --version)"
    fi
}
