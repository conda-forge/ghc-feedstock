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
  # --disable-ld-override
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

# Why does it use this linker? Damn, stubborn GHC...
echo "${PATH}"
which ld
ls -l "${SDKROOT}"/../../../../../Toolchains/XcodeDefault.xctoolchain/
ls -l "${SDKROOT}"/../../../../../Toolchains/XcodeDefault.xctoolchain/usr/bin/
ls -l /Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/

rm -f /Users/runner/miniforge3/bin/{as,ranlib,ld}
ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-as /Users/runner/miniforge3/bin/as
ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld /Users/runner/miniforge3/bin/ld
ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ranlib /Users/runner/miniforge3/bin/ranlib

"${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib#' "${settings_file}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest
iconv_aliases="-L${PREFIX}/lib -Wl,-alias,_libiconv,_iconv"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_open,_iconv_open"
iconv_aliases="${iconv_aliases} -Wl,-alias,_libiconv_close,_iconv_close"
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\$ENV{PREFIX}/lib -L\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quickest

export DYLD_LIBRARY_PATH="${PREFIX}/lib:${BUILD_PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
settings_file="${SRC_DIR}"/_build/stage1/lib/settings
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\$ENV{PREFIX}/lib -L\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=quickest

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=quickest --docs=none --progress-info=none

settings_file=$(find "${PREFIX}" -name settings | head -n 1)
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\\\$topdir/../../../../lib ${iconv_aliases} -liconv#" "${settings_file}"
