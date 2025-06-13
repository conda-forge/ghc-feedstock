#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export build_alias=x86_64-apple-darwin
export host_alias=x86_64-apple-darwin
export BUILD=x86_64-apple-darwin
export HOST=x86_64-apple-darwin

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  touch default.target.ghc-toolchain
  MergeCmdObj=${MergeCmdObj:-${CONDA_TOOLCHAIN_BUILD}-ld} \
  AR=${CONDA_TOOLCHAIN_BUILD}-ar \
  AS=${CONDA_TOOLCHAIN_BUILD}-as \
  CC=${CC_FOR_BUILD} \
  CXX=${CXX_FOR_BUILD} \
  NM=${CONDA_TOOLCHAIN_BUILD}-nm \
  RANLIB=${CONDA_TOOLCHAIN_BUILD}-ranlib \
  LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX/} \
  LDFLAGS_LD=${LDFLAGS_LD//$PREFIX/$BUILD_PREFIX/} \
  bash configure \
    --prefix="${SRC_DIR}"/binary \
    --build=x86_64-apple-darwin13.4.0 \
    --host=x86_64-apple-darwin13.4.0 \
    --target=x86_64-apple-darwin13.4.0

  # echo "|"; echo "|"; echo "|";
  # cat config.log
  # echo "|"; echo "|"; echo "|";
  # (grep osx ./* mk/* >/dev/tty)>&/dev/null || true
  # echo "|"; echo "|"; echo "|";
  # cat default.target
  perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' default.target
  run_and_log "bs-make-install" make install

  ls "${SRC_DIR}"/binary/lib
  ls "${SRC_DIR}"/binary/lib/*ghc-"${BOOT_VERSION}"/lib/

  # Correct GHC settings (odd)
  perl -pi -e 's/(LLVM llvm-as command", ").+?"/$1llvm-as"/' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"
  perl -pi -e 's#((C++ compiler flags|C compiler link flags)", ")#$1--target=x86_64-apple-darwin #' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"
  perl -pi -e 's/arm64-apple-darwin/x86_64-apple-darwin/g; s/20.0.0/13.4.0/g' "${SRC_DIR}"/binary/lib/ghc-"${BOOT_VERSION}"/lib/settings
  perl -pi -e 's/aarch64/x86_64/;s/ArchAArch64/ArchX86_64/' "${SRC_DIR}/binary/lib/ghc-${BOOT_VERSION}/lib/settings"
popd

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --target="arm64-apple-darwin20.0.0"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --disable-numa
  --enable-ignore-build-platform-mismatch=yes
  # This creates conflicts downstream: --enable-ghc-toolchain=yes
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

# This will not generate ghc-toolchain-bin or the .ghc-toolchain (possibly due to x-platform)
MergeCmdObj=${MergeCmdObj:-${CONDA_TOOLCHAIN_BUILD}-ld} \
AR=${CONDA_TOOLCHAIN_BUILD}-ar \
AS=${CONDA_TOOLCHAIN_BUILD}-as \
CC=${CC_FOR_BUILD} \
CXX=${CXX_FOR_BUILD} \
NM=${CONDA_TOOLCHAIN_BUILD}-nm \
RANLIB=${CONDA_TOOLCHAIN_BUILD}-ranlib \
LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX/} \
LDFLAGS_LD=${LDFLAGS_LD//$PREFIX/$BUILD_PREFIX/} \
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=aarch64-apple-darwin"#'  "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=x86_64-apple-darwin"#'  "${SRC_DIR}"/hadrian/cfg/default.host.target
perl -pi -e 's/aarch64/x86_64/;s/ArchAArch64/ArchX86_64/' "${SRC_DIR}"/hadrian/cfg/default.host.target

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none

"${SRC_DIR}"/_build/stage0/bin/arm64-apple-darwin20.0.0-ghc --version || { echo "Stage0 GHC failed to report version"; exit 1; }

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --disable-numa
  --enable-ignore-build-platform-mismatch=yes
  # This creates conflicts downstream: --enable-ghc-toolchain=yes
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

# This will not generate ghc-toolchain-bin or the .ghc-toolchain (possibly due to x-platform)
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
perl -pi -e 's#($ENV{BUILD_PREFIX}|$ENV{PREFIX})/bin/##' "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=aarch64-apple-darwin"#'  "${SRC_DIR}"/hadrian/cfg/default.target
perl -pi -e 's#"--target=[\w-]+"#"--target=x86_64-apple-darwin"#'  "${SRC_DIR}"/hadrian/cfg/default.host.target
perl -pi -e 's/aarch64/x86_64/;s/ArchAArch64/ArchX86_64/' "${SRC_DIR}"/hadrian/cfg/default.host.target

pushd rts
  echo ":"; echo ":"; echo ":";
  cp "${RECIPE_DIR}"/building/configure.sh ./configure
  ./configure --prefix="${PREFIX}" || { cat config.log;}
  echo ":"; echo ":"; echo ":";
popd

export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
"${_hadrian_build[@]}" stage1:lib:ghc -VV --flavour=release --docs=none --progress-info=unicorn

# run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc -VV --flavour=release --docs=none --progress-info=unicorn
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all"  "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none
