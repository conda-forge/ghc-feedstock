#!/usr/bin/env bash
set -eu

# ============================================================================
# EXPERIMENTAL GCC BRANCH (feat/v9.6.7-windows-gcc)
# ============================================================================
# This branch tests GCC instead of Clang to match bootstrap GHC's compiler.
#
# Bootstrap GHC was built with GCC 15.2.0, not Clang. Using Clang to compile
# Haskell programs might cause ABI mismatches with GCC-compiled RTS libraries.
#
# Key differences from primary branch:
# 1. Uses GCC/G++ instead of Clang/Clang++
# 2. Removes Clang-specific flags (--target, some -f flags)
# 3. Uses GCC's native MinGW/UCRT support
# 4. Windres uses GCC as preprocessor (not Clang)
#
# Created: 2025-11-24 after UCRT fix didn't solve stdio issue
# See CLAUDE.md for full investigation timeline.
# ============================================================================

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PATH="${_BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}:/c/Windows/System32"
export CABAL="${_BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}\\.cabal"
export _PYTHON="${_BUILD_PREFIX}/python.exe"
export GHC="${BUILD_PREFIX}\\ghc-bootstrap\\bin\\ghc.exe"
export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

# EXPERIMENTAL: Override conda's CC/CXX to use GCC instead of Clang
# Bootstrap GHC was built with GCC, so we should use GCC for consistency
export CC="x86_64-w64-mingw32-gcc"
export CXX="x86_64-w64-mingw32-g++"
export CPP="x86_64-w64-mingw32-cpp"
echo "=== Using GCC toolchain instead of Clang ==="
echo "CC=${CC}"
echo "CXX=${CXX}"
echo "CPP=${CPP}"

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
# Remove -fms-runtime-lib=dll which forces Microsoft MSVCRT (we want MinGW's msvcrt)
CFLAGS=$(echo "${CFLAGS}" | sed 's/-fms-runtime-lib=dll//g')
CXXFLAGS=$(echo "${CXXFLAGS}" | sed 's/-fms-runtime-lib=dll//g')

# EXPERIMENTAL GCC BRANCH: GCC uses libgcc, not compiler-rt
# compiler-rt is Clang's runtime library, GCC has its own libgcc
# We don't need to find it explicitly - we link it via -lgcc flag
# GCC provides libgcc builtin functions natively
echo "=== Using GCC runtime (libgcc) instead of compiler-rt ==="
COMPILER_RT_LIB=""  # Empty - not used with GCC

# EXPERIMENTAL GCC BRANCH: Use GCC with UCRT
# Remove Clang-specific flags (--target, explicit -fuse-ld)
# GCC is built for x86_64-w64-mingw32 by default and uses bfd linker natively
export CFLAGS="-I${_BUILD_PREFIX}/Library/include ${CFLAGS:-}"
export CXXFLAGS="-I${_BUILD_PREFIX}/Library/include ${CXXFLAGS:-}"
export LDFLAGS="-L${_BUILD_PREFIX}/Library/lib -L${_BUILD_PREFIX}/Library/lib/gcc/x86_64-w64-mingw32/15.2.0 ${LDFLAGS:-}"

echo "=== Debugging CFLAGS for GCC ==="
echo "CC=${CC}"
echo "CFLAGS=${CFLAGS}"
echo "CXXFLAGS=${CXXFLAGS}"
echo "LDFLAGS=${LDFLAGS}"

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

# NOTE: mingw32_stubs.a no longer needed with standard MinGW linking
# Using normal libmingw32.a from MinGW - no custom extraction required

# Install windres.bat wrapper
# windres uses "gcc -E" by default, but we only have clang
# The wrapper intercepts windres calls and specifies clang as preprocessor
cp "${_RECIPE_DIR}/building/windres.bat" "${_BUILD_PREFIX}/Library/bin/windres.bat"
echo "Installed windres.bat wrapper to ${_BUILD_PREFIX}/Library/bin/"

