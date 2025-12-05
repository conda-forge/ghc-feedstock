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
  if ! grep -q "^xelatex" "${settings_file}"; then
    echo "xelatex = /bin/true" >> "${settings_file}"
  fi
  if ! grep -q "^sphinx-build" "${settings_file}"; then
    echo "sphinx-build = /bin/true" >> "${settings_file}"
  fi

  echo "  ✓ Hadrian system.config patched"
}
