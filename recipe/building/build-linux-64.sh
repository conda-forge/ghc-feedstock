#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

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
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

for pkg in hadrian; do
  (cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" "${pkg}")
done

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release
update_settings_link_flags "${SRC_DIR}"/_build/stage0/lib/settings

export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release
update_settings_link_flags "${SRC_DIR}"/_build/stage0/lib/settings

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1
update_settings_link_flags "${SRC_DIR}"/_build/stage1/lib/settings

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze1
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --freeze1 --freeze2 --flavour=release --docs=none

settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
update_installed_settings
cat "${settings_file}"
