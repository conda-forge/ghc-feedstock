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
export host_platform="${build_platform}"

# Create environment and get library paths
echo "Creating environment for cross-compilation libraries..."
conda create -y \
    -n osx64_env \
    --platform osx-64 \
    -c conda-forge \
    cabal==3.10.3.0 \
    ghc-bootstrap=="${PKG_VERSION}" \
    libffi \
    libiconv

osx_64_env=$(conda info --envs | grep osx64_env | awk '{print $2}')
ghc_path="${osx_64_env}"/ghc-bootstrap/bin

export GHC="${ghc_path}"/ghc

"${ghc_path}"/ghc-pkg recache

export CABAL="${osx_64_env}"/bin/cabal
export CABAL_DIR="${SRC_DIR}"/.cabal

mkdir -p "${CABAL_DIR}" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# Create iconv compatibility library for x86_64 build machine
mkdir -p "${BUILD_PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib
"${BUILD_PREFIX}"/bin/${conda_host}-clang -dynamiclib \
  -o "${BUILD_PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/libiconv_compat.dylib \
  "${RECIPE_DIR}"/building/osx_iconv_compat.c \
  -L"${BUILD_PREFIX}/lib" -liconv \
  -Wl,-rpath,"${BUILD_PREFIX}/lib" \
  -target x86_64-apple-darwin13.4.0 \
  -mmacosx-version-min=11.3 \
  -install_name "${BUILD_PREFIX}/lib/ghc-${PKG_VERSION}/lib/libiconv_compat.dylib"

# Configure and build GHC
export AR_STAGE0=$(find "${BUILD_PREFIX}" -name llvm-ar | head -1)

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
  
  ac_cv_prog_AR="${AR}"
  ac_cv_prog_AS="${AS}"
  ac_cv_prog_CC="${CC}"
  ac_cv_prog_CXX="${CXX}"
  ac_cv_prog_LD="${LD}"
  ac_cv_prog_NM="${NM}"
  # ac_cv_prog_OBJDUMP="${OBJDUMP:-objdump}"
  ac_cv_prog_RANLIB="${RANLIB}"
  
  ac_cv_path_ac_pt_AR="${AR}"
  ac_cv_path_ac_pt_NM="${NM}"
  # ac_cv_path_ac_pt_OBJDUMP="${OBJDUMP:-objdump}"
  ac_cv_path_ac_pt_RANLIB="${RANLIB}"

  ac_cv_prog_ac_ct_LLC="${conda_target}"-llc
  ac_cv_prog_ac_ct_OPT="${conda_target}"-opt

  CC_STAGE0="${CC_FOR_BUILD}"
  LD_STAGE0="${BUILD_PREFIX}/bin/${conda_host}-ld"
  
  AR="${BUILD_PREFIX}"/bin/"${conda_target}"-ar
  AS="${BUILD_PREFIX}"/bin/"${conda_target}"-as
  CC="${BUILD_PREFIX}"/bin/"${conda_target}"-clang
  CXX="${BUILD_PREFIX}"/bin/"${conda_target}"-clang++
  LD="${BUILD_PREFIX}"/bin/"${conda_target}"-ld
  NM="${BUILD_PREFIX}"/bin/"${conda_target}"-nm
  OBJDUMP="${BUILD_PREFIX}"/bin/"${conda_target}"-objdump
  RANLIB="${BUILD_PREFIX}"/bin/"${conda_target}"-ranlib
  
  CFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CFLAGS:-}"
  CPPFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CPPFLAGS:-}"
  CXXFLAGS="--sysroot=${CONDA_BUILD_SYSROOT} ${CXXFLAGS:-}"
  LDFLAGS="-L${PREFIX}/lib ${LDFLAGS:-}"
)

(
  run_and_log "configure" ./configure -v "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}" || { cat config.log; exit 1; }
)

