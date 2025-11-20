#!/usr/bin/env bash
# ============================================================
# STANDARDIZED GHC BUILD SCRIPT - Linux Cross-Compilation
# ============================================================
# Version: 1.0
# GHC Version: 9.10.2
# Targets: aarch64-unknown-linux-gnu, powerpc64le-unknown-linux-gnu
# Last updated: 2025-11-13
#
# DESIGN PRINCIPLES:
# 1. Use lib module functions for consistency
# 2. Explicit Hadrian binary with BUILD machine toolchain
# 3. Clear separation: BUILD vs TARGET architecture
# 4. PowerPC64LE ABI v2 handling throughout
# 5. Race condition prevention
# 6. Comprehensive documentation
# ============================================================

set -eu

# Initialize logging index
_log_index=0

# Set up error trap to capture unexpected failures
trap 'echo "ERROR: Script failed at line $LINENO with exit code $?" >&2; exit 1' ERR

# Source common functions
source "${RECIPE_DIR}"/building/common.sh

# ============================================================
# ARCHITECTURE CALCULATION
# ============================================================
# Calculate BUILD and TARGET architecture triples
# Using target_platform for consistency
# ============================================================

# Save original conda aliases BEFORE overriding
# (conda-build sets these, but GHC configure needs different values)
original_build_alias="${build_alias}"
original_host_alias="${host_alias}"

# Extract architecture from conda aliases
conda_host="${original_build_alias}"      # e.g., x86_64-conda-linux-gnu (BUILD)
conda_target="${original_host_alias}"     # e.g., aarch64-conda-linux-gnu (TARGET)
host_arch="${original_build_alias%%-*}"   # e.g., x86_64 (BUILD)
target_arch="${original_host_alias%%-*}"  # e.g., aarch64 (TARGET)

# Convert to GHC triple format
ghc_host="${host_arch}-unknown-linux-gnu"       # BUILD triple for GHC
ghc_target="${target_arch}-unknown-linux-gnu"   # TARGET triple for GHC

echo "=== Cross-Compilation Architecture ==="
echo "  BUILD (host):    ${conda_host} -> ${ghc_host}"
echo "  TARGET (target): ${conda_target} -> ${ghc_target}"
echo "  Target platform: ${target_platform}"
echo "======================================="

# Override autoconf variables for GHC configure
# GHC's cross-compilation uses: --build=<host> --host=<host> --target=<target>
# NOTE: conda_host and conda_target still reference the ORIGINAL values
export build_alias="${ghc_host}"
export host_alias="${ghc_host}"

# ============================================================
# BOOTSTRAP ENVIRONMENT SETUP
# ============================================================
# Create conda environment with BUILD machine GHC and cabal
# This GHC runs on x86_64 and will compile Hadrian
# ============================================================

echo "=== Creating bootstrap environment ==="
setup_cross_build_env "linux-64" "libc2.17_env" "sysroot_linux-64==2.17"

# Verify bootstrap GHC works
echo "  Bootstrap GHC: ${GHC}"
"${GHC}" --version

# Create debug log directory
mkdir -p "${SRC_DIR}/_debug_logs"
DEBUG_LOG="${SRC_DIR}/_debug_logs/environment-check.log"

# Save environment variables to log file AND stdout
{
  echo "=== DEBUG: Environment Variables ==="
  echo "  Date: $(date)"
  echo "  PWD: $(pwd)"
  echo "  PREFIX=${PREFIX:-UNSET}"
  echo "  BUILD_PREFIX=${BUILD_PREFIX:-UNSET}"
  echo "  SRC_DIR=${SRC_DIR:-UNSET}"
  echo "  target_platform=${target_platform:-UNSET}"
  echo "  target_arch=${target_arch:-UNSET}"
  echo "  ghc_target=${ghc_target:-UNSET}"
  echo "  ghc_host=${ghc_host:-UNSET}"
  echo "  conda_target=${conda_target:-UNSET}"
  echo "  conda_host=${conda_host:-UNSET}"
  echo "  build_alias=${build_alias:-UNSET}"
  echo "  host_alias=${host_alias:-UNSET}"
  echo "=================================="
} | tee "${DEBUG_LOG}"

