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

# Define toolchain variables early for bootstrap settings patching
export LD="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
export AR="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ar.exe"
export RANLIB="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ranlib.exe"

# Configure CFLAGS/CXXFLAGS/LDFLAGS early so bootstrap settings get correct values
# CRITICAL: This MUST happen before patching bootstrap settings file
# CRITICAL: Replace %BUILD_PREFIX% with actual Unix paths in conda's environment
CFLAGS=$(echo "${CFLAGS}" | sed "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g")
CXXFLAGS=$(echo "${CXXFLAGS}" | sed "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g")
LDFLAGS=$(echo "${LDFLAGS}" | sed "s|%BUILD_PREFIX%|${_BUILD_PREFIX}|g")

# Remove problematic flags from conda environment
CFLAGS="${CFLAGS//-nostdlib/}"
CXXFLAGS="${CXXFLAGS//-nostdlib/}"
LDFLAGS="${LDFLAGS//-nostdlib/}"
# Use GNU ld (bfd) for MinGW compatibility (lld defaults to MSVC mode on Windows)
CFLAGS=$(echo "${CFLAGS}" | sed 's/-fuse-ld=lld/-fuse-ld=bfd/g')
CXXFLAGS=$(echo "${CXXFLAGS}" | sed 's/-fuse-ld=lld/-fuse-ld=bfd/g')
LDFLAGS=$(echo "${LDFLAGS}" | sed 's/-fuse-ld=lld/-fuse-ld=bfd/g')
# Remove problematic -Wl,-defaultlib: flags that are MSVC-specific
LDFLAGS=$(echo "${LDFLAGS}" | sed 's/-Wl,-defaultlib:[^ ]*//g')
# Remove -fstack-protector-strong which generates __security_cookie calls incompatible with MinGW+Clang
CFLAGS=$(echo "${CFLAGS}" | sed 's/-fstack-protector-strong//g')
CXXFLAGS=$(echo "${CXXFLAGS}" | sed 's/-fstack-protector-strong//g')

# Get Clang's builtin include directory
CLANG_RESOURCE_DIR=$(${CC} -print-resource-dir | sed 's#\\#/#g' | sed 's#^C:/#/c/#')
CLANG_BUILTIN_INCLUDE="${CLANG_RESOURCE_DIR}/include"

# Configure Clang for MinGW with all necessary include paths and defines
# NOTE: Use -I instead of -isystem to avoid path validation issues on Windows
# -nodefaultlibs: Don't link libgcc/libgcc_eh (not available in conda)
# -nostartfiles: Don't auto-include CRT startup files (we'll specify crt2.o explicitly in LIBS)
# -Wl,--subsystem,console: Set PE subsystem to console (not GUI)
export CFLAGS="--target=x86_64-w64-mingw32 -fuse-ld=bfd -nodefaultlibs -D__MINGW32__ -D_VA_LIST_DEFINED -D__GNUC__=13 -Dva_list=__builtin_va_list -I${CLANG_BUILTIN_INCLUDE} -I${_BUILD_PREFIX}/Library/include ${CFLAGS:-}"
export CXXFLAGS="--target=x86_64-w64-mingw32 -fuse-ld=bfd -nodefaultlibs -D__MINGW32__ -D_VA_LIST_DEFINED -D__GNUC__=13 -Dva_list=__builtin_va_list -I${CLANG_BUILTIN_INCLUDE} -I${_BUILD_PREFIX}/Library/include ${CXXFLAGS:-}"
export LDFLAGS="-fuse-ld=bfd -nostartfiles -L${_BUILD_PREFIX}/Library/lib -L${_BUILD_PREFIX}/Library/mingw-w64/lib -Wl,--subsystem,console ${LDFLAGS:-}"

# Bug in ghc-bootstrap
#WINDRES_PATH="${BUILD_PREFIX//\\/\\\\}\\\\Library\\\\bin\\\\${WINDRES}"
#perl -pi -e "s#WINDRES_CMD=.*windres\.exe#WINDRES_CMD=${WINDRES_PATH}#" "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat
perl -pi -e 's/findstr/C:\\Windows\\System32\\findstr/g' "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat

# CRITICAL: Create ___chkstk_ms stub library BEFORE updating settings file
# MinGW libraries reference this symbol but don't provide it
echo "=== Building ___chkstk_ms stub library ==="
CHKSTK_OBJ="${_SRC_DIR}/chkstk_ms.o"
CHKSTK_LIB="${_BUILD_PREFIX}/Library/lib/libchkstk_ms.a"

