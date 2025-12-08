#!/usr/bin/env bash
# ==============================================================================
# GHC Build Helpers - Utility Functions
# ==============================================================================
# Provides utility functions for the GHC build process:
#   - Logging (run_and_log)
#   - Array builders (nameref pattern)
#   - Settings file manipulation
#   - Cross-compilation helpers
#   - Hook execution
#
# These are foundational functions used by phases.sh and platform scripts.
# ==============================================================================

set -eu

# ==============================================================================
# Logging
# ==============================================================================

_log_index=0

run_and_log() {
  local phase="$1"
  shift

  ((_log_index++)) || true
  mkdir -p "${SRC_DIR}/_logs"
  local log_file="${SRC_DIR}/_logs/$(printf "%02d" ${_log_index})-${phase}.log"

  echo "  Running: $*"
  echo "  Log: ${log_file}"

  "$@" > "${log_file}" 2>&1 || {
    local exit_code=$?
    echo ""
    echo "========================================"
    echo "*** COMMAND FAILED (exit code: ${exit_code}) ***"
    echo "*** Phase: ${phase}"
    echo "*** Log file: ${log_file}"
    echo "========================================"
    echo ""
    echo "=== FULL LOG OUTPUT ==="
    cat "${log_file}"
    echo ""
    echo "=== END LOG OUTPUT ==="
    return ${exit_code}
  }
  return 0
}

# ==============================================================================
# Array Builder Helpers (Bash 5.2+ nameref pattern)
# ==============================================================================
# These functions use `local -n` (nameref) to directly populate arrays in
# the caller's scope. This is cleaner than global variables or subshell+eval.
#
# Usage pattern:
#   declare -a MY_ARGS
#   build_configure_args MY_ARGS
#   ./configure "${MY_ARGS[@]}"
# ==============================================================================

# Build standard GHC configure arguments (--with-* flags for libraries)
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - extra_ldflags: Additional LDFLAGS to append (optional)
#
build_configure_args() {
  local -n _result="$1"
  local extra_ldflags="${2:-}"

  _result+=(--with-system-libffi=yes)
  _result+=("--with-curses-includes=${PREFIX}/include")
  _result+=("--with-curses-libraries=${PREFIX}/lib")
  _result+=("--with-ffi-includes=${PREFIX}/include")
  _result+=("--with-ffi-libraries=${PREFIX}/lib")
  _result+=("--with-gmp-includes=${PREFIX}/include")
  _result+=("--with-gmp-libraries=${PREFIX}/lib")
  _result+=("--with-iconv-includes=${PREFIX}/include")
  _result+=("--with-iconv-libraries=${PREFIX}/lib")

  # Platform-specific additions
  if [[ "${target_platform:-}" == linux-* ]]; then
    _result+=(--disable-numa)
  fi

  # Optional LDFLAGS
  if [[ -n "$extra_ldflags" ]]; then
    _result+=("LDFLAGS=$extra_ldflags")
  fi
}

# Build system configuration arguments (--build, --host, --target, --prefix)
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - build_triple: Build machine triple (empty = omit)
#   $3 - host_triple: Host machine triple (empty = omit)
#   $4 - target_triple: Target machine triple (empty = omit)
#
build_system_config() {
  echo "  DEBUG: build_system_config called, args: '$1' '$2' '$3' '$4'"
  echo "  DEBUG: PREFIX=${PREFIX}"
  echo "  DEBUG: _PREFIX=${_PREFIX:-not_set} _PREFIX_=${_PREFIX_:-not_set}"

  local -n _result="$1"
  local build_triple="${2:-}"
  local host_triple="${3:-}"
  local target_triple="${4:-}"

  # Windows: Use _PREFIX_ (C:/... mixed format) for Cabal compatibility
  # Unix: Use PREFIX directly
  local prefix_path
  if [[ "${target_platform:-}" == "win-64" ]]; then
    prefix_path="${_PREFIX_:-${_PREFIX:-${PREFIX}}}"
  else
    prefix_path="${PREFIX}"
  fi
  echo "  DEBUG: prefix_path=${prefix_path}"

  _result+=("--prefix=${prefix_path}")
  [[ -n "$build_triple" ]] && _result+=("--build=$build_triple")
  [[ -n "$host_triple" ]] && _result+=("--host=$host_triple")
  [[ -n "$target_triple" ]] && _result+=("--target=$target_triple")

  echo "  DEBUG: build_system_config done, result has ${#_result[@]} elements"
}

