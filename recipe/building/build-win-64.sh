#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PYTHON=python
export MSYSTEM=MINGW64
export MSYS2_ARG_CONV_EXCL="*"
export PATH="$SRC_DIR"/bootstrap-ghc/bin:"$SRC_DIR"/bootstrap-cabal${PATH:+:}${PATH:-}

export BUILD_PREFIX="$(cygpath -w "${BUILD_PREFIX}")"
export PREFIX="$(cygpath -w "${PREFIX}")"
export SRC_DIR="$(cygpath -w "${SRC_DIR}")"

export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"
export GHC="${SRC_DIR}"/bootstrap-ghc/bin/ghc.exe

export CABAL="${SRC_DIR}"/bootstrap-cabal/cabal.exe
export LIBRARY_PATH="${BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

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

mkdir -p "${SRC_DIR}/hadrian/cfg"
touch "${SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"

# Remove this annoying mingw
#rm -rf "${SRC_DIR}"/bootstrap-ghc/mingw/clan*
#cp "${BUILD_PREFIX}"/bin/*clang* "${SRC_DIR}"/bootstrap-ghc/mingw/
perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-I\$topdir/../mingw//include##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-L\$topdir/../mingw//lib -L\$topdir/../mingw//x86_64-w64-mingw32/lib##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings

mkdir -p "${BUILD_PREFIX}"/bin
ln -s "${BUILD_PREFIX}"/Library/usr/bin/m4.exe "${BUILD_PREFIX}"/bin
cat "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

_hadrian_build=("${SRC_DIR}"/hadrian/build.bat)

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-w64-mingw32"
  # --host="x86_64-w64-mingw32"
  # --target="x86_64-w64-mingw32"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --disable-numa
  --enable-distro-toolchain
  --enable-ignore-build-platform-mismatch=yes
  --with-system-libffi=yes
  --with-curses-includes="${PREFIX}"/include
  --with-curses-libraries="${PREFIX}"/lib
  --with-ffi-includes="${PREFIX}"/include
  --with-ffi-libraries="${PREFIX}"/lib
  --with-gmp-includes="${PREFIX}"/include
  --with-gmp-libraries="${PREFIX}"/lib
  --with-iconv-includes="${PREFIX}"/include
  --with-iconv-libraries="${PREFIX}"/lib
)
# run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
AR_STAGE0=llvm-ar \
CC=clang \
CC_STAGE0=clang \
CFLAGS="${CFLAGS//-nostdlib/}" \
CXX=clang++ \
CXXFLAGS="${CXXFLAGS//-nostdlib/}" \
LDFLAGS="${LDFLAGS//-nostdlib/} -Wl,-defaultlib:msvcrt -Wl,-defaultlib:oldnames" \
MergeObjsCmd="x86_64-w64-mingw32-ld.exe" \
MergeObjsArgs="" \
run_and_log "ghc-configure" bash configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )

cat << EOF > hadrian/hadrian.settings
stage1.*.cabal.configure.opts += --verbose=3 --with-compiler="${SRC_DIR}"/bootstrap-ghc/bin/ghc.exe --with-gcc="${BUILD_PREFIX}"Library/bin/clang.exe
EOF

run_and_log "stage1_exe" bash "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn || ( cat "${SRC_DIR}"/libraries/directory/config.log ; exit 1 )

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --docs=none
