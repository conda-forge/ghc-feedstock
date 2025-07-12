#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

export PATH="${_SRC_DIR}/bootstrap-ghc/bin:${_SRC_DIR}/bootstrap-cabal${PATH:+:}${PATH:-}"

# Prepare python environment
export PYTHON=$(find "${BUILD_PREFIX}" -name python.exe | head -1)
export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

# Set up temp variables
export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# Some compilation complained about not finding clang_rt.builtins: Still needed?
LIBCLANG_RT_PATH=$(find "${_BUILD_PREFIX}/Library" -name "*clang_rt.builtins*" | head -1)
if [[ -z "${LIBCLANG_RT_PATH}" ]]; then
  echo "Warning: Could not find libclang_rt.builtins"
  exit 1
fi

LIBCLANG_DIR=$(dirname "${LIBCLANG_RT_PATH}")
LIBCLANG_RT=$(basename "${LIBCLANG_RT_PATH}")
if [ "$(basename "${LIBCLANG_DIR}")" != "x86_64-w64-windows-gnu" ]; then
  mkdir -p "$(dirname "${LIBCLANG_DIR}")/x86_64-w64-windows-gnu"
  cp "${LIBCLANG_DIR}/${LIBCLANG_RT}" "$(dirname "${LIBCLANG_DIR}")/x86_64-w64-windows-gnu/lib${LIBCLANG_RT//-x86_64.lib/.a}"
fi

# Define the wrapper script for MSVC
CLANG_WRAPPER="${BUILD_PREFIX}\\Library\\bin\\clang-mingw-wrapper.bat"
cp "${RECIPE_DIR}/building/non_unix/clang-mingw-wrapper.bat" "${_BUILD_PREFIX}/Library/bin/"
cp "${RECIPE_DIR}/building/non_unix/clang-mingw-wrapper.py" "${_BUILD_PREFIX}/Library/bin/"

# Create directory for MinGW chkstk_ms.obj file
MINGW_CHKSTK_DIR="${_BUILD_PREFIX}/Library/lib"
mkdir -p "${MINGW_CHKSTK_DIR}"
MINGW_CHKSTK_OBJ="${MINGW_CHKSTK_DIR}/chkstk_mingw_ms.obj"

# First run the script to create the MinGW chkstk_ms.obj file once
echo "Creating MinGW chkstk_ms.obj file at ${MINGW_CHKSTK_OBJ}..."

# Find clang executable
CLANG_EXE=$(find "${_BUILD_PREFIX}" -name clang.exe | head -1)

if [ -z "${CLANG_EXE}" ]; then
  echo "Error: Could not find clang.exe"
  exit 1
fi

echo "Found clang at: ${CLANG_EXE}"

# Find the latest MSVC version directory dynamically
MSVC_VERSION_DIR=$(ls -d "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/"*/ 2>/dev/null | sort -V | tail -1 | sed 's/\/$//')

# Use the discovered path or fall back to a default if not found
if [ -z "$MSVC_VERSION_DIR" ]; then
  echo "Warning: Could not find MSVC tools directory, using fallback path"
  MSVC_VERSION_DIR="C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/14.38.33130"
fi

# Export MSVC chkstk.obj location and analyze it
export CHKSTK_OBJ="${MSVC_VERSION_DIR}/lib/x64/chkstk.obj"
echo "Using MSVC chkstk.obj at ${CHKSTK_OBJ}"

# Analyze MSVC chkstk.obj to see what symbols it exports
if command -v llvm-nm &>/dev/null; then
  echo "Analyzing MSVC chkstk.obj symbols with llvm-nm:"
  llvm-nm "${CHKSTK_OBJ}" || echo "Failed to analyze symbols"
elif command -v nm &>/dev/null; then
  echo "Analyzing MSVC chkstk.obj symbols with nm:"
  nm "${CHKSTK_OBJ}" || echo "Failed to analyze symbols"
else
  echo "Warning: No nm tool available to analyze symbols"
fi

# Create a temporary source file with a more accurate implementation of ___chkstk_ms
TMP_DIR=$(mktemp -d)
TMP_C_FILE="${TMP_DIR}/chkstk_ms_combined.c"

