#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PATH="${_BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}:/c/Windows/System32"
export CABAL="${_BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}\\.cabal"
export _PYTHON="${_BUILD_PREFIX}/python.exe"
export GHC="${BUILD_PREFIX}\\ghc-bootstrap\\bin\\ghc.exe"
export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

# Bug in ghc-bootstrap
#WINDRES_PATH="${BUILD_PREFIX//\\/\\\\}\\\\Library\\\\bin\\\\${WINDRES}"
#perl -pi -e "s#WINDRES_CMD=.*windres\.exe#WINDRES_CMD=${WINDRES_PATH}#" "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat
perl -pi -e 's/findstr/C:\\Windows\\System32\\findstr/g' "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat

# Update Stage0 settings file with conda include paths for Windows build
settings_file="${_BUILD_PREFIX}/ghc-bootstrap/lib/settings"
if [[ -f "${settings_file}" ]]; then
  echo "=== Updating bootstrap settings with conda include paths ==="
  # Add -I flags to C compiler flags for ffi.h, gmp.h, etc.
  # CRITICAL: Use _PREFIX (Unix paths) NOT PREFIX (Windows paths with \b escape sequences)
  
  perl -pi -e "s#(C compiler command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  perl -pi -e "s#(Haskell CPP command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler command\", \")[^\"]*#\$1${CXX}#" "${settings_file}"
  perl -pi -e "s#(Merge objects command\", \")[^\"]*#\$1${LD}#" "${settings_file}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR}#" "${settings_file}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1${RANLIB}#" "${settings_file}"
  perl -pi -e "s#(dllwrap command\", \")[^\"]*#\$1false#" "${settings_file}"
  perl -pi -e "s#(windres command\", \")[^\"]*#\$1false#" "${settings_file}"
  
  perl -pi -e "s#-I\\\$tooldir/mingw/include#-I${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/include#g" "${settings_file}"
  
  perl -pi -e "s#(C compiler flags\", \")([^\"]*)#\$1\$2 ${CFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)#\$1\$2 ${CXXFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"
  perl -pi -e "s#(Haskell CPP flags\", \")[^\"]*#\$1-E -I${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/include -I${_PREFIX}/Library/include#" "${settings_file}"

  perl -pi -e "s#(C compiler link flags\", \")[^\"]*#\$1#" "${settings_file}"
  perl -pi -e "s#(ld is GNU ld\", \")[^\"]*#\$1NO#" "${settings_file}"
  
  grep "C compiler flags\|C++ compiler flags" "${settings_file}"
else
  echo "WARNING: Stage0 settings file not found at ${settings_file}"
fi
cat "${settings_file}"

cd "${SRC_DIR}"

# Clean any stale .cabal directory that might have permission issues
# This prevents "you don't have permission to modify this file" errors on package.cache
echo "=== Cleaning stale .cabal directory to prevent permission issues ==="
rm -rf "${SRC_DIR}/.cabal" || true
rm -rf "${HOME}/.cabal" || true

mkdir -p ".cabal" && "${CABAL}" user-config init

# Configure Cabal to use single-threaded builds on Windows to avoid race conditions
# This prevents parallel ghc-pkg updates from conflicting on package.cache
# echo "=== Configuring Cabal for single-threaded builds ==="
# echo "jobs: 1" >> "${SRC_DIR}/.cabal/config"

run_and_log "cabal-update" "${CABAL}" v2-update

# Set up temp variables
export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# # Find the latest MSVC version directory dynamically
# MSVC_VERSION_DIR=$(ls -d "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/"*/ 2>/dev/null | sort -V | tail -1 | sed 's/\/$//')
# 
# # Use the discovered path or fall back to a default if not found
# if [ -z "$MSVC_VERSION_DIR" ]; then
#   echo "Warning: Could not find MSVC tools directory, using fallback path"
#   MSVC_VERSION_DIR="C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/14.38.33130"
# fi
# 
# # Export LIB with the dynamic path
# export LIB="${BUILD_PREFIX}/Library/lib;${PREFIX}/Library/lib;C:/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0/um/x64;${MSVC_VERSION_DIR}/lib/x64${LIB:+;}${LIB:-}"
# 
# # Export INCLUDE with conda libraries FIRST (for ffi.h, gmp.h, iconv.h, etc.)
# export INCLUDE="${PREFIX}/Library/include;${BUILD_PREFIX}/Library/include;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/ucrt;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/shared;${MSVC_VERSION_DIR}/include${INCLUDE:+;}${INCLUDE:-}"