# Fix host configuration to use x86_64, target cross
(
  settings_file="${SRC_DIR}"/hadrian/cfg/system.config
  perl -pi -e "s#${BUILD_PREFIX}/bin/##" "${settings_file}"
  perl -pi -e "s#(=\s+)(ar|clang|clang\+\+|llc|nm|objdump|opt|ranlib)\$#\$1${conda_target}-\$2#" "${settings_file}"
  perl -pi -e "s#(system-ar\s*?=\s).*#\$1${AR_STAGE0}#" "${settings_file}"
  perl -pi -e "s#(conf-cc-args-stage0\s*?=\s).*#\$1--target=${conda_host}#" "${settings_file}"
  perl -pi -e "s#(conf-gcc-linker-args-stage0\s*?=\s).*#\$1--target=${conda_host} -Wl,-L${BUILD_PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-gcc-linker-args-stage[12]\s*?=\s)#\$1-Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(conf-ld-linker-args-stage[12]\s*?=\s)#\$1-L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-c-compiler-link-flags\s*?=\s)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib #" "${settings_file}"
  perl -pi -e "s#(settings-ar-command\s*?=\s).*#\$1${conda_target}-ar#" "${settings_file}"
  perl -pi -e "s#(settings-ld-flags\s*?=\s)#\$1-L${BUILD_PREFIX}/lib -rpath ${BUILD_PREFIX}/lib -L${PREFIX}/lib -rpath ${PREFIX}/lib #" "${settings_file}"

  perl -pi -e "s#${conda_target}-(objdump)#\$1#" "${settings_file}"

  cat "${settings_file}"
)