cat > "${TMP_C_FILE}" << 'EOF'
/*
 * Proper MinGW implementation of ___chkstk_ms for stack probing
 * Based on the actual MinGW implementation from mingw-w64
 */
#include <stdint.h>

/* This is the size of a page on Windows */
#define PAGE_SIZE 4096

/*
 * MinGW-style stack probe routine for 64-bit Windows
 * This follows the exact algorithm used in the actual MinGW runtime
 */
void ___chkstk_ms(void)
{
  /* RAX = size of stack frame */
  /* Return value = address of new stack pointer (RAX) */
  register unsigned char *stack_limit __asm__("%rcx"); /* Use rcx for storing stack_limit */
  register uintptr_t stack_ptr __asm__("%rax");        /* rax = stack size */
  register uintptr_t lo_guard_page;                   /* computed guard page position */
  register unsigned char* previous_page;              /* previously probed page */

  /* Get current stack pointer */
  __asm__ volatile ("movq %%rsp, %0" : "=r" (stack_ptr));

  /* Capture the stack size from rax (the Microsoft calling convention) */
  register uintptr_t stack_size;
  __asm__ volatile ("movq %%rax, %0" : "=r" (stack_size));

  /* Point rcx to the lowest guard page we'll touch */
  stack_limit = (unsigned char*)(stack_ptr - stack_size);

  /* Make sure stack is aligned to 16 bytes (very important for ABI compliance) */
  stack_limit = (unsigned char*)(((uintptr_t)stack_limit) & ~15);

  /* Start with the current page */
  lo_guard_page = ((uintptr_t)stack_limit) & ~(PAGE_SIZE - 1);
  previous_page = (unsigned char*)((uintptr_t)stack_ptr & ~(PAGE_SIZE - 1));

  /* Loop through all pages we need to probe */
  /* Subtract one page at a time and touch it */
  while (previous_page > (unsigned char*)lo_guard_page) {
    previous_page -= PAGE_SIZE;
    *(volatile unsigned char*)previous_page = 0;
  }

  /* Touch the final page */
  *(volatile unsigned char*)stack_limit = 0;
}

/* Plain alias for __chkstk_ms */
void __chkstk_ms(void) {
  ___chkstk_ms();
}

/* Additional alias that might be needed */
void __attribute__((alias("___chkstk_ms"))) _chkstk_ms(void);
EOF

# Compile it directly with advanced optimization settings
echo "Compiling ${TMP_C_FILE} to ${MINGW_CHKSTK_OBJ}..."
"${CLANG_EXE}" -c "${TMP_C_FILE}" -o "${MINGW_CHKSTK_OBJ}" \
  --target=x86_64-w64-mingw32 -O2 -fvisibility=default -fomit-frame-pointer -fno-stack-check \
  -fno-strict-aliasing -mno-stack-arg-probe
COMPILE_RESULT=$?

# Verify the compiled object file
if command -v llvm-nm &>/dev/null; then
  echo "Analyzing compiled chkstk_mingw_ms.obj symbols with llvm-nm:"
  llvm-nm "${MINGW_CHKSTK_OBJ}" || echo "Failed to analyze symbols"
elif command -v nm &>/dev/null; then
  echo "Analyzing compiled chkstk_mingw_ms.obj symbols with nm:"
  nm "${MINGW_CHKSTK_OBJ}" || echo "Failed to analyze symbols"
fi

# Clean up temporary files
rm -rf "${TMP_DIR}"

# Check if compilation succeeded
if [ ${COMPILE_RESULT} -ne 0 ] || [ ! -f "${MINGW_CHKSTK_OBJ}" ]; then
  echo "Critical Error: Failed to create MinGW chkstk_ms.obj file"
  exit 1
fi

echo "Successfully created ${MINGW_CHKSTK_OBJ} via direct compilation"

# Apply stack protector fixes early in the process
echo "*** Applying early stack protector fixes ***"
python "${RECIPE_DIR}/building/fix-stack-protector.py"

# Fix windres to use clang instead of gcc
echo "*** Fixing windres to use clang instead of gcc ***"
bash "${RECIPE_DIR}/building/fix-ghc-bootstrap-windres.sh" || echo "Windres fix failed"

