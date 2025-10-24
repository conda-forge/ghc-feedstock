#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

conda_host="${build_alias}"
conda_target="${host_alias}"

host_arch="${conda_host%%-*}"
target_arch="${conda_target%%-*}"

ghc_host="${conda_host/darwin*/darwin}"
ghc_target="${conda_target/darwin*/darwin}"

export build_alias="${conda_host}"
export host_alias="${conda_host}"
export target_alias="${conda_target}"

# Create environment and get library paths
echo "Creating environment for cross-compilation libraries..."
conda create -y \
    -n osx64_env \
    --platform osx-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap=="${PKG_VERSION}"

osx_64_env=$(conda info --envs | grep osx64_env | awk '{print $2}')
ghc_path="${osx_64_env}"/ghc-bootstrap/bin
export GHC="${ghc_path}"/ghc

"${ghc_path}"/ghc-pkg recache

export CABAL="${osx_64_env}"/bin/cabal
export CABAL_DIR="${SRC_DIR}"/.cabal

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# Configure and build GHC
SYSTEM_CONFIG=(
  --target="${target_alias}"
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
  ac_cv_lib_ffi_ffi_call=yes
  ac_cv_prog_CC="${BUILD_PREFIX}/bin/${conda_target}-clang"                                                                               \u2502
  ac_cv_prog_CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"                                                                            \u2502
  ac_cv_path_CC="${BUILD_PREFIX}/bin/${conda_target}-clang"                                                                               \u2502
  ac_cv_path_CXX="${BUILD_PREFIX}/bin/${conda_target}-clang++"                                                                            \u2502
  AR=llvm-ar
  # AS="${conda_target}"-as
  # CC="${conda_target}"-clang
  # CXX="${conda_target}"-clang++
  # LD="${conda_target}"-ld
  # NM="${conda_target}"-nm
  # OBJDUMP="${conda_target}"-objdump
  # RANLIB="${conda_target}"-ranlib
  LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
  CC_STAGE0="${CC_FOR_BUILD}"
)

run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }

# Fix host configuration to use x86_64, target cross
settings_file="${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"
perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

cat "${settings_file}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# ---| Stage 1: Cross-compiler |---

# Bug in ghc-bootstrap for libiconv2
perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${osx_64_env}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings

# This will not generate ghc-toolchain-bin or the .ghc-toolchain (possibly due to x-platform)
run_and_log "ghc-configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin -V --flavour=release --progress-info=unicorn
export CABFLAGS=(-v --enable-shared --enable-executable-dynamic -j)
(cd "${SRC_DIR}"/hadrian && "${CABAL}" v2-build -v3 clock)
"${_hadrian_build[@]}" stage1:exe:ghc-bin -V --flavour=release --progress-info=unicorn

"${SRC_DIR}"/_build/stage0/bin/arm64-apple-darwin20.0.0-ghc --version || { echo "Stage0 GHC failed to report version"; exit 1; }

# 9.12+: export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
# export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc -VV --flavour=release --docs=none --progress-info=unicorn
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all" "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none || true

# Create links of aarch64-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  for bin in arm64-apple-darwin20.0.0-*; do
    ln -s "${bin}" "${bin#arm64-apple-darwin20.0.0-}"
  done
popd

pushd "${PREFIX}"/lib
  if [[ -d arm64-apple-darwin20.0.0-ghc-"${PKG_VERSION}" ]]; then
    mv arm64-apple-darwin20.0.0-ghc-"${PKG_VERSION}" ghc-"${PKG_VERSION}"
    ln -s ghc-"${PKG_VERSION}" arm64-apple-darwin20.0.0-ghc-"${PKG_VERSION}"
  fi
popd
