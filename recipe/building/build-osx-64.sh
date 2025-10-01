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
  # default is auto: --disable-numa
  --disable-ld-override
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

export ac_cv_path_ac_pt_CC=""
export ac_cv_path_ac_pt_CXX=""
export ac_cv_prog_AR="${AR}"
export ac_cv_prog_RANLIB="${RANLIB}"
export ac_cv_path_AR="${AR}"
export ac_cv_path_RANLIB="${RANLIB}"
export DEVELOPER_DIR=""

settings_file=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -n 1)
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-v -Wl,-L$ENV{PREFIX}/lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib#' "${settings_file}"
set_macos_system_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
run_and_log "configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

set_macos_system_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.host.target "${CONDA_TOOLCHAIN_BUILD}"
set_macos_system_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.target "${CONDA_TOOLCHAIN_BUILD}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# GHC selection of tools seems to fail to use conda-forge toolchain tools
rm -f /Users/runner/miniforge3/bin/{as,ranlib,ld}
ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-as /Users/runner/miniforge3/bin/as
ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld /Users/runner/miniforge3/bin/ld
ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ranlib /Users/runner/miniforge3/bin/ranlib

"${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest

# Create wrapper to export both _iconv* and _libiconv* symbols
# This satisfies both GHC (uses _libiconv*) and system libs (use _iconv*)
cat > /tmp/iconv_compat.c << 'EOFC'
#include <stddef.h>
typedef void* iconv_t;
extern iconv_t libiconv_open(const char*, const char*);
extern size_t libiconv(iconv_t, char**, size_t*, char**, size_t*);
extern int libiconv_close(iconv_t);
iconv_t iconv_open(const char* a, const char* b) { return libiconv_open(a, b); }
size_t iconv(iconv_t a, char** b, size_t* c, char** d, size_t* e) { return libiconv(a,b,c,d,e); }
int iconv_close(iconv_t a) { return libiconv_close(a); }
EOFC

${CC} -c /tmp/iconv_compat.c -o /tmp/iconv_compat.o
${AR} rcs /tmp/libiconv_compat.a /tmp/iconv_compat.o

perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-liconv /tmp/libiconv_compat.a#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\$ENV{PREFIX}/lib -L\\\$topdir/../../../../lib -liconv /tmp/libiconv_compat.a#" "${settings_file}"

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quickest

export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
settings_file="${SRC_DIR}"/_build/stage1/lib/settings
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-liconv /tmp/libiconv_compat.a#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\$ENV{PREFIX}/lib -v -L\\\$topdir/../../../../lib -liconv /tmp/libiconv_compat.a#" "${settings_file}"
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=quickest

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=quickest --docs=none --progress-info=none

settings_file=$(find "${PREFIX}" -name settings | head -n 1)
perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -v -fno-lto#" "${settings_file}"
perl -i -pe "s#(C\+\+ compiler flags\", \")([^\"]*)#\1\2 -v -fno-lto#" "${settings_file}"
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-liconv /tmp/libiconv_compat.a#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\\\$topdir/../../../../lib -liconv /tmp/libiconv_compat.a#" "${settings_file}"

cat "${settings_file}"
