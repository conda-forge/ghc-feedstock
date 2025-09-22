#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# This is needed as in seems to interfere with configure scripts
unset build_alias
unset host_alias

export CABAL="${BUILD_PREFIX}/bin/cabal"
run_and_log "cabal-update" "${CABAL}" v2-update

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  --disable-numa
  --enable-ignore-build-platform-mismatch=yes
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
# perl -i -pe 's#x86_64-apple-darwin13.4.0-ar#/usr/bin/ar#g' "${SRC_DIR}"/hadrian/cfg/default.target
# perl -i -pe 's#prgFlags = ["q"]#prgFlags = ["qcls"]#g' "${SRC_DIR}"/hadrian/cfg/default.target
# perl -i -pe 's#x86_64-apple-darwin13.4.0-ranlib#/usr/bin/ranlib#g' "${SRC_DIR}"/hadrian/cfg/default.target

settings_file="${SRC_DIR}"/hadrian/cfg/default.host.target
perl -i -pe 's#/usr/bin/ar("[^"]*"q)cls#x86_64-apple-darwin13.4.0-ar${1}s#g' "${settings_file}"
perl -i -pe 's#((arIsGnu|arSupportsAtFile) = )False#$1True#g' "${settings_file}"
perl -i -pe 's#(arNeedsRanlib = )True#$1False#g' "${settings_file}"

settings_file="${SRC_DIR}"/hadrian/cfg/default.target
perl -i -pe 's#/usr/bin/ar("[^"]*"q)cls#x86_64-apple-darwin13.4.0-ar${1}s#g' "${settings_file}"
perl -i -pe 's#((arIsGnu|arSupportsAtFile) = )False#$1True#g' "${settings_file}"
perl -i -pe 's#(arNeedsRanlib = )True#$1False#g' "${settings_file}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

export DYLD_INSERT_LIBRARIES=$(find "${PREFIX}" -name libtinfow.dylib)
settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -i -pe 's#("ar command", ")([^"]*)"#\1 x86_64-apple-darwin13.4.0-ar"#g' "${settings_file}"
perl -i -pe 's#("ar flags", ")([^"]*)"#\1qs"#g' "${settings_file}"
perl -i -pe 's#("ranlib command", ")([^"]*)"#\1 x86_64-apple-darwin13.4.0-ranlib"#g' "${settings_file}"
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest
settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -i -pe 's#("ar command", ")([^"]*)"#\1 x86_64-apple-darwin13.4.0-ar"#g' "${settings_file}"
perl -i -pe 's#("ar flags", ")([^"]*)"#\1qs"#g' "${settings_file}"
perl -i -pe 's#("ranlib command", ")([^"]*)"#\1 x86_64-apple-darwin13.4.0-ranlib"#g' "${settings_file}"

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quickest
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=quickest

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=quickest --docs=none --progress-info=none
