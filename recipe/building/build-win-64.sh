#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PYTHON=python
export MSYSTEM=MINGW64
export MSYS2_ARG_CONV_EXCL="*"
export PATH="$SRC_DIR"/bootstrap-ghc/bin:"$SRC_DIR"/bootstrap-cabal${PATH:+:}${PATH:-}
export LIBRARY_PATH="${BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

export BUILD_PREFIX="$(cygpath -w "${BUILD_PREFIX}")"
export PREFIX="$(cygpath -w "${PREFIX}")"
export SRC_DIR="$(cygpath -w "${SRC_DIR}")"

export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# Make sure we use conda-forge clang (ghc bootstrap has a clang.exe)
CLANG=$(find "${BUILD_PREFIX}" -name clang.exe | head -1)
CLANGXX=$(find "${BUILD_PREFIX}" -name clang++.exe | head -1)

export CABAL="${SRC_DIR}"/bootstrap-cabal/cabal.exe
export CC="${CLANG}"
export CLANG_WRAPPER="${BUILD_PREFIX}/bin/clang-mingw-wrapper.bat"
export CXX="${CLANGXX}"
export GHC="${SRC_DIR}"/bootstrap-ghc/bin/ghc.exe

# Define the wrapper script for MSVC
cat > "${CLANG_WRAPPER}" << EOF
@echo off
"%CC%" %* -Wl,-libpath:"%BUILD_PREFIX%/Library/lib/ghc-libs" -Wl,-defaultlib:msvcrt -Wl,-defaultlib:oldnames -Wl,-defaultlib:libvcruntime -Wl,-defaultlib:libucrt
EOF

# Create .lib versions of required libraries
for lib in mingw32 mingwex m pthread clang_rt.builtins; do
  # Find the corresponding .a file
  LIB_A=$(find "${BUILD_PREFIX}" -name "lib${lib}.a" | head -1)

  if [ -n "$LIB_A" ]; then
    # Create a .lib symlink
    cp "$LIB_A" "${BUILD_PREFIX}/Library/lib/ghc-libs/${lib}.lib"
  else
    echo "Warning: Could not find lib${lib}.a"
  fi
done

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

mkdir -p "${SRC_DIR}/hadrian/cfg" && touch "${SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"

# Remove this annoying mingw
#rm -rf "${SRC_DIR}"/bootstrap-ghc/mingw/clan*
#cp "${BUILD_PREFIX}"/bin/*clang* "${SRC_DIR}"/bootstrap-ghc/mingw/
perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-I\$topdir/../mingw//include##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-L\$topdir/../mingw//lib -L\$topdir/../mingw//x86_64-w64-mingw32/lib##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings

mkdir -p "${BUILD_PREFIX}"/bin && ln -s "${BUILD_PREFIX}"/Library/usr/bin/m4.exe "${BUILD_PREFIX}"/bin

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

AR_STAGE0=llvm-ar \
CC_STAGE0=${CC} \
CFLAGS="${CFLAGS//-nostdlib/}" \
CXXFLAGS="${CXXFLAGS//-nostdlib/}" \
LDFLAGS="${LDFLAGS//-nostdlib/} -Wl,-defaultlib:msvcrt -Wl,-defaultlib:oldnames -Wl,-defaultlib:libvcruntime -Wl,-defaultlib:libucrt" \
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

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --docs=none