mkdir -p "${_BUILD_PREFIX}/bin"
cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin"

# Configure and build GHC
SYSTEM_CONFIG=(
  --prefix="${_PREFIX}"
)

# Add stack protector flags to ensure proper stack checking
CONFIGURE_ARGS=(
  --enable-distro-toolchain
  --with-system-libffi=yes
  --with-intree-gmp=no
  --with-curses-includes="${_PREFIX}"/Library/include
  --with-curses-libraries="${_PREFIX}"/Library/lib
  --with-ffi-includes="${_PREFIX}"/Library/include
  --with-ffi-libraries="${_PREFIX}"/Library/lib
  --with-gmp-includes="${_PREFIX}"/Library/include
  --with-gmp-libraries="${_PREFIX}"/Library/lib
  --with-iconv-includes="${_PREFIX}"/Library/include
  --with-iconv-libraries="${_PREFIX}"/Library/lib
)

# Configure with environment variables that help debugging
export ac_cv_lib_ffi_ffi_call=yes

# Force use of conda-provided toolchain and libraries (not inplace MinGW)
export UseSystemMingw=YES
export WindowsToolchainAutoconf=NO
export WINDOWS_TOOLCHAIN_AUTOCONF=no

# Force use of system libffi (conda-provided)
export UseSystemFfi=YES
export ac_cv_use_system_libffi=yes
export ac_cv_prog_cc_c99=""

export CXX_STD_LIB_LIBS="stdc++"

# Configure Clang for MinGW cross-compilation
# CRITICAL: Clang needs explicit target, sysroot, and include paths
export CFLAGS="-I${BUILD_PREFIX}/Library/include -I/C/Program Files\ \(x86\)/Windows\ Kits/10/Include/10.0.26100.0/um -I${BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/include ${CFLAGS:-}"
export CXXFLAGS="-I${BUILD_PREFIX}/Library/include -I/C/Program Files\ \(x86\)/Windows\ Kits/10/Include/10.0.26100.0/um -I${BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/include ${CXXFLAGS:-}"
export LDFLAGS="-nostdlib -L${BUILD_PREFIX}/Library/lib -L/c/Program Files\ \(x86\)/Windows\ Kits/10/Lib/10.0.26100.0/um/x64 -L${BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib"

(
  CFLAGS_CONFIGURE=$(echo "${CFLAGS}" | sed 's/-nostdlib//g' | sed 's/--target=x86_64-w64-mingw32//g')
  CXXFLAGS_CONFIGURE=$(echo "${CXXFLAGS}" | sed 's/-nostdlib//g' | sed 's/--target=x86_64-w64-mingw32//g')
  LDFLAGS_CONFIGURE=$(echo "${LDFLAGS}" | sed 's/-nostdlib//g')
  
  CFLAGS="-fms-extensions -fdeclspec ${CFLAGS_CONFIGURE}" \
  CXXFLAGS="-fms-extensions -fdeclspec ${CXXFLAGS_CONFIGURE}" \
  LDFLAGS="${LDFLAGS_CONFIGURE}" \
  MergeObjsCmd="${LD}" \
  MergeObjsArgs="" \
  run_and_log "ghc-configure" ./configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )
)
cat "${_SRC_DIR}"/hadrian/cfg/system.config

