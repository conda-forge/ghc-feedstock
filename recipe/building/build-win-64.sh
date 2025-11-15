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

export CXX_STD_LIB_LIBS="stdc++"

# Configure Clang for MinGW cross-compilation
# CRITICAL: Clang needs explicit target, sysroot, and include paths
SDK_PATH=$(ls -1d /c/Program*Files*x86*/Windows*/10)
SDK_PATH=$(cygpath -u "$(cygpath -d "${SDK_PATH}")")
SDK_VER=$(ls -1 ${SDK_PATH}/Include/ 2>/dev/null | grep "^10\." | sort -V | tail -1)

UCRT_INCLUDE="${SDK_PATH}"/Include/"${SDK_VER}"/ucrt
UM_INCLUDE="${SDK_PATH}"/Include/"${SDK_VER}"/um
SHARED_INCLUDE="${SDK_PATH}"/Include/"${SDK_VER}"/shared
CPPWINRT_INCLUDE="${SDK_PATH}"/Include/"${SDK_VER}"/cppwinrt
WINRT_INCLUDE="${SDK_PATH}"/Include/"${SDK_VER}"/winrt
UCRT_LIB="${SDK_PATH}"/Lib/"${SDK_VER}"/ucrt/x64
UM_LIB="${SDK_PATH}"/Lib/"${SDK_VER}"/x64

MSVC_BASE=$(ls -1d /c/Program*/Microsoft*/*/*/VC/Tools/MSVC 2>/dev/null | sort -V | tail -1)
MSVC_BASE=$(cygpath -u "$(cygpath -d "${MSVC_BASE}")")
MSVC_VER=$(ls -1 "${MSVC_BASE}" 2>/dev/null | sort -V | tail -1)

# Get short path for MSVC include (has vcruntime.h)
MSVC_INCLUDE="${MSVC_BASE}"/"${MSVC_VER}"/include

# CRITICAL: Replace %BUILD_PREFIX% with actual Unix paths in conda's environment
# Conda sets CFLAGS/LDFLAGS with Windows batch variable syntax which bash doesn't expand
CFLAGS=$(echo "${CFLAGS}" | sed "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g")
CXXFLAGS=$(echo "${CXXFLAGS}" | sed "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g")
LDFLAGS=$(echo "${LDFLAGS}" | sed "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g")

# Remove -nostdlib and linker flags for configure tests
# Let Clang's driver handle linking (it will automatically include compiler-rt builtins)
CFLAGS="${CFLAGS//-nostdlib/}"
CXXFLAGS="${CXXFLAGS//-nostdlib/}"
LDFLAGS="${LDFLAGS//-nostdlib/}"
# Remove linker flags entirely - Clang will use its default (lld-link for MSVC target)
CFLAGS=$(echo "${CFLAGS}" | sed 's/-fuse-ld=lld//g' | sed 's/-fuse-ld=bfd//g')
CXXFLAGS=$(echo "${CXXFLAGS}" | sed 's/-fuse-ld=lld//g' | sed 's/-fuse-ld=bfd//g')
LDFLAGS=$(echo "${LDFLAGS}" | sed 's/-fuse-ld=lld//g' | sed 's/-fuse-ld=bfd//g')
# Remove problematic -Wl,-defaultlib: flags that are MSVC-specific
LDFLAGS=$(echo "${LDFLAGS}" | sed 's/-Wl,-defaultlib:[^ ]*//g')
# Remove -fstack-protector-strong which generates __security_cookie calls incompatible with MinGW+Clang
CFLAGS=$(echo "${CFLAGS}" | sed 's/-fstack-protector-strong//g')
CXXFLAGS=$(echo "${CXXFLAGS}" | sed 's/-fstack-protector-strong//g')

# Use MinGW sysroot for headers and libraries (use Unix path _BUILD_PREFIX)
MINGW_SYSROOT="${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot"

