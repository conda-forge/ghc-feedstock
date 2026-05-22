#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

(cd "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build -j hadrian)
_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-unknown-linux"
  --host="x86_64-unknown-linux"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  --with-system-libffi=yes
  --with-curses-includes="${PREFIX}"/include
  --with-curses-libraries="${PREFIX}"/lib
  --with-ffi-includes="${PREFIX}"/include
  --with-ffi-libraries="${PREFIX}"/lib
  --with-gmp-includes="${PREFIX}"/include
  --with-gmp-libraries="${PREFIX}"/lib
  --with-iconv-includes="${PREFIX}"/include
  --with-iconv-libraries="${PREFIX}"/lib
)

# Override configure's incorrect detection of -no-pie support
# The FP_GCC_SUPPORTS_NO_PIE test fails because clang warns about -no-pie
# during preprocessing (-E flag), and the test uses -Werror.
# We know clang DOES support -no-pie for linking, so override the result.
# Scope the export to just configure to avoid affecting other parts of the build.
CONF_GCC_SUPPORTS_NO_PIE=YES run_and_log "ghc-configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quick
update_settings_link_flags "${SRC_DIR}"/_build/stage0/lib/settings

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quick
update_settings_link_flags "${SRC_DIR}"/_build/stage0/lib/settings

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quick --freeze1
update_settings_link_flags "${SRC_DIR}"/_build/stage1/lib/settings

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=quick --freeze1
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --freeze1 --freeze2 --flavour=quick --docs=none

settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
update_installed_settings
cat "${settings_file}"
