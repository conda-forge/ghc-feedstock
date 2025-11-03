
# Function to run a command, log its output, and increment log index
run_and_log() {
  local _logname="$1"
  shift
  local cmd=("$@")

  # Create log directory if it doesn't exist
  mkdir -p "${SRC_DIR}/_logs"

  echo " ";echo "|";echo "|";echo "|";echo "|"
  echo "Running: ${cmd[*]}"
  local start_time=$(date +%s)
  local exit_status_file=$(mktemp)
  # Run the command in a subshell to prevent set -e from terminating
  (
    # Temporarily disable errexit in this subshell
    set +e
    "${cmd[@]}" > "${SRC_DIR}/_logs/${_log_index}_${_logname}.log" 2>&1
    echo $? > "$exit_status_file"
  ) &
  local cmd_pid=$!
  local tail_counter=0

  # Periodically flush and show progress
  while kill -0 $cmd_pid 2>/dev/null; do
    sync
    echo -n "."
    sleep 5
    let "tail_counter += 1"

    if [ $tail_counter -ge 22 ]; then
      echo "."
      tail -5 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
      tail_counter=0
    fi
  done

  wait $cmd_pid || true  # Use || true to prevent set -e from triggering
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local exit_code=$(cat "$exit_status_file")
  rm "$exit_status_file"

  echo "."
  echo "─────────────────────────────────────────"
  printf "Command: %s\n" "${cmd[*]} in ${duration}s"
  echo "Exit code: $exit_code"
  echo "─────────────────────────────────────────"

  # Show more context on failure
  if [[ $exit_code -ne 0 ]]; then
    echo "COMMAND FAILED - Last 50 lines of log:"
    tail -50 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  else
    echo "COMMAND SUCCEEDED - Last 20 lines of log:"
    tail -20 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  fi

  echo "─────────────────────────────────────────"
  echo "Full log: ${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  echo "|";echo "|";echo "|";echo "|"

  let "_log_index += 1"
  return $exit_code
}

# Function to set the conda ar/ranlib for OSX
set_macos_conda_ar_ranlib() {
  local settings_file="$1"
  local toolchain="${2:-x86_64-apple-darwin13.4.0}"

  if [[ -f "$settings_file" ]]; then
    if [[ "$(basename "${settings_file}")" == "default."* ]]; then
      # Use LLVM ar instead of GNU ar for compatibility with Apple ld64
      perl -i -pe 's#(arMkArchive\s*=\s*).*#$1Program {prgPath = "llvm-ar", prgFlags = ["qcs"]}#g' "${settings_file}"
      perl -i -pe 's#((arIsGnu|arSupportsAtFile)\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe 's#(arNeedsRanlib\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe 's#(tgtRanlib\s*=\s*).*#$1Nothing#g' "${settings_file}"
    else
      # Use LLVM ar instead of GNU ar for compatibility with Apple ld64
      perl -i -pe 's#("ar command", ")[^"]*#$1llvm-ar#g' "${settings_file}"
      perl -i -pe 's#("ar flags", ")[^"]*#$1qcs#g' "${settings_file}"
      perl -i -pe "s#(\"(clang|llc|opt|ranlib) command\", \")[^\"]*#\$1${toolchain}-\$2#g" "${settings_file}"
    fi
  else
    echo "Error: $settings_file not found!"
    exit 1
  fi
}

update_settings_link_flags() {
  local settings_file="$1"
  local toolchain="${2:-$CONDA_TOOLCHAIN_HOST}"
  local prefix="${3:-$PREFIX}"

  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"

    # PowerPC 64-bit little-endian: Must use ABI v2 (not v1 which has .opd sections)
    if [[ "${TARGET_ARCH:-${target_arch:-}}" == *"ppc64le"* || "${TARGET_ARCH:-${target_arch:-}}" == *"powerpc64le"* || "${host_alias}" == *"ppc64le"* || "${target_platform}" == *"ppc64le"* ]]; then
      perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -v -mabi=elfv2#' "${settings_file}"
      perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -v -mabi=elfv2#' "${settings_file}"
    fi

    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${prefix}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${prefix}/lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${prefix}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${prefix}/lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    # Don't add -fuse-ld=lld during build (bootstrap compiler doesn't support it)
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-arm64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    # Don't add -fuse-ld=lld during build (bootstrap compiler doesn't support it)
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fuse-ld=lld -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
  fi
  
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${settings_file}"
}

