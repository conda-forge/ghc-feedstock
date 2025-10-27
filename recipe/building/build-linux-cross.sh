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

# Create environment and get library paths
echo "Creating environment for cross-compilation libraries..."
conda create -y \
    -n libc2.17_env \
    --platform linux-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    binutils_impl_linux-64==2.43 \
    ghc-bootstrap=="${PKG_VERSION}" \
    sysroot_linux-64==2.17

libc2_17_env=$(conda info --envs | grep libc2.17_env | awk '{print $2}')
ghc_path="${libc2_17_env}"/ghc-bootstrap/bin
export GHC="${ghc_path}"/ghc

"${ghc_path}"/ghc-pkg recache

conda_build_sysroot="${libc2_17_env}"/"${conda_host}"/sysroot
export CFLAGS="--sysroot=${conda_build_sysroot} ${CFLAGS}"
export CXXFLAGS="--sysroot=${conda_build_sysroot} ${CXXFLAGS}"
export LDFLAGS="--sysroot=${conda_build_sysroot} ${LDFLAGS}"

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
  ac_cv_lib_ffi_ffi_call=yes
  AR="${conda_target}"-ar
  AS="${conda_target}"-as
  CC="${conda_target}"-clang
  CXX="${conda_target}"-clang++
  LD="${conda_target}"-ld
  NM="${conda_target}"-nm
  OBJDUMP="${conda_target}"-objdump
  RANLIB="${conda_target}"-ranlib
  LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
)

run_and_log "ghc-configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# Fix host configuration to use x86_64, target cross
settings_file="${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"
perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# ---| Stage 1: Cross-compiler |---

# Disable copy for cross-compilation - force building the cross binary
# Change the cross-compile copy condition to never match
perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs
run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_hsc2hs"  "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quickest --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
update_linux_link_flags "${settings_file}"
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc -VV --flavour=quickest --docs=none --progress-info=none
update_linux_link_flags "${settings_file}"

# Redefine hadrian to avoid rebuilding via the build script
_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f -executable | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ---| Stage 2: Cross-compiled bin/libs |---

export GHC="${SRC_DIR}"/_build/ghc-stage1

run_and_log "stage2_ghc-bin" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --docs=none --progress-info=none
run_and_log "stage2_ghc-pkg" "${_hadrian_build[@]}" stage2:exe:ghc-pkg --flavour=release --docs=none --progress-info=none
run_and_log "stage2_hsc2hs" "${_hadrian_build[@]}" stage2:exe:hsc2hs --flavour=release --docs=none --progress-info=none

# This does not seem needed as the _build/stage1 libs are already cross
# We would have to modify the recipe in order to workaround the fact that the cross used
# by stage2 are cross (either by patches or by use of qemu)
# run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze-libs --docs=none --progress-info=none
run_and_log "bindist"    "${_hadrian_build[@]}" binary-dist --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none

# Now manually install from the bindist with correct configure arguments
bindist_dir=$(find "${SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)
if [[ -n "${bindist_dir}" ]]; then
  pushd "${bindist_dir}"
    # Configure the binary distribution with proper cross-compilation settings
    CC="${conda_host}"-clang \
    CXX="${conda_host}"-clang++ \
    ./configure --prefix="${PREFIX}" --target="${ghc_target}"
 
    # Install (update_package_db fails due to cross ghc-pkg)
    run_and_log "make_install" make install_bin install_lib install_man
  popd
else
  echo "Error: Could not find binary distribution directory"
  exit 1
fi

# Correct CC/CXX
settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
if [[ -f "${settings_file}" ]]; then
  perl -pi -e "s#${host_arch}(-[^ \"]*)#${target_arch}\$1#g" "${settings_file}"
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|opt)\"#\"${conda_target}-\$1\"#" "${settings_file}"
  cat "${settings_file}"
else
  echo "Error: Could not find settins file"
  exit 1
fi

# Create links of cross-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  for bin in ghc ghci ghc-pkg hp2ps hsc2hs; do
    if [[ -f "${ghc_target}-${bin}" ]] && [[ ! -f "${bin}" ]]; then
      ln -sf "${ghc_target}-${bin}" "${bin}"
    fi
  done
popd

if [[ -d "${PREFIX}"/lib/${ghc_target}-ghc-"${PKG_VERSION}" ]]; then
  # $PREFIX/lib/cross-conda-linux-gnu-ghc-9.12.2 -> $PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}"
fi