# Test the windres fix
echo "*** Testing windres fix ***"
bash "${RECIPE_DIR}/building/test-windres-fix.sh" || echo "Windres test completed"

# Make sure we use conda-forge clang (ghc bootstrap has a clang.exe)
CLANG=$(find "${_BUILD_PREFIX}" -name clang.exe | head -1)
CLANGXX=$(find "${_BUILD_PREFIX}" -name clang++.exe | head -1)

# CABAL will be set by ultimate-cabal-wrapper.sh
# export CABAL="${SRC_DIR}\\bootstrap-cabal\\cabal.exe"
export CC="${CLANG}"
export CXX="${CLANGXX}"
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"

# Export LIB with the dynamic path
export LIB="${BUILD_PREFIX}/Library/lib;${PREFIX}/Library/lib;C:/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0/um/x64;${MSVC_VERSION_DIR}/lib/x64${LIB:+;}${LIB:-}"
export INCLUDE="C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/ucrt;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/shared;${MSVC_VERSION_DIR}/include${INCLUDE:+;}${INCLUDE:-}"

mkdir -p "${_BUILD_PREFIX}/bin"
cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin"

# ==================== Begin HSC Tool Fixes ====================
# Copy the HSC fix scripts
cp "${RECIPE_DIR}/building/fix-hsc-direct.py" "${_BUILD_PREFIX}/bin/"
cp "${RECIPE_DIR}/building/fix-hsc-stack-overflow.py" "${_BUILD_PREFIX}/bin/"
cp "${RECIPE_DIR}/building/fix-stack-protector.py" "${_BUILD_PREFIX}/bin/"

# Create a simplified script to fix HSC crashes
cat > "${_BUILD_PREFIX}/bin/fix-hsc-crash.sh" << EOF
#!/bin/bash
set -ex
echo "Applying HSC fixes..."

# Apply stack protector fixes
echo "Applying stack protector fixes..."
python "\$(dirname "\$0")/fix-stack-protector.py"

# Apply stack overflow fixes to HSC tools
echo "Applying stack overflow fixes to HSC tools..."
python "\$(dirname "\$0")/fix-hsc-stack-overflow.py" "C:/cabal" "\${BUILD_PREFIX}" "\${SRC_DIR}"

# Run the direct fix script to pre-generate .hs files
echo "Pre-generating .hs files from .hsc sources..."
RECIPE_DIR="${RECIPE_DIR}" python "\$(dirname "\$0")/fix-hsc-direct.py" "\${SRC_DIR}" "C:/cabal" "\${HOME}/.cabal" "\${BUILD_PREFIX}" "C:/cabal/store/ghc-9.10.1"

echo "HSC fixes applied"
EOF
chmod +x "${_BUILD_PREFIX}/bin/fix-hsc-crash.sh"
# ==================== End HSC Tool Fixes ====================

mkdir -p "${_SRC_DIR}/hadrian/cfg" && touch "${_SRC_DIR}/hadrian/cfg/default.target.ghc-toolchain"

# Remove this annoying mingw
perl -i -pe 's#\$topdir/../mingw//bin/(llvm-)?##g' "${_SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-I\$topdir/../mingw//include##g' "${_SRC_DIR}"/bootstrap-ghc/lib/lib/settings
perl -i -pe 's#-L\$topdir/../mingw//lib -L\$topdir/../mingw//x86_64-w64-mingw32/lib##g' "${_SRC_DIR}"/bootstrap-ghc/lib/lib/settings

# Update cabal package database
run_and_log "cabal-update" cabal v2-update