# Verify chkstk library was created
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

  # CRITICAL: Override conda's LD=lld-link.exe with GNU ld
  # Conda-forge Windows toolchain sets LD to lld-link.exe (MSVC linker)
  # We need GNU ld for MinGW object files
  export LD="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
  echo "LD overridden to: ${LD}"

  # Convert Unix paths to Windows format for GHC settings
  # GHC on Windows needs Windows paths to execute programs
  # Convert /c/path to C:/path (Windows accepts forward slashes)
  LD_WIN=$(echo "${LD}" | sed 's#^/c/#C:/#')
  AR_WIN=$(echo "${AR}" | sed 's#^/c/#C:/#')
  RANLIB_WIN=$(echo "${RANLIB}" | sed 's#^/c/#C:/#')

  echo "Converted paths for GHC settings:"
  echo "  LD_WIN=${LD_WIN}"
  echo "  AR_WIN=${AR_WIN}"
  echo "  RANLIB_WIN=${RANLIB_WIN}"

  # CRITICAL: Update environment variables to Windows format
  # GHC and Cabal read these from the environment when executing tools
  export LD="${LD_WIN}"
  export AR="${AR_WIN}"
  export RANLIB="${RANLIB_WIN}"
  echo "Updated environment variables to Windows format"

  perl -pi -e "s#(C compiler command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  # Use Clang with -E for preprocessing (acts as cpp)
  # Must use full path to ensure it's found
  perl -pi -e "s#(Haskell CPP command\", \")[^\"]*#\$1${CC}#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler command\", \")[^\"]*#\$1${CXX}#" "${settings_file}"
  perl -pi -e "s#(Merge objects command\", \")[^\"]*#\$1${LD_WIN}#" "${settings_file}"
  perl -pi -e "s#(ar command\", \")[^\"]*#\$1${AR_WIN}#" "${settings_file}"
  perl -pi -e "s#(ranlib command\", \")[^\"]*#\$1${RANLIB_WIN}#" "${settings_file}"
  perl -pi -e "s#(dllwrap command\", \")[^\"]*#\$1false#" "${settings_file}"
  # windres wrapper (windres.bat) handles clang as preprocessor
  # Use Windows path format for tool execution
  WINDRES_WRAPPER_UNIX="${_BUILD_PREFIX}/Library/bin/windres.bat"
  WINDRES_WRAPPER_WIN=$(echo "${WINDRES_WRAPPER_UNIX}" | sed 's#^/c/#C:/#')
  perl -pi -e "s#(windres command\", \")[^\"]*#\$1${WINDRES_WRAPPER_WIN}#" "${settings_file}"

  perl -pi -e "s#-I\\\$tooldir/mingw/include#-I${_BUILD_PREFIX}/Library/include#g" "${settings_file}"

  perl -pi -e "s#(C compiler flags\", \")([^\"]*)#\$1\$2 ${CFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)#\$1\$2 ${CXXFLAGS} -I${_PREFIX}/Library/include#" "${settings_file}"
  # Clang preprocessor flags with -traditional-cpp for Haskell compatibility
  # -traditional-cpp: Traditional (pre-standard) preprocessing, handles # in identifiers
  perl -pi -e "s#(Haskell CPP flags\", \")[^\"]*#\$1-E -undef -traditional-cpp -I${_BUILD_PREFIX}/Library/include -I${_PREFIX}/Library/include#" "${settings_file}"

  # DO NOT patch bootstrap GHC link flags with custom CRT!
  # The custom CRT flags (-nostartfiles, custom crt2.o) break stdio initialization
  # for Haskell programs. Bootstrap GHC must use NORMAL MinGW linking so that
  # Haskell executables (including hadrian) can do stdio properly.
  #
  # The custom CRT flags are ONLY needed for the FINAL Stage1/Stage2 GHC being
  # built, NOT for intermediate Haskell programs compiled during the build.
  #
  # We only fix the merge-objects command to use GNU ld instead of lld.

  # CRITICAL: Fix merge-objects to use GNU ld (ld.bfd) instead of lld
  # The bootstrap GHC has system-merge-objects pointing to ld.lld.exe which uses MSVC-style .lib files
  # We need GNU ld which works with MinGW .a files
  # Match any ld command (lld.exe, ld.lld.exe, ld.exe) and replace with our GNU ld
  # IMPORTANT: Use LD_WIN (Windows format) not LD (Unix format) for tool execution
  perl -pi -e "s#(Merge objects command\", \")[^\"]*#\$1${LD_WIN}#" "${settings_file}"

  echo "Bootstrap GHC settings - only merge-objects modified:"
  grep "Merge objects command" "${settings_file}"
else
  echo "WARNING: Stage0 settings file not found at ${settings_file}"
