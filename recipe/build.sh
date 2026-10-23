#!/bin/bash

set -exu

# Hadrian 9.2 races on DerivedConstants.h with many jobs
hadrian_jobs=$(( ${CPU_COUNT:-1} > 4 ? 4 : ${CPU_COUNT:-1} ))

export MergeObjsCmd=${LD_GOLD:-${LD}}
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python
export PATH=${BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}

export CABAL="${BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}/.cabal"

# Append $2 to the value of settings key $1 in file $3 (once)
append_setting() {
  KEY="$1" VAL="$2" perl -pi -e 's#("\Q$ENV{KEY}\E", ")([^"]*)#$1.$2.(index($2,$ENV{VAL})<0 ? " $ENV{VAL}" : "")#e' "$3"
}

# Use the prefixed conda tools in a GHC settings file
use_conda_tools() {
  TC="${CONDA_TOOLCHAIN_HOST}" perl -pi -e 's#"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)"#"$ENV{TC}-$1"#' "$1"
}

update_settings() {
  append_setting "C compiler flags" "${extra_cflags}" "$1"
  append_setting "C++ compiler flags" "${extra_cflags}" "$1"
  append_setting "C compiler link flags" "${extra_link}" "$1"
  append_setting "ld flags" "${extra_ld}" "$1"
  use_conda_tools "$1"
  if [[ "${target_platform}" == osx-* ]]; then
    perl -pi -e 's#("ar command", ")[^"]*#$1llvm-ar#; s#("ar flags", ")[^"]*#$1qcs#' "$1"
    TC="${CONDA_TOOLCHAIN_HOST}" perl -pi -e 's#("(clang|llc|opt|ranlib) command", ")[^"]*#$1$ENV{TC}-$2#' "$1"
  fi
}

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
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
HADRIAN_FLAGS=(--flavour=quick --docs=none --progress-info=none)

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
"${CABAL}" v2-update

if [[ "${target_platform}" == osx-* ]]; then
  # build_alias/host_alias interfere with configure scripts
  unset build_alias
  unset host_alias

  triple=x86_64-apple-darwin13.4.0
  extra_cflags="-fno-lto -Wno-strict-prototypes"
  extra_link="-fno-lto -Wl,-L${PREFIX}/lib -Wl,-liconv -Wl,-L${PREFIX}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat"
  extra_ld="-L${PREFIX}/lib -liconv -L${PREFIX}/lib/ghc-${PKG_VERSION}/lib -liconv_compat"

  # Shim so that linking against conda-forge libiconv resolves _iconv_open
  mkdir -p "${PREFIX}/lib/ghc-${PKG_VERSION}/lib"
  ${CC} -dynamiclib -o "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib" "${RECIPE_DIR}/osx_iconv_compat.c" \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -install_name "${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"

  export DYLD_INSERT_LIBRARIES="${PREFIX}/lib/libiconv.dylib:${PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"
  export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"

  # Only archiver that avoids mismatched arch errors when linking
  export AR=llvm-ar
  export ac_cv_path_ac_pt_CC=""
  export ac_cv_path_ac_pt_CXX=""
  export DEVELOPER_DIR=""
  for tool in AR CC CXX LD RANLIB; do
    export ac_cv_prog_${tool}="${!tool}"
    export ac_cv_path_${tool}="${!tool}"
  done

  update_settings "$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -n 1)"
  hadrian=("${SRC_DIR}"/hadrian/build "-j${hadrian_jobs}")
else
  arch=$(uname -m)
  triple="${arch}-unknown-linux"
  extra_cflags="-Wno-strict-prototypes"
  extra_link="-Wl,-L${BUILD_PREFIX}/lib -Wl,-L${PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
  extra_ld="-L${BUILD_PREFIX}/lib -L${PREFIX}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${PREFIX}/lib"

  export LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"

  (cd "${SRC_DIR}"/hadrian/ && ${CABAL} v2-build -j hadrian)
  hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f | head -1)
  hadrian=("${hadrian_bin}" "-j${hadrian_jobs}" --directory "${SRC_DIR}")
fi