# Build Hadrian command array with standard flags
#
# Parameters:
#   $1 - result_array_name: Name of array variable to populate (nameref)
#   $2 - hadrian_bin: Path to hadrian executable
#   $3 - jobs: Number of parallel jobs (optional, defaults to CPU_COUNT)
#
build_hadrian_cmd() {
  local -n _result="$1"
  local hadrian_bin="$2"
  local jobs="${3:-${CPU_COUNT:-1}}"

  _result=("${hadrian_bin}" "-j${jobs}" "--directory" "${SRC_DIR}")
}

# Set autoconf cache variables for toolchain
# Exports ac_cv_* variables to environment for configure scripts
#
# Parameters:
#   $1 - target_prefix: Tool prefix (e.g., "x86_64-conda-linux-gnu")
#   $2 - debug: Set to "true" to print exported variables (optional)
#
set_autoconf_toolchain_vars() {
  local target_prefix="$1"
  local debug="${2:-false}"

  [[ "$debug" == "true" ]] && echo "=== Setting autoconf toolchain variables for: ${target_prefix}"

  # Core build tools - set all patterns for maximum compatibility
  for tool in AR AS CC CXX LD NM OBJDUMP RANLIB; do
    local tool_value="${!tool:-}"  # Indirect expansion
    if [[ -n "$tool_value" ]]; then
      export ac_cv_prog_${tool}="${tool_value}"
      export ac_cv_path_${tool}="${tool_value}"
      export ac_cv_path_ac_pt_${tool}="${tool_value}"
      [[ "$debug" == "true" ]] && echo "  ac_cv_prog_${tool}=${tool_value}"
    fi
  done

  # LLVM tools
  export ac_cv_prog_LLC="${target_prefix}-llc"
  export ac_cv_prog_OPT="${target_prefix}-opt"

  # CRITICAL: glibc 2.17 compatibility (statx added in 2.28)
  export ac_cv_func_statx=no
  export ac_cv_have_decl_statx=no

  # libffi detection
  export ac_cv_lib_ffi_ffi_call=yes

  [[ "$debug" == "true" ]] && echo "  ac_cv_func_statx=no (glibc 2.17 compat)"
}

# ==============================================================================
# Settings Update Helpers
# ==============================================================================