fi

echo "=== Full bootstrap settings file ==="
cat "${settings_file}"

echo ""
echo "=== Key settings for debugging GCC issue ==="
grep -E "C compiler (command|flags)|Haskell CPP" "${settings_file}" || echo "No matches found"

cd "${_SRC_DIR}"

# Clean any stale .cabal directory that might have permission issues
# This prevents "you don't have permission to modify this file" errors on package.cache
echo "=== Cleaning stale .cabal directory to prevent permission issues ==="
rm -rf "${_SRC_DIR}/.cabal" || true
rm -rf "${HOME}/.cabal" || true

mkdir -p "${_SRC_DIR}/.cabal" && "${CABAL}" user-config init

# Configure Cabal to use single-threaded builds on Windows to avoid race conditions
# This prevents parallel ghc-pkg updates from conflicting on package.cache
# echo "=== Configuring Cabal for single-threaded builds ==="
# echo "jobs: 1" >> "${_SRC_DIR}/.cabal/config"

# CRITICAL: Pass chkstk_ms library through LDFLAGS for linking
# This ensures ALL packages link against our custom library that provides ___chkstk_ms
# Add to LDFLAGS so it's used during linking but not during compilation-only operations
echo "=== Adding chkstk_ms library to LDFLAGS ==="
export LDFLAGS="${LDFLAGS} -lchkstk_ms"
echo "LDFLAGS=${LDFLAGS}"

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

# GCC BRANCH: GCC uses libgcc, not compiler-rt
# This duplicate compiler-rt detection removed for GCC compatibility
echo "=== Using libgcc (GCC builtin library) ==="

# LIBS - let configure use standard MinGW linking
# No custom CRT objects needed with normal linking
export LIBS=""