# ============================================================
# POWERPC64LE ABI V2 CONFIGURATION
# ============================================================
# PowerPC 64-bit little-endian requires ABI v2 (not v1)
# Must inject -mabi=elfv2 and architecture macros BEFORE configure
# ============================================================

if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
  echo "=== PowerPC64LE detected: Configuring ABI v2 ==="

  # Add ABI and architecture macros to CFLAGS/CXXFLAGS
  # These get baked into GHC's settings file during configure
  export CFLAGS="${CFLAGS:-} -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"
  export CXXFLAGS="${CXXFLAGS:-} -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"

  echo "  Added to CFLAGS: -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"
  echo "  Added to CXXFLAGS: -mabi=elfv2 -Dpowerpc64le_HOST_ARCH -Dlinux_HOST_OS"
fi

# ============================================================
# GHC CONFIGURE
# ============================================================
# Configure GHC for cross-compilation
# --target specifies the TARGET architecture
# ============================================================

# System triple configuration
SYSTEM_CONFIG=(
  --target="${ghc_target}"
  --prefix="${PREFIX}"
)

# Library paths and autoconf variables
declare -a CONFIGURE_ARGS

# Build configure arguments using Bash 3.2 compatible method
# Function now prints arguments to stdout, we capture them into array
DEBUG_CONFIGURE_LOG="${SRC_DIR}/_debug_logs/configure-args.log"
{
  echo "=== DEBUG: Calling build_configure_args ==="
  echo "  Date: $(date)"
  echo "  Using Bash 3.2 compatible array capture method"
} | tee "${DEBUG_CONFIGURE_LOG}"

# Capture function output into array (stderr goes to debug log)
declare -a CONFIGURE_ARGS
while IFS= read -r arg; do
  CONFIGURE_ARGS+=("$arg")
done < <(build_configure_args 2>> "${DEBUG_CONFIGURE_LOG}")

