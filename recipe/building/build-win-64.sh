#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PATH="${_SRC_DIR}/bootstrap-ghc/bin:${_SRC_DIR}/bootstrap-cabal${PATH:+:}${PATH:-}"

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

# Create a temporary source file
TMP_DIR=$(mktemp -d)
TMP_C_FILE="${TMP_DIR}/chkstk_ms.c"

cat > "${TMP_C_FILE}" << 'EOF'
/* Custom implementation of __chkstk_ms for MinGW */
#include <stdint.h>
#define PAGE_SIZE 4096
void ___chkstk_ms(void) {
    unsigned char *probe;
    uintptr_t stack_ptr;
    __asm__("movq %%rsp, %0" : "=r" (stack_ptr));
    uintptr_t stack_size;
    __asm__("movq %%rax, %0" : "=r" (stack_size));
    if (stack_size <= PAGE_SIZE) {
        probe = (unsigned char*)(stack_ptr - stack_size);
        *probe = 0;
        return;
    }
    probe = (unsigned char*)(stack_ptr & ~(PAGE_SIZE - 1));
    while (stack_size > PAGE_SIZE) {
        probe -= PAGE_SIZE;
        *probe = 0;
        stack_size -= PAGE_SIZE;
    }
    probe -= stack_size;
    *probe = 0;
}
void __chkstk_ms(void) { ___chkstk_ms(); }
EOF

# Compile it directly
echo "Compiling ${TMP_C_FILE} to ${MINGW_CHKSTK_OBJ}..."
"${CLANG_EXE}" -c "${TMP_C_FILE}" -o "${MINGW_CHKSTK_OBJ}" --target=x86_64-w64-mingw32 -O2
COMPILE_RESULT=$?

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

export CABAL="${SRC_DIR}\\bootstrap-cabal\\cabal.exe"
export CC="${CLANG}"
export CXX="${CLANGXX}"
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"

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
export CHKSTK_OBJ="${MSVC_VERSION_DIR}/lib/x64/chkstk.obj"

ls "${MSVC_VERSION_DIR}/lib/x64/"

mkdir -p "${_SRC_DIR}/hadrian/cfg" && touch "${_SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"

# Remove this annoying mingw
#rm -rf "${_SRC_DIR}"/bootstrap-ghc/mingw/clan*
#cp "${_BUILD_PREFIX}"/bin/*clang* "${_SRC_DIR}"/bootstrap-ghc/mingw/
perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##g' "${_SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-I\$topdir/../mingw//include##g' "${_SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-L\$topdir/../mingw//lib -L\$topdir/../mingw//x86_64-w64-mingw32/lib##g' "${_SRC_DIR}"/bootstrap-ghc/lib/lib/settings

mkdir -p "${_BUILD_PREFIX}"/bin && ln -s "${_BUILD_PREFIX}"/Library/usr/bin/m4.exe "${_BUILD_PREFIX}"/bin

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

_hadrian_build=("${_SRC_DIR}"/hadrian/build.bat)

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-w64-mingw32"
  --host="x86_64-w64-mingw32"
  # --target="x86_64-w64-mingw32"
)

CONFIGURE_ARGS=(
  --prefix="${_PREFIX}"
  --disable-numa
  --enable-distro-toolchain
  --enable-ignore-build-platform-mismatch=yes
  --with-system-libffi=yes
  --with-curses-includes="${_PREFIX}"/include
  --with-curses-libraries="${_PREFIX}"/lib
  --with-ffi-includes="${_PREFIX}"/include
  --with-ffi-libraries="${_PREFIX}"/lib
  --with-gmp-includes="${_PREFIX}"/include
  --with-gmp-libraries="${_PREFIX}"/lib
  --with-iconv-includes="${_PREFIX}"/include
  --with-iconv-libraries="${_PREFIX}"/lib
)

AR_STAGE0=llvm-ar \
CC_STAGE0=${CC} \
CFLAGS="${CFLAGS//-nostdlib/}" \
CXXFLAGS="${CXXFLAGS//-nostdlib/}" \
LDFLAGS="${LDFLAGS//-nostdlib/}" \
MergeObjsCmd="x86_64-w64-mingw32-ld.exe" \
MergeObjsArgs="" \
run_and_log "ghc-configure" bash configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )

# Cabal configure seems to default to the wrong clang
cat > hadrian/hadrian.settings << EOF
stage1.*.cabal.configure.opts += --verbose=3 --with-compiler="${GHC}" --with-gcc="${CLANG_WRAPPER}"
EOF

export CABFLAGS="--with-compiler=${GHC} --with-gcc=${CLANG_WRAPPER}"
# run_and_log "stage1_exe-1" "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
"${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn || true

echo "*** Stage 1 GHC build clock logs. ***"
cat C:/cabal/logs/ghc-9.10.1/clock-0.8.4*.log
echo "*** Stage 1 GHC build clock logs. ***"

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=release --freeze1 --docs=none
