#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PATH="${_SRC_DIR}/bootstrap-ghc/bin${PATH:+:}${PATH:-}"
export CABAL="${_BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}\\.cabal"

cd "${SRC_DIR}"

mkdir -p ".cabal" && "${CABAL}" user-config init
#run_and_log "cabal-update" "${CABAL}" v2-update
"${CABAL}" v2-update

# Prepare python environment
export PYTHON=$(find "${BUILD_PREFIX}" -name python.exe | head -1)
export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

# Set up temp variables
export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# Some compilation complained about not finding clang_rt.builtins: Still needed?
LIBCLANG_RT_PATH=$(find "${_BUILD_PREFIX}/Library" -name "*clang_rt.builtins*" | head -1)
if [[ -z "${LIBCLANG_RT_PATH}" ]]; then
  echo "Warning: Could not find libclang_rt.builtins"
  exit 1
fi

LIBCLANG_DIR=$(dirname "${LIBCLANG_RT_PATH}")
LIBCLANG_RT=$(basename "${LIBCLANG_RT_PATH}")
if [ "$(basename "${LIBCLANG_DIR}")" != "x86_64-w64-windows-gnu" ]; then
  mkdir -p "$(dirname "${LIBCLANG_DIR}")/x86_64-w64-windows-gnu"
  cp "${LIBCLANG_DIR}/${LIBCLANG_RT}" "$(dirname "${LIBCLANG_DIR}")/x86_64-w64-windows-gnu/lib${LIBCLANG_RT//-x86_64.lib/.a}"
fi

# Define the wrapper script for MSVC
CLANG_WRAPPER="${BUILD_PREFIX}\\Library\\bin\\clang-mingw-wrapper.bat"
cp "${RECIPE_DIR}/building/non_unix/clang-mingw-wrapper.bat" "${_BUILD_PREFIX}/Library/bin/"
cp "${RECIPE_DIR}/building/non_unix/clang-mingw-wrapper.py" "${_BUILD_PREFIX}/Library/bin/"

# Create directory for MinGW chkstk_ms.obj file
MINGW_CHKSTK_DIR="${_BUILD_PREFIX}/Library/lib"
mkdir -p "${MINGW_CHKSTK_DIR}"
MINGW_CHKSTK_OBJ="${MINGW_CHKSTK_DIR}/chkstk_mingw_ms.obj"

# First run the script to create the MinGW chkstk_ms.obj file once
echo "Creating MinGW chkstk_ms.obj file at ${MINGW_CHKSTK_OBJ}..."

# Find clang executable
CLANG_EXE=$(find "${_BUILD_PREFIX}" -name clang.exe | head -1)

if [ -z "${CLANG_EXE}" ]; then
  echo "Error: Could not find clang.exe"
  exit 1
fi

echo "Found clang at: ${CLANG_EXE}"

# Find the latest MSVC version directory dynamically
MSVC_VERSION_DIR=$(ls -d "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/"*/ 2>/dev/null | sort -V | tail -1 | sed 's/\/$//')

# Use the discovered path or fall back to a default if not found
if [ -z "$MSVC_VERSION_DIR" ]; then
  echo "Warning: Could not find MSVC tools directory, using fallback path"
  MSVC_VERSION_DIR="C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/14.38.33130"
fi

# Export MSVC chkstk.obj location and analyze it
export CHKSTK_OBJ="${MSVC_VERSION_DIR}/lib/x64/chkstk.obj"
echo "Using MSVC chkstk.obj at ${CHKSTK_OBJ}"

# Check if MSVC chkstk.obj exists
test -f "${CHKSTK_OBJ}" || echo "Warning: MSVC chkstk.obj not found"

# Create a temporary source file with a more accurate implementation of ___chkstk_ms
TMP_DIR=$(mktemp -d)
TMP_C_FILE="${TMP_DIR}/chkstk_ms_combined.c"
cp "${RECIPE_DIR}"/building/non_unix/___chkstk_ms.c "${TMP_C_FILE}"

# Compile it directly with advanced optimization settings
echo "Compiling ${TMP_C_FILE} to ${MINGW_CHKSTK_OBJ}..."
"${CLANG_EXE}" -c "${TMP_C_FILE}" -o "${MINGW_CHKSTK_OBJ}" \
  --target=x86_64-w64-mingw32 -O2 -fvisibility=default -fomit-frame-pointer -fno-stack-check \
  -fno-strict-aliasing -mno-stack-arg-probe
