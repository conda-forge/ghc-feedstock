#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# This is needed as in seems to interfere with configure scripts
unset build_alias
unset host_alias

# Update cabal package database
run_and_log "cabal-update" cabal v2-update --allow-newer --minimize-conflict-set

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  --disable-numa
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

# Temporary: ghc-bootstrap is being re-worked
if [[ -f "${SDKROOT}"/usr/lib/libiconv.2.tbd ]]; then
  sed -i -E "s#[^ ]*/usr/lib/libiconv.2.tbd#${SDKROOT}/usr/lib/libiconv.2.tbd#" "${BUILD_PREFIX}"/ghc-bootstrap/lib/ghc-*/lib/settings
fi
sed -i -E "s#-L/Applications[^ ]*#-L${SDKROOT}#g" "${BUILD_PREFIX}"/ghc-bootstrap/lib/ghc-*/lib/settings

# Remove LTO
if [[ -f "${SDKROOT}"/usr/lib/libLTO.dylib ]]; then
  export LDFLAGS="-Wl,-lto_library,${SDKROOT}/usr/lib/libLTO.dylib${LDFLAGS:-}"
else
  export CFLAGS="${CFLAGS//-flto/}"
  export CXXFLAGS="${CXXFLAGS//-flto/}"
  export LDFLAGS="-Wl,-no_lto_library ${LDFLAGS:-}"
fi

# configure detect the wrong CC/CXX (unknown why)
export ac_cv_prog_CC="x86_64-apple-darwin13.4.0-clang"
export ac_cv_path_CC="x86_64-apple-darwin13.4.0-clang"
export ac_cv_prog_CXX="x86_64-apple-darwin13.4.0-clang++"
export ac_cv_path_CXX="x86_64-apple-darwin13.4.0-clang++"

# Prevent autoconf from finding system compilers
export ac_cv_path_ac_pt_CC=""
export ac_cv_path_ac_pt_CXX=""

# Verify ghc-bootstrap configuration
printf 'import System.Posix.Signals\nmain = installHandler sigTERM Default Nothing >> putStrLn "Signal test"\n' > signal_test.hs
${BUILD_PREFIX}/ghc-bootstrap/bin/ghc --version
${BUILD_PREFIX}/ghc-bootstrap/bin/ghc signal_test.hs

bash ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || true
cat config.log && exit 1

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

export DYLD_INSERT_LIBRARIES=$(find ${PREFIX} -name libtinfow.dylib)

# Should be corrected in ghc-bootstrap
#settings_file=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -1)
#if [[ -n "${SDKROOT}" ]]; then
#  perl -i -pe 's#("C compiler link flags", ")([^"]*)"#\1\2 -L$ENV{SDKROOT}/usr/lib"#g' "${settings_file}"
#fi

"${_hadrian_build[@]}" stage1:exe:ghc-bin -V --flavour=release --progress-info=unicorn

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none --progress-info=none