# Patch hadrian/cfg/system.config with library paths and rpaths
# This is the common pattern used by all platforms after ./configure
#
# Usage:
#   patch_system_config_linker_flags
#   patch_system_config_linker_flags "${custom_prefix}"
#
# Parameters:
#   $1 - prefix: Library prefix path (optional, defaults to $PREFIX)
#
patch_system_config_linker_flags() {
  local prefix="${1:-${PREFIX}}"
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: system.config not found at ${settings_file}, skipping patch"
    return 0
  fi

  echo "  Patching system.config with library paths..."

  # Add -Wno-deprecated-non-prototype to suppress old-style C prototype warnings
  # Required for hp2ps utility which has: extern void* malloc();
  perl -pi -e "s#(conf-cc-args-stage[012].*?= )#\$1-Wno-deprecated-non-prototype #" "${settings_file}"

  # Add library paths and rpath to GCC linker flags (stage 1 and 2)
  # Use [ \t]* instead of \s* or .*? to avoid matching newlines
  perl -pi -e 's#^(conf-gcc-linker-args-stage[12][ \t]*=[ \t]*)#$1-Wl,-L'"${prefix}"'/lib -Wl,-rpath,'"${prefix}"'/lib #' "${settings_file}"

  # Add library paths and rpath to LD linker flags (stage 1 and 2)
  perl -pi -e 's#^(conf-ld-linker-args-stage[12][ \t]*=[ \t]*)#$1-L'"${prefix}"'/lib -rpath '"${prefix}"'/lib #' "${settings_file}"

  # Add library paths to settings (for installed GHC)
  perl -pi -e 's#^(settings-c-compiler-link-flags[ \t]*=[ \t]*)#$1-Wl,-L'"${prefix}"'/lib -Wl,-rpath,'"${prefix}"'/lib #' "${settings_file}"
  perl -pi -e 's#^(settings-ld-flags[ \t]*=[ \t]*)#$1-L'"${prefix}"'/lib -rpath '"${prefix}"'/lib #' "${settings_file}"

  # Add xelatex placeholder - Hadrian validates this even with --docs=none
  # Without this, build fails with: "Non optional builder 'xelatex' is not specified"
  # Note: system.config.in has "xelatex = @XELATEX@" which becomes "xelatex = " if not found
  # We need to detect and replace empty values or add the line if missing
  #
  # IMPORTANT: The line might be "xelatex = " (with trailing space) or "xelatex =" or similar
  # Check if value is empty/whitespace by looking for a non-whitespace char after =
  # NOTE: Using sed instead of perl because perl's $ anchor can miss \r in CRLF files
  if ! grep -qE "^xelatex\s*=\s*\S" "${settings_file}"; then
    # Replace the line completely (sed handles line endings correctly)
    sed -i 's/^xelatex[[:space:]]*=.*/xelatex = \/bin\/true/' "${settings_file}"
    # If line still doesn't exist with a value, add it
    if ! grep -qE "^xelatex\s*=\s*\S" "${settings_file}"; then
      echo "xelatex = /bin/true" >> "${settings_file}"
    fi
    echo "  Added xelatex placeholder to system.config"
  fi

  # Add sphinx-build placeholder - same issue as xelatex
  if ! grep -qE "^sphinx-build\s*=\s*\S" "${settings_file}"; then
    sed -i 's/^sphinx-build[[:space:]]*=.*/sphinx-build = \/bin\/true/' "${settings_file}"
    if ! grep -qE "^sphinx-build\s*=\s*\S" "${settings_file}"; then
      echo "sphinx-build = /bin/true" >> "${settings_file}"
    fi
    echo "  Added sphinx-build placeholder to system.config"
  fi

  echo "  ✓ system.config linker flags patched"
}

# Strip BUILD_PREFIX from tool paths in system.config
# Commonly needed for cross-compilation and some native builds
#
# Usage:
#   strip_build_prefix_from_tools
#   strip_build_prefix_from_tools "python"  # Exclude python from stripping
#
# Parameters:
#   $1 - exclude_pattern: Regex pattern to exclude from stripping (optional)
#
strip_build_prefix_from_tools() {
  local exclude_pattern="${1:-}"
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: system.config not found, skipping strip"
    return 0
  fi

  echo "  Stripping BUILD_PREFIX from tool paths..."

  if [[ -n "${exclude_pattern}" ]]; then
    # Use negative lookahead to exclude pattern
    perl -pi -e "s#${BUILD_PREFIX}/bin/(?!${exclude_pattern})##" "${settings_file}"
  else
    perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
  fi

  echo "  ✓ BUILD_PREFIX stripped from tool paths"
}

# Add toolchain prefix to tools in system.config
# Used for cross-compilation where tools need target prefix
#
# Usage:
#   add_toolchain_prefix_to_tools "aarch64-conda-linux-gnu"
#
# Parameters:
#   $1 - toolchain_prefix: The prefix to add (e.g., "aarch64-conda-linux-gnu")
#   $2 - tools: Space-separated list of tools (optional, defaults to common set)
#
add_toolchain_prefix_to_tools() {
  local toolchain_prefix="$1"
  local tools="${2:-ar clang clang++ llc nm opt ranlib}"
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: system.config not found, skipping prefix"
    return 0
  fi

  echo "  Adding toolchain prefix '${toolchain_prefix}' to tools..."

  # Build regex pattern from tools list
  local tool_pattern=$(echo "${tools}" | tr ' ' '|')

  perl -pi -e "s#(=\\s+)(${tool_pattern})\$#\$1${toolchain_prefix}-\$2#" "${settings_file}"

  echo "  ✓ Toolchain prefix added to tools"
}