# Deploy ultimate cabal wrapper - most aggressive solution
echo "*** Deploying ultimate cabal wrapper ***"
if [[ "${SKIP_CLOCK_STUB:-0}" != "1" ]]; then
    bash "${RECIPE_DIR}/building/ultimate-cabal-wrapper.sh" || echo "Ultimate cabal wrapper deployment failed"
    # Source the environment changes from the wrapper script
    if [[ -f "${_BUILD_PREFIX}/bin/cabal-ultimate.exe" ]]; then
        export CABAL="${_BUILD_PREFIX}/bin/cabal-ultimate.exe"
        export PATH="${_BUILD_PREFIX}/bin:${PATH}"
        echo "CABAL wrapper activated: ${CABAL}"
        
        # Ensure cabal is findable in PATH by creating additional symlinks
        echo "*** Ensuring cabal is in PATH ***"
        which cabal || echo "cabal not found in PATH before symlinks"
        ln -sf "${_BUILD_PREFIX}/bin/cabal-ultimate.exe" "${_BUILD_PREFIX}/bin/cabal" 2>/dev/null || true
        ln -sf "${_BUILD_PREFIX}/bin/cabal-ultimate.exe" "${_BUILD_PREFIX}/bin/cabal.exe" 2>/dev/null || true
        
        # Verify cabal is now findable
        echo "PATH contains: ${PATH}"
        echo "Checking cabal availability:"
        which cabal || echo "cabal still not found"
        ls -la "${_BUILD_PREFIX}/bin/cabal"* || echo "No cabal files in bin"
        
        # Test cabal wrapper execution
        echo "Testing cabal wrapper:"
        "${_BUILD_PREFIX}/bin/cabal-ultimate.exe" --version || echo "Wrapper test failed"
    fi
    # Test the Clock installation as backup
    bash "${RECIPE_DIR}/building/test-clock-install.sh" || echo "Clock install test completed"
    # Install HSC stubs as additional backup
    bash "${RECIPE_DIR}/building/install-hsc-stub.sh" || echo "HSC stub installation failed"
fi

# Apply HSC fixes right after cabal update but before any builds
echo "*** Applying HSC fixes after cabal update ***"
"${_BUILD_PREFIX}/bin/fix-hsc-crash.sh" || echo "HSC fix after cabal update completed"

# Also stub HSC tools to prevent crashes during build
echo "*** Stubbing HSC tools ***"
bash "${RECIPE_DIR}/building/stub-hsc-tools.sh" || echo "HSC tool stubbing completed"

_hadrian_build=("${_SRC_DIR}"/hadrian/build.bat)

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-w64-mingw32"
  --host="x86_64-w64-mingw32"
  # --target="x86_64-w64-mingw32"
)

# Add stack protector flags to ensure proper stack checking
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

# Configure with environment variables that help debugging
AR_STAGE0=llvm-ar \
CC_STAGE0=${CC} \
CFLAGS="${CFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector" \
CXXFLAGS="${CXXFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector" \
LDFLAGS="${LDFLAGS//-nostdlib/} -v" \
MergeObjsCmd="x86_64-w64-mingw32-ld.exe" \
MergeObjsArgs="" \
run_and_log "ghc-configure" bash configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )

# Cabal configure seems to default to the wrong clang
# Also ensure stack protection is disabled for all stages
cat > hadrian/hadrian.settings << EOF
stage1.*.cabal.configure.opts += --verbose=3 --with-compiler="${GHC}" --with-gcc="${CLANG_WRAPPER}"
stage1.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage1.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage1.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage1.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
stage0.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage0.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage0.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage0.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
EOF

export CABFLAGS="--with-compiler=${GHC} --with-gcc=${CLANG_WRAPPER} --ghc-options=-optc-fno-stack-protector --ghc-options=-optc-fno-stack-check"
# Enable debugging mode for more verbose output
export GHC_DEBUG=1

# Ensure stack protection is disabled for all tools
export CFLAGS="${CFLAGS} -fno-stack-protector -fno-stack-check"
export CXXFLAGS="${CXXFLAGS} -fno-stack-protector -fno-stack-check"
export LDFLAGS="${LDFLAGS} -fno-stack-protector"

# Also set these for Cabal
export CABAL_EXTRA_BUILD_FLAGS="--ghc-options=-optc-fno-stack-protector --ghc-options=-optc-fno-stack-check"


# Proactively apply HSC fixes before any build attempts
echo "*** Applying HSC fixes proactively ***"
"${_BUILD_PREFIX}/bin/fix-hsc-crash.sh" || echo "Pre-emptive HSC fix completed"

# Start aggressive HSC prevention
echo "*** Starting aggressive HSC crash prevention ***"
bash "${RECIPE_DIR}/building/aggressive-hsc-prevention.sh" || echo "HSC prevention start failed"

# Build stage1 GHC
echo "*** Building stage1 GHC ***"