{
  echo "DEBUG: build_configure_args succeeded - ${#CONFIGURE_ARGS[@]} elements"
  if [[ ${#CONFIGURE_ARGS[@]} -gt 0 ]]; then
    echo "DEBUG: First few args: ${CONFIGURE_ARGS[@]:0:3}"
  fi
  echo "=================================="
} | tee -a "${DEBUG_CONFIGURE_LOG}"

# Add cross-compilation specific autoconf variables
# These point to TARGET architecture toolchain
CONFIGURE_ARGS+=(
  ac_cv_path_AR="${BUILD_PREFIX}/bin/${conda_target}-ar"
  ac_cv_path_AS="${BUILD_PREFIX}/bin/${conda_target}-as"
  ac_cv_path_CC="${BUILD_PREFIX}/bin/${conda_target}-clang"
  ac_cv_path_CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"
  ac_cv_path_LD="${BUILD_PREFIX}/bin/${conda_target}-ld"
  ac_cv_path_NM="${BUILD_PREFIX}/bin/${conda_target}-nm"
  ac_cv_path_OBJDUMP="${BUILD_PREFIX}/bin/${conda_target}-objdump"
  ac_cv_path_RANLIB="${BUILD_PREFIX}/bin/${conda_target}-ranlib"
  ac_cv_path_LLC="${BUILD_PREFIX}/bin/${conda_target}-llc"
  ac_cv_path_OPT="${BUILD_PREFIX}/bin/${conda_target}-opt"

  LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
)

# Set autoconf variables for GLIBC 2.17 compatibility
echo "DEBUG: About to call set_autoconf_toolchain_vars with conda_target='${conda_target}'" | tee -a "${DEBUG_CONFIGURE_LOG}"
set_autoconf_toolchain_vars "${conda_target}" "false" 2>> "${SRC_DIR}/_debug_logs/set_autoconf.log"
echo "DEBUG: set_autoconf_toolchain_vars completed successfully" | tee -a "${DEBUG_CONFIGURE_LOG}"

echo "DEBUG: About to run configure" | tee -a "${DEBUG_CONFIGURE_LOG}"
run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }
echo "DEBUG: configure completed" | tee -a "${DEBUG_CONFIGURE_LOG}"

# ============================================================
# POWERPC64LE: HADRIAN CONFIG PATCHING
# ============================================================
# Patch Hadrian config files to inject ABI and architecture macros
# Only patch TARGET config (default.target), NOT HOST config
# ============================================================

if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
  echo "=== Patching Hadrian config for PowerPC64LE ==="

  for config_file in "${SRC_DIR}"/hadrian/cfg/default.target "${SRC_DIR}"/hadrian/cfg/*.ghc-toolchain; do
    if [[ -f "${config_file}" ]]; then
      echo "  Patching: ${config_file}"
      # Inject macros before -Qunused-arguments in prgFlags
      perl -pi -e 's/"-Qunused-arguments"/"-mabi=elfv2","-Dpowerpc64le_HOST_ARCH","-Dlinux_HOST_OS","-Qunused-arguments"/g' "${config_file}"
    fi
  done
fi

# ============================================================
# HADRIAN SYSTEM.CONFIG UPDATE
# ============================================================
# Update Hadrian's system.config with TARGET toolchain
# ============================================================

update_hadrian_system_config "${conda_target}" "false"

# ============================================================
# BUILD HADRIAN (WITH BUILD MACHINE TOOLCHAIN)
# ============================================================
# CRITICAL: Hadrian runs on BUILD machine (x86_64), not TARGET
# Must use BUILD machine compilers and CFLAGS
# ============================================================

# Stage 0 tools (BUILD machine)
export AR_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ar"
export CC_STAGE0="${CC_FOR_BUILD}"
export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

# Override CFLAGS/LDFLAGS for Hadrian build (BUILD machine, not TARGET)
build_cflags="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem ${PREFIX}/include -fdebug-prefix-map=${SRC_DIR}=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=${PREFIX}=/usr/local/src/conda-prefix"
build_ldflags="-L${CROSS_ENV_PATH}/${conda_host}/lib -L${CROSS_ENV_PATH}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"

echo "=== Building Hadrian with BUILD machine toolchain ==="
build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}" "${build_cflags}" "${build_ldflags}"

# Use the built Hadrian binary
_hadrian_build=("${HADRIAN_BIN}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ============================================================
# BUILD CONFIGURATION
# ============================================================

# Set Hadrian flavour
# Stage 1: Use quickest (builds cross-compiler quickly)
# Stage 2: Use release (optimized TARGET binaries)
HADRIAN_FLAVOUR_STAGE1="quickest"
HADRIAN_FLAVOUR_STAGE2="release"

echo "=== Build Configuration ==="
echo "  GHC Version: ${PKG_VERSION}"
echo "  Stage 1 Flavour: ${HADRIAN_FLAVOUR_STAGE1}"
echo "  Stage 2 Flavour: ${HADRIAN_FLAVOUR_STAGE2}"
echo "  Hadrian Binary: ${HADRIAN_BIN}"
echo "  CPU Count: ${CPU_COUNT}"
echo "=========================="

# ============================================================
# STAGE 1: CROSS-COMPILER
# ============================================================
# Build GHC cross-compiler that runs on x86_64 and targets aarch64/ppc64le
# Disable cross-compile copy optimization to force building the cross binary
# ============================================================

echo "=== Building Stage 1 Cross-Compiler ==="

# Disable copy optimization in Hadrian (force cross-compiler build)
perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs

# ============================================================
# RACE CONDITION PREVENTION
# Build tools explicitly in correct order
# ============================================================
echo "  Building cross-compiler tools (race condition prevention)"
run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR_STAGE1}" --docs=none --progress-info=none
run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour="${HADRIAN_FLAVOUR_STAGE1}" --docs=none --progress-info=none
run_and_log "stage1_hsc2hs"  "${_hadrian_build[@]}" stage1:exe:hsc2hs  --flavour="${HADRIAN_FLAVOUR_STAGE1}" --docs=none --progress-info=none
# ============================================================

# Patch settings file for cross-compilation
settings_file="${SRC_DIR}/_build/stage0/lib/settings"
update_linux_link_flags "${settings_file}"

echo "=== Stage 0 settings after patching ==="
grep -E "C compiler|C\+\+ compiler|Haskell CPP" "${settings_file}" || true

# Build stage 1 libraries
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour="${HADRIAN_FLAVOUR_STAGE1}" --docs=none --progress-info=none

# Patch settings again after library build
update_linux_link_flags "${settings_file}"

# ============================================================
# POWERPC64LE: GHCPLATFORM.H PATCHING
# ============================================================
# CRITICAL: Patch ghcplatform.h AFTER RTS configure
# GHC's configure only defines powerpc64_HOST_ARCH (generic)
# StgCRunAsm.S requires powerpc64le_HOST_ARCH (little-endian specific)
# ============================================================

if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
  echo "=== Patching ghcplatform.h for PowerPC64LE ==="

  ghcplatform_stage1="${SRC_DIR}/_build/stage1/rts/build/include/ghcplatform.h"

  if [[ -f "${ghcplatform_stage1}" ]]; then
    # Check if already patched
    if grep -q "^#define powerpc64le_HOST_ARCH" "${ghcplatform_stage1}"; then
      echo "  Already patched: powerpc64le_HOST_ARCH macro present"
    else
      perl -pi -e 's/(#define powerpc64_HOST_ARCH\s+1)/$1\n#define powerpc64le_HOST_ARCH  1/' "${ghcplatform_stage1}"
      echo "  Successfully patched: ${ghcplatform_stage1}"

      # Verify the patch
      if grep -q "^#define powerpc64le_HOST_ARCH" "${ghcplatform_stage1}"; then
        echo "  Verification: powerpc64le_HOST_ARCH macro confirmed"
      else
        echo "  WARNING: Patch verification failed!"
      fi
    fi
  else
    echo "  ERROR: ${ghcplatform_stage1} not found after stage1:lib:ghc build!"
    exit 1
  fi
fi

# ============================================================
# STAGE 2: TARGET BINARIES
# ============================================================
# Build final GHC binaries that run on TARGET architecture
# Uses the stage 1 cross-compiler built above
# ============================================================

echo "=== Building Stage 2 Target Binaries ==="

# Use stage 1 cross-compiler
export GHC="${SRC_DIR}/_build/ghc-stage1"

echo "  Using cross-compiler: ${GHC}"
cat "${settings_file}"

# ============================================================
# RACE CONDITION PREVENTION
# Build tools explicitly in correct order
# ============================================================
echo "  Building target binaries (race condition prevention)"
run_and_log "stage2_ghc-bin" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour="${HADRIAN_FLAVOUR_STAGE2}" --docs=none --progress-info=none
run_and_log "stage2_ghc-pkg" "${_hadrian_build[@]}" stage2:exe:ghc-pkg --flavour="${HADRIAN_FLAVOUR_STAGE2}" --docs=none --progress-info=none
run_and_log "stage2_hsc2hs"  "${_hadrian_build[@]}" stage2:exe:hsc2hs  --flavour="${HADRIAN_FLAVOUR_STAGE2}" --docs=none --progress-info=none
# ============================================================

# ============================================================
# BINARY DISTRIBUTION
# ============================================================
# Create and install binary distribution
# Cross-compiled libraries cannot be tested, so we use binary-dist
# ============================================================

echo "=== Creating Binary Distribution ==="
run_and_log "bindist" "${_hadrian_build[@]}" binary-dist \
  --prefix="${PREFIX}" \
  --flavour="${HADRIAN_FLAVOUR_STAGE2}" \
  --freeze1 \
  --freeze2 \
  --docs=none \
  --progress-info=none

# ============================================================
# BINARY DISTRIBUTION INSTALLATION
# ============================================================
# Configure and install from binary distribution
# ============================================================

bindist_dir=$(find "${SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)

if [[ -z "${bindist_dir}" ]]; then
  echo "ERROR: Could not find binary distribution directory"
  echo "Expected: ${SRC_DIR}/_build/bindist/ghc-${PKG_VERSION}-${ghc_target}"
  exit 1
fi

echo "=== Installing Binary Distribution ==="
echo "  Distribution: ${bindist_dir}"

pushd "${bindist_dir}"
  # CRITICAL: Completely reset environment for BUILD machine configuration
  # The bindist configure must run with BUILD machine (x86_64) tools and flags,
  # not TARGET architecture (aarch64/ppc64le) tools and flags.

  # Unset all TARGET architecture autoconf cache variables
  # Both ac_cv_path_* (tool paths) and ac_cv_prog_* (tool program names)
  unset ac_cv_path_AR ac_cv_path_AS ac_cv_path_CC ac_cv_path_CXX
  unset ac_cv_path_LD ac_cv_path_NM ac_cv_path_OBJDUMP ac_cv_path_RANLIB
  unset ac_cv_path_LLC ac_cv_path_OPT
  unset ac_cv_prog_AR ac_cv_prog_AS ac_cv_prog_CC ac_cv_prog_CXX
  unset ac_cv_prog_LD ac_cv_prog_NM ac_cv_prog_OBJDUMP ac_cv_prog_RANLIB
  unset ac_cv_prog_LLC ac_cv_prog_OPT

  # CRITICAL: Also unset target-prefixed tool cache variables
  # Autoconf creates these when --target is specified (e.g., ac_cv_prog_aarch64_unknown_linux_gnu_LD)
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_AR
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_AS
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_CC
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_CXX
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_LD
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_NM
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_OBJDUMP
  unset ac_cv_prog_${target_arch}_unknown_linux_gnu_RANLIB

  unset ac_cv_func_statx ac_cv_have_decl_statx ac_cv_lib_ffi_ffi_call
  unset ac_cv_func_posix_spawn_file_actions_addchdir_np

  # CRITICAL: Also unset environment-based autoconf cache (ac_cv_env_*)
  # These are cached from the environment variables at configure time
  unset CFLAGS CXXFLAGS  # Will trigger unset of ac_cv_env_CFLAGS_value, ac_cv_env_CXXFLAGS_value

  # Set BUILD machine compiler, linker, and all tools
  # These MUST be set to prevent configure from looking for target-prefixed tools
  export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export AR="${BUILD_PREFIX}/bin/${conda_host}-ar"
  export NM="${BUILD_PREFIX}/bin/${conda_host}-nm"
  export RANLIB="${BUILD_PREFIX}/bin/${conda_host}-ranlib"
  export STRIP="${BUILD_PREFIX}/bin/${conda_host}-strip"
  export OBJDUMP="${BUILD_PREFIX}/bin/${conda_host}-objdump"
  export AS="${BUILD_PREFIX}/bin/${conda_host}-as"

  # CRITICAL: Also set MergeObjsCmd to prevent configure from searching for $target_alias-ld
  # When ld.gold merge test runs, if it fails or ld is broken, configure looks for
  # "$target_alias-ld" which would be aarch64-conda-linux-gnu-ld (wrong!)
  # Setting MergeObjsCmd explicitly prevents this fallback search
  export MergeObjsCmd="${BUILD_PREFIX}/bin/${conda_host}-ld"

  # Provide minimal BUILD machine library paths (not target-specific flags like -march)
  export CFLAGS=""  # Explicitly empty - no target-specific optimization flags
  export CXXFLAGS=""  # Explicitly empty
  export LDFLAGS="-L${BUILD_PREFIX}/lib"
  export CPPFLAGS="-I${BUILD_PREFIX}/include"

  echo "  Cleared autoconf cache variables and compiler flags for bindist configure"
  echo "  BUILD machine: ${conda_host}"
  echo "  CC: ${CC}"
  echo "  CXX: ${CXX}"

  # CRITICAL: Bindist configure must use BUILD machine tools, not TARGET tools
  # Explicitly specify --build and --host to prevent autoconf from looking for cross-compiler
  # IMPORTANT: Do NOT pass --target here! The bindist configure is for installation,
  # not for building. Passing --target causes configure to construct target-prefixed
  # tool paths (e.g., aarch64-conda-linux-gnu-ld) even when we've set LD=$BUILD_LD.
  # The installed compiler already knows its target from the build phase.
  ./configure \
    --prefix="${PREFIX}" \
    --build="${ghc_host}" \
    --host="${ghc_host}" \
    || { cat config.log; exit 1; }

  # Install (skip package DB update - cross ghc-pkg doesn't work)
  run_and_log "make_install" make install_bin install_lib install_man
popd

# ============================================================
# POST-INSTALL SETTINGS PATCHING
# ============================================================
# Update installed settings file for TARGET architecture
# ============================================================

settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)

if [[ -z "${settings_file}" ]]; then
  echo "ERROR: Could not find installed settings file"
  exit 1
fi

echo "=== Updating installed settings ==="
echo "  Settings file: ${settings_file}"

# CRITICAL: Tests run under QEMU with TARGET architecture tools
# The settings file must use aarch64 tools because the compiler
# is being tested in a QEMU aarch64 environment

# Fix architecture in toolchain names (x86_64 -> aarch64 for QEMU testing)
perl -pi -e "s#${conda_host}(-[^ \"]*)#${conda_target}\$1#g" "${settings_file}"

# Add library paths with $topdir
perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"

# Fix toolchain prefixes to use target architecture for QEMU environment
perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|opt)\"#\"${conda_target}-\$1\"#" "${settings_file}"

# CRITICAL: Fix target arch field to match actual target architecture
# The settings file incorrectly has "ArchX86_64" even for aarch64/ppc64le cross-compile
# Use case statement to handle architecture name variations
# GHC architecture names from GHC.Platform.ArchOS:
#   - ArchAArch64 (for aarch64)
#   - ArchPPC_64 ELF_V2 (for ppc64le - PowerPC64 Little-Endian uses ELF v2 ABI)
case "${target_arch}" in
  aarch64)
    perl -pi -e 's#"target arch", "[^"]*"#"target arch", "ArchAArch64"#' "${settings_file}"
    ;;
  ppc64le|powerpc64le)
    perl -pi -e 's#"target arch", "[^"]*"#"target arch", "ArchPPC_64 ELF_V2"#' "${settings_file}"
    ;;
  *)
    echo "WARNING: Unknown target architecture for settings fix: ${target_arch}"
    ;;
esac

echo "=== Final settings file ==="
cat "${settings_file}"

# ============================================================
# SYMLINK CREATION
# ============================================================
# Create standard tool names pointing to cross-prefixed versions
# ============================================================

echo "=== Creating standard tool symlinks ==="
pushd "${PREFIX}"/bin
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${ghc_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${ghc_target}-${bin}" "${bin}"
      echo "  Created: ${bin} -> ${ghc_target}-${bin}"
    fi
  done
popd

# ============================================================
# LIBRARY DIRECTORY SYMLINK
# ============================================================
# Create standard lib/ghc-VERSION directory
# ============================================================

if [[ -d "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}" ]]; then
  echo "=== Creating library directory symlink ==="

  # Move to standard location
  mv "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}" "${PREFIX}/lib/ghc-${PKG_VERSION}"

  # Create reverse symlink for compatibility
  ln -sf "${PREFIX}/lib/ghc-${PKG_VERSION}" "${PREFIX}/lib/${ghc_target}-ghc-${PKG_VERSION}"

  echo "  Created: lib/ghc-${PKG_VERSION}"
  echo "  Symlink: lib/${ghc_target}-ghc-${PKG_VERSION} -> lib/ghc-${PKG_VERSION}"
fi

echo "=== Cross-compilation build completed successfully ==="