update_installed_settings() {
  local toolchain="${1:-$CONDA_TOOLCHAIN_HOST}"
  
  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-rpath,\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \")#\$1-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -rpath \\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-"* ]]; then
    perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"
    perl -i -pe "s#(C\\+\\+ compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -fuse-ld=lld -fno-lto -fno-use-linker-plugin -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib -liconv -Wl,-L\\\$topdir/../lib -Wl,-rpath,\\\$topdir/../lib -liconv_compat#" "${settings_file}"
  fi
  
  perl -pi -e "s#(-Wl,-L${BUILD_PREFIX}/lib|-Wl,-L${PREFIX}/lib|-Wl,-rpath,${BUILD_PREFIX}/lib|-Wl,-rpath,${PREFIX}/lib)##g" "${settings_file}"
  perl -pi -e "s#(-L${BUILD_PREFIX}/lib|-L${PREFIX}/lib|-rpath ${PREFIX}/lib|-rpath ${BUILD_PREFIX}/lib)##g" "${settings_file}"

  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${settings_file}"
}

update_linux_link_flags() {
  local settings_file="$1"

  # Base compiler flags for all Linux platforms
  perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"

  # PowerPC 64-bit little-endian: Must use ABI v2 (not v1 which has .opd sections)
  # The -mabi=elfv2 flag explicitly tells the compiler to use ELF v2 ABI
  # This prevents "error: .opd not allowed in ABI version 2" linker errors
  if [[ "${TARGET_ARCH:-${target_arch:-}}" == *"ppc64le"* || "${TARGET_ARCH:-${target_arch:-}}" == *"powerpc64le"* || "${host_alias}" == *"ppc64le"* || "${target_platform}" == *"ppc64le"* ]]; then
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -mabi=elfv2#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -mabi=elfv2#' "${settings_file}"
  fi

  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${PREFIX}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${CONDA_TOOLCHAIN_HOST}-\$1\"#" "${settings_file}"
}

update_osx_link_flags() {
  local settings_file="$1"

  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${PREFIX}/lib -Wl,-liconv -Wl,-L${PREFIX}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${PREFIX}/lib -liconv -L${PREFIX}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
}

################################################################################
# SHARED FUNCTIONS FOR BUILD SCRIPT CONSOLIDATION
#
# These functions consolidate common patterns across platform-specific build
# scripts to improve maintainability and consistency.
################################################################################

# ==============================================================================
# AUTOCONF VARIABLE MANAGEMENT
# ==============================================================================

# Set autoconf cache variables for GHC configure and sub-library configures
#
# CRITICAL: These variables MUST be exported globally (not in CONFIGURE_ARGS)
# because sub-library configure scripts (unix, time, directory, process, base)
# check the environment for ac_cv_* variables DURING the build.
#
# Reference: CLAUDE.md "CRITICAL #2: statx() System Call - GLIBC 2.17 Incompatibility"
#
# Autoconf variable patterns explained:
#   ac_cv_prog_XXX        - Set by AC_PROG_XXX (searches PATH)
#   ac_cv_path_XXX        - Set by AC_PATH_PROG (needs absolute path)
#   ac_cv_path_ac_pt_XXX  - Set by AC_PATH_TOOL (cross-compilation fallback)
#
# GHC's configure uses multiple detection methods, so we set all patterns
# to ensure tools are found regardless of which autoconf macro is used.
#
# Usage:
#   set_autoconf_toolchain_vars "aarch64-conda-linux-gnu"
#
# Parameters:
#   $1 - target_prefix: Tool prefix for target architecture (e.g., "aarch64-conda-linux-gnu")
#   $2 - debug: Set to "true" to print all exported variables (default: "false")
#
set_autoconf_toolchain_vars() {
  local target_prefix="$1"
  local debug="${2:-false}"

  if [[ -z "$target_prefix" ]]; then
    echo "ERROR: set_autoconf_toolchain_vars requires target_prefix argument"
    return 1
  fi

  [[ "$debug" == "true" ]] && echo "=== Setting autoconf toolchain variables for: ${target_prefix}"

  # Core build tools - set ALL patterns for maximum compatibility
  # Using indirect variable expansion to get values of AR, CC, etc.
  for tool in AR AS CC CXX LD NM OBJDUMP RANLIB; do
    local tool_value="${!tool}"  # Indirect expansion: get value of $AR, $CC, etc.

    if [[ -n "$tool_value" ]]; then
      export ac_cv_prog_${tool}="${tool_value}"
      export ac_cv_path_${tool}="${tool_value}"
      export ac_cv_path_ac_pt_${tool}="${tool_value}"

      [[ "$debug" == "true" ]] && echo "  ac_cv_prog_${tool}=${tool_value}"
    fi
  done

  # LLVM tools (different naming convention)
  export ac_cv_prog_LLC="${target_prefix}-llc"
  export ac_cv_prog_OPT="${target_prefix}-opt"
  export ac_cv_prog_ac_ct_LLC="${target_prefix}-llc"
  export ac_cv_prog_ac_ct_OPT="${target_prefix}-opt"

  [[ "$debug" == "true" ]] && echo "  ac_cv_prog_LLC=${target_prefix}-llc"
  [[ "$debug" == "true" ]] && echo "  ac_cv_prog_OPT=${target_prefix}-opt"

  # CRITICAL: glibc 2.17 compatibility
  # statx() was added in glibc 2.28, but conda uses 2.17
  # Reference: CLAUDE.md "CRITICAL #2"
  export ac_cv_func_statx=no
  export ac_cv_have_decl_statx=no

  [[ "$debug" == "true" ]] && echo "  ac_cv_func_statx=no (glibc 2.17 compatibility)"

  # libffi detection (often fails even when present)
  export ac_cv_lib_ffi_ffi_call=yes

  [[ "$debug" == "true" ]] && echo "  ac_cv_lib_ffi_ffi_call=yes"
  [[ "$debug" == "true" ]] && echo "=== Autoconf variables set successfully"
}

