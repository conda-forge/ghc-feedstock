#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PYTHON=python
export PATH="${_SRC_DIR}/bootstrap-ghc/bin:${_SRC_DIR}/bootstrap-cabal${PATH:+:}${PATH:-}"
export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# # Create .lib versions of required libraries
# mkdir -p "${_BUILD_PREFIX}/Library/lib/ghc-libs"
# for lib in mingw32 mingwex m pthread clang_rt.builtins; do
#   # Find the corresponding .a file
#   LIB_A=$(find "${_BUILD_PREFIX}" -name "lib${lib}.a" | head -1)
#
#   if [ -n "$LIB_A" ]; then
#     # Create a .lib symlink
#     cp "$LIB_A" "${_BUILD_PREFIX}/Library/lib/ghc-libs/${lib}.lib"
#   else
#     echo "Warning: Could not find lib${lib}.a"
#   fi
# done

find "${_BUILD_PREFIX}" -name "*clang_rt.builtins*{.lib,.a}"
LIBCLANG_RT_PATH=$(find "${_BUILD_PREFIX}" -name "*clang_rt.builtins*{.lib,.a}" | head -1)
if [[ ! -n "${LIBCLANG_RT_PATH}" ]]; then
  echo "Warning: Could not find libclang_rt.builtins"
  exit 1
fi
echo "${LIBCLANG_RT_PATH}"
LIBCLANG_DIR=$(dirname "${LIBCLANG_RT_PATH}")
LIBCLANG_RT=$(basename "${LIBCLANG_RT_PATH}")
if [ "$(basename "${LIBCLANG_DIR}")" != "x86_64-w64-windows-gnu" ]; then
  mkdir -p "$(dirname "${LIBCLANG_DIR}")/x86_64-w64-windows-gnu"
  cp "${LIBCLANG_DIR}/${LIBCLANG_RT}" "$(dirname "${LIBCLANG_DIR}")/x86_64-w64-windows-gnu/"
fi

# Define the wrapper script for MSVC
CLANG_WRAPPER="${BUILD_PREFIX}\\Library\\bin\\clang-mingw-wrapper.bat"
cat > "${_BUILD_PREFIX}/Library/bin/clang-mingw-wrapper.bat" << EOF
setlocal enabledelayedexpansion

set "args="
set "skip_next=0"

REM Process arguments and filter out problematic paths
for %%a in (%*) do (
  if "!skip_next!"=="1" (
    set "skip_next=0"
  ) else if "%%a"=="-I%SRC_DIR%\bootstrap-ghc\lib/../mingw//include" (
    REM Skip this include path
  ) else if "%%a"=="-L%SRC_DIR%\bootstrap-ghc\lib/../mingw//lib" (
    REM Skip this library path
  ) else if "%%a"=="-L%SRC_DIR%\bootstrap-ghc\lib/../mingw//x86_64-w64-mingw32/lib" (
    REM Skip this library path
  ) else (
    set "args=!args! %%a"
  )
)

"%BUILD_PREFIX%\Library\bin\clang.exe" !args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt -Wl,-defaultlib:%BUILD_PREFIX%\lib\clang\19\lib\windows\clang_rt.builtins-x86_64.lib
EOF

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
  # --host="x86_64-w64-mingw32"
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
run_and_log "stage1_exe-1" "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn || true

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=release --freeze1 --docs=none
