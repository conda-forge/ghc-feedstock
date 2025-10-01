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

export CABFLAGS=(--enable-shared --disable-static --disable-library-vanilla --enable-executable-dynamic -j)
for pkg in random hashable primitive directory unordered-containers extra filepattern directory shake random QuickCheck Cabal-syntax Cabal hadrian; do
  (cd  "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build "${CABFLAGS[@]}" --ghc-options="-dynamic -shared -fPIC -optl-dynamic -optl-Wl,-rpath,${PREFIX}/lib -optl-L${PREFIX}/lib -optl-liconv -optl-lffi -optl-lgmp -optl-ltinfo -optl-ltinfow" "${pkg}")
done

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release
settings_file="${SRC_DIR}"/_build/stage0/lib/settings

# CRITICAL: Set library paths in environment BEFORE stage1_lib build
# GHC uses these when linking, regardless of settings file content
export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${LD_LIBRARY_PATH:-}"

perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{BUILD_PREFIX}/lib -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{BUILD_PREFIX}/lib -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release || true
# perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{BUILD_PREFIX}/lib -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
# perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{BUILD_PREFIX}/lib -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"
# run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc -V --flavour=release --progress-info=unicorn
perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -v -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -v -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

# $topdir expansion will not work for _build/bindist/... binaries, use LD_PRELOAD hack
export LD_LIBRARY_PATH="${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${PREFIX}/lib/libiconv.so.2 ${PREFIX}/lib/libgmp.so.10 ${PREFIX}/lib/libffi.so.8 ${PREFIX}/lib/libtinfow.so.6 ${PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"
# Modify Stage0 settings for Stage2 build
settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -v -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -v -Wno-strict-prototypes#' "${settings_file}"
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

# Also modify Stage1 settings for primitive rebuild
settings_file_stage1="${SRC_DIR}"/_build/stage1/lib/settings
if [ -f "$settings_file_stage1" ]; then
  perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -v -Wno-strict-prototypes#' "${settings_file_stage1}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -v -Wno-strict-prototypes#' "${settings_file_stage1}"
  perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file_stage1}"
  perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file_stage1}"
fi

rm -rf "${BUILD_PREFIX}"/ghc-bootstrap

# CRITICAL: Workaround for primitive-0.9.0.0 missing include-dirs in its cabal file
# Add package-specific flags to hadrian's cabal.project
if ! grep -q "package primitive" "${SRC_DIR}"/hadrian/cabal.project 2>/dev/null; then
  cat >> "${SRC_DIR}"/hadrian/cabal.project << 'CABAL_LOCAL'

package primitive
  extra-include-dirs: cbits
CABAL_LOCAL
fi

export GHC="${SRC_DIR}"/_build/ghc-stage1
export PATH="${SRC_DIR}"/_build/stage0/bin:"${SRC_DIR}"/_build/stageBoot/bin:"${PATH}"
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin -V --flavour=release --freeze1
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze1

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none