# Set macOS-specific autoconf variables
#
# macOS has different tool availability and naming conventions.
# This function handles the platform-specific quirks.
#
# Usage:
#   set_autoconf_macos_vars
#
# Parameters:
#   $1 - debug: Set to "true" to print all exported variables (default: "false")
#
set_autoconf_macos_vars() {
  local debug="${1:-false}"

  [[ "$debug" == "true" ]] && echo "=== Setting macOS-specific autoconf variables"

  # Prevent autoconf from finding tools without explicit paths
  # This forces use of our conda-provided toolchain
  export ac_cv_path_ac_pt_CC=""
  export ac_cv_path_ac_pt_CXX=""

  # Explicitly set tool paths from environment
  export ac_cv_prog_AR="${AR}"
  export ac_cv_prog_CC="${CC}"
  export ac_cv_prog_CXX="${CXX}"
  export ac_cv_prog_LD="${LD}"
  export ac_cv_prog_RANLIB="${RANLIB}"

  # Also set path variants (macOS configure checks both)
  export ac_cv_path_AR="${AR}"
  export ac_cv_path_CC="${CC}"
  export ac_cv_path_CXX="${CXX}"
  export ac_cv_path_LD="${LD}"
  export ac_cv_path_RANLIB="${RANLIB}"

  # libffi detection
  export ac_cv_lib_ffi_ffi_call=yes

  [[ "$debug" == "true" ]] && echo "  ac_cv_prog_CC=${CC}"
  [[ "$debug" == "true" ]] && echo "  ac_cv_path_ac_pt_CC=<empty> (force conda toolchain)"
  [[ "$debug" == "true" ]] && echo "=== macOS autoconf variables set"
}

# ==============================================================================
# CONFIGURE ARGUMENTS BUILDERS
# ==============================================================================

# Build standard GHC configure arguments (--with-* flags)
#
# All platforms use the same set of --with-* flags to specify library locations.
# This function populates an array with these standard arguments.
#
# Usage:
#   declare -a CONFIGURE_ARGS
#   build_configure_args CONFIGURE_ARGS
#   ./configure "${CONFIGURE_ARGS[@]}"
#
# Parameters:
#   $1 - Name of array variable to populate (passed by reference)
#   $2 - extra_ldflags: Additional LDFLAGS to append (optional)
#
build_configure_args() {
  local -n result_array=$1  # nameref: allows modifying caller's array
  local extra_ldflags="${2:-}"

  result_array=(
    --with-system-libffi=yes
    --with-curses-includes="${PREFIX}/include"
    --with-curses-libraries="${PREFIX}/lib"
    --with-ffi-includes="${PREFIX}/include"
    --with-ffi-libraries="${PREFIX}/lib"
    --with-gmp-includes="${PREFIX}/include"
    --with-gmp-libraries="${PREFIX}/lib"
    --with-iconv-includes="${PREFIX}/include"
    --with-iconv-libraries="${PREFIX}/lib"
  )

  # Platform-specific additions
  if [[ "${target_platform}" == linux-* ]]; then
    result_array+=(--disable-numa)
  fi

  # Optional LDFLAGS
  if [[ -n "$extra_ldflags" ]]; then
    result_array+=(LDFLAGS="${extra_ldflags}")
  fi
}