# Compile the stub
${CC} -c "${_RECIPE_DIR}/building/chkstk_ms.c" -o "${CHKSTK_OBJ}"
echo "Created ${CHKSTK_OBJ}"

# Create static library
${AR} rcs "${CHKSTK_LIB}" "${CHKSTK_OBJ}"
echo "Created ${CHKSTK_LIB}"

echo "=== Building mingw32 runtime stubs library ==="
MINGW32_STUBS_OBJ="${_SRC_DIR}/mingw32_stubs.o"
MINGW32_STUBS_LIB="${_BUILD_PREFIX}/Library/lib/libmingw32_stubs.a"

# Compile the stubs
${CC} -c "${_RECIPE_DIR}/building/mingw32_stubs.c" -o "${MINGW32_STUBS_OBJ}"
echo "Created ${MINGW32_STUBS_OBJ}"

# Create static library
${AR} rcs "${MINGW32_STUBS_LIB}" "${MINGW32_STUBS_OBJ}"
echo "Created ${MINGW32_STUBS_LIB}"

# Verify library was created
if [ -f "${CHKSTK_LIB}" ]; then
    echo "✓ Library exists: ${CHKSTK_LIB}"
    ls -lh "${CHKSTK_LIB}"
else
    echo "✗ ERROR: Library NOT created at ${CHKSTK_LIB}"
    exit 1
fi

# Update Stage0 settings file with conda include paths for Windows build
# NOW we can reference the chkstk library since it exists
settings_file="${_BUILD_PREFIX}/ghc-bootstrap/lib/settings"
if [[ -f "${settings_file}" ]]; then
  echo "=== Updating bootstrap settings with conda include paths ==="
  # Add -I flags to C compiler flags for ffi.h, gmp.h, etc.
  # CRITICAL: Use _PREFIX (Unix paths) NOT PREFIX (Windows paths with \b escape sequences)
  
  perl -pi -e "s#(C compiler command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  # Use Clang with -E for preprocessing (acts as cpp)
  # Must use full path to ensure it's found
  perl -pi -e "s#(Haskell CPP command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler command\", \")[^\"]*#\$1${CXX}#" "${settings_file}"
  perl -pi -e "s#(Merge objects command\", \")[^\"]*#\$1${LD}#" "${settings_file}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR}#" "${settings_file}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1${RANLIB}#" "${settings_file}"
  perl -pi -e "s#(dllwrap command\", \")[^\"]*#\$1false#" "${settings_file}"
  perl -pi -e "s#(windres command\", \")[^\"]*#\$1false#" "${settings_file}"

  perl -pi -e "s#-I\\\$tooldir/mingw/include#-I${_BUILD_PREFIX}/Library/include#g" "${settings_file}"

  perl -pi -e "s#(C compiler flags\", \")([^\"]*)#\$1\$2 ${CFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)#\$1\$2 ${CXXFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"
  # Clang preprocessor flags with -traditional-cpp for Haskell compatibility
  # -traditional-cpp: Traditional (pre-standard) preprocessing, handles # in identifiers
  perl -pi -e "s#(Haskell CPP flags\", \")[^\"]*#\$1-E -undef -traditional-cpp -I${_BUILD_PREFIX}/Library/include -I${_PREFIX}/Library/include#" "${settings_file}"

  # Add MinGW runtime libraries to "C compiler link flags"
  # CRITICAL: Link order matters - user objects first, then helper libs, then -lmingw32 LAST
  # -lmingw32 provides console CRT startup BUT also defines main() that calls user's main()
  # It must come AFTER user objects so user's main() is found first
  # Use -Xlinker to pass ONLY to linker (not to compile-only invocations)
  CHKSTK_DIR="${_BUILD_PREFIX}/Library/lib"
  MINGW_SYSROOT="${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib"

  # Convert Unix path to Windows-style path with forward slashes for ld.bfd
  # ld.bfd on Windows understands C:/path/to/file format
  # NOTE: %BUILD_PREFIX% in logs is display-only; actual values ARE expanded
  # Some scripts need _XXX (Unix paths), others need %XXX% (Windows paths)
  CHKSTK_DIR_WIN=$(echo "${CHKSTK_DIR}" | sed 's#^/c/#C:/#')
  WIN_MINGW_SYSROOT=$(echo "${MINGW_SYSROOT}" | sed 's#^/c/#C:/#')
  CRT2_WIN_PATH="${WIN_MINGW_SYSROOT}/crt2.o"

  # Build complete link flags string - libraries come AFTER user objects
  # Use GNU ld (bfd) with GNU-style subsystem flag
  # CRITICAL: -nostartfiles prevents DEFAULT startups, but not those IN libraries
  # libmingw32.a contains crtexewin.o which conflicts with our crt2.o
  # Use --allow-multiple-definition so linker uses FIRST definition (our crt2.o)
  LINK_FLAGS="-fuse-ld=bfd -nostartfiles -Wl,--allow-multiple-definition -Wl,--subsystem,console"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -L${CHKSTK_DIR_WIN} -Xlinker -L${WIN_MINGW_SYSROOT}"
  # Console CRT startup - use --whole-archive to force inclusion FIRST
  # This ensures crt2.o's main() is resolved before libmingw32.a is scanned
  LINK_FLAGS="${LINK_FLAGS} -Wl,--whole-archive -Xlinker ${CRT2_WIN_PATH} -Wl,--no-whole-archive"
  # MinGW helper libraries
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmoldname"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmingwex"
  # CRITICAL: Skip -lmingw32 entirely to avoid crtexewin.o conflict
  # Instead, use our stub library with just the symbols we need
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmingw32_stubs"
  # Then chkstk_ms (provides symbols needed by mingw32)
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lchkstk_ms"
  # System libraries last
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmsvcrt"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lkernel32"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -ladvapi32"

  perl -pi -e "s#(C compiler link flags\", \")[^\"]*#\$1${LINK_FLAGS}#" "${settings_file}"
  perl -pi -e "s#(ld is GNU ld\", \")[^\"]*#\$1YES#" "${settings_file}"

  # Also add to "ld flags" for direct ld invocations (use bare library names, no -Xlinker)
  # CRITICAL: --subsystem,console for console entry point (GNU ld syntax with comma separator)
  # CRITICAL: Use stub library instead of full libmingw32.a
  perl -pi -e "s#(ld flags\", \")([^\"]*)#\$1\$2 -nostartfiles --allow-multiple-definition --subsystem,console -L${CHKSTK_DIR_WIN} -L${WIN_MINGW_SYSROOT} --whole-archive ${CRT2_WIN_PATH} --no-whole-archive -lmoldname -lmingwex -lmingw32_stubs -lchkstk_ms -lmsvcrt -lkernel32 -ladvapi32#" "${settings_file}"

  # CRITICAL: Fix merge-objects to use GNU ld (ld.bfd) instead of lld
  # The bootstrap GHC has system-merge-objects pointing to ld.lld.exe which uses MSVC-style .lib files
  # We need GNU ld which works with MinGW .a files
  perl -pi -e "s#(Merge objects command\", \")[^\"]*ld\\.lld[^\"]*#\$1${LD}#" "${settings_file}"

  grep "C compiler flags\|C++ compiler flags\|Merge objects\|ld is GNU\|ld flags" "${settings_file}"
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

