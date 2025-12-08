#!/usr/bin/env bash
# ==============================================================================
# Platform Configuration: Linux x86_64 (Native)
# ==============================================================================
# Linux-specific build behavior.
# Most phases use defaults from common-functions.sh
# ==============================================================================

set -eu

# Platform metadata
PLATFORM_NAME="Linux x86_64 (native)"

# ==============================================================================
# Platform Triple Configuration
# ==============================================================================
# Bootstrap GHC 9.2.8 uses 'x86_64-unknown-linux-gnu' but conda toolchain
# uses 'x86_64-conda-linux-gnu'. Override to match bootstrap GHC.

ghc_triple="x86_64-unknown-linux-gnu"

# Override build/host aliases for GHC configure
export build_alias="${ghc_triple}"
export host_alias="${ghc_triple}"

echo "Platform triple configuration:"
echo "  GHC triple: ${ghc_triple}"
echo "  build_alias: ${build_alias}"
echo "  host_alias: ${host_alias}"

# ==============================================================================
# Phase 4b: Post-Configure (patch Hadrian system.config)
# ==============================================================================

platform_post_configure_ghc() {
  echo "  Patching Hadrian system.config for Linux..."

  local settings_file="${SRC_DIR}/hadrian/cfg/system.config"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: system.config not found, skipping patch"
    return 0
  fi

  # Add library paths for linking
  perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"

  # Add doc builder placeholders - Hadrian validates these even with --docs=none
  # Note: Configure generates "sphinx-build = " (empty value) if not found,
  # so we check for non-empty value, not just key existence
  if ! grep -qE "^xelatex\s*=\s*\S" "${settings_file}"; then
    sed -i 's/^xelatex[[:space:]]*=.*/xelatex = \/bin\/true/' "${settings_file}"
  fi
  if ! grep -qE "^sphinx-build\s*=\s*\S" "${settings_file}"; then
    sed -i 's/^sphinx-build[[:space:]]*=.*/sphinx-build = \/bin\/true/' "${settings_file}"
  fi

  echo "  ✓ Hadrian system.config patched"
}

# ==============================================================================
# Phase 5: Build Hadrian (with profiling)
# ==============================================================================

platform_build_hadrian() {
  echo "  Building Hadrian for Linux (cabal-built with profiling)..."

  pushd "${SRC_DIR}/hadrian" >/dev/null

  # Build Hadrian with cabal - use profiled version for timing analysis
  run_and_log_profiled "build-hadrian" "${CABAL}" v2-build -j${CPU_COUNT} -v hadrian

  popd >/dev/null

  # Find Hadrian binary
  local hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle -name hadrian -type f | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  # Set up Hadrian command array with timing enabled
  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}" "--timing")
  HADRIAN_FLAVOUR="${HADRIAN_FLAVOUR:-release}"

  echo "  Hadrian binary: ${hadrian_bin}"
  echo "  Hadrian flags: -j${CPU_COUNT} --timing"
  echo "  ✓ Hadrian built (cabal-built)"
}

# ==============================================================================
# Phase 6: Build Stage 1 (with profiling)
# ==============================================================================

platform_build_stage1() {
  echo "  Building Stage 1 GHC for Linux..."

  local options=(--flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=brief)

  run_and_log_profiled "stage1-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:exe:ghc-bin
  run_and_log "stage1-pkg" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:exe:ghc-pkg
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:exe:hsc2hs

  # Update stage0 settings
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage0"
  fi

  # Build Stage 1 libraries - profile the main lib build
  run_and_log "stage1-lib-prim" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc-prim
  run_and_log "stage1-lib-bignum" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc-bignum
  run_and_log "stage1-lib-base" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:base
  run_and_log "stage1-lib-th" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:template-haskell
  run_and_log "stage1-lib-ghci" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghci
  run_and_log_profiled "stage1-lib-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc

  # Update stage0 settings again
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage0"
  fi
}

# ==============================================================================
# Phase 7: Build Stage 2 (with profiling)
# ==============================================================================

platform_build_stage2() {
  echo "  Building Stage 2 GHC for Linux..."

  local options=(--flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=brief)

  run_and_log_profiled "stage2-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-bin
  run_and_log "stage2-pkg" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-pkg
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:hsc2hs

  # Build Stage 2 libraries
  run_and_log "stage2-lib-prim" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-prim
  run_and_log "stage2-lib-bignum" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-bignum
  run_and_log "stage2-lib-base" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:base
  run_and_log "stage2-lib-th" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:template-haskell
  run_and_log "stage2-lib-ghci" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghci
  run_and_log_profiled "stage2-lib-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc
}