# Build system configuration arguments (--build, --host, --target)
#
# Configure requires --build, --host, --target for cross-compilation.
# This function generates the appropriate flags based on provided triples.
#
# Usage:
#   declare -a SYSTEM_CONFIG
#   build_system_config SYSTEM_CONFIG "x86_64-unknown-linux-gnu" "" "aarch64-unknown-linux-gnu"
#   ./configure "${SYSTEM_CONFIG[@]}"
#
# Parameters:
#   $1 - Name of array variable to populate (passed by reference)
#   $2 - build_triple: Build machine triple (empty = omit)
#   $3 - host_triple: Host machine triple (empty = omit)
#   $4 - target_triple: Target machine triple (empty = omit)
#
build_system_config() {
  local -n result_array=$1
  local build_triple="$2"
  local host_triple="$3"
  local target_triple="$4"

  result_array=(--prefix="${PREFIX}")

  [[ -n "$build_triple" ]] && result_array+=(--build="$build_triple")
  [[ -n "$host_triple" ]] && result_array+=(--host="$host_triple")
  [[ -n "$target_triple" ]] && result_array+=(--target="$target_triple")
}

# ==============================================================================
# ARCHITECTURE CALCULATION
# ==============================================================================

# Calculate and export architecture variables for GHC build
#
# GHC uses different architecture naming conventions than conda.
# This function standardizes the calculation and exports all needed variables.
#
# Sets these global variables:
#   CONDA_HOST, CONDA_TARGET     - Conda architecture strings
#   HOST_ARCH, TARGET_ARCH       - Architecture prefixes (x86_64, aarch64, etc.)
#   GHC_HOST, GHC_TARGET         - GHC triple format
#   IS_CROSS_COMPILE             - "true" or "false"
#
# Also overrides build_alias, host_alias, target_alias for cross-compilation.
#
# Usage:
#   calculate_build_architecture
#   echo "Building GHC: ${GHC_HOST} -> ${GHC_TARGET}"
#
# Parameters:
#   $1 - debug: Set to "true" to print calculated values (default: "false")
#
calculate_build_architecture() {
  local debug="${1:-false}"

  # Determine if cross-compiling
  export IS_CROSS_COMPILE="false"
  if [[ "${build_platform}" != "${target_platform}" ]]; then
    IS_CROSS_COMPILE="true"
  fi

  # Set conda aliases
  export CONDA_HOST="${build_alias}"
  export CONDA_TARGET="${host_alias}"

  # Extract architecture prefixes
  export HOST_ARCH="${build_alias%%-*}"
  export TARGET_ARCH="${host_alias%%-*}"

  # Platform-specific GHC triples
  if [[ "${target_platform}" == linux-* ]]; then
    export GHC_HOST="${HOST_ARCH}-unknown-linux-gnu"
    export GHC_TARGET="${TARGET_ARCH}-unknown-linux-gnu"

  elif [[ "${target_platform}" == osx-* ]]; then
    # macOS: Replace full darwin version with just "darwin"
    export GHC_HOST="${CONDA_HOST/darwin*/darwin}"
    export GHC_TARGET="${CONDA_TARGET/darwin*/darwin}"
  fi

  # Override build/host/target aliases for GHC configure
  # In cross-compilation, GHC wants host=build and target=actual-target
  if [[ "$IS_CROSS_COMPILE" == "true" ]]; then
    export build_alias="${GHC_HOST}"
    export host_alias="${GHC_HOST}"
    export target_alias="${GHC_TARGET}"
  fi

  if [[ "$debug" == "true" ]]; then
    echo "=== Build Architecture ==="
    echo "  Platform:    ${build_platform} -> ${target_platform}"
    echo "  Conda:       ${CONDA_HOST} -> ${CONDA_TARGET}"
    echo "  GHC triple:  ${GHC_HOST} -> ${GHC_TARGET}"
    echo "  Cross-compile: ${IS_CROSS_COMPILE}"
    echo "=========================="
  fi
}

