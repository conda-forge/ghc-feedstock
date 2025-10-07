#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Create iconv compatibility wrapper FIRST, before any commands run
# This must happen before cabal, ghc-bootstrap, or any other tool executes
cat > /tmp/iconv_compat.c << 'EOFC'
#include <stddef.h>
typedef void* iconv_t;
extern iconv_t libiconv_open(const char*, const char*);
extern size_t libiconv(iconv_t, char**, size_t*, char**, size_t*);
extern int libiconv_close(iconv_t);
iconv_t iconv_open(const char* a, const char* b) { return libiconv_open(a, b); }
size_t iconv(iconv_t a, char** b, size_t* c, char** d, size_t* e) { return libiconv(a,b,c,d,e); }
int iconv_close(iconv_t a) { return libiconv_close(a); }
EOFC

# Build both static and dynamic versions with explicit SDK version for compatibility
# This ensures the object file matches the SDK version used during GHC linking
${CC} -c /tmp/iconv_compat.c -o /tmp/iconv_compat.o -mmacosx-version-min=10.13

# Debug: Check what ar AND ld we're using
echo "=== Toolchain Debug Info ==="
echo "AR=${AR}"
which "${AR}" || echo "AR not in PATH"
"${AR}" --version || "${AR}" -V || echo "Cannot get ar version"
echo ""
echo "LD=${LD}"
which "${LD}" || echo "LD not in PATH"
"${LD}" -v || "${LD}" --version || echo "Cannot get ld version"
echo ""
echo "Testing ar format compatibility:"
echo "Creating test archive with ${AR}..."
echo "int test_func() { return 42; }" > /tmp/test.c
${CC} -c /tmp/test.c -o /tmp/test.o
${AR} rcs /tmp/test.a /tmp/test.o
file /tmp/test.a
echo "Trying to link with ${LD}..."
${CC} -o /tmp/test_binary /tmp/test.o 2>&1 | head -20
echo "=============================="

# Create archive with explicit format for LLVM ar compatibility
${AR} rcs /tmp/libiconv_compat.a /tmp/iconv_compat.o

# Verify the archive and object file metadata
echo "=== Archive verification ==="
file /tmp/libiconv_compat.a
${AR} -t /tmp/libiconv_compat.a
echo ""
echo "Object file metadata:"
file /tmp/iconv_compat.o
otool -l /tmp/iconv_compat.o | grep -A 3 "LC_VERSION_MIN\|LC_BUILD_VERSION" || echo "No version info found"
echo ""
echo "Checking if ld can read the archive:"
${AR} -x /tmp/libiconv_compat.a
file iconv_compat.o
echo "============================"

# Create dylib for runtime preloading with absolute paths
${CC} -dynamiclib -o /tmp/libiconv_compat.dylib /tmp/iconv_compat.c \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -install_name "/tmp/libiconv_compat.dylib"

# Preload the dylib for ALL commands from now on
export DYLD_INSERT_LIBRARIES="/tmp/libiconv_compat.dylib"
export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"

# This is needed as in seems to interfere with configure scripts
unset build_alias
unset host_alias

# CRITICAL: Configure ghc-bootstrap to use conda-forge ar/ranlib BEFORE cabal builds anything
# This ensures all Haskell libraries in cabal store are built with conda-forge toolchain
settings_file=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -n 1)

# Debug: Show ghc-bootstrap's ORIGINAL ar/ranlib settings before modification
echo "=== ghc-bootstrap ORIGINAL settings ==="
grep -E "(ar command|ar flags|ranlib command)" "${settings_file}" || true
echo "========================================"

# Force load the compat library to ensure symbols are exported in executables
# Disable LTO as it conflicts with GNU ar format archives
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv -fno-lto#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -force_load /tmp/libiconv_compat.a -liconv#' "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# Debug: Show UPDATED settings after conda-forge toolchain modification
echo "=== ghc-bootstrap AFTER conda-forge ar/ranlib ==="
grep -E "(ar command|ar flags|ranlib command)" "${settings_file}" || true
echo "=================================================="

cat "${settings_file}"

