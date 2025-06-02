#!/usr/bin/env bash
set -eu

_log_index=0

# Function to run a command, log its output, and increment log index
run_and_log() {
  local _logname="$1"
  shift
  local cmd=("$@")

  echo "Running: ${cmd[*]}"
  "${cmd[@]}" > "${SRC_DIR}/_logs/${_log_index}_${_logname}.log" 2>&1 &
  local cmd_pid=$!
  # Counter to track when to display tail output
  local tail_counter=0
  # Periodically flush and show progress
  while kill -0 $cmd_pid 2>/dev/null; do
    sync
    echo -n "."
    sleep 10
    let "tail_counter += 1"
    # After 3 cycles (30 seconds), show log tail and reset counter
    if [ $tail_counter -ge 3 ]; then
      echo "."
      tail -5 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
      tail_counter=0
    fi
  done
  wait $cmd_pid
  local exit_code=$?

  echo ".";echo ".";echo ".";echo "."
  printf "[--- %s ---]" "${cmd[*]}"
  tail -50 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  echo "[---------------------------------------]"
  echo ".";echo ".";echo ".";echo "."

  let "_log_index += 1"

  if [[ $exit_code -ne 0 ]]; then
    echo "Command failed with exit code $exit_code"
    return $exit_code
  fi

  return 0
}

unset host_alias

# Set environment variables
export MergeObjsCmd=${LD_GOLD:-${LD}}
export CC=${CC}
export CXX=${CXX}
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python

# Set up binary directory
mkdir -p binary _logs

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  CC="${CC_FOR_BUILD}" \
  CXX="${CXX_FOR_BUILD}" \
  LDFLAGS="${LDFLAGS//$PREFIX/$BUILD_PREFIX}" \
  run_and_log "bs-configure" ./configure --prefix="${SRC_DIR}"/binary
  run_and_log "bs-make-install" make install

  if [[ "${build_platform}" == "linux-64" ]]; then
    # Find bootstrap HShaskeline and HSterminfo
    find "${SRC_DIR}/binary" -type f -name "*HShaskeline*.so" -o -name "*HSterminfo*.so" | while read lib; do
      # Check if this library has the RPATH we want to change
      current_rpath=$(patchelf --print-rpath "$lib" 2>/dev/null)
      patchelf --set-rpath "$BUILD_PREFIX/lib" "$lib"
      if [[ -n "$current_rpath" ]]; then
        patchelf --add-rpath "$current_rpath" "$lib"
      fi
      patchelf --replace-needed libtinfo.so.6 "$BUILD_PREFIX"/lib/libtinfo.so.6 "$lib"
      readelf -d "$lib"
    done
  fi
popd

# Add binary GHC to PATH
export PATH=$PWD/binary/bin:$PATH

# Install cabal-install
mkdir -p binary/bin
cp bootstrap-cabal/cabal binary/bin/

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

case "${target_platform}" in
  linux-*)
    GHC_BUILD=x86_64-unknown-linux
    GHC_HOST=x86_64-unknown-linux
    ;;
  osx-*)
    GHC_BUILD=x86_64-apple-darwin
    GHC_HOST=x86_64-apple-darwin
    ;;
esac

# Set target-specific values
case "$target_platform" in
  linux-64)      GHC_TARGET=x86_64-conda-linux-gnu ;;
  linux-aarch64) GHC_TARGET=aarch64-conda-linux-gnu ;;
  osx-64)        GHC_TARGET=x86_64-apple-darwin13.4.0 ;;
  osx-arm64)     GHC_TARGET=aarch64-apple-darwin20.0.0 ;;
esac

# Configure and build GHC
CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
  --build="${GHC_BUILD}"
  --host="${GHC_HOST}"
  --target="${GHC_TARGET}"
  --disable-numa
  --with-system-libffi=yes
  --with-ffi-includes="${PREFIX}"/include
  --with-ffi-libraries="${PREFIX}"/lib
  --with-gmp-includes="${PREFIX}"/include
  --with-gmp-libraries="${PREFIX}"/lib
  --with-curses-includes="${PREFIX}"/include
  --with-curses-libraries="${PREFIX}"/lib
)

run_and_log "ghc-configure" ./configure "${CONFIGURE_ARGS[@]}"

# Build and install using hadrian
run_and_log "stage1_exe" hadrian/build stage1:exe:ghc-bin -j"${CPU_COUNT}" --flavour=release --docs=none --progress-info=none
run_and_log "stage1_lib" hadrian/build stage1:lib:ghc -j"${CPU_COUNT}" --flavour=release --docs=none --progress-info=none
run_and_log "stage2_exe" hadrian/build stage2:exe:ghc-bin -j"${CPU_COUNT}" --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "stage2_lib" hadrian/build stage2:lib:ghc -j"${CPU_COUNT}" --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all"  hadrian/build -j"${CPU_COUNT}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none

if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  run_and_log "install" hadrian/build install -j"${CPU_COUNT}" --prefix="${PREFIX}" --flavour=release --docs=no-sphinx-pdfs
else
  run_and_log "install_xcompiled" CC="${CC_FOR_BUILD}" hadrian/build install -j"${CPU_COUNT}" --prefix="${PREFIX}" --flavour=release --docs=no-sphinx-pdfs
fi

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

# Run post-install
if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  run_and_log "recache_xcompiled" "${CROSSCOMPILING_EMULATOR}" "${PREFIX}"/bin/ghc-pkg recache
else
  run_and_log "recache" "${PREFIX}"/bin/ghc-pkg recache
fi
