#!/usr/bin/env bash
# support/toolchain.sh - Minimal, streamlined toolchain configuration
#
# DESIGN PRINCIPLE: Trust configure. It was designed to handle toolchains.
# We only need to:
#   1. Pass the right arguments to configure
#   2. Fix Python path for cross-compile (runs on host)
#   3. Strip BUILD_PREFIX from installed settings (post-install)
#
# See TOOLCHAIN-MINIMAL.md for the full analysis.

set -eu

#=============================================================================
# CORE TOOLCHAIN BUILDER
#=============================================================================
# Builds configure arguments for toolchain. Uses nameref pattern.
#
# CRITICAL: Maps conda-forge variables to GHC's expected names
#   conda-forge: CC_FOR_BUILD, LD_FOR_BUILD, AR_FOR_BUILD
#   GHC expects: CC_STAGE0, LD_STAGE0, AR_STAGE0
#
# See CONFIGURE-MECHANISM.md for the rationale.
#
# Usage:
#   local -a tc_args
#   build_toolchain_args tc_args
#   ./configure "${tc_args[@]}"
#
build_toolchain_args() {
    local -n _args="$1"

    # Explicit platform triple (prevents autodetection from bootstrap GHC)
    _args+=("--build=${BUILD}")
    _args+=("--host=${HOST}")
    _args+=("--target=${TARGET}")

    # Target toolchain (stages 1, 2, 3) - from conda-forge environment
    # DO NOT pass CXXFLAGS/LDFLAGS as arguments - configure picks them up from environment
    _args+=("CC=${CC}")
    _args+=("CXX=${CXX}")
    _args+=("LD=${LD}")
    _args+=("NM=${NM}")
    _args+=("RANLIB=${RANLIB}")

    # OBJDUMP: may not be set on all platforms (e.g., macOS)
    if [[ -n "${OBJDUMP:-}" ]]; then
        _args+=("OBJDUMP=${OBJDUMP}")
    fi

    _args+=("STRIP=${STRIP}")

    # AR: platform-specific
    case "${target_platform}" in
        osx-*)
            # macOS: Apple ld64 requires BSD archive format (llvm-ar)
            _args+=("AR=${BUILD_PREFIX}/bin/llvm-ar")
            ;;
        *)
            # Linux/Windows: use environment AR
            _args+=("AR=${AR}")
            ;;
    esac

    # Bootstrap toolchain (stage 0) - CRITICAL MAPPING
    # Map conda-forge's CC_FOR_BUILD to GHC's CC_STAGE0
    # Fallback to $CC if CC_FOR_BUILD not set (native builds)
    _args+=("CC_STAGE0=${CC_FOR_BUILD:-${CC}}")
    _args+=("LD_STAGE0=${LD_FOR_BUILD:-${LD}}")
    _args+=("AR_STAGE0=${AR_FOR_BUILD:-${AR}}")

    # NO FLAGS - Let configure use environment variables directly
    # Passing them as arguments can cause quoting/escaping issues

    # Platform-specific configure options
    case "${target_platform}" in
        linux-*)
            # glibc 2.17 compatibility (statx added in 2.28)
            _args+=("ac_cv_func_statx=no")
            ;;
        win-64)
            # Use conda toolchain, not bundled MinGW
            _args+=("--enable-distro-toolchain")
            ;;
    esac

    # Cross-compile: tell configure explicitly
    if [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]; then
        _args+=("cross_compiling=yes")
    fi
}

#=============================================================================
# NOTE: Cross-compile support is now integrated into build_toolchain_args()
# The CC_STAGE0/LD_STAGE0/AR_STAGE0 mapping is handled there using
# conda-forge's CC_FOR_BUILD, LD_FOR_BUILD, AR_FOR_BUILD variables.
#=============================================================================