# Configure Clang to target MinGW and let it handle linking automatically
# Key insight: Clang's driver will automatically include compiler-rt builtins
# --target=x86_64-w64-mingw32: Tell Clang to target MinGW (not MSVC)
# -D__MINGW32__: Tell headers we're using MinGW
# -D_VA_LIST_DEFINED: Tell MinGW's vadefs.h that va_list is already defined
# -D__GNUC__: Pretend to be GCC so vadefs.h doesn't error out
# -Dva_list=__builtin_va_list: Map MinGW's va_list to Clang's builtin type
# Use -isystem for ALL includes to override Clang's default search paths
# Order matters: Clang builtins FIRST, then conda libs, then MinGW sysroot
# Convert Windows path to Unix for bash compatibility
CLANG_RESOURCE_DIR=$(${CC} -print-resource-dir | sed 's#\\#/#g' | sed 's#^C:/#/c/#')
CLANG_BUILTIN_INCLUDE="${CLANG_RESOURCE_DIR}/include"

# Debug: Check what compiler-rt libraries are actually available
echo "=== Clang resource directory: ${CLANG_RESOURCE_DIR}"
echo "=== Checking for compiler-rt libraries:"
if [ -d "${CLANG_RESOURCE_DIR}/lib" ]; then
  find "${CLANG_RESOURCE_DIR}/lib" -name "*clang_rt*" -o -name "*builtins*" || echo "No compiler-rt libraries found"
else
  echo "WARNING: ${CLANG_RESOURCE_DIR}/lib does not exist"
fi
export CFLAGS="--target=x86_64-w64-mingw32 -D__MINGW32__ -D_VA_LIST_DEFINED -D__GNUC__=13 -Dva_list=__builtin_va_list -isystem ${CLANG_BUILTIN_INCLUDE} -isystem ${_BUILD_PREFIX}/Library/include -isystem ${MINGW_SYSROOT}/usr/include ${CFLAGS:-}"
export CXXFLAGS="--target=x86_64-w64-mingw32 -D__MINGW32__ -D_VA_LIST_DEFINED -D__GNUC__=13 -Dva_list=__builtin_va_list -isystem ${CLANG_BUILTIN_INCLUDE} -isystem ${_BUILD_PREFIX}/Library/include -isystem ${MINGW_SYSROOT}/usr/include ${CXXFLAGS:-}"
# Let Clang's driver handle linking - it will automatically use appropriate linker and libraries
# We only need to specify library search paths and additional libraries
# -nodefaultlibs: Don't link standard system libraries (we'll add what we need explicitly)
export LDFLAGS="-nodefaultlibs -L${_BUILD_PREFIX}/Library/lib -L${_BUILD_PREFIX}/Library/mingw-w64/lib -L${MINGW_SYSROOT}/usr/lib ${LDFLAGS}"
# MinGW libraries that Clang might not add automatically
# CRITICAL: Find and explicitly link compiler-rt builtins library
# Try both .a (MinGW format) and .lib (MSVC format) extensions
COMPILER_RT_LIB=""
for candidate in \
  "${CLANG_RESOURCE_DIR}/lib/x86_64-w64-windows-gnu/libclang_rt.builtins.a" \
  "${CLANG_RESOURCE_DIR}/lib/windows/libclang_rt.builtins-x86_64.a" \
  "${CLANG_RESOURCE_DIR}/lib/windows/clang_rt.builtins-x86_64.lib" \
  "${CLANG_RESOURCE_DIR}/lib/x86_64-pc-windows-gnu/libclang_rt.builtins.a"
do
  echo "Checking for compiler-rt at: ${candidate}"
  if [ -f "${candidate}" ]; then
    COMPILER_RT_LIB="${candidate}"
    echo "Found compiler-rt: ${COMPILER_RT_LIB}"
    break
  fi
done