# ==============================================================================
# HADRIAN SYSTEM.CONFIG MANIPULATION
# ==============================================================================

# Update hadrian/cfg/system.config with correct tool paths and library flags
#
# After configure runs, hadrian's system.config needs adjustments for:
# - Tool prefixes (aarch64-conda-linux-gnu-clang, etc.)
# - Library search paths
# - Stage-specific compiler flags
#
# Usage:
#   update_hadrian_system_config "aarch64-conda-linux-gnu" "false"
#
# Parameters:
#   $1 - target_prefix: Tool prefix for target architecture
#   $2 - stage0_overrides: Set to "true" for cross-compilation (adds --target flags)
#   $3 - ar_stage0: Override for system-ar (optional, for macOS llvm-ar)
#
update_hadrian_system_config() {
  local target_prefix="$1"
  local stage0_overrides="${2:-false}"
  local ar_stage0="${3:-}"

  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "$settings_file" ]]; then
    echo "ERROR: Hadrian system.config not found at ${settings_file}"
    return 1
  fi

  echo "Updating Hadrian system.config for target: ${target_prefix}"

  # Remove build prefix from all tool paths
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"

  # Platform-specific tool prefixing
  if [[ "${target_platform}" == osx-* ]]; then
    # macOS includes objdump in tool list
    local tools="ar|clang|clang\+\+|llc|nm|objdump|opt|ranlib"

    # Override system-ar with LLVM ar if provided
    if [[ -n "$ar_stage0" ]]; then
      perl -pi -e "s#(system-ar\s*?=\s).*#\$1${ar_stage0}#" "${settings_file}"
    fi
  else
    # Linux: no objdump override needed
    local tools="ar|clang|clang\+\+|llc|nm|opt|ranlib"
  fi

  perl -pi -e "s#(=\s+)(${tools})\$#\$1${target_prefix}-\$2#" "${settings_file}"

  # Add library paths for stage1 and stage2
  perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"

  # Cross-compilation: stage0 overrides
  # Stage0 tools run on build machine, need --target flag for cross
  if [[ "$stage0_overrides" == "true" ]]; then
    local host_triple="${build_alias}"
    perl -pi -e "s#(conf-cc-args-stage0\s*?=\s).*#\$1--target=${host_triple}#" "${settings_file}"
    perl -pi -e "s#(conf-gcc-linker-args-stage0\s*?=\s).*#\$1--target=${host_triple}#" "${settings_file}"
  fi

  # macOS: Additional objdump cleanup (llvm-objdump doesn't need prefix)
  if [[ "${target_platform}" == osx-* ]]; then
    perl -pi -e "s#${target_prefix}-(objdump)#\$1#" "${settings_file}"
  fi

  echo "Hadrian system.config updated. Preview:"
  head -20 "${settings_file}"
}

# ==============================================================================
# CONDA ENVIRONMENT SETUP (CROSS-COMPILATION)
# ==============================================================================

