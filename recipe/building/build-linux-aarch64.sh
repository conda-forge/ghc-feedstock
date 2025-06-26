#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Install bootstrap GHC - Set conda platform moniker
pushd "${SRC_DIR}"/bootstrap-ghc
  MergeCmdObj=$(find "${BUILD_PREFIX}" -type f -name "${CONDA_TOOLCHAIN_BUILD}"-ld.gold | head -n 1)

  MergeCmdObj=${MergeCmdObj:-${CONDA_TOOLCHAIN_BUILD}-ld} \
  AR=${CONDA_TOOLCHAIN_BUILD}-ar \
  AS=${CONDA_TOOLCHAIN_BUILD}-as \
  CC=${CC_FOR_BUILD} \
  CXX=${CXX_FOR_BUILD} \
  NM=${CONDA_TOOLCHAIN_BUILD}-nm \
  RANLIB=${CONDA_TOOLCHAIN_BUILD}-ranlib \
  run_and_log "bs-configure" bash configure --prefix="${SRC_DIR}"/binary
  perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' default.target
  # cp default.target.ghc-toolchain default.target
  run_and_log "bs-make-install" make install

  # Correct GHC settings (odd)
  perl -pi -e 's/(LLVM llvm-as command", ").+?"/$1llvm-as"/' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"
  perl -pi -e 's#((C++ compiler flags|C compiler link flags)", ")#$1--target=x86_64-unknown-linux --sysroot=$ENV{BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot #' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"
  perl -pi -e 's/aarch64/x86_64/;s/ArchAArch64/ArchX86_64/' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"

  # CLANG: workaround to GHC not adding gmp to its needed library paths
  perl -pi -e 's#(link flags", "(--target=x86_64-unknown-linux|-Wl,--no-as-needed))#$1 -Wl,-L$ENV{BUILD_PREFIX}/lib#' "${SRC_DIR}"/binary/lib/ghc-"${BOOT_VERSION}"/lib/settings
  grep 'link flags' "${SRC_DIR}"/binary/lib/ghc-"${BOOT_VERSION}"/lib/settings
  perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/binary/lib/ghc-"${BOOT_VERSION}"/lib/settings

  # Update rpath of bootstrap HShaskeline and HSterminfo
  find "${SRC_DIR}/binary/lib" -type f \( -name "*HShaskeline*.so" -o -name "*HSterminfo*.so" -o -name "ghc-${BOOT_VERSION}" \) | while read -r lib; do
    current_rpath=$(patchelf --print-rpath "$lib")
    patchelf --set-rpath "${BUILD_PREFIX}/lib" "${lib}"
    if [[ -n "${current_rpath}" ]]; then
      patchelf --add-rpath "${current_rpath}" "${lib}"
    fi
    patchelf --replace-needed libtinfo.so.6 "${BUILD_PREFIX}"/lib/libtinfo.so.6 "${lib}"
  done
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-conda-linux-gnu"
  --host="x86_64-conda-linux-gnu"
  --target="aarch64-conda-linux-gnu"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --enable-ignore-build-platform-mismatch=yes
  # --enable-ghc-toolchain=yes
  --disable-numa
  --with-system-libffi=yes
  --with-curses-includes="${BUILD_PREFIX}"/include
  --with-curses-libraries="${BUILD_PREFIX}"/lib
  --with-ffi-includes="${BUILD_PREFIX}"/include
  --with-ffi-libraries="${BUILD_PREFIX}"/lib
  --with-gmp-includes="${BUILD_PREFIX}"/include
  --with-gmp-libraries="${BUILD_PREFIX}"/lib
  --with-iconv-includes="${BUILD_PREFIX}"/include
  --with-iconv-libraries="${BUILD_PREFIX}"/lib
)
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=aarch64-unknown-linux","--sysroot=$ENV{BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot"#'  "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=x86_64-unknown-linux","--sysroot=$ENV{BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot"#'  "${SRC_DIR}"/hadrian/cfg/default.host.target
perl -pi -e 's/aarch64/x86_64/;s/ArchAArch64/ArchX86_64/' "${SRC_DIR}"/hadrian/cfg/default.host.target

run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/_build/stage0/lib/settings

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --enable-ignore-build-platform-mismatch=yes
  # --enable-ghc-toolchain=yes
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
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=aarch64-unknown-linux","--sysroot=$ENV{BUILD_PREFIX}/aarch64-conda-linux-gnu/sysroot"#'  "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=x86_64-unknown-linux","--sysroot=$ENV{BUILD_PREFIX}/x86_64-conda-linux-gnu/sysroot"#'  "${SRC_DIR}"/hadrian/cfg/default.host.target
perl -pi -e 's/aarch64/x86_64/;s/ArchAArch64/ArchX86_64/' "${SRC_DIR}"/hadrian/cfg/default.host.target
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release --freeze1 --docs=none --progress-info=none

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/_build/stage1/lib/settings

# GHC build ghc-pkg with '-fno-use-rpaths' but it requires libiconv.so.2
# _build/stage1/bin/ghc-pkg: error while loading shared libraries: libiconv.so.2
export LD_PRELOAD="${BUILD_PREFIX}/lib/libiconv.so.2 ${BUILD_PREFIX}/lib/libgmp.so.10 ${BUILD_PREFIX}/lib/libffi.so.8 ${BUILD_PREFIX}/lib/libtinfow.so.6 ${BUILD_PREFIX}/lib/libtinfo.so.6 ${LD_PRELOAD:-}"
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none

run_and_log "build_all"  "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none

# Create links of aarch64-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  for bin in aarch64-conda-linux-gnu-*; do
    ln -s "${bin}" "${bin#aarch64-conda-linux-gnu-}"
  done
popd

if [[ -d "${PREFIX}"/lib/aarch64-conda-linux-gnu-ghc-"${PKG_VERSION}" ]]; then
  # $CONDA_PREFIX/lib/aarch64-conda-linux-gnu-ghc-9.12.2 -> $CONDA_PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/aarch64-conda-linux-gnu-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/aarch64-conda-linux-gnu-ghc-"${PKG_VERSION}"
fi

pushd "${PREFIX}"/share/doc/aarch64-linux-ghc-"${PKG_VERSION}"-inplace
  for file in */LICENSE; do
    cp "${file///-}" "${SRC_DIR}"/license_files
  done
popd

perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##g' "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings
_lib_path='lib/ghc-'"${PKG_VERSION}"'/lib/aarch64-linux-ghc-'"${PKG_VERSION}"'-inplace'
perl -pi -e "s#(link flags\", \"--target=aarch64-conda-linux)#\$1 -L\\\$CONDA_PREFIX/${_lib_path} -Wl,-rpath=\\\$CONDA_PREFIX/${_lib_path} -Wl,-rpath-link=\\\$CONDA_PREFIX/${_lib_path}#g" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings
perl -pi -e "s#(compiler flags\", \"--target=aarch64-conda-linux)#\$1 -L\\\$CONDA_PREFIX/${_lib_path} -Wl,-rpath=\\\$CONDA_PREFIX/${_lib_path} -Wl,-rpath-link=\\\$CONDA_PREFIX/${_lib_path}#g" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings

cat "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings

# Find all the .so libs with the '-ghc9.12.2' extension and link them to non--ghc9.12.2
find "${PREFIX}/lib" -name "*-ghc${PKG_VERSION}.so" | while read -r lib; do
  base_lib="${lib%-ghc$PKG_VERSION.so}.so"
  if [[ ! -e "$base_lib" ]]; then
    ln -s "$(basename "$lib")" "$base_lib"
  fi
done