# Clear cabal store to force rebuild with conda-forge toolchain
# This ensures no BSD ar format archives from previous builds are used
echo "=== Clearing cabal store for clean rebuild ==="
rm -rf ~/.local/state/cabal/store/ghc-9.6.7/* || true
echo "================================================"

# Update cabal package database (now using conda-forge toolchain)
run_and_log "cabal-update" cabal v2-update --allow-newer --minimize-conflict-set

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  # default is auto: --disable-numa
  # --disable-ld-override
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

export ac_cv_path_ac_pt_CC=""
export ac_cv_path_ac_pt_CXX=""
export ac_cv_prog_AR="${AR}"
export ac_cv_prog_CC="${CC}"
export ac_cv_prog_CXX="${CXX}"
export ac_cv_prog_LD="${LD}"
export ac_cv_prog_RANLIB="${RANLIB}"
export ac_cv_path_AR="${AR}"
export ac_cv_path_CC="${CC}"
export ac_cv_path_CXX="${CXX}"
export ac_cv_path_LD="${LD}"
export ac_cv_path_RANLIB="${RANLIB}"
export DEVELOPER_DIR=""

# Verify the iconv compatibility libraries were created
echo "=== Verifying iconv compatibility symbols ==="
echo "Static library:"
nm /tmp/libiconv_compat.a | grep iconv || true
echo "Dynamic library:"
nm -gU /tmp/libiconv_compat.dylib | grep iconv || true
echo "Dylib dependencies:"
otool -L /tmp/libiconv_compat.dylib || true
echo "DYLD_INSERT_LIBRARIES=${DYLD_INSERT_LIBRARIES}"
echo "=============================================="

# Check what ar tools are available
echo "=== Available ar tools ==="
ls -la "${BUILD_PREFIX}"/bin/*ar* 2>&1 | grep -E "(llvm-ar|ranlib|ar)" || true
echo "=========================="

# Test llvm-ar compatibility with ld
echo "=== Testing llvm-ar + ld compatibility ==="
echo "int test_func() { return 42; }" > /tmp/llvm_test.c
${CC} -c /tmp/llvm_test.c -o /tmp/llvm_test.o -mmacosx-version-min=10.13
echo "Creating archive with llvm-ar..."
"${BUILD_PREFIX}"/bin/llvm-ar rcs /tmp/llvm_test.a /tmp/llvm_test.o
file /tmp/llvm_test.a
echo "Linking with ld..."
${CC} -o /tmp/llvm_test_binary /tmp/llvm_test.o -mmacosx-version-min=10.13 2>&1 | head -10 || true
echo "Exit code: $?"
echo "============================================"

# Install ld wrapper to surgically remove MacOSX15.5.sdk rpath contamination
mv "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld.real
cp "${RECIPE_DIR}"/building/ld-wrapper.sh "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld
chmod +x "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld

# Create symlinks for conda-forge toolchain (ghc-bootstrap is already configured above)
ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-as "${BUILD_PREFIX}"/bin/as
ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld "${BUILD_PREFIX}"/bin/ld
ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ranlib "${BUILD_PREFIX}"/bin/ranlib

run_and_log "configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.host.target "${CONDA_TOOLCHAIN_BUILD}"
set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.target "${CONDA_TOOLCHAIN_BUILD}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# GHC selection of tools seems to fail to use conda-forge toolchain tools
rm -f /Users/runner/miniforge3/bin/{as,ranlib,ld}

"${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv -fno-lto#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#' "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release

perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv -fno-lto#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\$ENV{PREFIX}/lib -L\\\$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#" "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

"${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quickest

export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
settings_file="${SRC_DIR}"/_build/stage1/lib/settings
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv -fno-lto#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\$ENV{PREFIX}/lib -v -L\\\$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#" "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none --progress-info=none

settings_file=$(find "${PREFIX}" -name settings | head -n 1)
perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -v -fno-lto#" "${settings_file}"
perl -i -pe "s#(C\+\+ compiler flags\", \")([^\"]*)#\1\2 -v -fno-lto#" "${settings_file}"
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv -fno-lto#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\\\$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#" "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

cat "${settings_file}"

# Add debugging to verify archive format after build completes
echo "=== Post-build archive format check ==="
echo "Checking a cabal-built archive format:"
find /Users/runner/.local/state/cabal/store/ghc-9.6.7/ -name "*.a" -type f | head -3 | while read f; do
  echo "File: $f"
  file "$f"
  head -c 20 "$f" | od -An -tx1
done
echo "=========================================="
