#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# in 9.12+ we can use x86_64-conda-linux-gnu
conda_host="${build_alias}"
conda_target="${host_alias}"
host_arch="${build_alias%%-*}"
target_arch="${host_alias%%-*}"

ghc_host="${host_arch}-unknown-linux-gnu"
ghc_target="${target_arch}-unknown-linux-gnu"

_build_alias=${build_alias}
_host_alias=${host_alias}
export build_alias="${ghc_host}"
export host_alias="${ghc_host}"

unset host_alias
unset HOST

# Create environment and get library paths
echo "Creating environment for cross-compilation libraries..."
conda create -y \
    -n libc2.17_env \
    --platform linux-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap==9.2.8 \
    libffi \
    libiconv \
    sysroot_linux-64==2.17

libc2_17_env=$(conda info --envs | grep libc2.17_env | awk '{print $2}')
ghc_path="${libc2_17_env}"/ghc-bootstrap/bin
export GHC="${ghc_path}"/ghc

"${GHC}" --version
"${ghc_path}"/ghc-pkg recache

export CABAL="${libc2_17_env}"/bin/cabal
export CABAL_DIR="${SRC_DIR}"/.cabal

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# Configure and build GHC
SYSTEM_CONFIG=(
  --target="${ghc_target}"
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
  
  ac_cv_path_AR="${BUILD_PREFIX}"/bin/"${conda_target}"-ar
  ac_cv_path_AS="${BUILD_PREFIX}"/bin/"${conda_target}"-as
  ac_cv_path_CC="${BUILD_PREFIX}"/bin/"${conda_target}"-clang
  ac_cv_path_CXX="${BUILD_PREFIX}"/bin/"${conda_target}"-clang++
  ac_cv_path_LD="${BUILD_PREFIX}"/bin/"${conda_target}"-ld
  ac_cv_path_NM="${BUILD_PREFIX}"/bin/"${conda_target}"-nm
  ac_cv_path_OBJDUMP="${BUILD_PREFIX}"/bin/"${conda_target}"-objdump
  ac_cv_path_RANLIB="${BUILD_PREFIX}"/bin/"${conda_target}"-ranlib
  ac_cv_path_LLC="${BUILD_PREFIX}"/bin/"${conda_target}"-llc
  ac_cv_path_OPT="${BUILD_PREFIX}"/bin/"${conda_target}"-opt
  
  LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
)

# Disable trying to use libc 2.20 (we use 2.17) - export since it is needed for the sub-packages configuration during the build
export AR_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ar"
export CC_STAGE0="${CC_FOR_BUILD}"
export LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"

export ac_cv_func_statx=no
export ac_cv_have_decl_statx=no
export ac_cv_lib_ffi_ffi_call=yes

CONF_GCC_SUPPORTS_NO_PIE=YES run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }

# Fix host configuration to use x86_64, target cross
(
  settings_file="${SRC_DIR}"/hadrian/cfg/system.config
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
  perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"
  perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  cat "${settings_file}"
)

# Build hadrian with cabal outside script
# CRITICAL: Modify ghc-bootstrap settings to add BUILD sysroot flags
# hsc2hs gets compiler config from GHC settings, not cabal config
bootstrap_settings="${libc2_17_env}/ghc-bootstrap/lib/ghc-9.2.8/settings"
if [[ -f "${bootstrap_settings}" ]]; then
  # Add --sysroot to C compiler flags
  perl -pi -e "s#(C compiler flags.*?= )#\$1--sysroot=${BUILD_PREFIX}/${conda_host}/sysroot #" "${bootstrap_settings}"
  # Add --sysroot to C compiler link flags
  perl -pi -e "s#(C compiler link flags.*?= )#\$1--sysroot=${BUILD_PREFIX}/${conda_host}/sysroot #" "${bootstrap_settings}"
  echo "=== Modified ghc-bootstrap settings ==="
  grep -E "C compiler flags|C compiler link flags" "${bootstrap_settings}"
fi

unset CONDA_BUILD_SYSROOT