# Fix Python path in system.config for cross-compilation
# Configure sets python = $PREFIX/bin/python but Python runs on build host
#
# Usage:
#   fix_python_path_for_cross
#
fix_python_path_for_cross() {
  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: system.config not found, skipping python fix"
    return 0
  fi

  echo "  Fixing Python path for cross-compilation..."

  perl -pi -e "s#(^python\\s*=).*#\$1 ${BUILD_PREFIX}/bin/python#" "${settings_file}"

  echo "  ✓ Python path fixed to BUILD_PREFIX"
}

# Update stage settings file with library paths and rpaths
# This is commonly needed between build phases to ensure proper linking
#
# Usage:
#   update_stage_settings "stage0"
#   update_stage_settings "stage1"
#
# Parameters:
#   $1 - stage: Which stage settings to update (stage0, stage1)
#
update_stage_settings() {
  local stage="$1"
  local settings_file="${SRC_DIR}/_build/${stage}/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: ${stage} settings file not found at ${settings_file}"
    return 0
  fi

  # Check if flags are already present (idempotent operation)
  if grep -q "Wl,-L\${PREFIX}/lib" "${settings_file}" 2>/dev/null || \
     grep -q "Wl,-L${PREFIX}/lib" "${settings_file}" 2>/dev/null; then
    echo "  ${stage} settings already have library paths, skipping update"
    return 0
  fi

  echo "  Updating ${stage} settings with library paths..."

  # Add library paths and rpath
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

  echo "  ${stage} settings after update:"
  grep -E "(C compiler link flags|ld flags)" "${settings_file}" 2>/dev/null || echo "  (no matching lines)"

  echo "  ✓ ${stage} settings updated"
}

# Update settings file with platform-specific link flags
# Used by platform scripts to patch GHC settings during build
#
# Usage:
#   update_settings_link_flags "${settings_file}"
#
# Parameters:
#   $1 - settings_file: Path to GHC settings file
#   $2 - toolchain: Toolchain prefix (optional, defaults to $CONDA_TOOLCHAIN_HOST)
#   $3 - prefix: Install prefix (optional, defaults to $PREFIX)
#
update_settings_link_flags() {
  local settings_file="$1"
  local toolchain="${2:-$CONDA_TOOLCHAIN_HOST}"
  local prefix="${3:-$PREFIX}"

  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"

    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${prefix}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${prefix}/lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${prefix}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${prefix}/lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-arm64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fuse-ld=lld -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
  fi

  # Update toolchain paths
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${settings_file}"
}

# Set macOS-specific ar and ranlib settings for LLVM toolchain
# Apple ld64 requires LLVM ar instead of GNU ar
#
# Usage:
#   set_macos_conda_ar_ranlib "${settings_file}"
#
# Parameters:
#   $1 - settings_file: Path to GHC settings file
#   $2 - toolchain: Toolchain prefix (optional, defaults to x86_64-apple-darwin13.4.0)
#
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