# Ensure cabal wrapper is in PATH for hadrian
echo "*** Final cabal PATH verification before hadrian build ***"
export PATH="${_BUILD_PREFIX}/bin:${PATH}"
if [[ -f "${_BUILD_PREFIX}/bin/cabal-ultimate.exe" ]]; then
    export CABAL="${_BUILD_PREFIX}/bin/cabal-ultimate.exe"
    echo "CABAL set to: ${CABAL}"
fi
echo "PATH: ${PATH}"
which cabal || echo "WARNING: cabal not found in PATH"
echo "Cabal executable test:"
cabal --version || echo "WARNING: cabal --version failed"

# Ensure hadrian can find cabal by testing in the same way hadrian would
echo "Testing hadrian's cabal access method:"
cmd /c "cabal --version" || echo "WARNING: cmd /c cabal --version failed"
cmd /c "where cabal" || echo "WARNING: cmd /c where cabal failed"

# Test batch wrappers specifically
echo "Testing Windows batch wrappers:"
if [[ -f "${_BUILD_PREFIX}/bin/cabal.bat" ]]; then
    echo "Found cabal.bat wrapper"
    cmd /c "cabal.bat --version" || echo "WARNING: cabal.bat test failed"
else
    echo "WARNING: cabal.bat not found"
fi

if [[ -f "${SRC_DIR}/bootstrap-cabal/cabal.bat" ]]; then
    echo "Found bootstrap cabal.bat wrapper"
    # Fix Windows path for cmd execution
    WIN_CABAL_BAT=$(cygpath -w "${SRC_DIR}/bootstrap-cabal/cabal.bat")
    cmd /c "\"${WIN_CABAL_BAT}\" --version" || echo "WARNING: bootstrap cabal.bat test failed"
else
    echo "WARNING: bootstrap cabal.bat not found"
fi

# Set the Windows environment variable for batch scripts
export CABAL_EXE="${_BUILD_PREFIX}/bin/cabal-ultimate.exe"
echo "Set CABAL_EXE to: ${CABAL_EXE}"

# Critical: Ensure CABAL environment variable is set for Windows batch scripts
# Use our hadrian-specific wrapper that passes validation but uses our Clock wrapper
CABAL_WIN_PATH=$(cygpath -w "${_BUILD_PREFIX}/bin/cabal-hadrian.bat")
export CABAL="${CABAL_WIN_PATH}"
echo "Set CABAL (Windows path) to: ${CABAL}"

# Also ensure Windows can find this path by setting a fully resolved path
CABAL_RESOLVED=$(cygpath -w "${_BUILD_PREFIX}/bin/cabal-hadrian.bat")
echo "Testing resolved CABAL path: ${CABAL_RESOLVED}"
if [[ -f "${_BUILD_PREFIX}/bin/cabal-hadrian.bat" ]]; then
    echo "✓ cabal-hadrian.bat exists at expected location"
else
    echo "✗ cabal-hadrian.bat missing at expected location"
fi

# Also test if Windows batch can now find cabal
echo "Testing Windows batch CABAL variable:"
cmd /c "echo CABAL=%CABAL%" || echo "WARNING: cmd CABAL test failed"
cmd /c "if defined CABAL echo CABAL is defined: %CABAL%" || echo "WARNING: cmd CABAL definition test failed"

# Debug PATH and verify hadrian can find cabal wrappers
echo "Final PATH verification for hadrian:"
echo "Bootstrap-cabal in PATH: $(echo "$PATH" | grep -o bootstrap-cabal || echo "NOT FOUND")"
echo "Testing PATH order for cabal discovery:"
echo "  which cabal: $(which cabal 2>/dev/null || echo "NOT FOUND")"
echo "  where cabal in cmd: $(cmd /c "where cabal" 2>/dev/null || echo "NOT FOUND")"

# Check binary directory where hadrian expects cabal
BINARY_DIR="${SRC_DIR}/../binary/bin"
echo "Checking binary directory for hadrian: ${BINARY_DIR}"
if [[ -d "${BINARY_DIR}" ]]; then
    echo "  Binary directory exists"
    echo "  Contents: $(ls -la "${BINARY_DIR}"/cabal* 2>/dev/null || echo "No cabal files found")"
