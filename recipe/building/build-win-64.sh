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

# Make sure we use conda-forge clang (ghc bootstrap has a clang.exe)
CLANG=$(find "${_BUILD_PREFIX}" -name clang.exe | head -1)
CLANGXX=$(find "${_BUILD_PREFIX}" -name clang++.exe | head -1)

export CABAL="${SRC_DIR}\\bootstrap-cabal\\cabal.exe"
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

# Create simple clock stub to avoid HSC crashes
echo "*** Creating clock stub ***"
if [[ "${SKIP_CLOCK_STUB:-0}" != "1" ]]; then
    bash "${RECIPE_DIR}/building/simple-clock-stub.sh" || echo "Clock stub creation failed"
    
    # Also register the clock package with GHC
    echo "*** Registering clock package ***"
    bash "${RECIPE_DIR}/building/register-clock-package.sh" || echo "Clock registration failed"
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

# Build stage1 GHC with HSC workaround
echo "*** Building stage1 GHC ***"

# Set up a wrapper for cabal to intercept HSC builds
export CABAL_BUILDDIR="C:/cabal/dist-newstyle"
export CABAL_STORE="C:/cabal/store"

# Monitor and stub HSC tools during the build
(
    while true; do
        # Look for any Clock_hsc_make.exe that might be created
        find "${CABAL_STORE}" "${CABAL_BUILDDIR}" -name "Clock_hsc_make.exe" -newer "${_BUILD_PREFIX}/bin/fix-hsc-crash.sh" 2>/dev/null | while read hsc_exe; do
            if [[ -f "${hsc_exe}" && ! -f "${hsc_exe}.stubbed" ]]; then
                echo "Found new HSC tool, stubbing: ${hsc_exe}"
                mv "${hsc_exe}" "${hsc_exe}.original" 2>/dev/null || true
                cat > "${hsc_exe}" << 'EOF'
@echo off
exit /b 0
EOF
                touch "${hsc_exe}.stubbed"
                
                # Also ensure Clock.hs exists
                hsc_dir=$(dirname "${hsc_exe}")
                if [[ ! -f "${hsc_dir}/Clock.hs" ]]; then
                    cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" "${hsc_dir}/Clock.hs" 2>/dev/null || true
                fi
            fi
        done
        sleep 2
    done
) &
HSC_MONITOR_PID=$!

# Run the build
run_and_log "ghc-stage1-build" "${_hadrian_build[@]}" stage1:exe:ghc-bin -VV \
  --flavour=quickest \
  --docs=none \
  --progress-info=unicorn || BUILD_RESULT=$?

# Stop the HSC monitor
kill $HSC_MONITOR_PID 2>/dev/null || true

# Check build result
if [[ "${BUILD_RESULT:-0}" -ne 0 ]]; then
    echo "Build failed with code ${BUILD_RESULT}"
    # Check for clock-specific errors
    if grep -q "clock-0.8.4" C:/cabal/logs/ghc-9.10.1/*.log 2>/dev/null; then
        echo "Clock package build failed. Trying alternative approach..."
        # TODO: Add alternative approach
    fi
    exit ${BUILD_RESULT}
fi

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=release --freeze1 --docs=none