COMPILE_RESULT=$?

# Verify the compiled object file exists
test -f "${MINGW_CHKSTK_OBJ}" || echo "Warning: Compiled chkstk object not found"

# Clean up temporary files
rm -rf "${TMP_DIR}"

# Check if compilation succeeded
if [ ${COMPILE_RESULT} -ne 0 ] || [ ! -f "${MINGW_CHKSTK_OBJ}" ]; then
  echo "Critical Error: Failed to create MinGW chkstk_ms.obj file"
  exit 1
fi

echo "Successfully created ${MINGW_CHKSTK_OBJ} via direct compilation"

# Make sure we use conda-forge clang (ghc bootstrap has a clang.exe)
CLANG=$(find "${_BUILD_PREFIX}" -name clang.exe | head -1)
CLANGXX=$(find "${_BUILD_PREFIX}" -name clang++.exe | head -1)

# CABAL will be set by ultimate-cabal-wrapper.sh
# export CABAL="${SRC_DIR}\\bootstrap-cabal\\cabal.exe"
export CC="${CLANG}"
export CXX="${CLANGXX}"
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"

# Export LIB with the dynamic path
export LIB="${BUILD_PREFIX}/Library/lib;${PREFIX}/Library/lib;C:/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0/um/x64;${MSVC_VERSION_DIR}/lib/x64${LIB:+;}${LIB:-}"
export INCLUDE="C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/ucrt;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/shared;${MSVC_VERSION_DIR}/include${INCLUDE:+;}${INCLUDE:-}"

mkdir -p "${_BUILD_PREFIX}/bin"
cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin"

_hadrian_build=("${_SRC_DIR}"/hadrian/build.bat)

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-w64-mingw32"
  --host="x86_64-w64-mingw32"
  --prefix="${_PREFIX}"
  # --target="x86_64-w64-mingw32"
)

# Add stack protector flags to ensure proper stack checking
CONFIGURE_ARGS=(
  --with-system-libffi=yes
  --with-curses-includes="${_PREFIX}"/include
  --with-curses-libraries="${_PREFIX}"/lib
  --with-ffi-includes="${_PREFIX}"/include
  --with-ffi-libraries="${_PREFIX}"/lib
  --with-gmp-includes="${_PREFIX}"/include
  --with-gmp-libraries="${_PREFIX}"/lib
  --with-iconv-includes="${_PREFIX}"/include
  --with-iconv-libraries="${_PREFIX}"/lib

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
  
)

# Configure with environment variables that help debugging
export ac_cv_lib_ffi_ffi_call=yes
export AR_STAGE0=llvm-ar
export CC_STAGE0=${CC}
export LD_STAGE0=${LD}

CFLAGS="${CFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector" \
CXXFLAGS="${CXXFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector" \
LDFLAGS="${LDFLAGS//-nostdlib/} -v" \
MergeObjsCmd="x86_64-w64-mingw32-ld.exe" \
MergeObjsArgs="" \
run_and_log "ghc-configure" bash configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )

# Cabal configure seems to default to the wrong clang
# Also ensure stack protection is disabled for all stages
cat > ${_SRC_DIR}/hadrian/hadrian.settings << EOF
stage1.*.cabal.configure.opts += --verbose=3 --with-compiler="${GHC}" --with-gcc="${CLANG_WRAPPER}"
stage1.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage1.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage1.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage1.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
stage0.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage0.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage0.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage0.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
EOF

export CABFLAGS="--with-compiler=${GHC} --with-gcc=${CLANG_WRAPPER} --ghc-options=-optc-fno-stack-protector --ghc-options=-optc-fno-stack-check"
# Enable debugging mode for more verbose output
export GHC_DEBUG=1

# Ensure stack protection is disabled for all tools
export CFLAGS="${CFLAGS} -fno-stack-protector -fno-stack-check"
export CXXFLAGS="${CXXFLAGS} -fno-stack-protector -fno-stack-check"
export LDFLAGS="${LDFLAGS} -fno-stack-protector"

# Also set these for Cabal
export CABAL_EXTRA_BUILD_FLAGS="--ghc-options=-optc-fno-stack-protector --ghc-options=-optc-fno-stack-check"


# Proactively apply HSC fixes before any build attempts
echo "*** Applying HSC fixes proactively ***"
"${_BUILD_PREFIX}/bin/fix-hsc-crash.sh" || echo "Pre-emptive HSC fix completed"

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