# Fix Python path in system.config (configure sets Linux path, we need Windows)
# Use forward slashes to avoid escape sequence issues (\n, \t, \b, etc.)
perl -pi -e "s#(^python\\s*=).*#\$1 ${_PYTHON}#" "${_SRC_DIR}"/hadrian/cfg/system.config
echo "=== Converting FFI paths to Windows format in system.config ==="
perl -pi -e 's#^ffi-include-dir\s*=\s*/c/#ffi-include-dir   = C:/#' "${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^ffi-lib-dir\s*=\s*/c/#ffi-lib-dir       = C:/#' "${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^([a-z-]+dir)\s*=\s*/c/#$1 = C:/#g' "${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#^(intree-gmp\s*=\s*).*#\$1NO#" "${SRC_DIR}"/hadrian/cfg/system.config

echo "=== Forcing system toolchain and libffi settings ==="
# Force use of conda toolchain (not inplace MinGW)
perl -pi -e 's#^use-system-mingw\s*=\s*.*$#use-system-mingw = YES#' "${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^windows-toolchain-autoconf\s*=\s*.*$#windows-toolchain-autoconf = NO#' "${SRC_DIR}"/hadrian/cfg/system.config
# Force use of conda libffi
perl -pi -e 's#^use-system-ffi\s*=\s*.*$#use-system-ffi = YES#' "${SRC_DIR}"/hadrian/cfg/system.config

cat "${SRC_DIR}"/hadrian/cfg/system.config | grep "include-dir\|lib-dir\|windres\|dllwrap\|system-mingw\|system-ffi"

# Ensure CFLAGS/CXXFLAGS include conda headers for the build phase too
# export CFLAGS="${CFLAGS} -fno-stack-protector -fno-stack-check -I${PREFIX}/Library/include -I${BUILD_PREFIX}/Library/include"
# export CXXFLAGS="${CXXFLAGS} -fno-stack-protector -fno-stack-check -I${PREFIX}/Library/include -I${BUILD_PREFIX}/Library/include"
# export LDFLAGS="${LDFLAGS} -fno-stack-protector"
# export CABFLAGS="--with-compiler=${GHC} --ghc-options=-optc-fno-stack-protector --ghc-options=-optc-fno-stack-check"
# Enable debugging mode for more verbose output
# export GHC_DEBUG=1

# Fix MinGW-w64 pseudo relocation errors on Windows
# lld doesn't support GCC-generated relocation type 0xe (IMAGE_REL_AMD64_ADDR32NB)
# Solution: Use static linking for ghc.exe to avoid DLL relocation issues
mkdir -p ${_SRC_DIR}/_build
# cat > ${_SRC_DIR}/_build/hadrian.settings << EOF
# stage1.ghc-bin.ghc.link.opts += -optl-static
# stage1.ghc-pkg.ghc.link.opts += -optl-static
# stage1.hsc2hs.ghc.link.opts += -optl-static
# EOF

(
  pushd "${SRC_DIR}"/hadrian
    export CFLAGS="--target=x86_64-w64-mingw32 -I${BUILD_PREFIX}/Library/include -I${BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/include ${CFLAGS}"
    export CXXFLAGS="--target=x86_64-w64-mingw32 -I${BUILD_PREFIX}/Library/include -I${BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/include ${CXXFLAGS}"
    
    "${CABAL}" v2-build -j hadrian 2>&1 | tee "${SRC_DIR}"/cabal-verbose.log
    _cabal_exit_code=${PIPESTATUS[0]}

    if [[ $_cabal_exit_code -ne 0 ]]; then
      echo "=== Cabal build FAILED with exit code ${_cabal_exit_code} ==="
      exit 1
    else
      echo "=== Cabal build SUCCEEDED ==="
    fi
  popd
)

echo ">$(find ${SRC_DIR}/hadrian/dist-newstyle -name hadrian{,.exe} -type f | head -1)<"
_hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle -name hadrian{,.exe} -type f | head -1)
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${SRC_DIR}")

# Build stage1 GHC
echo "*** Building stage1 GHC ***"

# Ensure cabal wrapper is in PATH for hadrian
echo "*** Final cabal PATH verification ***"
export PATH="${_BUILD_PREFIX}/bin:${PATH}"
grep -A 10 "include-dirs:" rts/rts.cabal.in

run_and_log "stage1_ghc" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none
# "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none
settings_file="${_SRC_DIR}"/_build/stage0/lib/settings
if [[ -f "${settings_file}" ]]; then
  echo "=== Updating Stage0 settings with conda include paths ==="
  # Add -I flags to C compiler flags for ffi.h, gmp.h, etc.
  # CRITICAL: Use _PREFIX (Unix paths) NOT PREFIX (Windows paths with \b escape sequences)
  perl -pi -e "s#(C compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  grep "C compiler flags\|C++ compiler flags" "${settings_file}"