# Create and configure a conda environment for cross-compilation bootstrap
#
# Cross-compilation requires a bootstrap GHC and cabal that run on the
# build machine. This function creates a temporary conda environment with
# the necessary tools.
#
# Sets these global variables:
#   CROSS_ENV_PATH    - Path to created environment
#   GHC               - Path to bootstrap GHC
#   CABAL             - Path to cabal
#   CABAL_DIR         - Path to cabal configuration directory
#
# Usage:
#   setup_cross_build_env "linux-64" "libc2.17_env" "sysroot_linux-64==2.17"
#   "${GHC}" --version
#
# Parameters:
#   $1 - platform: Conda platform (e.g., "linux-64", "osx-64")
#   $2 - env_name: Name for the conda environment
#   $@ - extra_packages: Additional packages to install (rest of arguments)
#
setup_cross_build_env() {
  local platform="$1"
  local env_name="$2"
  shift 2
  local extra_packages=("$@")

  echo "=== Creating cross-compilation environment ==="
  echo "  Platform: ${platform}"
  echo "  Name: ${env_name}"
  [[ ${#extra_packages[@]} -gt 0 ]] && echo "  Extra packages: ${extra_packages[*]}"

  conda create -y \
    -n "${env_name}" \
    --platform "${platform}" \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap=="${PKG_VERSION}" \
    "${extra_packages[@]}"

  # Get environment path
  local env_path
  env_path=$(conda info --envs | grep "${env_name}" | awk '{print $2}')

  if [[ -z "$env_path" || ! -d "$env_path" ]]; then
    echo "ERROR: Could not find conda environment ${env_name}"
    return 1
  fi

  # Export standard variables
  export CROSS_ENV_PATH="${env_path}"
  export GHC="${env_path}/ghc-bootstrap/bin/ghc"
  export CABAL="${env_path}/bin/cabal"
  export CABAL_DIR="${SRC_DIR}/.cabal"

  echo "  Environment created at: ${env_path}"

  # Verify GHC works
  "${GHC}" --version

  # Recache package database
  "${env_path}/ghc-bootstrap/bin/ghc-pkg" recache

  # Initialize cabal
  mkdir -p "${CABAL_DIR}"
  "${CABAL}" user-config init

  # Update cabal package list
  run_and_log "cabal-update" "${CABAL}" v2-update

  echo "=== Cross-compilation environment ready ==="
  return 0
}

# ==============================================================================
# HADRIAN DEPENDENCY BUILDER
# ==============================================================================

# Build Hadrian and its dependencies with correct toolchain for build machine
#
# CRITICAL: Hadrian is a BUILD TOOL that runs on the build machine (x86_64),
# NOT on the target machine (aarch64/ppc64le). Therefore:
# - MUST use BUILD machine compilers (CC_STAGE0, not CC)
# - MUST use BUILD machine CFLAGS (x86_64, not target flags)
# - MUST NOT be affected by target architecture environment variables
#
# Reference: CLAUDE.md "CRITICAL #1: Directory Package Configure Failure"
#
# Exports:
#   HADRIAN_BIN - Path to the built hadrian executable
#
# Returns:
#   stdout - Path to hadrian executable (for command substitution)
#
# Usage:
#   # Option 1: Use exported variable
#   build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}"
#   "${HADRIAN_BIN}" --version
#
#   # Option 2: Capture return value
#   HADRIAN_BUILD=$(build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}")
#   "${HADRIAN_BUILD}" --version
#
#   # With custom CFLAGS for build machine (space-separated values):
#   build_cflags="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC"
#   HADRIAN_BUILD=$(build_hadrian_cross "${GHC}" "${AR_STAGE0}" "${CC_STAGE0}" "${LD_STAGE0}" "${build_cflags}")
#
#   # IMPORTANT: Always quote variables to preserve spaces in CFLAGS/LDFLAGS
#
# Parameters:
#   $1 - ghc_path: Path to bootstrap GHC (must run on build machine)
#   $2 - ar_stage0: Path to ar for build machine
#   $3 - cc_stage0: Path to C compiler for build machine
#   $4 - ld_stage0: Path to linker for build machine
#   $5 - extra_cflags: Override CFLAGS for build machine (optional)
#   $6 - extra_ldflags: Override LDFLAGS for build machine (optional)
#
build_hadrian_cross() {
  local ghc_path="$1"
  local ar_stage0="$2"
  local cc_stage0="$3"
  local ld_stage0="$4"
  local extra_cflags="${5:-}"
  local extra_ldflags="${6:-}"

  echo "=== Building Hadrian with dependencies ==="
  echo "  GHC: ${ghc_path}"
  echo "  AR: ${ar_stage0}"
  echo "  CC: ${cc_stage0}"
  echo "  LD: ${ld_stage0}"

  pushd "${SRC_DIR}/hadrian" || return 1

  # CRITICAL: Override CFLAGS/LDFLAGS if provided
  # This prevents target architecture flags from contaminating Hadrian build
  if [[ -n "$extra_cflags" ]]; then
    echo "  Overriding CFLAGS for build machine:"
    echo "    ${extra_cflags}"
    export CFLAGS="$extra_cflags"
  fi

  if [[ -n "$extra_ldflags" ]]; then
    echo "  Overriding LDFLAGS for build machine:"
    echo "    ${extra_ldflags}"
    export LDFLAGS="$extra_ldflags"
  fi

  export CABFLAGS=(--enable-shared --enable-executable-dynamic -j)

  # Hadrian dependency list (same across all platforms)
  local hadrian_deps=(
    clock
    file-io
    heaps
    js-dgtable
    js-flot
    js-jquery
    directory
    os-string
    splitmix
    utf8-string
    hashable
    process
    primitive
    random
    QuickCheck
    unordered-containers
    extra
    Cabal-syntax
    filepattern
    Cabal
    shake
    hadrian
  )

  "${CABAL}" v2-build \
    --with-ar="${ar_stage0}" \
    --with-gcc="${cc_stage0}" \
    --with-ghc="${ghc_path}" \
    --with-ld="${ld_stage0}" \
    -j \
    "${hadrian_deps[@]}" \
    2>&1 | tee "${SRC_DIR}/cabal-verbose.log"

  local exit_code=${PIPESTATUS[0]}

  popd || return 1

  if [[ $exit_code -ne 0 ]]; then
    echo "=== Cabal build FAILED with exit code ${exit_code} ==="
    echo "See ${SRC_DIR}/cabal-verbose.log for details"
    return 1
  fi

  # Find hadrian binary location
  local hadrian_path
  hadrian_path=$(find "${SRC_DIR}/hadrian" -type f -name hadrian -executable | head -1)

  if [[ -z "$hadrian_path" ]]; then
    echo "=== ERROR: Could not find hadrian binary ===" >&2
    return 1
  fi

  # Export for convenience
  export HADRIAN_BIN="${hadrian_path}"

  echo "=== Hadrian build completed successfully ===" >&2
  echo "  Hadrian binary: ${hadrian_path}" >&2

  # Return path for command substitution: HADRIAN_BUILD=$(build_hadrian_cross ...)
  echo "${hadrian_path}"
  return 0
}

# ==============================================================================
# MACOS BOOTSTRAP SETTINGS FIXER
# ==============================================================================

# Fix macOS bootstrap GHC settings for conda environment
#
# The ghc-bootstrap package from conda has settings that reference system
# libraries (libiconv2.tbd) which don't exist in conda environment.
# This function patches the bootstrap settings to use conda toolchain.
#
# Usage:
#   fix_macos_bootstrap_settings "${osx_64_env}" "x86_64-apple-darwin13.4.0" "llvm-ar"
#
# Parameters:
#   $1 - bootstrap_env_path: Path to bootstrap conda environment
#   $2 - conda_host: Conda host triple (for tool prefixing)
#   $3 - ar_stage0: Path to ar command (default: llvm-ar)
#
fix_macos_bootstrap_settings() {
  local bootstrap_env_path="$1"
  local conda_host="$2"
  local ar_stage0="${3:-llvm-ar}"

  local bootstrap_settings="${bootstrap_env_path}/ghc-bootstrap/lib/ghc-${PKG_VERSION}/lib/settings"

  if [[ ! -f "$bootstrap_settings" ]]; then
    echo "WARNING: Bootstrap settings not found at ${bootstrap_settings}"
    return 1
  fi

  echo "=== Fixing macOS bootstrap settings ==="
  echo "  Settings file: ${bootstrap_settings}"

  # Remove system libiconv reference (doesn't exist in conda env)
  perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${bootstrap_settings}"

  # Add -fno-lto to prevent ABI mismatches between bootstrap and final GHC
  perl -pi -e "s#(C compiler flags\", \")#\$1-v -fno-lto #" "${bootstrap_settings}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${bootstrap_settings}"
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto#" "${bootstrap_settings}"

  # Use conda toolchain instead of system tools
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${ar_stage0}#" "${bootstrap_settings}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1llvm-ranlib#" "${bootstrap_settings}"
  perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${conda_host}-\$2#" "${bootstrap_settings}"

  echo "=== Bootstrap settings updated ==="
  echo "Preview:"
  grep -E "(iconv|lto|ar command|ranlib command|clang command)" "${bootstrap_settings}" || true

  return 0
}

################################################################################
# Usage examples for build scripts:
#
# 1. Source common.sh:
#    source "${RECIPE_DIR}"/building/common.sh
#
# 2. Calculate architecture and set autoconf variables:
#    calculate_build_architecture "true"  # true = debug output
#    set_autoconf_toolchain_vars "${CONDA_TARGET}"
#
# 3. Build configure arguments:
#    declare -a CONFIGURE_ARGS
#    build_configure_args CONFIGURE_ARGS
#    ./configure "${CONFIGURE_ARGS[@]}"
################################################################################
