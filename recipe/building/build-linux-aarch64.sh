#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# in 9.12+ we can use x86_64-conda-linux-gnu
ghc_host="x86_64-unknown-linux-gnu"
ghc_target="aarch64-unknown-linux-gnu"
conda_host="x86_64-conda-linux-gnu"
conda_target="aarch64-conda-linux-gnu"

update_link_flags() {
  local settings_file="$1"
  
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -v -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -v -L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|objdump|opt)\"#\"${conda_target}-\$1\"#" "${settings_file}"
}

_build_alias=${build_alias}
_host_alias=${host_alias}
export build_alias="${ghc_host}"
export host_alias="${ghc_host}"
export BUILD=${build_alias}
export HOST=${host_alias}

# Create environment and get library paths
echo "Creating environment for cross-compilation libraries..."
conda create -y \
    -n libc2.17_env \
    --platform linux-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap==9.6.7 \
    sysroot_linux-64==2.17

libc2_17_env=$(conda info --envs | grep libc2.17_env | awk '{print $2}')
ghc_path="${libc2_17_env}"/ghc-bootstrap/bin
export GHC="${ghc_path}"//ghc

"${ghc_path}"/ghc-pkg recache

export CONDA_BUILD_SYSROOT="${libc2_17_env}"/"${conda_host}"/sysroot
export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT}"
export CXXFLAGS="--sysroot=${CONDA_BUILD_SYSROOT}"
export LDFLAGS="--sysroot=${CONDA_BUILD_SYSROOT}"

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
  MergeObjsCmd="${conda_target}"-ld.gold
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

# Fix host configuration to use x86_64, target aarch64
settings_file="${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"
perl -pi -e "s#(conf-gcc-linker-args-stage[12].*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(conf-ld-linker-args-stage[12].*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(settings-c-compiler-link-flags.*?= )#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
perl -pi -e "s#(settings-ld-flags.*?= )#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# ---| Stage 1: Cross-compiler |---

# Disable copy for cross-compilation - force building the aarch64 binary
# Change the cross-compile copy condition to never match
perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs
run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_hsc2hs"  "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quickest --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
update_link_flags "${settings_file}"
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest --docs=none --progress-info=none
update_link_flags "${settings_file}"

# Redifine hadrian to avoid rebuilding via the build script
_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f -executable | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# Verify that stage 1 produces aarch64 exec
cat > /tmp/hello.hs << EOF
main = putStrLn "Hello conda-forge"
EOF
"${SRC_DIR}"/_build/ghc-stage1 /tmp/hello.hs -o /tmp/hello && file /tmp/hello | grep "ARM aarch64"

# ---| Stage 2: Cross-compiled bin/libs |---

export GHC="${SRC_DIR}"/_build/ghc-stage1

# Make sure we don't reference any bootstrap
# rm -rf "${libc2_17_env}"/ghc-bootstrap
# rm -rf _build/StageBoot

run_and_log "stage2_ghc-bin" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --docs=none --progress-info=none
file "${SRC_DIR}"/_build/stage1/bin/"${ghc_target}"-ghc | grep "ARM aarch64"
run_and_log "stage2_ghc-pkg" "${_hadrian_build[@]}" stage2:exe:ghc-pkg --flavour=release --docs=none --progress-info=none
run_and_log "stage2_hsc2hs" "${_hadrian_build[@]}" stage2:exe:hsc2hs --flavour=release --docs=none --progress-info=none

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze-libs --docs=none --progress-info=none
run_and_log "bindist"    "${_hadrian_build[@]}" binary-dist --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none --progress-info=none

# Now manually install from the bindist with correct configure arguments
bindist_dir=$(find "${SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${ghc_target}" -type d | head -1)
if [[ -n "${bindist_dir}" ]]; then
  pushd "${bindist_dir}"
    # Configure the binary distribution with proper cross-compilation settings
    CC="${conda_host}"-clang \
    CXX="${conda_host}"-clang++ \
    ./configure --prefix="${PREFIX}" --target="${ghc_target}"
 
    # Install
    run_and_log "make_install" make install
  popd
else
  echo "Error: Could not find binary distribution directory"
  exit 1
fi

# Correct CC/CXX
settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
if [[ -f "${settings_file}" ]]; then
  perl -pi -e 's#x86_64(-[^ \"]*)#aarch64$1#g' "${settings_file}"
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"
  perl -pi -e "s#\"[/\w]*?(ar|clang|clang\+\+|ld|ranlib|llc|opt)\"#\"${conda_target}-\$1\"#" "${settings_file}"
else
  echo "Error: Could not find settins file"
  exit 1
fi

# Create links of aarch64-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  for bin in ghc ghci ghc-pkg hp2ps hcs2ps; do
    ln -sf "${bin}" "${bin#${ghc_target}-}"
  done
popd

if [[ -d "${PREFIX}"/lib/${ghc_target}-ghc-"${PKG_VERSION}" ]]; then
  # $PREFIX/lib/aarch64-conda-linux-gnu-ghc-9.12.2 -> $PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${ghc_target}"-ghc-"${PKG_VERSION}"
fi
