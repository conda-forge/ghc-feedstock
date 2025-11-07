#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# This is needed as it seems to interfere with configure scripts
unset build_alias
unset host_alias

# Build dynamic versions with explicit SDK version for compatibility
# This ensures the object file matches the SDK version used during GHC linking
# Resolves issues with missing _iconv_open when linking to conda-forge libiconv
mkdir -p "${PREFIX}/lib/ghc-${PKG_VERSION}/lib"
${CC} -dynamiclib -o "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/libiconv_compat.dylib "${RECIPE_DIR}"/building/osx_iconv_compat.c \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -mmacosx-version-min=10.13 \
    -install_name "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"

# Preload CONDA libraries to override system libraries
export DYLD_INSERT_LIBRARIES="${PREFIX}/lib/libiconv.dylib:${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"
export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"

# This seems to be the onlt archiver that resolves odd mismatched arch when linking
export AR=llvm-ar

settings_file=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -n 1)
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"
mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
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

export ac_cv_path_ac_pt_CC=""
export ac_cv_path_ac_pt_CXX=""
export ac_cv_prog_AR="${AR}"
export ac_cv_prog_CC="${CC}"
export ac_cv_prog_CXX="${CXX}"
export ac_cv_prog_LD="${LD}"
export ac_cv_prog_RANLIB="${RANLIB}"
export ac_cv_path_AR="${AR}"
export ac_cv_path_CC="${CC}"
export ac_cv_path_CXX="${CXX}"
export ac_cv_path_LD="${LD}"
export ac_cv_path_RANLIB="${RANLIB}"
export DEVELOPER_DIR=""

run_and_log "configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.host.target "${CONDA_TOOLCHAIN_BUILD}"
set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.target "${CONDA_TOOLCHAIN_BUILD}"

pushd "${SRC_DIR}"/hadrian
  "${CABAL}" v2-build -j hadrian 2>&1 | tee "${SRC_DIR}"/cabal-verbose.log
  _cabal_exit_code=${PIPESTATUS[0]}

  if [[ $_cabal_exit_code -ne 0 ]]; then
    echo "=== Cabal build FAILED with exit code ${_cabal_exit_code} ==="
    exit 1
  else
    echo "=== Cabal build SUCCEEDED ==="
  fi
popd

_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release+no_profiled_libs --docs=none --progress-info=none
"${_hadrian_build[@]}" stage1:exe:ghc-bin -V --flavour=release+no_profiled_libs --docs=none --progress-info=none
"${_hadrian_build[@]}" stage1:lib:ghc -V --flavour=release+no_profiled_libs --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
update_settings_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release+no_profiled_libs --docs=none --progress-info=none
# update_settings_link_flags "${settings_file}"
# set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release+no_profiled_libs --freeze1 --docs=none --progress-info=none
# update_settings_link_flags "${SRC_DIR}"/_build/stage1/lib/settings

# run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release+no_profiled_libs --freeze1 --docs=none --progress-info=none
"${_hadrian_build[@]}" stage2:exe:ghc-bin -V --flavour=release+no_profiled_libs --freeze1 --docs=none --progress-info=none
"${_hadrian_build[@]}" stage2:lib:ghc -V --flavour=release+no_profiled_libs --freeze1 --docs=none --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release+no_profiled_libs --freeze1 --freeze2 --docs=none --progress-info=none

update_installed_settings
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

cat "${settings_file}"

