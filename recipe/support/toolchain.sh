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
# CONFIGURE BYPASS - PREVENT BROKEN COMPILER SEARCH
#=============================================================================
# GHC 9.6.7 configure has a bug where it doesn't handle conda toolchain triples
# correctly. It expects compilers named ${triple}-gcc but conda provides
# ${conda_triple}-clang. This causes configure to strip prefixes and fail.
#
# ROBUST FIX: Create symlinks for bare compiler names (clang, clang++, etc.)
# pointing to the full prefixed versions. This way, even when configure strips
# prefixes, it still finds the correct compiler.
#
# This bypass will be removed in later GHC versions where the bug is fixed.
#
bypass_configure_compiler_search() {
    log_info "  Bypassing configure compiler search (using ac_cv_path cache variables)"

    # Set autoconf cache variables to full paths
    # This prevents AC_PROG_CC/AC_PROG_CXX from searching for compilers
    # Note: ac_cv_path_ac_pt_* are already set in environment.sh to prevent fallback search

    export ac_cv_path_CC="$(which ${CC})"
    export ac_cv_path_CXX="$(which ${CXX})"
    export ac_cv_prog_CC="${CC}"
    export ac_cv_prog_CXX="${CXX}"

    # Also set the executable check cache variables to prevent testing
    export ac_cv_prog_cc_c89=""
    export ac_cv_prog_cc_c99=""
    export ac_cv_prog_cc_c11=""
    export ac_cv_prog_cc_g=yes
    export ac_cv_prog_cxx_g=yes

    # Toolchain tools
    export ac_cv_path_AR="$(which ${AR})"
    export ac_cv_path_LD="$(which ${LD})"
    export ac_cv_prog_AR="${AR}"
    export ac_cv_prog_LD="${LD}"
    export ac_cv_prog_NM="${NM}"
    export ac_cv_prog_RANLIB="${RANLIB}"
    export ac_cv_prog_STRIP="${STRIP}"

    # Stage0 (bootstrap) toolchain
    export ac_cv_prog_CC_STAGE0="${CC_FOR_BUILD:-${CC}}"
    export ac_cv_prog_LD_STAGE0="${LD_FOR_BUILD:-${LD}}"
    export ac_cv_prog_AR_STAGE0="${AR_FOR_BUILD:-${AR}}"

    if [[ -n "${OBJDUMP:-}" ]]; then
        export ac_cv_prog_OBJDUMP="${OBJDUMP}"
    fi

    log_info "    Set ac_cv_path_CC=$(which ${CC})"
    log_info "    Set ac_cv_path_CXX=$(which ${CXX})"
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

    # Cross-compile only: Port EXACT logic from working feedstock
    # Reference: ghc-feedstock/recipe/lib/settings-patch.sh --linux-cross mode
    if [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]; then
        echo "  Fixing cross-compile toolchain for target architecture..."

        # 1. Python runs on build host (from _patch_fix_python)
        perl -i -pe "s|^(python =).*|\$1 ${BUILD_PREFIX}/bin/python3|" "${system_config}"

        # 2. Add target prefix to ALL toolchain tools (from _patch_toolchain_prefix)
        # This converts bare tool names to target-prefixed versions:
        #   ar    → aarch64-conda-linux-gnu-ar
        #   clang → aarch64-conda-linux-gnu-clang
        #   ld    → aarch64-conda-linux-gnu-ld
        # etc.
        local tools="ar clang clang++ llc nm opt ranlib"
        local pattern=$(echo "${tools}" | tr ' ' '|')
        perl -pi -e "s#(=\\s+)(${pattern})\$#\$1${conda_target}-\$2#" "${system_config}"
        echo "    ✓ Added target prefix to toolchain tools: ${conda_target}-{ar,clang,ld,...}"

        # 3. Add linker flags (from _patch_linker_flags)
        # Note: We still add sysroot for Linux cross-compile, but also add rpath
        perl -pi -e "s#(conf-cc-args-stage[012].*?= )#\$1-Wno-deprecated-non-prototype #" "${system_config}"
        perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${system_config}"
        perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${system_config}"
        perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${system_config}"
        perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${system_config}"

        # Linux-specific: Add target sysroot for Stage 1/2
        if [[ "${target_platform}" == linux-* ]]; then
            local target_sysroot="${BUILD_PREFIX}/${conda_target}/sysroot"
            echo "    ✓ Adding TARGET sysroot to linker args: ${target_sysroot}"
            perl -i -pe 's|^(conf-gcc-linker-args-stage1\s*=\s*)(.*)$|\1--sysroot='"${target_sysroot}"' \2|' "${system_config}"
            perl -i -pe 's|^(conf-gcc-linker-args-stage2\s*=\s*)(.*)$|\1--sysroot='"${target_sysroot}"' \2|' "${system_config}"
            perl -i -pe 's|^(conf-ld-linker-args-stage1\s*=\s*)(.*)$|\1--sysroot='"${target_sysroot}"' \2|' "${system_config}"
            perl -i -pe 's|^(conf-ld-linker-args-stage2\s*=\s*)(.*)$|\1--sysroot='"${target_sysroot}"' \2|' "${system_config}"
        fi

        # 4. Add doc tool placeholders (from _patch_doc_placeholders)
        for tool in xelatex sphinx-build makeindex; do
            if ! grep -qE "^${tool}\\s*=\\s*\\S" "${system_config}"; then
                perl -pi -e "s/^${tool}\\s*=.*/${tool} = \\/bin\\/true/" "${system_config}"
                grep -qE "^${tool}\\s*=\\s*\\S" "${system_config}" || echo "${tool} = /bin/true" >> "${system_config}"
            fi
        done
        echo "    ✓ Added doc tool placeholders (xelatex, sphinx-build, makeindex)"
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