# configure wrongly detects -no-pie support with clang, see fix-no-pie-detection-configure.patch
CONF_GCC_SUPPORTS_NO_PIE=YES ./configure --build="${triple}" --host="${triple}" "${CONFIGURE_ARGS[@]}"

if [[ "${target_platform}" == osx-* ]]; then
  system_config="${SRC_DIR}"/hadrian/cfg/system.config
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${system_config}"
  perl -pi -e 's#(=\s+)(ar)$#$1llvm-$2#' "${system_config}"
  perl -pi -e "s#(=\\s+)(clang|clang\\+\\+|llc|nm|opt|ranlib)\$#\$1${triple}-\$2#" "${system_config}"
  perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${system_config}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${system_config}"
fi

"${hadrian[@]}" stage1:exe:ghc-bin "${HADRIAN_FLAGS[@]}"
update_settings "${SRC_DIR}"/_build/stage0/lib/settings
# Generate RTS headers first; hadrian 9.2 does not order them before rts C compiles
"${hadrian[@]}" _build/stage1/lib/DerivedConstants.h _build/stage1/lib/ghcautoconf.h _build/stage1/lib/ghcplatform.h "${HADRIAN_FLAGS[@]}"
"${hadrian[@]}" stage1:lib:ghc "${HADRIAN_FLAGS[@]}"
update_settings "${SRC_DIR}"/_build/stage0/lib/settings
"${hadrian[@]}" stage2:exe:ghc-bin "${HADRIAN_FLAGS[@]}" --freeze1
update_settings "${SRC_DIR}"/_build/stage1/lib/settings
"${hadrian[@]}" stage2:lib:ghc "${HADRIAN_FLAGS[@]}" --freeze1
"${hadrian[@]}" install --prefix="${PREFIX}" "${HADRIAN_FLAGS[@]}" --freeze1 --freeze2

# Make the installed settings relocatable and drop build-time paths
settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
if [[ "${target_platform}" == osx-* ]]; then
  append_setting "C compiler flags" "-fno-lto" "${settings_file}"
  append_setting "C++ compiler flags" "-fno-lto" "${settings_file}"
  append_setting "C compiler link flags" '-v -fuse-ld=lld -fno-lto -fno-use-linker-plugin -Wl,-L$topdir/../../../lib -Wl,-rpath,$topdir/../../../lib -liconv -Wl,-L$topdir/../lib -Wl,-rpath,$topdir/../lib -liconv_compat' "${settings_file}"
  perl -pi -e 's#-undefined\s+dynamic_lookup##g; s#-dead_strip(_dylibs)?##g' "${settings_file}"
else
  topdir_arch='$topdir'/${arch}-linux-ghc-${PKG_VERSION}
  append_setting "C compiler link flags" "-Wl,-L${topdir_arch} -Wl,-rpath,${topdir_arch} -Wl,-L"'$topdir'"/../../../lib -Wl,-rpath,"'$topdir'"/../../../lib" "${settings_file}"
  append_setting "ld flags" "-L${topdir_arch} -rpath ${topdir_arch} -L"'$topdir'"/../../../lib -rpath "'$topdir'"/../../../lib" "${settings_file}"
  perl -pi -e 's#("C compiler supports -no-pie", ")[^"]*#$1YES#' "${settings_file}"
fi
for p in "${BUILD_PREFIX}" "${PREFIX}"; do
  perl -pi -e "s#(-Wl,-L|-Wl,-rpath,|-L|-rpath )${p}/lib(\\s|\"|\\))#\$2#g" "${settings_file}"
done
use_conda_tools "${settings_file}"
perl -pi -e "s#(${BUILD_PREFIX}|${PREFIX})/(bin|lib)/##g" "${settings_file}"

mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Package cache is invalid on installation, regenerated on activation
rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"

# Link dynamic libraries with the -ghc<version> suffix to their unsuffixed names
find "${PREFIX}/lib" -name "*-ghc${PKG_VERSION}.dylib" -o -name "*-ghc${PKG_VERSION}.so" | while read -r lib; do
  base_lib="${lib//-ghc${PKG_VERSION}./.}"
  if [[ ! -e "${base_lib}" ]]; then
    ln -s "$(basename "${lib}")" "${base_lib}"
  fi
done
