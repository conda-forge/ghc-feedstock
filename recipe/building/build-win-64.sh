#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PYTHON=python
export MSYSTEM=MINGW64
export MSYS2_ARG_CONV_EXCL="*"
export PATH="$SRC_DIR"/bootstrap-ghc/bin:"$SRC_DIR"/bootstrap-cabal${PATH:+:}${PATH:-}

export TMP="$(cygpath -w "$TEMP")"
export TMPDIR="$(cygpath -w "$TEMP")"
export GHC="$(cygpath -w "$SRC_DIR")"/bootstrap-ghc/bin/ghc.exe
export CABAL="${SRC_DIR}"/bootstrap-cabal/cabal.exe

mkdir -p "${SRC_DIR}/hadrian/cfg"
touch "${SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"

# Remove this annoying mingw
#rm -rf "${SRC_DIR}"/bootstrap-ghc/mingw/clan*
#cp "${BUILD_PREFIX}"/bin/*clang* "${SRC_DIR}"/bootstrap-ghc/mingw/
perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-I\$topdir/../mingw//include##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-L\$topdir/../mingw//lib -L\$topdir/../mingw//x86_64-w64-mingw32/lib##g' "${SRC_DIR}"/bootstrap-ghc/lib/lib/settings

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
CC=clang \
MergeObjsArgs="" \
bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

pushd libraries/directory
  CC=clang \
  bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
  cabal build --verbose=3
popd
"${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --docs=none
