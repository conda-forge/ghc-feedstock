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
    ghc-bootstrap==9.6.7 \
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

# PowerPC 64-bit little-endian: CRITICAL - Must use ABI v2
# Add -mabi=elfv2 to CFLAGS/CXXFLAGS BEFORE configure to ensure it's baked into settings
if [[ "${target_arch}" == "ppc64le" ]]; then
  export CFLAGS="${CFLAGS:-} -mabi=elfv2"
  export CXXFLAGS="${CXXFLAGS:-} -mabi=elfv2"
  echo "PowerPC64LE detected: Added -mabi=elfv2 to CFLAGS/CXXFLAGS"
fi

export ac_cv_func_statx=no
export ac_cv_have_decl_statx=no
export ac_cv_lib_ffi_ffi_call=yes
export ac_cv_func_posix_spawn_file_actions_addchdir_np=no
run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }

# PowerPC: Patch TARGET config files to add -mabi=elfv2
# GHC 9.10.2 has use-ghc-toolchain=NO, so it uses default.target, not .ghc-toolchain
# CRITICAL: Only patch TARGET config (default.target), NOT HOST config (default.host.target)
# The host.target is for BUILD platform (x86_64), not TARGET platform (ppc64le)
if [[ "${target_arch}" == "ppc64le" || "${target_arch}" == "powerpc64le" ]]; then
  for config_file in "${SRC_DIR}"/hadrian/cfg/default.target "${SRC_DIR}"/hadrian/cfg/*.ghc-toolchain; do
    if [[ -f "${config_file}" ]]; then
      echo "Patching ${config_file} to add -mabi=elfv2"
      # Add -mabi=elfv2 before -Qunused-arguments in prgFlags
      perl -pi -e 's/"-Qunused-arguments"/"-mabi=elfv2","-Qunused-arguments"/g' "${config_file}"
    fi
  done
fi

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
(
  pushd "${SRC_DIR}"/hadrian
    export CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} -march=nocona -mtune=haswell -ftree-vectorize -fPIC -fstack-protector-strong -fno-plt -O2 -ffunction-sections -pipe -isystem $PREFIX/include -fdebug-prefix-map=$SRC_DIR=/usr/local/src/conda/ghc-${PKG_VERSION} -fdebug-prefix-map=$PREFIX=/usr/local/src/conda-prefix"
    export LDFLAGS="-L${libc2_17_env}/${conda_host}/lib -L${libc2_17_env}/${conda_host}/sysroot/usr/lib ${LDFLAGS:-}"
    
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
)

echo ">$(find ${SRC_DIR}/hadrian/dist-newstyle -name hadrian -type f | head -1)<"
_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle -name hadrian -type f | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ---| Stage 1: Cross-compiler |---

# Disable copy for cross-compilation - force building the cross binary
# Change the cross-compile copy condition to never match
perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs
run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_hsc2hs"  "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quickest --docs=none --progress-info=none

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
update_linux_link_flags "${settings_file}"

# DEBUG: Dump settings file to verify -mabi=elfv2 is present
echo "=== DEBUG: Settings file after update_linux_link_flags ==="
grep -E "C compiler|C\+\+ compiler" "${settings_file}" || true
echo "=== END DEBUG ==="

# DEBUG: Also check Hadrian config files
echo "=== DEBUG: Hadrian config files ==="
if [ -f "${SRC_DIR}/hadrian/cfg/default.target" ]; then
  echo "--- default.target C compiler flags ---"
  grep -A 2 "tgtCCompiler" "${SRC_DIR}/hadrian/cfg/default.target" | head -5 || true
fi
echo "=== END DEBUG ==="

"${_hadrian_build[@]}" stage1:lib:ghc -VV --flavour=quickest --docs=none --progress-info=none
# run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc -VV --flavour=quickest --docs=none --progress-info=none
update_linux_link_flags "${settings_file}"

# ---| Stage 2: Cross-compiled bin/libs |---

export GHC="${SRC_DIR}"/_build/ghc-stage1
cat "${settings_file}"
"${_hadrian_build[@]}" stage2:exe:ghc-bin -VV --flavour=release --docs=none --progress-info=none
# run_and_log "stage2_ghc-bin" "${_hadrian_build[@]}" stage2:exe:ghc-bin -V --flavour=release --docs=none --progress-info=none
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
    ac_cv_path_CC="${BUILD_PREFIX}"/bin/"${conda_host}"-clang \
    ac_cv_path_CXX="${BUILD_PREFIX}"/bin/"${conda_host}"-clang++ \
    ./configure --prefix="${PREFIX}" --target="${ghc_target}" || { cat config.log; exit 1; }
 
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