# CRITICAL: Add custom chkstk_ms library to Cabal's global GHC options
# This ensures ALL packages link against our custom library that provides ___chkstk_ms
# The library must be passed as a linker option, not in LDFLAGS (which would add it to compile commands)
echo "=== Configuring Cabal to use custom chkstk_ms library ==="
cat >> "${SRC_DIR}/.cabal/config" << EOF

-- Add custom chkstk_ms library to all builds
-- This library provides the ___chkstk_ms symbol required by MinGW runtime
ghc-options: -optl${CHKSTK_LIB}
EOF

echo "=== Updated .cabal/config with chkstk_ms library ==="
tail -5 "${SRC_DIR}/.cabal/config"

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

# MinGW libraries that Clang might not add automatically (already configured above)
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

# The ___chkstk_ms library has been created upfront (lines 58-79)
# Now add it to both LIBS and LDFLAGS

# LIBS is used by autoconf-based configure
# CRITICAL: Link order - CRT startup object FIRST, then libraries
# CRITICAL: -lmingw32 needs ___chkstk_ms, so chkstk_ms must come AFTER mingw32
# With -nostartfiles, we must explicitly specify crt2.o (console CRT) not crtexewin.o (GUI)
CRT2_OBJ="${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib/crt2.o"
export LIBS="${CRT2_OBJ} -Wl,--subsystem,console -lmoldname -lmingwex -lmingw32 ${CHKSTK_LIB} -lmsvcrt -lkernel32 -ladvapi32"

