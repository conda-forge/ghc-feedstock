#!/usr/bin/env bash
set -eu

_log_index=0
_debug=1

# Function to run a command, log its output, and increment log index
run_and_log() {
  local _logname="$1"
  shift
  local cmd=("$@")

  # Create log directory if it doesn't exist
  mkdir -p "${SRC_DIR}/_logs"

  echo " ";echo "|";echo "|";echo "|";echo "|"
  echo "Running: ${cmd[*]}"
  local start_time=$(date +%s)
  local exit_status_file=$(mktemp)
  # Run the command in a subshell to prevent set -e from terminating
  (
    # Temporarily disable errexit in this subshell
    set +e
    "${cmd[@]}" > "${SRC_DIR}/_logs/${_log_index}_${_logname}.log" 2>&1
    echo $? > "$exit_status_file"
  ) &
  local cmd_pid=$!
  local tail_counter=0

  # Periodically flush and show progress
  while kill -0 $cmd_pid 2>/dev/null; do
    sync
    echo -n "."
    sleep 5
    let "tail_counter += 1"

    if [ $tail_counter -ge 22 ]; then
      echo "."
      tail -5 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
      tail_counter=0
    fi
  done

  wait $cmd_pid || true  # Use || true to prevent set -e from triggering
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local exit_code=$(cat "$exit_status_file")
  rm "$exit_status_file"

  echo "."
  echo "─────────────────────────────────────────"
  printf "Command: %s\n" "${cmd[*]} in ${duration}s"
  echo "Exit code: $exit_code"
  echo "─────────────────────────────────────────"

  # Show more context on failure
  if [[ $exit_code -ne 0 ]]; then
    echo "COMMAND FAILED - Last 50 lines of log:"
    tail -50 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  else
    echo "COMMAND SUCCEEDED - Last 20 lines of log:"
    tail -20 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  fi

  echo "─────────────────────────────────────────"
  echo "Full log: ${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  echo "|";echo "|";echo "|";echo "|"

  let "_log_index += 1"
  return $exit_code
}

# Set environment variables
export MergeObjsCmd=${LD_GOLD:-${LD}}
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python

unset build_alias
unset host_alias

# Set up binary directory
mkdir -p binary _logs

# Install bootstrap GHC - Set conda platform moniker
pushd bootstrap-ghc
  if [[ "${target_platform}" == "win-64" ]]; then
    echo "No configure/install for this platform"
    export MSYSTEM=MINGW64
  else
    CC="${CC_FOR_BUILD}" \
    CXX="${CXX_FOR_BUILD}" \
    CPP="${CPP_FOR_BUILD:-${CPP}}" \
    LDFLAGS="${LDFLAGS//$PREFIX/$BUILD_PREFIX}" \
    run_and_log "bs-configure" bash configure --prefix="${SRC_DIR}"/binary
    run_and_log "bs-make-install" make install
  fi

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
    done
  fi
popd

# Add binary GHC to PATH
export PATH=$PWD/binary/bin:$PATH

# Install cabal-install
mkdir -p binary/bin
cp bootstrap-cabal/cabal* binary/bin/

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

# --- Start conda build with bootstrapping tools ---

case "${target_platform}" in
  linux-*)
    GHC_BUILD_STAGE0=x86_64-unknown-linux
    GHC_BUILD_STAGE1=x86_64-conda-linux-gnu
    _hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
    ;;
  osx-*)
    GHC_BUILD_STAGE0=x86_64-apple-darwin
    GHC_BUILD_STAGE1=x86_64-apple-darwin
    _hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")
    ;;
  default)
    GHC_BUILD_STAGE0=x86_64-w64-mingw32
    GHC_BUILD_STAGE1=x86_64-w64-mingw32
    _hadrian_build=("${SRC_DIR}"/hadrian/build.bat "-j")
    ;;
esac
run_and_log "build_toolchain" "${SRC_DIR}"/bootstrap-ghc/bin/ghc-toolchain-bin -t "${GHC_BUILD_STAGE1//13.4.0//}" -o "${SRC_DIR}"/hadrian/cfg/"${GHC_BUILD_STAGE1}".host.target.ghc-toolchain

# Set target-specific values
case "$target_platform" in
  linux-64)      GHC_TARGET=x86_64-conda-linux-gnu ;;
  linux-aarch64) GHC_TARGET=aarch64-conda-linux-gnu ;;
  osx-64)        GHC_TARGET=x86_64-apple-darwin13.4.0 ;;
  osx-arm64)     GHC_TARGET=arm64-apple-darwin20.0.0 ;;
  default)       GHC_TARGET=x86_64-w64-mingw32 ;;
esac
run_and_log "target_toolchain" "${SRC_DIR}"/bootstrap-ghc/bin/ghc-toolchain-bin -t "${GHC_TARGET//20.0.0//}" -o "${SRC_DIR}"/hadrian/cfg/"${GHC_TARGET}".target.ghc-toolchain

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="${GHC_BUILD_STAGE0}"
  --host="${GHC_BUILD_STAGE0}"
  --target="${GHC_TARGET:-${GHC_BUILD_STAGE0}}"
)

CONFIGURE_ARGS=(
  --prefix="${PREFIX}"
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
)
run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

# Prefer the ghc-toolchain configuration
if [[ -e "hadrian/cfg/default.target.ghc-toolchain" ]]; then
  cp "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain "${SRC_DIR}"/hadrian/cfg/default.target
fi

# Build and install using hadrian
if [[ "${target_platform}" == "osx-arm64" ]] && [[ "${_debug}" == "1" ]]; then
  "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
else
  run_and_log "stage1_exe" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release --docs=none --progress-info=none
fi

# Re-built stage1 with conda host convention
# SYSTEM_CONFIG=(
#   # GHC="${SRC_DIR}"/_build/stage0/bin/"${GHC_BUILD_STAGE1}"-ghc
#   --build="${GHC_BUILD_STAGE0}"
#   --host="${GHC_BUILD_STAGE0}"
#   --target="${GHC_TARGET:-${GHC_BUILD_STAGE1}}"
# )
# run_and_log "ghc-configure" bash configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"
if [[ -e "hadrian/cfg/default.target.ghc-toolchain" ]]; then
  diff "${SRC_DIR}"/hadrian/cfg/default.target "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain
  exit 1
  cp "${SRC_DIR}"/hadrian/cfg/default.target.ghc-toolchain "${SRC_DIR}"/hadrian/cfg/default.target
fi
run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "build_all"  "${_hadrian_build[@]}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs --progress-info=none

if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  CC="${CC_FOR_BUILD}" run_and_log "install_xcompiled" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs
else
  run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --freeze1 --freeze2 --docs=no-sphinx-pdfs
fi

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

# Run post-install
if [[ -n "${CROSSCOMPILING_EMULATOR:-}" ]]; then
  "${PREFIX}"/bin/ghc-pkg recache
  # run_and_log "recache" "${PREFIX}"/bin/ghc-pkg recache
else
  "${CROSSCOMPILING_EMULATOR}" "${PREFIX}"/bin/ghc-pkg recache
  # run_and_log "recache_xcompiled" "${CROSSCOMPILING_EMULATOR}" "${PREFIX}"/bin/ghc-pkg recache
fi