# Use GNU ld for linking (compatible with MinGW libraries)
# CRITICAL: Use Windows format path for tool execution (GHC on Windows needs C:/path format)
LD_UNIX="${_BUILD_PREFIX}/Library/bin/x86_64-w64-mingw32-ld.exe"
LD_WIN=$(echo "${LD_UNIX}" | sed 's#^/c/#C:/#')
export LD="${LD_WIN}"
echo "LD set to Windows format: ${LD}"

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
perl -pi -e 's#^ffi-include-dir\s*=\s*/c/#ffi-include-dir   = C:/#' "${_SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^ffi-lib-dir\s*=\s*/c/#ffi-lib-dir       = C:/#' "${_SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^([a-z-]+dir)\s*=\s*/c/#$1 = C:/#g' "${_SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e "s#^(intree-gmp\s*=\s*).*#\$1NO#" "${_SRC_DIR}"/hadrian/cfg/system.config

echo "=== Forcing system toolchain and libffi settings ==="
# Force use of conda toolchain (not inplace MinGW)
perl -pi -e 's#^use-system-mingw\s*=\s*.*$#use-system-mingw = YES#' "${_SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^windows-toolchain-autoconf\s*=\s*.*$#windows-toolchain-autoconf = NO#' "${_SRC_DIR}"/hadrian/cfg/system.config
# Force use of conda libffi
perl -pi -e 's#^use-system-ffi\s*=\s*.*$#use-system-ffi = YES#' "${_SRC_DIR}"/hadrian/cfg/system.config

# CRITICAL: Fix system-merge-objects to use GNU ld instead of lld
# The bootstrap GHC's system-merge-objects points to ld.lld.exe which expects MSVC .lib files
# We need GNU ld which works with MinGW .a files
perl -pi -e 's#^system-merge-objects\s*=\s*.*ld\.lld.*$#system-merge-objects = '"${LD}"'#' "${_SRC_DIR}"/hadrian/cfg/system.config

cat "${_SRC_DIR}"/hadrian/cfg/system.config | grep "include-dir\|lib-dir\|windres\|dllwrap\|system-mingw\|system-ffi\|merge-objects"

mkdir -p ${_SRC_DIR}/_build

# Build Hadrian
(
  pushd "${_SRC_DIR}"/hadrian

    # CRITICAL: Test GHC before cabal build to ensure it's functional
    echo "=== Testing bootstrap GHC invocation ==="
    echo "Running: ghc --version"
    "${GHC}" --version || { echo "ERROR: GHC failed to run"; exit 1; }
    echo "Running: ghc --print-libdir"
    "${GHC}" --print-libdir || { echo "ERROR: GHC --print-libdir failed"; exit 1; }
    echo "Bootstrap GHC is functional"

    echo "=== Building Hadrian ==="
    # Using standard MinGW linking - no custom CRT complexity
    timeout 600 "${CABAL}" v2-build -j1 --with-ld="${LD}" hadrian 2>&1 | tee "${_SRC_DIR}"/cabal-build.log
    _cabal_exit_code=${PIPESTATUS[0]}

    if [[ $_cabal_exit_code -ne 0 ]]; then
      echo "=== Cabal build FAILED with exit code ${_cabal_exit_code} ==="
      exit 1
    fi

    echo "=== Cabal build SUCCEEDED ==="

  popd
)

_hadrian_bin=$(find "${_SRC_DIR}"/hadrian/dist-newstyle -name hadrian.exe -type f | head -1)
echo "Hadrian binary: ${_hadrian_bin}"

# Verify the hadrian binary
echo "=== Verifying hadrian.exe binary ==="
if [[ ! -f "${_hadrian_bin}" ]]; then
  echo "ERROR: Hadrian binary not found at: ${_hadrian_bin}"
  exit 1
fi
echo "File exists: ${_hadrian_bin}"
echo "File size: $(stat -c%s "${_hadrian_bin}" 2>/dev/null || stat -f%z "${_hadrian_bin}" 2>/dev/null || echo "unknown") bytes"
echo "File permissions: $(ls -l "${_hadrian_bin}")"
echo "File type: $(file "${_hadrian_bin}" 2>/dev/null || echo "file command not available")"
echo "MD5 checksum: $(md5sum "${_hadrian_bin}" 2>/dev/null | cut -d' ' -f1 || echo "md5sum not available")"

# Examine PE headers in detail
echo "=== Examining PE headers ==="
if command -v objdump &>/dev/null; then
  echo "--- PE Optional Header (ImageBase, SectionAlignment, etc) ---"
  objdump -p "${_hadrian_bin}" 2>&1 | grep -E "ImageBase|SectionAlignment|FileAlignment|AddressOfEntryPoint|Magic|Subsystem" | head -20
  echo ""
  echo "--- Section Table (checking for sections below image base) ---"
  objdump -h "${_hadrian_bin}" 2>&1 | head -30
else
  echo "objdump not available for PE header inspection"
fi

# Check DLL dependencies
echo "=== Checking DLL dependencies ==="
if command -v ldd &>/dev/null; then
  ldd "${_hadrian_bin}" 2>&1 | head -20
elif command -v objdump &>/dev/null; then
  objdump -p "${_hadrian_bin}" 2>&1 | grep "DLL Name" | head -20
else
  echo "No DLL dependency checker available"
fi

# Try multiple execution methods to diagnose the issue
echo "=== Testing hadrian execution (multiple methods) ==="

# Convert to Windows path for cmd.exe/PowerShell
_hadrian_win_path=$(cygpath -w "${_hadrian_bin}" 2>/dev/null || echo "${_hadrian_bin}")
echo "Windows path: ${_hadrian_win_path}"

# Test 1: Direct execution from bash (Unix path)
echo "--- Test 1: Direct bash execution (Unix path) ---"
set +e
"${_hadrian_bin}" --version 2>&1 | head -5
_test1_exit=$?
set -e
echo "Exit code: ${_test1_exit}"

# Test 2: Execution via cmd.exe
echo "--- Test 2: Execution via cmd.exe ---"
set +e
cmd.exe /c "\"${_hadrian_win_path}\" --version" 2>&1 | head -5 | grep '0.1.0.0'
_test2_exit=$?
set -e
echo "Exit code: ${_test2_exit}"

# Test 3: Check if it's a valid PE executable
echo "--- Test 3: PE executable validation ---"
if command -v objdump &>/dev/null; then
  # Check if entry point exists and is valid
  entry_point=$(objdump -p "${_hadrian_bin}" 2>&1 | grep "AddressOfEntryPoint" | awk '{print $2}')
  echo "Entry point address: ${entry_point:-NOT FOUND}"

  # Check subsystem type
  subsystem=$(objdump -p "${_hadrian_bin}" 2>&1 | grep "Subsystem" | head -1)
  echo "Subsystem: ${subsystem:-NOT FOUND}"
fi

# Summary
echo "=== Execution Test Summary ==="
echo "Test 1 (bash direct): exit code ${_test1_exit}"
echo "Test 2 (cmd.exe): exit code ${_test2_exit}"
if [[ ${_test2_exit} -eq 0 ]]; then
  echo "✓ Binary IS executable via cmd.exe - bash execution issue confirmed"
  echo "This is likely an MSYS2/Cygwin compatibility issue, not a malformed binary"
elif [[ ${_test1_exit} -eq 126 ]] && [[ ${_test2_exit} -ne 0 ]]; then
  echo "✗ Binary is NOT executable by any method - likely malformed PE binary"
  echo "The 'section below image base' warning indicates real PE format issues"
fi

# run_and_log will convert paths to Windows format when executing via cmd.exe
_hadrian_build=("${_hadrian_bin}" "-j${CPU_COUNT}" "--directory" "${_SRC_DIR}")

# Build stage1 GHC
echo "*** Building stage1 GHC ***"

# Ensure cabal wrapper is in PATH for hadrian
echo "*** Final cabal PATH verification ***"
export PATH="${_BUILD_PREFIX}/bin:${PATH}"
grep -A 10 "include-dirs:" rts/rts.cabal.in

echo "=== Verifying Hadrian binary before stage1 build ==="
echo "Hadrian path: ${_hadrian_bin}"
if [[ -f "${_hadrian_bin}" ]]; then
  echo "✓ Hadrian binary exists"
  ls -lh "${_hadrian_bin}"
  file "${_hadrian_bin}"

  echo ""
  echo "=== DLL DEPENDENCY ANALYSIS ==="

  # Method 1: objdump -p (static analysis - shows what DLLs binary declares it needs)
  echo "--- Method 1: objdump -p (declared DLL dependencies) ---"
  if command -v objdump &>/dev/null; then
    objdump -p "${_hadrian_bin}" | grep "DLL Name" || echo "No DLL dependencies found (or objdump failed)"
  else
    echo "objdump not available"
  fi

  # Method 2: ldd (runtime analysis - tries to resolve DLLs)
  echo ""
  echo "--- Method 2: ldd (runtime DLL resolution) ---"
  if command -v ldd &>/dev/null; then
    ldd "${_hadrian_bin}" || echo "ldd failed (may indicate missing DLLs)"
  else
    echo "ldd not available"
  fi

  # Method 3: ntldd (better alternative for Windows - if available)
  echo ""
  echo "--- Method 3: ntldd (Windows-specific DLL analysis) ---"
  if command -v ntldd &>/dev/null; then
    ntldd "${_hadrian_bin}" || echo "ntldd failed"
  else
    echo "ntldd not available (package: mingw-w64-x86_64-ntldd)"
  fi

  # Show current PATH to see if MinGW DLLs are accessible
  echo ""
  echo "--- Current PATH (checking for MinGW DLL directories) ---"
  echo "${PATH}" | tr ':' '\n' | grep -i "mingw\|library"

  # Check if critical DLLs exist in expected locations
  echo ""
  echo "--- Checking for critical MinGW DLLs ---"
  for dll in libgcc_s_seh-1.dll libwinpthread-1.dll libstdc++-6.dll; do
    dll_path="${_BUILD_PREFIX}/Library/bin/${dll}"
    if [[ -f "${dll_path}" ]]; then
      echo "✓ Found: ${dll}"
    else
      echo "✗ Missing: ${dll}"
    fi
  done

  echo ""
  echo "Testing hadrian.exe direct execution from MSYS2 bash:"
  "${_hadrian_bin}" --help || echo "hadrian.exe --help failed with exit code: $?"

  echo ""
  echo "=== CRITICAL TEST: Verify Haskell RTS and stdio work ==="

  # Test 1: Can bootstrap GHC print anything?
  echo "--- Test 1: Bootstrap GHC version output ---"
  "${_BUILD_PREFIX}/ghc-bootstrap/bin/ghc.exe" --version || echo "Bootstrap GHC --version failed: $?"

  # Test 2: Compile minimal Haskell program with bootstrap GHC
  echo "--- Test 2: Compile minimal Haskell program ---"
  cat > "${_SRC_DIR}/test_stdio.hs" <<'EOF'
main :: IO ()
main = putStrLn "Haskell stdio works!"
EOF

  "${_BUILD_PREFIX}/ghc-bootstrap/bin/ghc.exe" -o "${_SRC_DIR}/test_stdio.exe" "${_SRC_DIR}/test_stdio.hs" 2>&1 | head -20
  _compile_exit=$?
  echo "Compilation exit code: ${_compile_exit}"

  if [[ ${_compile_exit} -eq 0 ]] && [[ -f "${_SRC_DIR}/test_stdio.exe" ]]; then
    echo "--- Test 3: Execute compiled Haskell program ---"
    _test_win=$(cygpath -w "${_SRC_DIR}/test_stdio.exe")
    cmd.exe /c "${_test_win}" 2>&1 | tee "${_SRC_DIR}/test_stdio.log"
    _exec_exit=$?
    echo "Execution exit code: ${_exec_exit}"

    # Check if program actually printed the expected message
    if grep -q "Haskell stdio works!" "${_SRC_DIR}/test_stdio.log"; then
      echo "✓ Test program printed output - stdio works!"
    else
      echo "✗ ERROR: Test program produced NO output"
      echo "Output captured ($(wc -c < "${_SRC_DIR}/test_stdio.log") bytes):"
      cat "${_SRC_DIR}/test_stdio.log"
      echo ""
      echo "This indicates Haskell RTS stdio is broken"
      exit 1
    fi
  else
    echo "✗ ERROR: Cannot compile simple Haskell program"
    echo "This indicates bootstrap GHC has issues"
    exit 1
  fi

  # Test 4: Can hadrian print anything?
  echo "--- Test 4: Hadrian version output ---"
  _hadrian_win=$(cygpath -w "${_hadrian_bin}")
  echo "Testing: cmd.exe /c \"${_hadrian_win}\" --version"
  cmd.exe /c "${_hadrian_win}" --version 2>&1 | tee "${_SRC_DIR}/hadrian_version.log"
  _hadrian_exit=$?
  echo "Hadrian --version exit code: ${_hadrian_exit}"

  # Check if hadrian actually printed version info (not just cmd.exe banner)
  if grep -qE "(Hadrian|hadrian|version [0-9])" "${_SRC_DIR}/hadrian_version.log"; then
    echo "✓ Hadrian produces actual output"
  else
    echo "✗ ERROR: Hadrian produces NO actual output"
    echo "Output captured ($(wc -c < "${_SRC_DIR}/hadrian_version.log") bytes):"
    cat "${_SRC_DIR}/hadrian_version.log"
    echo ""
    echo "Haskell RTS stdio is broken - no Haskell programs can print"
    exit 1
  fi
else
  echo "✗ ERROR: Hadrian binary not found at ${_hadrian_bin}"
  echo "Searching for hadrian.exe:"
  find "${_SRC_DIR}" -name "hadrian.exe" -type f
  exit 1
fi

echo "=== Building Stage1 GHC using run_and_log (cmd.exe wrapper) ==="
# MSYS2 bash cannot execute Windows PE binaries directly (Exec format error)
# But cmd.exe CAN execute them, so use run_and_log which wraps in cmd.exe
run_and_log "stage1_ghc" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none

# Find Stage0 settings file (location may vary on Windows)
echo "=== Locating Stage0 settings file ==="
settings_file="${_SRC_DIR}"/_build/stage0/lib/settings

if [[ ! -f "${settings_file}" ]]; then
  echo "Settings file not at expected location: ${settings_file}"
  echo ""
  echo "Checking if _build directory exists..."
  if [[ -d "${_SRC_DIR}/_build" ]]; then
    echo "✓ _build directory exists"
    echo "Contents of _build:"
    ls -la "${_SRC_DIR}/_build" 2>/dev/null | head -20
  else
    echo "✗ _build directory does NOT exist"
  fi
  echo ""
  echo "Searching for all 'settings' files under SRC_DIR..."
  find "${_SRC_DIR}" -name "settings" -type f 2>/dev/null | while read -r found_settings; do
    echo "  Found: ${found_settings}"
  done
  echo ""
  # Try to find the first settings file
  found_settings=$(find "${_SRC_DIR}" -name "settings" -type f 2>/dev/null | head -1)
  if [[ -n "${found_settings}" ]]; then
    echo "Using first found settings file: ${found_settings}"
    settings_file="${found_settings}"
  fi
fi

if [[ -f "${settings_file}" ]]; then
  echo "=== Updating Stage0 settings with conda include paths ==="
  echo "Settings file: ${settings_file}"
  # Add -I flags to C compiler flags for ffi.h, gmp.h, etc.
  # CRITICAL: Use _PREFIX (Unix paths) NOT PREFIX (Windows paths with \b escape sequences)
  perl -pi -e "s#(C compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  grep "C compiler flags\|C++ compiler flags" "${settings_file}"
else
  echo "WARNING: Stage0 settings file not found at ${settings_file}"
  echo "Continuing without settings file modifications..."
fi

run_and_log "stage1_pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_hs" "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quickest --docs=none --progress-info=none
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quickest --docs=none --progress-info=none || { \
  echo "=== Checking if Hadrian patch was applied ==="; \
  grep -A 3 "interpolateSetting.*FFIIncludeDir" "${_SRC_DIR}"/hadrian/src/Rules/Generate.hs || echo "ERROR: Hadrian patch NOT applied!"; \
  grep -n "include-dirs\|extra-include-dirs\|/c/bld" "${_SRC_DIR}"/rts/rts.cabal | head -20; \
  exit 1; \
}

# Apply additional settings modifications if file exists
if [[ -f "${settings_file}" ]]; then
  echo "=== Redirecting mingw paths to conda-forge in Stage0 settings ==="
  # perl -pi -e "s#((dllwrap|windres|llc|opt|clang) command\", \")[^\"]*#\$1${conda_target}-\$2#" "${settings_file}"
  perl -pi -e "s#(Use inplace MinGW toolchain\", \")[^\"]*#\$1NO#" "${settings_file}"
  perl -pi -e "s#(Use LibFFI\", \")[^\"]*#\$1YES#" "${settings_file}"

  # Reassign mingw references to conda-forge MinGW (same as ghc-bootstrap)
  perl -pi -e 's#\$topdir/../mingw//bin/(llvm-)?##' "${settings_file}"
  perl -pi -e 's#-I\$topdir/../mingw//include#-I\$topdir/../../Library/include#g' "${settings_file}"
  perl -pi -e 's#-L\$topdir/../mingw//lib#-L\$topdir/../../Library/lib#g' "${settings_file}"
  perl -pi -e 's#-L\$topdir/../mingw//x86_64-w64-mingw32/lib#-L\$topdir/../../Library/bin -L\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib -Wl,-rpath,\$topdir/../../Library/x86_64-w64-mingw32/sysroot/usr/lib#g' "${settings_file}"

  echo "=== Stage0 settings after modifications ==="
  cat "${settings_file}" | grep -A1 "mingw\|C compiler\|LibFFI" || echo "(No matching lines found)"
else
  echo "WARNING: Skipping Stage0 settings modifications - file not found at: ${settings_file}"
fi

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
  # System libraries and compiler builtins
  # CRITICAL: Need -lgcc for __udivti3/__umodti3 symbols from RtsSymbols
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lgcc"
  # CRITICAL: Use -lucrt (Universal C Runtime) NOT -lmsvcrt (old runtime)
  # Bootstrap GHC was built with UCRT (mingw-w64-ucrt-x86_64-crt-git)
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lucrt"
  # GCC BRANCH: libgcc provides all builtins, no need for compiler-rt
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -lkernel32"
  LINK_FLAGS="${LINK_FLAGS} -Xlinker -ladvapi32"

  perl -pi -e "s#(C compiler link flags\", \")#\$1${LINK_FLAGS} #" "${settings_file}"

  # Also add to "ld flags" for direct ld invocations (use bare library names, no -Xlinker)
  # CRITICAL: --subsystem,console for console entry point (GNU ld syntax with comma separator)
  # CRITICAL: Need -lgcc for __udivti3/__umodti3 symbols from RtsSymbols
  # CRITICAL: Use -lucrt (Universal C Runtime) to match bootstrap GHC
  # GCC BRANCH: libgcc provides all builtins, no need for compiler-rt
  perl -pi -e "s#(ld flags\", \")#\$1--subsystem,console -L${CHKSTK_DIR} -L${MINGW_SYSROOT} -lmoldname -lmingwex -lmingw32 -lchkstk_ms -lgcc -lucrt -lkernel32 -ladvapi32 #" "${settings_file}"

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