# Update installed GHC settings with final link flags and toolchain paths
# Called after GHC is installed to PREFIX
#
# Usage:
#   update_installed_settings
#   update_installed_settings "x86_64-apple-darwin13.4.0"
#
# Parameters:
#   $1 - toolchain: Toolchain prefix (optional, defaults to $CONDA_TOOLCHAIN_HOST)
#
update_installed_settings() {
  local toolchain="${1:-$CONDA_TOOLCHAIN_HOST}"

  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  if [[ "${target_platform}" == "linux-"* ]]; then
    # Add library paths
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-rpath,\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \")#\$1-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -rpath \\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib #" "${settings_file}"

    # CRITICAL: Add -no-pie for GHC 9.2.x and 9.4.x to work around PIE relocation errors
    # The RTS static libraries are not compiled with -fPIC, so linking executables fails
    # with "relocation R_X86_64_32S against symbol ... cannot be used when making a PIE object"
    local major_version
    major_version=$(get_ghc_major_version)
    if [[ "${major_version}" == "9.2" || "${major_version}" == "9.4" ]]; then
      echo "    Adding -no-pie to installed settings for GHC ${major_version}.x PIE fix"
      perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -no-pie#' "${settings_file}"
      perl -pi -e 's#(ld flags", "[^"]*)#$1 -no-pie #' "${settings_file}"
    fi

  elif [[ "${target_platform}" == "osx-"* ]]; then
    perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"
    perl -i -pe "s#(C\\+\\+ compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -fuse-ld=lld -fno-lto -fno-use-linker-plugin -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib -liconv -Wl,-L\\\$topdir/../lib -Wl,-rpath,\\\$topdir/../lib -liconv_compat#" "${settings_file}"
  fi

  # Remove build-time paths (expanded paths like /home/conda/.../build_env/...)
  perl -pi -e "s#(-Wl,-L${BUILD_PREFIX}/lib|-Wl,-L${PREFIX}/lib|-Wl,-rpath,${BUILD_PREFIX}/lib|-Wl,-rpath,${PREFIX}/lib)##g" "${settings_file}"
  perl -pi -e "s#(-L${BUILD_PREFIX}/lib|-L${PREFIX}/lib|-rpath ${PREFIX}/lib|-rpath ${BUILD_PREFIX}/lib)##g" "${settings_file}"

  # Remove literal $BUILD_PREFIX and $PREFIX from tool paths
  # These are unexpanded variable references that won't work at runtime
  # Pattern: "$BUILD_PREFIX/bin/tool" -> "tool" (just the tool name)
  perl -pi -e 's#\$BUILD_PREFIX/bin/##g' "${settings_file}"
  perl -pi -e 's#\$PREFIX/bin/##g' "${settings_file}"

  # Also handle %BUILD_PREFIX% style (Windows batch variable syntax that may leak through)
  perl -pi -e 's#%BUILD_PREFIX%/bin/##g' "${settings_file}"
  perl -pi -e 's#%PREFIX%/bin/##g' "${settings_file}"

  # Remove expanded BUILD_PREFIX paths (e.g., /home/conda/.../build_env/bin/)
  # These paths contain hyphens which aren't matched by \w
  perl -pi -e "s#${BUILD_PREFIX}/bin/##g" "${settings_file}"

  # Update toolchain paths - strip any remaining absolute paths and keep just toolchain-prefixed names
  # Use [/\w\-]* to match paths with hyphens (like rattler-build_ghc_xxx)
  perl -pi -e "s#\"[/\w\-]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${toolchain}-\$1\"#" "${settings_file}"
}

# ==============================================================================
# Cross-Compilation Helpers
# ==============================================================================

# Configure native build triple for GHC
# Sets the GHC triple for native (non-cross) builds where build == host == target
#
# This function sets:
#   ghc_triple    - GHC-style triple for the native platform
#
# Environment exports:
#   build_alias   - Set to ghc_triple
#   host_alias    - Set to ghc_triple
#
# Usage:
#   configure_native_triple
#   echo "Native triple: ${ghc_triple}"
#
configure_native_triple() {
  case "${target_platform}" in
    linux-64)
      # Bootstrap GHC 9.2.8 uses 'x86_64-unknown-linux-gnu' but conda toolchain
      # uses 'x86_64-conda-linux-gnu'. Override to match bootstrap GHC.
      ghc_triple="x86_64-unknown-linux-gnu"
      ;;
    osx-64)
      ghc_triple="x86_64-apple-darwin13.4.0"
      ;;
    *)
      # Fallback: use conda's build_alias
      ghc_triple="${build_alias:-}"
      ;;
  esac

  export build_alias="${ghc_triple}"
  export host_alias="${ghc_triple}"

  echo "Native triple configuration:"
  echo "  GHC triple: ${ghc_triple}"
  echo "  build_alias: ${build_alias}"
  echo "  host_alias: ${host_alias}"
}