else
  echo "WARNING: Stage0 settings file not found at ${settings_file}"
fi

run_and_log "stage1_pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_hs" "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest --docs=none --progress-info=none || { \
  echo "=== Checking if Hadrian patch was applied ==="; \
  grep -A 3 "interpolateSetting.*FFIIncludeDir" "${SRC_DIR}"/hadrian/src/Rules/Generate.hs || echo "ERROR: Hadrian patch NOT applied!"; \
  grep -n "include-dirs\|extra-include-dirs\|/c/bld" "${SRC_DIR}"/rts/rts.cabal | head -20; \
  exit 1; \
}
  
# perl -pi -e "s#((dllwrap|windres|llc|opt|clang) command\", \")[^\"]*#\$1${conda_target}-\$2#" "${settings_file}"
perl -pi -e "s#(Use inplace MinGW toolchain\", \")[^\"]*#\$1NO#" "${settings_file}"
perl -pi -e "s#(Use LibFFI\", \")[^\"]*#\$1YES#" "${settings_file}"

echo "=== Redirecting mingw paths to conda-forge in Stage0 settings ==="
# Reassign mingw references to conda-forge MinGW (same as ghc-bootstrap)
perl -pi -e 's#\$topdir/../mingw//bin/(llvm-)?##' "${settings_file}"
perl -pi -e 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${settings_file}"
perl -pi -e 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${settings_file}"
perl -pi -e 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${settings_file}"

cat "${_SRC_DIR}"/_build/stage0/lib/settings | grep -A1 "mingw\|C compiler\|LibFFI"

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=release --freeze1 --docs=none --progress-info=none

# Patch Stage1 settings file (created by stage2:exe:ghc-bin)
settings_file="${_SRC_DIR}"/_build/stage1/lib/settings
if [[ -f "${settings_file}" ]]; then
  echo "=== Redirecting mingw paths in Stage1 settings ==="
  perl -pi -e "s#((dllwrap|windres|llc|opt|clang) command\", \")[^\"]*#\$1${conda_target}-\$2#" "${settings_file}"
  perl -pi -e "s#(Use inplace MinGW toolchain\", \")[^\"]*#\$1NO#" "${settings_file}"
  perl -pi -e "s#(Use LibFFI\", \")[^\"]*#\$1YES#" "${settings_file}"
  perl -pi -e 's#\$topdir/../mingw//bin/(llvm-)?##' "${settings_file}"
  perl -pi -e 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${settings_file}"
  perl -pi -e 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${settings_file}"
  perl -pi -e 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${settings_file}"

  perl -pi -e 's#(ld flags", ")#\1#' "${settings_file}"  # Keep empty for now
  perl -pi -e 's#(C compiler link flags", ")#\1-static #' "${settings_file}"  # Static linking for user programs

  echo "=== Stage1 settings after patching (COMPLETE FILE) ==="
  cat "${settings_file}"

  # Test if ghc.exe can actually run
  echo "=== Testing Stage1 ghc.exe ==="
  ghc_exe="${_SRC_DIR}/_build/stage1/bin/ghc.exe"
  if [[ -f "${ghc_exe}" ]]; then
    echo "Running: ${ghc_exe} --version"
    "${ghc_exe}" --version 2>&1 || {
      exit_code=$?
      echo "ERROR: ghc.exe failed with exit code ${exit_code}"
      echo "Trying with --numeric-version:"
      "${ghc_exe}" --numeric-version 2>&1 || echo "ERROR: --numeric-version also failed"
      echo "Trying with --info:"
      "${ghc_exe}" --info 2>&1 || echo "ERROR: --info also failed"
      echo "Build will likely fail at stage2:lib:ghc configuration"
    }
  else
    echo "WARNING: ghc.exe not found at ${ghc_exe}"
  fi
else
  echo "WARNING: Stage1 settings file not found at ${settings_file}"
fi

run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release --freeze1 --docs=none --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=release --freeze1 --freeze2 --docs=none
