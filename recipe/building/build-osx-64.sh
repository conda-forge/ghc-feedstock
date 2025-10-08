#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

update_link_flags() {
  local settings_file="$1"
  local prefix="${2:$PREFIX}"
  
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
}

# This is needed as in seems to interfere with configure scripts
unset build_alias
unset host_alias

# Build dynamic versions with explicit SDK version for compatibility
# This ensures the object file matches the SDK version used during GHC linking
${CC} -c "${RECIPE_DIR}"/building/osx_iconv_compat.c -o "${RECIPE_DIR}"/building/iconv_compat.o -mmacosx-version-min=10.13
mkdir -p "${PREFIX}/lib/ghc-${PKG_VERSION}/lib"
${CC} -dynamiclib -o "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/libiconv_compat.dylib "${RECIPE_DIR}"/building/iconv_compat.c \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -install_name "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"

# Preload CONDA libraries to override system libraries
export DYLD_INSERT_LIBRARIES="${PREFIX}/lib/libiconv.dylib:${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"
export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
export AR=llvm-ar

settings_file=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -n 1)
update_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# Update cabal package database (now using conda-forge toolchain)
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


# # Install ld wrapper to surgically remove MacOSX15.5.sdk rpath contamination
# mv "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld.real
# cp "${RECIPE_DIR}"/building/ld-wrapper.sh "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld
# chmod +x "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld

# # Create symlinks for conda-forge toolchain (ghc-bootstrap is already configured above)
# ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-as "${BUILD_PREFIX}"/bin/as
# ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld "${BUILD_PREFIX}"/bin/ld
# ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ranlib "${BUILD_PREFIX}"/bin/ranlib

run_and_log "configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.host.target "${CONDA_TOOLCHAIN_BUILD}"
set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.target "${CONDA_TOOLCHAIN_BUILD}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# GHC selection of tools seems to fail to use conda-forge toolchain tools
rm -f /Users/runner/miniforge3/bin/{ar,ranlib,ld}

"${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
update_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest --docs=none --progress-info=none

update_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

"${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quickest --freeze1 --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage1/lib/settings
update_link_flags "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze1 --docs=none --progress-info=none

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none

settings_file=$(find "${PREFIX}" -name settings | head -n 1)
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib -liconv -Wl,-L\$topdir -Wl,-rpath,\$topdir -liconv_compat#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib -liconv -L\$topdir -rpath \$topdir -liconv_compat#" "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
