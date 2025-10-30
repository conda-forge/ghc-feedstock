#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

conda_host="${build_alias}"
conda_target="${host_alias}"

ghc_host="${conda_host/w64/unknown}"
ghc_target="${conda_target/w64/unknown}"
_build_alias=${build_alias}
_host_alias=${host_alias}

export build_alias="${ghc_host}"
export host_alias="${ghc_host}"

export PATH="${_BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}"
export CABAL="${_BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}\\.cabal"
export GHC="${BUILD_PREFIX}\\ghc-bootstrap\\bin\\ghc.exe"

echo "${PATH}"
echo "${WINDRES}"

cd "${SRC_DIR}"

mkdir -p ".cabal" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

# Prepare python environment
export PYTHON=$(find "${BUILD_PREFIX}" -name python.exe | head -1)
export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

# Set up temp variables
export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# Find the latest MSVC version directory dynamically
MSVC_VERSION_DIR=$(ls -d "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/"*/ 2>/dev/null | sort -V | tail -1 | sed 's/\/$//')

# Use the discovered path or fall back to a default if not found
if [ -z "$MSVC_VERSION_DIR" ]; then
  echo "Warning: Could not find MSVC tools directory, using fallback path"
  MSVC_VERSION_DIR="C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/14.38.33130"
fi

# Export LIB with the dynamic path
export LIB="${BUILD_PREFIX}/Library/lib;${PREFIX}/Library/lib;C:/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0/um/x64;${MSVC_VERSION_DIR}/lib/x64${LIB:+;}${LIB:-}"
export INCLUDE="C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/ucrt;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/shared;${MSVC_VERSION_DIR}/include${INCLUDE:+;}${INCLUDE:-}"

mkdir -p "${_BUILD_PREFIX}/bin"
cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin"

_hadrian_build=("${_SRC_DIR}"/hadrian/build.bat)

# Configure and build GHC
SYSTEM_CONFIG=(
  --host="${ghc_target}"
  --prefix="${_PREFIX}"
)

# Add stack protector flags to ensure proper stack checking
CONFIGURE_ARGS=(
  --enable-distro-toolchain
  --with-system-libffi=yes
  --with-curses-includes="${_PREFIX}"/Library/include
  --with-curses-libraries="${_PREFIX}"/Library/lib
  --with-ffi-includes="${_PREFIX}"/Library/include
  --with-ffi-libraries="${_PREFIX}"/Library/lib
  --with-gmp-includes="${_PREFIX}"/Library/include
  --with-gmp-libraries="${_PREFIX}"/Library/lib
  --with-iconv-includes="${_PREFIX}"/Library/include
  --with-iconv-libraries="${_PREFIX}"/Library/lib

  ac_cv_path_AR="${GCC_AR}"
  ac_cv_path_AS="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-as
  ac_cv_path_CC="${GCC}"
  ac_cv_path_CXX="${GXX}"
  ac_cv_path_LD="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-ld
  ac_cv_path_NM="${GCC_NM}"
  ac_cv_path_OBJDUMP="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-objdump
  ac_cv_path_RANLIB="${GCC_RANLIB}"
  ac_cv_path_LLC="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-llc
  ac_cv_path_OPT="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-opt
)

# Configure with environment variables that help debugging
export ac_cv_lib_ffi_ffi_call=yes

# export AR_STAGE0=llvm-ar
export AR_STAGE0=${GCC_AR}
export CC_STAGE0=${GCC}
export LD_STAGE0=${LD}

export WINDOWS_TOOLCHAIN_AUTOCONF=no

CFLAGS="${CFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector" \
CXXFLAGS="${CXXFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector" \
LDFLAGS="${LDFLAGS//-nostdlib/} -v" \
MergeObjsCmd="${LD}" \
MergeObjsArgs="" \
run_and_log "ghc-configure" bash configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )

# Also ensure stack protection is disabled for all stages
cat > ${_SRC_DIR}/hadrian/hadrian.settings << EOF
stage1.*.cabal.configure.opts += --verbose=3 --with-compiler="${GHC}"
stage1.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage1.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage1.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage1.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
stage0.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage0.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage0.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage0.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
EOF

export CABFLAGS="--with-compiler=${GHC} --ghc-options=-optc-fno-stack-protector --ghc-options=-optc-fno-stack-check"
# Enable debugging mode for more verbose output
export GHC_DEBUG=1

# Ensure stack protection is disabled for all tools
export CFLAGS="${CFLAGS} -fno-stack-protector -fno-stack-check"
export CXXFLAGS="${CXXFLAGS} -fno-stack-protector -fno-stack-check"
export LDFLAGS="${LDFLAGS} -fno-stack-protector"

# Build stage1 GHC
echo "*** Building stage1 GHC ***"

# Ensure cabal wrapper is in PATH for hadrian
echo "*** Final cabal PATH verification ***"
export PATH="${_BUILD_PREFIX}/bin:${PATH}"
which cabal > /dev/null || echo "WARNING: cabal not found in PATH"

"${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn || BUILD_RESULT=$?

# Check build result
if [[ "${BUILD_RESULT:-0}" -ne 0 ]]; then
    echo "Build failed with code ${BUILD_RESULT}"
    exit ${BUILD_RESULT}
fi

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=release --freeze1 --docs=none