# Bug in ghc-bootstrap for libiconv2
(
  bootstrap_settings="${osx_64_env}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/settings
  perl -pi -e "s#[^ ]+/usr/lib/libiconv2.tbd##" "${bootstrap_settings}"
  perl -pi -e "s#(C compiler flags\", \")#\$1-v -fno-lto #" "${bootstrap_settings}"
  perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${bootstrap_settings}"
  # Don't add -fuse-ld=lld during build (bootstrap compiler doesn't support it)
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${BUILD_PREFIX}/lib#" "${bootstrap_settings}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -fno-lto -L${BUILD_PREFIX}/lib#" "${bootstrap_settings}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR_STAGE0}#" "${bootstrap_settings}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1llvm-ranlib#" "${bootstrap_settings}"
  perl -pi -e "s#((llc|opt|clang) command\", \")[^\"]*#\$1${conda_host}-\$2#" "${bootstrap_settings}"
  cat "${bootstrap_settings}"

  # Add osx64_env lib path to ALL bootstrap package configurations so libffi/libiconv are found
  pkg_conf_dir="${osx_64_env}"/ghc-bootstrap/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d
  if [[ -d "${pkg_conf_dir}" ]]; then
    # Prepend osx64_env/lib to library-dirs in ALL package.conf files (x86_64 libraries searched first)
    for conf in "${pkg_conf_dir}"/*.conf; do
      if [[ -f "${conf}" ]] && grep -q "^library-dirs:" "${conf}"; then
        perl -pi -e "s#^(library-dirs:)(.*)#\$1 ${osx_64_env}/lib\$2#" "${conf}"
      fi
    done
    "${osx_64_env}"/ghc-bootstrap/bin/ghc-pkg --package-db="${pkg_conf_dir}" recache
  fi
)
# Build hadrian with cabal outside script
(
  pushd "${SRC_DIR}"/hadrian
    "${CABAL}" v2-build \
      --with-gcc="${CC_FOR_BUILD}" \
      --with-ar="${AR_STAGE0}" \
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

_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle/build -name hadrian -type f | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# ---| Stage 1: Cross-compiler |---

# Disable copy for cross-compilation - force building the cross binary
# Change the cross-compile copy condition to never match
( 
  export AR="${AR_STAGE0}"
  export AS="${BUILD_PREFIX}/bin/${conda_host}-as"
  export CC="${BUILD_PREFIX}/bin/${conda_host}-clang"
  export CXX="${BUILD_PREFIX}/bin/${conda_host}-clang++"
  export LD="${BUILD_PREFIX}/bin/${conda_host}-ld"
  export LDFLAGS="-L${BUILD_PREFIX}/lib ${LDFLAGS}"
  
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ar" "${BUILD_PREFIX}"/bin/ar
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-as" "${BUILD_PREFIX}"/bin/as
  ln -sf "${BUILD_PREFIX}/bin/${conda_host}-ld" "${BUILD_PREFIX}"/bin/ld
  
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' "${SRC_DIR}"/hadrian/src/Rules/Program.hs
  
  run_and_log "stage1_ghc-bin" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quick --progress-info=none || true
  run_and_log "stage1_ghc-pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quick --docs=none --progress-info=none
  run_and_log "stage1_hsc2hs"  "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quick --docs=none --progress-info=none
)

ls "${SRC_DIR}"/_build/stage0/bin
ghc=$(find "${SRC_DIR}"/_build/stage0/bin -name "*ghc" -type f | head -1)
echo "${ghc}" && "${ghc}" --version || { echo "Stage0 GHC failed to report version"; exit 1; }

(
  # export DYLD_INSERT_LIBRARIES="${BUILD_PREFIX}/lib/libiconv.dylib:${BUILD_PREFIX}/lib/libffi.dylib${DYLD_INSERT_LIBRARIES:+:}${DYLD_INSERT_LIBRARIES:-}"
  run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quick --docs=none --progress-info=none
)

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quick --freeze1 --docs=none --progress-info=none
"${_hadrian_build[@]}" binary-dist --flavour=quick --freeze1 --freeze2 --docs=none --progress-info=none

# Now manually install from the bindist with correct configure arguments
bindist_dir=$(find "${SRC_DIR}"/_build/bindist -name "ghc-${PKG_VERSION}-${conda_target}" -type d | head -1)
if [[ -n "${bindist_dir}" ]]; then
  pushd "${bindist_dir}"
    # Configure the binary distribution with proper cross-compilation settings
    ac_cv_path_CC="${BUILD_PREFIX}"/bin/"${conda_host}"-clang \
    ac_cv_path_CXX="${BUILD_PREFIX}"/bin/"${conda_host}"-clang++ \
    ./configure --prefix="${PREFIX}" --host="${ghc_target}" --target="${ghc_target}" || { cat config.log; exit 1; }
 
    # Install (update_package_db fails due to cross ghc-pkg)
    make install_bin install_lib
  popd
else
  echo "Error: Could not find binary distribution directory"
  exit 1
fi

# Correct CC/CXX
update_installed_settings

# Create links of cross-conda-linux-gnu-xxx to xxx
pushd "${PREFIX}"/bin
  if [[ -f "${ghc_target}-ghc-pkg-${PKG_VERSION}" ]] && [[ ! -f "${conda_target}-ghc-pkg-${PKG_VERSION}" ]]; then
    mv "${ghc_target}-ghc-pkg-${PKG_VERSION}" "${conda_target}-ghc-pkg-${PKG_VERSION}"
    rm -f "ghc-pkg" "${ghc_target}-ghc-pkg"
    ln -sf "${conda_target}-ghc-pkg-${PKG_VERSION}" "ghc-pkg"
  fi
  
  for bin in hp2ps hsc2hs; do
    if [[ -f "${conda_target}-${bin}-ghc-${PKG_VERSION}" ]]; then
      rm -f "${bin}"
      ln -sf "${conda_target}-${bin}-ghc-${PKG_VERSION}" "${bin}"
    elif [[ -f "${ghc_target}-${bin}-ghc-${PKG_VERSION}" ]]; then
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

if [[ -d "${PREFIX}"/lib/${conda_target}-ghc-"${PKG_VERSION}" ]] && [[ ! -d "${PREFIX}"/lib/ghc-"${PKG_VERSION}" ]]; then
  # $PREFIX/lib/cross-conda-linux-gnu-ghc-9.12.2 -> $PREFIX/lib/ghc-9.12.2
  mv "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}" "${PREFIX}"/lib/ghc-"${PKG_VERSION}"
  ln -sf "${PREFIX}"/lib/ghc-"${PKG_VERSION}" "${PREFIX}"/lib/"${conda_target}"-ghc-"${PKG_VERSION}"
fi

# Create links of cross-conda-linux-gnu-xxx to xxx for ghc
pushd "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/bin
  if [[ "${ghc_target}-ghc-${PKG_VERSION}" ]]; then
    ln -s "${ghc_target}-ghc-${PKG_VERSION}" ghc-"${PKG_VERSION}"
    ln -s "${ghc_target}-ghc-${PKG_VERSION}" ghc
  fi
  if [[ "${conda_target}-ghc-${PKG_VERSION}" ]]; then
    ln -s "${conda_target}-ghc-${PKG_VERSION}" ghc-"${PKG_VERSION}"
    ln -s "${conda_target}-ghc-${PKG_VERSION}" ghc
  fi
popd