pushd "${SRC_DIR}"/hadrian
  "${CABAL}" v2-build \
    --with-ar="${AR_STAGE0}" \
    --with-gcc="${CC_STAGE0}" \
    --with-ghc="${GHC}" \
    --with-ld="${LD_STAGE0}" \
    -j \
    hadrian \
    2>&1 | tee "${SRC_DIR}"/cabal-verbose.log
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

# ---| Stage 1: Cross-compiler |---

# Disable copy for cross-compilation - force building the cross binary
# Change the cross-compile copy condition to never match
perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs
run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quick --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
update_linux_link_flags "${settings_file}"
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quick --docs=none --progress-info=none
update_linux_link_flags "${settings_file}"

# ---| Stage 2: Cross-compiled bin/libs |---

export GHC="${SRC_DIR}"/_build/ghc-stage1

run_and_log "stage2_ghc-bin" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quick --docs=none --progress-info=none
run_and_log "stage2_ghc-pkg" "${_hadrian_build[@]}" stage2:exe:ghc-pkg --flavour=quick --docs=none --progress-info=none
run_and_log "stage2_hsc2hs" "${_hadrian_build[@]}" stage2:exe:hsc2hs --flavour=quick --docs=none --progress-info=none

# This does not seem needed as the _build/stage1 libs are already cross
# We would have to modify the recipe in order to workaround the fact that the cross used
# by stage2 are cross (either by patches or by use of qemu)
# run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=quick --freeze-libs --docs=none --progress-info=none
run_and_log "bindist"    "${_hadrian_build[@]}" binary-dist --prefix="${PREFIX}" --flavour=quick --freeze1 --freeze2 --docs=none --progress-info=none

# Now manually install from the bindist with correct configure arguments
bindist_dir=$(find "${SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)
if [[ -n "${bindist_dir}" ]]; then
  pushd "${bindist_dir}"
    # Configure the binary distribution with proper cross-compilation settings
    ac_cv_path_CC="${BUILD_PREFIX}"/bin/"${conda_host}"-clang \
    ac_cv_path_CXX="${BUILD_PREFIX}"/bin/"${conda_host}"-clang++ \
    ./configure --prefix="${PREFIX}" --host="${ghc_target}" --target="${ghc_target}" || { cat config.log; exit 1; }
 
    # Install (update_package_db fails due to cross ghc-pkg)
    run_and_log "make_install" make install_bin install_lib
  popd
else
  echo "Error: Could not find binary distribution directory"
  exit 1
fi

update_installed_settings

# Create links of cross-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  mv "${ghc_target}-ghc-pkg-${PKG_VERSION}" "${conda_target}-ghc-pkg-${PKG_VERSION}"
  rm -f "ghc-pkg" "${ghc_target}-ghc-pkg"
  ln -sf "${conda_target}-ghc-pkg-${PKG_VERSION}" "ghc-pkg"
  
  for bin in hp2ps hsc2hs; do
    if [[ -f "${ghc_target}-${bin}-ghc-${PKG_VERSION}" ]]; then
      rm -f "${conda_target}-${bin}-${PKG_VERSION}"
      mv "${ghc_target}-${bin}-ghc-${PKG_VERSION}" "${conda_target}-${bin}-ghc-${PKG_VERSION}"
      rm -f "${ghc_target}-${bin}"
      rm -f "${bin}"
      ln -sf "${conda_target}-${bin}-ghc-${PKG_VERSION}" "${bin}"
    fi
  done
popd

if [[ -d "${PREFIX}"/lib/${ghc_target}-ghc-"${PKG_VERSION}" ]] && [[ ! -d "${PREFIX}"/lib/ghc-"${PKG_VERSION}" ]]; then
  # $PREFIX/lib/cross-conda-linux-gnu-ghc-9.12.2 -> $PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}"
fi

# Create links of cross-conda-linux-gnu-xxx to xxx for ghc
pushd "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/bin
  ln -s "${ghc_target}-ghc-${PKG_VERSION}" ghc-"${PKG_VERSION}"
  ln -s "${ghc_target}-ghc-${PKG_VERSION}" ghc
popd