# CRITICAL: Reinforce subsystem flag in LDFLAGS
# -Wl,--subsystem,console: Use console entry point (main) instead of GUI (WinMain)
# NOTE: crt2.o is in LIBS, not here, to avoid duplication
export LDFLAGS="${LDFLAGS} -Wl,--subsystem,console"

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

# CRITICAL: Fix system-merge-objects to use GNU ld instead of lld
# The bootstrap GHC's system-merge-objects points to ld.lld.exe which expects MSVC .lib files
# We need GNU ld which works with MinGW .a files
perl -pi -e 's#^system-merge-objects\s*=\s*.*ld\.lld.*$#system-merge-objects = '"${LD}"'#' "${SRC_DIR}"/hadrian/cfg/system.config

cat "${SRC_DIR}"/hadrian/cfg/system.config | grep "include-dir\|lib-dir\|windres\|dllwrap\|system-mingw\|system-ffi\|merge-objects"

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
  # CRITICAL: Isolate Hadrian build environment from configure-time link flags
  # The configure-time LIBS contains crt2.o which conflicts with Hadrian's builds
  # TWO SEPARATE CONTEXTS:
  # 1. Configure context (uses LDFLAGS/LIBS) - needs crt2.o for console startup
  # 2. Hadrian context (uses GHC settings file) - gets startup from GHC's settings
  #
  # SOLUTION: GHC settings file now has -nostartfiles + explicit crt2.o in correct order
  # This ensures Hadrian builds use bootstrap GHC settings (which are now correct)
  # We don't need to modify LIBS here since GHC ignores LIBS env var

  echo "=== Hadrian subshell: Using GHC settings file for link flags (not LIBS) ==="

  pushd "${_SRC_DIR}"/hadrian
    # WINDOWS CPP FIX: GCC cpp with -traditional flag configured in bootstrap settings
    # No need for cabal.project workarounds - GCC's cpp handles Haskell # identifiers correctly

    echo "=== Building Hadrian with GCC cpp (configured in bootstrap settings) ==="
    "${CABAL}" v2-build -v -j hadrian 2>&1 | tee "${_SRC_DIR}"/cabal-build.log
    _cabal_exit_code=${PIPESTATUS[0]}

    if [[ $_cabal_exit_code -ne 0 ]]; then
      echo "=== Cabal build FAILED with exit code ${_cabal_exit_code} ==="
      echo "=== Retrying with verbose output for failed packages ==="
      "${CABAL}" v2-build -v3 hadrian 2>&1 | tee "${_SRC_DIR}"/cabal-verbose.log
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

  # Add MinGW runtime libraries to "C compiler link flags"
  # CRITICAL: Link order matters - user objects first, then helper libs, then -lmingw32 LAST
  # -lmingw32 provides console CRT startup BUT also defines main() that calls user's main()
  # It must come AFTER user objects so user's main() is found first
  # Use -Xlinker to pass ONLY to linker (not to compile-only invocations)
  # Library path must be explicit, not a variable (settings file can't expand ${VAR})
  CHKSTK_DIR="${_BUILD_PREFIX}/Library/lib"
  MINGW_SYSROOT="${_BUILD_PREFIX}/Library/x86_64-w64-mingw32/sysroot/usr/lib"

  # Build complete link flags string - libraries come AFTER user objects
  # Use GNU ld (bfd) with GNU-style subsystem flag
  LINK_FLAGS="-Wl,--subsystem,console -Xlinker -L${CHKSTK_DIR} -Xlinker -L${MINGW_SYSROOT}"
  # MinGW helper libraries
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmoldname"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmingwex"
  # Then -lmingw32
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmingw32"
  # Then chkstk_ms (provides symbols needed by mingw32)
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lchkstk_ms"
  # System libraries last
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lmsvcrt"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lkernel32"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -ladvapi32"

  perl -pi -e "s#(C compiler link flags\", \")#\$1${LINK_FLAGS} #" "${settings_file}"

  # Also add to "ld flags" for direct ld invocations (use bare library names, no -Xlinker)
  # CRITICAL: --subsystem,console for console entry point (GNU ld syntax with comma separator)
  perl -pi -e "s#(ld flags\", \")#\$1--subsystem,console -L${CHKSTK_DIR} -L${MINGW_SYSROOT} -lmoldname -lmingwex -lmingw32 -lchkstk_ms -lmsvcrt -lkernel32 -ladvapi32 #" "${settings_file}"

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