# Configure cross-compilation triples for GHC
# Maps conda arch names to GHC arch names and exports environment variables
#
# This function sets:
#   conda_host    - Conda's build triple (from build_alias)
#   conda_target  - Conda's host triple (from host_alias)
#   host_arch     - Architecture portion of conda_host (e.g., x86_64, aarch64)
#   target_arch   - Architecture portion of conda_target
#   ghc_host      - GHC-style host triple
#   ghc_target    - GHC-style target triple
#
# Environment exports:
#   build_alias   - Set to conda_host (or ghc_host for Linux)
#   host_alias    - Set to conda_host (or ghc_host for Linux)
#   target_alias  - Set to conda_target (or ghc_target for Linux)
#   host_platform - Set to build_platform
#
# Usage:
#   configure_cross_triples
#   echo "Building ${host_arch} -> ${target_arch}"
#
configure_cross_triples() {
  # Map conda arch names to GHC arch names
  conda_host="${build_alias}"
  conda_target="${host_alias}"

  host_arch="${conda_host%%-*}"
  target_arch="${conda_target%%-*}"

  # Generate GHC-style triples (platform-specific)
  case "${target_platform}" in
    linux-*)
      # Linux uses *-unknown-linux-gnu format
      ghc_host="${host_arch}-unknown-linux-gnu"
      ghc_target="${target_arch}-unknown-linux-gnu"
      # Linux GHC configure wants the ghc-style triples
      export build_alias="${ghc_host}"
      export host_alias="${ghc_host}"
      export target_alias="${ghc_target}"
      ;;
    osx-*)
      # macOS uses condensed darwin format
      ghc_host="${conda_host/darwin*/darwin}"
      ghc_target="${conda_target/darwin*/darwin}"
      # macOS keeps conda-style triples
      export build_alias="${conda_host}"
      export host_alias="${conda_host}"
      export target_alias="${conda_target}"
      ;;
    *)
      # Fallback for other platforms
      ghc_host="${conda_host}"
      ghc_target="${conda_target}"
      export build_alias="${conda_host}"
      export host_alias="${conda_host}"
      export target_alias="${conda_target}"
      ;;
  esac

  export host_platform="${build_platform}"

  echo "Cross-compilation configuration:"
  echo "  Build arch: ${host_arch} (${conda_host})"
  echo "  Target arch: ${target_arch} (${conda_target})"
  echo "  GHC host: ${ghc_host}"
  echo "  GHC target: ${ghc_target}"
}

# Disable Hadrian's copy optimization for cross-compilation
# By default, Hadrian tries to copy the bootstrap GHC binary instead of building
# a new one. For cross-compilation, we need to force building the cross binary.
#
# Usage:
#   disable_copy_optimization
#
disable_copy_optimization() {
  echo "  Disabling copy optimization for cross-compilation..."

  # Force building the cross binary instead of copying
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' \
    "${SRC_DIR}/hadrian/src/Rules/Program.hs"

  echo "  ✓ Copy optimization disabled"
}

# ==============================================================================
# Hook Execution Helper
# ==============================================================================

call_hook() {
  local hook_name="platform_$1"
  if type -t "${hook_name}" >/dev/null 2>&1; then
    "${hook_name}"
  fi
}

# ==============================================================================
# Post-Install Helpers
# ==============================================================================

# Install bash completion script
# Should be called from platform_post_install or default_post_install
#
# Usage:
#   install_bash_completion
#
install_bash_completion() {
  echo "  Installing bash completion..."
  mkdir -p "${PREFIX}/etc/bash_completion.d"
  if [[ -f "${SRC_DIR}/utils/completion/ghc.bash" ]]; then
    cp "${SRC_DIR}/utils/completion/ghc.bash" "${PREFIX}/etc/bash_completion.d/ghc"
    echo "  ✓ Bash completion installed"
  else
    echo "  WARNING: ghc.bash completion file not found at ${SRC_DIR}/utils/completion/ghc.bash"
  fi
}

# ==============================================================================
# Platform Utility Helpers
# ==============================================================================

# Get the script file extension for the current platform
# Returns "sh" for Unix platforms, "bat" for Windows
#
# Usage:
#   local ext=$(get_script_extension)
#   cp "activate.${ext}" "${PREFIX}/etc/conda/activate.d/"
#
get_script_extension() {
  case "${target_platform}" in
    linux-64|linux-aarch64|linux-ppc64le|osx-64|osx-arm64)
      echo "sh"
      ;;
    *)
      echo "bat"
      ;;
  esac
}
