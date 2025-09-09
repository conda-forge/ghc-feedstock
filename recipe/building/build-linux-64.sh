#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Install cabal in its own environment to maintain GLIBC 2.17 for GHC
# if conda create -n cabal_env -y -c conda-forge cabal; then
#   export CABAL="conda run -n cabal_env cabal"
# else
#   echo "Conda cabal install failed"
#   exit 1
# fi

export CABAL="${BUILD_PREFIX}/bin/cabal"

# Update cabal package database
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

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin
perl -pi -e 's#(C compiler link flags", "--target=x86_64-unknown-linux)#$1 -L\$topdir/../../../../lib#' "${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(ld flags", ")#$1 -L\$topdir/../../../../lib #' "${SRC_DIR}"/_build/stage0/lib/settings

export LD_LIBRARY_PATH="${BUILD_PREFIX}"/lib:${LD_LIBRARY_PATH:-}
export LIBRARY_PATH="${BUILD_PREFIX}"/lib:${LIBRARY_PATH:-}
export LDFLAGS="-L${BUILD_PREFIX}/lib -L${PREFIX}/lib ${LDFLAGS:-}"
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc
perl -pi -e 's#(C compiler link flags", "--target=x86_64-unknown-linux)#$1 -L\$topdir/../../../../lib#' "${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(ld flags", ")#$1 -L\$topdir/../../../../lib #' "${SRC_DIR}"/_build/stage0/lib/settings

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none