if [ -n "${COMPILER_RT_LIB}" ]; then
  # GNU ld cannot handle MSVC .lib files properly (corrupt .drectve errors)
  # Try to extract and repack using llvm-ar (works with both formats)
  COMPILER_RT_A="${_SRC_DIR}/clang_rt.builtins-x86_64.a"

  if [ ! -f "${COMPILER_RT_A}" ]; then
    echo "Converting ${COMPILER_RT_LIB} to GNU ar format..."
    TMPDIR=$(mktemp -d)
    pushd "${TMPDIR}" > /dev/null

    # Extract objects from MSVC .lib using llvm-ar
    llvm-ar x "${COMPILER_RT_LIB}" 2>/dev/null && \
    # Repack with GNU ar
    ar crs "${COMPILER_RT_A}" *.obj 2>/dev/null && \
    echo "Successfully converted to ${COMPILER_RT_A}" || {
      echo "WARNING: Conversion failed, using .lib directly"
      COMPILER_RT_A="${COMPILER_RT_LIB}"
    }

    popd > /dev/null
    rm -rf "${TMPDIR}"
  else
    echo "Using cached converted library: ${COMPILER_RT_A}"
  fi

  # CRITICAL ISSUE: Conda's compiler-rt was built for MSVC, not MinGW
  # It has MSVC-specific stack protection symbols (__security_cookie) which don't exist in MinGW
  # Instead, let's extract ONLY the objects we actually need (___chkstk_ms) and skip the rest

  echo "Extracting ___chkstk_ms from compiler-rt..."
  CHKSTK_DIR="${_SRC_DIR}/chkstk_extract"
  mkdir -p "${CHKSTK_DIR}"
  pushd "${CHKSTK_DIR}" > /dev/null

  # Extract all objects and find the one with ___chkstk_ms
  llvm-ar x "${COMPILER_RT_A}" 2>/dev/null
  CHKSTK_OBJ=""
  for obj in *.obj; do
    if nm "$obj" 2>/dev/null | grep -q "___chkstk_ms"; then
      CHKSTK_OBJ="$obj"
      echo "Found ___chkstk_ms in: $obj"
      break
    fi
  done

  if [ -n "${CHKSTK_OBJ}" ]; then
    # Link just this object file directly
    export LIBS="-Wl,--start-group -lmingw32 -lmoldname -lmingwex ${CHKSTK_DIR}/${CHKSTK_OBJ} -Wl,--end-group -lmsvcrt -lkernel32 -ladvapi32"
  else
    echo "WARNING: ___chkstk_ms not found in compiler-rt"
    echo "Checking if MinGW provides ___chkstk_ms..."

    # Check MinGW libraries for ___chkstk_ms and show symbol details
    echo "Symbol details in libmingw32.a:"
    nm "${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib/libmingw32.a" 2>/dev/null | grep "___chkstk_ms" || echo "  (not found)"

    echo "Symbol details in libmingwex.a:"
    nm "${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib/libmingwex.a" 2>/dev/null | grep "___chkstk_ms" || echo "  (not found)"

    # Try linking with all mingw libraries, maybe it's in one we haven't tried
    export LIBS="-Wl,--start-group -lmingw32 -lmoldname -lmingwex -lmingwthrd -Wl,--end-group -lmsvcrt -lkernel32 -ladvapi32"
  fi

  popd > /dev/null
  # Don't cleanup CHKSTK_DIR yet - linker needs the .obj file
else
  echo "WARNING: compiler-rt builtins not found, linking may fail"
  export LIBS="-lmingw32 -lmoldname -lmingwex -lmsvcrt -lkernel32 -ladvapi32"
fi

# Use GNU ld for linking (compatible with MinGW libraries)
# CRITICAL: Use Unix path _BUILD_PREFIX not Windows path BUILD_PREFIX
export LD="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"

(
  MergeObjsCmd="${LD}" \
  MergeObjsArgs="" \
  ./configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )
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
    # export CFLAGS="--target=x86_64-w64-mingw32 -I${BUILD_PREFIX}/Library/include ${CFLAGS}"
    # export CXXFLAGS="--target=x86_64-w64-mingw32 -I${BUILD_PREFIX}/Library/include ${CXXFLAGS}"
    # export LDFLAGS=$(echo "${LDFLAGS}" | sed 's/-fuse-ld=lld/-fuse-ld=bfd/g') \

    # export LD="${BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe" \
    
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