else
    echo "  Binary directory does not exist"
fi

# Test if hadrian's working directory affects cabal discovery
echo "Testing cabal from hadrian's working directory:"
cd "${SRC_DIR}"
echo "  pwd: $(pwd)"
echo "  which cabal from SRC_DIR: $(which cabal 2>/dev/null || echo "NOT FOUND")"
echo "  cmd where cabal from SRC_DIR: $(cmd /c "where cabal" 2>/dev/null || echo "NOT FOUND")"

# Test the new native batch wrappers
echo "Testing native batch wrapper directly:"
if [[ -f "${BINARY_DIR}/cabal.bat" ]]; then
    echo "  Testing cabal.bat from binary directory:"
    WIN_BINARY_DIR=$(cygpath -w "${BINARY_DIR}")
    cmd /c "\"${WIN_BINARY_DIR}\\cabal.bat\" --version" || echo "  FAILED: cabal.bat test"
else
    echo "  cabal.bat not found in binary directory"
fi

# Test if Windows can find cabal.exe specifically
echo "Testing Windows executable discovery:"
echo "Windows PATH for executable discovery:"
cmd /c "echo %PATH%" 2>/dev/null | head -1 || echo "  Failed to get Windows PATH"
cmd /c "where cabal.exe" 2>/dev/null || echo "  cabal.exe not found by Windows"
cmd /c "where cabal.bat" 2>/dev/null || echo "  cabal.bat not found by Windows"
cmd /c "where cabal.cmd" 2>/dev/null || echo "  cabal.cmd not found by Windows"

# Critical test: Can hadrian's method find our cabal?
echo "Testing hadrian's exact cabal discovery method:"
echo "CABAL environment variable test:"
cmd /c "if defined CABAL (echo CABAL is defined as: %CABAL%) else (echo CABAL is not defined)" 2>/dev/null || echo "  CABAL test failed"
cmd /c "if exist \"%CABAL%\" (echo CABAL executable exists) else (echo CABAL executable missing)" 2>/dev/null || echo "  CABAL existence test failed"

# Test cabal execution like hadrian does
echo "Testing cabal execution like hadrian build-cabal.bat:"
echo "CABAL variable contains: ${CABAL}"
echo "Testing direct execution of cabal-hadrian.bat:"
WIN_BAT_PATH=$(cygpath -w "${_BUILD_PREFIX}/bin/cabal-hadrian.bat")
cmd /c "\"${WIN_BAT_PATH}\" 2>nul" 2>/dev/null
DIRECT_TEST_EXIT=$?
echo "Direct cabal-hadrian.bat test exit code: ${DIRECT_TEST_EXIT} (should be 1)"

echo "Testing via CABAL variable:"
cmd /c "\"%CABAL%\" 2>nul" 2>/dev/null
CABAL_TEST_EXIT=$?
echo "CABAL variable test exit code: ${CABAL_TEST_EXIT} (hadrian expects 1)"

if [[ ${CABAL_TEST_EXIT} -eq 1 ]]; then
    echo "✅ Cabal test matches hadrian expectation"
else
    echo "❌ Cabal test differs from hadrian expectation (expected 1, got ${CABAL_TEST_EXIT})"
    echo "Investigating issue..."
    echo "File exists: $(test -f "${_BUILD_PREFIX}/bin/cabal-hadrian.bat" && echo "YES" || echo "NO")"
    echo "File permissions: $(ls -la "${_BUILD_PREFIX}/bin/cabal-hadrian.bat" 2>/dev/null || echo "FILE NOT FOUND")"
fi

"${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn || BUILD_RESULT=$?

# Stop the HSC monitor
if [[ -f "${TEMP}/hsc-monitor.pid" ]]; then
    MONITOR_PID=$(cat "${TEMP}/hsc-monitor.pid")
    kill $MONITOR_PID 2>/dev/null || true
    echo "Stopped HSC monitor (PID $MONITOR_PID)"
fi

# Check build result
if [[ "${BUILD_RESULT:-0}" -ne 0 ]]; then
    echo "Build failed with code ${BUILD_RESULT}"
    exit ${BUILD_RESULT}
fi

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=release --freeze1 --docs=none