#=============================================================================
# POST-CONFIGURE FIXES
#=============================================================================
# Minimal fixes that configure can't handle.
# Called after ./configure completes.
#
post_configure_fixes() {
    local system_config="${SRC_DIR}/hadrian/cfg/system.config"

    if [[ ! -f "${system_config}" ]]; then
        echo "  WARNING: system.config not found, skipping post-configure"
        return 0
    fi

    # Cross-compile only: Python runs on build host
    if [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]; then
        echo "  Fixing Python path for cross-compile..."
        perl -i -pe "s|^(python =).*|\$1 ${BUILD_PREFIX}/bin/python3|" "${system_config}"
    fi

    # macOS: comprehensive system.config patching (matching modularization branch)
    case "${target_platform}" in
        osx-*)
            echo "  Patching system.config for macOS..."

            # Strip BUILD_PREFIX from tool paths
            perl -i -pe "s|${BUILD_PREFIX}/bin/||g" "${system_config}"

            # Set llvm-ar/llvm-ranlib (Apple ld64 requires BSD archive format)
            local llvm_ar="${BUILD_PREFIX}/bin/llvm-ar"
            local llvm_ranlib="${BUILD_PREFIX}/bin/llvm-ranlib"
            perl -i -pe "s|^(ar\\s*=\\s*).*|\$1${llvm_ar}|" "${system_config}"
            perl -i -pe "s|^(ranlib\\s*=\\s*).*|\$1${llvm_ranlib}|" "${system_config}"
            perl -i -pe "s|(system-ar\\s*=\\s*).*|\$1${llvm_ar}|" "${system_config}"
            perl -i -pe "s|(settings-ar-command\\s*=\\s*).*|\$1llvm-ar|" "${system_config}"

            # Add library paths and rpath to linker args
            perl -i -pe "s|(conf-cc-args-stage[012].*?= )|\$1-Wno-deprecated-non-prototype |" "${system_config}"
            perl -i -pe "s|(conf-gcc-linker-args-stage[12].*?= )|\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib |" "${system_config}"
            perl -i -pe "s|(conf-ld-linker-args-stage[12].*?= )|\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib |" "${system_config}"
            perl -i -pe "s|(settings-c-compiler-link-flags.*?= )|\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib |" "${system_config}"
            perl -i -pe "s|(settings-ld-flags.*?= )|\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib |" "${system_config}"

            # Add doc tool placeholders
            for tool in xelatex sphinx-build makeindex; do
                if ! grep -qE "^${tool}\\s*=\\s*\\S" "${system_config}"; then
                    echo "${tool} = /bin/true" >> "${system_config}"
                fi
            done
            ;;
    esac

    echo "  ✓ Post-configure fixes applied"
}

#=============================================================================
# POST-INSTALL FIXES
#=============================================================================
# Strip BUILD_PREFIX from installed settings.
# The installed GHC must not reference build-time paths.
#
post_install_fixes() {
    local settings_file="${PREFIX}/lib/ghc-${PKG_VERSION}/lib/settings"

    if [[ ! -f "${settings_file}" ]]; then
        echo "  WARNING: Settings file not found: ${settings_file}"
        return 0
    fi

    echo "  Stripping BUILD_PREFIX from installed settings..."

    # Remove absolute BUILD_PREFIX paths (keep just tool names)
    perl -i -pe "s|${BUILD_PREFIX}/bin/||g" "${settings_file}"
    perl -i -pe "s|${BUILD_PREFIX}/||g" "${settings_file}"

    # For cross-compile: also strip PREFIX if it differs from runtime
    if [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]; then
        # The target machine won't have these exact paths
        # Tools should be found via PATH at runtime
        perl -i -pe 's|"/.*/bin/([^"]+)"|"\1"|g' "${settings_file}"
    fi

    echo "  ✓ Post-install fixes applied"
}

#=============================================================================
# HELPER FUNCTIONS
#=============================================================================

is_cross_compile() {
    [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]
}

# Print current toolchain configuration (for debugging)
print_toolchain_config() {
    echo "=== Toolchain Configuration ==="
    echo "  target_platform: ${target_platform}"
    echo "  build_platform:  ${build_platform:-${target_platform}}"
    echo "  is_cross:        $(is_cross_compile && echo yes || echo no)"
    echo "  CC:              ${CC:-<not set>}"
    echo "  AR:              ${AR:-<not set>}"
    echo "  LD:              ${LD:-<not set>}"
    echo "  PREFIX:          ${PREFIX}"
    echo "  BUILD_PREFIX:    ${BUILD_PREFIX}"
    echo "==============================="
}
